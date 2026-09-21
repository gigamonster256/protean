{
  pkgs,
  ttSupportTools,
}:
let
  inherit (pkgs) lib;
  python = pkgs.python3;

  # The tt-support-tools pyproject is the single source of truth for the
  # Python dependencies of the TT flow (tt_tool.py, librelane client, etc.).
  pyproject = builtins.fromTOML (builtins.readFile "${ttSupportTools}/pyproject.toml");
  dependencies = pyproject.project.dependencies;

  # Bare package name (strip PEP 508 version specifiers like "numpy<2").
  pkgName = d: lib.head (builtins.match "([A-Za-z0-9_-]+).*" d);

  # Map each pyproject dependency to a nixpkgs Python package. `null` means
  # intentionally unprovided (not packaged in this nixpkgs revision, or only
  # needed for optional flows) - see comments.
  depToPkg = {
    CairoSVG = python.pkgs.cairosvg;
    chevron = python.pkgs.chevron;
    # gdstk: only tt_tool's optional SVG/PNG rendering; not packaged here.
    gdstk = null;
    GitPython = python.pkgs.gitpython;
    klayout = python.pkgs.klayout;
    mistune = python.pkgs.mistune;
    numpy = python.pkgs.numpy;
    # pre-commit: dev-only linting, unused by harden/test flows.
    pre-commit = null;
    pytest = python.pkgs.pytest;
    python-frontmatter = python.pkgs.python-frontmatter;
    PyYAML = python.pkgs.pyyaml;
    requests = python.pkgs.requests;
    # yowasp-yosys: pip-only wasm package; the flow wraps native `yosys`.
    yowasp-yosys = null;
    matplotlib = python.pkgs.matplotlib;
    configupdater = python.pkgs.configupdater;
    # mpremote: microcontroller tooling, unused here.
    mpremote = null;
  };

  # Fail loudly on any unmapped dependency so a future tt-support-tools bump
  # cannot silently drift from this nix environment.
  unknown = lib.filter (d: !(builtins.hasAttr (pkgName d) depToPkg)) dependencies;
  checkedDeps =
    if unknown == [ ] then
      dependencies
    else
      throw "nix/python.nix: unmapped tt-support-tools dependencies: ${lib.concatStringsSep ", " (map pkgName unknown)}";

  # Repo-specific extras (not part of the tt pyproject) required by the design
  # test harness and by OpenROAD's embedded Python.
  pythonEnv = python.withPackages (
    ps:
    [
      ps.librelane
      ps.cloup
      ps.click
      ps.cocotb
    ]
    ++ lib.map (d: depToPkg.${pkgName d}) (lib.filter (d: depToPkg.${pkgName d} != null) checkedDeps)
  );
in
{
  inherit pythonEnv pyproject dependencies;
}
