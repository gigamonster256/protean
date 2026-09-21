{
  pkgs,
  pythonEnv,
  ttSupportTools,
  ihpOpenPdk,
  ihpOpenPdkRev,
}:
let
  inherit (pkgs) lib;

  # A writable-patched copy of the IHP open PDK. The nixpkgs/librelane snapshot
  # ships Magic 8.3.623 while the cmos5l techfiles declare 8.3.657, so relax
  # that gate; also stamp the PDK source so tt_tool records a real version.
  patchedPdk =
    pkgs.runCommand "ihp-open-pdk-patched"
      {
        nativeBuildInputs = [ pkgs.ripgrep ];
      }
      ''
        cp -R ${ihpOpenPdk}/. $out/
        chmod -R u+w $out
        echo "IHP-Open-PDK ${ihpOpenPdkRev}" > $out/ihp-sg13cmos5l/SOURCES
        for techfile in $(rg -l '8\.3\.657' $out/ihp-sg13cmos5l/libs.tech/magic); do
          sed -i 's/8\.3\.657/8.3.623/g' "$techfile"
        done
      '';

  # Shared shell fragments reused by `nix build` (package.nix) and `nix
  # develop` (shell.nix) so both harden against the identical environment.

  # Copy the patched PDK into a writable directory (the function's argument).
  makePdkWritable = dir: ''
    mkdir -p "${dir}"
    cp -R ${patchedPdk}/. "${dir}/"
    chmod -R u+w "${dir}"
  '';

  # tt_tool.py calls `yowasp-yosys` (a wasm binary in the pip world). We run
  # LibreLane natively, so alias the real yosys to that name in the dir given.
  makeYowasp = dir: ''
    mkdir -p "${dir}"
    ln -sf ${pkgs.yosys}/bin/yosys "${dir}/yowasp-yosys"
  '';

  # gdstk is only needed by tt_tool's optional SVG/PNG rendering commands; the
  # hardening and test path does not use it. This nixpkgs revision does not
  # package gdstk, so avoid importing that optional module eagerly.
  patchRenderUtils = ''
    sed -i "s/^import gdstk.*/gdstk = None/" tt/render_utils.py
  '';

  # Environment every tt_tool.py invocation needs. Call after the writable PDK
  # has been materialized (so $PDK_ROOT points at it).
  commonExports = ''
    export PDK="''${PDK:-ihp-sg13cmos5l}"
    export PDK_ROOT="''${PDK_ROOT:-$PWD/pdk}"
    export TT_TOOLS_REF="''${TT_TOOLS_REF:-ihp-sg13cmos5l}"

    if [ "$PDK" = "ihp-sg13g2" ] || [ "$PDK" = "ihp-sg13cmos5l" ]; then
      export TT_ARGS="--ihp"
    elif [ "$PDK" = "gf180mcuD" ]; then
      export TT_ARGS="--gf"
    else
      export TT_ARGS=""
    fi

    # OpenROAD's embedded Python does not inherit the regular interpreter's
    # site-packages (its odbpy helpers import click, etc.).
    export PYTHONPATH="$(python -c 'import site; print(site.getsitepackages()[0])'):''${PYTHONPATH:-}"
  '';
in
{
  inherit
    patchedPdk
    makePdkWritable
    makeYowasp
    patchRenderUtils
    commonExports
    ;
}
