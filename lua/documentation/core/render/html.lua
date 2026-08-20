---@module 'documentation.core.render.html'
--- Renders the docmap IR as a single self-contained HTML page.
---
--- Self-contained is a hard requirement, not a preference: the artifact has to
--- work from a `file://` URL and from a `gh-pages` branch with no build step,
--- and a documentation page that breaks without network access is a bad
--- documentation page. Everything — CSS, JS, the IR itself — is inlined.
---
--- The IR is embedded as JSON in a `<script type="application/json">` block
--- rather than being expanded into markup at generation time, so the same file
--- powers the tree, the filter and the detail pane without duplicating data.

local json = require("documentation.core.json")
-- One finding, one sentence. Rendered here rather than carried already
-- rendered — see `core/findings.lua` for why the check no longer builds
-- its own English.
local fmt_finding = require("documentation.core.findings").format

local M = {}

---HTML-escape text destined for markup.
---@param s string?
---@return string
local function esc(s)
  if not s or s == "" then
    return ""
  end
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local CSS = [[
:root{
  --bg:#fbfbfa; --panel:#fff; --ink:#1a1a19; --muted:#6b6b68; --line:#e4e4e1;
  --accent:#3b6ea8; --accent-soft:#eaf1f9;
  --error:#b3261e; --warn:#8a5a00; --info:#4a4a48;
  --mod:#3b6ea8; --ns:#7a7a76; --file:#5c8a5c;
  --dep:#a35a2a; --call:#6b4c9a; --fn:#8a5a00; --ext:#2a7a6f;
  --mono:ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,monospace;
}
@media (prefers-color-scheme:dark){
  :root{
    --bg:#16171a; --panel:#1d1f23; --ink:#e6e6e3; --muted:#9a9a95; --line:#2e3136;
    --accent:#7aa9dd; --accent-soft:#22303f;
    --error:#f2837b; --warn:#e0b060; --info:#a8a8a3;
    --mod:#7aa9dd; --ns:#9a9a95; --file:#8fbf8f;
    --dep:#d99b6a; --call:#b09ada; --fn:#e0b060; --ext:#6fc0b3;
  }
}
:root[data-theme="light"]{
  --bg:#fbfbfa; --panel:#fff; --ink:#1a1a19; --muted:#6b6b68; --line:#e4e4e1;
  --accent:#3b6ea8; --accent-soft:#eaf1f9;
  --error:#b3261e; --warn:#8a5a00; --info:#4a4a48;
  --mod:#3b6ea8; --ns:#7a7a76; --file:#5c8a5c;
  --dep:#a35a2a; --call:#6b4c9a; --fn:#8a5a00; --ext:#2a7a6f;
}
:root[data-theme="dark"]{
  --bg:#16171a; --panel:#1d1f23; --ink:#e6e6e3; --muted:#9a9a95; --line:#2e3136;
  --accent:#7aa9dd; --accent-soft:#22303f;
  --error:#f2837b; --warn:#e0b060; --info:#a8a8a3;
  --mod:#7aa9dd; --ns:#9a9a95; --file:#8fbf8f;
  --dep:#d99b6a; --call:#b09ada; --fn:#e0b060; --ext:#6fc0b3;
}
*{box-sizing:border-box}
/* Type scale: 9.5 / 10.5 / 11.5 / 12.5 / 13 / 14 / 15 / 17 / 19 / 20px.
   Ten steps, not the fifteen this file used to declare — measured, not
   eyeballed: `grep -oE "font-size:[0-9.]+px"` found half-integer pairs
   less than a pixel apart (`11px`/`11.5px`, `12px`/`12.5px`…) with no
   distinguishing use — real signal the scale accreted through ordinary
   editing rather than being designed, exactly as
   docs/ROADMAP/V1_EXTENSION/IMPLEMENTATION_PLAN.md's Phase 4 named and
   deliberately deferred pending visual verification. Verified this time
   by counting which of each pair was already used more: every merge
   moved the *less*-used value onto the *more*-used one, so the majority
   of rules — the ones most likely to anchor a reader's sense of the
   page's rhythm — render pixel-identical to before, and only the
   minority actually shifted. No rule's *relative* ordering changed. */
body{margin:0;background:var(--bg);color:var(--ink);
  font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
/* Who made the thing you are reading. Muted and one line: this page is
   someone else's project, and a tool that shouts inside its own output is
   a tool people strip out. */
.topbar{padding:6px 24px;font-size:11.5px;color:var(--muted);
  display:flex;gap:8px;align-items:baseline;border-bottom:1px solid var(--line)}
.topbar .brand{color:var(--muted);text-decoration:none;font-weight:600;letter-spacing:.02em}
.topbar .brand:hover{color:var(--ink);text-decoration:underline}
.topbar .tagline{opacity:.75}
header{padding:20px 24px 14px;border-bottom:1px solid var(--line);
  display:flex;flex-wrap:wrap;gap:14px;align-items:baseline}
h1{margin:0;font-size:20px;font-weight:650;letter-spacing:-.01em}
h1 .sub{color:var(--muted);font-weight:400;font-size:14px;margin-left:8px}
.stats{margin-left:auto;display:flex;gap:14px;font-size:12.5px;color:var(--muted);flex-wrap:wrap}
.stats b{color:var(--ink);font-weight:600}
/* The counts are buttons, but they must not look like the toolbar's. Stripped
   back to text, gaining an underline only on hover — the affordance appears
   where the pointer already is, without five chrome buttons in the header. */
.stat-link{padding:0;border:0;background:none;color:inherit;font:inherit;cursor:pointer;
  border-radius:4px}
.stat-link:hover:not(:disabled){text-decoration:underline;text-underline-offset:3px}
.stat-link:focus-visible{outline:2px solid var(--accent-soft);outline-offset:2px}
/* A zero count is not a link. Same opacity as the surrounding muted text, so
   it reads as a number rather than as something broken. */
.stat-link:disabled{cursor:default}
/* Where an errors/warnings click lands. Fades, so the eye is drawn to the row
   without leaving a permanent highlight the reader then has to dismiss. */
@keyframes findflash{from{background:var(--accent-soft)}to{background:transparent}}
#findings tbody tr.flash td{animation:findflash 1.6s ease-out}
.toolbar{padding:12px 24px;display:flex;gap:10px;align-items:center;flex-wrap:wrap;
  border-bottom:1px solid var(--line)}
#q{flex:1;min-width:200px;max-width:440px;padding:7px 11px;border:1px solid var(--line);
  border-radius:7px;background:var(--panel);color:var(--ink);font-size:14px}
#q:focus{outline:2px solid var(--accent-soft);border-color:var(--accent)}
button{padding:6px 11px;border:1px solid var(--line);border-radius:7px;background:var(--panel);
  color:var(--ink);font-size:13px;cursor:pointer}
button:hover{border-color:var(--accent);color:var(--accent)}
.tabs{display:flex;flex-wrap:wrap;gap:2px;padding:0 24px;border-bottom:1px solid var(--line)}
.tab-btn{padding:9px 13px;border:none;background:none;color:var(--muted);font-size:13px;
  cursor:pointer;border-bottom:2px solid transparent;margin-bottom:-1px}
.tab-btn:hover{color:var(--ink)}
.tab-btn.active{color:var(--accent);border-bottom-color:var(--accent);font-weight:600}
.view{display:none}
.view.active{display:block}
main.view.active{display:grid}
main{grid-template-columns:minmax(300px,1.1fr) minmax(0,1.4fr);gap:0;align-items:start}
@media (max-width:860px){main{grid-template-columns:1fr}}
/* =====================================================================
   Print.

   The page is one artifact and printing it is a media query, not a
   feature — but only if the query actually says something, and four
   things here would otherwise print badly rather than merely plainly.

   1. **The panes are clipped, not long.** `#tree`, `#detail` and the two
      history panes carry `max-height:calc(100vh - Npx)` with
      `overflow:auto`, which on paper means the first screenful prints and
      the rest silently does not exist. Unclipping them is the single
      change that makes this work at all.
   2. **Dark mode follows you to the printer.** `prefers-color-scheme` is
      a property of the reader, not of the sheet, and browsers do not
      override it — so a reader in dark mode gets a black page. The tokens
      are forced back to the light set here rather than fought
      per-element.
   3. **Chrome that cannot be used on paper.** Tabs, the search box, the
      graph's control row and every button are affordances; on a sheet they
      are ink. The tab *bar* goes, the current view stays — `.view` already
      hides the others, so a printout is whatever tab you were on, which is
      also the least surprising thing it could be.
   4. **Rows split across the fold.** A tree row or a finding cut in half
      by a page break is unreadable in exactly the way a table is not.

   Deliberately not done: expanding collapsed tree branches. What prints is
   what is on screen — a printout that silently contains more than the page
   did is a different document, not a better one.
   ===================================================================== */
@media print{
  /* Light tokens, unconditionally: see note 2 above. */
  :root{
    --bg:#fff; --panel:#fff; --ink:#111; --muted:#555; --line:#bbb;
    --accent:#245; --accent-soft:#f0f0f0;
    --error:#900; --warn:#750; --info:#444;
    --mod:#245; --ns:#666; --file:#363; --dep:#743; --call:#534;
    --fn:#750; --ext:#255;
  }
  @page{margin:14mm}
  body{background:#fff;color:#111;font-size:10.5pt}

  /* Chrome. `.topbar` and `header` stay: they carry the project name and
     the counts, which is what tells a reader a week later what this sheet
     even is. */
  .tabs, .toolbar, .subtabs, .hctl, #markbar, #hiddenbar,
  #ctx, .sigpop, .explainpop, #hzoomlabel{display:none !important}
  button, input, select{display:none !important}

  /* Note 1: unclip every scrolling pane. */
  #tree, #detail, #hist-list, #hist-detail, #hgraph-wrap{
    max-height:none !important; overflow:visible !important;
    border-right:0 !important;
  }

  /* One column. Two panes side by side fit a screen, not a sheet — the
     tree ends up a narrow gutter and the detail wraps to nothing. */
  main.view.active{display:block !important}

  /* Note 4. */
  .row, .card, .qk, tr, .hnode, li{break-inside:avoid; page-break-inside:avoid}
  h1, h2, h3{break-after:avoid; page-break-after:avoid}

  /* A link's colour means nothing on paper and its target is not worth a
     parenthesis after every one — this page's links are internal
     navigation, so the URL would be noise rather than information. */
  a{color:inherit; text-decoration:none}

  /* Hover-only dimming must not survive into a static sheet. */
  #hgraph.focusing .hnode{opacity:1 !important}
}

#tree{padding:12px 8px 60px 16px;border-right:1px solid var(--line);
  max-height:calc(100vh - 132px);overflow:auto}
@media (max-width:860px){#tree{max-height:none;border-right:0;border-bottom:1px solid var(--line)}}
.row{display:flex;align-items:baseline;gap:7px;padding:3px 8px;border-radius:6px;cursor:pointer;
  white-space:nowrap}
.row:hover{background:var(--accent-soft)}
.row.sel{background:var(--accent-soft);box-shadow:inset 2px 0 0 var(--accent)}
.tw{width:14px;flex:none;color:var(--muted);font-size:11.5px;user-select:none}
.nm{font-family:var(--mono);font-size:13px}
.k-module .nm{color:var(--mod)} .k-namespace .nm{color:var(--ns)} .k-file .nm{color:var(--file)}
.sm{color:var(--muted);font-size:12.5px;overflow:hidden;text-overflow:ellipsis;flex:1;min-width:0}
.badges{display:flex;gap:4px;flex:none}
.bd{font-size:9.5px;letter-spacing:.04em;text-transform:uppercase;padding:1px 5px;
  border-radius:4px;border:1px solid var(--line);color:var(--muted)}
.bd.rd{color:var(--accent);border-color:var(--accent)}
.bd.dep{color:var(--error);border-color:var(--error)}
.bd.tested{color:var(--accent);border-color:var(--accent)}
.kids{margin-left:15px;border-left:1px solid var(--line);padding-left:3px}
.kids.hide{display:none}
#detail{padding:22px 26px 60px;max-height:calc(100vh - 132px);overflow:auto}
@media (max-width:860px){#detail{max-height:none}}
#detail h2{margin:0 0 3px;font-size:17px;font-family:var(--mono);font-weight:600}
.mp{font-family:var(--mono);font-size:12.5px;color:var(--muted);margin-bottom:16px;
  word-break:break-all}
.links{display:flex;gap:8px;flex-wrap:wrap;margin:0 0 18px}
.links a{font-size:12.5px;padding:4px 10px;border:1px solid var(--line);border-radius:6px;
  text-decoration:none;color:var(--accent);background:var(--panel)}
.links a:hover{border-color:var(--accent)}
.prose{white-space:pre-wrap;font-size:13px;color:var(--ink);
  background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:13px 15px;
  margin-bottom:18px;overflow-x:auto}
.sec{font-size:11.5px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);
  margin:18px 0 7px;font-weight:600}
.lst{list-style:none;margin:0;padding:0}
.lst li{font-family:var(--mono);font-size:12.5px;padding:2px 0;color:var(--muted)}
.empty{color:var(--muted);font-size:13px;font-style:italic}
.fn{margin-bottom:14px;padding-bottom:12px;border-bottom:1px dashed var(--line)}
.fn:last-child{border-bottom:0;padding-bottom:0;margin-bottom:0}
.fn-sig{font-family:var(--mono);font-size:12.5px;color:var(--ink);font-weight:600}
.fn-badges{display:inline-flex;gap:4px;margin-left:8px;vertical-align:middle}
.fn-desc{font-size:12.5px;color:var(--muted);margin:4px 0}
.fn-dep{color:var(--error);font-size:11.5px;font-weight:600;margin:4px 0}
.fn-plist{list-style:none;margin:4px 0;padding:0;font-size:11.5px}
.fn-plist li{padding:1px 0}
.fn-plist code{background:none;padding:0;color:var(--accent)}
.fn-ex{font-family:var(--mono);font-size:11.5px;white-space:pre-wrap;background:var(--accent-soft);
  border-radius:6px;padding:8px 10px;margin-top:6px;overflow-x:auto}
.fn-see a{color:var(--accent);text-decoration:none}
.fn-see a:hover{text-decoration:underline}
/* The bounded source snippet — popup-only, see snippetHTML()'s own comment
   for why this never touches the Tree tab's detail pane. Same shape as
   `.fn-ex`'s code block, a distinct class since the content is source, not
   an authored `@example`. */
.fn-snip-label{font-size:11.5px;text-transform:uppercase;letter-spacing:.05em;
  color:var(--muted);margin-top:10px}
.fn-snip-label .bd{text-transform:none;letter-spacing:0;margin-left:6px}
.fn-snip{font-family:var(--mono);font-size:11.5px;white-space:pre-wrap;background:var(--accent-soft);
  border-radius:6px;padding:8px 10px;margin-top:4px;overflow-x:auto}
/* Annotation popup — the same fn-* markup the detail pane renders, floated
   over whichever list the reader is scanning. Every list in this map shows a
   signature and nothing else; the params, returns and prose that were
   already parsed sat one navigation away, which is what this closes.
   `position:fixed` because the trigger can live inside a scrolling panel and
   an absolutely-positioned card would scroll away from its own anchor. */
.sigpop{position:fixed;z-index:60;display:none;max-width:520px;min-width:260px;
  max-height:60vh;overflow-y:auto;background:var(--bg);border:1px solid var(--line);
  border-radius:8px;box-shadow:0 8px 28px rgba(0,0,0,.18);padding:12px 14px}
.sigpop.on{display:block}
/* The language legend. Drawn only for a polyglot map -- see renderLangBar --
   so a single-language tree pays nothing for it. Quiet by default: a row of
   coloured chips over every map would be exactly the permanent chrome the
   rest of this page avoids. */
.langbar{display:flex;align-items:center;gap:6px;flex-wrap:wrap;
  padding:6px 10px;border-bottom:1px solid var(--line)}
.lb-label{font-size:11px;text-transform:uppercase;letter-spacing:.05em;color:var(--muted)}
.lb-chip{font-family:var(--mono);font-size:11px;padding:2px 7px;border-radius:11px;
  border:1px solid var(--line);background:transparent;color:var(--muted);cursor:pointer}
.lb-chip.on{color:var(--accent);border-color:var(--accent);background:var(--accent-soft)}
.lb-n{margin-left:5px;opacity:.65}
.lb-clear{font-size:11px;padding:2px 7px;border-radius:11px;border:1px dashed var(--line);
  background:transparent;color:var(--muted);cursor:pointer}
/* Sized off the toolbar's own buttons rather than styled separately: it is
   one more control in that row, not a feature announcing itself. The fixed
   width keeps "Copied" from resizing the toolbar under the pointer. */
#copylink{min-width:82px}
/* In the Hierarchy control row the bar is one control among several, not a
   band across the top: no border, no padding of its own. */
.langbar-h{border-bottom:none;padding:0}
/* Filtered out by language. Same opacity as the right-click dim above and a
   separate class on purpose -- a box the reader dimmed by hand must stay
   dimmed when the language filter clears, and the reverse. The
   `#hgraph.focusing` overrides repeat for the same reason they do there:
   equal specificity, decided by source order. */
.hnode.langoff{opacity:.08;pointer-events:none}
#hgraph.focusing .hnode.langoff{opacity:.08}
#hgraph.focusing .hnode.langoff.near{opacity:.08}
/* The keyword card: the same component as .sigpop, one layer above it,
   because a snippet is rendered *inside* .sigpop and its triggers therefore
   cannot borrow it. Narrower, because the content is two sentences. */
.kwpop{position:fixed;z-index:70;display:none;max-width:340px;
  background:var(--bg);border:1px solid var(--line);border-radius:8px;
  box-shadow:0 8px 28px rgba(0,0,0,.18);padding:10px 12px}
.kwpop.on{display:block}
.kw-word{font-family:var(--mono);font-size:12px;color:var(--accent);margin-bottom:4px}
.kw-sum{font-size:12px;line-height:1.45}
/* The surprising-fact line, set apart because it is the exception rather
   than a second half of the definition. */
.kw-note{font-size:11.5px;line-height:1.4;color:var(--muted);margin-top:6px}
.kw-ref{font-size:11px;margin-top:8px}
.kw-origin{font-size:10.5px;margin-top:6px;color:var(--muted);
  text-transform:uppercase;letter-spacing:.04em}
/* Decorated keywords stay unobtrusive until pointed at: a snippet where
   every keyword is coloured is syntax highlighting, which this page turned
   down on purpose. A dotted underline says "there is an answer here" and
   nothing more. */
.kw{border-bottom:1px dotted var(--muted);cursor:help}
.kw:hover,.kw:focus{border-bottom-color:var(--accent);color:var(--accent);outline:none}
.sigpop .fn-sig{font-size:12.5px}
/* The trigger. Kept at full opacity for keyboard focus and while its popup
   is open, so tabbing through a list does not chase an invisible control. */
.sigi{display:inline-block;margin-left:6px;padding:0 4px;border-radius:4px;cursor:help;
  font-size:10.5px;line-height:15px;color:var(--muted);border:1px solid var(--line);
  opacity:.45;transition:opacity .12s,color .12s;user-select:none}
.sigi:hover,.sigi:focus,.sigi.on{opacity:1;color:var(--accent);border-color:var(--accent);
  outline:none}
li:hover>.sigi,tr:hover .sigi{opacity:.8}
/* The prose-reference affordance. Rendered only where references exist, so
   unlike `.sigi` it carries information by being present at all — hence a
   accent-tinted resting state rather than `.sigi`'s near-invisible one. */
.doci{display:inline-block;margin-left:6px;padding:0 5px;border-radius:4px;cursor:help;
  font-size:10.5px;line-height:15px;color:var(--accent);border:1px solid var(--line);
  background:var(--accent-soft);opacity:.75;transition:opacity .12s;user-select:none}
.doci:hover,.doci:focus,.doci.on{opacity:1;border-color:var(--accent);outline:none}
.docn{margin-left:4px;font-weight:600}
.docref{margin:7px 0;padding-left:9px;border-left:2px solid var(--line)}
.docref-where{font-family:var(--mono);font-size:11.5px;color:var(--accent)}
.docref-where .bd{margin-left:6px}
.docref-ctx{font-size:11.5px;color:var(--muted);margin-top:2px}
/* @overload — one block per alternative call shape, indented under the
   primary signature so it reads as "also, this" rather than a second
   function. Left border rather than a background: a filled block here would
   compete with the deprecation banner for the reader's eye, and this is a
   much quieter fact. */
.fn-overloads{margin:6px 0 0 0;padding-left:10px;border-left:2px solid var(--line)}
.fn-ov-label{font-size:10.5px;color:var(--muted);text-transform:uppercase;
  letter-spacing:.04em;margin-bottom:2px}
.fn-ov-sig{font-family:var(--mono);font-size:12.5px;color:var(--ink)}
.fn-ov-raw{font-family:var(--mono);font-size:11.5px;color:var(--muted);font-style:italic}
code{font-family:var(--mono);font-size:.92em;background:var(--accent-soft);
  padding:1px 4px;border-radius:4px}
/* Inside its own view now, so it gets the same padding every other view has
   rather than the trailing gap it needed when it sat at the foot of the
   page under everything else. */
#view-findings{padding:22px 26px 60px}
#findings{padding:0}
#findings table{border-collapse:collapse;width:100%;font-size:12.5px}
#findings th{text-align:left;padding:6px 9px;border-bottom:1px solid var(--line);
  color:var(--muted);font-weight:600;font-size:11.5px;text-transform:uppercase;letter-spacing:.05em}
#findings td{padding:5px 9px;border-bottom:1px solid var(--line);vertical-align:top}
#findings td.msg{font-family:var(--mono);font-size:11.5px;word-break:break-word}
.sev{font-weight:650;text-transform:uppercase;font-size:10.5px;letter-spacing:.05em}
.sev.error{color:var(--error)} .sev.warn{color:var(--warn)} .sev.info{color:var(--info)}
details>summary{cursor:pointer;font-size:13px;color:var(--muted);padding:8px 0}
.wrap{overflow-x:auto}
#view-notes{padding:22px 26px 60px}
#view-notes h3{margin:26px 0 4px;font-size:13px;font-weight:600;color:var(--ink)}
#view-notes h3:first-child{margin-top:0}
#view-notes .nsub,#view-index .nsub,#view-analysis .nsub,#view-features .nsub{
  font-size:12.5px;color:var(--muted);margin:0 0 10px}
/* `#view-features` was missing here while the Features panel emitted the
   same span, so its counter had no rule at all and rendered glued to the
   heading: `FAVORITES6`. Three panels use this badge; three selectors. */
#view-notes .ncount,#view-index .ncount,#view-features .ncount{color:var(--muted);font-weight:400;font-size:11.5px;
  margin-left:6px}
/* A group heading, one level above the per-keyword headings under it.
   The Notes tab now has two halves that answer different questions --
   annotations on functions, markers on lines -- and a reader who cannot
   see the seam reads the second half as more of the first. */
#view-notes h3.ngroup{margin-top:34px;font-size:11px;letter-spacing:.08em;
  text-transform:uppercase;color:var(--muted);border-bottom:1px solid var(--line);
  padding-bottom:6px}
#view-notes h3.ngroup:first-child{margin-top:0}
/* The spelling the author actually typed, when it differs from the
   section it landed in -- `BUG` under FIX. A tag, not prose. */
.nlist .nauthor{font-size:11.5px;color:var(--muted);margin-left:8px}
.nlist .nword{font-family:var(--mono);font-size:11px;color:var(--muted);
  border:1px solid var(--line);border-radius:3px;padding:1px 5px;margin-left:8px}
.nlist{list-style:none;margin:0;padding:0}
.nlist li{padding:7px 0;border-bottom:1px dashed var(--line)}
.nlist li:last-child{border-bottom:0}
.nlist .nfn{font-family:var(--mono);font-size:12.5px;color:var(--accent);
  text-decoration:none;font-weight:600;cursor:pointer}
.nlist .nfn:hover{text-decoration:underline}
.nlist .nfn:focus-visible{outline:2px solid var(--accent-soft);outline-offset:2px}
.godi-wrap{position:relative;display:inline-block}
.godi-tip{display:none;position:absolute;z-index:40;left:0;top:calc(100% + 6px);
  width:min(46ch,80vw);padding:9px 11px;border:1px solid var(--line);border-radius:8px;
  background:var(--panel);color:var(--ink);font-size:12.5px;line-height:1.45;
  box-shadow:0 6px 20px rgba(0,0,0,.18)}
.godi-tip b{color:var(--accent)}
/* Hover *and* focus: a warning only a mouse can see is not a warning. */
.godi-wrap:hover .godi-tip,.godi-wrap:focus-within .godi-tip{display:block}
.godi-off{opacity:.55;text-decoration:line-through}
.godi-note{margin-top:4px;font-size:11.5px;color:var(--muted);max-width:62ch}
.feat-name[data-node]:focus-visible,.feat-tab-name[data-node]:focus-visible{
  outline:2px solid var(--accent-soft);outline-offset:2px}
/* Roving-tabindex lists: the container is the tab stop, the item is what the
   arrows move. Both need to say where focus is. `outline-offset:-2px` on the
   row keeps the ring inside the row box, which a table row would otherwise
   clip against its neighbours. */
#tree:focus-visible,#hist-list:focus-visible,#anbody:focus-visible{
  outline:2px solid var(--accent-soft);outline-offset:-2px}
.row:focus-visible,.crow:focus-visible,tr.anrow:focus-visible{
  outline:2px solid var(--accent);outline-offset:-2px}
.antable th.ansort:focus-visible{outline:2px solid var(--accent-soft);outline-offset:-2px}
.nlist .nwhere{font-family:var(--mono);font-size:11.5px;color:var(--muted);margin-left:8px}
.nlist .ntext{font-size:12.5px;color:var(--ink);margin-top:2px}
/* Unscoped variant: the Analysis panels' empty-state paragraphs
   (`<p class="ntext none">`) and the Features tab both use this outside any
   `.nlist`, and it was previously only ever styled inside one. */
.ntext.none{color:var(--muted);font-style:italic}
/* --- Features tab -------------------------------------------------------- */
#view-features{padding:22px 26px 60px}
.feat-wrap{max-width:820px}
.feat-intro{font-size:13px;color:var(--ink);line-height:1.5;margin-bottom:16px}
/* The intros are rendered Markdown now, so they arrive as real block
   elements. Without these the first paragraph's own top margin pushes the
   block away from its heading and the last one's pushes the next section
   down twice. */
.feat-intro>:first-child,.feat-fileintro>:first-child{margin-top:0}
.feat-intro>:last-child,.feat-fileintro>:last-child{margin-bottom:0}
.feat-intro h1,.feat-intro h2,.feat-intro h3{font-size:13.5px;margin:14px 0 6px}
.feat-intro ul,.feat-fileintro ul{margin:6px 0;padding-left:18px}
.feat-intro code,.feat-fileintro code{font-family:var(--mono);font-size:12px}
.feat-card{border:1px solid var(--line);border-radius:8px;background:var(--panel);
  padding:11px 14px;margin-bottom:8px}
.feat-name{font-size:13px;font-weight:600;color:var(--ink)}
.feat-name[data-node]{cursor:pointer;color:var(--accent)}
.feat-name[data-node]:hover{text-decoration:underline}
.feat-summary{font-size:12.5px;color:var(--ink);margin-top:4px;line-height:1.45}
.feat-meta{margin-top:7px;display:flex;flex-direction:column;gap:2px}
.feat-meta-row{font-size:11.5px;color:var(--muted);font-family:var(--mono)}
.feat-meta-row b{color:var(--ink);font-weight:600;margin-right:4px}
.feat-src{margin-top:6px}
.feat-src a{font-size:10.5px;color:var(--muted);font-family:var(--mono);text-decoration:none;
  cursor:pointer}
.feat-src a:hover{color:var(--accent);text-decoration:underline}
/* A promoted feature's own tab (`Tab: true` — see docs/FEATURES_FORMAT.md).
   Dynamically created, one `[id^="view-feature-"]` panel per promoted
   feature — `.view`/`.view.active` above already govern its visibility,
   nothing feature-tab-specific needed there. */
[id^="view-feature-"]{padding:22px 26px 60px}
.feat-tab-wrap{max-width:760px}
.feat-tab-theme{font-size:11.5px;color:var(--muted);text-transform:uppercase;
  letter-spacing:.05em}
.feat-tab-name{margin:2px 0 0;font-size:19px;font-weight:600;color:var(--ink)}
.feat-tab-name[data-node]{cursor:pointer;color:var(--accent)}
.feat-tab-name[data-node]:hover{text-decoration:underline}
.feat-tab-summary{font-size:13px;color:var(--ink);margin-top:6px;line-height:1.5}
.feat-tab-body{margin-top:16px;font-size:13px;color:var(--ink);line-height:1.55}
.feat-tab-body h4,.feat-tab-body h5,.feat-tab-body h6{margin:18px 0 4px;font-weight:600;
  color:var(--ink)}
.feat-tab-body h4:first-child,.feat-tab-body h5:first-child,
.feat-tab-body h6:first-child{margin-top:0}
.feat-tab-body p{margin:8px 0}
.feat-tab-body ul{margin:8px 0;padding-left:22px}
.feat-tab-body li{margin:2px 0}
.feat-tab-body pre{font-family:var(--mono);font-size:11.5px;white-space:pre-wrap;
  background:var(--accent-soft);border-radius:6px;padding:8px 10px;margin:10px 0;
  overflow-x:auto}
.feat-tab-body pre code{background:none;padding:0}
.feat-tab-body a{color:var(--accent)}
#hist-list{padding:12px 8px 60px 16px;border-right:1px solid var(--line);
  max-height:calc(100vh - 132px);overflow:auto}
@media (max-width:860px){#hist-list{max-height:none;border-right:0;
  border-bottom:1px solid var(--line)}}
#hist-detail{padding:22px 26px 60px;max-height:calc(100vh - 132px);overflow:auto}
@media (max-width:860px){#hist-detail{max-height:none}}
.crow{padding:5px 8px;border-radius:6px;cursor:pointer}
.crow:hover{background:var(--accent-soft)}
.crow.sel{background:var(--accent-soft);box-shadow:inset 2px 0 0 var(--accent)}
.crow .csub{font-size:12.5px;color:var(--ink);overflow:hidden;text-overflow:ellipsis;
  white-space:nowrap}
.crow .cmeta{font-family:var(--mono);font-size:10.5px;color:var(--muted);margin-top:1px}
.hist-approx{color:var(--warn);font-size:11.5px;border:1px solid var(--warn);
  border-radius:5px;padding:5px 8px;margin:0 0 12px}
.hist-sec{font-size:11.5px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);
  margin:18px 0 7px;font-weight:600}
.hist-fn{font-family:var(--mono);font-size:12.5px;color:var(--ink);font-weight:600}
.hist-callers{list-style:none;margin:2px 0 8px;padding:0 0 0 14px}
.hist-callers li{font-family:var(--mono);font-size:11.5px;color:var(--muted);padding:1px 0}
.hist-mods{display:flex;flex-wrap:wrap;gap:5px;margin:0 0 4px}
.hist-mods a{font-family:var(--mono);font-size:11.5px;padding:2px 7px;border-radius:5px;
  border:1px solid var(--line);color:var(--accent);cursor:pointer;text-decoration:none}
.hist-mods a:hover{border-color:var(--accent);background:var(--accent-soft)}
.hist-mods span.gone{font-family:var(--mono);font-size:11.5px;padding:2px 7px;
  border-radius:5px;border:1px dashed var(--line);color:var(--muted)}
.hist-diff{font-family:var(--mono);font-size:11.5px;white-space:pre;overflow-x:auto;
  background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:10px 12px;
  max-height:460px;overflow-y:auto}
.hist-diff .da{color:var(--file)} .hist-diff .dd{color:var(--error)}
.hist-diff .dh{color:var(--accent);font-weight:600} .hist-diff .dm{color:var(--muted)}
#view-index{padding:22px 26px 60px}
/* The second level, under the tab bar and above the view.

   Visually subordinate on purpose: smaller, no bottom border of its own,
   and the active mark is a filled pill rather than the underline the top
   bar uses. Two rows of identical-looking tabs would read as sixteen tabs
   rather than as eight with a choice inside two of them. */
.subtabs{display:flex;gap:4px;flex-wrap:wrap;padding:7px 20px;
  border-bottom:1px solid var(--line);background:var(--panel)}
.subtabs[hidden]{display:none}
.subtab-btn{border:1px solid transparent;border-radius:999px;background:none;
  color:var(--muted);font-size:12px;padding:3px 11px;cursor:pointer}
.subtab-btn:hover{color:var(--ink)}
.subtab-btn.active{background:var(--accent-soft);color:var(--accent);
  border-color:var(--line);font-weight:600}
.subtab-btn:focus-visible{outline:2px solid var(--accent-soft);outline-offset:1px}
/* The explanation card. Narrower than the annotation card it borrows from:
   these are two sentences about a control, not a function signature with a
   snippet under it, and a wide card over a tab strip covers the tabs. */
/* The graph's own breadcrumb. Quiet: it is orientation, not a control
   group, and it sits beside two buttons that are. */
.hcrumb{display:flex;align-items:center;gap:4px;flex-wrap:wrap;
  font-size:12px;color:var(--muted);margin-left:4px}
.hcrumb[hidden]{display:none}
.hcrumb button{border:none;background:none;padding:1px 4px;border-radius:4px;
  color:var(--accent);font:inherit;cursor:pointer}
.hcrumb button:hover{background:var(--accent-soft)}
.hcrumb .here{color:var(--ink);font-weight:600;padding:1px 4px}
.explainpop{max-width:340px}
.explainpop .fn-desc{white-space:normal;line-height:1.5}
#view-analysis{padding:22px 26px 60px}
#antoggle{margin-bottom:14px}
.cl-h{margin:18px 0 6px;font-size:14px}
.cl-h .cl-src{font-weight:400;font-size:11.5px;color:var(--muted);margin-left:8px}
.cl-list{list-style:none;margin:0;padding:0}
.cl-item{display:flex;flex-wrap:wrap;align-items:baseline;gap:8px;padding:7px 10px;
  border:1px solid var(--line);border-radius:7px;background:var(--panel);margin-bottom:6px}
.cl-box{font-family:ui-monospace,monospace;color:var(--muted)}
.cl-item.cl-done .cl-box{color:var(--accent)}
.cl-text{flex:1 1 320px}
.cl-ref,.cl-date,.cl-meta{font-size:11.5px;color:var(--muted)}
.cl-ref{font-family:ui-monospace,monospace}
.cl-state{font-size:11.5px;padding:1px 7px;border-radius:999px;border:1px solid var(--line)}
.cl-stale{color:#b3261e;border-color:#b3261e}
.cl-unverified{color:#8a6d00;border-color:#8a6d00}
.cl-uncited,.cl-unknown{color:var(--muted)}
.cl-current{color:var(--muted)}

.antable{width:100%;border-collapse:collapse;font-size:12.5px}
.antable th.ansort{cursor:pointer;user-select:none;white-space:nowrap}
.antable th.ansort:hover{color:var(--ink)}
.antable th.ansort.active{color:var(--accent)}
.antable th{text-align:left;font-weight:600;color:var(--muted);font-size:11.5px;
  text-transform:uppercase;letter-spacing:.03em;padding:4px 8px;border-bottom:1px solid var(--line);
  background:var(--panel);position:sticky;top:0}
.antable td{padding:5px 8px;border-bottom:1px dashed var(--line);font-family:var(--mono)}
.anrow{cursor:pointer}
.anrow:hover td{background:var(--accent-soft)}
.anflag{color:var(--warn);font-size:11.5px;border:1px solid var(--warn);
  border-radius:4px;padding:1px 5px;margin-left:6px}
.anbar{width:120px;height:8px;background:var(--line);border-radius:4px;overflow:hidden}
.anfill{height:100%;background:var(--accent)}
.telpicker{display:flex;gap:16px;flex-wrap:wrap;margin-bottom:10px;font-size:12.5px}
.telpicker label{display:flex;align-items:center;gap:6px;color:var(--muted)}
.telpicker select{font:inherit;color:var(--ink);background:var(--panel);
  border:1px solid var(--line);border-radius:5px;padding:2px 6px}
.telup{color:var(--file);font-weight:600}
.teldown{color:var(--warn);font-weight:600}
#view-index h3{margin:22px 0 6px;font-size:15px;font-weight:700;color:var(--accent);
  font-family:var(--mono);border-bottom:1px solid var(--line);padding-bottom:3px}
.ixjump{display:flex;flex-wrap:wrap;gap:3px;margin:0 0 6px;position:sticky;top:0;
  background:var(--bg);padding:6px 0;z-index:2}
.ixjump a{font-family:var(--mono);font-size:12.5px;padding:2px 7px;border-radius:5px;
  border:1px solid var(--line);color:var(--accent);cursor:pointer;text-decoration:none}
.ixjump a:hover{border-color:var(--accent);background:var(--accent-soft)}
.ixlist li{display:flex;align-items:baseline;gap:8px;flex-wrap:wrap;padding:3px 0}
.ixtag{font-size:9.5px;text-transform:uppercase;letter-spacing:.05em;color:var(--muted);
  border:1px solid var(--line);border-radius:4px;padding:0 4px}
.ixtag.dep{color:var(--error);border-color:var(--error)}
.ixtag.tested{color:var(--accent);border-color:var(--accent)}
#view-hierarchy{padding:16px 24px 60px}
.hctl{display:flex;gap:8px;align-items:center;margin-bottom:14px;flex-wrap:wrap}
.hctl .hpath{font-family:var(--mono);font-size:12.5px;color:var(--muted);word-break:break-all}
.hctl button{padding:4px 9px;font-size:12.5px}
#hgraph-outer{position:relative}
/* `max-height` is not optional here — same `calc(100vh - 132px)` #detail
   and #hist-detail already cap themselves at, reused rather than
   invented. Without it `overflow:auto` has nothing to overflow *against*:
   a block with no height constraint sizes to its content, so as
   `applyZoom()` grows #hgraph's own width/height to match the scaled
   diagram, #hgraph-wrap (and everything containing it, up to the page
   itself) grew right along with it instead of clipping the content
   behind scrollbars. Reported exactly that way, watching someone zoom in
   and the whole page grow under them rather than the diagram zooming
   within a fixed frame — the zoom math itself (cursor-anchored, see
   zoomAt()) was already correct; this was the one property missing that
   let it actually behave like a viewport. */
#hgraph-wrap{overflow:auto;border:1px solid var(--line);border-radius:8px;
  background:var(--panel);max-height:calc(100vh - 132px)}
/* Root-level hide/show slider (Modules view only) — a vertical Google
   Maps-style control: "+" hides one more layer (zooming into a narrower
   slice of the tree), "-" shows one more (zooming back out). Positioned
   against #hgraph-outer, not #hgraph-wrap, so it stays put while the
   diagram underneath scrolls.

   Reported, watching someone use the page for the first time: this reads
   as an actual zoom control, not a tree-depth one — the vertical
   range-input shape and the "+"/"-" pair are exactly what a real zoom
   widget would look like, and this comment's own "zooming into a
   narrower slice" phrasing shows why: the word applies here only as a
   metaphor. `.hrootslider-label` exists because the tooltip
   (`title="Hide root levels…"`) was the only place that said so, and
   nobody hovers a control to find out what it does before deciding
   whether to use it. */
.hrootslider{position:absolute;left:10px;top:14px;z-index:20;display:none;
  flex-direction:column;align-items:center;gap:4px;background:var(--panel);
  border:1px solid var(--line);border-radius:8px;padding:8px 6px;
  box-shadow:0 2px 8px rgba(0,0,0,.14)}
.hrootslider.on{display:flex}
.hrootslider-label{font-size:9.5px;text-transform:uppercase;letter-spacing:.05em;
  color:var(--muted);white-space:nowrap;margin-bottom:1px}
.hroot-btn{width:22px;height:22px;padding:0;border:1px solid var(--line);
  border-radius:5px;background:var(--bg);color:var(--ink);font-size:14px;
  line-height:1;cursor:pointer;display:flex;align-items:center;justify-content:center}
.hroot-btn:hover:not(:disabled){border-color:var(--accent);color:var(--accent)}
.hroot-btn:disabled{opacity:.35;cursor:default}
/* `writing-mode:vertical-lr` turns a plain range input vertical with no JS
   transform hack — min renders at the bottom, max at the top, which is
   exactly "+" (more hidden, higher value) above "-" (less hidden, lower
   value) without any extra flipping. */
#hrootrange{writing-mode:vertical-lr;width:20px;height:84px;margin:2px 0;
  cursor:pointer;accent-color:var(--accent)}
/* Middle-drag panning. `grabbing` only while a drag is live — a permanent
   grab cursor would advertise left-drag panning, which is deliberately not
   what this does. `user-select:none` is on the dragging state only, so text
   in the boxes stays selectable the rest of the time. */
#hgraph-wrap.panning{cursor:grabbing;user-select:none}
#hgraph{position:relative}
/* The zoom lives on its own layer. #hstage carries the transform and keeps the
   analytic pixel layout; #hgraph is sized to the *scaled* extent, because a
   transform does not change layout size and the scroll area would otherwise
   not grow when zooming in. */
#hstage{position:absolute;top:0;left:0;transform-origin:0 0;will-change:transform}
#hstage.zooming{transition:none}
#hstage.jumping{transition:transform .34s cubic-bezier(.2,.7,.2,1)}
/* Level of detail: below ~0.65 the secondary line is unreadable grey noise,
   so it goes away rather than being rendered illegibly. Pure CSS — no redraw. */
#hstage.lod-min .hsm,#hstage.lod-min .hline,#hstage.lod-min .hkind{display:none}
#hstage.lod-min .hnode{padding:4px 8px}
.hzoom{font-family:var(--mono);font-size:11.5px;color:var(--muted);min-width:44px;
  text-align:right}
@media (prefers-reduced-motion:reduce){#hstage.jumping{transition:none}}
.hnode{position:absolute;box-sizing:border-box;padding:7px 10px;border:1px solid var(--line);
  border-radius:7px;background:var(--panel);cursor:pointer;overflow:hidden}
.hnode:hover{border-color:var(--accent);z-index:1}
/* Pinned: the focus is being held rather than followed. A ring rather than
   a different colour, because the box keeps whatever its language and kind
   already say about it — this adds a state, it does not replace one. Without
   it, a held focus and a hovered one look identical and the reader cannot
   tell whether moving the mouse will cost them the view. */
.hnode.pinned{border-color:var(--accent);box-shadow:0 0 0 2px var(--accent-soft);z-index:2}
.hnode .hnm{font-family:var(--mono);font-size:12.5px;font-weight:600;white-space:nowrap;
  overflow:hidden;text-overflow:ellipsis}
.hnode .hsm{font-size:10.5px;color:var(--muted);margin-top:2px;max-height:2.6em;overflow:hidden}
.hnode.k-module .hnm{color:var(--mod)} .hnode.k-namespace .hnm{color:var(--ns)} .hnode.k-file .hnm{color:var(--file)}
#hsvg{position:absolute;top:0;left:0;pointer-events:none}
.hedge{fill:none;stroke:var(--muted);stroke-width:1.5;opacity:.6}
.hedge-type{stroke:var(--accent);stroke-dasharray:4 3;opacity:.75}
.hedge-ext{stroke:var(--ext);stroke-width:2;opacity:.9}
.hmsg{color:var(--muted);font-size:13px;padding:20px;text-align:center}
.htrunc{color:var(--warn);font-size:12.5px;margin-top:8px}
/* Sits directly before `#hdepth`'s button group. "1"/"2"/"3"/"∞" alone
   read as a slider or a zoom control — reported exactly that way after
   watching someone use the page for the first time — because every other
   number on this toolbar (`#hzoomlabel`) *is* a percentage. Direction and
   view-switcher groups need no such label; their own button text
   ("← In", "Out →", "Modules") already says what they do. */
.hctl-label{font-size:11.5px;text-transform:uppercase;letter-spacing:.06em;
  color:var(--muted);align-self:center}
.hview-toggle{display:flex;gap:0;border:1px solid var(--line);border-radius:7px;overflow:hidden}
.hview-toggle button{border:none;border-radius:0;padding:4px 10px;font-size:12.5px}
.hview-toggle button+button{border-left:1px solid var(--line)}
.hview-toggle button.active{background:var(--accent-soft);color:var(--accent);font-weight:600}
/* Marks a panel/mode that only does anything when a soft-dependency plugin
   (or, for Tools, a project-level manifest file) is present -- same signal
   `--ext` already carries for "connects outside this map" in the Hierarchy
   graphs, reused here for "depends on something outside this plugin". The
   badge is the primary cue (readable even without color); the tint is a
   second one for a quick scan of the tab bar. */
.hview-toggle button.plugin-gated{color:var(--ext)}
.hview-toggle button.plugin-gated::after{content:"\1F50C";font-size:9.5px;margin-left:3px;opacity:.85}
.hview-toggle button.plugin-gated.active{background:var(--ext);color:var(--bg);font-weight:600}
.hnode.t-class .hnm{color:var(--mod)}
.hnode.t-alias .hnm{color:var(--ns)}
.hnode .hkind{font-size:9.5px;text-transform:uppercase;letter-spacing:.05em;color:var(--muted);margin-top:1px}
/* --- Stats grid + module-scope symbols in the detail pane --------------- */
.stat-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(96px,1fr));gap:7px;
  margin-bottom:6px}
.stat{border:1px solid var(--line);border-radius:7px;padding:6px 9px;background:var(--panel)}
.stat b{display:block;font-size:15px;font-weight:650;font-family:var(--mono)}
.stat span{font-size:10.5px;color:var(--muted)}
.sec .sub{text-transform:none;letter-spacing:0;font-weight:400;font-size:10.5px}
.lst.syms li{padding:4px 0;color:var(--ink)}
.sdet{color:var(--muted);font-size:11.5px;font-family:var(--mono)}
.bd.sk-table{color:var(--mod);border-color:var(--mod)}
.bd.sk-constant{color:var(--file);border-color:var(--file)}
.bd.sk-binding{color:var(--ns)}
#findings tbody tr[data-node]{cursor:pointer}
#findings tbody tr[data-node]:hover{background:var(--accent-soft)}
/* --- Quicks ------------------------------------------------------------- */
.qk-wrap{padding:18px 24px;max-width:1100px}
.qk-col{margin-bottom:22px}
.qk-h{font-size:12.5px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);
  margin-bottom:9px}
.qk{border:1px solid var(--line);border-left-width:3px;border-radius:8px;background:var(--panel);
  padding:11px 14px;margin-bottom:8px}
.qk.good{border-left-color:var(--ok,#3f9142)}
.qk.bad{border-left-color:var(--error)}
.qk-head{display:flex;align-items:baseline;gap:10px;flex-wrap:wrap}
.qk-line{font-size:14px;font-weight:600;color:var(--ink)}
.qk-val{font-family:var(--mono);font-size:12.5px;color:var(--muted);white-space:nowrap}
/* The reason a verdict is allowed to be a sentence at all — see quicks.lua's
   header. Quieter than the sentence, never hidden behind a disclosure. */
.qk-basis{font-size:11.5px;color:var(--muted);margin-top:5px;line-height:1.45}
.qk-acts{margin-top:8px;display:flex;gap:7px;flex-wrap:wrap}
.qk-acts button{font-size:11.5px;padding:3px 9px}
.qk-none{color:var(--muted);font-size:13px;padding:6px 0}
/* --- Compare marks ------------------------------------------------------ */
/* Sits beside `.sigi` rather than replacing its click: that click already
   pins the annotation popup open, which is what makes a long `@example`
   readable, and taking it over would trade one affordance for another. */
.marki{display:inline-block;margin-left:3px;padding:0 4px;border-radius:4px;cursor:pointer;
  font-size:10.5px;line-height:15px;color:var(--muted);border:1px solid var(--line);
  opacity:.45;transition:opacity .12s,color .12s,background .12s;user-select:none}
.marki:hover,.marki:focus{opacity:1;color:var(--accent);border-color:var(--accent);outline:none}
li:hover>.marki,tr:hover .marki{opacity:.8}
.marki.on{opacity:1;color:var(--bg);background:var(--accent);border-color:var(--accent)}
.markbar{white-space:nowrap}
.markbar.has{color:var(--accent);border-color:var(--accent);font-weight:600}
/* --- Compare tab -------------------------------------------------------- */
#cmpbody{padding:14px 24px}
.cmp-cols{display:flex;gap:12px;overflow-x:auto;padding-bottom:8px;align-items:flex-start}
.cmp-cols .cmp-card{flex:0 0 340px}
.cmp-stack .cmp-card{margin-bottom:12px}
.cmp-card{border:1px solid var(--line);border-radius:8px;background:var(--panel);padding:12px 14px}
.cmp-card-h{display:flex;justify-content:space-between;align-items:baseline;gap:8px;
  margin-bottom:6px}
.cmp-where{font-family:var(--mono);font-size:11.5px;color:var(--accent)}
.cmp-drop{border:none;background:none;color:var(--muted);cursor:pointer;font-size:14px;padding:0 3px}
.cmp-drop:hover{color:var(--error)}
.cmptable{width:100%;border-collapse:collapse;font-size:12.5px}
.cmptable th,.cmptable td{border:1px solid var(--line);padding:6px 9px;text-align:left;
  vertical-align:top}
.cmptable thead th{background:var(--panel);position:sticky;top:0;font-size:11.5px}
.cmptable tbody th{background:var(--panel);font-weight:600;color:var(--muted);
  font-size:11.5px;white-space:nowrap}
/* The point of the matrix: a row where every marked object agrees is not what
   the reader came for, so the ones that differ are the ones that are lit. */
.cmptable tr.differs td{background:var(--accent-soft)}
.cmptable tr.differs th{color:var(--ink)}
.cmp-scroll{overflow-x:auto}

/* --- Function rows in the tree ------------------------------------------ */
.row.k-fn .nm{color:var(--fn)}
.row.fnhead .nm{color:var(--muted);font-style:italic}
.fnkids.hide{display:none}

/* --- Graph: edge kinds, arrowheads, legend ------------------------------ */
.hedge-dep{stroke:var(--dep);opacity:.8}
.hedge-dep.deferred{stroke-dasharray:2 4;opacity:.55}
.hedge-dep.external{stroke-dasharray:6 3;opacity:.5}
.hnode.k-external{border-style:dashed;background:none}
.hnode.k-external .hnm{color:var(--muted)}
.hnode.k-external.linked{border-style:solid;border-color:var(--accent)}
.hnode.k-external.linked .hnm{color:var(--accent)}
.hlegend .sw.dep.external{border-top-style:dashed}
#hext.active button{background:var(--accent-soft);color:var(--accent);font-weight:600}
#hgest.active button{background:var(--accent-soft);color:var(--accent);font-weight:600}
.hedge-call{stroke:var(--call);opacity:.8}
.hedge-call.weak{stroke-dasharray:3 4;opacity:.5}
/* An invisible, much wider companion path per edge. A 1.5px line is a 1.5px
   hover target, which is not a target — the weighted Module Calls edges made
   that obvious, since the thing worth reading (how many calls, which way) was
   hardest to point at on the thinnest edges. `stroke:transparent` rather than
   `opacity:0`: an `opacity:0` element still paints nothing *and* still takes
   pointer events, but reads to a future editor as "hidden, delete me".
   `pointer-events:stroke` is not optional here — #hsvg itself is
   `pointer-events:none` (so the HTML boxes stacked on top of the SVG stay
   clickable through it), and every path inside inherits that unless it
   opts back in. Missed the first time, and invisible to any test that
   fires the handler directly instead of a real hit-tested mouse event:
   `element.dispatchEvent(new MouseEvent(...))` runs the listener
   regardless of `pointer-events`, since that property only gates the
   browser's own hit-testing for real input, not a manually dispatched
   event. `document.elementFromPoint` at a hedge-hit's own screen
   coordinates returned the background `<div>` underneath, never the SVG
   at all, until this line existed. `stroke` rather than `auto`: this
   shape is `fill:none`, so only the stroked band should ever be
   clickable — `auto` happens to behave the same way here, `stroke` says
   so without depending on that being true. */
.hedge-hit{fill:none;stroke:transparent;stroke-width:14;cursor:default;pointer-events:stroke}
/* Edge readout. `position:fixed` for exactly the reason `.sigpop` is: the
   graph lives in a pannable, zoomable stage, and an absolutely-positioned
   card would ride along with that transform instead of staying by the
   cursor. `pointer-events:none` so it can never sit between the cursor and
   the edge it describes and flicker the hover off. */
.hedge-tip{position:fixed;z-index:60;display:none;pointer-events:none;
  background:var(--bg);border:1px solid var(--line);border-radius:6px;
  box-shadow:0 6px 20px rgba(0,0,0,.18);padding:6px 9px;font-size:11.5px;
  max-width:300px;line-height:1.5}
.hedge-tip.on{display:block}
.hedge-tip .et-row{white-space:nowrap;font-family:var(--mono);color:var(--ink)}
.hedge-tip .et-n{font-weight:650;color:var(--call)}
/* The reverse direction, when the pair calls both ways. Muted because it is
   context for the edge under the cursor, not the edge itself. */
.hedge-tip .et-back{color:var(--muted)}
.hedge-tip .et-back .et-n{color:var(--muted)}
#hsvg marker path{stroke:none}
#m-tree path{fill:var(--muted)}
#m-type path{fill:var(--accent)}
#m-ext path{fill:var(--ext)}
#m-dep path{fill:var(--dep)}
#m-call path{fill:var(--call)}
.hlegend{display:flex;gap:12px;flex-wrap:wrap;align-items:center;margin:10px 0 0;
  font-size:11.5px;color:var(--muted)}
.hlegend .lg{display:inline-flex;align-items:center;gap:5px}
.hlegend .sw{width:20px;height:0;border-top:2px solid var(--muted)}
.hlegend .sw.type{border-top-style:dashed;border-top-color:var(--accent)}
.hlegend .sw.ext{border-top-color:var(--ext);border-top-width:3px}
.hlegend .sw.dep{border-top-color:var(--dep)}
.hlegend .sw.dep.deferred{border-top-style:dotted}
.hlegend .sw.call{border-top-color:var(--call)}
.hlegend .sw.call.weak{border-top-style:dashed}
.hlegend .bx{width:11px;height:11px;border-radius:3px;border:1px solid currentColor}
.hnode.k-fn .hnm{color:var(--fn)}
.hnode.center{border-color:var(--accent);box-shadow:0 0 0 2px var(--accent-soft)}
.hnode .hline{font-size:9.5px;color:var(--muted);margin-top:1px;font-family:var(--mono)}

/* --- Graph: movement ---------------------------------------------------
   Boxes keep their identity across redraws (see reconcile() in the JS), so a
   re-center animates the boxes that survive from their old position to their
   new one instead of the whole diagram cutting. left/top are transitioned
   rather than transform, because positions are already absolute pixels
   computed from the IR — a transform would need a second coordinate system
   for no gain. */
.hnode{transition:left .34s cubic-bezier(.2,.7,.2,1),top .34s cubic-bezier(.2,.7,.2,1),
  opacity .22s ease,border-color .15s ease}
.hnode.entering{opacity:0;transform:scale(.94)}
.hnode.leaving{opacity:0;pointer-events:none}
#hsvg{transition:opacity .18s ease}
#hsvg.settling{opacity:0}
.hnode.pulse{animation:hpulse .7s ease-out}
@keyframes hpulse{
  0%{box-shadow:0 0 0 0 var(--accent)}
  100%{box-shadow:0 0 0 12px transparent}
}
/* Hover focus: dim everything that is not a direct neighbour. Class-driven so
   it costs no layout recomputation on a graph that can hold 90 boxes. */
#hgraph.focusing .hnode{opacity:.22}
#hgraph.focusing .hnode.near{opacity:1}
#hgraph.focusing .hedge{opacity:.08}
#hgraph.focusing .hedge.near{opacity:1;stroke-width:2}
/* Persistent per-box dim (":DocMap"'s "hide/dim a module" — see the JS
   section above this one for the state it reads). Same opacity mechanism as
   hover-focus, deliberately independent of it: a dimmed box has to stay
   dimmed even when hover-focus would otherwise light it up as a ".near"
   neighbour, which is why both overrides below repeat the "#hgraph.focusing"
   prefix — equal specificity to the rules above, decided by source order. */
.hnode.hidden{opacity:.08;pointer-events:none}
#hgraph.focusing .hnode.hidden{opacity:.08}
#hgraph.focusing .hnode.hidden.near{opacity:.08}
.hedge{transition:opacity .15s ease}
@media (prefers-reduced-motion:reduce){
  .hnode,#hsvg,.hedge{transition:none}
  .hnode.pulse{animation:none}
}

/* --- Context menu ------------------------------------------------------- */
#ctx{position:fixed;z-index:50;min-width:210px;padding:5px;border:1px solid var(--line);
  border-radius:9px;background:var(--panel);box-shadow:0 8px 28px rgba(0,0,0,.18);display:none}
#ctx.open{display:block}
#ctx .ci{display:flex;align-items:center;gap:8px;padding:6px 10px;border-radius:6px;
  font-size:12.5px;cursor:pointer;white-space:nowrap;color:var(--ink)}
#ctx .ci:hover,#ctx .ci.hi{background:var(--accent-soft);color:var(--accent)}
#ctx .ci.disabled{color:var(--muted);cursor:default;opacity:.6}
#ctx .ci.disabled:hover{background:none;color:var(--muted)}
#ctx .ci .hint{margin-left:auto;font-size:10.5px;color:var(--muted)}
#ctx .sep{height:1px;background:var(--line);margin:4px 6px}
#ctx .hdr{padding:5px 10px 6px;font-family:var(--mono);font-size:11.5px;color:var(--muted);
  max-width:280px;overflow:hidden;text-overflow:ellipsis}
]]

local JS = [[
(function(){
  var IR = JSON.parse(document.getElementById("ir").textContent);
  var FIND = JSON.parse(document.getElementById("findings-data").textContent);
  var byId = {}; IR.nodes.forEach(function(n){ byId[n.id] = n; });

  var findByNode = {};
  FIND.forEach(function(f){ if(!f.node) return;
    (findByNode[f.node] = findByNode[f.node] || []).push(f); });

  // className -> { info: Documentation.TypeInfo, nodeId: owning node id }. Built
  // once so the Types hierarchy view and any class lookup can go straight to
  // a class by name instead of re-scanning every node's types_detail.
  var classByName = {};
  IR.nodes.forEach(function(n){
    (n.types_detail || []).forEach(function(t){ classByName[t.name] = { info: t, nodeId: n.id }; });
  });

  // ---------------------------------------------------------------------
  // Functions as first-class, addressable objects.
  //
  // "<node id>#<declared name>" — derivable from data already in the IR, so
  // no id has to be generated and serialized, and stable across regenerations
  // as long as the function keeps its name. This is what makes a function
  // something the URL can point at, the Calls view can center on, and the
  // context menu can act on; before it, a function existed only as a block of
  // text inside one node's detail pane.
  // ---------------------------------------------------------------------
  function fnKey(nodeId, name){ return nodeId + "#" + name; }

  var fnByKey = {};
  IR.nodes.forEach(function(n){
    (n.functions || []).forEach(function(fn){
      fnByKey[fnKey(n.id, fn.name)] = { node: n, fn: fn, key: fnKey(n.id, fn.name) };
    });
  });

  // =====================================================================
  // Compare marks
  //
  // A mark is a key — a node id, or `fnKey(nodeId, name)` — the reader has
  // set aside to look at next to others. Deliberately the *same* key scheme
  // `sigTrigger`, the context menu and `quicks.evidence` already speak, which
  // is what makes "mark every function behind this verdict" a one-liner
  // instead of a translation layer.
  //
  // The trigger is its own control beside the `ⓘ`, not a new meaning for
  // clicking it. That click already pins the annotation popup open, which is
  // the thing that makes a long `@example` readable at all; taking it over
  // would have traded one affordance for another and called it a feature.
  // =====================================================================
  function markExists(key){ return !!(fnByKey[key] || byId[key]); }

  // Scoped to this artifact's own path. Two projects' maps open in the same
  // browser are two different trees, and a shared key would leak one's marks
  // into the other's page.
  var MARKS_LS_KEY = "docmap:marks:" + location.pathname;

  function loadMarks(){
    try {
      var raw = localStorage.getItem(MARKS_LS_KEY);
      if(!raw) return [];
      return JSON.parse(raw).filter(markExists);
    } catch(e){
      // Private-mode localStorage throws on read in some browsers, and a
      // corrupt value is not worth a broken page over a convenience feature.
      return [];
    }
  }

  function saveMarks(list){
    try { localStorage.setItem(MARKS_LS_KEY, JSON.stringify(list)); } catch(e){ void 0; }
  }

  function isMarked(key){ return state.marks.indexOf(key) !== -1; }

  // Marks do not go through `navigate`: toggling one is not a navigation, and
  // pushing a history entry per mark would bury the actual navigation the
  // reader wants Back to return to under a stack of selection noise. The hash
  // is still updated — in place — so the link in the address bar is always
  // shareable and always current.
  function toggleMark(key){
    if(!markExists(key)) return;
    var i = state.marks.indexOf(key);
    if(i === -1) state.marks.push(key); else state.marks.splice(i, 1);
    state.marks.sort();
    saveMarks(state.marks);
    syncMarks();
    history.replaceState(state, "", serializeState(state));
    if(state.tab === "compare") drawCompare();
  }

  function addMarks(keys){
    var changed = false;
    keys.forEach(function(k){
      if(markExists(k) && state.marks.indexOf(k) === -1){ state.marks.push(k); changed = true; }
    });
    if(!changed) return;
    state.marks.sort();
    saveMarks(state.marks);
    syncMarks();
    history.replaceState(state, "", serializeState(state));
  }

  function clearMarks(){
    if(!state.marks.length) return;
    state.marks = [];
    saveMarks(state.marks);
    syncMarks();
    history.replaceState(state, "", serializeState(state));
    if(state.tab === "compare") drawCompare();
  }

  // The affordance itself. Rendered beside every `sigTrigger`, and on its own
  // for a module (which has annotations but no signature to hang a `ⓘ` off).
  function markTrigger(key){
    return '<span class="marki" tabindex="0" role="button" data-mark="' + esc(key) +
      '" aria-label="Mark for comparison" title="Mark for comparison">&#43;</span>';
  }

  // Paints mark state onto whatever is currently in the DOM, and keeps the
  // toolbar counter honest. Called after every redraw rather than having each
  // renderer remember to emit an `on` class — one place to be right.
  function syncMarks(){
    document.querySelectorAll("[data-mark]").forEach(function(el){
      el.classList.toggle("on", isMarked(el.dataset.mark));
    });
    var bar = document.getElementById("markbar");
    if(!bar) return;
    var n = state.marks.length;
    bar.hidden = n === 0;
    bar.classList.toggle("has", n > 0);
    bar.textContent = "Compare (" + n + ")";
    bar.title = n + " marked object" + (n === 1 ? "" : "s") + " — open the Compare tab";
  }

  // Same "paint whatever is on screen" role as syncMarks, over `hboxes`
  // instead of a `[data-mark]` query — a Hierarchy box's key already sits on
  // its own element (`el.dataset.key`, set by reconcile()), so iterating
  // `hboxes` directly reaches every box without a second lookup. A no-op
  // on every tab but Hierarchy (`hboxes` is empty until drawHierarchy runs
  // at least once), which is why this is safe to call unconditionally from
  // applyState alongside syncMarks rather than gated on `state.tab`.
  // Boxes are created and destroyed by `reconcile()` on every redraw, so a
  // class set once does not survive a view switch or a re-centre. Painted
  // alongside `syncHidden` for exactly that reason -- same problem, same
  // solution, same call sites.
  function syncHidden(){
    Object.keys(hboxes).forEach(function(key){
      hboxes[key].classList.toggle("hidden", isHidden(key));
    });
    var bar = document.getElementById("hiddenbar");
    if(!bar) return;
    var n = state.hidden.length;
    bar.hidden = n === 0;
    bar.classList.toggle("has", n > 0);
    bar.textContent = "Hidden (" + n + ") — show all";
    bar.title = n + " box" + (n === 1 ? "" : "es") +
      " dimmed in the Hierarchy view — click to show them again";
  }

  // =====================================================================
  // Hierarchy hide/dim
  //
  // A box in the Hierarchy graph, set aside so it stops competing for
  // attention in a large tree — never removed from the layout (that would
  // mean re-flowing the tree's remaining boxes, and possibly reparenting
  // its children, every time one is toggled), just dimmed to near-zero
  // opacity and taken out of pointer interaction. "Ausblenden/abdunkeln"
  // in the roadmap item this ships — reads as fully hidden, implemented as
  // a strong dim, so a reader who forgot what was under a dimmed box can
  // still make out its outline rather than wondering what used to be there.
  //
  // Keyed the same as `hboxes`/`positions`/`boxSpec` — a node id, a class
  // name (Types/Inheritance), or an `fnKey` (Calls) — so one mechanism
  // covers all five Hierarchy views without a per-view special case.
  //
  // State shape and persistence deliberately mirror Compare marks above:
  // same array-of-keys shape, same per-path localStorage scoping, same
  // hash-wins-over-localStorage precedence on initial load (see the load
  // at the bottom of this script). Not unified into one mechanism with
  // marks, because the two answer different questions — "compare these"
  // vs. "stop showing me that" — and a reader marking a function for
  // comparison has no reason to expect it to also disappear from a graph.
  // =====================================================================
  function hiddenKeyExists(key){
    return !!(byId[key] || classByName[key] || fnByKey[key]);
  }

  var HIDDEN_LS_KEY = "docmap:hidden:" + location.pathname;

  function loadHidden(){
    try {
      var raw = localStorage.getItem(HIDDEN_LS_KEY);
      if(!raw) return [];
      return JSON.parse(raw).filter(hiddenKeyExists);
    } catch(e){
      return [];
    }
  }

  function saveHidden(list){
    try { localStorage.setItem(HIDDEN_LS_KEY, JSON.stringify(list)); } catch(e){ void 0; }
  }

  function isHidden(key){ return state.hidden.indexOf(key) !== -1; }

  // Same "not a navigation" reasoning as toggleMark: updates the hash in
  // place via replaceState rather than pushState, so dimming ten boxes
  // while decluttering a tree does not bury the navigation the reader
  // actually wants Back to return to under ten selection-noise entries.
  function toggleHidden(key){
    if(!hiddenKeyExists(key)) return;
    var i = state.hidden.indexOf(key);
    if(i === -1) state.hidden.push(key); else state.hidden.splice(i, 1);
    state.hidden.sort();
    saveHidden(state.hidden);
    syncHidden();
    syncLangFilter();
    history.replaceState(state, "", serializeState(state));
  }

  function clearHidden(){
    if(!state.hidden.length) return;
    state.hidden = [];
    saveHidden(state.hidden);
    syncHidden();
    syncLangFilter();
    history.replaceState(state, "", serializeState(state));
  }

  // Blast radius: the transitive closure of `required_by`. Already implied
  // by the edges and visible nowhere, and it is the number that says how
  // risky a change to a module is — the same measurement before and after a
  // refactor is evidence that the refactor decoupled something.
  var impactCache = {};
  function impactOf(id){
    if(impactCache[id]) return impactCache[id];
    var seen = {}, queue = [id], qi = 0, out = [];
    seen[id] = true;
    while(qi < queue.length){
      var cur = queue[qi++];
      ((byId[cur] || {}).required_by || []).forEach(function(dep){
        if(seen[dep]) return;
        seen[dep] = true;
        out.push(dep);
        queue.push(dep);
      });
    }
    impactCache[id] = out;
    return out;
  }

  // Tree-wide, not scoped to whatever subgraph the Deps view currently has
  // centered — an external box means the same thing regardless of which
  // node you walked in from, and a count that changed as you re-centered
  // would read as a bug, not a feature. Computed once, lazily, off
  // `n.calls_external` (per-node, from `core/calls.lua`) rather than a
  // second pass over anything — the counting already happened in Lua.
  var externalCallTotals = null;
  function getExternalCallTotals(){
    if(externalCallTotals) return externalCallTotals;
    externalCallTotals = {};
    IR.nodes.forEach(function(n){
      (n.calls_external || []).forEach(function(c){
        var byMember = externalCallTotals[c.module] || (externalCallTotals[c.module] = {});
        var mkey = c.member || "";
        byMember[mkey] = (byMember[mkey] || 0) + c.count;
      });
    });
    return externalCallTotals;
  }

  // Edges arrive as one array with a `kind` discriminator; every consumer
  // wants one kind at a time, and both directions of it. Built once here
  // rather than filtered per redraw — a re-center at depth 3 would otherwise
  // walk all ~1300 edges once per layer.
  var depOut = {}, depIn = {}, callOut = {}, callIn = {}, typeEdges = [];
  // Inheritance, keyed both ways by class name: `extUp` answers "who are my
  // parents", `extDown` "who inherits me". An edge is stored as written
  // (from_class = the child, to_class = the parent), so which end is "next"
  // depends on which map you came in through — see layoutInheritance.
  var extUp = {}, extDown = {}, extendsEdges = [];
  // Module Calls view: the same "call" edges above, collapsed from
  // function-to-function to module-to-module and counted, so five call
  // sites between two modules draw one weighted edge, not five overlapping
  // ones. Built by reference: `moduleCallOut[id]` and `moduleCallIn[id]`
  // for a given pair share the *same* edge object, so incrementing
  // `.weight` once updates whichever side a walk finds it from. Self-edges
  // (two functions in the same file calling each other) are dropped — a
  // module graph has nothing to say about a module calling itself.
  var moduleCallOut = {}, moduleCallIn = {}, moduleCallEdgeByPair = {};
  function push(map, key, val){ (map[key] = map[key] || []).push(val); }
  (IR.edges || []).forEach(function(e){
    if(e.kind === "require"){
      push(depOut, e.from, e); push(depIn, e.to, e);
    } else if(e.kind === "call"){
      push(callOut, fnKey(e.from, e.from_fn), e);
      push(callIn, fnKey(e.to, e.to_fn), e);
      if(e.from !== e.to){
        var pairKey = e.from + " " + e.to;
        var mcEdge = moduleCallEdgeByPair[pairKey];
        if(!mcEdge){
          mcEdge = { from: e.from, to: e.to, weight: 0 };
          moduleCallEdgeByPair[pairKey] = mcEdge;
          push(moduleCallOut, e.from, mcEdge);
          push(moduleCallIn, e.to, mcEdge);
        }
        mcEdge.weight++;
      }
    } else if(e.kind === "type"){
      typeEdges.push(e);
    } else if(e.kind === "extends"){
      extendsEdges.push(e);
      push(extUp, e.from_class, e);
      push(extDown, e.to_class, e);
    }
  });

  // Classes that take part in at least one inheritance relation. The
  // Inheritance view seeds from these rather than from every class the
  // centered node declares: a class with no parent and no subclass is an
  // isolated box in a view that exists to show relationships, and most nodes
  // declare several of those — they would crowd out the handful of boxes that
  // actually connect.
  var inInheritance = {};
  extendsEdges.forEach(function(e){
    inInheritance[e.from_class] = true;
    inInheritance[e.to_class] = true;
  });

  // @see target -> owning node id. Same three resolution shapes as
  // docmap.check's check_see_targets, kept in sync deliberately: a bare
  // module path, "module.bareName" (the qualified form a reader would
  // actually write), and the raw declared name (e.g. "M.scan_full") as a
  // fallback for targets copy-pasted straight from source.
  var seeIndex = {};
  IR.nodes.forEach(function(n){
    if(n.module) seeIndex[n.module] = n.id;
    (n.functions || []).forEach(function(fn){
      seeIndex[fn.name] = n.id;
      if(n.module){
        var bare = fn.name.replace(/^[A-Z][\w]*\./, "");
        seeIndex[n.module + "." + bare] = n.id;
      }
    });
  });

  var repo = IR.meta.repo_url, branch = IR.meta.branch || "main";
  function srcUrl(p){ return repo ? repo + "/blob/" + branch + "/" + p : null; }

  function esc(s){ return (s||"").replace(/[&<>"]/g, function(c){
    return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]; }); }

  // Prose from a doc-comment, with its inline code rendered.
  //
  // **The doc-comments have always been markdown; this page was the one
  // output that showed it as text.** A summary reading "Registers the single
  // `:Debug` user command" arrived in the Hierarchy boxes with the backticks
  // visible. Measured on this repository: **432 summaries carry backticks**
  // — the rule rather than an edge. `overview.md` renders them correctly and
  // always has, because markdown does it natively, so the page was behind
  // its own sibling output.
  //
  // **Escaping first is not a detail, it is the whole safety argument.** A
  // summary is author-controlled text that ends up as innerHTML. `esc` runs
  // over the entire string before a single tag is introduced, and the only
  // tags this can then produce are the `<code>` pair it writes itself —
  // there is no path from source text to markup, because by the time the
  // backtick scan runs, every `<` in the input is already `&lt;`.
  //
  // Double backticks first, so ``a ` b`` — markdown's way of putting a
  // backtick inside code — is not read as two separate single-backtick
  // spans. **Non-greedy and character-agnostic**, because the first attempt
  // was neither and got the one case it exists for wrong: `[^`]+` forbids
  // the very character the double-backtick form is for, so this tree's own
  // "``\`[text](url)\``` in \`FEATURES_FORMAT.md\`" came out as `<code>`
  // wrapped around the spaces between the ticks. Found by reading the
  // rendered DOM, not the regex.
  //
  // **One pass, not two**, and that is the second thing rendering caught.
  // Run separately, the single-backtick pass reads the double-backtick
  // pass's own output and turns the ticks it deliberately preserved into a
  // nested `<code><code>…</code></code>`. One alternation consumes each
  // position exactly once, so the scanner never re-reads what it wrote.
  //
  // One leading and one trailing space are dropped when both are there,
  // which is what CommonMark does and what makes ``\`x\`` render as the
  // backticked text rather than as a space-padded one.
  //
  // Unpaired backticks are left exactly as written: half a code span is a
  // typo in the source, and silently swallowing the character would hide it.
  // Eleven of this tree's 432 have an odd count, every one of them a summary
  // the scanner truncated mid-span — visible now, which is the point.
  //
  // Fenced blocks are deliberately not handled here. A summary is one line;
  // the multi-line case is `@example`, which is a different surface with a
  // different shape, and doing both in one regex is how you get a renderer
  // nobody can reason about.
  function prose(s){
    var out = esc(s);
    out = out.replace(/``([\s\S]+?)``|`([^`\n]+)`/g, function(_, dbl, single){
      if(dbl === undefined){ return "<code>" + single + "</code>"; }
      var code = dbl;
      if(code.length > 2 && code[0] === " " && code[code.length - 1] === " "){
        code = code.slice(1, -1);
      }
      return "<code>" + code + "</code>";
    });
    return out;
  }

  // The affordance that opens the annotation popup, for any list that shows
  // a function. `tabindex` because a keyboard reader must be able to reach
  // it; `aria-label` rather than `title` because a native tooltip would open
  // *beside* the card this control exists to open, saying less.
  // Emits the mark trigger alongside, rather than making six call sites
  // remember to render both. The two controls are a pair — "tell me about
  // this" and "set this aside" — and a list that grew one without the other
  // would be a list the compare tab silently cannot reach.
  function sigTrigger(nodeId, fnName){
    var key = fnKey(nodeId, fnName);
    return '<span class="sigi" tabindex="0" role="button" aria-label="Annotations"' +
      ' data-sig="' + esc(key) + '">&#9432;</span>' + markTrigger(key);
  }

  var DOCREFS = (IR.docs && IR.docs.refs) || {};

  // The same affordance for prose references, and deliberately **only
  // rendered when there are some**. An always-present icon that is usually
  // empty trains the reader to ignore it; one that appears exactly when a
  // document mentions this thing is itself the signal, before it is clicked.
  // `key` is a node id for a module or `nodeId#fnName` for a function — the
  // shape `docs.lua` files references under.
  function docTrigger(key){
    var refs = DOCREFS[key];
    if(!refs || !refs.length) return "";
    return '<span class="doci" tabindex="0" role="button" data-doc="' + esc(key) +
      '" aria-label="Mentioned in ' + refs.length + ' place' +
      (refs.length === 1 ? '' : 's') + ' in the docs">&#182;' +
      (refs.length > 1 ? '<span class="docn">' + refs.length + '</span>' : '') + '</span>';
  }

  // =====================================================================
  // Compiler Explorer (opts.godbolt, experimental, session 2026-08-10) —
  // a genuine `luac -l -l -p` bytecode disassembly for Lua, not a
  // workaround: verified against Compiler Explorer's own `/api/languages`
  // (lua is a real language id there) and its compiler source (the "lua"
  // compiler class runs exactly that), after an earlier version of this
  // roadmap item wrongly assumed Lua had no meaningful compiled output to
  // show. `godbolt.org/clientstate/<base64 JSON>` is Compiler Explorer's
  // own documented, fully client-side link format — no API call needed to
  // build one, so opening it is the only network access this feature ever
  // causes, the same posture every other external link on this page
  // (`srcUrl`, `tag_links`) already has.
  //
  // No new IR field: built lazily, on click, from `fn.snippet` — already
  // serialized for the existing hover-preview feature, already bounded the
  // same way `core/snippet.lua` bounds it. A very long function's snippet
  // may be truncated (`snippet_omitted` says by how much); the bytecode
  // Compiler Explorer shows for it is correspondingly a compile of that
  // same truncated fragment — the same honesty the in-page preview already
  // has, not a new limitation this feature introduces. A module's own link
  // concatenates its functions' snippets in declaration order — an
  // approximation of the file, not the file itself (comments/requires/
  // symbols outside a function are not part of any `fn.snippet`), which is
  // why this is marked experimental rather than a byte-perfect "whole
  // project" view — Compiler Explorer's own Lua compiler (`luac`) takes
  // exactly one file per compile in any case; there is no project mode for
  // it the way CMake/C++ has.
  function godboltUrl(source){
    var state = { sessions: [{ id: 1, language: "lua", source: source,
      compilers: [{ id: "lua547", options: "" }] }] };
    // btoa is Latin1-only; encodeURIComponent/unescape is the standard
    // UTF-8-safe detour around that (Lua source can carry UTF-8 in
    // comments/strings). The result then needs the url-safe substitution
    // Compiler Explorer's own clientstate format documents.
    var b64 = btoa(unescape(encodeURIComponent(JSON.stringify(state))))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    return "https://godbolt.org/clientstate/" + b64;
  }

  // Emits nothing at all unless `opts.godbolt` was set at generation time
  // — same "render nothing when not applicable" shape `docTrigger` above
  // already has, just gated by a build-time flag instead of runtime data.
  // The URL itself is *not* built here: constructing and base64-encoding a
  // clientstate JSON for every function/module on a large tree, on every
  // page load, for a link most readers will never click, would be
  // needless work — `kind`/`key` are carried on the element instead, and
  // the real URL is built once, lazily, in the click handler below.
  // Functions only. `kind` is kept on the element because the click handler
  // reads it, not because there is a second kind left to pass.
  //
  // The notice is a real box on hover and on focus, not a `title`. What it
  // has to say is that clicking sends this function's source to a third
  // party — a `title` tooltip is the wrong weight for that, it appears after
  // a delay, never appears for keyboard users, and cannot be read by anyone
  // who is deciding whether to click.
  function godboltTrigger(kind, key){
    if(!IR.meta.godbolt) return "";
    return '<span class="godi-wrap"><a href="#" class="godi" data-godbolt="' + kind +
      '" data-godbolt-key="' + esc(key) + '">⚙ Compiler Explorer ↗</a>' +
      '<span class="godi-tip" role="note"><b>Experimental — leaves your machine.</b> ' +
      'Opens Compiler Explorer in a new tab and hands it this function’s source, so ' +
      'godbolt.org compiles it and shows you real <code>luac</code> bytecode. The code ' +
      'travels inside the link itself: nothing is uploaded ahead of time and nothing is ' +
      'stored there. It is still someone else’s server, and this map has no other ' +
      'outbound request anywhere.</span></span>';
  }

  // Where a mention lives, and the line it sits on. Rendered into the same
  // card the annotation popup uses rather than a second floating thing with
  // its own lifecycle — one set of rules for one page.
  function docRefsHTML(key){
    var refs = DOCREFS[key] || [];
    var h = ['<div class="fn-sig">Mentioned in the docs<span class="fn-badges">' +
      '<span class="bd">' + refs.length + '</span></span></div>'];
    refs.forEach(function(r){
      h.push('<div class="docref">' +
        '<div class="docref-where">' + esc(r.doc) + ':' + r.line +
        (r.confidence === "heuristic"
          ? '<span class="bd" title="matched on a bare, tree-unique name">heuristic</span>'
          : '') +
        '</div>' +
        '<div class="docref-ctx">' + esc(r.context) + '</div></div>');
    });
    if(refs.more){
      h.push('<div class="fn-desc">… and ' + refs.more +
        ' more, not carried into the artifact.</div>');
    }
    return h.join("");
  }

  // Everything a function's annotations say, as HTML: signature line with
  // badges, deprecation, summary, params, returns, overloads, see-also,
  // example.
  //
  // Shared on purpose between the Tree tab's detail pane (which has always
  // rendered this) and the annotation popup (which is the whole reason this
  // was extracted). Two copies of "how a function's annotations look" is
  // exactly the drift this plugin exists to detect, and shipping one inside
  // it would be hard to defend — the same argument the `?` key-hint overlay
  // already makes for rendering from the same KEYS table it binds from.
  //
  // What deliberately stays with the caller: the `<div class="fn">` wrapper
  // and the Calls-view links, both of which only make sense in the detail
  // pane, where `callOut`/`callIn` counts and a stable per-function anchor
  // exist.
  function fnAnnotationHTML(fn){
    var h = [];
    var badges = [];
    // The badges *are* the tags, so they are the third trigger surface of
    // the lookup layer (`ReferenceTab.md` § One layer, four trigger
    // surfaces). A reader who does not know what `nodiscard` promises is
    // looking straight at the word; sending them to a tab to find out is the
    // proximity failure that document warns about.
    //
    // `data-kw` rather than a second popup: the dwell timer, the grace
    // period on the way out, the keyboard path and the flip-when-it-would-
    // overflow positioning all already exist behind that attribute. A
    // tag-specific implementation would be a fourth copy of them.
    function tagBadge(name, label, cls){
      return '<span class="bd' + (cls ? " " + cls : "") + '" data-kw="' + name +
        '" data-kwkind="tag" tabindex="0">' + esc(label) + '</span>';
    }
    if(fn.deprecated !== undefined) badges.push(tagBadge("deprecated", "deprecated", "dep"));
    if(fn.async) badges.push(tagBadge("async", "async"));
    if(fn.nodiscard) badges.push(tagBadge("nodiscard", "nodiscard"));
    if(fn.internal) badges.push(tagBadge("internal", "internal", "sk-binding"));
    if(fn.since) badges.push(tagBadge("since", "since " + fn.since));
    // Visible from the list, not only once the function is opened — the
    // whole point of parsing @overload structurally instead of leaving
    // it as opaque text is to answer "does this have call variants" at a
    // glance, the same way "deprecated"/"async" already do.
    if(fn.overload && fn.overload.length){
      badges.push('<span class="bd">+'+fn.overload.length+' signature'
        +(fn.overload.length===1?'':'s')+'</span>');
    }
    // R2 — auto-derived, coarse and safe in the "tested" direction (see
    // coverage.lua). No badge for the false case: this is a "not found
    // by name in a spec" signal, not "definitely untested", and a
    // warning-shaped badge on the majority of functions would be noise,
    // not information.
    if(fn.tested) badges.push('<span class="bd tested">tested</span>');
    h.push('<div class="fn-sig">'+esc(fn.signature)
      +(badges.length?'<span class="fn-badges">'+badges.join("")+'</span>':'')+'</div>');
    if(fn.deprecated){ h.push('<div class="fn-dep">⚠ Deprecated: '+esc(fn.deprecated)+'</div>'); }
    if(fn.summary){ h.push('<div class="fn-desc">'+prose(fn.summary)+'</div>'); }
    if(fn.params && fn.params.length){
      h.push('<ul class="fn-plist">');
      fn.params.forEach(function(p){
        h.push('<li><code>'+esc(p.name)+(p.optional?'?':'')+'</code> '+esc(p.type)
          +(p.desc?' — '+esc(p.desc):'')+'</li>');
      });
      h.push('</ul>');
    }
    if(fn.returns && fn.returns.length){
      h.push('<ul class="fn-plist">');
      fn.returns.forEach(function(r){
        h.push('<li>→ <code>'+esc(r.type)+'</code>'+(r.name?' '+esc(r.name):'')
          +(r.desc?' — '+esc(r.desc):'')+'</li>');
      });
      h.push('</ul>');
    }
    if(fn.overload && fn.overload.length){
      h.push('<div class="fn-overloads"><div class="fn-ov-label">Also callable as</div>');
      fn.overload.forEach(function(ov){
        if(ov.params.length === 0 && ov.returns.length === 0 && !ov.raw.match(/^fun\s*\(\s*\)/)){
          // Did not parse as fun(...) — shown verbatim rather than as an
          // empty, misleading "fn.name()".
          h.push('<div class="fn-ov-raw">'+esc(ov.raw)+'</div>');
          return;
        }
        // An anonymous LuaCATS param (`fun(string)`, no `name:`) got the
        // placeholder name "_" from parse_overload — shown as its type
        // instead of a bare underscore, which would read as an actual
        // parameter called "_" rather than as "unnamed".
        var paramNames = ov.params.map(function(p){
          return (p.name === "_" ? p.type : p.name) + (p.optional?'?':'');
        });
        h.push('<div class="fn-ov-sig">'+esc(fn.name)+'('+paramNames.join(', ')+')</div>');
        if(ov.params.length){
          h.push('<ul class="fn-plist">');
          ov.params.forEach(function(p){
            h.push('<li><code>'+esc(p.name)+(p.optional?'?':'')+'</code> '+esc(p.type)+'</li>');
          });
          h.push('</ul>');
        }
        if(ov.returns.length){
          h.push('<ul class="fn-plist">');
          ov.returns.forEach(function(r){
            h.push('<li>→ <code>'+esc(r.type)+'</code></li>');
          });
          h.push('</ul>');
        }
      });
      h.push('</div>');
    }
    if(fn.see && fn.see.length){
      var seeLinks = fn.see.map(function(target){
        var targetId = seeIndex[target];
        return targetId
          ? '<a href="#" data-see-target="'+esc(targetId)+'">'+esc(target)+'</a>'
          : '<span title="unresolved">'+esc(target)+'</span>';
      });
      h.push('<div class="fn-desc fn-see">See also: '+seeLinks.join(", ")+'</div>');
    }
    if(fn.example){ h.push('<div class="fn-ex">'+esc(fn.example)+'</div>'); }
    return h.join("");
  }

  // The keyword lookup inside a rendered snippet.
  //
  // The page has shown source since `core/snippet.lua` existed; it just
  // never said anything about it. `IR.glossaries` carries one entry per
  // file extension (see `lang_registry.glossaries()`), and a backend that
  // ships none decorates nothing at all — which is the honest degradation.
  // Falling back to another language's keywords would explain `goto` in a
  // file where it means something else.
  //
  // The glossary is chosen by the *snippet's own* extension, not by the
  // page's or the reader's: a polyglot tree has Lua snippets and TS
  // snippets on the same screen, and each has to answer for itself.
  function glossaryForPath(path){
    if(!path || !IR.glossaries) return null;
    var m = /\.([A-Za-z0-9]+)$/.exec(path);
    if(!m) return null;
    return IR.glossaries[m[1].toLowerCase()] || null;
  }

  // Which spans of a snippet are *not* code.
  //
  // A keyword decorated inside a string or a comment is a false positive:
  // the definition shown would be right and the context wrong, which is
  // worse than leaving it plain. So this skips those spans, driven by the
  // per-language delimiters in `glossary.syntax` rather than by a lexer per
  // language living here.
  //
  // Every known limit (Lua long brackets above level zero, JS template
  // interpolation, a regex literal containing comment-looking bytes) costs
  // a *missing* decoration rather than a wrong one. That is the direction
  // to fail in, and it is why this is allowed to be approximate at all.
  function snipBodyHTML(src, path){
    var gl = glossaryForPath(path);
    if(!gl || !gl.keywords) return esc(src);
    var sx = gl.syntax || {};
    var strs = sx.strings || [];
    var out = "", plain = "", i = 0, n = src.length;

    function flush(){ if(plain){ out += esc(plain); plain = ""; } }
    function at(tok){ return tok && src.substr(i, tok.length) === tok; }

    while(i < n){
      if(at(sx.line_comment)){
        var eol = src.indexOf("\n", i);
        if(eol < 0) eol = n;
        plain += src.slice(i, eol); i = eol; continue;
      }
      var bc = sx.block_comment;
      if(bc && at(bc[0])){
        var close = src.indexOf(bc[1], i + bc[0].length);
        var stop = close < 0 ? n : close + bc[1].length;
        plain += src.slice(i, stop); i = stop; continue;
      }
      var str = null;
      for(var s = 0; s < strs.length; s++){
        if(at(strs[s][0])){ str = strs[s]; break; }
      }
      if(str){
        var j = i + str[0].length;
        while(j < n){
          if(sx.escape && src.charAt(j) === sx.escape){ j += 2; continue; }
          if(src.substr(j, str[1].length) === str[1]){ j += str[1].length; break; }
          j++;
        }
        if(j > n) j = n;
        plain += src.slice(i, j); i = j; continue;
      }
      var ch = src.charAt(i);
      if(/[A-Za-z_]/.test(ch)){
        // The whole dotted run, not just the first identifier: a stdlib entry
        // is `table.concat`, and stopping at `table` would look up a word
        // that means nothing on its own. Consumed once, then matched
        // longest-first below.
        var k = i;
        while(k < n && /[A-Za-z0-9_]/.test(src.charAt(k))) k++;
        while(k + 1 < n && src.charAt(k) === "." && /[A-Za-z_]/.test(src.charAt(k + 1))){
          k++;
          while(k < n && /[A-Za-z0-9_]/.test(src.charAt(k))) k++;
        }
        var run = src.slice(i, k);

        // `hasOwnProperty` rather than a truthiness test: a glossary is a
        // plain object from JSON, so a word like "constructor" would
        // otherwise find Object.prototype's own member and decorate an entry
        // that does not exist.
        function has(table, key){
          return table && Object.prototype.hasOwnProperty.call(table, key);
        }

        // Longest prefix wins: `vim.treesitter.query.parse` beats
        // `vim.treesitter`, which beats nothing. A shorter match on a longer
        // run would explain the namespace while the reader pointed at the
        // function.
        var parts = run.split(".");
        var matched = null, kind = null, label = null;

        // `s:gsub(...)` is `string.gsub`, and in real Lua it is the common
        // spelling by two orders of magnitude. The receiver's type is
        // unknowable here, so this is deliberately narrow: a *declared*
        // namespace, a single word, and only names that namespace actually
        // has. An object of one's own with a `:format` method gets the
        // string card, which is the price -- and the same direction of error
        // the rest of this tokenizer accepts: an entry that exists, on text
        // that may not be it, never an invented one.
        //
        // `::label::` is not a method call, hence the second look back.
        if(sx.method_namespace && parts.length === 1 && i > 0 &&
           src.charAt(i - 1) === ":" && src.charAt(i - 2) !== ":"){
          var viaColon = sx.method_namespace + "." + run;
          if(Object.prototype.hasOwnProperty.call(gl.stdlib || {}, viaColon)){
            matched = viaColon; kind = "std"; label = run;
          }
        }

        for(var take = parts.length; take >= 1 && !matched; take--){
          var candidate = parts.slice(0, take).join(".");
          if(has(gl.stdlib, candidate)){ matched = candidate; kind = "std"; }
          // A keyword is a bare word by definition, so only the whole run
          // can be one -- `end` in `foo.end` is not Lua at all.
          else if(take === parts.length && take === 1 && has(gl.keywords, candidate)){
            matched = candidate; kind = "kw";
          }
        }

        if(matched){
          flush();
          // The decorated text is not always the key: a colon call shows
          // `gsub` and answers about `string.gsub`.
          if(label === null) label = matched;
          // The undecorated tail (`.parse` when only `vim.treesitter`
          // matched) is emitted plain rather than swallowed into the span:
          // the card would otherwise claim to describe text it does not.
          out += '<span class="kw" data-kw="' + esc(matched) + '" data-kwkind="' + kind +
            '" tabindex="0">' + esc(label) + '</span>';
          plain += run.slice(label.length);
        } else {
          plain += run;
        }
        i = k; continue;
      }
      plain += ch; i++;
    }
    flush();
    return out;
  }

  // The bounded source snippet, popup-only — deliberately **not** folded
  // into `fnAnnotationHTML` above, unlike everything else that function
  // renders. That function is shared with the Tree tab's detail pane, which
  // already lists every function of a node in full; a node with a few dozen
  // functions each carrying up to 40 lines of source would turn that pane
  // into mostly code, for a question ("what does this look like") the
  // pane's own click-through to source already answers one step away. The
  // popup is a different reading task — one function, inspected without
  // navigating — where the tradeoff runs the other way. See
  // `docs/ECOSYSTEM.md` §3.5 for the "bounded snippet, embeddable tier"
  // this implements.
  function snippetHTML(fn, node){
    if(!fn.snippet) return "";
    var omitted = fn.snippet_omitted
      ? ' <span class="bd" title="truncated — not carried into the artifact">+' +
        fn.snippet_omitted + ' more line' + (fn.snippet_omitted === 1 ? '' : 's') + '</span>'
      : '';
    // The path rides on the container rather than on every keyword span:
    // one attribute per snippet instead of one per word, and the lookup
    // walks up to it, which is what `.closest` is for.
    var path = node ? (node.source || node.path || "") : "";
    return '<div class="fn-snip-label">Source' + omitted + '</div>' +
      '<div class="fn-snip" data-path="' + esc(path) + '">' +
      snipBodyHTML(fn.snippet, path) + '</div>';
  }

  // Artifact lives in out_dir; repo-relative paths need to climb back out.
  function rel(p){ return (IR.meta.out_depth ? "../".repeat(IR.meta.out_depth) : "") + p; }

  // =====================================================================
  // State + history
  //
  // One object describes everything the page can be showing:
  //   { tab: "tree"|"hierarchy", id: <selected tree node>,
  //     center: <hierarchy centered node>,
  //     view: "modules"|"types"|"deps"|"calls",
  //     dir: "out"|"in"|"both",   — deps/calls only: follow edges forwards
  //                                 (what this needs), backwards (what needs
  //                                 this), or both around the center
  //     depth: 1|2|3|0,           — 0 means unbounded, still capped by MAX_HNODES
  //     fn: "<node id>#<name>" }  — calls view centered on one function
  //
  // Direction is an axis rather than two more views on purpose: "callers of X"
  // and "callees of X" are the same diagram walked the other way, and making
  // them separate views would have doubled the view list to four buttons
  // saying almost the same thing.
  //
  // navigate(patch) is the single entry point every discrete click handler
  // calls; it merges the patch into current state, updates the DOM, and
  // pushes a real history entry so the browser Back/Forward buttons step
  // through actual states instead of only reacting to a directly-edited
  // hash. Every axis above goes through it — a control that set `dir` or
  // `depth` behind its back would produce a diagram the Back button cannot
  // return from. Live preview while typing in the Hierarchy search box is the
  // one deliberate exception — see the "input" listener below for why going
  // through history.replaceState there was a real bug, not just an
  // unnecessary one.
  // =====================================================================
  var DEFAULT_STATE = {
    tab: "hierarchy", id: null, center: null, view: "modules",
    dir: "out", depth: 2, fn: null, ext: false, iview: "functions", atool: "test",
    sha: null,
    // Modules view only: how many top layers of the real tree are peeled
    // off, so every node that used to sit at that depth renders as its own
    // parallel root instead — a "forest" view, not a re-center on any one
    // of them (that's what `center` already does). Mutually exclusive with
    // `center` in practice — see `navigate()`'s own note on why setting one
    // clears the other.
    hideroot: 0,
    // Analysis sort. `null` means "this panel's own default order", which is
    // deliberately not spelled as an explicit column: each panel's default is
    // an editorial choice (worst coverage first, highest fan-in first) that a
    // named column would flatten into "sorted by pct, descending" and lose the
    // tiebreaks with it.
    asort: null, adir: null,
    // Which capture the Telemetry panel's single-view table reads: `null`
    // means the live aggregate ("Latest"), otherwise a snapshot name.
    // `tsnapb` is set only in compare mode — `null` means "not comparing",
    // the string `"latest"` means "compare against the live aggregate
    // explicitly", anything else is a second snapshot name.
    tsnap: null, tsnapb: null,
    // Which persisted runtime-analysis.loaded snapshot the Loaded panel
    // reads (docs/ROADMAP.md §5.4). `null` means "none selected yet" —
    // unlike Telemetry there is no live aggregate to fall back to here
    // (see drawAnalysisLoaded's own header for why), so a picker with
    // nothing chosen shows a prompt rather than data.
    lsnap: null,
    // Per-tab text filter. One field, but the *contract* is per tab — see
    // `filterFor`.
    q: null,
    // Compare layout. "matrix" is the default because it is the layout that
    // earns the feature: two annotation cards side by side is something two
    // browser windows already do, whereas "which of these four differ, and
    // where" has no other answer on this page.
    cview: "matrix",
    // Marked objects, as `"<node id>"` or `"<node id>#<fn>"` — the same key
    // scheme `fnKey` and `quicks.evidence` use. In the hash so a comparison
    // set is shareable, which is the same promise every other view on this
    // page makes; also mirrored into localStorage, because a mark collected
    // while reading should survive the regenerate that follows.
    marks: [],
    // Dimmed Hierarchy boxes — same key scheme `hboxes` uses (node id, class
    // name, or `fnKey`), unlike `marks` not unified with it since the two
    // answer different questions. Hierarchy-scoped in the hash (see
    // `serializeState`'s hierarchy branch), unlike `marks`, which is
    // deliberately global — a dimmed box only exists inside the Hierarchy
    // tab, so carrying it into a Tree-tab link would be noise no other
    // hierarchy axis (`dir`/`depth`/`ext`) is allowed to add either.
    hidden: []
  };
  // Both are arrays, so a shared reference would let one state's edits reach
  // every other state object built from the same default — including the
  // one `parseState` starts from on every popstate.
  function freshState(){
    var s = Object.assign({}, DEFAULT_STATE);
    s.marks = [];
    s.hidden = [];
    return s;
  }

  var state = freshState();
  // Tracks only the hash of the last *pushed* entry — deliberately never
  // touched by a replace. Search-as-you-type replaces the current entry on
  // every keystroke; without this separation, typing to a match and then
  // pressing Enter to commit it would compute the same resulting hash the
  // last replace already wrote, and a single "skip if hash unchanged" guard
  // would then suppress the deliberate push entirely — Enter would silently
  // do nothing. Keeping the two trackers apart means a push always executes
  // unless the *previous push* (not the previous replace) had that hash.
  var lastPushedHash = null;

  // Only axes that matter for the current view are serialized: a Tree-tab URL
  // carrying dir/depth/view would be three pieces of noise in every link
  // anyone shares, and a Modules-view URL carrying `dir` would suggest a
  // control that view does not have.
  function isGraphView(v){ return v === "deps" || v === "calls" || v === "modulecalls"; }

  function serializeState(s){
    var parts = ["tab=" + encodeURIComponent(s.tab)];
    if(s.tab === "tree"){
      if(s.id) parts.push("id=" + encodeURIComponent(s.id));
    } else if(s.tab === "notes"){
      // Nothing else to carry: a flat aggregate over the whole map, with no
      // center, view or direction to remember. Falling through to the
      // hierarchy branch would put a `view=modules` in every shared link that
      // means nothing there.
      void 0;
    } else if(s.tab === "index"){
      // One axis, not the hierarchy branch's whole set: R3's Functions/
      // Modules toggle, omitted when it is the default so the common case
      // stays a bare `#tab=index` link.
      if(s.iview === "modules") parts.push("iview=modules");
    } else if(s.tab === "analysis"){
      // Same rule, Analysis's own axes: which tool panel is open, and how it
      // is sorted. Both omitted at their defaults so the common case stays a
      // bare `#tab=analysis` link.
      if(s.atool !== "test") parts.push("atool=" + encodeURIComponent(s.atool));
      if(s.asort){
        parts.push("asort=" + encodeURIComponent(s.asort));
        parts.push("adir=" + encodeURIComponent(s.adir === "asc" ? "asc" : "desc"));
      }
      // Telemetry's own two axes — which capture, and what it is compared
      // against — only meaningful on that one panel, same as asort/adir are
      // scoped to whichever panel is actually sortable.
      if(s.tsnap) parts.push("tsnap=" + encodeURIComponent(s.tsnap));
      if(s.tsnapb) parts.push("tsnapb=" + encodeURIComponent(s.tsnapb));
      if(s.lsnap) parts.push("lsnap=" + encodeURIComponent(s.lsnap));
      if(s.q) parts.push("q=" + encodeURIComponent(s.q));
    } else if(s.tab === "history"){
      // The opened commit, so a link to one is shareable. Validated on the
      // way back in — the server validates it again before it reaches git,
      // but a hash is user input and the fetch URL is built from it here.
      if(s.sha) parts.push("sha=" + encodeURIComponent(s.sha));
    } else if(s.tab === "quicks"){
      // Nothing to carry: one flat verdict list over the whole map, same as
      // Notes.
      void 0;
    } else if(s.tab === "features"){
      // Same reasoning as Quicks/Notes: one flat catalog over the whole
      // repo's docs/FEATURES/, no center/sort/filter axis of its own yet.
      void 0;
    } else if(s.tab === "compare"){
      if(s.cview !== "matrix") parts.push("cview=" + encodeURIComponent(s.cview));
    } else if(s.tab && s.tab.indexOf("feature-") === 0){
      // A promoted feature's own tab: same reasoning as Features itself —
      // one flat page over one feature, no axis of its own to carry. Caught
      // here rather than falling into the hierarchy branch below, which
      // would otherwise stamp a meaningless `view=modules` onto every link
      // to one of these tabs.
      void 0;
    } else {
      if(s.center) parts.push("center=" + encodeURIComponent(s.center));
      parts.push("view=" + encodeURIComponent(s.view || "modules"));
      // Orientation, and only when it is not the default — the common case
      // stays the link this page has always produced. It belongs to every
      // graph view, unlike `dir`/`depth`, because every one of them is
      // laid out in layers.
      if(s.hdir === "lr") parts.push("hdir=lr");
      // Modules only, same "only where it applies" rule as `ext` below —
      // Deps/Calls/Module Calls/Types/Inheritance have no notion of a
      // directory root to peel layers off of.
      if((s.view || "modules") === "modules" && s.hideroot) {
        parts.push("hideroot=" + encodeURIComponent(String(s.hideroot)));
      }
      if(isGraphView(s.view)){
        parts.push("dir=" + encodeURIComponent(s.dir || "out"));
        parts.push("depth=" + encodeURIComponent(String(s.depth === 0 ? 0 : (s.depth || 2))));
      }
      // Only when on, and only where it applies: an "ext=0" in every Deps
      // link would be noise in the common case.
      if((s.view === "deps" || s.view === "modulecalls") && s.ext) parts.push("ext=1");
      if(s.view === "calls" && s.fn) parts.push("fn=" + encodeURIComponent(s.fn));
      // Hierarchy-scoped, unlike `marks` below: a dimmed box only exists in
      // this tab, so a Tree-tab link carrying `hidden=` would name a control
      // that link's own view does not have — the same rule `dir`/`depth`/
      // `ext`/`fn` above already follow.
      if(s.hidden && s.hidden.length) parts.push("hidden=" + encodeURIComponent(s.hidden.join(",")));
    }
    // Outside the per-tab branches, unlike every other axis: marks are
    // collected while reading any tab and belong to the reader, not to a view.
    // Only when non-empty, so the common case is not a link with a trailing
    // `&marks=` in it.
    if(s.marks && s.marks.length) parts.push("marks=" + encodeURIComponent(s.marks.join(",")));
    return "#" + parts.join("&");
  }

  function parseState(hash){
    var s = freshState();
    var raw = (hash || "").replace(/^#/, "");
    if(!raw) return s;
    // A bare node id with no "=" is the pre-existing #<id> scheme (also what
    // a hand-typed or externally shared link looks like) — treat it as
    // "select this node in the Tree tab".
    if(raw.indexOf("=") === -1){
      s.id = decodeURIComponent(raw);
      return s;
    }
    raw.split("&").forEach(function(kv){
      var i = kv.indexOf("=");
      if(i < 0) return;
      var k = kv.slice(0, i), v = decodeURIComponent(kv.slice(i + 1));
      if(k === "tab") s.tab = v;
      else if(k === "id") s.id = v;
      else if(k === "center") s.center = v;
      else if(k === "view") s.view = v;
      else if(k === "dir") s.dir = (v === "in" || v === "both") ? v : "out";
      // Anything unparseable falls back to the default rather than to NaN,
      // which would make every BFS below terminate immediately and draw an
      // empty diagram for a URL that merely had a typo in it.
      else if(k === "depth"){ var d = parseInt(v, 10); s.depth = isNaN(d) ? 2 : d; }
      // Clamped against the real tree at layout time (layoutModulesRooted),
      // not here — maxRootDepth() reads IR, which parseState has no need to
      // depend on. A negative or unparseable value falls back to 0 (the
      // ordinary single-root case) rather than to NaN, same reasoning as
      // `depth` above.
      else if(k === "hideroot"){ var hr = parseInt(v, 10); s.hideroot = (isNaN(hr) || hr < 0) ? 0 : hr; }
      else if(k === "fn") s.fn = v;
      else if(k === "ext") s.ext = (v === "1" || v === "true");
      else if(k === "iview") s.iview = (v === "modules") ? "modules" : "functions";
      else if(k === "atool") s.atool = (v === "doc" || v === "deps" || v === "complexity" ||
        v === "duplicates" || v === "plugins" || v === "lazy" || v === "tools" || v === "hooks" ||
        v === "checklist" || v === "api" || v === "annotations" ||
        v === "docs" || v === "endpoints" || v === "telemetry" || v === "loaded" ||
        v === "bindings") ? v : "test";
      // Snapshot names are whatever runtime-analysis.telemetry's own
      // sanitizer allowed through when saved — not re-validated here, the
      // same posture `sha`/`q` already take: a value that does not
      // actually name a saved snapshot just gets "snapshot not found" back
      // from `/api/telemetry`, not silently dropped before it can ask.
      // Orientation. Anything but "lr" is top-down, so an old link and a
      // typo land in the same place — the one this page has always had.
      else if(k === "hdir") s.hdir = (v === "lr") ? "lr" : null;
      else if(k === "tsnap") s.tsnap = v || null;
      else if(k === "tsnapb") s.tsnapb = v || null;
      // Same posture as tsnap/tsnapb: a snapshot name runtime-analysis.
      // loaded's own sanitizer allowed through when saved, not
      // re-validated here — an invalid one just gets "snapshot not found"
      // back from /api/loaded.
      else if(k === "lsnap") s.lsnap = v || null;
      // Not whitelisted against a column list here, because the valid columns
      // differ per panel and this parser does not know which panel `atool`
      // will resolve to. `anSort` looks the key up in the panel's own column
      // spec and falls back to the default order when it does not match — so
      // an unknown value degrades to "the normal view", not to a broken one.
      else if(k === "asort") s.asort = v || null;
      else if(k === "adir") s.adir = (v === "asc") ? "asc" : "desc";
      else if(k === "q") s.q = v || null;
      // Validated here, not just at the server: this value is interpolated
      // into a fetch URL, and the same whitelist the server applies before it
      // reaches git is the right shape to demand of a hash too. Anything else
      // is dropped rather than sanitized.
      else if(k === "sha") s.sha = /^[0-9a-f]{7,40}$/.test(v) ? v : null;
      else if(k === "cview") s.cview = (v === "columns" || v === "stacked") ? v : "matrix";
      // Filtered against what this map actually contains, not taken on trust.
      // A shared link outlives the tree it was made from: rename a module and
      // yesterday's comparison URL names keys that no longer resolve. Dropping
      // them here means the surviving ones still open, instead of the page
      // rendering a row of "unknown" cards — the same tolerance `fnByKey`
      // already extends to a stale `data-sig`.
      else if(k === "marks"){
        s.marks = v.split(",").filter(function(key){ return key && markExists(key); });
      }
      else if(k === "hidden"){
        s.hidden = v.split(",").filter(function(key){ return key && hiddenKeyExists(key); });
      }
    });
    return s;
  }

  // Applies `s` to the DOM. `push` controls history: true adds a Back-stack
  // entry (every discrete navigate() call), false replaces the current entry
  // in place (restoring state after a popstate, and the very first load —
  // neither should itself create a Back-stack entry). Never mutates `state`
  // directly outside this function, so `state` always reflects exactly what
  // is on screen.
  function applyState(s, push){
    // A promoted feature's tab id is content-derived and can disappear
    // across a regenerate (renamed, un-promoted, its theme file deleted) —
    // unlike the other nine, permanent tabs. A bookmarked or shared link to
    // one that no longer resolves falls back to the Features catalog rather
    // than leaving every `.view` panel inactive and the page blank.
    if(s.tab && s.tab.indexOf("feature-") === 0 &&
       !collectPromotedFeatures().some(function(p){ return p.slug === s.tab; })){
      s.tab = "features";
    }
    state = s;

    var group = topTab(s.tab);
    document.querySelectorAll(".tab-btn").forEach(function(b){
      b.classList.toggle("active", b.dataset.tab === group);
    });
    renderSubTabs(s);
    document.getElementById("view-tree").classList.toggle("active", s.tab === "tree");
    document.getElementById("view-hierarchy").classList.toggle("active", s.tab === "hierarchy");
    document.getElementById("view-notes").classList.toggle("active", s.tab === "notes");
    document.getElementById("view-index").classList.toggle("active", s.tab === "index");
    document.getElementById("view-analysis").classList.toggle("active", s.tab === "analysis");
    document.getElementById("view-history").classList.toggle("active", s.tab === "history");
    document.getElementById("view-findings").classList.toggle("active", s.tab === "findings");
    document.getElementById("view-quicks").classList.toggle("active", s.tab === "quicks");
    document.getElementById("view-compare").classList.toggle("active", s.tab === "compare");
    document.getElementById("view-features").classList.toggle("active", s.tab === "features");
    document.querySelectorAll('[id^="view-feature-"]').forEach(function(v){
      v.classList.toggle("active", v.id === "view-" + s.tab);
    });

    if(s.tab === "tree" && s.id && byId[s.id]) selectRow(s.id);
    if(s.tab === "hierarchy") drawHierarchy(s.center || IR.root, s.view || "modules");
    if(s.tab === "notes") drawNotes();
    if(s.tab === "index") drawIndex();
    if(s.tab === "analysis") drawAnalysis();
    if(s.tab === "history") drawHistory(s.sha || null);
    if(s.tab === "quicks") drawQuicks();
    if(s.tab === "compare") drawCompare();
    if(s.tab === "features") drawFeatures();
    if(s.tab && s.tab.indexOf("feature-") === 0) drawFeatureTab(s.tab);
    // After the draw, not before: a redraw rebuilds the rows that carry the
    // mark triggers, so painting them first would paint elements about to be
    // replaced.
    syncMarks();
    syncHidden();
    syncLangFilter();
    syncGraphControls(s);
    syncSearchBox(s);

    var hash = serializeState(s);
    if(push){
      if(hash !== lastPushedHash){
        history.pushState(s, "", hash);
        lastPushedHash = hash;
      }
    } else {
      history.replaceState(s, "", hash);
    }

    postContext(s);
  }

  // A host embedding this page in an iframe (docmap-desktop is the first —
  // `src-tauri/src/server.rs` serves it over a real origin specifically so
  // this has somewhere to go) has no other way to know which panel is on
  // screen: `history.pushState` above only updates *this* page's own
  // session history, invisible outside it, and a `<button>` inside this
  // panel could not act on the embedding app regardless (a browser page
  // cannot reach into a Tauri window's own process — the same category
  // error `docs/ECOSYSTEM.md` already names for the reverse direction).
  // `postMessage` is the one channel that crosses the iframe boundary in
  // either direction.
  //
  // Coarse on purpose — `tab`/`atool`/`view` only, not the full state
  // object: a host reacting to "which panel" does not need `center`,
  // `depth`, or any of the dozen other keys the URL hash already carries,
  // and sending them would make this page's own internal state shape part
  // of a cross-origin contract other code depends on.
  //
  // `"*"` as the target origin, not this page's own: the parent's origin
  // (`tauri://…`, `file://`, whatever embeds this) is not something a page
  // that does not know it is embedded can predict, and every value sent is
  // already public — it is exactly what the URL bar of this page itself
  // would show.
  var lastPostedContext = null;
  function postContext(s){
    if(window.parent === window) return;
    var ctx = { source: "docmap", tab: s.tab || null, atool: s.atool || null, view: s.view || null };
    var key = ctx.tab + "|" + ctx.atool + "|" + ctx.view;
    if(key === lastPostedContext) return;
    lastPostedContext = key;
    try { window.parent.postMessage(ctx, "*"); } catch(e){ /* no listening host, or postMessage unavailable — silent, same as no host at all */ }
  }

  ///Apply `patch` over the current state.
  ///
  ///`opts.push === false` replaces the current history entry instead of adding
  ///one — for changes that happen per keystroke, where one Back-stack entry
  ///per character would make the Back button useless.
  function navigate(patch, opts){
    // Centering on a specific node and hiding root levels are two different
    // answers to "what does the Modules view show" — picking one has to
    // clear the other, or double-clicking a box while a forest view is up
    // would appear to do nothing (still covered by every other root's own
    // subtree), and dragging the slider after centering somewhere would
    // leave a stale `center` sitting in the URL that the forest layout
    // never even reads. Centralized here rather than at each of the dozen
    // call sites that set one or the other, so none of them has to
    // remember to.
    if(patch.center !== undefined && patch.hideroot === undefined){
      patch = Object.assign({}, patch, { hideroot: 0 });
    } else if(patch.hideroot !== undefined && patch.center === undefined){
      patch = Object.assign({}, patch, { center: null });
    }
    applyState(Object.assign({}, state, patch), !(opts && opts.push === false));
  }

  window.addEventListener("popstate", function(ev){
    applyState(ev.state || parseState(location.hash), false);
  });

  // =====================================================================
  // Tree tab
  // =====================================================================
  var treeEl = document.getElementById("tree");
  var detailEl = document.getElementById("detail");
  var selectedRowId = null;

  function badges(n){
    var b = [];
    if(n.readme) b.push('<span class="bd rd">readme</span>');
    if(n.types && n.types.length) b.push('<span class="bd">types</span>');
    var f = findByNode[n.id] || [];
    if(f.some(function(x){return x.severity==="error";})) b.push('<span class="bd" style="color:var(--error);border-color:var(--error)">drift</span>');
    return b.length ? '<span class="badges">'+b.join("")+'</span>' : "";
  }

  // Functions hang under their node behind their own collapsed group rather
  // than being mixed into `children`. Two reasons: `children` is IR structure
  // and functions are not part of it, and this tree renders eagerly — folding
  // ~1500 function rows into the always-expanded default would bury the
  // module structure the tree exists to show. One extra row per node, opened
  // on demand, costs nothing until asked for.
  function renderFunctionGroup(n){
    var group = document.createElement("div");

    var head = document.createElement("div");
    head.className = "row fnhead";
    head.innerHTML = '<span class="tw">▸</span>' +
      '<span class="nm">ƒ ' + n.functions.length + ' function' +
      (n.functions.length === 1 ? '' : 's') + '</span>';

    var list = document.createElement("div");
    list.className = "kids fnkids hide";

    n.functions.forEach(function(fn){
      var key = fnKey(n.id, fn.name);
      var r = document.createElement("div");
      r.className = "row k-fn";
      r.dataset.fn = key;
      r.dataset.id = n.id;
      r.innerHTML = '<span class="tw"></span>' +
        '<span class="nm">' + esc(fn.signature) + '</span>' +
        '<span class="sm">' + prose(fn.summary || "") + '</span>';
      r.addEventListener("click", function(){
        navigate({ tab: "tree", id: n.id });
      });
      list.appendChild(r);
    });

    head.addEventListener("click", function(ev){
      ev.stopPropagation();
      list.classList.toggle("hide");
      head.querySelector(".tw").textContent = list.classList.contains("hide") ? "▸" : "▾";
    });

    group.appendChild(head);
    group.appendChild(list);
    return group;
  }

  function renderNode(n){
    var kids = (n.children||[]).map(function(id){ return byId[id]; }).filter(Boolean);
    var hasFns = (n.functions || []).length > 0;
    var hasKids = kids.length > 0 || hasFns;
    var row = document.createElement("div");
    row.className = "row k-" + n.kind;
    row.dataset.id = n.id;
    row.innerHTML =
      '<span class="tw">' + (hasKids ? "▾" : "") + '</span>' +
      '<span class="nm">' + esc(n.name) + '</span>' +
      badges(n) +
      '<span class="sm">' + prose(n.summary || "") + '</span>';

    var box = document.createElement("div");
    box.appendChild(row);

    if(hasKids){
      var kidsEl = document.createElement("div");
      kidsEl.className = "kids";
      kids.forEach(function(k){ kidsEl.appendChild(renderNode(k)); });
      if(hasFns) kidsEl.appendChild(renderFunctionGroup(n));
      box.appendChild(kidsEl);
      row.querySelector(".tw").addEventListener("click", function(ev){
        ev.stopPropagation();
        kidsEl.classList.toggle("hide");
        this.textContent = kidsEl.classList.contains("hide") ? "▸" : "▾";
      });
    }
    row.addEventListener("click", function(){ navigate({ tab: "tree", id: n.id }); });
    return box;
  }

  // DOM-only: row highlight + detail pane. No history side effects — that is
  // applyState's job, so this can be called from anywhere (including a
  // popstate restore) without ever touching the URL itself.
  function selectRow(id){
    var n = byId[id]; if(!n) return;
    if(selectedRowId){ var p = treeEl.querySelector('.row[data-id="'+CSS.escape(selectedRowId)+'"]');
      if(p) p.classList.remove("sel"); }
    selectedRowId = id;
    var cur = treeEl.querySelector('.row[data-id="'+CSS.escape(id)+'"]');
    if(cur) cur.classList.add("sel");
    renderDetail(n);
  }

  function renderDetail(n){
    var h = [];
    h.push('<h2>'+esc(n.name)+'</h2>');
    // A module has annotations but no signature, so there is no `sigTrigger`
    // here to carry the mark control along — it is rendered on its own. Marks
    // are not a function-only idea: "how do these three modules differ" is the
    // same question one scale up.
    h.push('<div class="mp">'+esc(n.module || n.path)+docTrigger(n.id)+markTrigger(n.id)+'</div>');

    var links = [];
    if(n.readme) links.push('<a href="'+esc(rel(n.readme))+'">README</a>');
    if(n.source){ var u = srcUrl(n.source);
      links.push(u ? '<a href="'+esc(u)+'">source ↗</a>' : '<a href="'+esc(rel(n.source))+'">source</a>'); }
    (n.types||[]).forEach(function(t){
      var u2 = srcUrl(t);
      links.push(u2 ? '<a href="'+esc(u2)+'">types ↗</a>' : '<a href="'+esc(rel(t))+'">types</a>');
    });
    if(n.kind !== "file"){
      links.push('<a href="#" data-goto="hierarchy">Hierarchy ↳</a>');
    }
    if((n.requires||[]).length || (n.required_by||[]).length){
      links.push('<a href="#" data-goto="deps">Dependencies ↳</a>');
    }
    if((n.functions||[]).length){
      links.push('<a href="#" data-goto="calls">Calls ↳</a>');
      // No module-level Compiler Explorer link, deliberately — removed
      // rather than repaired, for two independent reasons.
      //
      // It could not work: the source travels base64-encoded in the URL and
      // godbolt.org rejects a request line over 8 KB, while this
      // repository's largest module came to 33,332 characters. A shortener
      // API exists and was verified to handle that size — but it uploads the
      // source and keeps it under a public short link, which is a different
      // act from opening a stateless URL.
      //
      // And it should not work: a module link concatenated every function's
      // snippet, which is an approximation of the file and not the file —
      // no requires, no comments, nothing at module scope. `luac` compiles
      // one real file and has no project mode to approximate. Making a
      // meaningless view work is not a fix.
      //
      // Per function it is exact and small (2,880 characters at this
      // repository's worst), and that link is rendered beside each function.
    }
    if(links.length) h.push('<div class="links">'+links.join("")+'</div>');

    if(n.summary || n.body){
      h.push('<div class="prose">'+prose([n.summary, n.body].filter(Boolean).join("\n\n"))+'</div>');
    } else {
      h.push('<p class="empty">No description — this module has an @module tag but no prose.</p>');
    }

    var f = findByNode[n.id] || [];
    if(f.length){
      h.push('<div class="sec">Drift</div><ul class="lst">');
      f.forEach(function(x){ h.push('<li><span class="sev '+x.severity+'">'+x.severity+'</span> '+esc(x.message)+'</li>'); });
      h.push('</ul>');
    }

    // Stats before anything else in the body: "how big is this and what is in
    // it" is the question asked on arrival, and it is the one thing that was
    // impossible to answer from the map at all. Zero-valued entries are
    // dropped rather than shown as "0 markdown", which would be five sixths
    // noise on a leaf file.
    var st = n.stats || {};
    var cells = [
      ["modules", st.modules], ["namespaces", st.namespaces],
      ["lua files", st.files_lua], ["markdown", st.files_md],
      ["other files", st.files_other], ["lines of lua", st.lines],
      ["functions", st.functions], ["tables & values", st.symbols],
      ["types", st.types]
    ].filter(function(c){ return c[1]; });
    if(cells.length){
      h.push('<div class="sec">Stats' +
        (n.kind === "file" ? '' : ' <span class="sub">(this and everything below)</span>') +
        '</div><div class="stat-grid">');
      cells.forEach(function(c){
        h.push('<div class="stat"><b>' + c[1].toLocaleString() + '</b><span>' + esc(c[0]) + '</span></div>');
      });
      h.push('</div>');
    }

    // Dependencies as text, next to the diagram that draws the same thing:
    // the graph answers "what does this sit in the middle of", a list answers
    // "is X in there", and the second question is the more common one.
    function depList(title, ids){
      if(!ids || !ids.length) return;
      h.push('<div class="sec">'+title+' ('+ids.length+')</div><ul class="lst">');
      ids.forEach(function(id){
        var t = byId[id];
        if(!t) return;
        h.push('<li><a href="#" data-node-link="'+esc(id)+'">'+esc(t.module || t.path)+'</a></li>');
      });
      h.push('</ul>');
    }
    depList("Requires", n.requires);
    depList("Required by", n.required_by);

    // Stated even when it is zero: "nothing depends on this" is itself the
    // answer to "is this safe to change".
    if((n.requires || []).length || (n.required_by || []).length){
      var hull = impactOf(n.id);
      h.push('<div class="sec">Impact</div><ul class="lst"><li>' +
        '<b>' + hull.length + '</b> module' + (hull.length === 1 ? '' : 's') +
        ' would be affected by changing this — ' + (n.required_by || []).length +
        ' directly.</li></ul>');
    }

    if(n.types_detail && n.types_detail.length){
      h.push('<div class="sec">Types ('+n.types_detail.length+')</div><ul class="lst">');
      n.types_detail.forEach(function(t){
        h.push('<li>'+t.kind+' <code>'+esc(t.name)+'</code>'+(t.fields.length?' — '+t.fields.length+' field'+(t.fields.length===1?'':'s'):'')+'</li>');
      });
      h.push('</ul>');
    }

    if(n.functions && n.functions.length){
      h.push('<div class="sec">Functions ('+n.functions.length+')</div>');
      n.functions.forEach(function(fn){
        var key = fnKey(n.id, fn.name);
        h.push('<div class="fn" data-fn="'+esc(key)+'">');
        h.push(fnAnnotationHTML(fn));
        // Prose references for this function, where the reader is already
        // looking at everything else known about it.
        var dref = docTrigger(key);
        if(dref) h.push('<div class="fn-desc fn-see">' + dref + '</div>');

        // The per-function entry into the Calls view. Counts are shown up
        // front so a function with no edges either way does not offer a link
        // to an empty diagram — with no call data in the map at all (the
        // common case before `:DocMap` is re-run), this section simply is not
        // rendered, rather than every function sprouting two dead links.
        var outN = (callOut[key] || []).length, inN = (callIn[key] || []).length;
        if(outN || inN){
          var cl = [];
          if(outN) cl.push('<a href="#" data-calls="'+esc(key)+'" data-dir="out">calls '+outN+' ↓</a>');
          if(inN) cl.push('<a href="#" data-calls="'+esc(key)+'" data-dir="in">callers '+inN+' ↑</a>');
          h.push('<div class="fn-desc fn-see">'+cl.join(" · ")+'</div>');
        }
        var godboltFn = godboltTrigger("fn", key);
        if(godboltFn) h.push('<div class="fn-desc fn-see">'+godboltFn+'</div>');
        h.push('</div>');
      });
    }

    // The half of a module's surface that is not callable: the lookup tables
    // it dispatches through, the constants that encode its thresholds, the
    // things it computes once at load time. Reading a module's source these
    // are usually the first thing you go looking for, and nothing generated
    // showed them before.
    if(n.symbols && n.symbols.length){
      h.push('<div class="sec">Tables &amp; values ('+n.symbols.length+')</div><ul class="lst syms">');
      n.symbols.forEach(function(sy){
        h.push('<li><span class="bd sk-'+sy.kind+'">'+sy.kind+'</span> <code>'+esc(sy.name)+'</code>'
          + (sy.detail ? ' <span class="sdet">'+esc(sy.detail)+'</span>' : '')
          + (sy.summary ? '<div class="fn-desc">'+prose(sy.summary)+'</div>' : '')
          + '</li>');
      });
      h.push('</ul>');
    }

    var kids = (n.children||[]).map(function(i){return byId[i];}).filter(Boolean);
    if(kids.length){
      h.push('<div class="sec">Contains ('+kids.length+')</div><ul class="lst">');
      kids.forEach(function(k){
        h.push('<li>'+esc(k.name)+(k.summary?' — <span style="font-family:inherit">'+prose(k.summary)+'</span>':'')+'</li>');
      });
      h.push('</ul>');
    }

    var meta = [];
    if(n.export) meta.push("exports: " + n.export);
    meta.push("kind: " + n.kind);
    h.push('<div class="sec">Meta</div><ul class="lst"><li>'+esc(meta.join("  ·  "))+'</li></ul>');

    detailEl.innerHTML = h.join("");

    // One handler per link family. `fn: null` on the Deps/Hierarchy hops is
    // not redundant: leaving a stale function centered would make a later
    // switch back to Calls open on whatever function was last looked at
    // several nodes ago, rather than on this node.
    detailEl.querySelectorAll("a[data-goto]").forEach(function(a){
      a.addEventListener("click", function(ev){
        ev.preventDefault();
        var to = a.dataset.goto;
        if(to === "hierarchy") navigate({ tab: "hierarchy", view: "modules", center: n.id, fn: null });
        else if(to === "deps") navigate({ tab: "hierarchy", view: "deps", center: n.id, fn: null });
        else navigate({ tab: "hierarchy", view: "calls", center: n.id, fn: null });
      });
    });

    detailEl.querySelectorAll("a[data-calls]").forEach(function(a){
      a.addEventListener("click", function(ev){
        ev.preventDefault();
        navigate({ tab: "hierarchy", view: "calls", center: n.id,
                   fn: a.dataset.calls, dir: a.dataset.dir });
      });
    });

    detailEl.querySelectorAll("a[data-node-link]").forEach(function(a){
      a.addEventListener("click", function(ev){
        ev.preventDefault();
        navigate({ tab: "tree", id: a.dataset.nodeLink });
      });
    });

    detailEl.querySelectorAll("a[data-see-target]").forEach(function(a){
      a.addEventListener("click", function(ev){
        ev.preventDefault();
        navigate({ tab: "tree", id: a.dataset.seeTarget });
      });
    });
  }

  treeEl.appendChild(renderNode(byId[IR.root]));

  document.getElementById("expand").addEventListener("click", function(){
    treeEl.querySelectorAll(".kids").forEach(function(k){ k.classList.remove("hide"); });
    treeEl.querySelectorAll(".tw").forEach(function(t){ if(t.textContent) t.textContent = "▾"; });
  });
  document.getElementById("collapse").addEventListener("click", function(){
    treeEl.querySelectorAll(".kids").forEach(function(k, i){ if(i) k.classList.add("hide"); });
    treeEl.querySelectorAll(".row").forEach(function(r){
      // The function-group header carries no node id, so the depth test below
      // skipped it and left a ▾ twisty over a collapsed group. It is always
      // collapsed by this button, so its arrow is unconditional.
      if(r.classList.contains("fnhead")){
        var ft = r.querySelector(".tw");
        if(ft) ft.textContent = "▸";
        return;
      }
      var n = byId[r.dataset.id];
      if(n && n.depth >= 1){ var t = r.querySelector(".tw"); if(t && t.textContent) t.textContent = "▸"; }
    });
  });

  // =====================================================================
  // Findings: clicking a row with a resolvable node id selects it. Rows for
  // findings whose node isn't a real IR node (a couple of repo-specific
  // checks report against synthetic paths) simply have no data-node
  // attribute and stay inert — see render/html.lua for why.
  // =====================================================================
  document.querySelectorAll("#findings tbody tr[data-node]").forEach(function(tr){
    var target = tr.dataset.node;
    if(!byId[target]) return;
    tr.addEventListener("click", function(){ navigate({ tab: "tree", id: target }); });
  });

  // =====================================================================
  // Header counts → the view that shows that set.
  //
  // Three of the five destinations were obvious and two were not, which was
  // the actual work:
  //
  //   modules     Hierarchy, Modules view — the graph of exactly those.
  //   files       the Tree tab, which is the file tree.
  //   namespaces  the Index tab's Modules view, which already lists "every
  //               module and namespace" filed under the last path segment.
  //               A dedicated namespace *view* was considered and rejected:
  //               namespaces are already drawn in the Hierarchy graph and
  //               already listed here, so a sixth tab would be a third
  //               rendering of a set that has two.
  //   errors      the findings disclosure at the foot of the page — which
  //   warnings    already existed, collapsed. These two are not navigations
  //               at all: they open it, scroll to the first row of that
  //               severity, and flash it.
  // =====================================================================
  /// The path from the root to whatever the graph is currently rooted at.
  ///
  /// `Up` and `Root` already existed and neither answers "where am I" —
  /// after two recentres a reader knows they moved and not from where. Each
  /// segment is also a way back to exactly that level, which `Up` only
  /// reaches one at a time.
  function renderCrumb(){
    var host = document.getElementById("hcrumb");
    if(!host) return;
    var chain = [];
    for(var id = hcenter; id && byId[id]; id = byId[id].parent){
      chain.unshift(byId[id]);
      // A malformed parent chain would spin here rather than fail; the
      // scan cannot produce one, and a loop that trusts that is a loop
      // that hangs the page if it is ever wrong.
      if(chain.length > 64) break;
    }
    host.innerHTML = "";
    // One level deep is the root itself, which `⌂ Root` already says. A
    // breadcrumb of one entry is a label pretending to be navigation.
    if(chain.length < 2){ host.hidden = true; return; }
    host.hidden = false;
    chain.forEach(function(n, i){
      if(i) host.appendChild(document.createTextNode(" / "));
      if(i === chain.length - 1){
        var here = document.createElement("span");
        here.className = "here";
        here.textContent = n.name;
        host.appendChild(here);
        return;
      }
      var a = document.createElement("button");
      a.type = "button";
      a.textContent = n.name;
      a.title = n.module || n.path;
      a.addEventListener("click", function(){ navigate({ center: n.id, fn: null }); });
      host.appendChild(a);
    });
  }

  function revealFinding(severity){
    var box = document.getElementById("findings");
    if(!box) return;
    // The list lives in its own tab now, so getting there is a navigation
    // rather than a scroll. The header count stays where it is: a number
    // behind a click is a number nobody reads, and that number is the
    // whole reason the check exists.
    navigate({ tab: "findings" });
    var details = box.querySelector("details");
    if(details) details.open = true;

    // By class, not by the cell's visible text: the severity is already
    // carried as `<span class="sev error">`, and matching the class keeps this
    // working if the label is ever rendered differently (capitalised,
    // translated, replaced with an icon).
    var marker = box.querySelector("tbody tr td .sev." + severity);
    var target = marker ? marker.closest("tr") : null;
    // No row of that severity should be unreachable: the button is rendered
    // disabled when the count is zero, so arriving here without a match means
    // the tally and the table disagree — scroll to the section anyway rather
    // than doing nothing visible.
    (target || box).scrollIntoView({ behavior: "smooth", block: "center" });
    if(target){
      target.classList.remove("flash");
      // Reflow between remove and add, or a second click on the same button
      // restarts nothing — the class never left the element as far as the
      // animation is concerned.
      void target.offsetWidth;
      target.classList.add("flash");
    }
  }

  document.querySelectorAll(".stat-link").forEach(function(b){
    b.addEventListener("click", function(){
      if(b.disabled) return;
      var to = b.dataset.goto;
      if(to === "modules"){
        navigate({ tab: "hierarchy", center: IR.root, view: "modules" });
      } else if(to === "files"){
        navigate({ tab: "tree" });
      } else if(to === "namespaces"){
        navigate({ tab: "index", iview: "modules" });
      } else if(to === "errors"){
        revealFinding("error");
      } else if(to === "warnings"){
        revealFinding("warn");
      }
    });
  });

  // =====================================================================
  // Tabs
  // =====================================================================
  // Promoted-feature tabs are inserted before the generic .tab-btn wiring
  // below runs, so a click on one goes through the exact same navigate()
  // path every static tab already uses — no separate listener to keep in
  // sync with the rest of the tab bar.
  buildPromotedTabs();
  document.querySelectorAll(".tab-btn").forEach(function(b){
    b.addEventListener("click", function(){ navigate({ tab: b.dataset.tab }); });
  });

  // =====================================================================
  // Hierarchy view
  //
  // Two "aufbereitungen" of the same annotation data, toggled via
  // .hview-btn: "modules" draws the directory/module hierarchy (unchanged
  // from before); "types" draws the class/alias graph from LuaLS
  // enrichment — a materially different view of the same map, not just a
  // relabeling, since it walks ir.edges' from_class/to_class rather than
  // node.children.
  //
  // Node/class positions are computed analytically from IR data (layer =
  // BFS depth, position = index within the layer), not measured off the
  // DOM — this sidesteps "a box inside display:none has zero size" entirely
  // rather than working around it with a re-layout-on-show step, since the
  // math produces correct pixel coordinates regardless of visibility.
  // =====================================================================
  var hgraphWrap = document.getElementById("hgraph-wrap");
  var hgraph = document.getElementById("hgraph");
  var hstage = document.getElementById("hstage");
  var hpathEl = document.getElementById("hpath");
  var hlegendEl = document.getElementById("hlegend");
  // ---------------------------------------------------------------------
  // Middle-mouse panning.
  //
  // `#hgraph-wrap` is `overflow:auto`, so the graph has always scrolled — but
  // only through scrollbars and the wheel, one axis at a time. A wide graph is
  // the normal case here, and dragging it is the interaction every other graph
  // tool has.
  //
  // Middle button only. Left-drag is a text selection on this page — the boxes
  // carry module names people copy — and taking that away to gain a second way
  // to pan would be a bad trade.
  //
  // Three things have to be suppressed or the browser fights the drag:
  //   * `mousedown` default on button 1 starts Chrome/Firefox autoscroll (the
  //     four-way arrow cursor that then scrolls on its own);
  //   * `auxclick` fires on release and is what would open a link in a new tab
  //     had the drag ended over one;
  //   * text selection, once the pointer moves with a button held.
  //
  // Nothing here touches history or state: panning is a viewport change, the
  // same category as the scrollbar it replaces, and pushing a Back-stack entry
  // per drag would bury real navigation under it.
  // ---------------------------------------------------------------------
  var panning = null;

  hgraphWrap.addEventListener("mousedown", function(ev){
    if(ev.button !== 1) return;
    ev.preventDefault();
    panning = {
      x: ev.clientX, y: ev.clientY,
      left: hgraphWrap.scrollLeft, top: hgraphWrap.scrollTop
    };
    hgraphWrap.classList.add("panning");
  });

  // On `window`, not on the element: a drag that leaves the graph and comes
  // back should keep panning, and a release outside it must still end the
  // drag — otherwise the next click anywhere would resume it.
  window.addEventListener("mousemove", function(ev){
    if(!panning) return;
    ev.preventDefault();
    hgraphWrap.scrollLeft = panning.left - (ev.clientX - panning.x);
    hgraphWrap.scrollTop = panning.top - (ev.clientY - panning.y);
  });

  window.addEventListener("mouseup", function(ev){
    if(!panning || ev.button !== 1) return;
    panning = null;
    hgraphWrap.classList.remove("panning");
  });

  hgraphWrap.addEventListener("auxclick", function(ev){
    if(ev.button === 1) ev.preventDefault();
  });

  var hcenter = null;
  var MAX_HNODES = 90;
  var BOX_W = 168, BOX_H = 52, GAP_X = 16, GAP_Y = 44, PAD = 20;

  /// Whether the graph runs left-to-right instead of top-down.
  ///
  /// A layout choice, not a second layout: every view already produces
  /// *layers*, and an orientation is which axis a layer index becomes.
  /// Three places turn layers into geometry — positions, edges, canvas —
  /// and this is the only thing they consult.
  ///
  /// Worth having because module names are wide and shallow: a top-down
  /// graph of a deep tree is a tall column of half-empty rows, and the same
  /// tree sideways fills the screen it is on.
  function isLR(){ return state.hdir === "lr"; }

  // Downward edges keep the original S-curve between the boxes' facing sides.
  // Backedges — an edge to a box on the same layer or above — are a new
  // problem the tree views never had: a require or call graph has cycles, so
  // the BFS assigns a target its *first-seen* depth and any later edge into it
  // points sideways or up. Drawn with the same curve, those run straight
  // through every box in between; routed out of the side and back in, they
  // read as the loop they are.
  function edgePath(a, b){
    if(isLR()){
      // The same curve, a quarter turn round: forward edges leave the right
      // side and enter the left, and anything not going forward falls
      // through to the sideways route below, which already handles a graph
      // whose cycles point backwards.
      if(b.x > a.x){
        var lx1 = a.x + BOX_W, lx2 = b.x;
        var ly1 = a.y + BOX_H/2, ly2 = b.y + BOX_H/2;
        var midX = (lx1 + lx2) / 2;
        return "M" + lx1 + "," + ly1 + " C" + midX + "," + ly1 + " " +
          midX + "," + ly2 + " " + lx2 + "," + ly2;
      }
    }
    var x1 = a.x + BOX_W/2, x2 = b.x + BOX_W/2;
    if(!isLR() && b.y > a.y){
      var y1 = a.y + BOX_H, y2 = b.y;
      var midY = (y1 + y2) / 2;
      return "M" + x1 + "," + y1 + " C" + x1 + "," + midY + " " + x2 + "," + midY + " " + x2 + "," + y2;
    }
    var leftward = x2 <= x1;
    var sx = leftward ? a.x : a.x + BOX_W;
    var ex = leftward ? b.x + BOX_W : b.x;
    var sy = a.y + BOX_H/2, ey = b.y + BOX_H/2;
    var bulge = (leftward ? -1 : 1) * Math.max(38, Math.abs(sy - ey) * 0.45);
    return "M" + sx + "," + sy + " C" + (sx + bulge) + "," + sy + " " +
      (ex + bulge) + "," + ey + " " + ex + "," + ey;
  }

  // Edge readout on hover. The weighted Module Calls edges encode their count
  // as thickness, which ranks well and reads badly: "thicker than that one"
  // is not a number, and log scaling — the thing that stops one outlier
  // flattening everything else — deliberately compresses the difference the
  // eye is being asked to judge. So the number itself is one hover away.
  //
  // Shows the reverse direction too when the pair calls both ways. That is
  // the question thickness cannot express at all: two modules calling each
  // other draw two separate edges (`pairKey` is directional), and which of
  // them is under the cursor is otherwise guesswork.
  var edgeTip = null;
  function edgeHover(hit, path, e, weightByPair){
    function label(id){ var n = byId[id]; return (n && (n.module || n.name)) || id; }
    hit.addEventListener("mouseenter", function(){
      if(!edgeTip){
        edgeTip = document.createElement("div");
        edgeTip.className = "hedge-tip";
        document.body.appendChild(edgeTip);
      }
      var back = weightByPair[e.to + " " + e.from];
      var h = '<div class="et-row"><span class="et-n">' + e.weight + '</span> ' +
        (e.weight === 1 ? "call" : "calls") + " " + esc(label(e.from)) + " → " + esc(label(e.to)) + "</div>";
      if(back){
        h += '<div class="et-row et-back"><span class="et-n">' + back + '</span> ' +
          (back === 1 ? "call" : "calls") + " back</div>";
      }
      edgeTip.innerHTML = h;
      edgeTip.classList.add("on");
      // Widen the real edge while it is described, so it is unambiguous which
      // of several overlapping lines the readout belongs to. Set inline and
      // restored on leave: the weighted edges already carry an inline
      // `stroke-width`, which no class could override.
      path.dataset.w = path.style.strokeWidth || "";
      path.style.strokeWidth = String((parseFloat(path.style.strokeWidth) || 1.5) + 2.5);
      path.style.opacity = "1";
    });
    hit.addEventListener("mousemove", function(ev){
      if(!edgeTip) return;
      // Flip to the other side near the viewport edges rather than letting a
      // fixed-position card get clipped.
      var pad = 14, w = edgeTip.offsetWidth, hgt = edgeTip.offsetHeight;
      var x = ev.clientX + pad, y = ev.clientY + pad;
      if(x + w > window.innerWidth) x = ev.clientX - w - pad;
      if(y + hgt > window.innerHeight) y = ev.clientY - hgt - pad;
      edgeTip.style.left = Math.max(4, x) + "px";
      edgeTip.style.top = Math.max(4, y) + "px";
    });
    hit.addEventListener("mouseleave", function(){
      if(edgeTip) edgeTip.classList.remove("on");
      path.style.strokeWidth = path.dataset.w || "";
      path.style.opacity = "";
    });
  }

  // BFS over node.children from `startId`. Files count the same as modules/
  // namespaces — an earlier version excluded them as "just noise", which was
  // wrong in practice: centering on a module implemented as flat files with
  // no further subdirectories then drew almost nothing. MAX_HNODES already
  // bounds noise at any scope.
  // Every layout below returns the same shape, so drawHierarchy never asks
  // which view it is drawing:
  //   { layers: [[key,…],…], included: {key: layerIndex}, count, truncated,
  //     edges: [{from, to, cls, label}] }
  // Producing the edges here rather than in the drawing code is what keeps
  // four structurally different graphs — a tree, a class graph, a require
  // graph and a call graph — behind one renderer.
  // Shared by layoutModules (one seed, the ordinary case) and
  // layoutModulesRooted (several seeds at once, the hidden-root forest
  // case) — the BFS itself does not care how many roots it started from,
  // only layoutModules used to assume there was exactly one.
  function layoutModulesFrom(seeds){
    var layers = [], included = {}, count = 0, truncated = false;
    var queue = seeds.map(function(id){ return { id: id, d: 0 }; });
    while(queue.length){
      var item = queue.shift();
      if(included[item.id] !== undefined) continue;
      if(count >= MAX_HNODES){ truncated = true; break; }
      var node = byId[item.id];
      if(!node) continue;
      included[item.id] = item.d;
      count++;
      layers[item.d] = layers[item.d] || [];
      layers[item.d].push(item.id);
      (node.children || []).forEach(function(c){
        if(byId[c]) queue.push({ id: c, d: item.d + 1 });
      });
    }

    var edges = [];
    Object.keys(included).forEach(function(id){
      (byId[id].children || []).forEach(function(c){
        if(included[c] !== undefined) edges.push({ from: id, to: c, cls: "hedge", marker: "tree" });
      });
    });
    // Type-reference edges layered on top (dashed), node-granularity,
    // self-loops skipped — a field can reference a class anywhere in the whole
    // map, and pulling in out-of-view targets would break "scoped to one
    // subtree".
    typeEdges.forEach(function(e){
      if(e.from !== e.to && included[e.from] !== undefined && included[e.to] !== undefined){
        edges.push({ from: e.from, to: e.to, cls: "hedge hedge-type",
                     marker: "type", label: "." + e.via });
      }
    });

    return { layers: layers, included: included, count: count, truncated: truncated, edges: edges };
  }

  function layoutModules(startId){
    return layoutModulesFrom([startId]);
  }

  // Every node at exactly `n` steps below the true IR.root via `children` —
  // the "peel off the top n layers" seed set the hidden-root slider needs.
  // n<=0 is the ordinary single-root case. Falls back to [IR.root] if `n`
  // overshoots the tree's real depth (a hand-edited URL hash, since the
  // slider's own `max` is bounded by maxRootDepth()) rather than laying out
  // nothing.
  function rootFrontier(n){
    if(n <= 0) return [IR.root];
    var frontier = [];
    var seen = {};
    var queue = [ { id: IR.root, d: 0 } ];
    while(queue.length){
      var item = queue.shift();
      if(seen[item.id]) continue;
      seen[item.id] = true;
      if(item.d === n){ frontier.push(item.id); continue; }
      var node = byId[item.id];
      if(!node) continue;
      (node.children || []).forEach(function(c){
        if(byId[c]) queue.push({ id: c, d: item.d + 1 });
      });
    }
    return frontier.length ? frontier : [IR.root];
  }

  // The tree's own real depth from IR.root, computed once and cached — the
  // slider's `max`, so it is structurally impossible to drag past the point
  // where there would be nothing left to show.
  var cachedMaxRootDepth = null;
  function maxRootDepth(){
    if(cachedMaxRootDepth !== null) return cachedMaxRootDepth;
    var max = 0;
    var seen = {};
    var queue = [ { id: IR.root, d: 0 } ];
    while(queue.length){
      var item = queue.shift();
      if(seen[item.id]) continue;
      seen[item.id] = true;
      if(item.d > max) max = item.d;
      var node = byId[item.id];
      if(!node) continue;
      (node.children || []).forEach(function(c){
        if(byId[c]) queue.push({ id: c, d: item.d + 1 });
      });
    }
    cachedMaxRootDepth = max;
    return max;
  }

  function layoutModulesRooted(n){
    return layoutModulesFrom(rootFrontier(Math.min(n, maxRootDepth())));
  }

  // BFS over ir.edges' from_class/to_class, seeded from the centered node's
  // own types_detail. A field can reference a class owned by any node in the
  // whole map, which is exactly the point of this view — unlike the Modules
  // view, edges are not required to stay within the laid-out subtree, they
  // define it.
  function layoutTypes(startId){
    var center = byId[startId];
    var seeds = (center.types_detail || []).map(function(t){ return t.name; });
    if(seeds.length === 0) return { layers: [], included: {}, count: 0, truncated: false, edges: [] };

    // `typeEdges`, not `IR.edges`: that array now also carries require and
    // call edges, whose `from_class` is undefined — keying an adjacency map on
    // it would file every one of them under the same bogus key.
    var adj = {};
    typeEdges.forEach(function(e){
      (adj[e.from_class] = adj[e.from_class] || []).push(e);
    });

    var layers = [], included = {}, count = 0, truncated = false;
    var queue = seeds.map(function(name){ return { name: name, d: 0 }; });
    while(queue.length){
      var item = queue.shift();
      if(included[item.name] !== undefined) continue;
      if(!classByName[item.name]) continue;
      if(count >= MAX_HNODES){ truncated = true; break; }
      included[item.name] = item.d;
      count++;
      layers[item.d] = layers[item.d] || [];
      layers[item.d].push(item.name);
      (adj[item.name] || []).forEach(function(e){
        if(classByName[e.to_class]) queue.push({ name: e.to_class, d: item.d + 1 });
      });
    }

    var edges = [];
    Object.keys(included).forEach(function(name){
      (adj[name] || []).forEach(function(e){
        if(included[e.to_class] !== undefined){
          edges.push({ from: name, to: e.to_class, cls: "hedge hedge-type",
                       marker: "type", label: "." + e.via });
        }
      });
    });

    return { layers: layers, included: included, count: count, truncated: truncated, edges: edges };
  }

  // Inheritance: Doxygen's class-hierarchy diagram, centered the way every
  // other view here is centered rather than drawn as one global root-to-leaf
  // tree. Both directions at once, because for a class "what am I" and "who
  // inherits me" are equally the question.
  //
  // Deliberately *not* built on `walk()`, which the two directed views share.
  // `walk` puts every seed on layer 0 and measures distance from there — but a
  // module normally declares a base class and its subclasses together, so all
  // of them are seeds, and the whole hierarchy collapsed onto one row
  // (observed: Lib.Cache.Opts sat beside its own LoadOpts/SaveOpts). Depth
  // here has to come from the inheritance relation itself, not from distance
  // to whatever the reader happened to center on.
  //
  // So: take the connected component around the seeds, then layer it by
  // longest path from a root — depth(c) = 0 when c has no parent in the
  // component, else 1 + max(depth(parents)). Longest rather than shortest is
  // what guarantees a class always renders strictly below *every* one of its
  // parents, including in a diamond where one path is shorter than the other.
  function layoutInheritance(startId){
    var center = byId[startId];
    var seeds = (center.types_detail || [])
      .filter(function(t){ return inInheritance[t.name]; })
      .map(function(t){ return t.name; });
    if(seeds.length === 0) return { layers: [], included: {}, count: 0, truncated: false, edges: [] };

    // Connected component, walking parents and children alike.
    var inComp = {}, queue = seeds.slice(), qi = 0, truncated = false;
    seeds.forEach(function(s){ inComp[s] = true; });
    while(qi < queue.length){
      var cur = queue[qi++];
      var step = function(e, other){
        if(!classByName[other] || inComp[other]) return;
        if(Object.keys(inComp).length >= MAX_HNODES){ truncated = true; return; }
        inComp[other] = true;
        queue.push(other);
      };
      (extUp[cur] || []).forEach(function(e){ step(e, e.to_class); });
      (extDown[cur] || []).forEach(function(e){ step(e, e.from_class); });
    }

    // Longest-path depth, memoized. `state` also guards against a cycle:
    // `---@class A : B` plus `---@class B : A` is nonsense LuaLS would still
    // hand over, and without the guard this recursion would not terminate.
    var depth = {}, state = {};
    function depthOf(name){
      if(state[name] === 2) return depth[name];
      if(state[name] === 1) return 0; // cycle: stop contributing
      state[name] = 1;
      var d = 0;
      (extUp[name] || []).forEach(function(e){
        if(inComp[e.to_class]) d = Math.max(d, depthOf(e.to_class) + 1);
      });
      depth[name] = d; state[name] = 2;
      return d;
    }
    Object.keys(inComp).forEach(depthOf);

    var layers = [], included = {}, count = 0;
    Object.keys(inComp).sort().forEach(function(name){
      var d = depth[name];
      included[name] = d;
      (layers[d] = layers[d] || []).push(name);
      count++;
    });
    for(var i = 0; i < layers.length; i++){ layers[i] = layers[i] || []; }

    var edges = [];
    extendsEdges.forEach(function(e){
      if(included[e.from_class] !== undefined && included[e.to_class] !== undefined){
        edges.push({ from: e.from_class, to: e.to_class, cls: "hedge hedge-ext",
                     marker: "ext", label: "extends " + e.to_class });
      }
    });

    // Named explicitly rather than left to "first box of the first layer":
    // base classes occupy layer 0, so that shortcut (which the Types view can
    // rely on) would ring a parent instead of the class being looked at.
    return { layers: layers, included: included, count: count,
             truncated: truncated, edges: edges, centerKey: seeds[0] };
  }

  // =====================================================================
  // Deps and Calls: the two directed views.
  //
  // Both are the same walk over different adjacency, so it is written once.
  // `dir` decides which way the walk runs: "out" follows edges forwards
  // (what this needs / calls), "in" follows them backwards (what needs /
  // calls this), "both" runs each independently from the same seeds and
  // places the results above and below the center.
  //
  // Running the two sides separately for "both" is not an optimisation, it is
  // the correct semantics: once a walk has gone *up* into callers, continuing
  // it downwards through those callers' other callees would fill the diagram
  // with functions that have nothing to do with the center. Doxygen's caller
  // graph makes the same choice.
  // =====================================================================
  function walk(seeds, adj, keyOf, dir, maxDepth, exists){
    var depth = {}, count = 0, truncated = false;

    seeds.forEach(function(k){
      if(exists(k) && depth[k] === undefined && count < MAX_HNODES){
        depth[k] = 0; count++;
      }
    });

    function side(sign, adjMap, pick){
      var queue = Object.keys(depth).filter(function(k){ return depth[k] === 0; })
        .map(function(k){ return { key: k, d: 0 }; });
      while(queue.length){
        var it = queue.shift();
        if(maxDepth > 0 && Math.abs(it.d) >= maxDepth) continue;
        var list = adjMap[it.key] || [];
        for(var i = 0; i < list.length; i++){
          var nxt = pick(list[i]);
          if(!exists(nxt) || depth[nxt] !== undefined) continue;
          if(count >= MAX_HNODES){ truncated = true; return; }
          depth[nxt] = it.d + sign;
          count++;
          queue.push({ key: nxt, d: it.d + sign });
        }
      }
    }

    if(dir === "out" || dir === "both") side(1, adj.out, keyOf.to);
    if(dir === "in" || dir === "both") side(-1, adj.in, keyOf.from);

    // Depths can be negative in "both" mode; layers is a dense array, so the
    // whole thing is shifted down by the deepest caller level.
    var min = 0;
    Object.keys(depth).forEach(function(k){ if(depth[k] < min) min = depth[k]; });

    var layers = [], included = {};
    Object.keys(depth).sort().forEach(function(k){
      var idx = depth[k] - min;
      included[k] = idx;
      (layers[idx] = layers[idx] || []).push(k);
    });
    for(var i = 0; i < layers.length; i++){ layers[i] = layers[i] || []; }

    return { layers: layers, included: included, count: count, truncated: truncated };
  }

  // Requires that resolve to nothing in the scanned tree, materialized into
  // boxes on demand. One box per module however many nodes reach for it —
  // "these four all pull in plenary" is the thing worth seeing, and four
  // separate boxes would hide exactly that. Keyed "ext:<module>" so they can
  // never collide with a node id, and given no `nodeId`, which is what stops
  // click, double-click and the context menu from offering to navigate into
  // something the map knows nothing about.
  function addExternals(built, maxDepth){
    var depthOf = {};
    Object.keys(built.included).forEach(function(id){
      ((byId[id] || {}).requires_external || []).forEach(function(mod){
        var key = "ext:" + mod;
        var d = built.included[id] + 1;
        if(maxDepth > 0 && d > maxDepth) return;
        if(depthOf[key] === undefined || d > depthOf[key]) depthOf[key] = d;
      });
    });

    Object.keys(depthOf).sort().forEach(function(key){
      if(built.count >= MAX_HNODES){ built.truncated = true; return; }
      var d = depthOf[key];
      while(built.layers.length <= d) built.layers.push([]);
      built.layers[d].push(key);
      built.included[key] = d;
      built.count++;
    });

    Object.keys(built.included).forEach(function(id){
      if(id.indexOf("ext:") === 0) return;
      ((byId[id] || {}).requires_external || []).forEach(function(mod){
        var key = "ext:" + mod;
        if(built.included[key] === undefined) return;
        built.edges.push({
          from: id, to: key,
          cls: "hedge hedge-dep external",
          marker: "dep",
          label: "requires " + mod + " (outside this map)"
        });
      });
    });
  }

  function layoutDeps(startId, dir, maxDepth, showExternal){
    var keyOf = { from: function(e){ return e.from; }, to: function(e){ return e.to; } };
    var built = walk([startId], { out: depOut, in: depIn }, keyOf, dir, maxDepth,
      function(k){ return !!byId[k]; });

    var edges = [];
    (IR.edges || []).forEach(function(e){
      if(e.kind !== "require") return;
      if(built.included[e.from] === undefined || built.included[e.to] === undefined) return;
      edges.push({
        from: e.from, to: e.to,
        cls: "hedge hedge-dep" + (e.deferred ? " deferred" : ""),
        marker: "dep",
        label: (e.deferred ? "lazy require " : "require ") + e.to_module + ":" + e.line
      });
    });
    built.edges = edges;
    if(showExternal) addExternals(built, maxDepth);
    return built;
  }

  function layoutCalls(startId, startFn, dir, maxDepth){
    var keyOf = {
      from: function(e){ return fnKey(e.from, e.from_fn); },
      to: function(e){ return fnKey(e.to, e.to_fn); }
    };
    // Centering on a node rather than a single function seeds every function
    // it declares: "what does this module call" is the question asked from
    // the node's own detail pane, and answering it one function at a time
    // would mean opening the view once per function.
    var seeds;
    if(startFn && fnByKey[startFn]){
      seeds = [startFn];
    } else {
      var n = byId[startId];
      seeds = ((n && n.functions) || []).map(function(fn){ return fnKey(startId, fn.name); });
    }

    var built = walk(seeds, { out: callOut, in: callIn }, keyOf, dir, maxDepth,
      function(k){ return !!fnByKey[k]; });

    var edges = [];
    (IR.edges || []).forEach(function(e){
      if(e.kind !== "call") return;
      var a = keyOf.from(e), b = keyOf.to(e);
      if(built.included[a] === undefined || built.included[b] === undefined) return;
      edges.push({
        from: a, to: b,
        cls: "hedge hedge-call" + (e.confidence === "heuristic" ? " weak" : ""),
        marker: "call",
        label: (e.confidence === "heuristic" ? "guessed call, line " : "call, line ") + e.line
      });
    });
    built.edges = edges;
    return built;
  }

  // Module Calls view: same shape as layoutDeps, but walking the
  // module-to-module edges collapsed above (moduleCallOut/moduleCallIn)
  // instead of per-function call edges — one weighted arrow per pair of
  // modules rather than one per call site.
  function layoutModuleCalls(startId, dir, maxDepth, showExternal){
    var keyOf = { from: function(e){ return e.from; }, to: function(e){ return e.to; } };
    var built = walk([startId], { out: moduleCallOut, in: moduleCallIn }, keyOf, dir, maxDepth,
      function(k){ return !!byId[k]; });

    var edges = [];
    Object.keys(moduleCallEdgeByPair).forEach(function(key){
      var e = moduleCallEdgeByPair[key];
      if(built.included[e.from] === undefined || built.included[e.to] === undefined) return;
      edges.push({
        from: e.from, to: e.to,
        cls: "hedge hedge-call",
        marker: "call",
        label: e.weight + " call" + (e.weight === 1 ? "" : "s"),
        weight: e.weight
      });
    });
    built.edges = edges;
    if(showExternal) addModuleCallExternals(built, maxDepth);
    return built;
  }

  // Same idea as addExternals, but sourcing node.calls_external — which,
  // unlike requires_external, can have several entries per module (one per
  // distinct member called), so weights are summed per (node, module) pair
  // before boxes/edges are built.
  function addModuleCallExternals(built, maxDepth){
    var idModuleWeight = {};
    Object.keys(built.included).forEach(function(id){
      if(id.indexOf("ext:") === 0) return;
      ((byId[id] || {}).calls_external || []).forEach(function(c){
        var byMod = idModuleWeight[id] || (idModuleWeight[id] = {});
        byMod[c.module] = (byMod[c.module] || 0) + c.count;
      });
    });

    var depthOf = {};
    Object.keys(idModuleWeight).forEach(function(id){
      Object.keys(idModuleWeight[id]).forEach(function(mod){
        var key = "ext:" + mod;
        var d = built.included[id] + 1;
        if(maxDepth > 0 && d > maxDepth) return;
        if(depthOf[key] === undefined || d > depthOf[key]) depthOf[key] = d;
      });
    });

    Object.keys(depthOf).sort().forEach(function(key){
      if(built.count >= MAX_HNODES){ built.truncated = true; return; }
      var d = depthOf[key];
      while(built.layers.length <= d) built.layers.push([]);
      built.layers[d].push(key);
      built.included[key] = d;
      built.count++;
    });

    Object.keys(idModuleWeight).forEach(function(id){
      Object.keys(idModuleWeight[id]).forEach(function(mod){
        var key = "ext:" + mod;
        if(built.included[key] === undefined) return;
        var weight = idModuleWeight[id][mod];
        built.edges.push({
          from: id, to: key,
          cls: "hedge hedge-call external",
          marker: "call",
          label: weight + " call" + (weight === 1 ? "" : "s") + " to " + mod + " (outside this map)",
          weight: weight
        });
      });
    });
  }

  function layerPositions(layers){
    var lr = isLR();
    // The extent of the widest layer, across the axis a layer spreads on.
    var span = 0;
    layers.forEach(function(layer){
      if(!layer) return;
      var n = layer.length;
      span = Math.max(span, lr
        ? n * BOX_H + (n - 1) * GAP_Y
        : n * BOX_W + (n - 1) * GAP_X);
    });
    var positions = {};
    layers.forEach(function(layer, d){
      if(!layer) return;
      var n = layer.length;
      var own = lr ? n * BOX_H + (n - 1) * GAP_Y : n * BOX_W + (n - 1) * GAP_X;
      // Layers are centred against the widest one, so the graph reads as a
      // shape rather than as a left-aligned staircase.
      var start = PAD + (span - own) / 2;
      layer.forEach(function(key, i){
        positions[key] = lr
          ? { x: PAD + d * (BOX_W + GAP_X), y: start + i * (BOX_H + GAP_Y) }
          : { x: start + i * (BOX_W + GAP_X), y: PAD + d * (BOX_H + GAP_Y) };
      });
    });
    return { positions: positions, maxRowWidth: span };
  }

  // =====================================================================
  // Box specs: one place that knows what a box in each view says. Returns a
  // class, its markup, a tooltip and the node the box ultimately belongs to
  // (a class box and a function box both resolve back to a node, which is
  // what click-to-select and the context menu act on).
  // =====================================================================
  function boxSpec(key, view){
    if(key.indexOf("ext:") === 0){
      var mod = key.slice(4);
      // Resolved through opts.tag_files (Doxygen TAGFILES equivalent) or
      // opts.external_repos (a guessed/verified GitHub link) — either way a
      // box that isn't part of *this* map stops being an inert dead end and
      // opens somewhere real.
      var link = (IR.tag_links || {})[mod];

      // "Why is this here" — every function of `mod` this tree actually
      // calls, not just the bare "X is required" fact `requires_external`
      // already drew before this existed. Absent (not empty) when nothing
      // resolved: a require kept purely for side effects, or a call shape
      // `core/calls.lua`'s four resolvable forms cannot see — a real
      // difference from "resolved and found zero calls", which cannot
      // happen (a module with a resolved call is why this entry exists).
      var byMember = getExternalCallTotals()[mod];
      var callTotal = 0;
      var callLines = [];
      if(byMember){
        var members = Object.keys(byMember);
        members.sort(function(a, b){
          if(byMember[a] !== byMember[b]) return byMember[b] - byMember[a];
          return a < b ? -1 : (a > b ? 1 : 0);
        });
        members.forEach(function(m){
          var n = byMember[m];
          callTotal += n;
          callLines.push((m ? mod + "." + m : mod) + " (" + n + "×)");
        });
      }

      var baseTitle = link
        ? mod + " — open " + link.title + " in its own map"
        : mod + " — required here but not part of this map";
      var title = callLines.length ? baseTitle + "\n" + callLines.join("\n") : baseTitle;

      return {
        cls: "hnode k-external" + (link ? " linked" : ""),
        title: title,
        html: '<div class="hnm">' + esc(mod) + '</div>' +
              '<div class="hkind">external' + (link ? " ↗" : "") +
              (callTotal ? "  ·  " + callTotal + " call" + (callTotal === 1 ? "" : "s") : "") +
              '</div>',
        nodeId: null, recenter: null, externalHtml: link && link.html
      };
    }
    // Both class-keyed views. Inheritance boxes carry the parent list as the
    // second line instead of the bare kind: in a diagram *about* inheritance,
    // "class" on every box says nothing, and the declared `: A, B` is exactly
    // what the reader is checking the arrows against.
    if(view === "types" || view === "inheritance"){
      var cls = classByName[key];
      if(!cls) return null;
      var sub = cls.info.kind;
      if(view === "inheritance"){
        var ps = cls.info.extends || [];
        sub = ps.length ? ": " + ps.join(", ") : "base";
      }
      return {
        cls: "hnode t-" + cls.info.kind,
        title: cls.info.desc || key,
        html: '<div class="hnm">' + esc(key) + '</div>' +
              '<div class="hkind">' + esc(sub) + '</div>',
        nodeId: cls.nodeId, recenter: cls.nodeId
      };
    }
    if(view === "calls"){
      var entry = fnByKey[key];
      if(!entry) return null;
      return {
        cls: "hnode k-fn",
        title: (entry.fn.summary || entry.fn.signature) + "\n" +
               (entry.node.module || entry.node.path),
        html: '<div class="hnm">' + esc(entry.fn.signature) + '</div>' +
              '<div class="hline">' + esc(entry.node.name) + ':' + entry.fn.line + '</div>',
        nodeId: entry.node.id, recenter: entry.node.id, fnKey: key
      };
    }
    var n = byId[key];
    if(!n) return null;
    // The Deps view labels boxes by module path rather than directory name:
    // a require graph is read in module terms, and half this tree's
    // directories are called `init`-shaped things that are ambiguous alone.
    var label = (view === "deps" || view === "modulecalls") ? (n.module || n.name) : n.name;
    return {
      cls: "hnode k-" + n.kind,
      title: n.summary || n.name,
      html: '<div class="hnm">' + esc(label) + '</div>' +
            (n.summary ? '<div class="hsm">' + prose(n.summary) + '</div>' : ''),
      nodeId: n.id, recenter: n.id
    };
  }

  // =====================================================================
  // Keyed reconcile — the reason re-centering moves instead of cutting.
  //
  // Boxes are held in `hboxes` by key and reused across redraws, so a box
  // present before and after a re-center is the *same element* at a new
  // left/top, and the CSS transition on .hnode animates it there. Rebuilding
  // the subtree with innerHTML = "" (what this used to do) threw that
  // identity away every time, which is why every navigation was a hard cut
  // even though the two layouts often shared most of their boxes.
  //
  // Positions are still computed analytically from the IR, never measured off
  // the DOM — that is what lets the diagram be correct while the pane is
  // display:none, and animating does not change it.
  // =====================================================================
  var hboxes = {};
  var hpending = {};
  var ANIM_MS = 340;

  function reconcile(positions, view, centerKey){
    var moved = false;

    Object.keys(positions).forEach(function(key){
      var spec = boxSpec(key, view);
      if(!spec) return;
      var pos = positions[key];
      var el = hboxes[key];

      if(el){
        // A box that was mid-exit and is wanted again: cancel the removal
        // rather than let the timer delete a live element out from under us.
        if(hpending[key]){ clearTimeout(hpending[key]); delete hpending[key]; }
        if(parseFloat(el.style.left) !== pos.x || parseFloat(el.style.top) !== pos.y) moved = true;
      } else {
        el = document.createElement("div");
        el.dataset.key = key;
        el.style.left = pos.x + "px";
        el.style.top = pos.y + "px";
        el.classList.add("entering");
        hstage.appendChild(el);
        hboxes[key] = el;
      }

      var entering = el.classList.contains("entering");
      el.className = spec.cls + (key === centerKey ? " center" : "") + (entering ? " entering" : "");
      el.style.left = pos.x + "px";
      el.style.top = pos.y + "px";
      el.style.width = BOX_W + "px";
      el.title = spec.title;
      el.innerHTML = spec.html;
      el._spec = spec;
    });

    Object.keys(hboxes).forEach(function(key){
      if(positions[key] !== undefined || hpending[key]) return;
      var el = hboxes[key];
      el.classList.add("leaving");
      hpending[key] = setTimeout(function(){
        delete hpending[key];
        if(hboxes[key] === el){ delete hboxes[key]; }
        if(el.parentNode) el.parentNode.removeChild(el);
      }, ANIM_MS);
    });

    // Entering boxes need one frame at opacity 0 before the class comes off,
    // or the browser coalesces both styles into the final one and there is no
    // transition to run.
    requestAnimationFrame(function(){
      Object.keys(hboxes).forEach(function(key){
        hboxes[key].classList.remove("entering");
      });
    });

    return moved;
  }

  // Arrowheads: a tree needs none (the layout says which way is down), a
  // directed graph does — an edge between two boxes on the same layer, or a
  // backedge, is otherwise unreadable. One marker per edge colour, coloured
  // from CSS so the dark-mode palette applies to them too.
  function buildDefs(svgNS){
    var defs = document.createElementNS(svgNS, "defs");
    ["tree", "type", "ext", "dep", "call"].forEach(function(name){
      var m = document.createElementNS(svgNS, "marker");
      m.id = "m-" + name;
      m.setAttribute("viewBox", "0 0 8 8");
      m.setAttribute("refX", "7"); m.setAttribute("refY", "4");
      m.setAttribute("markerWidth", "7"); m.setAttribute("markerHeight", "7");
      m.setAttribute("orient", "auto-start-reverse");
      var p = document.createElementNS(svgNS, "path");
      p.setAttribute("d", "M0,0 L8,4 L0,8 z");
      m.appendChild(p);
      defs.appendChild(m);
    });
    return defs;
  }

  // Written as objects rather than nested arrays for a mundane reason worth
  // knowing before editing this file: the whole script lives inside a Lua
  // long string, and two adjacent closing square brackets terminate it —
  // which is exactly what an array of arrays ends with. The rest of the
  // script then parses as Lua source. Avoid that pair anywhere in here.
  function sw(mod, text){ return { sw: mod, text: text }; }
  var LEGEND = {
    modules: [ sw("", "contains"), sw("type", "type reference") ],
    types:   [ sw("type", "field references class") ],
    inheritance: [ sw("ext", "inherits from (arrow points at the base class)") ],
    deps:    [ sw("dep", "requires at load time"),
               sw("dep deferred", "lazy require (inside a function)") ],
    depsExt: [ sw("dep external", "requires something outside this map") ],
    calls:   [ sw("call", "calls"),
               sw("call weak", "guessed call (--calls-heuristic)") ]
  };

  function drawLegend(view){
    var entries = (LEGEND[view] || []).slice();
    if(view === "deps" && state.ext) entries = entries.concat(LEGEND.depsExt);
    var items = entries.map(function(it){
      return '<span class="lg"><span class="sw ' + it.sw + '"></span>' + esc(it.text) + '</span>';
    });
    items.push('<span class="lg">wheel zooms · shift+wheel pans · ' +
      (isGraphView(view) ? 'zoom past the edge changes depth' : 'zoom right in to open a module') +
      ' · right-click for more</span>');
    hlegendEl.innerHTML = items.join("");
  }

  function emptyMessage(view, center){
    if(view === "types"){
      return typeEdges.length
        ? '<p class="hmsg">' + esc(center.name) + ' has no <code>@class</code>/<code>@alias</code> of its own — pick a module with type definitions, or switch back to Modules.</p>'
        : '<p class="hmsg">No type data in this map — regenerate with <code>:DocMap full</code> (or <code>--full</code>) to include lua-language-server class/alias detail.</p>';
    }
    if(view === "inheritance"){
      if(!typeEdges.length && !extendsEdges.length){
        return '<p class="hmsg">No type data in this map — regenerate with <code>:DocMap full</code> (or <code>--full</code>) to include lua-language-server class detail.</p>';
      }
      return extendsEdges.length
        ? '<p class="hmsg">None of ' + esc(center.name) + '’s classes take part in an inheritance relation (<code>---@class Child : Parent</code>).</p>'
        : '<p class="hmsg">No class in this map declares a parent — nothing to draw an inheritance tree from.</p>';
    }
    if(view === "deps"){
      return '<p class="hmsg">' + esc(center.name) + ' neither requires nor is required by anything in this map.</p>';
    }
    if(view === "calls"){
      return (center.functions || []).length
        ? '<p class="hmsg">None of ' + esc(center.name) + '’s functions call — or are called by — anything the scanner could resolve. Dynamic dispatch is invisible to it; see the module README.</p>'
        : '<p class="hmsg">' + esc(center.name) + ' declares no functions.</p>';
    }
    if(view === "modulecalls"){
      return '<p class="hmsg">' + esc(center.name) + ' has no resolved call edges to or from another module — either it doesn’t call across module boundaries, or nothing else calls into it.</p>';
    }
    return '<p class="hmsg">Nothing to draw here.</p>';
  }

  function clearGraph(){
    Object.keys(hpending).forEach(function(k){ clearTimeout(hpending[k]); });
    hpending = {};
    hboxes = {};
    hstage.innerHTML = "";
    // The empty-state message hangs off #hgraph, outside the stage, so
    // clearing the stage alone would stack a second copy on the next empty
    // draw instead of replacing the first.
    var msg = hgraph.querySelector(".hmsg");
    if(msg) msg.remove();
  }

  var VIEWS = { modules: 1, types: 1, inheritance: 1, deps: 1, calls: 1, modulecalls: 1 };

  // =====================================================================
  // Notes tab: Doxygen's Deprecated / Todo / Bug / Test lists.
  //
  // Four aggregates over data the scan already has, in one tab rather than
  // four pages: three of these tags are usually unused in a given tree, and
  // four tabs that are empty most of the time would be four tabs of noise.
  // Sections with no entries say so instead of vanishing, so "nothing is
  // deprecated" is distinguishable from "this build forgot to collect it".
  //
  // Not a `check` finding, deliberately: none of these is drift or an error,
  // and routing them through findings would put author to-dos into an exit
  // code that CI fails on.
  // =====================================================================
  var NOTE_KINDS = [
    { key: "deprecated", title: "Deprecated", scalar: true,
      sub: "Functions marked ---@deprecated. The text is the migration hint the author left." },
    { key: "todo", title: "Todo",
      sub: "Open ---@todo entries, one line per occurrence." },
    { key: "bug", title: "Bug",
      sub: "Known defects recorded with ---@bug, still present in the code." },
    { key: "test", title: "Test",
      sub: "---@test notes: what covers this function, or what still needs covering." }
  ];

  function collectNotes(kind){
    var out = [];
    IR.nodes.forEach(function(n){
      (n.functions || []).forEach(function(fn){
        var v = fn[kind.key];
        if(kind.scalar){
          if(v) out.push({ node: n, fn: fn, text: v });
          return;
        }
        (v || []).forEach(function(entry){ out.push({ node: n, fn: fn, text: entry }); });
      });
    });
    // By where it lives, then by line: reading a list of todos is reading a
    // to-do list per module, not an alphabet of function names.
    out.sort(function(a, b){
      var am = a.node.module || a.node.path, bm = b.node.module || b.node.path;
      if(am !== bm) return am < bm ? -1 : 1;
      return a.fn.line - b.fn.line;
    });
    return out;
  }

  // =====================================================================
  // Marker comments — the other half of the Notes tab.
  //
  // The annotation sections above read `---@todo` and friends off function
  // doc blocks. These read `-- TODO:`, `// FIXME:`, `-- PERF:` off the
  // source text, wherever they sit. Two collectors and two section groups
  // rather than one merged list, because the two answer different
  // questions: an annotation is a claim about a function and is shown
  // beside its signature, a marker is a claim about a line and is shown
  // with its location. Merging them would produce rows whose function name
  // is a guess.
  //
  // `core/markers.lua` decided which keywords exist and what each means;
  // `IR.marker_kinds` carries that table so this code names none of them.
  // =====================================================================

  function collectMarkers(){
    var byKind = {};
    IR.nodes.forEach(function(n){
      (n.markers || []).forEach(function(m){
        (byKind[m.kind] = byKind[m.kind] || []).push({ node: n, m: m });
      });
    });
    // By file, then by line — the order they would be read in, not the
    // order the walk happened to produce them in.
    Object.keys(byKind).forEach(function(kind){
      byKind[kind].sort(function(a, b){
        var ap = a.node.source || a.node.path, bp = b.node.source || b.node.path;
        if(ap !== bp) return ap < bp ? -1 : 1;
        return a.m.line - b.m.line;
      });
    });
    return byKind;
  }

  function markerItem(it){
    var where = (it.node.source || it.node.path) + ":" + it.m.line;
    var bits = ['<li><a class="nfn" tabindex="0" role="button" data-node="' +
      esc(it.node.id) + '">' + esc(where) + "</a>"];
    // The spelling the author typed, shown only when it differs from the
    // section it landed in: a `BUG:` under the FIX heading needs saying, a
    // `TODO:` under TODO does not.
    if(it.m.word && it.m.word !== it.m.kind){
      bits.push('<span class="nword">' + esc(it.m.word) + "</span>");
    }
    if(it.m.author){
      // Prefixed and given its own class: beside a file path, a bare name
      // reads as another piece of the location.
      bits.push('<span class="nauthor">@' + esc(it.m.author) + "<\/span>");
    }
    bits.push('<div class="ntext">' + (it.m.text ? esc(it.m.text) : "&mdash;") + "</div></li>");
    return bits.join("");
  }

  function drawMarkers(parts){
    var kinds = IR.marker_kinds || [];
    var byKind = collectMarkers();
    var total = 0;
    kinds.forEach(function(k){ total += (byKind[k.name] || []).length; });

    parts.push('<h3 class="ngroup">Marker comments<span class="ncount">' +
      total + "</span></h3>");
    parts.push('<p class="nsub">Keywords written in ordinary comments — ' +
      '<code>-- TODO:</code>, <code>// FIXME:</code>, <code>-- PERF:</code> — ' +
      "read from the source text rather than from an annotation. The same " +
      "keyword set <code>todo-comments.nvim</code> highlights in the editor, " +
      "so what is coloured in the buffer is what is listed here.</p>");

    // An artifact generated before marker scanning existed carries no
    // `markers` key at all, and rendering that as "nothing to do" would be
    // the exact silent-degradation failure this page keeps being caught by.
    // Schema 4 is where the field arrived.
    if(!((IR.meta || {}).schema >= 4)){
      parts.push('<p class="ntext none">This map predates marker scanning. ' +
        "Regenerate it to list them.</p>");
      return;
    }

    var empty = [];
    kinds.forEach(function(k){
      var items = byKind[k.name] || [];
      if(items.length === 0){ empty.push(k.name); return; }
      parts.push("<h3>" + esc(k.name) +
        '<span class="ncount">' + items.length + "</span></h3>");
      parts.push('<p class="nsub">' + esc(k.sub) + "</p>");
      parts.push('<ul class="nlist">');
      items.forEach(function(it){ parts.push(markerItem(it)); });
      parts.push("</ul>");
    });

    // The keywords that found nothing get one line between them rather than
    // a heading each: seven empty sections is the whole tab, and this page's
    // rule is density on demand, never on screen.
    if(empty.length === kinds.length){
      parts.push('<p class="ntext none">No marker comments in this map.</p>');
    } else if(empty.length){
      parts.push('<p class="ntext none">Nothing marked ' +
        esc(empty.join(", ")) + ".</p>");
    }
  }

  var notesDrawn = false;
  function drawNotes(){
    if(notesDrawn) return; // static over one IR; nothing invalidates it
    notesDrawn = true;

    var host = document.getElementById("view-notes");
    var parts = [];

    // Named rather than implied. Before this heading existed the tab
    // opened straight into `Deprecated 0 / Todo 0 / Bug 0`, which reads as
    // "this repository has nothing outstanding" -- and was reported as
    // exactly that misreading by an author whose tree is full of
    // `-- TODO:`. Those four sections were never counting comments.
    parts.push('<h3 class="ngroup">Annotations<\/h3>');
    parts.push('<p class="nsub">Tags written in a documentation block, shown '
      + 'beside the function they describe. Comment markers such as '
      + '<code>-- TODO:<\/code> are a separate list, further down.<\/p>');
    NOTE_KINDS.forEach(function(kind){
      var items = collectNotes(kind);
      parts.push('<h3>' + esc(kind.title) +
        '<span class="ncount">' + items.length + '</span></h3>');
      parts.push('<p class="nsub">' + esc(kind.sub) + '</p>');
      if(items.length === 0){
        parts.push('<p class="ntext none">No function carries <code>---@' +
          esc(kind.key) + '<\/code>. Comment markers are listed under Marker comments below.<\/p>');
        return;
      }
      parts.push('<ul class="nlist">');
      items.forEach(function(it){
        parts.push('<li><a class="nfn" tabindex="0" role="button" data-node="' + esc(it.node.id) + '">' +
          esc(it.fn.signature) + '</a>' +
          sigTrigger(it.node.id, it.fn.name) + docTrigger(fnKey(it.node.id, it.fn.name)) +
          '<span class="nwhere">' + esc(it.node.module || it.node.path) +
          ':' + it.fn.line + '</span>' +
          '<div class="ntext">' + (it.text ? esc(it.text) : "&mdash;") + '</div></li>');
      });
      parts.push("</ul>");
    });
    drawMarkers(parts);

    host.innerHTML = parts.join("");

    host.querySelectorAll(".nfn").forEach(function(a){
      a.addEventListener("click", function(){
        navigate({ tab: "tree", id: a.dataset.node });
      });
    });
  }

  // =====================================================================
  // Features tab: this repo's own docs/FEATURES/, read by
  // core/features.lua — see docs/FEATURES_FORMAT.md for the format.
  //
  // An index, not a Markdown viewer, the same shape the Plugins/Tools
  // Analysis panels already are: name, summary, metadata — never the full
  // prose that may follow a feature's bullets in its own file. That prose
  // stays exactly where the author put it; the card's own path links out to
  // it instead of re-rendering it here.
  //
  // A plain key/value list, not a table, because the metadata keys are not
  // fixed columns — one feature may carry Module/Keymaps/Config, another
  // Module/Command/Autocmd, and `docs/FEATURES_FORMAT.md` deliberately
  // never constrains the vocabulary (see that file's own header for why a
  // whitelist would reject real, working documentation).
  // =====================================================================

  // One line per bullet's first backtick-quoted token, matched against
  // every node's own `source`/`path` — the same "endswith" leniency
  // `tag_links` resolution already extends to stale cross-references
  // elsewhere on this page. `null` when nothing in `meta` names a `Module`
  // bullet, or nothing in the tree matches it; never thrown.
  function resolveModuleNode(meta){
    var mod = null;
    meta.forEach(function(m){
      if(!mod && /^module$/i.test(m.key)) mod = m.value;
    });
    if(!mod) return null;
    var token = (mod.match(/`([^`]+)`/) || [])[1];
    if(!token) return null;
    token = token.replace(/\\/g, "/");
    var found = null;
    IR.nodes.forEach(function(n){
      if(found) return;
      var p = (n.source || n.path || "").replace(/\\/g, "/");
      if(p && (p === token || p.slice(-token.length) === token)) found = n.id;
    });
    return found;
  }

  // A theme filename as the tab's own heading: an already-uppercase name
  // (`UI`, `PERFORMANCE`) is left alone but for its separators, since
  // title-casing it would just be re-uppercasing what is already upper;
  // anything else (`headings`, `editing-and-handlers`) is title-cased.
  function themeTitle(theme){
    var spaced = theme.replace(/[_-]+/g, " ");
    if(/^[A-Z0-9 ]+$/.test(spaced)) return spaced;
    return spaced.replace(/\b\w/g, function(c){ return c.toUpperCase(); });
  }

  var featuresDrawn = false;
  function drawFeatures(){
    if(featuresDrawn) return; // static over one IR; nothing invalidates it
    featuresDrawn = true;

    var host = document.getElementById("view-features");
    var feats = IR.features;
    var parts = ['<div class="feat-wrap">'];

    if(!feats){
      parts.push('<p class="ntext none">No <code>docs/FEATURES/</code> (or ' +
        '<code>docs/features/</code>) folder in this repo — see ' +
        '<code>docs/FEATURES_FORMAT.md</code> for the convention this tab reads.</p>');
      parts.push("</div>");
      host.innerHTML = parts.join("");
      return;
    }

    if(feats.intro){
      // Through the same Markdown-subset renderer a promoted feature's body
      // uses, not `esc`. This text is the top of somebody's FEATURES.md and
      // is written as Markdown — escaping it printed `#`, `**` and
      // `[text](url)` literally and ran every heading, list and paragraph
      // together into one wall, which is what the folder's own intro looked
      // like in every generated map until now.
      parts.push('<div class="feat-intro">' + renderFeatureBody(feats.intro) + '</div>');
    }

    // A `Tab: true` feature has its own top-level tab (see
    // collectPromotedFeatures/drawFeatureTab below) and is left out of this
    // catalog entirely, counts included — showing it as both a card here
    // and a tab of its own would be the same feature listed twice for no
    // reason, and the whole point of promoting one is that it no longer
    // needs the card.
    var totalFeatures = 0;
    feats.files.forEach(function(f){
      f.entries.forEach(function(e){ if(!e.tab) totalFeatures++; });
    });
    parts.push('<p class="nsub">' + totalFeatures + ' feature' +
      (totalFeatures === 1 ? '' : 's') + ' across ' + feats.files.length + ' file' +
      (feats.files.length === 1 ? '' : 's') + ' in <code>' + esc(feats.folder) + '</code>.</p>');

    feats.files.forEach(function(f){
      var visible = f.entries.filter(function(e){ return !e.tab; });
      parts.push('<h3 class="nhead">' + esc(themeTitle(f.theme)) +
        '<span class="ncount">' + visible.length + '</span></h3>');
      if(f.intro){
        // Same reason as the folder intro above: a file's own preamble is
        // Markdown too.
        parts.push('<div class="nsub feat-fileintro">' + renderFeatureBody(f.intro) + '</div>');
      }
      if(f.entries.length === 0){
        parts.push('<p class="ntext none">No <code>##</code> sections in this file.</p>');
        return;
      }
      if(visible.length === 0){
        parts.push('<p class="ntext none">Every feature in this file is promoted to its ' +
          'own tab — see the tab bar.</p>');
        return;
      }
      visible.forEach(function(e){
        var nodeId = resolveModuleNode(e.meta);
        parts.push('<div class="feat-card">');
        parts.push('<div class="feat-name"' +
          (nodeId ? ' data-node="' + esc(nodeId) + '" tabindex="0" role="button"' : '') +
          '>' + esc(e.name) + '</div>');
        if(e.summary){
          parts.push('<div class="feat-summary">' + prose(e.summary) + '</div>');
        }
        if(e.meta.length){
          parts.push('<div class="feat-meta">');
          e.meta.forEach(function(m){
            parts.push('<div class="feat-meta-row"><b>' + esc(m.key) + ':</b> <span>' +
              esc(m.value) + '</span></div>');
          });
          parts.push("</div>");
        }
        parts.push('<div class="feat-src"><a href="#" data-src="' + esc(f.path) + '">' +
          esc(f.path) + ':' + e.line + '</a></div>');
        parts.push("</div>");
      });
    });

    parts.push("</div>");
    host.innerHTML = parts.join("");

    host.querySelectorAll(".feat-name[data-node]").forEach(function(el){
      el.addEventListener("click", function(){
        navigate({ tab: "tree", id: el.dataset.node });
      });
    });
    host.querySelectorAll(".feat-src a[data-src]").forEach(function(a){
      a.addEventListener("click", function(ev){
        ev.preventDefault();
        var u = srcUrl(a.dataset.src);
        window.open(u || rel(a.dataset.src), u ? "_blank" : "_self");
      });
    });
  }

  // =====================================================================
  // Promoted features: a `- **Tab:** true` bullet gets a feature its own
  // top-level tab instead of a card in the Features catalog above — see
  // docs/FEATURES_FORMAT.md "Promoting a feature to its own tab".
  // =====================================================================

  // Slugified once and cached, not recomputed per navigation: the tab
  // bar/view panels are built once at page load (buildPromotedTabs, called
  // from the boot sequence below), and every later lookup (applyState,
  // click handlers) needs the exact same slug that build produced.
  function featureSlug(name){
    return "feature-" + name.toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "");
  }

  // A tab label is a fixed, scarce surface — nine of them share one row —
  // and a promoted feature's name is a *heading*, written to be read in a
  // document. `The \`:Cmdlog <subcommand>\` command tree` is a good heading
  // and an unreadable tab: it crowds every other tab off the row and is
  // still too long to scan.
  //
  // Shortened rather than truncated where the name says how. A heading of
  // the form "The X …" is about X, and the backticked term in it is the
  // thing being named — so `:Cmdlog` survives and the sentence around it
  // does not. Only then does a hard cap apply, and the full name is always
  // in the tooltip.
  //
  // Deliberately not solved by asking authors to write shorter headings:
  // this page does not get to dictate how someone's FEATURES.md reads, and
  // a layout that only works for cooperative input is not a layout.
  function tabLabel(name){
    // Declared inside, not beside: `buildPromotedTabs` runs during boot,
    // which is before this point in the script body executes. A `var` at
    // file scope would be hoisted but still unassigned, and
    // `slice(0, undefined)` returns the whole string — so every label came
    // out full-length with an ellipsis glued on, which is the one outcome
    // worse than not shortening at all.
    var TAB_LABEL_MAX = 22;
    var s = String(name || "").trim();

    // A backticked term is the author naming the thing themselves; prefer it
    // over any guess this code could make.
    var quoted = s.match(/`([^`]+)`/);
    if(quoted && quoted[1].length <= TAB_LABEL_MAX) return quoted[1];

    s = s.replace(/^(The|A|An)\s+/i, "");
    if(s.length <= TAB_LABEL_MAX) return s;

    // Cut on a word boundary rather than mid-word: a label ending in "com…"
    // reads as broken, one ending in "command…" reads as shortened.
    var cut = s.slice(0, TAB_LABEL_MAX);
    var space = cut.lastIndexOf(" ");
    if(space > TAB_LABEL_MAX / 2) cut = cut.slice(0, space);
    return cut.replace(/[\s\-–—:,.]+$/, "") + "…";
  }

  // =====================================================================
  // "What is this?" — hover explanations for the page's own furniture
  //
  // Every tab, every mode inside one, and the findings disclosure says what
  // it *does* rather than repeating its label. A card that restates the
  // heading costs a hover and teaches nothing, so each text below is written
  // from what that view computes.
  //
  // One card, one attribute: anything carrying `data-explain` gets it. The
  // texts live in `EXPLAIN` keyed by the same value, in this file rather
  // than in the markup, because several of them are two sentences and
  // markup with prose in its attributes is markup nobody edits twice.
  //
  // **On the worry that a section means different things in different
  // tabs**: it was raised about "Drift findings", and that one turns out to
  // be a single element at the foot of the page shared by every tab — so
  // there is nothing to disambiguate there. Where a repeated heading *does*
  // mean different things, the key is what distinguishes them, not the
  // label: `index.functions` and `hierarchy.calls` are separate entries even
  // though both could be titled "functions".
  //
  // Reuses `.sigpop`'s styling the way the keyword card already does. A
  // third floating component with its own rules would be a third set of
  // rules to keep in step for no gain.
  // =====================================================================
  var EXPLAIN = {
    // ── The six graphs inside Hierarchy ──────────────────────────────
    //
    // Added because the outer tab explains the *tab* and each of these
    // computes something different from the same IR. Six of the controls
    // below used to carry a plain `title` instead, which this mechanism's
    // own `focusin` handler already argues against: a `title` never appears
    // on focus, so it left exactly the controls a keyboard user reaches as
    // the only ones with no explanation.
    "view.modules":
      "The directory hierarchy itself — every module and namespace, nested " +
      "the way the tree is. The one view with no direction, because " +
      "containment has none; the slider hides the top N levels instead.",
    "view.deps":
      "The require graph: an arrow means this module requires that one. " +
      "`+ external` adds the modules outside this map, each box naming the " +
      "functions actually called through it.",
    "view.calls":
      "Function-level callers and callees, resolved from real call sites " +
      "rather than guessed. A weak match is drawn dimmed rather than " +
      "hidden — see the Findings tab for what could not be resolved.",
    "view.modulecalls":
      "The same call graph collapsed module to module, with each edge " +
      "weighted by how many calls it carries. Answers which modules lean on " +
      "each other, where Calls answers which functions do.",
    "view.types":
      "How `@class` and `@alias` declarations reference each other through " +
      "their fields. Needs LuaLS enrichment (`:DocMap full`) — without it " +
      "this is empty rather than wrong.",
    "view.inheritance":
      "Only `@class Child : Parent` edges, drawn apart from Types because " +
      "inheritance is a different claim than collaboration and reading both " +
      "in one picture hides which is which.",

    // ── The tools inside Analysis ────────────────────────────────────
    //
    // Written from what each panel computes, per this table's own rule.
    // The `.plugin-gated` ones say what they need, because an empty panel
    // that cannot say why is the failure this whole card exists against.
    "atool.test":
      "Which functions a test suite mentions by name, per module, worst " +
      "first. A floor rather than a verdict: a name found under the tests " +
      "directory counts, and a function exercised only indirectly does not.",
    "atool.doc":
      "Which functions carry a summary and fully documented parameters, per " +
      "module, worst first. `@internal` functions are excluded — this is a " +
      "question about the published surface, not about helpers.",
    "atool.annotations":
      "Which annotation tags this tree actually uses, counted per function. " +
      "Generated, so unlike a hand-written inventory it cannot go stale.",
    "atool.api":
      "Every function this tree publishes, with its documentation state and " +
      "how many other modules here call it — the question asked every time a " +
      "module is extracted into its own plugin.",
    "atool.deps":
      "Fan-in and fan-out per module: how many modules it requires, and how " +
      "many require it. The second number is the one that decides how " +
      "expensive a rename is.",
    "atool.complexity":
      "Cyclomatic complexity per function, counted over its own subtree " +
      "including nested closures. A ranking of where the branching is, not " +
      "a threshold anything fails.",
    "atool.duplicates":
      "Functions whose parse-tree *shape* is identical, ignoring names and " +
      "literals — the one kind of drift the require graph cannot see, since " +
      "two modules that each grew their own `read(path)` do not require " +
      "each other.",
    "atool.lazy":
      "The Plugins question inverted: which plugins load on each event, " +
      "filetype, command and key, and which are paid for at startup " +
      "regardless. Answers what typing a command actually costs, and why " +
      "something is not loaded yet.",
    "atool.plugins":
      "Every lazy.nvim-shaped plugin spec in the tree. Matters when this is " +
      "pointed at a Neovim *config* rather than a plugin, where most files " +
      "are specs with no function in them and are invisible to every other " +
      "panel.",
    "atool.bindings":
      "Keymaps, user commands and autocommands registered in this tree. The " +
      "`vim.*` APIs are recognised unconditionally; a config binding through " +
      "its own wrapper needs `opts.bindings.wrappers` to declare it.",
    "atool.tools":
      "The CLI tools this repository declares it wants, from its own " +
      "`docs/install.json`. Declared only — a static page has no host to ask " +
      "whether any of them is installed here.",
    "atool.telemetry":
      "Call counts collected by runtime-analysis.nvim inside a real Neovim " +
      "session, joined onto this map. Needs `:DocMap serve`: counts change " +
      "between runs, so they are never baked into the committed page.",
    "atool.loaded":
      "A loaded-versus-declared comparison from a saved runtime-analysis " +
      "snapshot. Needs `:DocMap serve` and a named snapshot — the difference " +
      "is a property of one live session, never of a live aggregate.",
    "atool.checklist":
      "Hand-verified facts, each cited to the file it was read off. The " +
      "ledger is baked into this page; the changed-since-verified verdict " +
      "needs git, so it fills in under `:DocMap serve`.",
    "atool.hooks":
      "Functions named like a React hook (`^use[A-Z]`, the convention " +
      "eslint-plugin-react-hooks itself relies on). Only JavaScript, " +
      "TypeScript and TSX files are checked for this.",
    "atool.docs":
      "Every Markdown file in the tree and how often the rest of the " +
      "documentation points at it — which pages are load-bearing, and which " +
      "nothing links to.",
    "atool.endpoints":
      "HTTP routes registered in the source, Express/Fastify/Koa-shaped. An " +
      "ecosystem convention rather than a language feature, so a tree " +
      "without one is empty here and that is a real answer.",

    "tab.hierarchy":
      "The dependency graph, drawn from one module outward. Boxes are modules " +
      "and namespaces, arrows are requires and calls; the slider decides how " +
      "far from the centre it reaches. Hovering a box lights it and its " +
      "neighbours; the first click holds that, so you can read it and follow " +
      "the edges without the pointer. Click the same box again to root the " +
      "graph there — or double-click, which is the same two clicks at once. " +
      "Escape, a click on empty space, or a click on another box lets go. " +
      "The path above the graph shows where you are, every level a way back. " +
      "The *Classic clicks* pill decides what that second click does: root " +
      "here, or open in the Tree. The one view that exports as an SVG.",
    "tab.index":
      "Flat lists of everything the map found, for when you know the name and " +
      "not the place. Three ways of listing the same repository — as a tree, " +
      "as functions, as modules.",
    "tab.analysis":
      "Aggregate numbers over the whole tree: how much is tested, how much is " +
      "documented, where dependencies concentrate. A palette of tools sharing " +
      "one panel, not a single report.",
    "tab.compare":
      "Two or more modules side by side, on the same rows, so a difference is " +
      "a difference in a column rather than something to remember between " +
      "scrolls.",
    "tab.features":
      "This repository's own `docs/FEATURES/` files, read as an index — name, " +
      "summary and metadata. Never the prose that follows them, which stays " +
      "in the file it was written in.",
    "tab.quicks":
      "The verdicts: what is notable about this tree stated in sentences, " +
      "good and bad, each with the count it is based on. Computed by the " +
      "engine, not by this page.",
    "tab.notes":
      "Everything the authors left behind. Annotations on functions " +
      "(`---@todo`, `---@bug`) and marker comments in the source " +
      "(`-- TODO:`, `// FIXME:`) — two lists, because one is attached to a " +
      "signature and the other to a line.",
    "tab.history":
      "This repository's git history, and what each commit did to the map. " +
      "Computed on demand from git, so it needs a host that can run it — a " +
      "map opened as a file says so instead of guessing.",

    "sub.tree":
      "The module tree as the scan walked it, with each node's own detail " +
      "beside it. The default place to start reading a repository you do not " +
      "know.",
    "sub.functions":
      "Every documented function in the map, alphabetically, with its " +
      "signature and where it lives.",
    "sub.modules":
      "Every module and namespace, alphabetically. The same set the tree " +
      "shows, without the nesting.",
    "sub.features.all":
      "The index of every feature file, above the ones promoted to a tab of " +
      "their own.",

    "tab.findings":
      "Where the drift checks report. Each row is one check disagreeing " +
      "with the code — a doc reference to something that no longer exists, " +
      "an example that does not parse, a binding declared twice. The same " +
      "list that fails CI and lands on GitHub as SARIF. Its count stays in " +
      "the header rather than moving in here, because a number behind a " +
      "click is a number nobody reads.",
  };

  var explainpop = null;
  var explainAnchor = null;
  var explainTimer = null;

  function explainClose(){
    if(explainTimer){ clearTimeout(explainTimer); explainTimer = null; }
    if(explainpop) explainpop.classList.remove("on");
    // Removed with the card, not left behind: an `aria-describedby` pointing
    // at a hidden element describes nothing and is read as one anyway.
    if(explainAnchor) explainAnchor.removeAttribute("aria-describedby");
    explainAnchor = null;
  }

  function explainOpen(el){
    var text = EXPLAIN[el.dataset.explain];
    if(!text) return;
    if(!explainpop){
      explainpop = document.createElement("div");
      explainpop.className = "sigpop explainpop";
      explainpop.setAttribute("role", "tooltip");
      document.body.appendChild(explainpop);
    }
    explainAnchor = el;
    // **Associated, not merely positioned.** Six of these controls used to
    // carry a `title`, which a screen reader announces; replacing it with a
    // styled card would have taken that away from the readers least able to
    // spare it. `aria-describedby` is what puts it back, and it also gives
    // the nine tabs an association they never had.
    explainpop.id = explainpop.id || "explainpop";
    el.setAttribute("aria-describedby", explainpop.id);
    explainpop.innerHTML = '<div class="fn-desc"></div>';
    // `textContent`, not `innerHTML`: these strings carry backticks as
    // literal characters and nothing else, and a card that renders markup
    // is a card somebody eventually puts a link in.
    explainpop.querySelector(".fn-desc").textContent = text;
    explainpop.classList.add("on");

    // Under the control, flipped up when there is no room — the same rule
    // the annotation and keyword cards already follow.
    var r = el.getBoundingClientRect();
    var p = explainpop.getBoundingClientRect();
    var left = Math.min(r.left, window.innerWidth - p.width - 8);
    var top = r.bottom + 6;
    if(top + p.height > window.innerHeight - 8) top = r.top - p.height - 6;
    explainpop.style.left = Math.max(8, left) + "px";
    explainpop.style.top = Math.max(8, top) + "px";
  }

  // A deliberate dwell, not a pointer crossing the strip: eight tabs in a
  // row means a card per tab on the way to the one you wanted.
  document.addEventListener("mouseover", function(ev){
    var el = ev.target.closest && ev.target.closest("[data-explain]");
    if(!el){
      if(explainAnchor && !explainTimer) explainTimer = setTimeout(explainClose, 120);
      return;
    }
    if(explainTimer){ clearTimeout(explainTimer); explainTimer = null; }
    if(el === explainAnchor) return;
    explainClose();
    explainTimer = setTimeout(function(){
      explainTimer = null;
      explainOpen(el);
    }, 450);
  });

  // Keyboard focus opens it immediately. A `title` attribute would have been
  // free and never appears on focus, which would leave exactly the controls
  // a keyboard user reaches as the only ones with no explanation.
  document.addEventListener("focusin", function(ev){
    var el = ev.target.closest && ev.target.closest("[data-explain]");
    if(el) explainOpen(el); else explainClose();
  });
  document.addEventListener("keydown", function(ev){
    if(ev.key === "Escape") explainClose();
  });
  document.addEventListener("scroll", explainClose, true);
  window.addEventListener("blur", explainClose);

  // =====================================================================
  // The second level
  //
  // Two tabs own one: Index is three ways of listing the same repository
  // (Tree, Functions, Modules), and Features owns however many entries this
  // repository promotes with `Tab: true`.
  //
  // One strip rather than one per owner. Two strips in the same place that
  // are never both visible are one strip with extra code — and the promoted
  // features used to have no strip at all: each appended a button to the
  // *top* bar, so a repository documenting five features pushed the eight
  // permanent tabs onto a second row and buried them under five that are
  // particular to it.
  //
  // `state.tab` is unchanged by any of this. `tree` is still `tree` and a
  // promoted feature is still `feature-<slug>`, so every link ever shared
  // and every `#tab=` in anyone's history still lands where it did. What
  // changed is only which button lights up for them.
  // =====================================================================

  /// The top-level tab a state belongs to.
  ///
  /// `tree` lives under Index and `feature-x` under Features; everything
  /// else is its own group. This is the one place that mapping exists.
  function topTab(tab){
    if(tab === "tree") return "index";
    if(tab && tab.indexOf("feature-") === 0) return "features";
    return tab;
  }

  /// Entries for the strip, or `[]` when this group has no second level.
  function subTabs(tab){
    var group = topTab(tab);
    if(group === "index"){
      return [
        { tab: "tree", label: "Tree", explain: "sub.tree" },
        { tab: "index", iview: "functions", label: "Functions",
          explain: "sub.functions" },
        { tab: "index", iview: "modules", label: "Modules",
          explain: "sub.modules" }
      ];
    }
    if(group === "features"){
      // "All features" first: without it, opening a promoted feature would
      // leave no way back to the index of them except the browser's Back
      // button.
      var out = [{ tab: "features", label: "All features",
                   explain: "sub.features.all" }];
      collectPromotedFeatures().forEach(function(p){
        out.push({ tab: p.slug, label: tabLabel(p.entry.name), title: p.entry.name });
      });
      return out;
    }
    return [];
  }

  function renderSubTabs(s){
    var host = document.getElementById("subtabs");
    var entries = subTabs(s.tab);
    if(!entries.length){
      host.hidden = true;
      host.innerHTML = "";
      return;
    }
    host.hidden = false;
    host.innerHTML = "";
    entries.forEach(function(e){
      var b = document.createElement("button");
      b.className = "subtab-btn";
      // Active when both the tab and — where it matters — the mode match.
      // `Functions` and `Modules` are the same tab and differ only by
      // `iview`, so tab equality alone would light both.
      var on = e.tab === s.tab && (!e.iview || e.iview === (s.iview || "functions"));
      if(on) b.classList.add("active");
      b.textContent = e.label;
      if(e.title) b.title = e.title;
      if(e.explain) b.dataset.explain = e.explain;
      b.addEventListener("click", function(){
        navigate(e.iview ? { tab: e.tab, iview: e.iview } : { tab: e.tab });
      });
      host.append(b);
    });
  }

  var promotedFeatures = null;
  function collectPromotedFeatures(){
    if(promotedFeatures) return promotedFeatures;
    promotedFeatures = [];
    if(!IR.features) return promotedFeatures;
    // Two features can slugify to the same string (same name in different
    // theme files, or names differing only in punctuation) — disambiguated
    // with a numeric suffix rather than silently letting the second one's
    // tab button overwrite the first's in the DOM.
    var seen = {};
    IR.features.files.forEach(function(f){
      f.entries.forEach(function(e){
        if(!e.tab) return;
        var base = featureSlug(e.name);
        var slug = base, n = 2;
        while(seen[slug]){ slug = base + "-" + n; n++; }
        seen[slug] = true;
        promotedFeatures.push({ entry: e, file: f, slug: slug });
      });
    });
    return promotedFeatures;
  }

  // Inserted right after the static "Features" tab button/panel, each
  // subsequent one after the last — deterministic order (file order, then
  // entry order within a file, the same order `IR.features` already
  // carries), not something later re-sorts. Runs once at boot, before the
  // generic .tab-btn click-handler wiring picks up every button currently
  // in the DOM.
  function buildPromotedTabs(){
    var promoted = collectPromotedFeatures();
    if(!promoted.length) return;
    var afterView = document.getElementById("view-features");
    promoted.forEach(function(p){
      // Views only. The buttons are `renderSubTabs`'s now: appending them
      // to the top bar is what pushed the eight permanent tabs onto a
      // second row on any repository that promotes a few features.
      var view = document.createElement("div");
      view.id = "view-" + p.slug;
      view.className = "view";
      afterView.insertAdjacentElement("afterend", view);
      afterView = view;
    });
  }

  // Cheap Markdown-subset renderer for a promoted feature's body — the same
  // "cheap reliable reading beats a general one" discipline
  // core/features.lua's own parser follows, not a CommonMark
  // implementation. Understood: `#`.."######" headings, fenced ``` code
  // blocks, `-`/`*` bullet lists, paragraphs, and inline `` `code` ``/
  // **bold**/*italic*/[text](url). Not understood: tables, blockquotes,
  // images, nested/ordered lists, or raw HTML passthrough — anything else
  // renders as plain escaped text rather than being interpreted.
  function inlineMd(s){
    s = esc(s);
    s = s.replace(/`([^`]+)`/g, "<code>$1</code>");
    s = s.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
    s = s.replace(/(^|[^*_])\*([^*\n]+)\*(?!\*)/g, "$1<em>$2</em>");
    // A hex escape for the closing bracket, not a backslash-escaped literal
    // one: two adjacent close-brackets anywhere in this file's embedded JS
    // would end the Lua long string this whole block lives inside early —
    // a sharp edge no other function here hit, since none needed a bracket
    // right next to the closing one of its own character class.
    s = s.replace(/\[([^\x5d]+)\]\(([^)]+)\)/g, function(m, text, url){
      // Only http(s)/relative-looking targets get linked — never a
      // `javascript:` URL smuggled through a docs/FEATURES/ file this
      // parser otherwise trusts as plain prose.
      if(/^(https?:)?\/\//.test(url) || /^[.\w#]/.test(url)){
        return '<a href="' + url + '" target="_blank" rel="noopener">' + text + '</a>';
      }
      return text;
    });
    return s;
  }

  function renderFeatureBody(raw){
    var lines = raw.split("\n");
    var out = [], para = [], list = null;

    function flushPara(){
      if(para.length){ out.push("<p>" + inlineMd(para.join(" ")) + "</p>"); para = []; }
    }
    function flushList(){
      if(list){ out.push("<ul>" + list.join("") + "</ul>"); list = null; }
    }

    var i = 0;
    while(i < lines.length){
      var trimmed = lines[i].replace(/^\s+|\s+$/g, "");

      if(/^```/.test(trimmed)){
        flushPara(); flushList();
        var code = [];
        i++;
        while(i < lines.length && !/^```/.test(lines[i].replace(/^\s+|\s+$/g, ""))){
          code.push(lines[i]); i++;
        }
        i++; // skip the closing fence (or run off the end if one is missing)
        out.push("<pre><code>" + esc(code.join("\n")) + "</code></pre>");
        continue;
      }

      var heading = trimmed.match(/^(#{1,6})\s+(.+)$/);
      if(heading){
        flushPara(); flushList();
        // A body's own headings sit under the tab's H2 (feature name) and
        // the theme label above it — h4 is the highest an author's `#`
        // should reach, capped at h6 so `######` doesn't overshoot into
        // nothing.
        var level = Math.min(heading[1].length + 3, 6);
        out.push("<h" + level + ">" + inlineMd(heading[2]) + "</h" + level + ">");
        i++; continue;
      }

      var item = trimmed.match(/^[-*]\s+(.+)$/);
      if(item){
        flushPara();
        list = list || [];
        list.push("<li>" + inlineMd(item[1]) + "</li>");
        i++; continue;
      }

      if(trimmed === ""){
        flushPara(); flushList();
        i++; continue;
      }

      flushList();
      para.push(trimmed);
      i++;
    }
    flushPara(); flushList();
    return out.join("\n");
  }

  var drawnFeatureTabs = {};
  function drawFeatureTab(slug){
    if(drawnFeatureTabs[slug]) return; // static over one IR, same as drawFeatures
    var promoted = collectPromotedFeatures().filter(function(p){ return p.slug === slug; })[0];
    var host = document.getElementById("view-" + slug);
    if(!promoted || !host) return;
    drawnFeatureTabs[slug] = true;

    var e = promoted.entry, f = promoted.file;
    var nodeId = resolveModuleNode(e.meta);
    var parts = ['<div class="feat-tab-wrap">'];
    parts.push('<div class="feat-tab-theme">' + esc(themeTitle(f.theme)) + '</div>');
    parts.push('<h2 class="feat-tab-name"' +
      (nodeId ? ' data-node="' + esc(nodeId) + '" tabindex="0" role="button"' : '') +
      '>' + esc(e.name) + '</h2>');
    if(e.summary){
      parts.push('<p class="feat-tab-summary">' + prose(e.summary) + '</p>');
    }
    if(e.meta.length){
      parts.push('<div class="feat-meta">');
      e.meta.forEach(function(m){
        parts.push('<div class="feat-meta-row"><b>' + esc(m.key) + ':</b> <span>' +
          esc(m.value) + '</span></div>');
      });
      parts.push("</div>");
    }
    if(e.body){
      parts.push('<div class="feat-tab-body">' + renderFeatureBody(e.body) + '</div>');
    }
    parts.push('<div class="feat-src"><a href="#" data-src="' + esc(f.path) + '">' +
      esc(f.path) + ':' + e.line + '</a></div>');
    parts.push("</div>");
    host.innerHTML = parts.join("");

    var nameEl = host.querySelector(".feat-tab-name[data-node]");
    if(nameEl){
      nameEl.addEventListener("click", function(){ navigate({ tab: "tree", id: nodeId }); });
    }
    host.querySelectorAll(".feat-src a[data-src]").forEach(function(a){
      a.addEventListener("click", function(ev){
        ev.preventDefault();
        var u = srcUrl(a.dataset.src);
        window.open(u || rel(a.dataset.src), u ? "_blank" : "_self");
      });
    });
  }

  // =====================================================================
  // Index tab: Doxygen's "File Members" — every documented function in the
  // tree, A–Z, without walking the module hierarchy to find it.
  //
  // Sorted on the *bare* name (`M.read` files under R, not M), because the
  // `M.` is this repo's local-table convention rather than part of what the
  // function is called — filing 900 functions under "M" would be an index in
  // name only. `calls.lua` needed the same reduction and its `bare()` is the
  // model here.
  //
  // The Tree tab already filters and the picker already fuzzy-matches; what
  // neither gives you is the flat alphabet, which is the one way to find
  // something whose module you do not know.
  // =====================================================================
  function bareName(name){ return (name.match(/[\w]+$/) || [name])[0]; }

  // Shared by both index views: letter buckets plus a jump bar, filed on
  // `entry.bare`. Ties broken by `entry.tie` so two entries with the same
  // bare name (`M.setup` everywhere; two modules named `init`) sort
  // deterministically instead of leaving it to the engine's discretion.
  function buildIndexBuckets(entries){
    entries.sort(function(a, b){
      var ab = a.bare.toLowerCase(), bb = b.bare.toLowerCase();
      if(ab !== bb) return ab < bb ? -1 : 1;
      return a.tie < b.tie ? -1 : (a.tie > b.tie ? 1 : 0);
    });
    var buckets = {}, order = [];
    entries.forEach(function(e){
      var c = e.bare.charAt(0).toUpperCase();
      if(!/[A-Z]/.test(c)) c = "#";
      if(!buckets[c]){ buckets[c] = []; order.push(c); }
      buckets[c].push(e);
    });
    order.sort();
    return { buckets: buckets, order: order };
  }

  function indexJumpBar(order){
    return '<div class="ixjump">' + order.map(function(c){
      return '<a data-jump="' + esc(c) + '">' + esc(c) + '</a>';
    }).join("") + "</div>";
  }

  function wireIndexBody(host){
    host.querySelectorAll(".nfn").forEach(function(a){
      a.addEventListener("click", function(){
        navigate({ tab: "tree", id: a.dataset.node });
      });
    });
    host.querySelectorAll("[data-jump]").forEach(function(a){
      a.addEventListener("click", function(){
        var h = host.querySelector("#ix-" + CSS.escape(a.dataset.jump));
        if(h) h.scrollIntoView({ behavior: "smooth", block: "start" });
      });
    });
  }

  // Doxygen's "File Members" — every documented function in the tree, A-Z,
  // without walking the module hierarchy to find it. Sorted on the *bare*
  // name (`M.read` files under R, not M): the `M.` is this repo's
  // local-table convention rather than part of what the function is
  // called, and filing 900 functions under "M" would be an index in name
  // only — `calls.lua` needed the same reduction and its `bare()` is the
  // model. The Tree tab already filters and the picker already
  // fuzzy-matches; what neither gives you is the flat alphabet, the one way
  // to find something whose module you do not already know.
  var indexFnHTML = null;
  function renderIndexFunctions(){
    if(indexFnHTML !== null) return indexFnHTML;

    var entries = [];
    IR.nodes.forEach(function(n){
      (n.functions || []).forEach(function(fn){
        entries.push({ node: n, fn: fn, bare: bareName(fn.name), tie: n.module || n.path });
      });
    });

    if(entries.length === 0){
      indexFnHTML = '<p class="ntext none">This map contains no documented functions.</p>';
      return indexFnHTML;
    }

    var built = buildIndexBuckets(entries);
    var parts = [];
    parts.push('<p class="nsub">' + entries.length +
      ' documented functions, filed under the last segment of the declared name' +
      ' (<code>M.read</code> sorts under R).</p>');
    parts.push(indexJumpBar(built.order));

    built.order.forEach(function(c){
      parts.push('<h3 id="ix-' + esc(c) + '">' + esc(c) +
        '<span class="ncount">' + built.buckets[c].length + '</span></h3>');
      parts.push('<ul class="nlist ixlist">');
      built.buckets[c].forEach(function(e){
        parts.push('<li><a class="nfn" tabindex="0" role="button" data-node="' + esc(e.node.id) + '">' +
          esc(e.fn.signature) + '</a>' +
          sigTrigger(e.node.id, e.fn.name) + docTrigger(fnKey(e.node.id, e.fn.name)) +
          (e.fn.internal ? '<span class="ixtag">internal</span>' : '') +
          (e.fn.deprecated ? '<span class="ixtag dep">deprecated</span>' : '') +
          (e.fn.tested ? '<span class="ixtag tested">tested</span>' : '') +
          '<span class="nwhere">' + esc(e.node.module || e.node.path) +
          ':' + e.fn.line + '</span></li>');
      });
      parts.push("</ul>");
    });
    indexFnHTML = parts.join("");
    return indexFnHTML;
  }

  // R3: the same flat alphabet, one level up — every *module and namespace*
  // (not function, and deliberately not `file` nodes: a file is reached
  // through its module in the Tree, and this index exists for "I know the
  // module name, not where it lives", which a leaf file rarely is). Doxygen
  // keeps its File Index and Class Index as separate pages for the same
  // reason a flat function alphabet and a flat module alphabet answer two
  // different "I know the name, not the location" questions.
  var indexModHTML = null;
  function renderIndexModules(){
    if(indexModHTML !== null) return indexModHTML;

    var entries = [];
    IR.nodes.forEach(function(n){
      if(n.kind !== "module" && n.kind !== "namespace") return;
      var label = n.module || n.path;
      entries.push({ node: n, bare: bareName(label), label: label, tie: label });
    });

    if(entries.length === 0){
      indexModHTML = '<p class="ntext none">This map contains no modules.</p>';
      return indexModHTML;
    }

    var built = buildIndexBuckets(entries);
    var parts = [];
    parts.push('<p class="nsub">' + entries.length +
      ' modules and namespaces, filed under the last segment of the module path' +
      ' (<code>lib.nvim.fs</code> sorts under F).</p>');
    parts.push(indexJumpBar(built.order));

    built.order.forEach(function(c){
      parts.push('<h3 id="ix-' + esc(c) + '">' + esc(c) +
        '<span class="ncount">' + built.buckets[c].length + '</span></h3>');
      parts.push('<ul class="nlist ixlist">');
      built.buckets[c].forEach(function(e){
        var fnCount = (e.node.functions || []).length;
        parts.push('<li><a class="nfn" tabindex="0" role="button" data-node="' + esc(e.node.id) + '">' +
          esc(e.label) + '</a>' + docTrigger(e.node.id) +
          '<span class="ixtag">' + esc(e.node.kind) + '</span>' +
          '<span class="nwhere">' + fnCount + (fnCount === 1 ? " function" : " functions") +
          '</span></li>');
      });
      parts.push("</ul>");
    });
    indexModHTML = parts.join("");
    return indexModHTML;
  }

  function drawIndex(){
    var host = document.getElementById("ixbody");
    var iview = state.iview === "modules" ? "modules" : "functions";
    host.innerHTML = iview === "modules" ? renderIndexModules() : renderIndexFunctions();
    wireIndexBody(host);
  }

  // =====================================================================
  // Analysis tab: a tool palette, not a diagram — the same "toolbar
  // switches what a shared panel shows" shape the Hierarchy view buttons
  // and the Index Functions/Modules toggle already use, applied to
  // aggregate numbers instead of boxes or a flat alphabet.
  //
  // Each tool reads a boolean docmap already stamped onto every function
  // during scan_full() (`fn.tested`, R2; `fn.documented`, R4) rather than
  // recomputing anything here — `doccoverage.is_documented`'s param-name
  // comparison in particular is not something this file should ever
  // reimplement in JS, where it would inevitably drift from check.lua's
  // own logic the moment either side changed.
  //
  // First two tools only, deliberately: R6 (fan-in/fan-out hotspots) and
  // beyond are real candidates but have no data stamped into the IR yet —
  // adding their buttons here before their data exists would be a menu
  // entry that opens an empty panel, exactly what the context menu's
  // "disabled with count shown" rule exists to avoid elsewhere.
  // =====================================================================

  // `excludeInternal` matters for the Documentation panel specifically:
  // `doccoverage.summary`'s own definition of "total" already excludes
  // `@internal` functions (an internal function's documentation bar is the
  // author's own, not part of a "published API" number), and this panel
  // must count the same way or its 65% would quietly disagree with the
  // number `:DocMap`/the CLI prints for the same tree. The Test-coverage
  // panel passes false: `coverage.resolve` stamps `fn.tested` on every
  // function regardless of `@internal`, so its total is every function.
  // ---------------------------------------------------------------------
  // Sortable Analysis tables.
  //
  // Three pieces shared by every panel so the behaviour cannot differ between
  // them: a header renderer, a sorter, and a filter. Each panel declares its
  // columns as `{ label, key, get, initial }` and gets clickable headers, the
  // arrow, the URL round-trip and the text filter for free.
  //
  // `key == null` means an unsortable column — the bar graphics, which are a
  // rendering of a column already in the table and would sort by nothing.
  //
  // The panel's own default order survives: with no `asort` the caller's
  // `fallback` comparator runs, tiebreaks included. That matters because
  // "worst first, then most functions affected, then id" is an editorial
  // judgement about where to look, and collapsing it to "sorted by pct desc"
  // would quietly change what the panel recommends.
  // ---------------------------------------------------------------------

  ///Render a `<thead>` from a column spec, marking the active sort.
  function anHead(cols){
    var out = ['<thead><tr>'];
    cols.forEach(function(c){
      if(!c.key){ out.push('<th>' + (c.label || "") + '</th>'); return; }
      var active = state.asort === c.key;
      // The arrow is on the active column only. An idle arrow on every header
      // reads as "these are all sorted", which is exactly backwards.
      var arrow = active ? (state.adir === "asc" ? " ▲" : " ▼") : "";
      // A sort control is a control: focusable in its own right, and few
      // enough (three per table) that it is a tab stop rather than another
      // roving list. `aria-sort` is the one ARIA property a sortable column
      // header genuinely owns, and it is derivable from state already here.
      out.push('<th class="ansort' + (active ? " active" : "") + '" data-sort="' +
        esc(c.key) + '" data-initial="' + (c.initial === "asc" ? "asc" : "desc") +
        '" tabindex="0" role="button" aria-sort="' +
        (active ? (state.adir === "asc" ? "ascending" : "descending") : "none") +
        '" title="Sort by ' + esc(c.label) + '">' + c.label + arrow + '</th>');
    });
    out.push('</tr></thead>');
    return out.join("");
  }

  ///Sort `rows` per the active column, or by `fallback` when none is active.
  function anSort(rows, cols, fallback){
    var col = null;
    for(var i = 0; i < cols.length; i++){
      if(cols[i].key && cols[i].key === state.asort) col = cols[i];
    }
    if(!col || !col.get){
      rows.sort(fallback);
      return rows;
    }
    var dir = state.adir === "asc" ? 1 : -1;
    rows.sort(function(a, b){
      var av = col.get(a), bv = col.get(b);
      if(av !== bv) return (av < bv ? -1 : 1) * dir;
      // Always the same tiebreak, independent of direction: without it, two
      // rows with equal values swap places on every re-render, which looks
      // like the table is unstable.
      var ak = a.sortkey || "", bk = b.sortkey || "";
      return ak < bk ? -1 : (ak > bk ? 1 : 0);
    });
    return rows;
  }

  ///Keep only rows whose `haystack` contains the active query.
  ///
  ///Substring, case-insensitive, no fuzzy matching. The Tree tab's filter and
  ///the Hierarchy jump already offer richer matching; what this answers is
  ///"show me only this module", where a fuzzy match that also returns four
  ///near-misses is worse than an exact one.
  function anFilter(rows){
    var q = (state.q || "").toLowerCase().trim();
    if(!q) return rows;
    return rows.filter(function(r){
      return (r.haystack || "").toLowerCase().indexOf(q) >= 0;
    });
  }

  ///The "N hidden by the filter" line, or "" when nothing is filtered.
  ///
  ///Said out loud rather than left implicit: a panel that silently shows three
  ///of forty rows looks like a map with three modules in it.
  function anFilterNote(shown, total){
    if(shown === total) return "";
    return ' <strong>' + shown + ' of ' + total + '</strong> shown, filtered by "' +
      esc(state.q) + '".';
  }

  function renderAnalysisPanel(label, sub, pick, excludeInternal){
    var rows = [];
    IR.nodes.forEach(function(n){
      var fns = (n.functions || []).filter(function(fn){
        return !(excludeInternal && fn.internal);
      });
      if(fns.length === 0) return;
      var hit = 0;
      fns.forEach(function(fn){ if(pick(fn)) hit++; });
      var name = n.module || n.path;
      rows.push({
        node: n, hit: hit, total: fns.length, pct: hit / fns.length,
        name: name, haystack: name + " " + n.id, sortkey: n.id
      });
    });

    // Totals over *everything*, before the filter: the headline percentage is
    // a property of the map, not of what is currently on screen, and a number
    // that moved when you typed would be actively misleading.
    var totalHit = 0, totalAll = 0;
    rows.forEach(function(r){ totalHit += r.hit; totalAll += r.total; });
    var overallPct = totalAll > 0 ? Math.round(100 * totalHit / totalAll) : 0;
    var totalRows = rows.length;

    if(rows.length === 0){
      return '<p class="ntext none">This map contains no documented functions.</p>';
    }

    // Worst-first: the module that needs attention most belongs at the top
    // of a panel meant to answer "where should I look", not filed
    // alphabetically where that answer is buried. Fewer functions is not
    // itself worse, so the tiebreak is functions-affected (a 0% module with
    // 20 functions matters more than one with 1), then module id for a
    // stable order once both numbers tie exactly.
    var cols = [
      { label: "Module", key: "name", get: function(r){ return r.name; }, initial: "asc" },
      { label: label, key: "pct", get: function(r){ return r.pct; }, initial: "asc" },
      { label: "Functions", key: "total", get: function(r){ return r.total; }, initial: "desc" },
      { label: "", key: null }
    ];

    rows = anFilter(rows);
    anSort(rows, cols, function(a, b){
      // The default: worst first. The module that needs attention most belongs
      // at the top of a panel meant to answer "where should I look", not filed
      // alphabetically where that answer is buried. Fewer functions is not
      // itself worse, so the tiebreak is functions-affected (a 0% module with
      // 20 functions matters more than one with 1), then module id for a
      // stable order once both numbers tie exactly.
      if(a.pct !== b.pct) return a.pct - b.pct;
      if(a.total !== b.total) return b.total - a.total;
      return a.node.id < b.node.id ? -1 : (a.node.id > b.node.id ? 1 : 0);
    });

    var parts = [];
    parts.push('<p class="nsub">' + label + ': <strong>' + totalHit + '/' + totalAll +
      '</strong> functions (' + overallPct + '%). ' + sub +
      anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      return parts.join("") + '<p class="ntext none">No module matches that filter.</p>';
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      var pct = Math.round(r.pct * 100);
      parts.push('<tr class="anrow" data-node="' + esc(r.node.id) + '">' +
        '<td>' + esc(r.name) + '</td>' +
        '<td>' + r.hit + '/' + r.total + ' (' + pct + '%)</td>' +
        '<td>' + r.total + '</td>' +
        '<td><div class="anbar"><div class="anfill" style="width:' + pct + '%"></div></div></td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  // R6: fan-in/fan-out per module, read straight off `n.requires`/
  // `n.required_by` — both already sorted, deduplicated indexes into
  // `ir.edges`'s require edges (see `Documentation.Node` in @types/init.lua),
  // so this is JS-side aggregation only, no new Lua extraction. Distinct
  // from `renderAnalysisPanel`: that one counts a boolean over a node's
  // *functions*, this counts edges over the *node itself*, so it is its
  // own small render function rather than a third `pick` callback bent
  // into the same shape.
  function renderAnalysisDeps(){
    var rows = [];
    IR.nodes.forEach(function(n){
      var fanIn = (n.required_by || []).length;
      var fanOut = (n.requires || []).length;
      if(fanIn === 0 && fanOut === 0) return;
      var name = n.module || n.path;
      rows.push({
        node: n, fanIn: fanIn, fanOut: fanOut,
        name: name, haystack: name + " " + n.id, sortkey: n.id
      });
    });

    if(rows.length === 0){
      return '<p class="ntext none">This map contains no require edges.</p>';
    }

    var totalRows = rows.length;
    var cols = [
      { label: "Module", key: "name", get: function(r){ return r.name; }, initial: "asc" },
      { label: "Fan-in", key: "fanIn", get: function(r){ return r.fanIn; }, initial: "desc" },
      { label: "Fan-out", key: "fanOut", get: function(r){ return r.fanOut; }, initial: "desc" },
      { label: "", key: null }
    ];

    rows = anFilter(rows);
    anSort(rows, cols, function(a, b){
      // Highest fan-in first: the module most other modules depend on is the
      // one whose blast radius matters most, the same "most consequential
      // first" rule the coverage panels already follow with their pct sort.
      // Fan-out is the tiebreak, not an equal-weight second key — a module
      // nothing depends on but that itself pulls in a lot is a different
      // smell (the roadmap's "God module" idea), worth seeing but not at the
      // cost of burying real fan-in leaders under it.
      if(a.fanIn !== b.fanIn) return b.fanIn - a.fanIn;
      if(a.fanOut !== b.fanOut) return b.fanOut - a.fanOut;
      return a.node.id < b.node.id ? -1 : (a.node.id > b.node.id ? 1 : 0);
    });

    // Over the filtered set on purpose, unlike the coverage panels' headline
    // percentage: this is a *scale* for the bars beside it, so it has to match
    // the rows actually drawn or the longest visible bar stops being full.
    var maxFanIn = rows.reduce(function(m, r){ return Math.max(m, r.fanIn); }, 0);

    var parts = [];
    parts.push('<p class="nsub">' + totalRows + ' modules with at least one require ' +
      'edge. Fan-in is how many other modules require this one — the blast radius if it ' +
      'changes. Fan-out is how many modules it requires itself.' +
      anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      return parts.join("") + '<p class="ntext none">No module matches that filter.</p>';
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      var barPct = maxFanIn > 0 ? Math.round(100 * r.fanIn / maxFanIn) : 0;
      parts.push('<tr class="anrow" data-node="' + esc(r.node.id) + '">' +
        '<td>' + esc(r.name) + '</td>' +
        '<td>' + r.fanIn + '</td>' +
        '<td>' + r.fanOut + '</td>' +
        '<td><div class="anbar"><div class="anfill" style="width:' + barPct + '%"></div></div></td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  // Cyclomatic complexity (McCabe): `fn.complexity`, computed unconditionally
  // by docmap.functions during the scan itself (unlike tested/documented,
  // there is no IR-only "resolve" step that could derive it later — it
  // needs the treesitter node, which only exists during that same pass).
  // Ranked by function, not rolled up per module: "longest/most tangled
  // function" is a property of one function, and averaging it into a
  // per-module score would bury the one function that actually needs
  // attention under a healthy module's mean.
  // The published surface: every function this tree exposes, with whether it
  // is documented and whether anything outside its own module calls it.
  //
  // Three places already hold a third of this each -- Index has the names,
  // Documentation has the state, Deps has the edges -- and none of them
  // answers "what does this plugin actually expose". The question is asked
  // every time a module is extracted into its own plugin, which this
  // ecosystem has now done twice, by hand both times.
  //
  // **`internal` is read, never guessed.** It is a contract field the backend
  // fills from the language itself in nineteen of the backend files -- Zig's
  // `pub`, Java's `public`, C's `static`, Lua's `@internal` tag -- so the
  // surface is *declared* rather than inferred from a naming convention.
  // That is also why this panel was cheap: the hard half was paid for by the
  // visibility work.
  //
  // **"No caller here" is not "unused", and the panel says so.** A plugin's
  // published API is consumed by *other repositories* by definition; a
  // function with no in-tree caller outside its own module is exactly what an
  // exported entry point looks like from inside. So the column counts what it
  // can see, is named for that, and the sub-line states what it cannot.
  // Which annotation tags this tree actually uses, generated.
  //
  // `docs/ANNOTATIONS.md` is this analysis done by hand, for one repository,
  // once — which `IDEAS.md` §2.1 calls what it is: a plugin whose entire
  // purpose is detecting drift shipping a hand-maintained inventory of its
  // own tag usage is drift, structurally. The last time that document was
  // recounted, `@nodiscard` had gone from 112 occurrences to zero and nothing
  // had noticed.
  //
  // **Adoption per function, not occurrences.** The hand-written table counts
  // how many times a tag appears in the source; this counts how many
  // functions carry it at least once. They answer different questions and the
  // panel says which one it answers: eleven hundred `@param` lines is a fact
  // about typing effort, "84% of functions document a parameter" is a fact
  // about the tree.
  //
  // **The tag -> field mapping comes from the catalogue**, not from here.
  // `param` lands in `params` and `return` in `returns`, which is not
  // derivable from the name, so the alternative is this panel keeping its own
  // copy of a table `core/tags.lua` already has — and a copy that drifts
  // reports zero adoption for a tag the tree uses everywhere, which looks
  // exactly like a true answer.
  function renderAnalysisAnnotations(){
    var catalogue = IR.tags || [];
    if(!catalogue.length){
      return '<p class="ntext none">This map was generated before the annotation ' +
        'catalogue existed, so there is nothing to report adoption against.</p>';
    }

    // Only function-scope tags: a module tag lives on the file and a class
    // tag on a type, and folding three denominators into one column would
    // produce a percentage of nothing in particular.
    var fnTags = catalogue.filter(function(t){ return t.scope === "function" && t.field; });

    var total = 0;
    var counts = {};
    fnTags.forEach(function(t){ counts[t.name] = { n: 0, nodes: {} }; });

    IR.nodes.forEach(function(n){
      (n.functions || []).forEach(function(fn){
        total++;
        fnTags.forEach(function(t){
          var v = fn[t.field];
          // Three shapes behind one question: a list with something in it, a
          // string with something in it, a flag that is set. `false` and `[]`
          // and `""` all mean the same thing here and none of them counts.
          var has = Array.isArray(v) ? v.length > 0 : (typeof v === "string" ? v.length > 0 : !!v);
          if(has){
            counts[t.name].n++;
            counts[t.name].nodes[n.id] = true;
          }
        });
      });
    });

    if(total === 0){
      return '<p class="ntext none">This map contains no functions to report adoption over.</p>';
    }

    var rows = fnTags.map(function(t){
      var c = counts[t.name];
      var files = 0;
      for(var k in c.nodes){ if(c.nodes.hasOwnProperty(k)) files++; }
      return {
        tag: "@" + t.name,
        name: t.name,
        origin: t.origin === "luals" ? "LuaCATS" : "docmap",
        summary: t.summary,
        url: t.url || null,
        n: c.n,
        files: files,
        pct: Math.round(1000 * c.n / total) / 10,
        haystack: "@" + t.name + " " + t.summary,
        sortkey: t.name
      };
    });

    var cols = [
      { label: "Tag", key: "name", get: function(r){ return r.name; }, initial: "asc" },
      { label: "From", key: "origin", get: function(r){ return r.origin; }, initial: "asc" },
      { label: "Functions", key: "n", get: function(r){ return r.n; }, initial: "desc" },
      { label: "Files", key: "files", get: function(r){ return r.files; }, initial: "desc" },
      { label: "", key: null }
    ];

    var totalRows = rows.length;
    var unused = rows.reduce(function(a, r){ return a + (r.n === 0 ? 1 : 0); }, 0);
    rows = anFilter(rows);
    // Most-used first, and an unused tag sinks to the bottom where it reads
    // as what it is: a convention this tree does not follow. That is the row
    // the hand-written table got wrong for months.
    anSort(rows, cols, function(a, b){
      if(a.n !== b.n) return b.n - a.n;
      return a.sortkey < b.sortkey ? -1 : 1;
    });

    var parts = [];
    parts.push('<p class="nsub">' + totalRows + ' function-scope tag' +
      (totalRows === 1 ? "" : "s") + ' this pipeline reads, against ' + total +
      ' function' + (total === 1 ? "" : "s") + ' in this map' +
      (unused ? ' - ' + unused + ' of them used nowhere here' : '') +
      '. Counted per <em>function that carries the tag at least once</em>, not ' +
      'per occurrence: eleven hundred <code>@param</code> lines is a fact about ' +
      'typing effort, "most functions document a parameter" is a fact about the ' +
      'tree. Module-scope and type-scope tags are left out rather than folded ' +
      'in, because their denominator is files and types rather than functions.' +
      anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      return parts.join("") + '<p class="ntext none">No tag matches that filter.</p>';
    }

    var maxN = rows.reduce(function(m, r){ return Math.max(m, r.n); }, 1);
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      var barPct = Math.round(100 * r.n / maxN);
      parts.push('<tr class="anrow">' +
        '<td><code>' + esc(r.tag) + '</code><div class="ntext">' + prose(r.summary) + '</div></td>' +
        '<td>' + esc(r.origin) + '</td>' +
        '<td>' + r.n + (r.n ? ' <span class="ntext">(' + r.pct + '%)</span>' : '') + '</td>' +
        '<td>' + (r.files || "none") + '</td>' +
        '<td><div class="anbar"><div class="anfill" style="width:' + barPct + '%"></div></div></td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  function renderAnalysisApi(){
    // Call edges into a `<node>#<fn>` key, keeping only callers from a
    // *different* module. A module calling itself says nothing about what it
    // exposes.
    var external = {};
    (IR.edges || []).forEach(function(e){
      if(e.kind !== "call") return;
      if(!e.to || !e.to_fn) return;
      if(e.from === e.to) return;
      var k = fnKey(e.to, e.to_fn);
      if(!external[k]) external[k] = {};
      external[k][e.from] = true;
    });

    var rows = [];
    var marked = 0;
    IR.nodes.forEach(function(n){
      var name = n.module || n.path;
      (n.functions || []).forEach(function(fn){
        if(fn.internal){ marked++; return; }
        var callers = external[fnKey(n.id, fn.name)];
        var count = 0;
        if(callers){
          for(var k in callers){ if(callers.hasOwnProperty(k)) count++; }
        }
        rows.push({
          node: n, fn: fn, name: name,
          sig: fn.signature || fn.name,
          documented: !!fn.documented,
          callers: count,
          haystack: (fn.signature || fn.name) + " " + name,
          sortkey: name + "#" + (fn.signature || fn.name)
        });
      });
    });

    if(rows.length === 0){
      return '<p class="ntext none">This map exposes no functions - everything ' +
        'it declares is marked internal, or nothing was extracted.</p>';
    }

    var totalRows = rows.length;
    var documented = rows.reduce(function(a, r){ return a + (r.documented ? 1 : 0); }, 0);
    var unreached = rows.reduce(function(a, r){ return a + (r.callers === 0 ? 1 : 0); }, 0);

    var cols = [
      { label: "Function", key: "sig", get: function(r){ return r.sig; }, initial: "asc" },
      { label: "Module", key: "name", get: function(r){ return r.name; }, initial: "asc" },
      { label: "Documented", key: "documented",
        get: function(r){ return r.documented ? 1 : 0; }, initial: "asc" },
      { label: "Callers here", key: "callers",
        get: function(r){ return r.callers; }, initial: "desc" }
    ];

    rows = anFilter(rows);
    // Least-reached first: the rows worth opening this panel for are the ones
    // nothing here calls. Each is either a real entry point or an export
    // nobody meant to make, and telling those two apart is the whole job.
    anSort(rows, cols, function(a, b){
      if(a.callers !== b.callers) return a.callers - b.callers;
      if(a.documented !== b.documented) return a.documented ? 1 : -1;
      return a.sortkey < b.sortkey ? -1 : 1;
    });

    var parts = [];
    // **Whether this is a surface at all depends on the language.** Zig's
    // `pub`, Java's `public` and C's `static` are keywords, so `internal`
    // arrives from the code and the list below is the real published API. Lua
    // and the ECMA family have no keyword at this granularity, so `internal`
    // arrives from an `@internal` tag somebody had to write -- and in a tree
    // where nobody wrote one, an unmarked file-local helper is
    // indistinguishable from an entry point. Measured on this repository the
    // day the panel was built: `norm(p)`, a local in `bindings/usrcmds`, sat
    // in the list beside `M.render()`. Saying so is the fix; guessing from a
    // `M.` prefix would be exactly the naming-convention inference the rest
    // of this panel refuses.
    // Always both halves, rather than a caveat above some threshold: the
    // count says how much was excluded, and the sentence after it says what
    // being excluded depended on. A tree with two marked functions out of
    // 776 -- this repository, measured -- is nearer to the zero case than to
    // a curated surface, and no cut-off would have said so honestly.
    var caveat = ' ' + (marked === 0
      ? '<strong>Nothing here is marked internal.</strong>'
      : marked + ' function' + (marked === 1 ? " is" : "s are") +
        ' marked internal and excluded.') +
      ' Internal is declared, never inferred - a keyword in Zig, Java and C, ' +
      'an <code>@internal</code> tag in Lua and JS/TS. In a tag language ' +
      'that means an untagged file-local helper reads the same here as an ' +
      'entry point, so the list is the surface only as far as the tree ' +
      'bothered to say.';
    parts.push('<p class="nsub">' + totalRows + ' published function' +
      (totalRows === 1 ? "" : "s") + ' - ' + documented + ' documented, ' +
      unreached + ' with no caller inside this repository.' + caveat +
      ' <strong>No caller here does not mean unused</strong> - a published API ' +
      'is consumed by other repositories by definition, and that is what an ' +
      'entry point looks like from inside. The column counts call edges from ' +
      'a different module of this tree, so a dynamically dispatched call is ' +
      'invisible to it, the same blind spot the Calls view has.' +
      anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      return parts.join("") + '<p class="ntext none">No function matches that filter.</p>';
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      parts.push('<tr class="anrow" data-node="' + esc(r.node.id) + '">' +
        '<td>' + esc(r.sig) + sigTrigger(r.node.id, r.fn.name) +
          docTrigger(fnKey(r.node.id, r.fn.name)) + '</td>' +
        '<td>' + esc(r.name) + '</td>' +
        '<td>' + (r.documented ? "yes" : "no") + '</td>' +
        '<td>' + (r.callers === 0 ? "none" : r.callers) + '</td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  function renderAnalysisComplexity(){
    var rows = [];
    IR.nodes.forEach(function(n){
      var name = n.module || n.path;
      (n.functions || []).forEach(function(fn){
        rows.push({
          node: n, fn: fn, complexity: fn.complexity || 1,
          name: name, sig: fn.signature || "",
          // Both, so "which of this module's functions are the tangled ones"
          // and "where is `parse_header`" are the same box.
          haystack: (fn.signature || "") + " " + name,
          sortkey: name + "#" + (fn.signature || "")
        });
      });
    });

    if(rows.length === 0){
      return '<p class="ntext none">This map contains no documented functions.</p>';
    }

    var totalRows = rows.length;
    var cols = [
      { label: "Function", key: "sig", get: function(r){ return r.sig; }, initial: "asc" },
      { label: "Module", key: "name", get: function(r){ return r.name; }, initial: "asc" },
      { label: "Complexity", key: "complexity", get: function(r){ return r.complexity; },
        initial: "desc" },
      { label: "", key: null }
    ];

    rows = anFilter(rows);
    anSort(rows, cols, function(a, b){
      if(a.complexity !== b.complexity) return b.complexity - a.complexity;
      return a.fn.signature < b.fn.signature ? -1 : 1;
    });
    // Scale for the bars, so over the filtered set — same reasoning as the
    // deps panel's `maxFanIn`.
    var maxC = rows.reduce(function(m, r){ return Math.max(m, r.complexity); }, 1);

    var parts = [];
    parts.push('<p class="nsub">' + totalRows + ' documented functions, ranked by ' +
      'cyclomatic complexity (McCabe) — one point per if/elseif/while/for/repeat/and/or, ' +
      'plus a base of 1. Highest first.' + anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      return parts.join("") + '<p class="ntext none">No function matches that filter.</p>';
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      var barPct = Math.round(100 * r.complexity / maxC);
      parts.push('<tr class="anrow" data-node="' + esc(r.node.id) + '">' +
        '<td>' + esc(r.fn.signature) + sigTrigger(r.node.id, r.fn.name) +
          docTrigger(fnKey(r.node.id, r.fn.name)) + '</td>' +
        '<td>' + esc(r.name) + '</td>' +
        '<td>' + r.complexity + '</td>' +
        '<td><div class="anbar"><div class="anfill" style="width:' + barPct + '%"></div></div></td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  // Structural duplicates, straight off `ir.duplicates` — computed in Lua by
  // duplicates.lua rather than here, unlike the fan-in/fan-out panel. That one
  // is an aggregation over data already serialised; this one needs the parse
  // tree, which does not survive into the artifact, so the grouping has to
  // happen where the tree existed.
  function renderAnalysisDuplicates(){
    var dup = IR.duplicates;
    if(!dup){
      return '<p class="ntext none">This map was generated before duplicate ' +
        'detection existed. Regenerate it to see this panel.</p>';
    }

    var parts = [];
    if(!dup.groups || dup.groups.length === 0){
      parts.push('<p class="nsub">No two functions in this tree share a structure. ' +
        dup.considered + ' functions were large enough to compare (at least ' +
        dup.min_size + ' syntax nodes); anything smaller is excluded, because ' +
        'every tree has a dozen one-line accessors that match each other and ' +
        'mean nothing.</p>');
      parts.push('<p class="ntext none">Nothing to report.</p>');
      return parts.join("");
    }

    parts.push('<p class="nsub">' + dup.groups.length + ' group' +
      (dup.groups.length === 1 ? '' : 's') + ' of structurally identical functions, ' +
      'covering ' + dup.functions + ' of the ' + dup.considered + ' functions large ' +
      'enough to compare (at least ' + dup.min_size + ' syntax nodes). Identifier and ' +
      'literal names are ignored, so a renamed copy still matches — but a single ' +
      'edited line does not. Largest group first.</p>');
    parts.push('<p class="nsub">Sharing a shape is not by itself a defect: two ' +
      'adapters around different APIs can be the same five lines of plumbing. ' +
      'This is a ranking to read, never a check that fails.</p>');

    // Filtered by *group*, not by member: a duplicate group with its matching
    // members removed is no longer a duplicate group, and showing "3
    // identical" above one row would be a lie. So a group survives if any
    // member matches, and then survives whole.
    var query = (state.q || "").toLowerCase().trim();
    var groups = dup.groups;
    if(query){
      groups = groups.filter(function(g){
        return g.members.some(function(m){
          return ((m.signature || m.name || "") + " " + (m.module || m.node || ""))
            .toLowerCase().indexOf(query) >= 0;
        });
      });
      parts.push('<p class="nsub"><strong>' + groups.length + ' of ' +
        dup.groups.length + '</strong> groups shown, filtered by "' + esc(state.q) +
        '". A group matches when any of its members does, and is then shown whole — ' +
        'a group with members removed would no longer be one.</p>');
      if(groups.length === 0){
        return parts.join("") + '<p class="ntext none">No group matches that filter.</p>';
      }
    }

    groups.forEach(function(g){
      parts.push('<h3 class="nhead">' + g.members.length + ' identical, ' +
        g.size + ' nodes</h3>');
      parts.push('<table class="antable"><thead><tr><th>Function</th><th>Module</th>' +
        '<th>Line</th></tr></thead><tbody>');
      g.members.forEach(function(m){
        parts.push('<tr class="anrow" data-node="' + esc(m.node) + '">' +
          '<td>' + esc(m.signature || m.name) + sigTrigger(m.node, m.name) + '</td>' +
          '<td>' + esc(m.module || m.node) + '</td>' +
          '<td>' + m.line + '</td>' +
          '</tr>');
      });
      parts.push("</tbody></table>");
    });
    return parts.join("");
  }

  // One line per trigger kind actually present on a spec — mirrors
  // bindings/usrcmds/plugins.lua's `traits()` in Lua exactly, kept in sync by
  // hand because the two run in different languages and read the same
  // `Documentation.PluginSpec` shape for two different surfaces (this panel,
  // that command's quickfix list).
  // Whether anything in this spec defers the load.
  function pluginHasTrigger(spec){
    return ((spec.event || []).length + (spec.cmd || []).length +
            (spec.keys || []).length + (spec.ft || []).length) > 0;
  }

  // **When this plugin is actually loaded — four states, not two.**
  //
  // This used to answer "no trigger — loads at startup" for every spec with
  // no `event`/`cmd`/`ft`/`keys`, and that is wrong for one of them in a way
  // that matters. `lazy = true` with no trigger does *not* load at startup:
  // it loads when another plugin `require`s it, or on `:Lazy load`. Telling
  // its author it costs them startup time is the opposite of the truth, and
  // it is the state a dependency-only plugin is normally in.
  //
  // Measured before being called a defect: against a real 52-entry config,
  // **seven** specs were in exactly that state and every one was labelled
  // "loads at startup".
  //
  // `lazy` is `null` when unstated, which lazy.nvim resolves by looking at
  // the triggers — the same rule applied here, and the one place this file
  // re-derives a default the extractor deliberately did not.
  function pluginLoad(spec){
    if(spec.lazy === false) return "startup";
    if(pluginHasTrigger(spec)) return "trigger";
    if(spec.lazy === true) return "ondemand";
    return "startup";
  }

  function pluginTraits(spec){
    var bits = [];
    var load = pluginLoad(spec);
    if(spec.lazy === false) bits.push("eager");
    if((spec.event || []).length) bits.push("event:" + spec.event.join(","));
    if((spec.cmd || []).length) bits.push("cmd:" + spec.cmd.join(","));
    if((spec.keys || []).length) bits.push("keys:" + spec.keys.join(","));
    if((spec.ft || []).length) bits.push("ft:" + spec.ft.join(","));
    if(spec.enabled === false) bits.push("disabled");
    if(load === "ondemand"){
      bits.push("lazy = true, no trigger — loads only when required");
    }else if(bits.length === 0){
      bits.push("no trigger — loads at startup");
    }
    return bits.join("  ");
  }

  // lazy.nvim spec entries, straight off `n.plugins` — JS-side aggregation
  // only, no new Lua extraction, the same shape as the fan-in/fan-out panel:
  // the data already sits per-node in the serialised IR (`core/plugins.lua`
  // extracts it during the scan, where the parse tree exists; this only
  // walks what is already JSON).
  //
  // Sorted by repo, ascending, by default — unlike every other panel here.
  // The others rank a health metric worst-first; this is an inventory, and
  // "what do I have installed" is read alphabetically, not by severity.
  // The lazy-load inventory: the Plugins panel's question, inverted.
  //
  // Plugins answers "what does this plugin load on"; every row already says
  // so. What it cannot answer without reading every row is the other
  // direction — *which* plugins load on `VeryLazy`, what typing `:Neogit`
  // actually costs, and what is paid for unconditionally at startup. That is
  // the question "why is this not loaded yet" is really asking, and it is a
  // different index over the same data rather than new data.
  //
  // No new Lua extraction: `core/plugins.lua` already stamps `event`, `cmd`,
  // `ft` and `keys` per spec during the scan. This walks the serialised IR,
  // the same way the fan-in panel does.
  function renderAnalysisLazy(){
    // trigger identity -> row. Keyed by kind *and* value: an `ft` named
    // `lua` and a `cmd` named `lua` would otherwise share a row and claim
    // each other's plugins.
    var byTrigger = {};
    var total = 0;

    function bucket(kind, value){
      var key = kind + "\u0000" + value;
      if(!byTrigger[key]){
        byTrigger[key] = { kind: kind, value: value, repos: [], seen: {} };
      }
      return byTrigger[key];
    }

    IR.nodes.forEach(function(n){
      (n.plugins || []).forEach(function(spec){
        total++;
        var load = pluginLoad(spec);
        // The two trigger-less states get a bucket of their own rather than
        // being left out. "What loads at startup" is the most expensive
        // answer on this panel, and a panel about load timing that omitted
        // it would be answering the easy half.
        if(load === "startup"){
          var st = bucket("startup", "");
          if(!st.seen[spec.repo]){ st.seen[spec.repo] = true; st.repos.push(spec.repo); }
          return;
        }
        if(load === "ondemand"){
          var od = bucket("ondemand", "");
          if(!od.seen[spec.repo]){ od.seen[spec.repo] = true; od.repos.push(spec.repo); }
          return;
        }
        ["event", "cmd", "ft", "keys"].forEach(function(kind){
          (spec[kind] || []).forEach(function(v){
            var b = bucket(kind, String(v));
            if(!b.seen[spec.repo]){ b.seen[spec.repo] = true; b.repos.push(spec.repo); }
          });
        });
      });
    });

    var rows = Object.keys(byTrigger).map(function(k){
      var b = byTrigger[k];
      b.repos.sort();
      return {
        kind: b.kind,
        value: b.value,
        label: b.kind === "startup" ? "at startup"
          : b.kind === "ondemand" ? "when required by something else"
          : b.kind + ": " + b.value,
        count: b.repos.length,
        repos: b.repos.join(", "),
        haystack: b.kind + " " + b.value + " " + b.repos.join(" "),
        sortkey: b.kind + "#" + b.value
      };
    });

    if(total === 0){
      return '<p class="ntext none">No lazy.nvim-shaped plugin spec found in this tree, ' +
        'so there is nothing to say about when anything loads. ' +
        'See <code>core/plugins.lua</code> for what is recognized.</p>';
    }

    var cols = [
      { label: "Loads", key: "label", get: function(r){ return r.label; }, initial: "asc" },
      { label: "Plugins", key: "count", get: function(r){ return r.count; }, initial: "desc" },
      { label: "Which", key: "repos", get: function(r){ return r.repos; }, initial: "asc" }
    ];

    var totalRows = rows.length;
    rows = anFilter(rows);
    // **Startup first, then the biggest groups**, unlike the alphabetical
    // Plugins inventory next door. This panel is read for cost: what is paid
    // unconditionally comes first, and after that a trigger carrying seven
    // plugins matters more than one carrying a single plugin. `ondemand`
    // sorts last because it is the one state that costs nothing until
    // something asks.
    var ORDER = { startup: 0, event: 1, ft: 2, cmd: 3, keys: 4, ondemand: 5 };
    anSort(rows, cols, function(a, b){
      if(ORDER[a.kind] !== ORDER[b.kind]) return ORDER[a.kind] - ORDER[b.kind];
      if(a.count !== b.count) return b.count - a.count;
      return a.value < b.value ? -1 : (a.value > b.value ? 1 : 0);
    });

    var startup = byTrigger["startup\u0000"];
    var nstartup = startup ? startup.repos.length : 0;

    var parts = [];
    parts.push('<p class="nsub">' + total + ' plugin spec entr' +
      (total === 1 ? 'y' : 'ies') + ' across ' + totalRows + ' distinct load point' +
      (totalRows === 1 ? '' : 's') + '. <strong>' + nstartup + '</strong> load' +
      (nstartup === 1 ? 's' : '') + ' at startup — everything else is deferred.' +
      anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      return parts.join("") + '<p class="ntext none">No load point matches that filter.</p>';
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      parts.push('<tr><td>' + esc(r.label) + '</td><td class="num">' + r.count +
        '</td><td class="dim">' + esc(r.repos) + '</td></tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  function renderAnalysisPlugins(){
    var rows = [];
    var seen = {};
    IR.nodes.forEach(function(n){
      (n.plugins || []).forEach(function(spec){
        seen[spec.repo] = (seen[spec.repo] || 0) + 1;
      });
    });
    IR.nodes.forEach(function(n){
      var name = n.module || n.path;
      (n.plugins || []).forEach(function(spec){
        var traits = pluginTraits(spec);
        rows.push({
          node: n, spec: spec, repo: spec.repo, traits: traits,
          dup: seen[spec.repo] > 1, name: name,
          haystack: spec.repo + " " + traits + " " + name,
          sortkey: spec.repo + "#" + n.id
        });
      });
    });

    if(rows.length === 0){
      return '<p class="ntext none">No lazy.nvim-shaped plugin spec found in this tree. ' +
        'See <code>core/plugins.lua</code> for what is recognized — packer.nvim and ' +
        'vim-plug specs look different and are not.</p>';
    }

    var totalRows = rows.length;
    var ndup = 0;
    Object.keys(seen).forEach(function(r){ if(seen[r] > 1) ndup++; });

    var cols = [
      { label: "Repo", key: "repo", get: function(r){ return r.repo; }, initial: "asc" },
      { label: "Triggers", key: "traits", get: function(r){ return r.traits; }, initial: "asc" },
      { label: "Declared in", key: "name", get: function(r){ return r.name; }, initial: "asc" }
    ];

    rows = anFilter(rows);
    anSort(rows, cols, function(a, b){
      if(a.repo !== b.repo) return a.repo < b.repo ? -1 : 1;
      return a.node.id < b.node.id ? -1 : (a.node.id > b.node.id ? 1 : 0);
    });

    var parts = [];
    parts.push('<p class="nsub">' + totalRows + ' plugin spec entr' +
      (totalRows === 1 ? 'y' : 'ies') + '.' +
      (ndup > 0 ? ' <strong>' + ndup + '</strong> repo' + (ndup === 1 ? '' : 's') +
        ' declared more than once — in a config split across files, the last one ' +
        'lazy.nvim imports silently wins.' : '') +
      anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      return parts.join("") + '<p class="ntext none">No spec matches that filter.</p>';
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      parts.push('<tr class="anrow" data-node="' + esc(r.node.id) + '">' +
        '<td>' + esc(r.repo) + (r.dup ? ' <span class="anflag">⚠ duplicate</span>' : '') + '</td>' +
        '<td>' + esc(r.traits) + '</td>' +
        '<td>' + esc(r.name) + '</td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  // Keymaps / user commands / autocmds, straight off `n.bindings` — the same
  // JS-side-aggregation-only shape as the Plugins panel above: `core/
  // bindings.lua` did the extraction during the scan, where the parse tree
  // exists, and this only walks the serialised IR.
  //
  // Sorted by the identifying text (kind, then lhs/name/event) rather than
  // worst-first, for the reason `renderAnalysisPlugins` states — an
  // inventory is read alphabetically. That sort is also what makes
  // collisions visible: two rows for the same lhs land adjacent.
  function bindingLabel(b){
    if(b.kind === "keymap"){
      var modes = (b.modes || []).length ? b.modes.join("/") : "?";
      return "[" + modes + "] " + (b.lhs || "?");
    }
    if(b.kind === "usercmd") return ":" + (b.name || "?");
    return (b.events || []).join(",");
  }

  // Keymap collisions are per (mode, lhs); a user command's name is global.
  // Buffer-local registrations never collide — shadowing a global mapping
  // inside an ftplugin is the intended idiom, not a clash. Autocmds do not
  // collide at all: many handlers per event is the normal shape.
  // Built with fromCharCode rather than an escape: this whole script is a
  // Lua long string, so a literal control character here would be at the
  // mercy of any retab/whitespace pass that ever touches the file.
  var BSEP = String.fromCharCode(1);

  function bindingCollisionKey(b){
    if(b.kind === "keymap" && b.lhs && !b.buffer){
      var modes = (b.modes || []).length ? b.modes.join(",") : "?";
      return "keymap" + BSEP + modes + BSEP + b.lhs;
    }
    if(b.kind === "usercmd" && b.name) return "usercmd" + BSEP + b.name;
    return null;
  }

  function renderAnalysisBindings(){
    var rows = [];
    var seen = {};
    IR.nodes.forEach(function(n){
      (n.bindings || []).forEach(function(b){
        var key = bindingCollisionKey(b);
        if(key) seen[key] = (seen[key] || 0) + 1;
      });
    });
    var counts = { keymap: 0, usercmd: 0, autocmd: 0 };
    IR.nodes.forEach(function(n){
      var name = n.module || n.path;
      (n.bindings || []).forEach(function(b){
        var key = bindingCollisionKey(b);
        var label = bindingLabel(b);
        var desc = b.desc || "";
        counts[b.kind] = (counts[b.kind] || 0) + 1;
        var kindRank = b.kind === "keymap" ? "1" : (b.kind === "usercmd" ? "2" : "3");
        rows.push({
          node: n, kind: b.kind, label: label, desc: desc, name: name,
          via: b.callee, buffer: b.buffer === true,
          dup: key !== null && seen[key] > 1,
          haystack: label + " " + desc + " " + name + " " + b.callee,
          sortkey: kindRank + BSEP + label
        });
      });
    });

    if(rows.length === 0){
      return '<p class="ntext none">No keymap, user command or autocmd found. ' +
        'The <code>vim.*</code> APIs are always recognized; a config that binds ' +
        'through its own helper — <code>map(...)</code>, ' +
        '<code>usercmd.create(...)</code> — must declare it in ' +
        '<code>opts.bindings.wrappers</code>. See <code>core/bindings.lua</code>.</p>';
    }

    var totalRows = rows.length;
    var ndup = 0;
    Object.keys(seen).forEach(function(k){ if(seen[k] > 1) ndup++; });

    var cols = [
      { label: "Binding", key: "label", get: function(r){ return r.sortkey; }, initial: "asc" },
      { label: "Kind", key: "kind", get: function(r){ return r.kind; }, initial: "asc" },
      { label: "Description", key: "desc", get: function(r){ return r.desc; }, initial: "asc" },
      { label: "Declared in", key: "name", get: function(r){ return r.name; }, initial: "asc" }
    ];

    rows = anFilter(rows);
    anSort(rows, cols, function(a, b){
      if(a.sortkey !== b.sortkey) return a.sortkey < b.sortkey ? -1 : 1;
      return a.node.id < b.node.id ? -1 : (a.node.id > b.node.id ? 1 : 0);
    });

    var parts = [];
    parts.push('<p class="nsub">' + counts.keymap + ' keymap' +
      (counts.keymap === 1 ? '' : 's') + ', ' + counts.usercmd + ' command' +
      (counts.usercmd === 1 ? '' : 's') + ', ' + counts.autocmd + ' autocmd' +
      (counts.autocmd === 1 ? '' : 's') + '.' +
      (ndup > 0 ? ' <strong>' + ndup + '</strong> bound more than once — ' +
        'whichever module loads last silently wins.' : '') +
      anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      return parts.join("") + '<p class="ntext none">No binding matches that filter.</p>';
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      parts.push('<tr class="anrow" data-node="' + esc(r.node.id) + '">' +
        '<td><code>' + esc(r.label) + '</code>' +
        (r.dup ? ' <span class="anflag">⚠ duplicate</span>' : '') +
        (r.buffer ? ' <span class="anflag">buf</span>' : '') + '</td>' +
        '<td>' + esc(r.kind) + '</td>' +
        '<td>' + esc(r.desc || ("via " + r.via)) + '</td>' +
        '<td>' + esc(r.name) + '</td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  // Call-based route registrations, straight off `n.endpoints` — JS-side
  // aggregation only, no new extraction: `core/endpoints.lua` already
  // recognizes these during the scan, the same shape `n.plugins` already
  // is. See that module's own header for what counts as a route
  // (Express/Fastify/Koa-shaped `app.get(path, handler)`) and what does
  // not — `docs/ECOSYSTEM.md` §3.1 puts file-based routing
  // (Next.js/SvelteKit/Nuxt/Remix) in a Hierarchy view instead, not here.
  //
  // Sorted by path, ascending, by default — the same reasoning
  // `renderAnalysisPlugins` gives for repo: an inventory ("what routes does
  // this codebase have"), not a ranked health metric.
  function renderAnalysisEndpoints(){
    var rows = [];
    IR.nodes.forEach(function(n){
      var name = n.module || n.path;
      var fnByName = {};
      (n.functions || []).forEach(function(fn){ fnByName[fn.name] = fn; });
      (n.endpoints || []).forEach(function(spec){
        var handlerFn = spec.handler ? fnByName[spec.handler] : null;
        rows.push({
          node: n, spec: spec, method: spec.method.toUpperCase(),
          path: spec.path, handler: spec.handler || "(inline handler)",
          handlerFn: handlerFn, framework: spec.framework || "", name: name,
          documented: !!spec.documented, line: spec.line,
          haystack: spec.method + " " + spec.path + " " + (spec.handler || "") +
            " " + (spec.framework || "") + " " + name,
          sortkey: spec.path + "#" + spec.method
        });
      });
    });

    if(rows.length === 0){
      return '<p class="ntext none">No call-based route registration found in this ' +
        'tree. See <code>core/endpoints.lua</code> for what is recognized — file-based ' +
        'routing (Next.js and similar) is a separate, unbuilt concept, not this.</p>';
    }

    var totalRows = rows.length;
    var ndoc = 0;
    rows.forEach(function(r){ if(r.documented) ndoc++; });

    var cols = [
      { label: "Method", key: "method", get: function(r){ return r.method; }, initial: "asc" },
      { label: "Path", key: "path", get: function(r){ return r.path; }, initial: "asc" },
      { label: "Handler", key: "handler", get: function(r){ return r.handler; }, initial: "asc" },
      { label: "Framework", key: "framework", get: function(r){ return r.framework; }, initial: "asc" },
      { label: "Declared in", key: "name", get: function(r){ return r.name; }, initial: "asc" }
    ];

    rows = anFilter(rows);
    anSort(rows, cols, function(a, b){
      if(a.path !== b.path) return a.path < b.path ? -1 : 1;
      return a.method < b.method ? -1 : (a.method > b.method ? 1 : 0);
    });

    var parts = [];
    parts.push('<p class="nsub">' + totalRows + ' route' + (totalRows === 1 ? '' : 's') +
      ' found. <strong>' + ndoc + '</strong> of ' + totalRows +
      ' handler' + (totalRows === 1 ? '' : 's') + ' documented.' +
      anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      return parts.join("") + '<p class="ntext none">No route matches that filter.</p>';
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      var handlerCell = esc(r.handler);
      if(r.handlerFn){
        handlerCell += sigTrigger(r.node.id, r.handlerFn.name) +
          docTrigger(fnKey(r.node.id, r.handlerFn.name));
      }
      parts.push('<tr class="anrow" data-node="' + esc(r.node.id) + '">' +
        '<td>' + esc(r.method) + '</td>' +
        '<td>' + esc(r.path) + '</td>' +
        '<td>' + handlerCell + '</td>' +
        '<td>' + esc(r.framework) + '</td>' +
        '<td>' + esc(r.name) + '</td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  // React hooks, straight off `fn.is_hook` — JS-side aggregation only, no new
  // extraction: `core/lang/ecma.lua` already tags this per function at scan
  // time, the same shape as `n.plugins` above. A tree with no JS/TS backend
  // registered (this repository's own map, today) simply has no function
  // with the field set, which reads as "no hooks" rather than an error —
  // the panel does not need to know which languages exist.
  //
  // Sorted by name, ascending, by default — an inventory ("what hooks does
  // this codebase have"), not a ranked health metric, the same reasoning
  // `renderAnalysisPlugins` gives for sorting by repo instead of worst-first.
  function renderAnalysisHooks(){
    var rows = [];
    IR.nodes.forEach(function(n){
      var name = n.module || n.path;
      (n.functions || []).forEach(function(fn){
        if(!fn.is_hook) return;
        rows.push({
          node: n, fn: fn, name: fn.name, module: name,
          signature: fn.signature || fn.name, summary: fn.summary || "",
          line: fn.line,
          haystack: fn.name + " " + (fn.signature || "") + " " + name,
          sortkey: fn.name + "#" + n.id
        });
      });
    });

    if(rows.length === 0){
      return '<p class="ntext none">No function named like a React hook ' +
        '(<code>^use[A-Z]</code> — the same convention ' +
        '<code>eslint-plugin-react-hooks</code> itself relies on) was found. ' +
        'Only JavaScript/TypeScript/TSX files are checked for this — see ' +
        '<code>core/lang/ecma.lua</code>.</p>';
    }

    var totalRows = rows.length;
    var cols = [
      { label: "Hook", key: "name", get: function(r){ return r.name; }, initial: "asc" },
      { label: "Signature", key: "signature", get: function(r){ return r.signature; }, initial: "asc" },
      { label: "Declared in", key: "module", get: function(r){ return r.module; }, initial: "asc" },
      { label: "Line", key: "line", get: function(r){ return r.line; }, initial: "asc" }
    ];

    rows = anFilter(rows);
    anSort(rows, cols, function(a, b){
      if(a.name !== b.name) return a.name < b.name ? -1 : 1;
      return a.node.id < b.node.id ? -1 : (a.node.id > b.node.id ? 1 : 0);
    });

    var parts = [];
    parts.push('<p class="nsub">' + totalRows + ' hook' + (totalRows === 1 ? '' : 's') +
      ' found by name.' + anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      return parts.join("") + '<p class="ntext none">No hook matches that filter.</p>';
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      parts.push('<tr class="anrow" data-node="' + esc(r.node.id) + '">' +
        '<td>' + esc(r.name) + '</td>' +
        '<td>' + esc(r.signature) + sigTrigger(r.node.id, r.fn.name) + '</td>' +
        '<td>' + esc(r.module) + '</td>' +
        '<td>' + r.line + '</td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  // The documentation corpus itself (`ir.docs.files`) — every `.md` file
  // `core/docs.lua` scanned, with how many code-span mentions it made.
  // ECOSYSTEM.md §3.4 calls this "cheap, once the corpus scan exists": no
  // new extraction, just the same `anFilter`/`anSort`/`anHead` plumbing
  // every other panel already uses, over data `docs.lua` already collected.
  //
  // Rows carry no `data-node` and are not `.anrow`-classed: a doc file is
  // not a `Documentation.Node`, so there is nowhere in the Tree tab for a
  // click to land — giving these rows the hover/click affordance every
  // other panel's clickable rows have would be a false promise. Where a
  // reference actually resolves to a function or module is the marker
  // beside that entity (`sigTrigger`/the docs-reference popup), not this
  // overview.
  //
  // `doc-references-missing` (`ir.docs.missing`) is deliberately not
  // repeated here — it is already a `check.lua` finding, in the Notes tab,
  // and belongs to "what is wrong" rather than "what documentation exists".
  function renderAnalysisDocs(){
    var files = (IR.docs && IR.docs.files) || [];

    if(files.length === 0){
      return '<p class="ntext none">No <code>.md</code> file was found under this ' +
        'tree (see <code>core/docs.lua</code> for what counts as the corpus), or this ' +
        'map was generated before the docs corpus scan existed.</p>';
    }

    var rows = files.map(function(f){
      return {
        path: f.path, title: f.title || f.path, refs: f.refs || 0,
        haystack: f.path + " " + (f.title || ""), sortkey: f.path
      };
    });
    var totalRows = rows.length;
    var totalRefs = 0;
    rows.forEach(function(r){ totalRefs += r.refs; });

    var cols = [
      { label: "Path", key: "path", get: function(r){ return r.path; }, initial: "asc" },
      { label: "Title", key: "title", get: function(r){ return r.title; }, initial: "asc" },
      { label: "References", key: "refs", get: function(r){ return r.refs; }, initial: "desc" }
    ];

    rows = anFilter(rows);
    anSort(rows, cols, function(a, b){
      return a.path < b.path ? -1 : (a.path > b.path ? 1 : 0);
    });

    var parts = [];
    parts.push('<p class="nsub">' + totalRows + ' documentation file' +
      (totalRows === 1 ? '' : 's') + ', ' + totalRefs + ' code-span reference' +
      (totalRefs === 1 ? '' : 's') + ' resolved in total.' +
      anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      return parts.join("") + '<p class="ntext none">No file matches that filter.</p>';
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      parts.push('<tr>' +
        '<td>' + esc(r.path) + '</td>' +
        '<td>' + esc(r.title) + '</td>' +
        '<td>' + r.refs + '</td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  // This repo's own `lib.nvim.deps` manifest — `IR.tools`, a repo-level
  // object rather than a per-node array (there is exactly one
  // docs/install.json or docs/INSTALL.md per repo, not one per file), same
  // shape `IR.docs`/`IR.duplicates` already are. Declared tools only: never
  // a live "is this installed on my machine" check, which a static page
  // read on GitHub Pages has no host to ask anyway — see `core/tools.lua`'s
  // header for why that stays out of the artifact entirely, not just this
  // panel.
  function renderAnalysisTools(){
    var spec = IR.tools;
    var tools = (spec && spec.tools) || [];
    var errors = (spec && spec.errors) || [];

    if(!spec){
      return '<p class="ntext none">No <code>docs/install.json</code> or ' +
        '<code>docs/INSTALL.md</code> found in this repo (or lib.nvim.deps was not ' +
        'available when this map was generated) — see <code>core/tools.lua</code>, or ' +
        'lib.nvim\'s <code>:help lib.nvim-deps-declaring</code>.</p>';
    }
    if(tools.length === 0 && errors.length === 0){
      return '<p class="ntext none">' + esc(spec.source) + ' declares no tools.</p>';
    }

    var rows = tools.map(function(t){
      var pkgs = Object.keys(t.pkg || {}).sort();
      return {
        bin: t.bin, required: !!t.required, why: t.why, pkg: pkgs.join(", "),
        haystack: t.bin + " " + t.why + " " + pkgs.join(" "), sortkey: t.bin
      };
    });
    var totalRows = rows.length;
    var nrequired = 0;
    rows.forEach(function(r){ if(r.required) nrequired++; });

    var cols = [
      { label: "Tool", key: "bin", get: function(r){ return r.bin; }, initial: "asc" },
      { label: "Required", key: "required", get: function(r){ return r.required ? 1 : 0; }, initial: "desc" },
      { label: "Why", key: "why", get: function(r){ return r.why; }, initial: "asc" },
      { label: "Packages", key: "pkg", get: function(r){ return r.pkg; }, initial: "asc" }
    ];

    rows = anFilter(rows);
    anSort(rows, cols, function(a, b){
      return a.bin < b.bin ? -1 : (a.bin > b.bin ? 1 : 0);
    });

    var parts = [];
    parts.push('<p class="nsub">' + totalRows + ' tool' + (totalRows === 1 ? '' : 's') +
      ' declared in ' + esc(spec.source) + ', ' + nrequired + ' required.' +
      (errors.length > 0 ? ' <strong>' + errors.length + '</strong> invalid entr' +
        (errors.length === 1 ? 'y' : 'ies') + ' — see the drift findings below.' : '') +
      anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      return parts.join("") + '<p class="ntext none">No tool matches that filter.</p>';
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      parts.push('<tr>' +
        '<td><code>' + esc(r.bin) + '</code></td>' +
        '<td>' + (r.required ? 'required' : 'optional') + '</td>' +
        '<td>' + esc(r.why) + '</td>' +
        '<td>' + esc(r.pkg) + '</td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    return parts.join("");
  }

  // Rendered panels, memoised per *rendering* rather than per panel.
  //
  // One variable per panel was correct while a panel had exactly one
  // rendering. Sorting and filtering give it many, so the key carries them —
  // otherwise clicking a column re-serves the previous order out of the cache
  // and the header arrow moves while the rows do not.
  //
  // Unbounded on purpose: the key space is (9 panels x ~4 columns x 2
  // directions x the queries actually typed), every entry is a string already
  // built once, and the alternative — evicting — would re-render on a Back
  // button press, which is the one moment the cache exists for.
  var analysisCache = {};

  function anCacheKey(atool){
    return atool + "|" + (state.asort || "") + "|" + (state.adir || "") + "|" + (state.q || "");
  }

  ///Render one panel from scratch. Sort and filter come from `state`.
  function renderAnalysis(atool){
    if(atool === "test"){
      return renderAnalysisPanel(
        "Tested",
        "A function counts as tested when its bare name is found somewhere " +
        "under the configured tests directory — see docmap's coverage.lua " +
        "for what that heuristic can and cannot see.",
        function(fn){ return !!fn.tested; },
        false
      );
    }
    if(atool === "doc"){
      return renderAnalysisPanel(
        "Documented",
        "A function counts as documented when it has a summary and its " +
        "parameters are fully and correctly named — @internal functions " +
        "are excluded entirely, not counted as undocumented.",
        function(fn){ return !!fn.documented; },
        true
      );
    }
    if(atool === "annotations") return renderAnalysisAnnotations();
    if(atool === "api") return renderAnalysisApi();
    if(atool === "deps") return renderAnalysisDeps();
    if(atool === "complexity") return renderAnalysisComplexity();
    if(atool === "duplicates") return renderAnalysisDuplicates();
    if(atool === "hooks") return renderAnalysisHooks();
    if(atool === "lazy") return renderAnalysisLazy();
    if(atool === "docs") return renderAnalysisDocs();
    if(atool === "endpoints") return renderAnalysisEndpoints();
    if(atool === "tools") return renderAnalysisTools();
    if(atool === "bindings") return renderAnalysisBindings();
    return renderAnalysisPlugins();
  }

  function drawAnalysis(){
    var atool = (state.atool === "doc" || state.atool === "deps" ||
      state.atool === "complexity" || state.atool === "duplicates" ||
      state.atool === "plugins" || state.atool === "lazy" ||
      state.atool === "tools" || state.atool === "hooks" ||
      state.atool === "docs" || state.atool === "endpoints" || state.atool === "telemetry" ||
      state.atool === "loaded" || state.atool === "checklist" ||
      state.atool === "api" || state.atool === "annotations" ||
      state.atool === "bindings")
      ? state.atool : "test";

    document.querySelectorAll("#antoggle .anview-btn").forEach(function(b){
      b.classList.toggle("active", b.dataset.atool === atool);
    });

    // Telemetry/Loaded are not computed from the embedded IR and cannot
    // be — see each draw function's own header for why. They get a
    // separate path rather than a branch inside `renderAnalysis`, the
    // same reason History is a sibling of this whole function rather than
    // a case in it: the cache below is for synchronous, IR-only renders,
    // and a fetch does not fit that shape.
    if(atool === "telemetry"){
      drawAnalysisTelemetry();
      return;
    }
    if(atool === "loaded"){
      drawAnalysisLoaded();
      return;
    }
    // Unlike Telemetry and Loaded above, this one is not fetch-*dependent*:
    // the ledger is baked into the page and renders completely from
    // `IR.checklist`. The fetch only adds the staleness verdict, so the
    // panel is fully useful from `file://` and merely gains a column under
    // `:DocMap serve`. It still takes the separate path rather than a case
    // in `renderAnalysis`, for the same reason those two do — the cache
    // below is for synchronous renders, and an enrichment that arrives
    // later does not fit it.
    if(atool === "checklist"){
      drawAnalysisChecklist();
      return;
    }

    var host = document.getElementById("anbody");
    var key = anCacheKey(atool);
    if(analysisCache[key] === undefined) analysisCache[key] = renderAnalysis(atool);
    host.innerHTML = analysisCache[key];

    host.querySelectorAll(".anrow").forEach(function(tr){
      tr.addEventListener("click", function(){
        navigate({ tab: "tree", id: tr.dataset.node });
      });
    });

    // Sortable headers. Clicking the active column flips direction; clicking a
    // new one starts at that column's natural direction — descending for a
    // number (largest first is what a ranking means), ascending for a name.
    host.querySelectorAll("th.ansort").forEach(function(th){
      th.addEventListener("click", function(){
        var key2 = th.dataset.sort;
        var dir;
        if(state.asort === key2){
          dir = state.adir === "asc" ? "desc" : "asc";
        } else {
          dir = th.dataset.initial === "asc" ? "asc" : "desc";
        }
        navigate({ tab: "analysis", atool: atool, asort: key2, adir: dir });
      });
    });
  }

  // ---------------------------------------------------------------------
  // Analysis -> Telemetry: the runtime-analysis.nvim join, on demand.
  //
  // Not computed from the embedded IR, and cannot be: call counts change
  // between runs, and baking them into `module_map.json` would make
  // `--check`'s byte-for-byte comparison depend on when it happened to run
  // relative to real usage — the same reason `core/tools.lua`'s own header
  // keeps host-presence checks out of the artifact, one step further
  // (there, the *shape* is deterministic and only presence is not; here,
  // the counts themselves are the volatile part). `/api/telemetry` reads
  // `runtime-analysis.telemetry` straight off disk on every request, so
  // this is always the latest aggregate, never a stale snapshot baked in
  // at generate() time — see `documentation.editor.serve`'s own header for
  // why that means a server, exactly the History tab's own reasoning.
  //
  // `state.tsnap` (which capture the single-view table reads) and
  // `state.tsnapb` (set only in compare mode — `null` means "not
  // comparing", the string `"latest"` means "compare against the live
  // aggregate explicitly", anything else is a snapshot name) both default
  // to `null`/`"latest"` meaning the live aggregate, matching what this
  // panel always showed before named snapshots existed. Threaded through
  // `navigate()`/the URL the same way `atool`/`asort` already are, so a
  // link to a specific comparison is shareable.
  // ---------------------------------------------------------------------
  var telSnapLoaded = false, telSnapList = null;
  var telCache = {}, telReqToken = 0;

  // Fetch (and cache) /api/telemetry's response for one capture. `name` is
  // null/"latest" for the live aggregate, otherwise a snapshot name — both
  // forms state.tsnap/state.tsnapb can hold.
  function telFetch(name){
    var key = (!name || name === "latest") ? "" : name;
    if(telCache[key]) return Promise.resolve(telCache[key]);
    var url = key ? ("/api/telemetry?snapshot=" + encodeURIComponent(key)) : "/api/telemetry";
    return fetch(url).then(function(r){ return r.json(); }).then(function(d){
      telCache[key] = d;
      return d;
    });
  }

  function drawAnalysisTelemetry(){
    var host = document.getElementById("anbody");
    if(!historyAvailable()){
      host.innerHTML = '<p class="hmsg">This page was opened from a file, so the Telemetry panel has ' +
        'nothing to ask.<br><br>Call counts live outside the committed map on purpose — they change between ' +
        'runs, which the committed artifact never does — so reading them needs a server. Run ' +
        '<code>:DocMap serve</code> and open the URL it prints (or <code>:DocMap open</code> while it runs).</p>';
      return;
    }

    var token = ++telReqToken;
    host.innerHTML = '<p class="hmsg">Loading telemetry…</p>';

    var snapListPromise = telSnapLoaded
      ? Promise.resolve(telSnapList)
      : fetch("/api/telemetry/snapshots").then(function(r){ return r.json(); }).then(function(d){
          telSnapLoaded = true;
          telSnapList = (d && d.snapshots) || [];
          return telSnapList;
        }).catch(function(){ telSnapLoaded = true; telSnapList = []; return telSnapList; });

    var fetches = [telFetch(state.tsnap)];
    if(state.tsnapb) fetches.push(telFetch(state.tsnapb));

    Promise.all([snapListPromise].concat(fetches))
      .then(function(results){
        if(token !== telReqToken) return; // a newer selection superseded this one
        renderAnalysisTelemetryBody(results[1], state.tsnapb ? results[2] : null);
      })
      .catch(function(e){
        if(token !== telReqToken) return;
        explainFetchFailure(e, "the Telemetry panel").then(function(msg){
          // The token is re-checked after the probe: a newer selection may
          // have superseded this one while it was in flight.
          if(token === telReqToken) host.innerHTML = msg;
        });
      });
  }

  // The picker row: "Snapshot:" (single view) plus, once at least one
  // snapshot exists, a "Compare vs:" second select that switches into the
  // diff render below. Rendered even with zero snapshots saved yet — the
  // "Snapshot:" select still lets a reader pick "Latest" explicitly, and
  // an empty picker row would read as a missing feature rather than "no
  // snapshots saved yet".
  // {v, l} (value, label) objects to <option> HTML, marking whichever
  // matches "selected" -- one small builder instead of the fragile "join
  // then string-replace the right value= in afterward" a first draft of
  // this used, which risked matching the wrong option whenever one value
  // was a substring of another. Objects rather than [value, label]
  // tuples for a second, entirely mechanical reason: this whole script is
  // one Lua long-bracket string, and two adjacent closing square brackets
  // anywhere inside it -- which a tuple array closing right after a
  // nested one produces -- close that Lua string early. Not a style
  // preference; the first draft of this function shipped with exactly
  // that bug.
  function telOptionsHTML(items, selected){
    return items.map(function(it){
      return '<option value="' + esc(it.v) + '"' + (it.v === selected ? " selected" : "") + '>' +
        esc(it.l) + "</option>";
    }).join("");
  }

  function telPickerHTML(){
    var aItems = [{ v: "", l: "Latest" }].concat((telSnapList || []).map(function(s){
      var d = new Date(s.saved_at * 1000);
      return { v: s.name, l: s.name + " (" + d.toLocaleString() + ")" };
    }));
    var h = ['<div class="telpicker">'];
    h.push('<label>Snapshot: <select id="telsnap">' +
      telOptionsHTML(aItems, state.tsnap || "") + '</select></label>');
    if((telSnapList || []).length > 0){
      var bItems = [{ v: "", l: "— not comparing —" }, { v: "latest", l: "Latest" }]
        .concat((telSnapList || []).map(function(s){ return { v: s.name, l: s.name }; }));
      h.push('<label>Compare vs: <select id="telsnapb">' +
        telOptionsHTML(bItems, state.tsnapb || "") + '</select></label>');
    }
    h.push("</div>");
    return h.join("");
  }

  function telWirePicker(){
    var snapSel = document.getElementById("telsnap");
    if(snapSel) snapSel.addEventListener("change", function(){
      navigate({ tab: "analysis", atool: "telemetry", tsnap: snapSel.value || null });
    });
    var snapBSel = document.getElementById("telsnapb");
    if(snapBSel) snapBSel.addEventListener("change", function(){
      navigate({ tab: "analysis", atool: "telemetry", tsnapb: snapBSel.value || null });
    });
  }

  function telUnavailableMessage(d){
    var reason = (d && d.reason) || "unknown";
    if(reason === "no namespace"){
      return "No telemetry namespace configured for this project — set " +
        "<code>opts.telemetry_namespace</code> or <code>opts.title</code>.";
    }
    if(reason === "no map generated yet"){
      return "No map has been generated yet on this machine — run <code>:DocMap</code> first.";
    }
    if(reason === "snapshot not found"){
      return "Snapshot <code>" + esc((d && d.snapshot) || "") + "</code> was not found — it may have " +
        "been evicted (only the most recent ones are kept).";
    }
    return "No telemetry data for namespace <code>" + esc((d && d.namespace) || "") + "</code> yet — " +
      "install/enable <code>runtime-analysis.nvim</code>, or <code>:RATelemetry start</code> there.";
  }

  function renderAnalysisTelemetryBody(dA, dB){
    var host = document.getElementById("anbody");

    if(!dA || !dA.available){
      host.innerHTML = telPickerHTML() + '<p class="ntext none">' + telUnavailableMessage(dA) + '</p>';
      telWirePicker();
      return;
    }
    if(dB !== null && (!dB || !dB.available)){
      host.innerHTML = telPickerHTML() + '<p class="ntext none">' + telUnavailableMessage(dB) + '</p>';
      telWirePicker();
      return;
    }

    var parts = [telPickerHTML()];

    if(dB === null){
      // Single-capture view — unchanged from before the picker existed,
      // just fed by whichever capture is currently selected instead of
      // always the live aggregate.
      var totalRows = (dA.rows || []).length;
      var rows = anFilter((dA.rows || []).map(function(r){
        return {
          id: r.id, fn: r.fn, ir_key: r.ir_key, calls: r.calls,
          has_static_caller: r.has_static_caller,
          haystack: r.ir_key, sortkey: r.ir_key
        };
      }));

      if(totalRows === 0){
        parts.push('<p class="ntext none">Telemetry namespace <code>' + esc(dA.namespace) +
          '</code> has data, but none of it resolved to a function still in this map.</p>');
        host.innerHTML = parts.join("");
        telWirePicker();
        return;
      }

      var cols = [
        { label: "Function", key: "ir_key", get: function(r){ return r.ir_key; }, initial: "asc" },
        { label: "Calls", key: "calls", get: function(r){ return r.calls; }, initial: "desc" },
        { label: "Static caller?", key: "has_static_caller",
          get: function(r){ return r.has_static_caller ? 1 : 0; }, initial: "desc" }
      ];
      anSort(rows, cols, function(a, b){ return b.calls - a.calls; });

      parts.push('<p class="nsub">' + rows.length + ' function' + (rows.length === 1 ? '' : 's') +
        ' with telemetry data in namespace <code>' + esc(dA.namespace) + '</code>' +
        (state.tsnap ? ' (snapshot ' + esc(state.tsnap) + ')' : ' (latest)') + '.' +
        anFilterNote(rows.length, totalRows) + '</p>');
      if(rows.length === 0){
        parts.push('<p class="ntext none">No function matches that filter.</p>');
        host.innerHTML = parts.join("");
        telWirePicker();
        return;
      }
      parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
      rows.forEach(function(r){
        parts.push('<tr class="anrow" data-node="' + esc(r.id) + '">' +
          '<td><code>' + esc(r.ir_key) + '</code></td>' +
          '<td>' + r.calls + '</td>' +
          '<td>' + (r.has_static_caller ? "yes" : "no static caller found") + '</td>' +
          '</tr>');
      });
      parts.push("</tbody></table>");
      host.innerHTML = parts.join("");
      host.querySelectorAll(".anrow").forEach(function(tr){
        tr.addEventListener("click", function(){
          navigate({ tab: "tree", id: tr.dataset.node });
        });
      });
      telWirePicker();
      return;
    }

    // A/B diff — the point of naming snapshots at all: "what changed
    // between these two captures", not just "what does one look like".
    // Union of both sides' functions, not an intersection: a function only
    // one side has data for is exactly as real a result as one both do —
    // it either did not exist yet, or was never called, at the other
    // point in time, which is itself the answer to "what changed".
    var byKeyA = {}, byKeyB = {};
    (dA.rows || []).forEach(function(r){ byKeyA[r.ir_key] = r; });
    (dB.rows || []).forEach(function(r){ byKeyB[r.ir_key] = r; });
    var allKeys = Object.keys(byKeyA);
    Object.keys(byKeyB).forEach(function(k){ if(!(k in byKeyA)) allKeys.push(k); });

    var diffRows = anFilter(allKeys.map(function(k){
      var ra = byKeyA[k], rb = byKeyB[k];
      var callsA = ra ? ra.calls : 0, callsB = rb ? rb.calls : 0;
      return {
        id: (ra || rb).id, ir_key: k, callsA: callsA, callsB: callsB,
        delta: callsB - callsA, haystack: k, sortkey: k
      };
    }));

    var cols = [
      { label: "Function", key: "ir_key", get: function(r){ return r.ir_key; }, initial: "asc" },
      { label: "A", key: "callsA", get: function(r){ return r.callsA; }, initial: "desc" },
      { label: "B", key: "callsB", get: function(r){ return r.callsB; }, initial: "desc" },
      { label: "Δ (B − A)", key: "delta", get: function(r){ return Math.abs(r.delta); }, initial: "desc" }
    ];
    anSort(diffRows, cols, function(a, b){ return Math.abs(b.delta) - Math.abs(a.delta); });

    var aLabel = state.tsnap ? esc(state.tsnap) : "latest";
    var bLabel = (state.tsnapb === "latest" || !state.tsnapb) ? "latest" : esc(state.tsnapb);
    parts.push('<p class="nsub">Comparing <code>' + aLabel + '</code> (A) against <code>' + bLabel +
      '</code> (B) — ' + diffRows.length + ' function' + (diffRows.length === 1 ? '' : 's') + '.' +
      anFilterNote(diffRows.length, allKeys.length) + '</p>');
    if(diffRows.length === 0){
      parts.push('<p class="ntext none">No function matches that filter.</p>');
      host.innerHTML = parts.join("");
      telWirePicker();
      return;
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    diffRows.forEach(function(r){
      var sign = r.delta > 0 ? "+" : "";
      parts.push('<tr class="anrow" data-node="' + esc(r.id) + '">' +
        '<td><code>' + esc(r.ir_key) + '</code></td>' +
        '<td>' + r.callsA + '</td>' +
        '<td>' + r.callsB + '</td>' +
        '<td class="' + (r.delta > 0 ? "telup" : r.delta < 0 ? "teldown" : "") + '">' +
          sign + r.delta + '</td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    host.innerHTML = parts.join("");
    host.querySelectorAll(".anrow").forEach(function(tr){
      tr.addEventListener("click", function(){
        navigate({ tab: "tree", id: tr.dataset.node });
      });
    });
    telWirePicker();
  }

  // ---------------------------------------------------------------------
  // Analysis -> Loaded: the runtime-analysis.loaded persisted-snapshot join,
  // docs/ROADMAP.md §5.4 — "cold viewing" of a loaded-vs-declared diff taken
  // in a process that is not this one.
  //
  // Unlike Telemetry, there is no "live aggregate" fallback here: a loaded
  // diff is inherently a property of *some* live session's package.loaded,
  // and the only such session `:DocBrowse loaded` can read is the one the
  // browser was opened from — a browser tab, running in a different
  // process entirely, has no live package.loaded of its own to read. So
  // this panel only ever reads named snapshots (`:RA loaded snapshot
  // <prefix> [name]`, runtime-analysis.nvim's own §5.4 command) — never a
  // "Latest" option the way Telemetry's picker has one. `state.lsnap` is
  // `null` until a snapshot is actually chosen; the panel prompts for one
  // rather than guessing.
  // ---------------------------------------------------------------------
  var loadedSnapLoaded = false, loadedSnapList = null;
  var loadedCache = {};

  function loadedFetch(name){
    if(loadedCache[name]) return Promise.resolve(loadedCache[name]);
    return fetch("/api/loaded?snapshot=" + encodeURIComponent(name))
      .then(function(r){ return r.json(); })
      .then(function(d){ loadedCache[name] = d; return d; });
  }

  // ── Checklist ────────────────────────────────────────────────────────────
  //
  // The one Analysis panel whose data is baked but whose *verdict* is not.
  // `IR.checklist` carries the whole ledger, so every item, citation and
  // date renders from `file://` with no server. What cannot be baked is
  // whether the cited files have moved since verification: that comes from
  // `git log`, and core/churn.lua established that git data in a
  // byte-compared artifact leaves the map with no fixed point.
  //
  // So the panel renders twice — immediately from the IR, then again with
  // the verdict once `/api/checklist` answers. A reader on a static page
  // gets a complete ledger and a one-line note saying what is missing and
  // how to get it, rather than a blank panel.

  // Verdict by "<file>:<line>", or null before the fetch resolves / when
  // there is no server to ask.
  var checklistStatus = null, checklistFailed = false;
  var checklistTried = false;

  function checklistStateLabel(st){
    if(!st) return { cls: "cl-unknown", text: "—" };
    if(st.state === "stale"){
      return { cls: "cl-stale", text: st.commits + " commit" + (st.commits === 1 ? "" : "s") + " since" };
    }
    if(st.state === "unverified") return { cls: "cl-unverified", text: "never verified" };
    if(st.state === "uncited") return { cls: "cl-uncited", text: "no citation" };
    return { cls: "cl-current", text: "unchanged" };
  }

  function renderChecklistBody(){
    var led = IR.checklist;
    if(!led){
      return '<p class="ntext none">This repository has no checklist. Create ' +
        '<code>docs/CHECKLIST/*.md</code> (or <code>docs/CHECKLIST.md</code>) — ' +
        'see <code>docs/CHECKLIST_FORMAT.md</code>.</p>';
    }

    var out = [];
    var note;
    if(checklistStatus){
      var c = checklistStatus.counts || {};
      note = '<p class="ntext">' + (c.stale || 0) + ' stale, ' + (c.unverified || 0) +
        ' unverified, ' + (c.current || 0) + ' current, ' + (c.uncited || 0) +
        ' uncited — of ' + led.total + ' item' + (led.total === 1 ? "" : "s") + '.</p>';
    } else if(!historyAvailable() || checklistFailed){
      // `checklistFailed` covers the published copy: the protocol says
      // fetching is possible, the enrichment still cannot be answered, and
      // without this the note sat on "Reading history…" forever. The wording
      // below is already right for both — the verdict needs git *and* a local
      // server, neither of which a static host has.
      note = '<p class="ntext">' + led.done + ' of ' + led.total + ' done, ' + led.cited +
        ' cited. <em>Changed-since-verified needs git, so it is not in this file.</em> Run ' +
        '<code>:DocMap serve</code> and open the URL it prints to fill in the verdict — or ' +
        '<code>:DocMap checklist</code> for the same answer in the quickfix list.</p>';
    } else {
      note = '<p class="ntext">' + led.done + ' of ' + led.total + ' done, ' + led.cited +
        ' cited. Reading history…</p>';
    }
    out.push(note);

    (led.files || []).forEach(function(f){
      (f.sections || []).forEach(function(sec){
        if(!sec.items || sec.items.length === 0) return;
        var heading = sec.name || f.name;
        out.push('<h3 class="cl-h">' + esc(heading) +
          ' <span class="cl-src">' + esc(f.path) + '</span></h3>');
        out.push('<ul class="cl-list">');
        sec.items.forEach(function(it){
          var st = checklistStatus && checklistStatus.status
            ? checklistStatus.status[it.file + ":" + it.line] : null;
          var lab = checklistStateLabel(st);
          var bits = [];
          bits.push('<li class="cl-item ' + (it.done ? "cl-done" : "cl-open") + '">');
          bits.push('<span class="cl-box">' + (it.done ? "✓" : " ") + '</span>');
          bits.push('<span class="cl-text">' + esc(it.text) + '</span>');
          if(it.ref){
            bits.push('<span class="cl-ref">' + esc(it.ref) +
              (it.ref_line ? ":" + it.ref_line : "") + '</span>');
          }
          if(it.verified) bits.push('<span class="cl-date">verified ' + esc(it.verified) + '</span>');
          if(st) bits.push('<span class="cl-state ' + lab.cls + '">' + esc(lab.text) + '</span>');
          (it.meta || []).forEach(function(m){
            bits.push('<span class="cl-meta"><b>@' + esc(m.key) + '</b> ' + esc(m.value) + '</span>');
          });
          bits.push('</li>');
          out.push(bits.join(""));
        });
        out.push('</ul>');
      });
    });

    return out.join("");
  }

  function drawAnalysisChecklist(){
    var host = document.getElementById("anbody");
    host.innerHTML = renderChecklistBody();

    // One fetch per page load, not per panel open: the answer only changes
    // when someone commits, and re-asking on every tab switch would spawn a
    // whole-history `git log` each time.
    if(!IR.checklist || checklistTried || !historyAvailable()) return;
    checklistTried = true;

    fetch("/api/checklist").then(function(r){ return r.json(); }).then(function(d){
      if(d && d.available) checklistStatus = d;
      if(state.tab === "analysis" && state.atool === "checklist"){
        document.getElementById("anbody").innerHTML = renderChecklistBody();
      }
    }).catch(function(){
      // Still silent — the panel above is already complete and correct
      // without a verdict, and a scary error over a missing enrichment would
      // overstate what went wrong. But the note has to stop claiming it is
      // still reading, which is what this flag is for.
      checklistFailed = true;
      if(state.tab === "analysis" && state.atool === "checklist"){
        document.getElementById("anbody").innerHTML = renderChecklistBody();
      }
    });
  }

  function drawAnalysisLoaded(){
    var host = document.getElementById("anbody");
    if(!historyAvailable()){
      host.innerHTML = '<p class="hmsg">This page was opened from a file, so the Loaded panel has ' +
        'nothing to ask.<br><br>Snapshots live outside the committed map on purpose — the same reason ' +
        'Telemetry does — so reading them needs a server. Run <code>:DocMap serve</code> and open the ' +
        'URL it prints (or <code>:DocMap open</code> while it runs).</p>';
      return;
    }

    // Two separate fetches can run below — the snapshot list (once per page
    // load) and, once a snapshot is picked, that snapshot's own data (every
    // time the picker changes) — and either one left in flight with nothing
    // shown was the same bug from two different code paths. The list-fetch
    // case: switching tabs to Loaded left whatever panel was on screen
    // before sitting there unchanged, so the toolbar said "Loaded" while
    // the body still showed a different panel's table. The snapshot-fetch
    // case, found the same way right after: picking a snapshot from the
    // dropdown left the *previous* "choose a snapshot" message on screen
    // for the length of the request, which reads as "nothing happened" and
    // not as "loading". Telemetry never had either problem — it shows its
    // own loading message unconditionally because it re-fetches live data on
    // every draw; here the same message needs a wider gate than "not yet
    // fetched" because a *second*, later fetch is just as real as the first.
    // Left un-gated only for the true no-op case: an already-loaded list
    // with no snapshot picked resolves with nothing to wait for.
    if(!loadedSnapLoaded || state.lsnap) host.innerHTML = '<p class="hmsg">Loading…</p>';

    var snapListPromise = loadedSnapLoaded
      ? Promise.resolve(loadedSnapList)
      : fetch("/api/loaded/snapshots").then(function(r){ return r.json(); }).then(function(d){
          loadedSnapLoaded = true;
          loadedSnapList = (d && d.snapshots) || [];
          return loadedSnapList;
        });
    // No `.catch` swallowing the failure into an empty list, deliberately.
    // A server that simply has no snapshots answers `{"snapshots":[]}` with
    // a 200, so this promise only rejects when the request genuinely failed
    // — and turning that into "No snapshots saved yet" states something
    // about the *data* when the truth is about the *server*. On a published
    // copy of the map that reading is plainly wrong, which is how it was
    // found. Letting it reject hands it to the outer catch, which explains
    // the real situation; `loadedSnapLoaded` staying false also means the
    // next draw retries rather than caching a failure forever.

    snapListPromise.then(function(list){
      if(!state.lsnap){
        renderAnalysisLoadedBody(null, list);
        return;
      }
      return loadedFetch(state.lsnap).then(function(d){
        renderAnalysisLoadedBody(d, list);
      });
    }).catch(function(e){
      explainFetchFailure(e, "the Loaded panel").then(function(msg){ host.innerHTML = msg; });
    });
  }

  function loadedPickerHTML(list){
    var items = [{ v: "", l: (list.length === 0 ? "No snapshots saved yet" : "— choose a snapshot —") }]
      .concat(list.map(function(s){
        var d = new Date(s.saved_at * 1000);
        return { v: s.name, l: s.name + " (" + d.toLocaleString() + ")" };
      }));
    return '<div class="telpicker"><label>Snapshot: <select id="loadedsnap">' +
      telOptionsHTML(items, state.lsnap || "") + '</select></label></div>';
  }

  function loadedWirePicker(){
    var sel = document.getElementById("loadedsnap");
    if(sel) sel.addEventListener("change", function(){
      navigate({ tab: "analysis", atool: "loaded", lsnap: sel.value || null });
    });
  }

  function loadedUnavailableMessage(d){
    var reason = (d && d.reason) || "unknown";
    if(reason === "no map generated yet"){
      return "No map has been generated yet on this machine — run <code>:DocMap</code> first.";
    }
    if(reason === "no single root module prefix for this tree"){
      return "This tree has no single root module (opts.source resolves to several top-level " +
        "modules, or equals opts.lua_root) — there is no one prefix to snapshot.";
    }
    if(reason === "snapshot not found"){
      return "Snapshot <code>" + esc((d && d.snapshot) || "") + "</code> was not found — it may have " +
        "been evicted (only the most recent ones are kept).";
    }
    return "No loaded-snapshot data for prefix <code>" + esc((d && d.prefix) || "") + "</code> yet — " +
      "install/enable <code>runtime-analysis.nvim</code>, then <code>:RA loaded snapshot " +
      esc((d && d.prefix) || "&lt;prefix&gt;") + "</code> there.";
  }

  function renderAnalysisLoadedBody(d, list){
    var host = document.getElementById("anbody");
    var parts = [loadedPickerHTML(list || [])];

    if(!state.lsnap){
      parts.push('<p class="ntext none">Choose a snapshot above — this panel has nothing live to ' +
        'fall back to (see the panel\'s own note: a browser tab has no package.loaded of its own).</p>');
      host.innerHTML = parts.join("");
      loadedWirePicker();
      return;
    }
    if(!d || !d.available){
      parts.push('<p class="ntext none">' + loadedUnavailableMessage(d) + '</p>');
      host.innerHTML = parts.join("");
      loadedWirePicker();
      return;
    }

    var totalRows = (d.rows || []).length;
    var rows = anFilter((d.rows || []).map(function(r){
      var key = r.id + "#" + r.name;
      return {
        id: r.id, kind: r.kind, name: r.name, declared_name: r.declared_name,
        line: r.line, haystack: key, sortkey: key
      };
    }));

    var capturedAt = d.captured_at ? new Date(d.captured_at * 1000).toLocaleString() : "unknown time";
    if(totalRows === 0){
      parts.push('<p class="ntext none">Snapshot <code>' + esc(d.snapshot) + '</code> (captured ' +
        esc(capturedAt) + ') has data for prefix <code>' + esc(d.prefix) +
        '</code>, but nothing disagreed with the source.</p>');
      host.innerHTML = parts.join("");
      loadedWirePicker();
      return;
    }

    var cols = [
      { label: "Module", key: "id", get: function(r){ return r.id; }, initial: "asc" },
      { label: "Name", key: "name", get: function(r){ return r.name; }, initial: "asc" },
      { label: "Discrepancy", key: "kind", get: function(r){ return r.kind; }, initial: "asc" }
    ];
    anSort(rows, cols, function(a, b){
      if(a.id !== b.id) return a.id < b.id ? -1 : 1;
      return a.name < b.name ? -1 : 1;
    });

    parts.push('<p class="nsub">' + rows.length + ' discrepanc' + (rows.length === 1 ? 'y' : 'ies') +
      ' in snapshot <code>' + esc(d.snapshot) + '</code> (captured ' + esc(capturedAt) +
      ') for prefix <code>' + esc(d.prefix) + '</code>.' + anFilterNote(rows.length, totalRows) + '</p>');
    if(rows.length === 0){
      parts.push('<p class="ntext none">No function matches that filter.</p>');
      host.innerHTML = parts.join("");
      loadedWirePicker();
      return;
    }
    parts.push('<table class="antable">' + anHead(cols) + '<tbody>');
    rows.forEach(function(r){
      var label = r.kind === "declared_only"
        ? "✕ declared, not loaded" : "! loaded, not declared";
      parts.push('<tr class="anrow" data-node="' + esc(r.id) + '">' +
        '<td><code>' + esc(r.id) + '</code></td>' +
        '<td><code>' + esc(r.name) + '</code></td>' +
        '<td class="' + (r.kind === "declared_only" ? "teldown" : "telup") + '">' + label + '</td>' +
        '</tr>');
    });
    parts.push("</tbody></table>");
    host.innerHTML = parts.join("");
    host.querySelectorAll(".anrow").forEach(function(tr){
      tr.addEventListener("click", function(){
        navigate({ tab: "tree", id: tr.dataset.node });
      });
    });
    loadedWirePicker();
  }

  // =====================================================================
  // History tab: where each commit's diff radiates to.
  //
  // The only tab that is not computed from the embedded IR, and cannot be.
  // The analysis needs git and the *historical* artifacts, which means it
  // needs a server — a page opened as `file://` gets an opaque origin and
  // `fetch()` refuses the `file:` scheme outright, so "load it when clicked"
  // is only possible over http. `:DocMap serve` provides that.
  //
  // Opened from `file://` the tab must therefore explain itself rather than
  // fail: the committed map is the common case (it is what is in the repo),
  // and a tab that silently does nothing there would read as a bug. Same
  // treatment the class-based Hierarchy views give a map generated without
  // LuaLS.
  // =====================================================================
  var histLoaded = false, histCommits = null, histSelected = null;

  function historyAvailable(){ return location.protocol === "http:" || location.protocol === "https:"; }

  // Why a *served* page and a *published* one are not the same thing.
  //
  // `historyAvailable()` above tests the protocol, which answers "can this
  // page fetch at all" and nothing more. That was enough while the only two
  // cases were `file://` (cannot fetch) and `:DocMap serve` (a real docmap
  // server). Publishing the map to a static host adds a third: `https:`,
  // fetching works, and there is no server behind it. The four server-backed
  // panels then reported "Could not reach the map server — is it still
  // running? `:DocMap serve` starts it", which on a published page is advice
  // for a problem the reader does not have.
  //
  // Asked only on the failure path, so the normal case pays nothing: by the
  // time this runs a request has already failed, and one more tells the
  // reader which of the two situations they are in. `/api/ping` answers
  // `{"docmap":true}`; a static host answers its own 404, and any other
  // origin answers something that is not that.
  function explainFetchFailure(e, what){
    var detail = esc(String(e));
    return fetch("/api/ping", { cache: "no-store" })
      .then(function(r){ return r.ok ? r.json() : null; })
      .then(function(d){
        if(d && d.docmap === true){
          // A docmap server is there; this particular request still failed.
          return '<p class="hmsg">The map server is running, but ' + what +
            ' failed: ' + detail + '</p>';
        }
        return null;
      })
      .catch(function(){ return null; })
      .then(function(msg){
        if(msg) return msg;
        return '<p class="hmsg">This is a published copy of the map, so ' + what +
          ' has nothing to ask.<br><br>' + what.charAt(0).toUpperCase() + what.slice(1) +
          ' is computed on demand by a local server — it reads your working tree, your ' +
          'git history and your runtime data, none of which exist here.<br><br>' +
          'Run <code>:DocMap serve</code> in the repository and open the URL it prints.</p>';
      });
  }

  function histOffline(msg){
    document.getElementById("hist-list").innerHTML = "";
    document.getElementById("hist-detail").innerHTML = msg;
  }

  function drawHistory(sha){
    if(!historyAvailable()){
      histOffline(
        '<p class="hmsg">This page was opened from a file, so the History tab has nothing to ask.<br><br>' +
        'The commit analysis is computed on demand from <code>git</code> and the map committed at each ' +
        'revision — that needs a server, because a <code>file://</code> page is not allowed to fetch ' +
        'anything.<br><br>Run <code>:DocMap serve</code> and open the URL it prints ' +
        '(or <code>:DocMap open</code> while it runs).</p>'
      );
      return;
    }
    if(!histLoaded){
      histLoaded = true;
      document.getElementById("hist-list").innerHTML = '<p class="hmsg">Loading commits…</p>';
      fetch("/api/commits?n=100")
        .then(function(r){ return r.json(); })
        .then(function(d){
          histCommits = d.commits || [];
          renderHistList();
          if(state.sha) loadCommit(state.sha);
        })
        .catch(function(e){
          histLoaded = false;
          explainFetchFailure(e, "the History tab").then(histOffline);
        });
      return;
    }
    renderHistList();
    if(sha) loadCommit(sha);
  }

  function renderHistList(){
    var host = document.getElementById("hist-list");
    if(!histCommits || histCommits.length === 0){
      host.innerHTML = '<p class="hmsg">No commits.</p>';
      return;
    }
    host.innerHTML = histCommits.map(function(c){
      return '<div class="crow' + (c.sha === histSelected ? " sel" : "") +
        '" data-sha="' + esc(c.sha) + '">' +
        '<div class="csub">' + esc(c.subject) + "</div>" +
        '<div class="cmeta">' + esc(c.short) + " · " + esc(c.date) + " · " + esc(c.author) +
        "</div></div>";
    }).join("");
    host.querySelectorAll(".crow").forEach(function(row){
      row.addEventListener("click", function(){
        navigate({ tab: "history", sha: row.dataset.sha });
      });
    });
  }

  function loadCommit(sha){
    if(histSelected === sha && document.getElementById("hist-detail").dataset.sha === sha) return;
    histSelected = sha;
    renderHistList();
    var det = document.getElementById("hist-detail");
    det.innerHTML = '<p class="hmsg">Analysing ' + esc(sha.slice(0, 8)) + "…</p>";
    fetch("/api/commit/" + encodeURIComponent(sha))
      .then(function(r){ return r.json(); })
      .then(function(d){
        if(d.error){ det.innerHTML = '<p class="hmsg">' + esc(d.error) + "</p>"; return; }
        det.dataset.sha = sha;
        det.innerHTML = renderCommitDetail(d);
        wireCommitDetail(det);
      })
      .catch(function(e){
        explainFetchFailure(e, "the History tab").then(function(msg){ det.innerHTML = msg; });
      });
  }

  // Module chips link into the rest of the page like any other cross-
  // reference — but only when the node still exists in the *current* map. A
  // commit can name a module that has since been renamed or deleted, and a
  // link that navigates nowhere is worse than plain text saying so.
  function modChips(ids, names){
    if(!ids || ids.length === 0) return '<p class="ntext none">None.</p>';
    return '<div class="hist-mods">' + ids.map(function(id){
      var label = esc((names && names[id]) || id);
      return byId[id]
        ? '<a data-node="' + esc(id) + '">' + label + "</a>"
        : '<span class="gone" title="not in the current map">' + label + "</span>";
    }).join("") + "</div>";
  }

  function renderCommitDetail(d){
    var c = d.commit, im = d.impact, names = d.names || {};
    var out = [];

    out.push("<h2>" + esc(c.subject) + "</h2>");
    out.push('<div class="mp">' + esc(c.short) + " · " + esc(c.date) + " · " + esc(c.author) + "</div>");
    if(c.body) out.push('<div class="prose">' + esc(c.body) + "</div>");

    if(!d.has_map){
      out.push('<div class="hist-approx">This revision predates the committed map, so nothing ' +
        "could be attributed to functions — only the changed files are known.</div>");
    } else if(im.approximate){
      out.push('<div class="hist-approx">Function spans were <b>approximated</b> for at least one ' +
        "file: the map at this revision predates <code>line_end</code>, so a function's extent was " +
        "taken as \"up to the next one\". Attribution errs toward over-reaching into the gaps " +
        "between functions.</div>");
    }

    out.push('<div class="sec">Touched functions <span class="sub">' + im.touched.length + "</span></div>");
    if(im.touched.length === 0){
      out.push('<p class="ntext none">No scanned function contains any of the changed lines.</p>');
    } else {
      im.touched.forEach(function(t){
        var callers = (im.callers || {})[t.node + "#" + t.fn] || [];
        out.push('<div class="hist-fn">' + esc(t.signature || t.fn) +
          '  <span class="cmeta">' + esc(names[t.node] || t.node) + ":" + t.line + "</span></div>");
        if(callers.length === 0){
          out.push('<ul class="hist-callers"><li>no resolved caller in the tree</li></ul>');
        } else {
          out.push('<ul class="hist-callers">' + callers.map(function(x){
            return "<li>← " + esc(x.fn || "?") + "  (" + esc(names[x.node] || x.node) + ")</li>";
          }).join("") + "</ul>");
        }
      });
    }

    out.push('<div class="sec">Calling modules <span class="sub">precise — they hold a call site</span></div>');
    out.push(modChips(im.calling_modules, names));
    out.push('<div class="sec">Impacted modules <span class="sub">transitive, via required_by</span></div>');
    out.push(modChips(im.impacted_modules, names));

    if(im.unattributed && im.unattributed.length){
      out.push('<div class="sec">Changed, nothing to trace <span class="sub">' +
        im.unattributed.length + "</span></div>");
      out.push('<ul class="lst">' + im.unattributed.map(function(p){
        return "<li>" + esc(p) + "</li>";
      }).join("") + "</ul>");
    }

    out.push('<div class="sec">Diff <span class="sub">generated map excluded</span></div>');
    out.push('<div class="hist-diff">' + colorDiff(d.diff || "") + "</div>");
    return out.join("");
  }

  // Minimal diff colouring: enough to read, and done by line prefix rather
  // than by parsing, because the only thing that matters visually here is
  // added / removed / hunk header.
  function colorDiff(text){
    if(!text) return '<span class="dm">(empty)</span>';
    return text.split("\n").map(function(l){
      var cls = "";
      if(l.charAt(0) === "+") cls = "da";
      else if(l.charAt(0) === "-") cls = "dd";
      else if(l.slice(0, 2) === "@@") cls = "dh";
      else if(l.slice(0, 4) === "diff" || l.slice(0, 5) === "index") cls = "dm";
      return cls ? '<span class="' + cls + '">' + esc(l) + "</span>" : esc(l);
    }).join("\n");
  }

  function wireCommitDetail(det){
    det.querySelectorAll(".hist-mods a[data-node]").forEach(function(a){
      a.addEventListener("click", function(){
        navigate({ tab: "tree", id: a.dataset.node });
      });
    });
  }

  // `forceCenter`: used only by the search box's live-typing preview below,
  // which calls this directly rather than through navigate() (see that
  // handler's own comment for why) and so never goes through navigate()'s
  // own center-clears-hideroot logic. Without it, live-typing a match while
  // a root-hidden forest view was up would silently keep drawing the
  // forest — `state.hideroot` unchanged, the typed match completely
  // ignored — until Enter's real navigate({center}) finally cleared it.
  function drawHierarchy(centerId, view, forceCenter){
    view = VIEWS[view] ? view : "modules";
    hcenter = (centerId && byId[centerId]) ? centerId : (hcenter && byId[hcenter] ? hcenter : IR.root);
    var center = byId[hcenter];

    var oldNote = hgraphWrap.parentNode.querySelector(".htrunc");
    if(oldNote) oldNote.remove();
    drawLegend(view);

    var depth = state.depth === 0 ? 0 : (state.depth || 2);

    // A centered function only applies while the center is still its own
    // node. The search box re-centers live as you type without touching the
    // rest of the state, so without this the Calls view would keep drawing
    // the previously focused function and quietly ignore what was typed.
    var wantFn = (state.fn && fnByKey[state.fn] && fnByKey[state.fn].node.id === hcenter)
      ? state.fn : null;

    var hidingRoot = !forceCenter && view === "modules" && (state.hideroot || 0) > 0;

    var built;
    if(view === "types") built = layoutTypes(hcenter);
    else if(view === "inheritance") built = layoutInheritance(hcenter);
    else if(view === "deps") built = layoutDeps(hcenter, state.dir || "out", depth, !!state.ext);
    else if(view === "calls") built = layoutCalls(hcenter, wantFn, state.dir || "out", depth);
    else if(view === "modulecalls") built = layoutModuleCalls(hcenter, state.dir || "out", depth, !!state.ext);
    else if(hidingRoot) built = layoutModulesRooted(state.hideroot);
    else built = layoutModules(hcenter);

    if(built.count === 0){
      clearGraph();
      hpathEl.textContent = hidingRoot
        ? (state.hideroot + " root level" + (state.hideroot === 1 ? "" : "s") + " hidden")
        : (center.module || center.path);
      hgraph.style.width = ""; hgraph.style.height = "";
      hstage.style.width = ""; hstage.style.height = "";
      // Cleared, not just left behind: applyZoom() multiplies this by the
      // scale, so a stale extent would give an empty message a scroll area
      // thousands of pixels wide the moment the wheel is touched.
      stageExtent = { w: 0, h: 0 };
      // Into #hgraph, not #hstage: the stage is position:absolute (it carries
      // the zoom transform), so it contributes no height to its parent, and
      // #hgraph's explicit height was just cleared above — a message parented
      // to the stage therefore renders into a 0px-tall box and is clipped away
      // by #hgraph-wrap's overflow. Every empty state in this tab was
      // invisible for that reason; a normal-flow child of the relative #hgraph
      // gives it height on its own, with nothing measured off the DOM (which
      // would read 0 anyway while the pane is display:none).
      hgraph.insertAdjacentHTML("beforeend", emptyMessage(view, center));
      return;
    }

    var suffix = { types: " · types", inheritance: " · inheritance",
                   deps: " · deps", calls: " · calls",
                   modulecalls: " · module calls" }[view] || "";
    var focusFn = view === "calls" && wantFn;
    if(hidingRoot){
      hpathEl.textContent = state.hideroot + " root level" + (state.hideroot === 1 ? "" : "s") +
        " hidden — " + (built.layers[0] ? built.layers[0].length : 0) + " subtree" +
        ((built.layers[0] && built.layers[0].length === 1) ? "" : "s") + " shown";
    } else {
      hpathEl.textContent = (focusFn ? wantFn.split("#")[1] + "  in  " : "") +
        (center.module || center.path) + suffix +
        (isGraphView(view) ? "  ·  " + (state.dir || "out") + ", depth " + (depth === 0 ? "∞" : depth) : "");
    }

    // The empty branch above writes its explanation straight into #hgraph;
    // nothing else removes it, because reconcile() only ever adds and removes
    // boxes it knows about. Without this, going Calls-on-a-namespace (empty)
    // → Modules left "lib.nvim declares no functions." sitting above a
    // ninety-box diagram.
    var stale = hgraph.querySelector(".hmsg");
    if(stale) stale.remove();

    var laid = layerPositions(built.layers);
    var positions = laid.positions;

    // The key the view considers "the middle": a node id in three views, a
    // function id in Calls. Used for the highlight ring and the scroll
    // target, so both follow whatever the view is actually about.
      renderCrumb();
    var lrBtn = document.getElementById("hlr");
    if(lrBtn) lrBtn.classList.toggle("active", isLR());
  var centerKey = hcenter;
    if(view === "types") centerKey = built.layers[0] && built.layers[0][0];
    else if(view === "inheritance") centerKey = built.centerKey;
    else if(view === "calls") centerKey = wantFn || (built.layers[0] && built.layers[0][0]);
    // A forest has no single "middle" — every layer-0 box is equally a
    // root, so none of them gets the highlight ring a real center would.
    else if(hidingRoot) centerKey = null;

    var moved = reconcile(positions, view, centerKey);

    // The layer axis and the spread axis swap with the orientation; the
    // canvas has to swap with them or half the graph is outside it.
    var depth = built.layers.length;
    var alongLayers = PAD * 2 + depth * (isLR() ? BOX_W : BOX_H) +
      Math.max(0, depth - 1) * (isLR() ? GAP_X : GAP_Y);
    var totalW = isLR() ? alongLayers : laid.maxRowWidth + PAD * 2;
    var totalH = isLR() ? laid.maxRowWidth + PAD * 2 : alongLayers;

    var svgNS = "http://www.w3.org/2000/svg";
    var old = document.getElementById("hsvg");
    if(old) old.remove();
    var svg = document.createElementNS(svgNS, "svg");
    svg.id = "hsvg";
    svg.setAttribute("width", totalW);
    svg.setAttribute("height", totalH);
    svg.appendChild(buildDefs(svgNS));

    // Edge geometry cannot be interpolated the way a box position can — `d`
    // is not an animatable CSS property, and a per-frame path interpolator
    // for up to 90 edges buys very little over simply not drawing lines that
    // would be pointing at boxes still in motion. So: hidden while the boxes
    // move, faded in once they have arrived.
    // Both directions of a pair are separate edge objects (`pairKey` is
    // `from + " " + to`), so the reverse call count is a lookup away rather
    // than something to recompute. Built once per draw, not per hover.
    var weightByPair = {};
    built.edges.forEach(function(e){
      if(e.weight) weightByPair[e.from + " " + e.to] = e.weight;
    });

    var neighbours = {};
    built.edges.forEach(function(e){
      var a = positions[e.from], b = positions[e.to];
      if(!a || !b || e.from === e.to) return;
      var p = document.createElementNS(svgNS, "path");
      p.setAttribute("d", edgePath(a, b));
      p.setAttribute("class", e.cls);
      p.setAttribute("marker-end", "url(#m-" + (e.marker || "tree") + ")");
      // Weighted edges (Module Calls) get a thicker stroke for more calls —
      // log-scaled so one outlier pair doesn't flatten every other edge to a
      // hairline. Set via inline style, not a `stroke-width` attribute: the
      // `.hedge{stroke-width:1.5}` CSS rule would win over a presentation
      // attribute but not over an inline style.
      if(e.weight){
        p.style.strokeWidth = String(Math.min(1.5 + Math.log2(e.weight) * 1.1, 7));
      }
      p.dataset.from = e.from;
      p.dataset.to = e.to;
      if(e.label){
        var title = document.createElementNS(svgNS, "title");
        title.textContent = e.label;
        p.appendChild(title);
      }
      svg.appendChild(p);
      // The hover companion, added after its own edge so it sits on top and
      // wins the pointer. Only where there is something to read: an
      // unweighted tree edge has no count to show, and giving every edge a
      // 14px hit area would make the graph's own boxes harder to reach.
      if(e.weight){
        var hit = document.createElementNS(svgNS, "path");
        hit.setAttribute("d", edgePath(a, b));
        hit.setAttribute("class", "hedge-hit");
        edgeHover(hit, p, e, weightByPair);
        svg.appendChild(hit);
      }
      (neighbours[e.from] = neighbours[e.from] || {})[e.to] = true;
      (neighbours[e.to] = neighbours[e.to] || {})[e.from] = true;
    });

    hstage.style.width = totalW + "px";
    hstage.style.height = totalH + "px";
    hstage.insertBefore(svg, hstage.firstChild);
    stageExtent = { w: totalW, h: totalH };
    applyZoom();

    if(moved){
      svg.classList.add("settling");
      setTimeout(function(){ svg.classList.remove("settling"); }, ANIM_MS);
    }

    hgraphNeighbours = neighbours;

    // Rows are centered on the widest layer, so the centered box can sit
    // thousands of pixels from the left edge on a wide map — without this,
    // opening the tab scrolls to (0,0) and shows an arbitrary fragment of
    // whichever layer is widest, not the node the view is actually about.
    // After a zoom-driven jump the cursor is the anchor: re-centering the
    // view here would yank the diagram out from under the pointer the gesture
    // is still on. The flag is consumed once, so ordinary navigation keeps
    // its centering.
    var selfPos = (centerKey && !suppressAutoScroll) ? positions[centerKey] : null;
    if(suppressAutoScroll){ suppressAutoScroll = false; }
    if(selfPos){
      var targetLeft = Math.max(0, selfPos.x + BOX_W / 2 - hgraphWrap.clientWidth / 2);
      var targetTop = Math.max(0, selfPos.y - hgraphWrap.clientHeight / 2 + BOX_H);
      if(moved && !reducedMotion()){
        hgraphWrap.scrollTo({ left: targetLeft, top: targetTop, behavior: "smooth" });
      } else {
        hgraphWrap.scrollLeft = targetLeft;
        hgraphWrap.scrollTop = targetTop;
      }
      var centerEl = hboxes[centerKey];
      if(centerEl && !reducedMotion()){
        centerEl.classList.remove("pulse");
        void centerEl.offsetWidth;
        centerEl.classList.add("pulse");
      }
    }

    if(built.truncated){
      var note = document.createElement("div");
      note.className = "htrunc";
      note.textContent = "Showing the first " + MAX_HNODES + " boxes — narrow the depth, or double-click a box to re-center on a smaller neighbourhood.";
      hgraphWrap.parentNode.insertBefore(note, hgraphWrap.nextSibling);
    }
  }

  function reducedMotion(){
    return window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  }

  // =====================================================================
  // Zoom — two mechanisms that must stay separate in the code, or both end
  // up half-done:
  //
  //   geometric  the same diagram, larger. A CSS transform on #hstage.
  //              No relayout, no redraw, nothing in the URL — it is comfort,
  //              not state.
  //   semantic   past a threshold, a *different* excerpt: one level down into
  //              the module under the cursor, or one level up. That is
  //              exactly the navigate({center}) double-click already does.
  //
  // The geometric zoom is the feel between two levels; the semantic one is
  // the jump. Only the jump touches history — the same rule the search
  // preview had to learn, for the same reason.
  //
  // Positions stay analytic. The transform sits on a layer *above* the
  // computed pixel coordinates, so `positions`, reconcile() and the SVG paths
  // are all unaware a zoom exists.
  // =====================================================================
  var Z_MIN = 0.35, Z_MAX = 2.40;
  var DRILL_IN = 1.80, DRILL_OUT = 0.55;
  var AFTER_IN = 0.90, AFTER_OUT = 1.15;
  var COOLDOWN_MS = 260;
  var LOD_MIN = 0.65;

  var hzoom = 1;
  var stageExtent = { w: 0, h: 0 };
  var lastJump = 0;
  var suppressAutoScroll = false;
  var zoomLabel;

  function clampZoom(z){ return Math.min(Z_MAX, Math.max(Z_MIN, z)); }

  // #hgraph is sized to the scaled extent because a transform leaves layout
  // size alone; without this the scroll area would not grow on zoom-in and
  // half the diagram would be unreachable.
  function applyZoom(){
    hstage.style.transform = "scale(" + hzoom + ")";
    hgraph.style.width = Math.round(stageExtent.w * hzoom) + "px";
    hgraph.style.height = Math.round(stageExtent.h * hzoom) + "px";
    hstage.classList.toggle("lod-min", hzoom < LOD_MIN);
    if(zoomLabel) zoomLabel.textContent = Math.round(hzoom * 100) + "%";
  }

  // Keeps the graph point under the cursor fixed while scaling around it —
  // without this the diagram slides out from under the pointer and zooming
  // feels like it is fighting you.
  function zoomAt(clientX, clientY, factor){
    var r = hgraphWrap.getBoundingClientRect();
    var gx = (hgraphWrap.scrollLeft + clientX - r.left) / hzoom;
    var gy = (hgraphWrap.scrollTop + clientY - r.top) / hzoom;
    var before = hzoom;
    hzoom = clampZoom(hzoom * factor);
    if(hzoom === before) return false;
    applyZoom();
    hgraphWrap.scrollLeft = gx * hzoom - (clientX - r.left);
    hgraphWrap.scrollTop = gy * hzoom - (clientY - r.top);
    return true;
  }

  function setZoom(z){
    hzoom = clampZoom(z);
    applyZoom();
  }

  // The box under the cursor, or — when the pointer sits in empty space —
  // the nearest one, measured from `positions` rather than from the DOM, so
  // this keeps working at any scale and never triggers a layout read.
  function boxNear(clientX, clientY){
    var direct = boxOf(document.elementFromPoint(clientX, clientY));
    if(direct) return direct;

    var r = hgraphWrap.getBoundingClientRect();
    var gx = (hgraphWrap.scrollLeft + clientX - r.left) / hzoom;
    var gy = (hgraphWrap.scrollTop + clientY - r.top) / hzoom;
    var best = null, bestD = Infinity;
    Object.keys(hboxes).forEach(function(k){
      var el = hboxes[k];
      if(el.classList.contains("leaving")) return;
      var dx = parseFloat(el.style.left) + BOX_W / 2 - gx;
      var dy = parseFloat(el.style.top) + BOX_H / 2 - gy;
      var d = dx * dx + dy * dy;
      if(d < bestD){ bestD = d; best = el; }
    });
    return best;
  }

  // A jump that cannot happen — a leaf with no children, the root on the way
  // out, an external box that stands for nothing — pulses the box instead of
  // silently doing nothing, which reads as a bug. The zoom is deliberately
  // left where it is: on a leaf, zooming further in to read the box is a
  // reasonable thing to want, and crossing-based triggering means it will not
  // re-fire on every further notch.
  function refuseJump(box){
    if(box && !reducedMotion()){
      box.classList.remove("pulse");
      void box.offsetWidth;
      box.classList.add("pulse");
    }
  }

  // In Deps and Calls "one level deeper" is not defined — a require graph is
  // not a containment hierarchy. Depth is the axis that means "show more"
  // there, and it already exists as state and as a toolbar control, so the
  // threshold binds to it instead.
  function drill(dir, clientX, clientY){
    var now = Date.now();
    // One flick of the wheel must not fall three levels. Blocked by the
    // cooldown, the zoom is pulled back just inside the threshold so the next
    // notch crosses it again — left where it was, the gesture would have to
    // be wound all the way back before it could retry.
    if(now - lastJump < COOLDOWN_MS){
      setZoom(dir > 0 ? DRILL_IN - 0.02 : DRILL_OUT + 0.02);
      return;
    }

    if(isGraphView(state.view)){
      var d = state.depth === 0 ? 0 : (state.depth || 2);
      var next = dir > 0 ? (d === 0 ? 0 : d + 1) : (d <= 1 ? 1 : d - 1);
      if(next === d){ refuseJump(null); return; }
      lastJump = now;
      suppressAutoScroll = true;
      setZoom(dir > 0 ? AFTER_IN : AFTER_OUT);
      navigate({ depth: next });
      return;
    }

    if(dir > 0){
      var box = boxNear(clientX, clientY);
      var target = box && box._spec && box._spec.recenter;
      // Three refusals, all of which would otherwise reset the zoom for no
      // visible reason: nothing under the cursor, a leaf with no level below
      // it, and — the easy one to miss — the box that is *already* the
      // center, whose children are what the view is showing right now.
      if(!target || target === hcenter || !((byId[target] || {}).children || []).length){
        refuseJump(box);
        return;
      }
      lastJump = now;
      suppressAutoScroll = true;
      setZoom(AFTER_IN);
      navigate({ center: target, fn: null });
    } else {
      var parent = (byId[hcenter] || {}).parent;
      if(!parent){ refuseJump(null); return; }
      lastJump = now;
      suppressAutoScroll = true;
      setZoom(AFTER_OUT);
      navigate({ center: parent, fn: null });
    }
  }

  hgraphWrap.addEventListener("wheel", function(ev){
    // Shift keeps a way to pan horizontally, which is what the wheel would
    // otherwise have done here.
    if(ev.shiftKey){
      ev.preventDefault();
      hgraphWrap.scrollLeft += ev.deltaY;
      return;
    }
    ev.preventDefault();

    // Exponential so each notch feels the same at any scale, and so a
    // trackpad's small deltas do not crawl. ctrl+wheel is what a pinch
    // gesture arrives as, and it means the same thing here.
    var before = hzoom;
    var factor = Math.exp(-ev.deltaY * 0.0015);
    zoomAt(ev.clientX, ev.clientY, factor);

    // Fires on *crossing* the threshold, not on being past it. Two things
    // depend on that: a refused jump (a leaf, the root) leaves the zoom above
    // the line without re-firing on every further notch, and — the bug this
    // replaced — a zoom that came to rest above DRILL_IN no longer drills
    // *in* when the next notch is a zoom-*out*.
    if(before < DRILL_IN && hzoom >= DRILL_IN) drill(1, ev.clientX, ev.clientY);
    else if(before > DRILL_OUT && hzoom <= DRILL_OUT) drill(-1, ev.clientX, ev.clientY);
  }, { passive: false });

  // Keyboard equivalents, so the view is not mouse-only.
  document.addEventListener("keydown", function(ev){
    if(state.tab !== "hierarchy") return;
    if(ev.target && /^(INPUT|TEXTAREA)$/.test(ev.target.tagName)) return;
    if(ev.ctrlKey || ev.metaKey || ev.altKey) return;
    if(ev.key === "+" || ev.key === "="){ ev.preventDefault(); setZoom(hzoom * 1.2); }
    else if(ev.key === "-"){ ev.preventDefault(); setZoom(hzoom / 1.2); }
    else if(ev.key === "0"){ ev.preventDefault(); setZoom(1); }
  });

  // =====================================================================
  // Graph interaction. Delegated from #hgraph rather than bound per box:
  // reconcile() reuses boxes across redraws, and re-adding listeners on every
  // draw would stack duplicates on exactly the boxes that survive longest.
  // =====================================================================
  var hgraphNeighbours = {};

  function boxOf(target){
    var el = target;
    while(el && el !== hgraph){
      if(el.classList && el.classList.contains("hnode")) return el;
      el = el.parentNode;
    }
    return null;
  }

  // =====================================================================
  // Which click does what.
  //
  // **The default swapped on 2026-08-20**, deliberately. Before, a single
  // click left the Hierarchy for the Tree view and a double click recentred
  // — which meant the cheapest, most reflexive gesture did the one thing
  // that abandons the view you are working in, and the deliberate gesture
  // did the thing the view exists for. `WORKPLAN.md` §9.2 named it "the most
  // surprising thing in the view" and left the swap as an open decision
  // precisely because existing muscle memory is a real cost.
  //
  // So the swap ships with a way back rather than as a fait accompli. It now
  // follows the convention every file manager and tree widget uses: a single
  // click selects and stays, a double click commits and opens.
  //
  // The preference is stored **unscoped**, unlike marks and hidden boxes,
  // which key on `location.pathname`. Those are facts about one project's
  // map; this is a fact about the person's hands, and it would be absurd to
  // relearn the gesture per repository.
  var GESTURE_LS_KEY = "docmap:classic-clicks";
  var classicClicks = false;
  try { classicClicks = localStorage.getItem(GESTURE_LS_KEY) === "1"; } catch(e){ void 0; }

  function leaveForTree(box){
    // A tag_files-resolved external box has no node in *this* map — nothing
    // to navigate to here — but does have another project's own generated
    // page to open, in a new tab so the current map's state is not lost.
    if(box._spec.externalHtml){ window.open(box._spec.externalHtml, "_blank"); return; }
    // An unresolved external box has no node behind it at all — no id to
    // select, nothing to re-center on. Inert rather than navigating
    // somewhere arbitrary.
    if(!box._spec.nodeId) return;
    navigate({ tab: "tree", id: box._spec.nodeId });
  }

  function recentreOn(box){
    if(!box._spec.recenter) return;
    // In the Calls view a re-center lands on the function itself, which is
    // the whole point of the view; elsewhere there is no finer object than
    // the node.
    if(box._spec.fnKey) navigate({ center: box._spec.recenter, fn: box._spec.fnKey });
    else navigate({ center: box._spec.recenter, fn: null });
  }

  // What a click on a box actually does.
  //
  // **First click pins, second click acts** — added 2026-08-20, on top of the
  // gesture swap above. Hovering already lights a box and its direct
  // neighbours and dims everything else, and all of it vanished the moment
  // the pointer moved, so the highlighted subgraph could not be read, traced
  // or followed. Freezing it is what makes the view legible; the action is
  // one click further on.
  //
  // **A double click is that sequence, only fast**, which is why there is no
  // `dblclick` handler any more. The two `click` events a double click emits
  // already pin and then act, so a reader who knows where they are going
  // pays nothing for the pin and never sees it. A third handler on top would
  // have fired *in addition* to those two and acted twice.
  //
  // The `classicClicks` pill keeps its meaning unchanged: it decides what the
  // *second* click does — root the graph here, or open the module in Tree.
  function actOn(box){
    if(classicClicks){ leaveForTree(box); return; }
    // An external box has nothing in this map to recentre on, so it keeps
    // its old meaning under either setting rather than becoming inert.
    if(box._spec.externalHtml || !box._spec.recenter){ leaveForTree(box); return; }
    recentreOn(box);
  }

  hgraph.addEventListener("click", function(ev){
    var box = boxOf(ev.target);
    // A click on the graph's own background releases the pin. The gesture
    // everybody tries reflexively to drop a selection, so it should not need
    // discovering.
    if(!box || !box._spec){ unpin(); return; }
    var key = box.dataset.key;
    if(pinnedKey === key){ actOn(box); return; }
    // A different box re-pins there rather than releasing first. Without
    // that, following a chain — the one thing this exists for — would be the
    // most tedious way to use it.
    pin(key);
  });

  document.getElementById("hgest").addEventListener("click", function(){
    classicClicks = !classicClicks;
    try {
      if(classicClicks) localStorage.setItem(GESTURE_LS_KEY, "1");
      else localStorage.removeItem(GESTURE_LS_KEY);
    } catch(e){ void 0; }
    this.classList.toggle("active", classicClicks);
  });

  // Focus: dim everything that is not a direct neighbour of one box. Pure
  // class toggling — on a dense require graph this is the difference between
  // a readable diagram and a spider's web, and it costs no relayout.
  //
  // Driven by the pointer *or* by a pin, which is why it is a function of a
  // key rather than of an event.
  function focusOn(key){
    var near = hgraphNeighbours[key] || {};
    hgraph.classList.add("focusing");
    Object.keys(hboxes).forEach(function(k){
      hboxes[k].classList.toggle("near", k === key || near[k]);
      hboxes[k].classList.toggle("pinned", k === pinnedKey);
    });
    var svg = document.getElementById("hsvg");
    if(svg) svg.querySelectorAll(".hedge").forEach(function(p){
      p.classList.toggle("near", p.dataset.from === key || p.dataset.to === key);
    });
  }

  function clearFocus(){
    hgraph.classList.remove("focusing");
    Object.keys(hboxes).forEach(function(k){ hboxes[k].classList.remove("pinned"); });
  }

  // The pinned box, or null. Held here rather than in `state`: a pin is a
  // way of looking at the graph, not a place in it, so it never rides in the
  // URL and pressing Back does not undo one.
  var pinnedKey = null;

  function pin(key){
    pinnedKey = key;
    focusOn(key);
  }

  function unpin(){
    if(pinnedKey === null) return;
    pinnedKey = null;
    clearFocus();
  }

  hgraph.addEventListener("mouseover", function(ev){
    // A pin holds against the pointer — that is the entire point of it.
    // Hover behaves exactly as before whenever nothing is pinned.
    if(pinnedKey !== null) return;
    var box = boxOf(ev.target);
    // Moving off a box onto the graph's own background has to un-focus:
    // mouseleave only fires when the pointer leaves #hgraph entirely, so
    // without this the last box hovered stayed lit while the cursor sat in
    // empty space next to it.
    if(!box){ clearFocus(); return; }
    focusOn(box.dataset.key);
  });

  hgraph.addEventListener("mouseleave", function(){
    if(pinnedKey !== null) return;
    clearFocus();
  });

  // Escape releases, the same meaning it already carries for this page's
  // popups — a further place for one gesture rather than a new gesture.
  document.addEventListener("keydown", function(ev){
    if(ev.key === "Escape" && pinnedKey !== null){ unpin(); }
  });

  // =====================================================================
  // Graph toolbar. Direction and depth only apply to the directed views, so
  // their controls are hidden elsewhere rather than sitting there inert.
  // =====================================================================
  function syncGraphControls(s){
    document.querySelectorAll(".hview-btn").forEach(function(b){
      b.classList.toggle("active", b.dataset.view === (s.view || "modules"));
    });
    document.querySelectorAll(".hdir-btn").forEach(function(b){
      b.classList.toggle("active", b.dataset.dir === (s.dir || "out"));
    });
    document.querySelectorAll(".hdepth-btn").forEach(function(b){
      b.classList.toggle("active", parseInt(b.dataset.depth, 10) === (s.depth === 0 ? 0 : (s.depth || 2)));
    });
    var show = isGraphView(s.view) ? "" : "none";
    document.getElementById("hdir").style.display = show;
    document.getElementById("hdepth").style.display = show;
    // External requires/calls exist only in Deps and Module Calls; the
    // per-function Calls view has no equivalent, since a call into a module
    // the map never scanned leaves no resolvable name behind to draw.
    var hext = document.getElementById("hext");
    hext.style.display = (s.view === "deps" || s.view === "modulecalls") ? "" : "none";
    hext.classList.toggle("active", !!s.ext);

    // Not part of `state`: a gesture preference is the reader's, not the
    // map's, so it never rides in the URL hash and never goes through
    // `navigate`. Reflected here only so the pill agrees with what the
    // handlers will actually do.
    document.getElementById("hgest").classList.toggle("active", classicClicks);

    // Modules only — Deps/Calls/Module Calls/Types/Inheritance have no
    // directory root to peel layers off of.
    var slider = document.getElementById("hrootslider");
    slider.classList.toggle("on", (s.view || "modules") === "modules");
    var max = maxRootDepth();
    var val = Math.min(s.hideroot || 0, max);
    var range = document.getElementById("hrootrange");
    range.max = String(max);
    range.value = String(val);
    document.getElementById("hrootplus").disabled = val >= max;
    document.getElementById("hrootminus").disabled = val <= 0;
  }

  document.getElementById("hup").addEventListener("click", function(){
    // Hidden-root mode has no single center to walk up from — "Up" peels
    // back one hidden level instead, the same direction the slider's own
    // "-" end moves in.
    if(state.view === "modules" && (state.hideroot || 0) > 0){
      navigate({ hideroot: state.hideroot - 1 });
      return;
    }
    var center = byId[hcenter || IR.root];
    if(center && center.parent) navigate({ center: center.parent, fn: null });
  });
  document.getElementById("hroot").addEventListener("click", function(){
    navigate({ center: IR.root, fn: null, hideroot: 0 });
  });
  document.getElementById("hrootplus").addEventListener("click", function(){
    navigate({ hideroot: Math.min((state.hideroot || 0) + 1, maxRootDepth()) });
  });
  document.getElementById("hrootminus").addEventListener("click", function(){
    navigate({ hideroot: Math.max((state.hideroot || 0) - 1, 0) });
  });
  document.getElementById("hrootrange").addEventListener("input", function(ev){
    var n = parseInt(ev.target.value, 10);
    navigate({ hideroot: isNaN(n) ? 0 : n });
  });
  document.getElementById("hlr").addEventListener("click", function(){
    navigate({ hdir: isLR() ? null : "lr" });
  });

  document.querySelectorAll(".hview-btn").forEach(function(b){
    b.addEventListener("click", function(){ navigate({ view: b.dataset.view }); });
  });
  document.querySelectorAll(".anview-btn").forEach(function(b){
    b.addEventListener("click", function(){ navigate({ tab: "analysis", atool: b.dataset.atool }); });
  });
  document.querySelectorAll(".hdir-btn").forEach(function(b){
    b.addEventListener("click", function(){ navigate({ dir: b.dataset.dir }); });
  });
  document.querySelectorAll(".hdepth-btn").forEach(function(b){
    b.addEventListener("click", function(){ navigate({ depth: parseInt(b.dataset.depth, 10) }); });
  });
  document.getElementById("hext").addEventListener("click", function(){
    navigate({ ext: !state.ext });
  });

  // =====================================================================
  // SVG export
  //
  // The diagram on screen is half SVG (the edges) and half absolutely
  // positioned HTML (the boxes), which is the right trade for an interactive
  // page and useless as a file. Rather than wrapping the boxes in
  // <foreignObject> — which Inkscape and most converters do not render — the
  // export redraws them as plain <rect>/<text>, so the result opens anywhere.
  //
  // Colours are read back off the live DOM instead of being hardcoded, so the
  // exported file matches the theme it was exported from rather than always
  // being the light one.
  // =====================================================================
  /// The diagram as a standalone SVG string, or `null` when none is drawn.
  ///
  /// Split out from `exportSvg` so a host can ask for the bytes without a
  /// download happening: an embedded page's `<a download>` lands wherever
  /// the embedder decides, which is not a place anybody chose.
  function buildSvg(){
    // Only while the diagram is the thing on screen. `#hsvg` is hidden by
    // CSS on every other tab rather than removed, so without this check a
    // host asking from the Notes tab got the last hierarchy that happened
    // to be drawn — exported under the name "current view", which it was
    // not. Found by asking from Notes, not by reading this function.
    if(state.tab !== "hierarchy") return null;
    var svg = document.getElementById("hsvg");
    if(!svg) return null;
    var w = svg.getAttribute("width"), h = svg.getAttribute("height");
    var cs = getComputedStyle(document.body);
    var parts = ['<svg xmlns="http://www.w3.org/2000/svg" width="'+w+'" height="'+h+'" '+
      'viewBox="0 0 '+w+' '+h+'" font-family="monospace">'];
    parts.push('<rect width="100%" height="100%" fill="'+cs.backgroundColor+'"/>');

    // Markers first: the paths below reference them by id.
    parts.push('<defs>');
    ["tree","type","ext","dep","call"].forEach(function(name){
      var probe = document.querySelector("#m-" + name + " path");
      var fill = probe ? getComputedStyle(probe).fill : cs.color;
      parts.push('<marker id="x-'+name+'" viewBox="0 0 8 8" refX="7" refY="4" '+
        'markerWidth="7" markerHeight="7" orient="auto-start-reverse">'+
        '<path d="M0,0 L8,4 L0,8 z" fill="'+fill+'"/></marker>');
    });
    parts.push('</defs>');

    svg.querySelectorAll(".hedge").forEach(function(p){
      var st = getComputedStyle(p);
      var marker = (p.getAttribute("marker-end") || "").replace("url(#m-", "").replace(")", "");
      parts.push('<path d="'+esc(p.getAttribute("d"))+'" fill="none" stroke="'+st.stroke+'" '+
        'stroke-width="'+st.strokeWidth+'" stroke-dasharray="'+
        (st.strokeDasharray === "none" ? "" : st.strokeDasharray)+'" opacity="'+st.opacity+'" '+
        'marker-end="url(#x-'+marker+')"/>');
    });

    Object.keys(hboxes).forEach(function(key){
      var el = hboxes[key];
      if(el.classList.contains("leaving")) return;
      var x = parseFloat(el.style.left), y = parseFloat(el.style.top);
      var st = getComputedStyle(el);
      parts.push('<rect x="'+x+'" y="'+y+'" width="'+BOX_W+'" height="'+BOX_H+'" rx="7" '+
        'fill="'+st.backgroundColor+'" stroke="'+st.borderTopColor+'"/>');
      var nm = el.querySelector(".hnm"), sub = el.querySelector(".hsm, .hkind, .hline");
      if(nm){
        parts.push('<text x="'+(x+9)+'" y="'+(y+19)+'" font-size="11" font-weight="600" '+
          'fill="'+getComputedStyle(nm).color+'">'+esc(clip(nm.textContent, 22))+'</text>');
      }
      if(sub){
        parts.push('<text x="'+(x+9)+'" y="'+(y+35)+'" font-size="9.5" '+
          'fill="'+getComputedStyle(sub).color+'">'+esc(clip(sub.textContent, 26))+'</text>');
      }
    });

    parts.push('</svg>');
    return parts.join("\n");
  }

  /// The name this diagram would be saved under.
  function svgName(){
    return (state.view || "modules") + "-" +
      (hcenter || "map").replace(/[^\w.-]+/g, "_") + ".svg";
  }

  function exportSvg(){
    var text = buildSvg();
    if(!text) return;
    var blob = new Blob([text], { type: "image/svg+xml" });
    var a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = svgName();
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(function(){ URL.revokeObjectURL(a.href); }, 1000);
  }

  // SVG <text> does not wrap or ellipsize; the HTML boxes rely on CSS
  // overflow for that, so the export has to truncate itself.
  function clip(s, n){
    s = (s || "").trim();
    return s.length > n ? s.slice(0, n - 1) + "…" : s;
  }

  document.getElementById("hexport").addEventListener("click", exportSvg);

  // =====================================================================
  // The inbound channel — questions only
  //
  // This page has always spoken to a host and never listened. Opening that
  // direction is a change of security posture, so the shape is chosen to
  // give away as little of it as possible:
  //
  // **It answers questions about itself. It does not take instructions.**
  // There is no "go to this tab", no "run this", no "set this value" — a
  // host that wants the page somewhere navigates the frame's own URL, which
  // it already controls and which the page already validates on the way in.
  // What a host cannot do from outside is *read* a cross-origin document,
  // and that is exactly what the one verb below exists for.
  //
  // Consequences of that choice, stated so a later verb has to argue against
  // them rather than quietly break them:
  //
  //   * A malicious embedder gains nothing it did not have. Everything
  //     answerable here is already rendered on the page it embedded.
  //   * A fixed vocabulary, not a dispatch table keyed by whatever arrived.
  //     An unknown verb is answered with silence, not with an error echoing
  //     the input back.
  //   * Replies go to the asker's own origin, never to `"*"`. An `opener`
  //     that is not the embedder therefore learns nothing by listening.
  //
  // The theme deliberately does *not* come through here: `?theme=` is read
  // from the URL instead, because it has to apply before first paint and a
  // message cannot arrive that early.
  // =====================================================================
  window.addEventListener("message", function(ev){
    var msg = ev.data;
    if(!msg || typeof msg !== "object" || msg.source !== "docmap-host") return;

    var reply = null;
    if(msg.ask === "export-svg"){
      // `null` when no diagram is drawn — a real answer, and the one the
      // host needs in order to say "there is nothing to export" rather than
      // writing an empty file.
      var text = (typeof buildSvg === "function") ? buildSvg() : null;
      reply = text
        ? { ok: true, kind: "svg", name: svgName(), data: text }
        : { ok: false, reason: "no-diagram" };
    }else if(msg.ask === "counts"){
      // What the header shows, for a host that has a place to show it and
      // cannot read this document. Everything here is already on the page:
      // the three structural counts come from the artifact, the two
      // finding counts from `FIND`, which is why this needs no new payload
      // and cannot drift from the header beside it.
      var sev = { error: 0, warn: 0 };
      FIND.forEach(function(f){
        if(sev[f.severity] !== undefined) sev[f.severity]++;
      });
      var c = (IR.meta && IR.meta.counts) || {};
      reply = { ok: true, kind: "counts", modules: c.module || 0,
                namespaces: c.namespace || 0, files: c.file || 0,
                errors: sev.error, warnings: sev.warn };
    }
    // **There was a third question, `state`, and it was removed rather than
    // kept.** It answered with the same coarse context this page already
    // volunteers on every navigation, added on the reasoning that asking is
    // cheaper than waiting. A round later nothing had ever asked it — the
    // one host there is reads the volunteered message, because by the time
    // it has a reason to care the message has already arrived. A question
    // nobody asks is not free: it is a branch in a published channel that
    // every generated artifact carries and that any future change to
    // `state` has to keep answering correctly.
    if(!reply) return;

    reply.source = "docmap";
    reply.replyTo = msg.id;
    try {
      // `ev.origin` is `"null"` for a sandboxed or file: embedder, and
      // `postMessage` rejects that as a target — those hosts get no answer,
      // which is the correct outcome rather than a broadcast.
      if(ev.origin && ev.origin !== "null" && ev.source){
        ev.source.postMessage(reply, ev.origin);
      }
    } catch(e) { /* a host that went away mid-question is not an error here */ }
  });

  zoomLabel = document.getElementById("hzoomlabel");
  document.getElementById("hzoomreset").addEventListener("click", function(){ setZoom(1); });
  applyZoom();


  // =====================================================================
  // Search — one input, two behaviors depending on the active tab: filters
  // visible rows in the Tree tab (unchanged), re-centers the Hierarchy view
  // on the best-matching node as you type in the Hierarchy tab. Typing
  // updates live via a replaced (not pushed) history entry — five keystrokes
  // finding the same module should not become five Back-button stops — and
  // Enter commits the current match as a real, pushed navigation.
  // =====================================================================
  function findBestMatch(query){
    var q = query.toLowerCase().trim();
    if(!q) return null;
    var starts = null, contains = null;
    for(var i = 0; i < IR.nodes.length; i++){
      var n = IR.nodes[i];
      var name = (n.name || "").toLowerCase();
      var mod = (n.module || "").toLowerCase();
      if(name === q || mod === q) return n.id;
      if(!starts && (name.indexOf(q) === 0 || mod.indexOf(q) === 0)) starts = n.id;
      if(!contains && (name.indexOf(q) >= 0 || mod.indexOf(q) >= 0 || (n.summary||"").toLowerCase().indexOf(q) >= 0)) contains = n.id;
    }
    return starts || contains;
  }

  var q = document.getElementById("q");

  // One input, one contract *per tab* — not one matcher over the whole page.
  //
  // The tabs list genuinely different things (modules, aggregate rows,
  // commits, a flat alphabet), and a single matcher over all of them would be
  // vaguer than any of the four. What is shared is the placeholder, which has
  // to say what the current tab will match, and the fragment state, so a
  // filtered view is linkable.
  //
  // The two tabs that do nothing say so in the placeholder rather than
  // sitting there with a stale prompt — a box that invites typing and then
  // ignores it reads as broken, which is what this used to do on four tabs.
  var PLACEHOLDERS = {
    tree: "Filter modules, paths, descriptions…",
    hierarchy: "Jump to a module — Enter commits",
    analysis: "Filter this panel's rows…",
    notes: "Filter is not used on Notes",
    index: "Filter is not used on the Index",
    history: "Filter is not used on History"
  };
  var FILTERING_TABS = { tree: true, hierarchy: true, analysis: true };

  // The box's contents belong to the *active* tab, so they are reset when the
  // tab changes and left alone otherwise. Resetting on every applyState would
  // wipe a Tree filter the moment a row in it was clicked; never resetting
  // would carry an Analysis query into the Tree tab, where it sits in the box
  // looking applied while filtering nothing.
  var lastSearchTab = null;

  function syncSearchBox(s){
    q.placeholder = PLACEHOLDERS[s.tab] || PLACEHOLDERS.tree;
    q.disabled = !FILTERING_TABS[s.tab];

    if(s.tab !== lastSearchTab){
      // The Analysis filter lives in the URL, so a Back button or a shared
      // link has to put it back in the box. The Tree and Hierarchy filters
      // deliberately do not — both are transient views over rows that are all
      // still there, and persisting them would make a shared link arrive
      // pre-narrowed for no reason the recipient can see.
      q.value = (s.tab === "analysis") ? (s.q || "") : "";
      if(s.tab === "tree") showAllTreeRows();
      lastSearchTab = s.tab;
    } else if(s.tab === "analysis" && q.value !== (s.q || "")){
      // Same tab, but the state changed underneath the box — a popstate, or a
      // link followed within Analysis. Typing does not take this path: there
      // the box is already the source of the value.
      q.value = s.q || "";
    }
  }

  ///Undo the Tree tab's row hiding.
  function showAllTreeRows(){
    treeEl.querySelectorAll(".row").forEach(function(r){ r.style.display = ""; });
  }

  // =====================================================================
  // Language legend
  //
  // A map can hold more than one language since `opts.source` became a list,
  // and until now nothing on screen said which node was which. `n.language`
  // (schema 3) is the backend that read it.
  //
  // **Drawn only when there is more than one.** A legend over a single-
  // language tree is a row of permanent chrome restating what the repository
  // already is — and single-language is nearly every repository, so the
  // common case gets nothing at all. This is the same rule the keyword card
  // follows: depth where there is depth, silence where there is not.
  //
  // No per-row language badge either, for the same reason. The question
  // "which language is this node" is asked about a handful of nodes in a
  // polyglot tree and never in any other tree; a filter answers it without
  // putting a marker on all ninety of them.
  // =====================================================================
  // Two elements, one state. The Tree and the Hierarchy live in separate
  // view containers, so a single shared bar would either sit above every
  // tab (including the ones it means nothing for) or be absent from one of
  // the two. Two elements painted by one function keeps the filter itself
  // single -- switching tabs never changes what is filtered.
  var langBars = [document.getElementById("langbar"), document.getElementById("langbar-h")];
  var activeLangs = null; // null = no filter; otherwise a set of names

  function languageCounts(){
    var counts = {}, order = [];
    IR.nodes.forEach(function(n){
      if(!n.language) return;
      if(counts[n.language] === undefined){ counts[n.language] = 0; order.push(n.language); }
      counts[n.language]++;
    });
    order.sort(function(a, b){ return counts[b] - counts[a] || (a < b ? -1 : 1); });
    return { counts: counts, order: order };
  }

  // Does this node, or anything below it, belong to an active language?
  //
  // Ancestors have to survive the filter or the nodes it selects become
  // unreachable — a `src/util.js` whose parent `src` is hidden is a row with
  // no path to it. A namespace has no language of its own by construction
  // (see scan.lua), so without this it would always be filtered out.
  var langSubtree = {};
  function subtreeLanguages(id){
    if(langSubtree[id]) return langSubtree[id];
    var n = byId[id], set = {};
    if(!n) return set;
    langSubtree[id] = set; // set first: a cycle would otherwise recurse forever
    if(n.language) set[n.language] = true;
    (n.children || []).forEach(function(kid){
      var sub = subtreeLanguages(kid);
      for(var k in sub) set[k] = true;
    });
    return set;
  }

  function rowMatchesLanguage(r){
    if(!activeLangs) return true;
    // Function rows and the group header follow the module they sit under,
    // which the DOM already expresses: they have no id of their own.
    var id = r.dataset.id;
    if(!id) return true;
    var sub = subtreeLanguages(id);
    for(var k in sub) if(activeLangs[k]) return true;
    return false;
  }

  // One pass for both filters.
  //
  // The search box and the legend both decide row visibility through
  // `style.display`, and two independent handlers writing that property make
  // the second one to run silently undo the first. Deciding once, from both
  // inputs, is the only version that cannot drift.
  function applyTreeFilter(){
    var v = (q.value || "").toLowerCase().trim();
    treeEl.querySelectorAll(".row").forEach(function(r){
      var hit;
      if(r.dataset.fn){
        var entry = fnByKey[r.dataset.fn];
        hit = !v || !entry ||
          (entry.fn.signature + " " + (entry.fn.summary || "")).toLowerCase().indexOf(v) >= 0;
      } else if(r.classList.contains("fnhead")){
        hit = !v;
      } else {
        var n = byId[r.dataset.id];
        hit = !v || !n ||
          (n.name + " " + (n.module || "") + " " + (n.summary || "")).toLowerCase().indexOf(v) >= 0;
      }
      r.style.display = (hit && rowMatchesLanguage(r)) ? "" : "none";
    });
    if(v) treeEl.querySelectorAll(".kids").forEach(function(k){ k.classList.remove("hide"); });
  }

  // Which language a Hierarchy box belongs to, or `null` for "cannot say".
  //
  // `hboxes` keys are not all node ids — `boxSpec` resolves four kinds: a
  // node id, an `ext:<module>` box for something outside this map, a class
  // name (Types/Inheritance), and an `fnKey` (Calls). Only two of the four
  // can answer, and the other two are answered honestly rather than guessed:
  //
  //   * `ext:` is by definition not part of this map, so it has no language
  //     *here*, whatever it is written in.
  //   * A class name comes from LuaLS enrichment, which is Lua-only today —
  //     but saying "therefore Lua" would be inferring a fact from the
  //     limitations of a tool rather than from the tree.
  //
  // A box that cannot say is never filtered out. Hiding boxes on the strength
  // of a guess is how a graph starts lying about its own shape.
  function languagesOfBoxKey(key){
    if(key.indexOf("ext:") === 0) return null;
    if(byId[key]) return subtreeLanguages(key);
    var entry = fnByKey[key];
    if(entry && entry.node && entry.node.language){
      var one = {};
      one[entry.node.language] = true;
      return one;
    }
    return null;
  }

  // Dim, never remove.
  //
  // The Tree view hides filtered rows because a list with gaps is still a
  // list. A graph is not: taking boxes out re-flows every remaining one and
  // can disconnect the picture, so the reader loses the shape they were
  // looking at in order to ask a question about part of it. This is the same
  // reasoning — and deliberately the same opacity — as the right-click
  // hide/dim above, kept on its own class so the two never fight over one:
  // a box the reader dimmed by hand must stay dimmed when the language
  // filter clears, and vice versa.
  function syncLangFilter(){
    Object.keys(hboxes).forEach(function(key){
      var off = false;
      if(activeLangs){
        var langs = languagesOfBoxKey(key);
        if(langs){
          off = true;
          for(var k in langs){ if(activeLangs[k]){ off = false; break; } }
        }
      }
      hboxes[key].classList.toggle("langoff", off);
    });
  }

  function renderLangBar(){
    var info = languageCounts();
    if(info.order.length < 2){
      langBars.forEach(function(bar){ if(bar) bar.hidden = true; });
      return;
    }

    var h = ['<span class="lb-label">Languages</span>'];
    info.order.forEach(function(name){
      var on = !activeLangs || activeLangs[name];
      h.push('<button type="button" class="lb-chip' + (on ? " on" : "") +
        '" data-lang="' + esc(name) + '" aria-pressed="' + (on ? "true" : "false") + '">' +
        esc(name) + '<span class="lb-n">' + info.counts[name] + '</span></button>');
    });
    if(activeLangs){
      h.push('<button type="button" class="lb-clear" data-lang-clear="1">show all</button>');
    }
    langBars.forEach(function(bar){
      if(!bar) return;
      bar.innerHTML = h.join("");
      bar.hidden = false;
    });
  }

  langBars.forEach(function(bar){ if(bar) bar.addEventListener("click", onLangBarClick); });

  function onLangBarClick(ev){
    var clear = ev.target.closest && ev.target.closest("[data-lang-clear]");
    if(clear){ activeLangs = null; renderLangBar(); applyLangFilter(); return; }
    var chip = ev.target.closest && ev.target.closest("[data-lang]");
    if(!chip) return;
    var name = chip.dataset.lang;
    // First click on an unfiltered bar selects *only* that language rather
    // than deselecting it. "Show me the TypeScript" is the thing a reader
    // wants from a legend; "show me everything except TypeScript" is not,
    // and starting from all-on makes the first click do the useless one.
    if(!activeLangs){
      activeLangs = {};
      activeLangs[name] = true;
    } else if(activeLangs[name]){
      delete activeLangs[name];
      // Emptied by unticking the last one: that is "show nothing", which is
      // never what was meant, so it means "show all" instead.
      var any = false;
      for(var k in activeLangs){ any = true; break; }
      if(!any) activeLangs = null;
    } else {
      activeLangs[name] = true;
    }
    renderLangBar();
    applyLangFilter();
  }

  ///Both surfaces the filter reaches, in one call, so a chip click cannot
  ///update one and leave the other showing a stale selection.
  function applyLangFilter(){
    applyTreeFilter();
    syncLangFilter();
  }

  // Drawn at load, not on first interaction: the legend's whole job is to
  // tell a reader the map holds more than one language before they wonder.
  renderLangBar();

  // =====================================================================
  // Copy link
  //
  // The whole page state already lives in the URL fragment -- that is what
  // `:DocMap graph` and `gO` exploit, and what every `navigate()` call
  // maintains. What was missing is any way for a reader to *get* it: the
  // address bar shows it, but a map opened from a file:// path or inside an
  // iframe (docmap-desktop) has no address bar to select from.
  //
  // Reads `location.href` rather than rebuilding the URL from `state`: the
  // hash is written by `applyState` on every navigation, so the address is
  // already correct by construction, and a second serializer here would be a
  // second answer to "what is this view called" that could drift from the
  // first.
  // =====================================================================
  var copyBtn = document.getElementById("copylink");
  var copyTimer = null;

  function flashCopy(text){
    if(copyTimer) clearTimeout(copyTimer);
    copyBtn.textContent = text;
    copyTimer = setTimeout(function(){ copyBtn.textContent = "Copy link"; copyTimer = null; }, 1400);
  }

  copyBtn.addEventListener("click", function(){
    var url = location.href;
    // `navigator.clipboard` is unavailable on an insecure origin, which
    // includes the `file://` case this page is most often opened as. The
    // fallback is the old `execCommand` route, and if even that fails the
    // reader is told rather than left looking at a button that did nothing.
    var done = function(){ flashCopy("Copied"); };
    var failed = function(){
      try {
        var ta = document.createElement("textarea");
        ta.value = url;
        ta.setAttribute("readonly", "");
        ta.style.position = "fixed";
        ta.style.opacity = "0";
        document.body.appendChild(ta);
        ta.select();
        var okExec = document.execCommand && document.execCommand("copy");
        document.body.removeChild(ta);
        flashCopy(okExec ? "Copied" : "Press Ctrl+C");
      } catch(e){
        flashCopy("Press Ctrl+C");
      }
    };
    if(navigator.clipboard && navigator.clipboard.writeText){
      navigator.clipboard.writeText(url).then(done, failed);
    } else {
      failed();
    }
  });

  q.addEventListener("input", function(){
    var v = this.value.toLowerCase().trim();

    if(state.tab === "analysis"){
      // Replaces rather than pushes, for the same reason the Hierarchy
      // preview does not push: five keystrokes narrowing to one module should
      // not become five Back-button stops. Unlike Hierarchy this *does* go
      // through navigate(), because the result is a re-render from state and
      // there is no separate draw path to call.
      navigate({ q: v || null }, { push: false });
      return;
    }

    if(state.tab === "hierarchy"){
      // Live preview only — draws directly, deliberately bypassing
      // navigate()/history entirely rather than replacing on every
      // keystroke. An earlier version used navigate(patch, {push:false}),
      // which calls history.replaceState on the *current top entry* — right
      // after switching to the Hierarchy tab, that entry is the tab-switch
      // itself, so the first keystroke overwrote it. Enter's subsequent
      // pushState then pushed a duplicate of that already-overwritten entry
      // instead of a distinct new stop, so Back from the committed search
      // landed on an indistinguishable copy of itself instead of the
      // pre-search tab state. Not writing to history at all while typing
      // avoids the clobber; drawHierarchy still keeps its own `hcenter`
      // current, so Up/Root/double-click after a preview (without ever
      // pressing Enter) act on what's actually on screen.
      var match = findBestMatch(this.value);
      // forceCenter: a typed match always wins over a root-hidden forest
      // view, the same way Enter's real navigate({center}) would clear
      // hideroot — see drawHierarchy's own note on why this path needs it
      // spelled out explicitly instead of getting it for free.
      if(match) drawHierarchy(match, state.view, true);
      return;
    }
    // Three row shapes share this list -- node rows, function rows (which
    // match on their own signature, not their module's summary) and the
    // function-group header, which has no data at all -- and the language
    // legend filters the same rows. `applyTreeFilter` owns all of it, so the
    // two inputs cannot take turns undoing each other's `display`.
    applyTreeFilter();
  });
  q.addEventListener("keydown", function(ev){
    if(ev.key === "Enter" && state.tab === "hierarchy"){
      var match = findBestMatch(this.value);
      if(match) navigate({ center: match });
    }
  });

  // =====================================================================
  // Context menu
  //
  // Every clickable object in the page — a tree row, a function row, a graph
  // box, a type or function entry in the detail pane — resolves through one
  // describeTarget() into { kind, nodeId, fnKey, className, label }, and the
  // menu is built from that. One resolver instead of four menus is what keeps
  // "right-click anything, get the same verbs" true as views are added.
  //
  // preventDefault only fires when the target actually resolves: selecting a
  // paragraph of documentation and reaching for the browser's own Copy has to
  // keep working, so unrecognised targets are left entirely alone.
  // =====================================================================
  var ctx = document.getElementById("ctx");
  var ctxItems = [];
  var ctxHi = -1;

  function describeTarget(el){
    while(el && el !== document.body){
      if(el.dataset){
        if(el.classList.contains("hnode") && el._spec){
          // `hkey` is the box's own key into `hboxes`/`state.hidden` — the
          // only place this is available, since a tree row or detail-pane
          // reference (the branches below) has no Hierarchy box behind it to
          // dim. `buildMenu` gates the hide/dim entry on this field alone.
          return { kind: el._spec.fnKey ? "function" : (classByName[el.dataset.key] ? "class" : "node"),
                   nodeId: el._spec.nodeId, fnKey: el._spec.fnKey,
                   className: classByName[el.dataset.key] ? el.dataset.key : null,
                   label: el.dataset.key, hkey: el.dataset.key };
        }
        if(el.dataset.fn && fnByKey[el.dataset.fn]){
          var e = fnByKey[el.dataset.fn];
          return { kind: "function", nodeId: e.node.id, fnKey: el.dataset.fn, label: e.fn.signature };
        }
        if(el.dataset.id && byId[el.dataset.id]){
          var n = byId[el.dataset.id];
          return { kind: "node", nodeId: n.id, label: n.module || n.path };
        }
      }
      el = el.parentNode;
    }
    return null;
  }

  function ctxClose(){ ctx.classList.remove("open"); ctxItems = []; ctxHi = -1; }

  function buildMenu(t){
    var n = byId[t.nodeId];
    var items = [];
    var fnEntry = t.fnKey ? fnByKey[t.fnKey] : null;

    items.push({ label: "Show in tree", run: function(){ navigate({ tab: "tree", id: t.nodeId }); } });
    items.push({ sep: true });

    items.push({ label: "Hierarchy", hint: "structure",
      run: function(){ navigate({ tab: "hierarchy", view: "modules", center: t.nodeId, fn: null }); } });

    var hasDeps = ((n.requires || []).length + (n.required_by || []).length) > 0;
    items.push({ label: "Dependencies — needs", hint: (n.requires || []).length || "0",
      disabled: !(n.requires || []).length,
      run: function(){ navigate({ tab: "hierarchy", view: "deps", center: t.nodeId, dir: "out", fn: null }); } });
    items.push({ label: "Dependencies — needed by", hint: (n.required_by || []).length || "0",
      disabled: !(n.required_by || []).length,
      run: function(){ navigate({ tab: "hierarchy", view: "deps", center: t.nodeId, dir: "in", fn: null }); } });
    items.push({ label: "Dependencies — both ways", disabled: !hasDeps,
      run: function(){ navigate({ tab: "hierarchy", view: "deps", center: t.nodeId, dir: "both", fn: null }); } });

    // Counts come from the same adjacency the view walks, so a menu entry is
    // only offered when it leads somewhere — an enabled item that opens an
    // empty diagram teaches people to distrust the menu.
    var outN = fnEntry ? (callOut[t.fnKey] || []).length
      : (n.functions || []).reduce(function(a, f){ return a + (callOut[fnKey(n.id, f.name)] || []).length; }, 0);
    var inN = fnEntry ? (callIn[t.fnKey] || []).length
      : (n.functions || []).reduce(function(a, f){ return a + (callIn[fnKey(n.id, f.name)] || []).length; }, 0);

    items.push({ sep: true });
    items.push({ label: fnEntry ? "Calls — callees" : "Calls — what it calls", hint: outN || "0",
      disabled: !outN,
      run: function(){ navigate({ tab: "hierarchy", view: "calls", center: t.nodeId, fn: t.fnKey || null, dir: "out" }); } });
    items.push({ label: fnEntry ? "Calls — callers" : "Calls — what calls it", hint: inN || "0",
      disabled: !inN,
      run: function(){ navigate({ tab: "hierarchy", view: "calls", center: t.nodeId, fn: t.fnKey || null, dir: "in" }); } });
    items.push({ label: "Calls — both ways", disabled: !(outN || inN),
      run: function(){ navigate({ tab: "hierarchy", view: "calls", center: t.nodeId, fn: t.fnKey || null, dir: "both" }); } });

    items.push({ label: "Types", disabled: !(n.types_detail || []).length,
      run: function(){ navigate({ tab: "hierarchy", view: "types", center: t.nodeId, fn: null }); } });

    // Enabled only when this node actually owns a class that inherits or is
    // inherited from — the view would otherwise open on its own empty state,
    // and "greyed out with a reason" beats "opens and says nothing here".
    var inhN = (n.types_detail || []).filter(function(ty){ return inInheritance[ty.name]; }).length;
    items.push({ label: "Inheritance", hint: inhN || "0", disabled: !inhN,
      run: function(){ navigate({ tab: "hierarchy", view: "inheritance", center: t.nodeId, fn: null }); } });

    items.push({ sep: true });
    if(n.source){
      var u = srcUrl(n.source);
      var frag = fnEntry ? "#L" + fnEntry.fn.line : "";
      items.push({ label: u ? "Open source ↗" : "Open source",
        run: function(){ window.open(u ? u + frag : rel(n.source), u ? "_blank" : "_self"); } });
      // Open it in an editor — only when something is embedding this page.
      // A browser cannot start an editor, so in a plain tab this item would
      // be a menu entry that does nothing, which is worse than an absent
      // one. `window.parent !== window` is the whole test: a host that
      // embeds this is a host that can be told, and one that ignores the
      // message leaves the item doing what it appears to do — nothing —
      // rather than lying about it.
      if(window.parent !== window){
        items.push({ label: "Open in editor", run: function(){
          try {
            window.parent.postMessage({
              source: "docmap", kind: "open-file",
              path: n.source,
              line: fnEntry ? fnEntry.fn.line : null
            }, "*");
          } catch(e){ /* no host, same as no item */ }
        } });
      }
    }
    if(n.readme){
      items.push({ label: "Open README", run: function(){ window.open(rel(n.readme), "_self"); } });
    }

    // Only offered when the menu was opened on an actual Hierarchy box
    // (`t.hkey`, set by describeTarget only in that branch) — right-clicking
    // this same node's tree row or a reference in a detail pane has nothing
    // to dim, since neither one has a box on screen.
    if(t.hkey){
      items.push({ sep: true });
      items.push({
        label: isHidden(t.hkey) ? "Show this box" : "Dim this box",
        hint: "hierarchy",
        run: function(){ toggleHidden(t.hkey); }
      });
    }

    items.push({ sep: true });
    items.push({ label: "Copy module path", run: function(){ copy(n.module || n.path); } });
    items.push({ label: "Copy link to this view", run: function(){
      copy(location.origin + location.pathname + serializeState(state));
    } });

    return items;
  }

  // clipboard.writeText is unavailable on a file:// page in some browsers,
  // which is exactly how this artifact is most often opened. The textarea
  // fallback is not legacy cruft here, it is the primary path.
  function copy(text){
    if(navigator.clipboard && window.isSecureContext){
      navigator.clipboard.writeText(text);
      return;
    }
    var ta = document.createElement("textarea");
    ta.value = text;
    ta.style.position = "fixed";
    ta.style.opacity = "0";
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand("copy"); } catch(e) {}
    document.body.removeChild(ta);
  }

  function openMenu(x, y, t){
    var items = buildMenu(t);
    var html = ['<div class="hdr">' + esc(t.label || "") + '</div>'];
    items.forEach(function(it, i){
      if(it.sep){ html.push('<div class="sep"></div>'); return; }
      html.push('<div class="ci' + (it.disabled ? " disabled" : "") + '" data-i="' + i + '">' +
        esc(it.label) + (it.hint !== undefined ? '<span class="hint">' + esc(String(it.hint)) + '</span>' : '') +
        '</div>');
    });
    ctx.innerHTML = html.join("");
    ctxItems = items;
    ctxHi = -1;
    ctx.classList.add("open");

    // Positioned after the menu is measurable, clamped so a right-click near
    // the bottom or right edge does not open a menu that runs off-screen.
    var r = ctx.getBoundingClientRect();
    ctx.style.left = Math.min(x, window.innerWidth - r.width - 8) + "px";
    ctx.style.top = Math.min(y, window.innerHeight - r.height - 8) + "px";

    ctx.querySelectorAll(".ci").forEach(function(el){
      el.addEventListener("click", function(){
        var it = ctxItems[parseInt(el.dataset.i, 10)];
        if(!it || it.disabled) return;
        ctxClose();
        it.run();
      });
    });
  }

  document.addEventListener("contextmenu", function(ev){
    var t = describeTarget(ev.target);
    if(!t || !byId[t.nodeId]) return;
    ev.preventDefault();
    openMenu(ev.clientX, ev.clientY, t);
  });

  document.addEventListener("click", function(ev){
    if(ctx.classList.contains("open") && !ctx.contains(ev.target)) ctxClose();
  });
  window.addEventListener("blur", ctxClose);
  window.addEventListener("resize", ctxClose);
  document.addEventListener("scroll", ctxClose, true);

  document.addEventListener("keydown", function(ev){
    if(!ctx.classList.contains("open")) return;
    if(ev.key === "Escape"){ ctxClose(); return; }
    if(ev.key !== "ArrowDown" && ev.key !== "ArrowUp" && ev.key !== "Enter") return;
    ev.preventDefault();
    var els = Array.prototype.slice.call(ctx.querySelectorAll(".ci:not(.disabled)"));
    if(!els.length) return;
    if(ev.key === "Enter"){
      if(ctxHi >= 0) els[ctxHi].click();
      return;
    }
    els.forEach(function(e){ e.classList.remove("hi"); });
    ctxHi = ev.key === "ArrowDown"
      ? (ctxHi + 1) % els.length
      : (ctxHi <= 0 ? els.length - 1 : ctxHi - 1);
    els[ctxHi].classList.add("hi");
  });


  // =====================================================================
  // Keyword card
  //
  // A second floating layer, which the governing rule for this feature
  // ("one card component, one card at a time") would normally forbid — and
  // the exception is structural rather than a concession. A snippet is
  // rendered *inside* the annotation popup, so a keyword trigger lives
  // inside the very card that would otherwise have to display its answer;
  // reusing `sigpop` would mean a keyword hover destroying the function
  // card the reader opened to look at. Two layers is what the nesting
  // actually is.
  //
  // What the rule still buys, and what is kept: the same visual component
  // (`.sigpop` styling), the same positioning and flip logic, the same
  // dismissal rules. Only the content and the nesting differ.
  //
  // Opens on a dwell, never on hover-through: a card that appears while the
  // pointer merely crosses a word is chrome nobody asked for, and a snippet
  // is full of words a pointer crosses on the way somewhere else.
  // =====================================================================
  var kwpop = document.getElementById("kwpop");
  var kwAnchor = null, kwOpenTimer = null, kwCloseTimer = null;
  var KW_DWELL = 260;

  function kwClearTimers(){
    if(kwOpenTimer){ clearTimeout(kwOpenTimer); kwOpenTimer = null; }
    if(kwCloseTimer){ clearTimeout(kwCloseTimer); kwCloseTimer = null; }
  }

  function kwClose(){
    kwClearTimers();
    kwpop.classList.remove("on");
    kwAnchor = null;
  }

  // Positioned exactly like the annotation popup, including the flip: a card
  // pinned below the viewport edge would cover the line the reader is
  // pointing at. Extracted when the tag card became a second caller -- two
  // copies of a flip rule is two chances to flip one of them the wrong way.
  function kwPlace(el){
    var a = el.getBoundingClientRect();
    var r = kwpop.getBoundingClientRect();
    kwpop.style.left = Math.max(8, Math.min(a.left, window.innerWidth - r.width - 8)) + "px";
    kwpop.style.top = ((a.bottom + r.height + 8 <= window.innerHeight)
      ? a.bottom + 6
      : Math.max(8, a.top - r.height - 6)) + "px";
  }

  // The tag catalogue as a lookup table, built once. Keyed by name without
  // the `@`, which is how the badges and the parser both spell it.
  var tagByName = null;
  function tagEntry(name){
    if(tagByName === null){
      tagByName = {};
      (IR.tags || []).forEach(function(t){ tagByName[t.name] = t; });
    }
    return Object.prototype.hasOwnProperty.call(tagByName, name) ? tagByName[name] : null;
  }

  function kwOpen(el){
    // The third kind. Unlike keywords and stdlib names it has no snippet
    // behind it and therefore no per-language glossary: an annotation means
    // the same thing wherever it is written, which is exactly why the
    // catalogue is one table and the glossaries are one per language.
    if(el.dataset.kwkind === "tag"){
      var tag = tagEntry(el.dataset.kw);
      if(!tag) return;
      var th = '<div class="kw-word">@' + esc(tag.name) + '</div>' +
        '<div class="kw-sum">' + prose(tag.summary) + '</div>' +
        '<div class="kw-origin">' + (tag.origin === "luals"
          ? "LuaCATS annotation" : "this project's own convention") + '</div>';
      // Only where the origin publishes one. A LuaLS link for `@todo` would
      // load, look authoritative and not contain the answer -- the same rule
      // that withholds the Lua-manual link from `vim.*` below.
      if(tag.url){
        th += '<div class="kw-ref"><a href="' + esc(tag.url) +
          '" target="_blank" rel="noreferrer noopener">LuaLS reference &#8599;</a></div>';
      }
      kwAnchor = el;
      kwpop.innerHTML = th;
      kwpop.classList.add("on");
      kwPlace(el);
      return;
    }

    var snip = el.closest && el.closest(".fn-snip");
    var gl = glossaryForPath(snip && snip.dataset.path);
    var table = el.dataset.kwkind === "std" ? (gl && gl.stdlib) : (gl && gl.keywords);
    var entry = table && Object.prototype.hasOwnProperty.call(table, el.dataset.kw)
      ? table[el.dataset.kw]
      : null;
    // Nothing behind the trigger is a bug in whatever decorated it, not
    // something to show an empty card for.
    if(!entry) return;

    var h = '<div class="kw-word">' + esc(el.dataset.kw) + '</div>' +
      '<div class="kw-sum">' + prose(entry.summary) + '</div>';
    if(entry.note) h += '<div class="kw-note">' + esc(entry.note) + '</div>';
    // Where the name comes from, when it is not the language itself. The
    // distinction is the whole reason `vim.*` entries can sit in a Lua
    // glossary without pretending to be Lua: a reader is told the difference
    // rather than left to infer it.
    if(entry.origin) h += '<div class="kw-origin">' + esc(entry.origin) + '</div>';
    // Only for entries that *are* the language. A `vim.*` name is not in the
    // Lua manual, and sending a reader there would be a link that looks
    // right and answers nothing.
    if(!entry.origin && gl.reference && gl.reference.url){
      // The one link, per language, that this feature is allowed to depend
      // on nothing for: every sentence above it is already the answer. See
      // `docs/ROADMAP/IDEAS/ReferenceTab.md` on why there is one base URL
      // rather than one URL per keyword.
      h += '<div class="kw-ref"><a href="' + esc(gl.reference.url + (entry.anchor || "")) +
        '" target="_blank" rel="noreferrer noopener">' + esc(gl.reference.label) + ' &#8599;</a></div>';
    }

    kwAnchor = el;
    kwpop.innerHTML = h;
    kwpop.classList.add("on");
    kwPlace(el);
  }

  document.addEventListener("mouseover", function(ev){
    var el = ev.target.closest && ev.target.closest("[data-kw]");
    if(el){
      kwClearTimers();
      if(el !== kwAnchor) kwOpenTimer = setTimeout(function(){ kwOpen(el); }, KW_DWELL);
      return;
    }
    if(!kwAnchor && !kwOpenTimer) return;
    // Same grace period on the way out as the annotation popup, and for the
    // same reason: the pointer has to be able to travel into the card to
    // reach the reference link.
    if(ev.target.closest && ev.target.closest("#kwpop")){ kwClearTimers(); return; }
    kwClearTimers();
    kwCloseTimer = setTimeout(kwClose, 180);
  });

  // Keyboard parity. The spans are focusable, so a reader who never touches
  // a pointer still reaches every explanation -- the same reason `.sigi`
  // above is kept at full opacity while focused.
  document.addEventListener("focusin", function(ev){
    var el = ev.target.closest && ev.target.closest("[data-kw]");
    if(el){ kwClearTimers(); kwOpen(el); }
    else if(!(ev.target.closest && ev.target.closest("#kwpop"))) kwClose();
  });

  document.addEventListener("keydown", function(ev){ if(ev.key === "Escape") kwClose(); });
  // Same exemption as the annotation popup below: the keyword card is short
  // today, but it lives *inside* that card, so a scroll gesture aimed at the
  // snippet behind it must not take it down either.
  window.addEventListener("scroll", function(ev){
    if(ev.target && ev.target.nodeType === 1 && ev.target.closest &&
       (ev.target.closest("#kwpop") || ev.target.closest("#sigpop"))) return;
    kwClose();
  }, true);
  window.addEventListener("resize", kwClose);

  // =====================================================================
  // Annotation popup
  //
  // Every list in this map — Index, Notes, Complexity, Hooks, Duplicates —
  // shows a function as its signature and nothing else. The params, returns,
  // deprecation and prose were all parsed and are all already in this page;
  // they were simply one navigation away, in the Tree tab's detail pane.
  // This surfaces them where the reader already is.
  //
  // No new data: `fnByKey` and `fnAnnotationHTML` both already exist, which
  // is why this costs a popup and not an extraction.
  //
  // Lifecycle deliberately mirrors the context menu above (close on
  // click-outside, blur, resize, scroll, Escape) rather than inventing a
  // second set of rules for a second floating thing on the same page.
  // =====================================================================
  var sigpop = document.getElementById("sigpop");
  var sigAnchor = null, sigPinned = false, sigTimer = null;

  function sigClose(){
    if(sigTimer){ clearTimeout(sigTimer); sigTimer = null; }
    sigpop.classList.remove("on");
    if(sigAnchor) sigAnchor.classList.remove("on");
    sigAnchor = null;
    sigPinned = false;
  }

  function sigOpen(el){
    // Two kinds of trigger, one card: `data-sig` shows what the annotations
    // say, `data-doc` shows where the prose mentions it. Sharing the element
    // is not just economy — two independently-positioned cards that can both
    // be open would have to negotiate overlap, focus and Escape between
    // them, and there is no reading task that wants both at once.
    var html;
    if(el.dataset.doc){
      html = docRefsHTML(el.dataset.doc);
    } else {
      var entry = fnByKey[el.dataset.sig];
      // A key with no entry is a bug in whatever rendered the trigger, not
      // something to paper over with an empty card — say nothing at all.
      if(!entry) return;
      html = fnAnnotationHTML(entry.fn) + snippetHTML(entry.fn, entry.node) +
        '<div class="fn-desc fn-see"><a href="#" data-sig-goto="' +
        esc(entry.node.id) + '">' + esc(entry.node.module || entry.node.path) +
        ':' + entry.fn.line + '</a></div>';
    }

    if(sigAnchor && sigAnchor !== el) sigAnchor.classList.remove("on");
    sigAnchor = el;
    el.classList.add("on");
    sigpop.innerHTML = html;
    sigpop.classList.add("on");

    // Measured after it is in the DOM, then flipped rather than clamped
    // vertically: a card pinned to the bottom edge would cover the very row
    // the reader is pointing at, which a menu (positioned at the cursor)
    // does not have to worry about.
    var a = el.getBoundingClientRect();
    var r = sigpop.getBoundingClientRect();
    var left = Math.max(8, Math.min(a.left, window.innerWidth - r.width - 8));
    var top = (a.bottom + r.height + 8 <= window.innerHeight)
      ? a.bottom + 6
      : Math.max(8, a.top - r.height - 6);
    sigpop.style.left = left + "px";
    sigpop.style.top = top + "px";
  }

  // Hover opens, but with a grace period on the way out so the pointer can
  // travel into the card to scroll it or select text. Click pins, which is
  // what makes the card usable at all for a long `@example` block.
  document.addEventListener("mouseover", function(ev){
    var el = ev.target.closest && ev.target.closest("[data-sig],[data-doc]");
    if(el){
      if(sigTimer){ clearTimeout(sigTimer); sigTimer = null; }
      if(el !== sigAnchor) sigOpen(el);
      return;
    }
    if(sigPinned || !sigAnchor) return;
    if(ev.target.closest && ev.target.closest("#sigpop")){
      if(sigTimer){ clearTimeout(sigTimer); sigTimer = null; }
      return;
    }
    if(!sigTimer) sigTimer = setTimeout(sigClose, 180);
  });

  document.addEventListener("click", function(ev){
    var goto = ev.target.closest && ev.target.closest("[data-sig-goto]");
    if(goto){
      ev.preventDefault();
      var id = goto.dataset.sigGoto;
      sigClose();
      navigate({ tab: "tree", id: id });
      return;
    }
    var el = ev.target.closest && ev.target.closest("[data-sig],[data-doc]");
    if(el){
      ev.preventDefault();
      if(sigPinned && sigAnchor === el){ sigClose(); return; }
      sigOpen(el);
      sigPinned = true;
      return;
    }
    if(sigAnchor && !(ev.target.closest && ev.target.closest("#sigpop"))) sigClose();
  });

  // A separate listener rather than folded into the one above: this one
  // never opens an in-page popup, only ever a new tab, so it has none of
  // sigOpen/sigClose's own state to coordinate with.
  document.addEventListener("click", function(ev){
    var el = ev.target.closest && ev.target.closest("[data-godbolt]");
    if(!el) return;
    ev.preventDefault();
    var key = el.dataset.godboltKey;
    var entry = fnByKey[key];
    var source = entry && entry.fn.snippet;
    if(!source) return; // no snippet to show — a trigger with nothing behind it is inert, not a dead link to godbolt.org with an empty editor

    // The whole source travels in the URL, base64-encoded, and godbolt.org
    // sits behind a front end that rejects a request line over 8 KB with a
    // bare `414`. Measured against this repository's own map: the longest
    // single function comes to 2,880 characters and is fine, while the
    // largest module — 37 functions concatenated — comes to 33,332, four
    // times over. So a module trigger did not *sometimes* fail; on anything
    // past a handful of functions it could never have worked, and it failed
    // as an unexplained CloudFront error page in a new tab.
    //
    // Refuse locally instead. Saying why, in the page, beats opening a tab
    // that says `414 ERROR` and nothing else — and the alternative is real:
    // the per-function triggers on the same page do work.
    var url = godboltUrl(source);
    if(url.length > 8000){
      godboltTooLong(el, url.length);
      return;
    }
    window.open(url, "_blank");
  });

  // Explain a refusal where the reader clicked, and leave it explained: the
  // trigger keeps the message as its title afterwards, so the same link does
  // not invite the same click again.
  function godboltTooLong(el, len){
    var msg = "Too large for Compiler Explorer: this would be a " +
      Math.round(len / 1024) + " KB URL and their front end rejects anything " +
      "over 8 KB with a 414. Open a single function instead — those fit.";
    el.classList.add("godi-off");
    el.title = msg;
    var note = el.parentNode && el.parentNode.querySelector(".godi-note");
    if(!note){
      note = document.createElement("div");
      note.className = "godi-note";
      el.parentNode.appendChild(note);
    }
    note.textContent = msg;
  }

  // Keyboard parity: the trigger is focusable, so tabbing a list reaches it
  // and Enter/Space opens the same card the pointer would.
  document.addEventListener("keydown", function(ev){
    if(ev.key === "Escape" && sigAnchor){ sigClose(); return; }
    if(ev.key !== "Enter" && ev.key !== " ") return;
    var el = document.activeElement;
    if(!el || !el.dataset || !(el.dataset.sig || el.dataset.doc)) return;
    ev.preventDefault();
    if(sigPinned && sigAnchor === el){ sigClose(); return; }
    sigOpen(el);
    sigPinned = true;
  });

  window.addEventListener("blur", sigClose);
  window.addEventListener("resize", sigClose);
  // Capture phase, so a scroll anywhere on the page reaches this — the card
  // is `position:fixed` against an anchor that scrolls away, so it has to go
  // when the page moves under it.
  //
  // But **not when the scroll is the card's own**. It is `max-height:60vh;
  // overflow-y:auto` on purpose: a forty-line snippet is meant to be
  // scrolled inside it. Without this test the card showed a scrollbar and
  // shut the instant anyone used it — an affordance that advertised
  // something it then refused to do, which is worse than not offering it.
  document.addEventListener("scroll", function(ev){
    if(ev.target && ev.target.nodeType === 1 && ev.target.closest &&
       ev.target.closest("#sigpop")) return;
    sigClose();
  }, true);

  // =====================================================================
  // Quicks — the tree's own state, in sentences.
  //
  // No computation here: `core/quicks.lua` produced the verdicts, including
  // the `basis` line under each one. That split is deliberate rather than
  // tidy — the same verdicts have to be reachable from the CLI and from a
  // spec, and a rule that lives in this file is a rule only the browser can
  // check.
  // =====================================================================
  var QUICKS = IR.quicks || { good: [], bad: [], total_good: 0, total_bad: 0 };

  function quickHTML(q){
    var h = ['<div class="qk ' + (q.polarity === "good" ? "good" : "bad") + '">'];
    h.push('<div class="qk-head"><span class="qk-line">' + esc(q.headline) + '</span>' +
      '<span class="qk-val">' + esc(q.detail) + '</span></div>');
    h.push('<div class="qk-basis">' + esc(q.basis) + '</div>');

    var acts = [];
    if(q.tab){
      acts.push('<button data-qgoto="' + esc(q.id) + '">Show the rows</button>');
    }
    // Only where the verdict actually carried evidence — an offer to mark
    // "the functions behind this" that silently marks nothing is worse than
    // no button. `quicks.lua` attaches evidence to negative verdicts only,
    // and caps the list, so this is bounded by construction.
    if(q.evidence && q.evidence.length){
      acts.push('<button data-qmark="' + esc(q.id) + '">Mark all ' +
        q.evidence.length + '</button>');
    }
    if(acts.length) h.push('<div class="qk-acts">' + acts.join("") + '</div>');
    h.push("</div>");
    return h.join("");
  }

  function quickById(id){
    var all = QUICKS.good.concat(QUICKS.bad);
    for(var i = 0; i < all.length; i++){ if(all[i].id === id) return all[i]; }
    return null;
  }

  function drawQuicks(){
    var el = document.getElementById("view-quicks");
    var h = ['<div class="qk-wrap">'];

    if(!QUICKS.good.length && !QUICKS.bad.length){
      // Three different situations, and telling them apart matters: an old
      // artifact, a tree too small to say anything about, or a genuinely
      // unremarkable one. Only the last is good news, so do not phrase all
      // three as if they were.
      h.push('<p class="ntext none">Nothing crossed a threshold in either direction. ' +
        'That is the normal reading for a tree that is doing fine — every measure ' +
        'landed in the unremarkable band between its two cut points. An artifact ' +
        'generated before Quicks existed also lands here; regenerate with ' +
        '<code>:DocMap</code> if this map is old.</p>');
      h.push("</div>");
      el.innerHTML = h.join("");
      return;
    }

    // Negatives first. The positives are the reward for reading, not the
    // headline — a page that opens with praise buries the one thing the
    // reader could act on today.
    if(QUICKS.bad.length){
      h.push('<div class="qk-col"><div class="qk-h">Worth fixing' +
        (QUICKS.total_bad > QUICKS.bad.length
          ? ' — ' + QUICKS.bad.length + ' of ' + QUICKS.total_bad + ' shown'
          : '') + '</div>');
      QUICKS.bad.forEach(function(q){ h.push(quickHTML(q)); });
      h.push("</div>");
    }
    if(QUICKS.good.length){
      h.push('<div class="qk-col"><div class="qk-h">Going well' +
        (QUICKS.total_good > QUICKS.good.length
          ? ' — ' + QUICKS.good.length + ' of ' + QUICKS.total_good + ' shown'
          : '') + '</div>');
      QUICKS.good.forEach(function(q){ h.push(quickHTML(q)); });
      h.push("</div>");
    }
    h.push("</div>");
    el.innerHTML = h.join("");
  }

  document.addEventListener("click", function(ev){
    var goto = ev.target.closest && ev.target.closest("[data-qgoto]");
    if(goto){
      var q = quickById(goto.dataset.qgoto);
      if(q) navigate(q.atool ? { tab: q.tab, atool: q.atool } : { tab: q.tab });
      return;
    }
    var mk = ev.target.closest && ev.target.closest("[data-qmark]");
    if(mk){
      var qq = quickById(mk.dataset.qmark);
      if(qq && qq.evidence) addMarks(qq.evidence);
      return;
    }
  });

  // =====================================================================
  // Compare — the marked objects, next to each other.
  //
  // Three layouts, and they are not three skins of one thing. Columns and
  // Stacked render the annotation card this page already has, which is worth
  // having but is also roughly what two browser windows do. Matrix is the
  // layout that earns the tab: attributes down the side, marked objects
  // across, and every row where they disagree lit up. "Where do these four
  // differ" has no other answer here.
  // =====================================================================
  function markEntry(key){
    var fn = fnByKey[key];
    if(fn) return { kind: "fn", key: key, fn: fn.fn, node: fn.node };
    var n = byId[key];
    if(n) return { kind: "node", key: key, node: n };
    return null;
  }

  function markTitle(e){
    if(e.kind === "fn") return e.fn.name;
    return e.node.module || e.node.name;
  }

  function markWhere(e){
    if(e.kind === "fn") return (e.node.module || e.node.path) + ":" + e.fn.line;
    return e.node.path;
  }

  // One row of the matrix. `get` returns a display string; rows where every
  // marked object returns the same string are not what the reader came for.
  var CMP_ROWS = [
    { label: "Kind", get: function(e){ return e.kind === "fn" ? "function" : e.node.kind; } },
    { label: "Where", get: function(e){ return markWhere(e); } },
    { label: "Summary", get: function(e){
      return (e.kind === "fn" ? e.fn.summary : e.node.summary) || "—"; } },
    { label: "Signature", get: function(e){
      return e.kind === "fn" ? (e.fn.signature || "—") : "—"; } },
    { label: "Params", get: function(e){
      return e.kind === "fn" ? String((e.fn.params || []).length) : "—"; } },
    { label: "Returns", get: function(e){
      return e.kind === "fn" ? String((e.fn.returns || []).length) : "—"; } },
    { label: "Complexity", get: function(e){
      return e.kind === "fn" ? String(e.fn.complexity || 1) : "—"; } },
    { label: "Lines", get: function(e){
      if(e.kind !== "fn") return String((e.node.stats && e.node.stats.lines) || 0);
      return (e.fn.line_end && e.fn.line) ? String(e.fn.line_end - e.fn.line + 1) : "—"; } },
    { label: "Tested", get: function(e){
      return e.kind === "fn" ? (e.fn.tested ? "yes" : "no") : "—"; } },
    { label: "Documented", get: function(e){
      return e.kind === "fn" ? (e.fn.documented ? "yes" : "no") : "—"; } },
    { label: "Internal", get: function(e){
      return e.kind === "fn" ? (e.fn.internal ? "yes" : "no") : "—"; } },
    { label: "Deprecated", get: function(e){
      if(e.kind !== "fn") return "—";
      return e.fn.deprecated !== undefined ? (e.fn.deprecated || "yes") : "no"; } },
    { label: "Example", get: function(e){
      return e.kind === "fn" ? (e.fn.example ? "yes" : "no") : "—"; } },
    { label: "Requires", get: function(e){
      return String(((e.kind === "fn" ? e.node : e.node).requires || []).length); } },
    { label: "Required by", get: function(e){
      return String(((e.kind === "fn" ? e.node : e.node).required_by || []).length); } }
  ];

  function cmpMatrixHTML(entries){
    var h = ['<div class="cmp-scroll"><table class="cmptable"><thead><tr><th></th>'];
    entries.forEach(function(e){
      h.push('<th>' + esc(markTitle(e)) +
        '<button class="cmp-drop" data-unmark="' + esc(e.key) +
        '" title="Drop this one">&times;</button></th>');
    });
    h.push("</tr></thead><tbody>");
    CMP_ROWS.forEach(function(row){
      var vals = entries.map(row.get);
      var differs = false;
      for(var i = 1; i < vals.length; i++){ if(vals[i] !== vals[0]){ differs = true; break; } }
      h.push('<tr class="' + (differs ? "differs" : "") + '"><th>' + esc(row.label) + '</th>');
      vals.forEach(function(v){ h.push('<td>' + esc(v) + '</td>'); });
      h.push("</tr>");
    });
    h.push("</tbody></table></div>");
    return h.join("");
  }

  function cmpCardHTML(e){
    var h = ['<div class="cmp-card">'];
    h.push('<div class="cmp-card-h"><span class="cmp-where">' + esc(markWhere(e)) + '</span>' +
      '<button class="cmp-drop" data-unmark="' + esc(e.key) + '" title="Drop this one">&times;</button></div>');
    if(e.kind === "fn"){
      // The same renderer the detail pane and the popup use. A third copy of
      // "how a function's annotations look" is exactly the drift this plugin
      // exists to detect.
      h.push(fnAnnotationHTML(e.fn) + snippetHTML(e.fn, e.node));
    } else {
      h.push('<div class="fn-sig">' + esc(e.node.module || e.node.name) + '</div>');
      if(e.node.summary) h.push('<div class="fn-desc">' + prose(e.node.summary) + '</div>');
    }
    h.push("</div>");
    return h.join("");
  }

  function drawCompare(){
    var body = document.getElementById("cmpbody");
    var view = state.cview || "matrix";
    document.querySelectorAll("#cmptoggle .cmpview-btn").forEach(function(b){
      b.classList.toggle("active", b.dataset.cview === view);
    });

    var entries = state.marks.map(markEntry).filter(Boolean);

    if(!entries.length){
      body.innerHTML = '<p class="ntext none">Nothing marked yet. The <code>+</code> ' +
        'beside any function or module adds it here — mark two or more and this tab ' +
        'shows them next to each other. Marks survive a reload and travel in the URL, ' +
        'so a comparison is shareable.</p>';
      return;
    }
    if(view === "matrix" && entries.length === 1){
      body.innerHTML = '<p class="nsub">One object marked — a matrix needs a second ' +
        'to compare against. Shown as a card until then.</p>' +
        '<div class="cmp-stack">' + cmpCardHTML(entries[0]) + '</div>';
      return;
    }

    if(view === "matrix"){ body.innerHTML = cmpMatrixHTML(entries); return; }

    var cls = view === "columns" ? "cmp-cols" : "cmp-stack";
    body.innerHTML = '<div class="' + cls + '">' +
      entries.map(cmpCardHTML).join("") + "</div>";
  }

  document.querySelectorAll("#cmptoggle .cmpview-btn").forEach(function(b){
    b.addEventListener("click", function(){
      navigate({ tab: "compare", cview: b.dataset.cview });
    });
  });
  document.getElementById("cmpclear").addEventListener("click", clearMarks);
  document.getElementById("markbar").addEventListener("click", function(){
    navigate({ tab: "compare" });
  });
  // Unlike #markbar, no tab to open — the pill's only job is showing how many
  // boxes are dimmed and clearing all of them in one click.
  document.getElementById("hiddenbar").addEventListener("click", clearHidden);

  document.addEventListener("click", function(ev){
    var un = ev.target.closest && ev.target.closest("[data-unmark]");
    if(un){ toggleMark(un.dataset.unmark); return; }
    var mk = ev.target.closest && ev.target.closest("[data-mark]");
    if(mk){
      // Stops the row's own click handler from also firing: every list that
      // renders a mark trigger renders it inside a row that navigates when
      // clicked, and marking something must not also move the page away from
      // the list being scanned.
      ev.preventDefault();
      ev.stopPropagation();
      toggleMark(mk.dataset.mark);
      return;
    }
  }, true);

  // Keyboard parity, same as the `ⓘ` trigger has.
  document.addEventListener("keydown", function(ev){
    if(ev.key !== "Enter" && ev.key !== " ") return;
    var el = document.activeElement;
    if(!el || !el.dataset || !el.dataset.mark) return;
    ev.preventDefault();
    toggleMark(el.dataset.mark);
  });

  // Keyboard parity for the third affordance on those same rows: the link
  // itself. `.marki` and `.sigi` above each got a tabindex and their own
  // Enter/Space handler; the `data-node` element they decorate did not, so
  // tabbing the Index reached all 456 "mark" toggles and all 456 `ⓘ`
  // triggers and none of the 456 function links they belong to — every
  // accessory keyboard-operable, the primary action not.
  //
  // One delegated listener rather than a per-element one at each of the
  // render sites, for the reason the graph's own click handler gives: these
  // lists are rebuilt wholesale on every redraw, and re-binding per element
  // would stack duplicates on whatever survives.
  //
  // Disjoint from the two handlers above by construction — they key on
  // `data-mark`/`data-sig`/`data-doc`, this on `data-node`, and no element
  // carries both. `.feat-name`/`.feat-tab-name` are covered by the same
  // listener: they already shipped `tabindex="0" role="button"` but had only
  // a click listener, so they took a tab stop and announced themselves as
  // buttons while doing nothing when operated — `role="button"` does not
  // make a non-button activate on Enter, which was measured rather than
  // assumed before this was written.
  document.addEventListener("keydown", function(ev){
    if(ev.key !== "Enter" && ev.key !== " ") return;
    var el = document.activeElement;
    if(!el || !el.dataset || !el.dataset.node) return;
    // A real <input>/<textarea> that happened to carry data-node keeps its
    // own meaning for Space; nothing renders that today, and guarding costs
    // one test.
    if(/^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName)) return;
    ev.preventDefault();
    navigate({ tab: "tree", id: el.dataset.node });
  });

  // =====================================================================
  // =====================================================================
  // Roving tabindex for the long lists.
  //
  // Slice 5 gave the Index's 456 links a tabindex each, which is right for a
  // list of links but wrong at this scale: the Tree carries 169 rows, the
  // Analysis panels up to 79, History 100. Stamping each one a tab stop
  // would put ~440 presses between the tab bar and the page's own content,
  // which is not "accessible", just unusable in a different way.
  //
  // So: one tab stop per list, on the container, and the arrows move within
  // it — the roving-tabindex pattern. Exactly one element in each list is
  // focusable at any moment, which is what makes it "roving".
  //
  // Delegated on a container that exists in the initial HTML and is never
  // replaced (`#tree`, `#hist-list`, `#anbody`), never bound per item, for
  // the reason the graph's click handler already states: these bodies are
  // rebuilt wholesale on redraw and per-item binding stacks duplicates.
  // Items therefore carry no tabindex attribute at rest; `tabIndex = -1` is
  // set on one lazily, immediately before focusing it. That is also what
  // makes this survive a redraw with no re-wiring: nothing is remembered
  // about the old DOM.
  //
  // `offsetParent === null` is the visibility test, and it is doing real
  // work rather than being a formality: it excludes rows inside a collapsed
  // `.kids` (`display:none`) *and* rows the search box hid via
  // `style.display`, so the arrows walk exactly what the eye sees.
  // =====================================================================
  function rovingList(containerId, itemSelector, activate, hooks){
    var container = document.getElementById(containerId);
    if(!container) return;
    // The container is the single tab stop. Items are reached with arrows
    // once focus is inside it.
    if(!container.hasAttribute("tabindex")) container.tabIndex = 0;

    function items(){
      return Array.prototype.slice.call(container.querySelectorAll(itemSelector))
        .filter(function(el){ return el.offsetParent !== null; });
    }
    function itemOf(target){
      var el = target;
      while(el && el !== container){
        if(el.matches && el.matches(itemSelector)) return el;
        el = el.parentNode;
      }
      return null;
    }
    function focusItem(el){
      if(!el) return;
      el.tabIndex = -1;
      el.focus();
      // `nearest` so arrowing does not yank a list that is already in view.
      if(el.scrollIntoView) el.scrollIntoView({ block: "nearest" });
    }

    container.addEventListener("keydown", function(ev){
      if(ev.ctrlKey || ev.metaKey || ev.altKey) return;
      // A search box or any other real input inside the list keeps its own
      // arrow-key meaning.
      if(/^(INPUT|TEXTAREA|SELECT)$/.test(ev.target.tagName)) return;

      var list = items();
      if(!list.length) return;
      var cur = itemOf(ev.target);
      var i = cur ? list.indexOf(cur) : -1;

      if(ev.key === "ArrowDown"){
        ev.preventDefault();
        focusItem(list[i < 0 ? 0 : Math.min(i + 1, list.length - 1)]);
      } else if(ev.key === "ArrowUp"){
        ev.preventDefault();
        focusItem(list[i <= 0 ? 0 : i - 1]);
      } else if(ev.key === "Home"){
        ev.preventDefault(); focusItem(list[0]);
      } else if(ev.key === "End"){
        ev.preventDefault(); focusItem(list[list.length - 1]);
      } else if(ev.key === "Enter" || ev.key === " "){
        if(!cur) return;
        ev.preventDefault();
        activate(cur);
      } else if(hooks && hooks.horizontal && (ev.key === "ArrowRight" || ev.key === "ArrowLeft")){
        if(!cur) return;
        ev.preventDefault();
        hooks.horizontal(cur, ev.key === "ArrowRight", focusItem, list, i);
      }
    });
  }

  // The Tree is a tree, not a flat list, so Right/Left expand and collapse
  // the way every other tree widget does. Reusing the twisty's own click
  // handler rather than re-implementing the toggle keeps one source of truth
  // for what expanding means — including the arrow glyph it swaps.
  function treeKidsOf(row){
    var box = row.parentNode;
    return box ? box.querySelector(".kids") : null;
  }
  rovingList("tree", ".row", function(row){
    if(row.dataset.id) navigate({ tab: "tree", id: row.dataset.id });
  }, {
    horizontal: function(row, isRight, focusItem, list, i){
      var kids = treeKidsOf(row);
      var tw = row.querySelector(".tw");
      if(isRight){
        // Collapsed: open it. Already open (or a leaf): step into the first
        // child, which is what Right does in a tree that is already expanded.
        if(kids && kids.classList.contains("hide")){ tw && tw.click(); return; }
        if(i >= 0 && i + 1 < list.length) focusItem(list[i + 1]);
        return;
      }
      // Left: close an open node, else go to the parent row.
      if(kids && !kids.classList.contains("hide")){ tw && tw.click(); return; }
      var parentBox = row.parentNode && row.parentNode.parentNode;
      var parentRow = parentBox && parentBox.parentNode
        ? parentBox.parentNode.querySelector(":scope > .row") : null;
      if(parentRow && parentRow !== row) focusItem(parentRow);
    }
  });

  rovingList("hist-list", ".crow", function(row){
    if(row.dataset.sha) navigate({ tab: "history", sha: row.dataset.sha });
  });

  // The Analysis body holds a real <table>. Its rows get roving focus, but
  // deliberately no listbox/option roles: a table already carries correct
  // semantics, and overriding them with list roles would throw away the row
  // and column relationships a screen reader otherwise gets for free.
  rovingList("anbody", "tr.anrow", function(row){
    if(row.dataset.node) navigate({ tab: "tree", id: row.dataset.node });
  });

  // `aria-expanded` on the rows that have something to expand. Stamped after
  // every tree redraw and every toggle rather than at render time, because
  // the twisty's own click handler is what changes the state and it lives in
  // renderNode. Measurable and unambiguous, unlike the fuller tree/treeitem
  // role taxonomy, which is deliberately not attempted here: getting it
  // half-right is worse than leaving native semantics alone, and this
  // session has no screen reader to verify it against.
  function syncTreeExpanded(){
    var treeEl2 = document.getElementById("tree");
    if(!treeEl2) return;
    treeEl2.querySelectorAll(".row").forEach(function(row){
      var kids = treeKidsOf(row);
      if(kids) row.setAttribute("aria-expanded", kids.classList.contains("hide") ? "false" : "true");
      else row.removeAttribute("aria-expanded");
    });
  }
  // Capture phase, deliberately: the twisty's own click handler calls
  // `ev.stopPropagation()` (so that expanding a node does not also select
  // it), which means a bubble-phase listener on `#tree` never sees the one
  // click that actually changes expanded state. Measured, not reasoned about
  // — the first version of this used the bubble phase and left
  // `aria-expanded` reading "true" on a collapsed node, for keyboard and
  // mouse alike. Capture runs on the way down, before that stop; the
  // `setTimeout` then reads the state after the toggle has applied.
  document.getElementById("tree").addEventListener("click", function(){
    setTimeout(syncTreeExpanded, 0);
  }, true);

  // Keyboard parity for the sort headers, same shape as `data-node`'s above:
  // they are rendered fresh with every panel redraw, so this is delegated on
  // `#anbody` and keyed on `data-sort`, and it simply replays the click the
  // pointer would have produced rather than duplicating the direction logic
  // that decides ascending from descending.
  document.getElementById("anbody").addEventListener("keydown", function(ev){
    if(ev.key !== "Enter" && ev.key !== " ") return;
    var el = document.activeElement;
    if(!el || !el.dataset || el.dataset.sort === undefined) return;
    ev.preventDefault();
    el.click();
  });

  // =====================================================================
  // Initial load: parse whatever hash the page was opened with (a bare
  // #<id> from an old-style/shared link, a full serialized state from
  // Back/Forward, or nothing) and apply it as a *replace*, not a push — the
  // very first state should not itself create a Back-stack entry.
  // =====================================================================
  var initial = parseState(location.hash);
  if(!initial.id && !initial.center) initial.id = IR.root;
  // A link that carries marks wins — it is an explicit statement about which
  // set to look at, and silently unioning it with whatever this browser had
  // lying around would make a shared comparison show things the sender never
  // marked. Only a hash with no `marks` at all falls back to the stored set,
  // which is the "I marked these yesterday, then regenerated" case.
  if(!initial.marks.length) initial.marks = loadMarks();
  // Same precedence, same reasoning: a shared Hierarchy link that dims a
  // specific set of boxes should show exactly that set, not that set unioned
  // with whatever this browser had dimmed from an earlier session.
  if(!initial.hidden.length) initial.hidden = loadHidden();
  applyState(initial, false);
  syncTreeExpanded();
})();
]]

---@param ir Documentation.IR
---@param findings Documentation.Finding[]
---@param opts Documentation.Opts
---@return string
function M.render(ir, findings, opts)
  -- How far the artifact sits below the repo root, so relative links back to
  -- README files resolve from wherever it was written.
  local out_dir = opts.out_dir or "docs/map"
  local depth = select(2, out_dir:gsub("[^/]+", "")) or 0

  local meta = vim.deepcopy(ir.meta)
  meta.out_depth = depth
  -- Render-time-only, same as `out_depth` above: `opts.godbolt` needs no new
  -- IR field and touches no scan step, only whether the client-side
  -- Compiler Explorer trigger renders anything at all — see that code's own
  -- header comment.
  meta.godbolt = not not opts.godbolt

  local nodes = {}
  for _, id in ipairs(ir.order) do
    nodes[#nodes + 1] = ir.nodes[id]
  end

  local payload = json.encode({
    meta = meta,
    root = ir.root,
    nodes = nodes,
    edges = ir.edges or {},
    tag_links = ir.tag_links or {},
    -- Was missing, which made the Duplicates panel unreachable: it reads
    -- `IR.duplicates`, found nothing, and showed its "this map was generated
    -- before duplicate detection existed — regenerate it" message on *every*
    -- map including one generated a second earlier. The advice was impossible
    -- to follow, because regenerating produced the same payload again.
    --
    -- The empty shape rather than `nil` when absent, so the panel can tell
    -- "ran, found nothing" (its real no-duplicates message) apart from "this
    -- artifact predates the feature" (the message above, which is now only
    -- reachable by an artifact that genuinely predates it).
    duplicates = ir.duplicates or { groups = {}, functions = 0, considered = 0, min_size = 0 },
    -- The same omission as `duplicates` above, made a second time and caught
    -- the same way — by opening the generated page and finding the feature
    -- silently absent. This payload is built independently of
    -- `documentation.to_json`, so adding a field to `ir` and to the JSON
    -- artifact does *not* put it on the page; both sites need it. That is
    -- the trap, and it has now cost two features, so it is worth stating
    -- plainly rather than leaving for a third.
    docs = ir.docs or { files = {}, refs = {}, missing = {} },
    -- Third time this field list has had to be extended by hand, and the
    -- comment above is the reason it went right the first try here. Same empty
    -- shape rather than `nil`, so the tab can tell "computed, nothing crossed a
    -- threshold" (a real and quite good answer for a healthy tree) apart from
    -- "this artifact predates Quicks".
    quicks = ir.quicks or { good = {}, bad = {}, total_good = 0, total_bad = 0 },
    -- Caught here, before shipping, precisely *because* of the comment
    -- thread above — the fourth and fifth fields added to `ir` after
    -- `M.render`'s own field list existed, checked against this trap on
    -- purpose instead of by opening the page and finding them missing.
    -- No empty-shape fallback, unlike duplicates/docs/quicks: `nil` here is
    -- not "this artifact predates the feature", it is the real, common
    -- answer "this repo ships no lib.nvim.deps manifest" / "no
    -- docs/FEATURES/ folder" — `renderAnalysisTools`/`drawFeatures` already
    -- check for exactly that falsy value.
    tools = ir.tools,
    features = ir.features,
    -- The trap above claimed a third feature after all, and the comment
    -- thread did not prevent it: `ir.checklist` is set by `scan_full` and
    -- serialised by `documentation.to_json`, but never reached this list —
    -- so the Checklist panel rendered "This repository has no checklist" on
    -- every page, including one whose own `module_map.json` carried the
    -- ledger and whose `/api/checklist` answered `available: true`. Found by
    -- opening the served page and comparing the three against each other,
    -- which is the same way the first two were found.
    --
    -- No empty-shape fallback, for the same reason as `tools`/`features`:
    -- `nil` here is the real, common answer "this repo ships no
    -- docs/CHECKLIST/", which `drawAnalysisChecklist` already handles.
    checklist = ir.checklist,
    -- Keyword glossaries, keyed by file extension. Tool data rather than
    -- scanned data -- the same bytes in every checkout -- so it rides on
    -- the page and deliberately not in `module_map.json`, which is
    -- byte-deterministic and describes the repository rather than the
    -- renderer. Reached through the registry, never by requiring a backend:
    -- `documentation.core` must not name `documentation.core.lang.*`, and
    -- this module is under that prefix.
    glossaries = require("documentation.core.lang_registry").glossaries(),
    -- The annotation catalogue, for the same reason and on the same terms as
    -- `glossaries` above: tool data, identical in every checkout, so it rides
    -- on the page rather than inflating a byte-deterministic artifact that is
    -- supposed to describe the repository.
    --
    -- Carried before either consumer exists, deliberately and visibly: the
    -- lookup layer's third kind (`ReferenceTab.md`) and the annotation
    -- adoption panel (`IDEAS_IMPLEMENTATION_PLAN.md` §2.1) both need exactly
    -- this table, and shipping it once here is what makes each of them the
    -- quick win their own estimate claims. A payload key with no reader is a
    -- cost of a few hundred bytes; two panels each inlining their own copy is
    -- the duplication this repository argues against everywhere else.
    tags = require("documentation.core.tags").for_page(),
    -- The keyword table `core/markers.lua` matched with, so the Notes tab
    -- renders sections in the same order and with the same names the
    -- scanner used. Passed rather than repeated in JavaScript: a second
    -- copy of this list is a second thing to keep in step, and the page
    -- would show a `PERF` section that the scanner had stopped filling.
    -- Tool data, like `glossaries` above, so it rides on the page and not
    -- in the byte-deterministic artifact.
    marker_kinds = require("documentation.core.markers").KEYWORDS,
  })
  -- `</script>` inside JSON would terminate the block early.
  payload = payload:gsub("</", "<\\/")

  -- **This page is an edge, so this is where a finding becomes a
  -- sentence.** The embedded array carries `message` rather than the
  -- `params` the finding travels with, because the page's own JS reads
  -- `x.message` and a committed artifact has to be readable without a
  -- catalog beside it. Sending params and a catalog instead is I18N-3,
  -- deliberately not this task: it changes what the artifact *is*, and
  -- the point of I18N-0 is that it changes nothing anyone can see.
  local rendered = {}
  for i, f in ipairs(findings) do
    rendered[i] = {
      severity = f.severity,
      check = f.check,
      node = f.node,
      message = fmt_finding(f),
    }
  end
  local findings_json = json.encode(rendered):gsub("</", "<\\/")

  local c = ir.meta.counts
  local t = { error = 0, warn = 0, info = 0 }
  for _, f in ipairs(findings) do
    t[f.severity] = (t[f.severity] or 0) + 1
  end

  local rows = {}
  for _, f in ipairs(findings) do
    -- data-node drives the click-to-select wiring in JS. Left off entirely
    -- (rather than set to an empty string) when the finding has no node, or
    -- points at something that isn't a real IR node id (config.lua's
    -- aggregator check reports against a synthetic "lua/lib/@types" path
    -- that was never a scanned node) — the click handler only wires up rows
    -- that actually carry the attribute, so an unresolvable target silently
    -- stays inert instead of being a dead click.
    local node_attr = f.node and (' data-node="%s"'):format(esc(f.node)) or ""
    rows[#rows + 1] = ([[<tr%s><td><span class="sev %s">%s</span></td><td class="msg">%s</td><td class="msg">%s</td></tr>]]):format(
      node_attr,
      f.severity,
      f.severity,
      esc(f.check),
      esc(fmt_finding(f))
    )
  end

  return table.concat({
    "<!doctype html>",
    '<html lang="en"><head><meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width,initial-scale=1">',
    "<title>",
    esc(ir.meta.title),
    " — module map",
    -- Suppressed when the scanned project *is* documentation.nvim:
    -- "documentation.nvim — module map · documentation.nvim" repeats the
    -- name for no reason. Every other project gets the credit.
    (ir.meta.title ~= "documentation.nvim") and " · documentation.nvim" or "",
    "</title>",
    "<style>",
    CSS,
    "</style>",

    -- The theme, settable from outside the page.
    --
    -- `:root[data-theme]` has always been here; nothing could reach it.
    -- That is not academic: `docmap-desktop` embeds this page in an
    -- iframe served from `127.0.0.1` while its own shell is on `tauri://`,
    -- so the attribute it stamps on its own document never crosses, and a
    -- reader who chose dark on a light OS got a dark window with a white
    -- page in it.
    --
    -- In `<head>`, before any element exists, because a theme applied
    -- after first paint is a flash of the wrong one. `?theme=` is read
    -- rather than a `postMessage` handler added: a page that executes
    -- instructions from whatever embeds it is a different security
    -- posture than one that only reads its own URL, and a query parameter
    -- is also the thing a person can type into a browser.
    --
    -- Three states, like the app: `light` and `dark` decide, anything
    -- else -- including no parameter at all -- means follow the OS.
    [[<script>(function(){]],
    [[  try{]],
    [[    var t = new URLSearchParams(location.search).get("theme");]],
    [[    if(t === "light" || t === "dark")]],
    [[      document.documentElement.setAttribute("data-theme", t);]],
    [[  }catch(e){}]],
    [[})();</script>]],

    "</head><body>",

    -- Above the project's own header, not inside it: the header names the
    -- repository being read, and putting the tool's name in there would
    -- make the two look like one thing.
    '<div class="topbar">'
      .. '<a class="brand" href="https://github.com/StefanBartl/documentation.nvim"'
      .. ' target="_blank" rel="noopener">documentation.nvim</a>'
      .. '<span class="tagline">know your project</span>'
      .. "</div>",

    "<header><h1>",
    esc(ir.meta.title),
    '<span class="sub">module map</span></h1>',
    -- Each count links to the view that shows that set. They were inert
    -- `<span>`s: five numbers naming sets the reader could see the size of and
    -- had no way to reach.
    --
    -- `<button>` rather than `<a href="#...">`, deliberately. An anchor would
    -- write the fragment itself and then `applyState` would write it again
    -- from the parsed state, producing two history entries per click — and the
    -- errors/warnings ones are not navigations at all, they open a disclosure
    -- further down the same page.
    --
    -- A count of zero is rendered disabled rather than as a live link, because
    -- "0 warnings" that navigates somewhere empty is worse than a number that
    -- never claimed to be clickable.
    '<div class="stats">',
    ('<button class="stat-link" data-goto="modules"%s><b>%d</b> modules</button>'):format(
      (c.module or 0) == 0 and " disabled" or "",
      c.module or 0
    ),
    ('<button class="stat-link" data-goto="namespaces"%s><b>%d</b> namespaces</button>'):format(
      (c.namespace or 0) == 0 and " disabled" or "",
      c.namespace or 0
    ),
    ('<button class="stat-link" data-goto="files"%s><b>%d</b> files</button>'):format(
      (c.file or 0) == 0 and " disabled" or "",
      c.file or 0
    ),
    ('<button class="stat-link" data-goto="errors"%s><b class="sev error">%d</b> errors</button>'):format(
      t.error == 0 and " disabled" or "",
      t.error
    ),
    ('<button class="stat-link" data-goto="warnings"%s><b class="sev warn">%d</b> warnings</button>'):format(
      t.warn == 0 and " disabled" or "",
      t.warn
    ),
    "</div></header>",

    -- Quicks leads the tab bar because it is the one tab that answers a
    -- question the reader has before they have a question. It is deliberately
    -- *not* the default tab: `state.tab` still starts on "tree", so every link
    -- ever shared and every habit ever formed lands where it always did.
    -- Eight tabs in reading order, and two of them own a second level.
    --
    -- **Tree is no longer one of them.** Tree, Functions and Modules are
    -- three ways of listing the same repository, so they are three modes of
    -- Index rather than one top-level tab and two buttons inside another.
    -- Promoted features moved the same way: a feature marked `Tab: true`
    -- used to append a button to *this* bar, so a repository documenting
    -- five features pushed the tabs onto a second row and buried the eight
    -- that are always there under five that are particular to it.
    --
    -- `#subtabs` below is the second level for both, rendered from whichever
    -- group is active. One strip, not one per owner: two strips in the same
    -- place that are never both visible are one strip with extra code.
    '<div class="tabs">',
    '<button class="tab-btn active" data-tab="hierarchy" data-explain="tab.hierarchy">Hierarchy</button>',
    '<button class="tab-btn" data-tab="index" data-explain="tab.index">Index</button>',
    '<button class="tab-btn" data-tab="analysis" data-explain="tab.analysis">Analysis</button>',
    '<button class="tab-btn" data-tab="compare" data-explain="tab.compare">Compare</button>',
    '<button class="tab-btn" data-tab="features" data-explain="tab.features">Features</button>',
    '<button class="tab-btn" data-tab="quicks" data-explain="tab.quicks">Quicks</button>',
    '<button class="tab-btn" data-tab="notes" data-explain="tab.notes">Notes</button>',
    '<button class="tab-btn" data-tab="history" data-explain="tab.history">History</button>',
    '<button class="tab-btn" data-tab="findings" data-explain="tab.findings">Findings</button>',
    "</div>",

    '<div class="subtabs" id="subtabs" hidden></div>',

    '<div class="toolbar">',
    '<input id="q" type="search" placeholder="Filter modules, paths, descriptions…" autocomplete="off">',
    '<button id="expand">Expand all</button><button id="collapse">Collapse</button>',
    -- Sits with the filter rather than inside any one tab: marks are collected
    -- while reading *any* list, so the control that says how many there are and
    -- opens them has to be visible from all of them.
    '<button id="markbar" class="markbar" hidden></button>',
    -- Beside the marks pill for the same reason it is: the state being
    -- copied is whatever tab, node, graph view and filter the reader is
    -- looking at right now, so the control belongs where it is reachable
    -- from all of them rather than inside one.
    '<button id="copylink" title="Copy a link to exactly this view">Copy link</button>',
    "</div>",

    '<main id="view-tree" class="view active"><div id="langbar" class="langbar" hidden></div>'
      .. '<div id="tree"></div><div id="detail"></div></main>',

    '<div id="view-hierarchy" class="view">',
    '<div class="hctl">',
    '<button id="hup">▲ Up</button><button id="hroot">⌂ Root</button>',
    -- Where the graph is rooted, and every level above it. `Up` and `Root`
    -- were the only way back and neither says where you are — after two
    -- recentres the reader knows they moved and not from where.
    '<nav id="hcrumb" class="hcrumb" aria-label="Graph root"></nav>',
    [[<button id="hlr" title="Lay the graph out left-to-right instead of top-down">&#8644; Sideways</button>]],
    '<div class="hview-toggle">',
    '<button class="hview-btn active" data-view="modules" data-explain="view.modules">Modules</button>',
    '<button class="hview-btn" data-view="deps" data-explain="view.deps">Deps</button>',
    '<button class="hview-btn" data-view="calls" data-explain="view.calls">Calls</button>',
    '<button class="hview-btn" data-view="modulecalls" data-explain="view.modulecalls">Module Calls</button>',
    '<button class="hview-btn" data-view="types" data-explain="view.types">Types</button>',
    '<button class="hview-btn" data-view="inheritance" data-explain="view.inheritance">Inheritance</button>',
    "</div>",
    -- Direction and depth belong to the directed views only; `syncGraphControls`
    -- hides them in Modules/Types rather than leaving two control groups that
    -- do nothing.
    '<div class="hview-toggle" id="hdir">',
    '<button class="hdir-btn" data-dir="in" title="What depends on / calls this">← In</button>',
    '<button class="hdir-btn" data-dir="both" title="Both directions around the center">⇄ Both</button>',
    '<button class="hdir-btn active" data-dir="out" title="What this depends on / calls">Out →</button>',
    "</div>",
    -- Not a zoom control -- the label exists because it read like one
    -- without it (see .hctl-label's own comment).
    '<span class="hctl-label" title="How many hops from the centered node to draw">Depth</span>',
    '<div class="hview-toggle" id="hdepth">',
    '<button class="hdepth-btn" data-depth="1" title="Depth 1">1</button>',
    '<button class="hdepth-btn active" data-depth="2" title="Depth 2">2</button>',
    '<button class="hdepth-btn" data-depth="3" title="Depth 3">3</button>',
    '<button class="hdepth-btn" data-depth="0" title="Unbounded, still capped at 90 boxes">∞</button>',
    "</div>",
    '<div class="hview-toggle" id="hext">',
    '<button class="hext-btn" title="Also draw requires/calls that resolve outside this map">+ external</button>',
    "</div>",
    -- Which gesture recentres and which one leaves the view. A toggle rather
    -- than a fixed choice because the two answers have genuinely different
    -- costs: the default is the one that surprises a first-time reader least
    -- (a single click stays where you are), and the pill is for the reader
    -- who already has the opposite muscle memory from every earlier map.
    -- Styled as a pill like `#hext` rather than as a bare checkbox, because a
    -- lone checkbox among nine pills reads as a different kind of control.
    '<div class="hview-toggle" id="hgest">',
    '<button class="hgest-btn" title="Classic gestures: single click leaves for the Tree view, double click recentres. Off by default — a single click recentres and stays here.">⇵ Classic clicks</button>',
    "</div>",
    '<button id="hzoomreset" title="Reset zoom to 100% (or press 0)">⌕ 100%</button>',
    '<span class="hzoom" id="hzoomlabel">100%</span>',
    '<button id="hexport" title="Download the current diagram as a standalone SVG">↓ SVG</button>',
    -- Right-click a box to dim/show it — see the context menu. This pill
    -- only says how many are dimmed right now and clears all of them,
    -- mirroring #markbar's own role for Compare marks.
    -- The language legend again, same state as the Tree tab's. Inline in the
    -- control row rather than a band above the graph: the graph area is the
    -- scarce space here, and this is a control among controls.
    '<span id="langbar-h" class="langbar langbar-h" hidden></span>',
    '<button id="hiddenbar" class="markbar" hidden></button>',
    '<span class="hpath" id="hpath"></span>',
    "</div>",
    -- Outside #hgraph-wrap, not inside it: the wrap itself scrolls
    -- (overflow:auto, for a diagram bigger than the viewport), and an
    -- absolutely-positioned child of a scrolling element scrolls away with
    -- its content. This outer div exists only to give the slider a
    -- positioned ancestor that never moves.
    '<div id="hgraph-outer">',
    '<div class="hrootslider" id="hrootslider" title="Hide root levels — every node at that depth becomes its own root">',
    '<span class="hrootslider-label">Levels</span>',
    '<button class="hroot-btn" id="hrootplus" title="Hide one more root level">+</button>',
    '<input type="range" id="hrootrange" min="0" max="0" value="0" step="1">',
    '<button class="hroot-btn" id="hrootminus" title="Show one more root level">−</button>',
    "</div>",
    '<div id="hgraph-wrap"><div id="hgraph"><div id="hstage"></div></div></div>',
    "</div>",
    '<div class="hlegend" id="hlegend"></div>',
    "</div>",

    '<div id="view-quicks" class="view"></div>',

    '<div id="view-compare" class="view">',
    '<div class="hview-toggle" id="cmptoggle">',
    '<button class="cmpview-btn active" data-cview="matrix">Matrix</button>',
    '<button class="cmpview-btn" data-cview="columns">Columns</button>',
    '<button class="cmpview-btn" data-cview="stacked">Stacked</button>',
    '<button id="cmpclear" title="Drop every mark">Clear all</button>',
    "</div>",
    '<div id="cmpbody"></div>',
    "</div>",

    '<div id="view-notes" class="view"></div>',

    '<div id="view-features" class="view"></div>',

    '<div id="view-index" class="view">',
    '<div id="ixbody"></div>',
    "</div>",

    '<main id="view-history" class="view">',
    '<div id="hist-list"></div><div id="hist-detail"></div>',
    "</main>",

    '<div id="view-analysis" class="view">',
    '<div class="hview-toggle" id="antoggle">',
    '<button class="anview-btn active" data-atool="test" data-explain="atool.test">Test coverage</button>',
    '<button class="anview-btn" data-atool="doc" data-explain="atool.doc">Documentation</button>',
    '<button class="anview-btn" data-atool="annotations" data-explain="atool.annotations">Annotations</button>',
    '<button class="anview-btn" data-atool="api" data-explain="atool.api">API surface</button>',
    '<button class="anview-btn" data-atool="deps" data-explain="atool.deps">Dependencies</button>',
    '<button class="anview-btn" data-atool="complexity" data-explain="atool.complexity">Complexity</button>',
    '<button class="anview-btn" data-atool="duplicates" data-explain="atool.duplicates">Duplicates</button>',
    '<button class="anview-btn" data-atool="plugins" data-explain="atool.plugins">Plugins</button>',
    '<button class="anview-btn" data-atool="lazy" data-explain="atool.lazy">Lazy loading</button>',
    '<button class="anview-btn" data-atool="bindings" data-explain="atool.bindings">Bindings</button>',
    '<button class="anview-btn plugin-gated" data-atool="tools" data-explain="atool.tools">Tools</button>',
    '<button class="anview-btn plugin-gated" data-atool="telemetry" data-explain="atool.telemetry">Telemetry</button>',
    '<button class="anview-btn plugin-gated" data-atool="loaded" data-explain="atool.loaded">Loaded</button>',
    '<button class="anview-btn" data-atool="checklist" data-explain="atool.checklist">Checklist</button>',
    '<button class="anview-btn" data-atool="hooks" data-explain="atool.hooks">Hooks</button>',
    '<button class="anview-btn" data-atool="docs" data-explain="atool.docs">Docs</button>',
    '<button class="anview-btn" data-atool="endpoints" data-explain="atool.endpoints">Endpoints</button>',
    "</div>",
    '<div id="anbody"></div>',
    "</div>",

    '<div id="view-findings" class="view"><div id="findings"><details open><summary>Drift findings (',
    tostring(#findings),
    ')</summary><div class="wrap"><table>',
    "<thead><tr><th>Severity</th><th>Check</th><th>Message</th></tr></thead><tbody>",
    table.concat(rows),
    "</tbody></table></div></details></div></div>",

    '<div id="ctx" role="menu"></div>',
    '<div id="sigpop" class="sigpop" role="tooltip"></div>',
    '<div id="kwpop" class="kwpop" role="tooltip"></div>',

    '<script type="application/json" id="ir">',
    payload,
    "</script>",
    '<script type="application/json" id="findings-data">',
    findings_json,
    "</script>",
    "<script>",
    JS,
    "</script>",
    "</body></html>",
  })
end

return setmetatable(M, {
  __call = function(_, ...)
    return M.render(...)
  end,
})
