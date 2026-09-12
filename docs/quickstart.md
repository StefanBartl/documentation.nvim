# Quickstart

Open a file anywhere in the repository you want mapped, and generate:

```vim
:DocMap
```

That writes the artifacts under `docs/map/`. Then look at them, or ask
questions of them:

```vim
:DocMap open                     " open the HTML in the system browser
:DocBrowse                       " navigate the same map inside the editor
:DocMap why my.a my.b            " shortest require path between two, to quickfix
:DocMap pick                     " fuzzy-find any module or function
:DocMap check                    " verify without writing, findings to quickfix
```

Twenty-one `:DocMap` actions in all, and five ways to open `:DocBrowse`:
[commands.md](commands.md). Inside the browser, `?` shows the keys for the
current mode, rendered from the same table the keys are installed from, so it
cannot drift from them.

Verify your setup any time with:

```vim
:checkhealth documentation
```

See [health.md](health.md) for what each line of that report means.
