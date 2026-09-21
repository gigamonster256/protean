(* Emit the TT top module as Verilog on stdout.
 * Usage from the repo root: mkdir -p gen && dune exec ./hw/bin/gen.exe > gen/project.v *)
open! Hardcaml

let () = Rtl.print Verilog Tt_top.Top.circuit
