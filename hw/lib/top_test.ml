(* Cycle-accurate simulation of the TT top module (no Verilog needed). *)
open! Base
open! Hardcaml
open! Top
module Sim = Cyclesim.With_interface (I) (O)

let set_inputs sim ~ui_in ~uio_in =
  let inputs : Bits.t ref I.t = Cyclesim.inputs sim in
  inputs.ui_in := Bits.of_int ~width:8 ui_in;
  inputs.uio_in := Bits.of_int ~width:8 uio_in;
  inputs.ena := Bits.vdd;
  inputs.clk := Bits.gnd;
  inputs.rst_n := Bits.vdd
;;

let show_outputs sim =
  let outputs : Bits.t ref O.t = Cyclesim.outputs sim in
  Stdio.printf
    "uo_out=%d uio_out=%d uio_oe=%d\n"
    (Bits.to_int !(outputs.uo_out))
    (Bits.to_int !(outputs.uio_out))
    (Bits.to_int !(outputs.uio_oe))
;;

let%expect_test "uo_out = ui_in + uio_in (mod 256)" =
  let sim = Sim.create create_fn in
  set_inputs sim ~ui_in:20 ~uio_in:30;
  Cyclesim.cycle sim;
  show_outputs sim;
  [%expect {| uo_out=50 uio_out=0 uio_oe=0 |}];
  set_inputs sim ~ui_in:200 ~uio_in:100;
  Cyclesim.cycle sim;
  show_outputs sim;
  [%expect {| uo_out=44 uio_out=0 uio_oe=0 |}]
;;
