# Protean — Tiny Tapeout Programmable Protocol Emulator (Hardcaml + Nix)

A [Tiny Tapeout](https://tinytapeout.com) ASIC project whose design is written in
[Hardcaml](https://github.com/janestreet/hardcaml) (OCaml) rather than raw
Verilog. Nix is the single source of truth for the whole flow: it fetches the
OCaml toolchain via [opam-nix](https://github.com/tweag/opam-nix), the Python +
EDA tooling via [librelane](https://github.com/librelane/librelane)/nixpkgs, and
drives Hardcaml → Verilog → RTL sim → LibreLane harden → GDS.

| | |
|---|---|
| GDS | ![gds](https://github.com/gigamonster256/protean/actions/workflows/gds.yaml/badge.svg) |
| test | ![test](https://github.com/gigamonster256/protean/actions/workflows/test.yaml/badge.svg) |
| docs | ![docs](https://github.com/gigamonster256/protean/actions/workflows/docs.yaml/badge.svg) |
| fpga | ![fpga](https://github.com/gigamonster256/protean/actions/workflows/fpga.yaml/badge.svg) |

## Local development with Nix (no Docker)

Everything runs locally with the tools provided by `nix develop` — LibreLane and
the other EDA tools come from nix, so there is no Docker requirement for
hardening.

```sh
nix develop   # one-time: builds the OCaml + Python + EDA closure
```

The shell drops you into an environment with:

- `dune` + Hardcaml (OCaml toolchain, via opam-nix)
- the `tt_tool.py` Python stack (`librelane`, cocotb, klayout, …)
- LibreLane and the EDA tools (`yosys`, `openroad`, `opensta`, `magic`, `netgen`, `iverilog`)
- a writable, magic-patched PDK under `./pdk`
- `info.yaml` materialized from `info.nix`, `./tt` copied from the pinned
  `tt-support-tools`, and `src/project.v` regenerated from `hw/`

### The full e2e flow

```sh
# 1. Hardcaml -> Verilog (also run automatically by the shell hook)
dune runtest                                            # fast OCaml simulation
dune exec ./hw/bin/gen.exe > gen/project.v && cp gen/project.v src/project.v

# 2. RTL verification (cocotb + iverilog)
make -C test clean && make -C test

# 3. Harden -> GDS (LibreLane, no Docker)
./tt/tt_tool.py --create-user-config --ihp --no-docker
./tt/tt_tool.py --harden --ihp --no-docker

# 4. Build the TT submission package (GDS/OAS/LEF/SPEF/netlist/stats)
./tt/tt_tool.py --create-tt-submission --ihp

# 5. Gate-level verification
TOP=$(./tt/tt_tool.py --print-top-module --ihp)
cp runs/wokwi/final/nl/$TOP.nl.v test/gate_level_netlist.v
make -C test clean && GATES=yes make -C test

# 6. View the result
./tt/tt_tool.py --open-in-klayout --ihp --no-docker
```

### One-command equivalents

```sh
nix run .#rtl-test    # step 2
nix run .#harden      # steps 3 + 4
nix run .#gl-test     # step 5
```

The pure, sandboxed equivalents (what CI runs) are:

```sh
nix build .#verilog   # Hardcaml -> Verilog
nix build .#rtl-test  # cocotb RTL sim
nix build .#gds       # LibreLane harden -> GDS
nix build .#gl-test   # gate-level sim
nix build             # everything (default = .#design)
```

## Design source of truth

- `hw/` — Hardcaml design (`lib/top.ml` defines the TT port interface; `bin/gen.ml` prints Verilog).
- `info.nix` — project metadata (top module, source files, pinout). Regenerate the gitignored `info.yaml` with `nix run .#materialize-info`.
- `dune-project` → `protean.opam` — OCaml deps, resolved by opam-nix against the opam-repository pinned in `flake.lock`.
- `src/config.json` — the committed TT/LibreLane config defaults (overridden per-run by the generated `src/user_config.json`).

## CI

GitHub Actions reuse the same nix closure as local development:

- `test.yaml` — `nix build .#rtl-test` (Hardcaml → Verilog → cocotb RTL sim).
- `gds.yaml` — `nix build .#verilog` to produce `src/project.v`, then the
  [tt-gds-action](https://github.com/TinyTapeout/tt-gds-action) for the official
  submission artifacts (GDS, precheck, gate-level test, viewer).
- `docs.yaml` / `fpga.yaml` — materialize `info.yaml` via nix, then the
  tt-gds-action docs/fpga steps.

## Resources

- [Tiny Tapeout docs](https://tinytapeout.com)
- [Local hardening guide](https://www.tinytapeout.com/guides/local-hardening/)
- [LibreLane](https://www.zerotoasiccourse.com/terminology/librelane/)
- [Hardcaml](https://github.com/janestreet/hardcaml)
- [opam-nix](https://github.com/tweag/opam-nix)
