(** Parity fixture — OCaml.

    One documented function, one helper, an open, a call, a module constant
    and a marker. *)

open Other

let max_count = 10
(** How many. *)

let double n = n * 2
(** Double a value.
    @param n How much.
    @return the doubled value *)

(* TODO: cap at max_count *)
let widen n = double n + bump max_count
(** Widen a value.
    @param n How much.
    @return the widened value *)
