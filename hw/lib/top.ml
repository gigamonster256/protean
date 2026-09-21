(* Top-level Tiny Tapeout module, described in Hardcaml.
 *
 * Port names must match the Tiny Tapeout pinout exactly:
 * https://tinytapeout.com/specs/pinouts/
 * [Circuit.With_interface] labels the Verilog ports from these interfaces,
 * so the generated [src/project.v] plugs straight into the TT flow.
 *)

open! Hardcaml
open! Signal

module I = struct
  type 'a t =
    { ui_in : 'a [@bits 8]
    ; uio_in : 'a [@bits 8]
    ; ena : 'a
    ; clk : 'a
    ; rst_n : 'a
    }
  [@@deriving hardcaml]
end

module O = struct
  type 'a t =
    { uo_out : 'a [@bits 8]
    ; uio_out : 'a [@bits 8]
    ; uio_oe : 'a [@bits 8]
    }
  [@@deriving hardcaml]
end

(* Starter behaviour: same as the Verilog template (uo_out = ui_in + uio_in).
 * [clk], [rst_n] and [ena] are carried as ports but unused until the design
 * grows sequential logic - then wire them through [Reg_spec.create]. *)
let create_fn ({ ui_in; uio_in; ena = _; clk = _; rst_n = _ } : Signal.t I.t)
  : Signal.t O.t
  =
  { uo_out = uresize (ui_in +: uio_in) 8; uio_out = zero 8; uio_oe = zero 8 }
;;

module Circuit_impl = Circuit.With_interface (I) (O)

let circuit = Circuit_impl.create_exn ~name:"tt_um_gigamonster256" create_fn
