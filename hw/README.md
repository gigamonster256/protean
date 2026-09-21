# Hardcaml design source

OCaml (Hardcaml v0.17.1) is the source of truth. Verilog is generated at
build time into the gitignored `gen/` directory.

Layout:

- `../dune-project` — dune workspace root (at the repo root so `dune`
  commands run from the top level). Generates `../protean.opam`.
- `lib/top.ml` — `I` / `O` interfaces with the exact Tiny Tapeout port names
  plus `create_fn`. `Circuit.With_interface` labels the Verilog ports from
  these, so the output plugs straight into the TT flow.
- `lib/top_test.ml` — cyclesim expect-tests (`dune runtest`, no Verilog needed).
- `bin/gen.ml` — prints the top module as Verilog on stdout.

Local workflow (inside `nix develop`):

```sh
dune runtest                              # fast OCaml simulation
dune exec ./hw/bin/gen.exe > gen/project.v # regenerate Verilog
cp gen/project.v src/project.v            # for the TT harden flow (see README)
```

## OCaml dependencies (opam-nix)

There is no `hardcaml` package in nixpkgs, so OCaml deps come from opam and are
built by opam-nix. The source of truth is `../dune-project` (and the
`../protean.opam` it generates via `dune build`). opam-nix resolves the package
against the opam-repository pinned in `flake.lock` at build time, so there is no
committed lock file to keep in sync.

To bump a dependency: edit `../dune-project`, run `dune build` (regenerates
`protean.opam`), and commit both files. Direct deps are pinned with `=` in
`dune-project` so their versions are exact; only transitive picks are left to
the solver.
