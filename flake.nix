{
  description = "Tiny Tapeout + Hardcaml";

  inputs = {
    nixpkgs.follows = "librelane/nix-eda/nixpkgs";

    librelane.url = "github:librelane/librelane/3.0.14";

    opam-nix.url = "github:tweag/opam-nix";
    opam-nix.inputs.nixpkgs.follows = "nixpkgs";

    tt-support-tools.url = "git+https://github.com/TinyTapeout/tt-support-tools.git?ref=ihp-sg13cmos5l&submodules=1";
    tt-support-tools.flake = false;

    ihp-open-pdk.url = "git+https://github.com/IHP-GmbH/IHP-Open-PDK.git?ref=dev&submodules=1";
    ihp-open-pdk.flake = false;
  };

  outputs =
    {
      self,
      nixpkgs,
      librelane,
      opam-nix,
      tt-support-tools,
      ihp-open-pdk,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      systems = [ "x86_64-linux" ];
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [
            librelane.inputs.nix-eda.overlays.default
            librelane.overlays.default
          ];
        };
      forAllSystems = f: lib.genAttrs systems (system: f (pkgsFor system));
    in
    {
      # info.yaml materialized from info.nix (single source of truth for
      # project metadata). `nix build .#info-yaml` prints the store path;
      # `nix run .#materialize-info` writes it to ./info.yaml in the repo.
      # Note: lib.generators.toYAML emits compact JSON, which is valid YAML
      # (superset since 1.2) but single-line - edit info.nix, not info.yaml.
      packages = forAllSystems (
        pkgs:
        let
          # The Hardcaml/OCaml toolchain from opam-nix (resolved live against
          # the opam-repository pinned in flake.lock). This is a build/dev
          # input, not a deliverable - the TT stages are below.
          hardcaml = pkgs.callPackage ./nix/hardcaml.nix {
            inherit opam-nix;
          };
          stages = pkgs.callPackage ./nix/package.nix {
            inherit hardcaml;
            ttSupportTools = tt-support-tools;
            ihpOpenPdk = ihp-open-pdk;
            ihpOpenPdkRev = ihp-open-pdk.rev;
            infoYaml = self.packages.${pkgs.stdenv.hostPlatform.system}.info-yaml;
            opensta = librelane.packages.${pkgs.stdenv.hostPlatform.system}.opensta;
            openroad = librelane.packages.${pkgs.stdenv.hostPlatform.system}.openroad;
          };
        in
        rec {
          inherit hardcaml;
          inherit (stages)
            verilog
            rtl-test
            gds
            gl-test
            design
            ;
          default = design;
          info-yaml = pkgs.writeText "info.yaml" ''
            # GENERATED from info.nix - do not edit by hand.
            # Regenerate with: nix run .#materialize-info
            ${lib.generators.toYAML { } (import ./info.nix)}
          '';
        }
      );

      apps = forAllSystems (pkgs: {
        # Local no-Docker e2e helpers: each runs the underlying tt_tool.py /
        # make command inside `nix develop` (so the shellHook sets up tt/,
        # pdk/, info.yaml, yowasp and the env). `nix build .#<stage>` is the
        # pure, sandboxed equivalent used by CI.
        rtl-test = {
          type = "app";
          program = lib.getExe (
            pkgs.writeShellApplication {
              name = "tt-rtl-test";
              text = ''
                if [ ! -f info.nix ]; then
                  echo "error: run from the repo root (info.nix not found)" >&2
                  exit 1
                fi
                exec nix develop --command bash -c 'make -C test clean && make -C test'
              '';
            }
          );
        };
        harden = {
          type = "app";
          program = lib.getExe (
            pkgs.writeShellApplication {
              name = "tt-harden";
              text = ''
                if [ ! -f info.nix ]; then
                  echo "error: run from the repo root (info.nix not found)" >&2
                  exit 1
                fi
                exec nix develop --command bash -c '
                  ./tt/tt_tool.py --create-user-config $TT_ARGS --no-docker &&
                  ./tt/tt_tool.py --harden $TT_ARGS --no-docker &&
                  ./tt/tt_tool.py --create-tt-submission $TT_ARGS
                '
              '';
            }
          );
        };
        gl-test = {
          type = "app";
          program = lib.getExe (
            pkgs.writeShellApplication {
              name = "tt-gl-test";
              text = ''
                if [ ! -f info.nix ]; then
                  echo "error: run from the repo root (info.nix not found)" >&2
                  exit 1
                fi
                exec nix develop --command bash -c '
                  TOP=$(./tt/tt_tool.py --print-top-module $TT_ARGS)
                  cp runs/wokwi/final/nl/$TOP.nl.v test/gate_level_netlist.v
                  make -C test clean
                  GATES=yes make -C test
                '
              '';
            }
          );
        };
        materialize-info = {
          type = "app";
          program = lib.getExe (
            pkgs.writeShellApplication {
              name = "materialize-info";
              text = ''
                if [ ! -f info.nix ]; then
                  echo "error: run from the repo root (info.nix not found)" >&2
                  exit 1
                fi
                cp ${self.packages.${pkgs.stdenv.hostPlatform.system}.info-yaml} info.yaml
                echo "wrote info.yaml from info.nix"
              '';
            }
          );
        };
        default = self.apps.${pkgs.stdenv.hostPlatform.system}.materialize-info;
      });
      devShells = forAllSystems (pkgs: {
        default = import ./nix/shell.nix {
          inherit
            pkgs
            ;
          ttSupportTools = tt-support-tools;
          ihpOpenPdk = ihp-open-pdk;
          ihpOpenPdkRev = ihp-open-pdk.rev;
          infoYaml = self.packages.${pkgs.stdenv.hostPlatform.system}.info-yaml;
          hardcaml = self.packages.${pkgs.stdenv.hostPlatform.system}.hardcaml;
          stages = self.packages.${pkgs.stdenv.hostPlatform.system};
        };
      });

      formatter = forAllSystems (
        pkgs:
        pkgs.writeShellApplication {
          name = "tt-formatter";

          runtimeInputs = [
            pkgs.nixfmt
            pkgs.ocaml
            pkgs.dune_3
            pkgs.ocamlformat
            pkgs.fd
          ];

          text = ''
            # Format Nix with Nixfmt
            fd "$@" -t f -e nix -x nixfmt -q '{}'

            # run dune fmt
            dune fmt
          '';
        }
      );
    };
}
