# Around it

**[lib.nvim](https://github.com/StefanBartl/lib.nvim)** — the utility library
this grew out of and still builds on. If you are mapping a tree you are
probably about to want its `fs`, `ui.kit` and `usercmd` modules too; this
plugin uses exactly those.

**[runtime-analysis.nvim](https://github.com/StefanBartl/runtime-analysis.nvim)** —
the counter-check. This plugin knows what exists and what is documented; that
one knows what actually ran. Install it and the Telemetry and Loaded tabs stop
saying "no data".

**[docmap-desktop](https://github.com/StefanBartl/docmap-desktop)** — the
third leg: the same map read entirely outside Neovim, over a real
`http://127.0.0.1` origin, so the Telemetry and Loaded panels work there
exactly as they do in the editor.

**[pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim)** — renders
`overview.md` to `overview.pdf` when `opts.pdf` is on.

Everything except `lib.nvim` is soft: without them the map is generated
unchanged, minus those panels. See [requirements.md](requirements.md).

The full architecture story — where docs, static analysis and runtime each
belong, and why `runtime-analysis.nvim` is a separate plugin rather than a
mode of this one — is [ecosystem.md](ecosystem.md).
