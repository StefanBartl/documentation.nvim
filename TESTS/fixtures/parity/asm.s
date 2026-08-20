; Parity fixture — assembly (GAS flavour).
;
; A label with a leading comment block, one published and one local, an
; include, a module-scope constant and a marker. There is no parameter list
; and no call graph; see docs/LANGUAGES.md for why those cells are blank.

%include "other.inc"

MAX equ 10

.globl widen

; Double a value.
double:
    add eax, eax
    ret

; Widen a value.
; TODO: cap at MAX
widen:
    call double
    ret
