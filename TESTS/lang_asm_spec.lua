-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/lang_asm_spec.lua — documentation.core.lang.asm
--
-- **The one language spec here that never skips.** Every other backend spec
-- opens by asking whether its tree-sitter grammar is reachable and degrades
-- to a stated skip when it is not, because CI does not install grammars this
-- repository does not vendor. `lang/asm.lua` parses by line, on purpose and
-- for the reasons in its header, so there is nothing to be missing — which
-- makes this the spec that proves the no-grammar path in `lang_registry`
-- works end to end, not merely that it is declared.
--
-- The fixtures below are three syntaxes on purpose: GAS with `.globl`, NASM
-- with `%include` and `global`, and an ARM file whose comments are `@`. The
-- fork is the whole reason this backend exists in the shape it does, so a
-- spec that only covered GAS would prove the least interesting third of it.

return function(H)
  local eq, ok = H.eq, H.ok

  local registry = require("documentation.core.lang_registry")
  local asm = registry.get("asm")
  ok(asm ~= nil, "the asm backend must be registered")

  eq(asm.grammar, nil, "asm declares no grammar, and that is a decision — see its header")

  -- -------------------------------------------------------------------
  -- Which files it claims.
  -- -------------------------------------------------------------------
  eq(asm.is_source("boot.s"), true)
  eq(asm.is_source("boot.S"), true, "a .S is preprocessed, not a different language")
  eq(asm.is_source("hello.asm"), true)
  eq(
    asm.is_source("macros.inc"),
    true,
    "NASM's include extension — see the field's note on the conflict"
  )
  eq(asm.is_source("main.c"), false)
  eq(asm.is_source("thing.lua"), false)
  eq(asm.module_tag, false, "the path is the identity, as with Zig and C")

  -- -------------------------------------------------------------------
  -- GAS: a file header, exported and private labels, data, constants.
  -- -------------------------------------------------------------------
  local gas = H.tmpfile(".s")
  local gw = assert(io.open(gas, "w"))
  gw:write(table.concat({
    "# The entry point and its one helper.",
    "# Second line of the file's own description.",
    "",
    '.include "macros.inc"',
    "",
    ".equ STACK_SIZE, 4096",
    "",
    ".globl _start, printed",
    "",
    ".section .data",
    "# The greeting written to stdout.",
    'msg: .asciz "hello"',
    "buf:",
    "    .space 64",
    "",
    ".section .text",
    "# Where the kernel enters.",
    "# Never returns.",
    "_start:",
    "    call helper",
    "    ret",
    "",
    "# Not exported, so nothing outside this file can reach it.",
    "helper:",
    "    ret",
    "",
    ".Lloop:",
    "    jmp .Lloop",
    "1:",
    "    nop",
    "",
  }, "\n"))
  gw:close()

  local header = asm.parse_header(gas)
  eq(
    header.summary,
    "The entry point and its one helper.",
    "the top comment block is the file's own doc"
  )
  ok(header.body:match("Second line"), "the rest of the block is the body")
  eq(header.module, nil, "assembly has no module tag to read")

  local fns, _, requires, symbols = asm.scan_file(gas)

  local by_name = {}
  for _, fn in ipairs(fns) do
    by_name[fn.name] = fn
  end
  ok(by_name["_start"] ~= nil, "_start is a label and therefore an entity")
  eq(by_name["_start"].summary, "Where the kernel enters.")
  eq(by_name["_start"].signature, "_start:", "written the way the file writes it")
  eq(by_name["_start"].internal, false, "`.globl _start` is an export, read from the directive")
  ok(by_name["helper"] ~= nil)
  eq(by_name["helper"].internal, true, "not named in any export directive")
  eq(
    by_name[".Lloop"],
    nil,
    "a GAS `.L` label never reaches the symbol table, so it is a jump target"
  )
  eq(by_name["1"], nil, "a numeric branch target is not an entity")
  eq(by_name["msg"], nil, "a data label is not a function")

  local sym = {}
  for _, s in ipairs(symbols) do
    sym[s.name] = s
  end
  ok(sym["STACK_SIZE"] ~= nil, ".equ is a module-scope constant")
  eq(sym["STACK_SIZE"].kind, "constant")
  eq(sym["STACK_SIZE"].detail, "4096")
  ok(sym["msg"] ~= nil, "a label followed by a data directive is data")
  eq(sym["msg"].kind, "constant")
  eq(sym["msg"].summary, "The greeting written to stdout.", "data carries its comment too")
  ok(sym["buf"] ~= nil, "the directive may sit on the next line")
  eq(sym["buf"].kind, "binding", "`.space` reserves rather than stores")

  eq(#requires, 1, "one include")
  eq(requires[1].module, "./macros.inc", "prefixed so `deps.resolve_relative` can follow it")

  -- -------------------------------------------------------------------
  -- NASM: `;` comments, `%include`, `global name:function`, `equ` postfix.
  -- -------------------------------------------------------------------
  local nasm = H.tmpfile(".asm")
  local nw = assert(io.open(nasm, "w"))
  nw:write(table.concat({
    "; A NASM translation unit.",
    "",
    '%include "sys.inc"',
    "",
    "SYS_WRITE equ 1",
    "",
    "global main:function",
    "",
    "section .text",
    "; The only exported entry.",
    "main:",
    "    ret",
    "",
    ".local_bit:",
    "    ret",
    "",
    "section .bss",
    "scratch: resb 128",
    "",
  }, "\n"))
  nw:close()

  local nfns, _, nrequires, nsymbols = asm.scan_file(nasm)
  local nby = {}
  for _, fn in ipairs(nfns) do
    nby[fn.name] = fn
  end
  eq(
    nby["main"] and nby["main"].internal,
    false,
    "`global main:function` exports it, type suffix and all"
  )
  eq(
    nby[".local_bit"],
    nil,
    "a NASM `.name` label is scoped to the label above it — a jump target"
  )
  eq(nrequires[1] and nrequires[1].module, "./sys.inc")

  local nsym = {}
  for _, s in ipairs(nsymbols) do
    nsym[s.name] = s
  end
  eq(
    nsym["SYS_WRITE"] and nsym["SYS_WRITE"].detail,
    "1",
    "NASM writes the constant the other way round"
  )
  eq(nsym["scratch"] and nsym["scratch"].kind, "binding", "`resb` reserves")

  -- -------------------------------------------------------------------
  -- ARM: `@` comments, and `#1` immediates that must not read as ones.
  -- -------------------------------------------------------------------
  local arm = H.tmpfile(".s")
  local aw = assert(io.open(arm, "w"))
  aw:write(table.concat({
    "@ An ARM routine.",
    "",
    ".global arm_entry",
    "",
    "@ Sets r0 and returns.",
    "arm_entry:",
    "    mov r0, #1",
    "    bx lr",
    "",
  }, "\n"))
  aw:close()

  local ah = asm.parse_header(arm)
  eq(ah.summary, "An ARM routine.", "`@` opens a comment in ARM's GAS syntax")
  local afns = asm.scan_file(arm)
  eq(#afns, 1)
  eq(afns[1].name, "arm_entry")
  eq(afns[1].internal, false)
  eq(afns[1].summary, "Sets r0 and returns.", "an immediate `#1` on a later line changes nothing")

  -- -------------------------------------------------------------------
  -- The two rules that keep a file header from being claimed twice, and a
  -- banner from being claimed at all.
  -- -------------------------------------------------------------------
  local touching = H.tmpfile(".s")
  local tw = assert(io.open(touching, "w"))
  tw:write(table.concat({
    "# Adds two numbers.",
    "add2:",
    "    ret",
    "",
  }, "\n"))
  tw:close()
  eq(
    asm.parse_header(touching).summary,
    "",
    "a block touching a label documents the label, not the file"
  )
  local tfns = asm.scan_file(touching)
  eq(tfns[1].summary, "Adds two numbers.", "and the label does get it")

  local licensed = H.tmpfile(".s")
  local lw = assert(io.open(licensed, "w"))
  lw:write(table.concat({
    "/* Copyright (c) 2026 Somebody.",
    " * Licensed under the MIT License.",
    " */",
    "",
    ".globl start",
    "start:",
    "    ret",
    "",
  }, "\n"))
  lw:close()
  eq(asm.parse_header(licensed).summary, "", "a license banner is a summary of nothing")

  local switched_off = H.tmpfile(".s")
  local sw = assert(io.open(switched_off, "w"))
  sw:write(table.concat({
    "; This file does one thing.",
    "",
    "; mov $1, %eax",
    "; int $0x80",
    "old_path:",
    "    ret",
    "",
  }, "\n"))
  sw:close()
  local ofns = asm.scan_file(switched_off)
  eq(ofns[1].summary, "", "commented-out instructions are not documentation")

  -- -------------------------------------------------------------------
  -- The second documentation convention: a note trailing the label itself,
  -- which is how a real NASM codebase writes a calling convention. Also a
  -- measurement's doing — see `doc_above` in the backend.
  -- -------------------------------------------------------------------
  local trailing = H.tmpfile(".asm")
  local rw = assert(io.open(trailing, "w"))
  rw:write(table.concat({
    "; A file of two annotated routines.",
    "",
    "copy_bytes: ;rdi - destination, rsi - source, rdx - count",
    "    ret",
    "",
    "; The block above wins when both are there.",
    "zero_out: ;rdi - buffer",
    "    ret",
    "",
  }, "\n"))
  rw:close()
  local rfns = asm.scan_file(trailing)
  local rby = {}
  for _, fn in ipairs(rfns) do
    rby[fn.name] = fn
  end
  eq(
    rby["copy_bytes"] and rby["copy_bytes"].summary,
    "rdi - destination, rsi - source, rdx - count",
    "a trailing comment is the calling convention, and it is documentation"
  )
  eq(
    rby["zero_out"] and rby["zero_out"].summary,
    "The block above wins when both are there.",
    "the block above is the longer statement, so it wins"
  )

  -- -------------------------------------------------------------------
  -- Routine vs. branch target — the rule a measurement produced, and the
  -- two guards on it. See `is_routine` in the backend for the numbers.
  -- -------------------------------------------------------------------
  local branchy = H.tmpfile(".asm")
  local bw = assert(io.open(branchy, "w"))
  bw:write(table.concat({
    "; A routine with jump targets written the way real NASM writes them.",
    "",
    "global handle",
    "",
    "; Handles one request.",
    "handle:",
    "    cmp rax, 0",
    "    je handle_ret",
    "    call work",
    "    handle_ret:",
    "    ret",
    "",
    "work:",
    "    ret",
    "",
  }, "\n"))
  bw:close()
  local bfns = asm.scan_file(branchy)
  local bnames = {}
  for _, fn in ipairs(bfns) do
    bnames[fn.name] = true
  end
  eq(bnames["handle"], true, "a flush label is a routine")
  eq(bnames["work"], true)
  eq(
    bnames["handle_ret"],
    nil,
    "an indented label is a branch target, whatever its name looks like"
  )
  eq(#bfns, 2, "two routines, not three")

  -- The guard: a file that indents everything is one where indentation says
  -- nothing, and the rule switches itself off rather than reporting the
  -- file as empty.
  local all_indented = H.tmpfile(".asm")
  local aw2 = assert(io.open(all_indented, "w"))
  aw2:write(table.concat({
    "; Everything in this file is indented.",
    "",
    "    first:",
    "        ret",
    "    second:",
    "        ret",
    "",
  }, "\n"))
  aw2:close()
  local ifns = asm.scan_file(all_indented)
  eq(#ifns, 2, "with no flush label anywhere, indentation carries no information")

  -- -------------------------------------------------------------------
  -- Markers, through the same path the contract spec exercises — but with
  -- the token this backend lists second, which is the one with a second
  -- meaning in ARM.
  -- -------------------------------------------------------------------
  local markers = require("documentation.core.markers")
  eq(#markers.scan_source("; TODO: finish this", asm), 1)
  eq(#markers.scan_source("# FIXME: and this", asm), 1)
  eq(#markers.scan_source("    mov r0, #1", asm), 0, "an immediate is not a marker")
end
