# documentation.nvim — Ausblick

**Was dieses Plugin ist, in einem Satz:** ein Werkzeug, das die
Dokumentation eines Baums gegen den Baum selbst prüft — und die Karte ist
das sichtbare Nebenprodukt, nicht der Zweck.

Der Zweck ist die andere Hälfte: eine erzeugte Karte ist ein hübsches
Artefakt, eine Karte, die *fehlschlägt*, wenn Dokumentation und Wirklichkeit
auseinanderlaufen, ist ein Test. Jede Richtung unten ist daran gemessen.

> **Die Warteschlange steht woanders.** Was als Nächstes gebaut wird — hier
> *und* in `docmap-desktop` und `runtime-analysis.nvim` — steht seit
> 2026-08-20 in **einem** Plan:
> [`docmap-desktop/docs/PLAN.md`](https://github.com/StefanBartl/docmap-desktop/blob/main/docs/PLAN.md).
>
> Was gebaut wurde und warum, steht in
> [`FEATURES.md`](../FEATURES/FEATURES.md). Die Herleitung samt Kosten und
> Gegenargumenten liegt in [`IDEAS/`](IDEAS/) — dieses Dokument ist keins
> von beidem.

## Die vier großen Richtungen

**Mehr Sprachen lesen können.** Dreiundzwanzig Backends hinter einem
Contract, damit ein gemischtes Repository *eine* Karte ergibt statt mehrerer.
Was jedes liest, steht in [`LANGUAGES.md`](../LANGUAGES.md); was jedes
gekostet hat, in [`IDEAS/MULTILANG.md`](IDEAS/MULTILANG.md). Fünfzehn
weitere sind **verfügbar, nicht geplant** — benannt, kalkuliert und nach
Kosten geordnet in derselben Datei.

**Call-Kanten außerhalb von Lua, Go und der ECMA-Familie.** Die größte
einzelne Lücke im Werkzeug: fünf Backends von dreiundzwanzig liefern
Call-Kanten, achtzehn liefern `{}` — und damit sind die Calls-Ansichten,
`:DocMap why`, die Call-Hierarchie und `dead-function`s Call-Stufe dort leer.
**Nichts an diesen Sprachen macht das unmöglich**; es ist ungebaut, nicht
blockiert. Go war bewusst die erste, als Muster — und die Lehre daraus ist
die Anweisung für die übrigen: *erst fragen, was in dieser Sprache ein Scope
ist, dann die Query schreiben.* Ein Go-Paket ist ein Verzeichnis, und ein
dateiweiser Resolver verliert daran fast die Hälfte eines echten Call-Graphen
(`aws/smithy-go`: 397 von 883 Kanten).

**Sprechen, nicht nur lesen.** Die Sprachen, die dieses Werkzeug *spricht* —
eine andere Achse als die oben, trotz des gemeinsamen Worts. Findings tragen
seit I18N-0 Parameter statt fertiger englischer Sätze; die erzeugte Seite ist
die verbleibenden ~85 % der Arbeit. Siehe [`IDEAS/I18N.md`](IDEAS/I18N.md).

**Ohne Neovim laufen.** „Eine Lua-Karte aus dem Terminal" geht längst. Die
Neovim-Abhängigkeit ganz fallen zu lassen ist separat kalkuliert in
[`IDEAS/PORTABILITY.md`](IDEAS/PORTABILITY.md) — und der Standalone-Build
hat sich zuletzt vor allem als *Prüfstand* bewährt: er liest das Artefakt als
gewöhnliche Datei und sieht damit Dinge, die keine Prüfung über den Quellbaum
sieht.

## Der eine offene Befund, den man kennen sollte

**Der `standalone`-Gate überspringt sich stillschweigend** und zählt trotzdem
zu „5/5 grün". Er braucht PUC Lua auf dem `PATH` mit `lfs` und `dkjson`;
fehlt eins davon, druckt er *skipped*. Lokal heißt grün also **„vier Gates
und ein Achselzucken"** — und genau dahinter sind drei echte Defekte bis in
ein Release gekommen.

Halb behoben: `TESTS/shim_contract_spec.lua` fängt seit 2026-08-20, was
*statisch* sichtbar ist — jeder `vim.*`-Pfad und jeder Methodenname, den
`core/` aufruft, gegen das, was der Shim implementiert. Was er nicht sieht,
ist eine Shim-Funktion, die **existiert und sich anders verhält**. Der Rest
steht als Quick Win im Plan.
