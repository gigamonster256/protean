{
  lib,
  pkgs,
  stdenv,
  hardcaml,
  ttSupportTools,
  ihpOpenPdk,
  ihpOpenPdkRev,
  infoYaml,
  opensta,
  openroad,
  magic,
  netgen,
  yosys,
  iverilog,
  verilator,
  dune_3,
  gnumake,
  git,
  ripgrep,
}:
let
  python = pkgs.callPackage ./python.nix { inherit ttSupportTools; };
  pythonEnv = python.pythonEnv;

  ttenv = pkgs.callPackage ./tt-env.nix {
    inherit
      pythonEnv
      ttSupportTools
      ihpOpenPdk
      ihpOpenPdkRev
      ;
  };

  # Repository source minus the gitignored build/tool trees. Hardcaml (hw/) is
  # the design source of truth; Verilog and the TT tooling are generated.
  source = lib.cleanSourceWith {
    src = ../.;
    filter =
      path: type:
      let
        relative = lib.removePrefix "${toString ../.}/" (toString path);
      in
      !(
        lib.hasPrefix "tt/" relative
        || relative == "tt"
        || lib.hasPrefix "gen/" relative
        || relative == "gen"
        || relative == "pdk"
        || lib.hasPrefix "pdk/" relative
      );
  };

  # ---- stage 1: Hardcaml -> Verilog -------------------------------------
  verilog = stdenv.mkDerivation {
    pname = "protean-verilog";
    version = "0.1.0";
    src = source;
    nativeBuildInputs = [
      hardcaml
      dune_3
    ];
    dontConfigure = true;
    buildPhase = ''
      runHook preBuild
      dune runtest --force
      mkdir -p gen
      dune exec ./hw/bin/gen.exe > gen/project.v
      runHook postBuild
    '';
    installPhase = ''
      mkdir -p $out/gen $out/src
      cp gen/project.v $out/project.v
      cp gen/project.v $out/gen/project.v
      cp gen/project.v $out/src/project.v
    '';
  };

  # ---- stage 2: cocotb RTL simulation -----------------------------------
  rtl-test = stdenv.mkDerivation {
    pname = "protean-rtl-test";
    version = "0.1.0";
    src = source;
    nativeBuildInputs = [
      pythonEnv
      iverilog
      gnumake
      ripgrep
    ];
    dontConfigure = true;
    buildPhase = ''
      runHook preBuild
      mkdir -p gen
      cp ${verilog}/project.v gen/project.v
      make -C test clean
      make -C test
      test -f test/results.xml
      ! rg -q failure test/results.xml
      runHook postBuild
    '';
    installPhase = ''
      mkdir -p $out
      cp test/results.xml $out/
      if [ -f test/tb.fst ]; then cp test/tb.fst $out/; fi
    '';
  };

  # ---- stage 3: LibreLane hardening -> GDS ------------------------------
  gds = stdenv.mkDerivation {
    pname = "protean-gds";
    version = "0.1.0";
    src = source;
    nativeBuildInputs = [
      pythonEnv
      gnumake
      git
      verilator
      opensta
      openroad
      magic
      netgen
      ripgrep
      yosys
    ];
    dontConfigure = true;
    buildPhase = ''
      runHook preBuild

      mkdir -p gen src
      cp ${verilog}/project.v gen/project.v
      cp ${verilog}/project.v src/project.v

      # tt-support-tools and info.yaml are flake inputs/build products, not
      # source files in the Nix build sandbox.
      mkdir tt
      tar --exclude='./.git' --exclude='./.git/*' -C ${ttSupportTools} -cf - . | tar -C tt -xf -
      chmod -R u+w tt
      # Some tar implementations still preserve the input's Git metadata.
      # It is not needed; tt_tool gets a fresh local repository below.
      if [ -e tt/.git ]; then
        chmod -R u+w tt/.git
        rm -rf tt/.git
      fi
      cp ${infoYaml} info.yaml
      # tt_tool records repository metadata in the LibreLane run. The Nix source
      # is intentionally not a Git checkout, so provide deterministic local
      # repositories for those metadata queries.
      git init -q
      git config user.email build@nixos.invalid
      git config user.name nix-build
      git remote add origin https://github.com/gigamonster256/protean.git
      git add .
      git commit -qm nix-build
      git -C tt init -q
      git -C tt config user.email build@nixos.invalid
      git -C tt config user.name nix-build
      git -C tt remote add origin https://github.com/TinyTapeout/tt-support-tools.git
      git -C tt add .
      git -C tt commit -qm ihp-sg13cmos5l
      # gdstk is only needed by tt_tool's optional SVG/PNG rendering commands;
      # the hardening and test path does not use it. This nixpkgs revision does
      # not package gdstk, so avoid importing that optional module eagerly.
      ${ttenv.patchRenderUtils}
      export HOME=$TMPDIR/home
      export MPLCONFIGDIR=$TMPDIR/matplotlib
      mkdir -p "$HOME" "$MPLCONFIGDIR"

      # Writable, magic-patched PDK (from tt-env.nix) + shared env.
      ${ttenv.makePdkWritable "pdk"}
      ${ttenv.makeYowasp "$TMPDIR/bin"}
      export PATH="$TMPDIR/bin:$PATH"
      ${ttenv.commonExports}

      # LibreLane's IHP flow is explicitly manual-PDK and must run without
      # Docker inside the Nix derivation.
      python tt/tt_tool.py --create-user-config --ihp
      python tt/tt_tool.py --no-docker --ihp --harden

      runHook postBuild
    '';
    installPhase = ''
      mkdir -p $out
      cp -r runs $out/
      cp info.yaml $out/
    '';
  };

  # ---- stage 4: gate-level simulation (needs the hardened netlist) ------
  gl-test = stdenv.mkDerivation {
    pname = "protean-gl-test";
    version = "0.1.0";
    src = source;
    nativeBuildInputs = [
      pythonEnv
      iverilog
      gnumake
      ripgrep
    ];
    dontConfigure = true;
    buildPhase = ''
      runHook preBuild

      mkdir -p gen
      cp ${verilog}/project.v gen/project.v

      # Gate-level sim needs the hardened netlist (from the gds stage) and the
      # PDK standard-cell Verilog models (read-only store path is fine here).
      cp -r ${gds}/runs runs
      export PDK_ROOT=${ttenv.patchedPdk}

      # The IHP action uses the unpowered netlist (nl) for gate-level testing.
      cp runs/wokwi/final/nl/*.nl.v test/gate_level_netlist.v
      make -C test clean
      GATES=yes make -C test
      test -f test/results.xml
      ! rg -q failure test/results.xml

      runHook postBuild
    '';
    installPhase = ''
      mkdir -p $out
      cp test/results.xml $out/gl-results.xml
      cp test/gate_level_netlist.v $out/
    '';
  };

  # ---- aggregate: everything (default build target) ---------------------
  design = pkgs.symlinkJoin {
    name = "protean";
    paths = [
      verilog
      rtl-test
      gds
      gl-test
    ];
  };
in
{
  inherit
    verilog
    rtl-test
    gds
    gl-test
    design
    ;
}
