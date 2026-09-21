{
  opam-nix,
  stdenv,
  project ? ../.,
}:
# The Hardcaml/OCaml toolchain. opam-nix resolves the `protean` package (from
# dune-project/opam) against the opam-repository pinned in flake.lock at eval
# time - the idiomatic OCaml flow, no committed lock file. `with-test` pulls in
# test deps and runs `dune runtest` as part of the build.
(opam-nix.lib.${stdenv.hostPlatform.system}.buildDuneProject {
  resolveArgs.with-test = true;
} "protean" project { }).protean
