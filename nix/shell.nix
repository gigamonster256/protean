{
  pkgs ? import <nixpkgs> { },
  pdkDefault ? "ihp-sg13cmos5l",
  toolsRefDefault ? "ihp-sg13cmos5l",
  ttSupportTools,
  ihpOpenPdk,
  ihpOpenPdkRev,
  infoYaml,
  hardcaml,
  stages,
}:
let
  python = pkgs.callPackage ./python.nix { inherit ttSupportTools; };
  ttenv = pkgs.callPackage ./tt-env.nix {
    pythonEnv = python.pythonEnv;
    inherit ttSupportTools ihpOpenPdk ihpOpenPdkRev;
  };
in
pkgs.mkShell {
  name = "protean";

  # Pull the exact closure of the nix build stages (OCaml/hardcaml, the
  # crafted Python env + librelane, and the EDA tools) so `nix develop` and
  # `nix build` share one environment - no venv/pip, no Docker.
  # `hardcaml` is the opam-nix OCaml dev env (dune + Hardcaml + deps); the
  # stages carry the Python + EDA toolchain.
  inputsFrom = [
    hardcaml
    stages.rtl-test
    stages.gds
  ];

  buildInputs = with pkgs; [
    # --- RTL sim / cocotb tests (mirrors test.yaml) ---
    verible # formatting
    gtkwave # view tb.fst + tb.gtkw
    surfer # alt waveform viewer (see test/README.md)
    gnumake
    git
    curl
    jq # gl_test reads PDK from tt_submission/pdk.json

    # --- native libs the optional SVG/PNG rendering commands need ---
    cairo # dlopened by cairocffi
    libpng
    qhull
    librsvg # rsvg-convert for --create-png
    pngquant # PNG compression for --create-png
  ];

  shellHook = ''
    # Materialize the pinned flake inputs next to the project (CI checks them
    # out as ./tt / ./pdk). Never git-clone or mutate the immutable inputs.
    if [ ! -d tt ]; then
      echo "Copying pinned tt-support-tools@''${TT_TOOLS_REF:-${toolsRefDefault}} into ./tt ..."
      cp -R "${ttSupportTools}" tt
    fi

    # Writable, magic-patched PDK for local --no-docker hardening.
    if [ ! -d pdk/ihp-sg13cmos5l ]; then
      echo "Materializing writable PDK into ./pdk ..."
      ${ttenv.makePdkWritable "pdk"}
    fi

    # info.yaml is generated from info.nix (single source of truth).
    if [ ! -f info.yaml ]; then
      cp ${infoYaml} info.yaml
    fi

    # tt_tool.py imports gdstk eagerly; it is not packaged in this nixpkgs rev.
    if grep -q '^import gdstk' tt/render_utils.py 2>/dev/null; then
      ${ttenv.patchRenderUtils}
    fi

    # tt_tool.py calls `yowasp-yosys`; alias the native yosys in a per-shell bin.
    ${ttenv.makeYowasp "$PWD/.tt-bin"}
    export PATH="$PWD/.tt-bin:$PATH"

    ${ttenv.commonExports}

    # Hardcaml -> Verilog -> src/ (gitignored build output).
    mkdir -p gen src
    dune exec ./hw/bin/gen.exe > gen/project.v
    cp gen/project.v src/project.v

    echo ""
    echo "Tiny Tapeout env ready (no Docker): PDK=$PDK PDK_ROOT=$PDK_ROOT tt=$TT_TOOLS_REF"
    echo ""
    echo "  RTL test:        make -C test clean && make -C test"
    echo "  Regen Verilog:   dune exec ./hw/bin/gen.exe > gen/project.v && cp gen/project.v src/project.v"
    echo "  Harden:          ./tt/tt_tool.py --create-user-config \$TT_ARGS --no-docker && ./tt/tt_tool.py --harden \$TT_ARGS --no-docker"
    echo "  Submission:      ./tt/tt_tool.py --create-tt-submission \$TT_ARGS"
    echo "  GL test:         TOP=\$(./tt/tt_tool.py --print-top-module \$TT_ARGS); cp runs/wokwi/final/nl/\$TOP.nl.v test/gate_level_netlist.v; make -C test clean && GATES=yes make -C test"
    echo "  View GDS:        ./tt/tt_tool.py --open-in-klayout \$TT_ARGS --no-docker"
    echo "  nix equivalents: nix run .#rtl-test | .#harden | .#gl-test | nix build .#gds"
    echo ""
  '';
}
