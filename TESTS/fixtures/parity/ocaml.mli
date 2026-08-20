(** Parity fixture — OCaml, the interface half.

    OCaml states its published surface in a sibling file, so this is where
    the visibility answer lives: `widen` is exported and `double` is not. *)

val widen : int -> int
(** Widen a value.
    @param n How much.
    @return the widened value *)
