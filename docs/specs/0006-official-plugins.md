# Official plugins

Artifact-Version: 1
Status: Approved

## Intent
The first official plugins should help in any course, and each should exercise a different part of the [plugin platform](0004-plugin-platform.md):
- note views, model-written blocks, actions and pages;
- exporters and connectors;
- an external agent.

Most of them make existing notes and lectures easier to see, connect and review. Some only change the assistant's behaviour. All of them live in `agent/plugins/<id>/`, are listed in the bundled catalog, and none is installed by default.

Non-goals:
- online-judge or course-site submission;
- two-way sync with other apps;
- plugins for one specific course.

Not in this spec (backlog): Zotero citations (local API), board photos to LaTeX, running code snippets, bilingual glossary, one-page exam cheat sheet to PDF.

## Contract
Shared rules for every view below:
- Every view is native Material 3 (tonal surfaces, dynamic colour, dark mode, reduced motion honoured), keyboard and screen-reader accessible.
- Layouts are deterministic, so the same data always looks the same.
- Every node or item can carry a `ref` (`look://` timestamp, slide, courseware or note) that opens the source.
- Limits, as validated by the tool before the model sees success:
  - ≤ 300 nodes per view;
  - labels ≤ 40 chars;
  - ids unique;
  - edges point at existing nodes.

### Wave 1 — notes you can see
**思维导图 `mindmap`**: `noteViews`, `blocks`, permissions `views`, `library.read`.
- The 导图 view of a note is computed without a model from its headings (H1–H4) and nested lists. Timestamps and refs in an item become node links.
- View `mindmap`:
  - layouts: right tree and radial;
  - collapse/expand, focus a branch, search;
  - tap a node to scroll the document to it, or follow its ref;
  - export as PNG and as a Markdown outline.
- Tool `refine_mindmap {note_id}` asks the model to shorten labels and merge duplicates. The result is saved next to the note as `<note>.mindmap.json` and used until the note changes.

**图示与图表 `diagrams`**: `blocks`, tools `make_diagram`, `make_chart`; permission `views`.
- View `diagram`, one of four kinds:
  - `flowchart`: nodes shaped process / decision / terminal / io, labelled edges, TB or LR, layered layout;
  - `sequence`: participants, messages, notes;
  - `state`: states, transitions, initial and final;
  - `timeline`: dated events.
- View `chart`: `bar | line | area | scatter | pie` with named series, axis titles and units, built on the existing `charts.dart`.
- The skill says when a picture beats text, and requires data in charts to come from the material, with refs.

**推导步骤 `derivations`**: `blocks`, tool `show_derivation`; permission `views`.
- View `steps`: a list of LaTeX lines, each with a justification and an optional highlighted sub-expression.
- Modes:
  - 全部;
  - 逐步 (reveal one by one);
  - 自测 (hide the next step; the user tries, then reveals).
- For proofs, circuit analysis, physics derivations and algorithm reasoning.

**引导式提问 `socratic`**: skill and hook only, no tools. Ships with the plugin platform ([spec 0004](0004-plugin-platform.md)).
- `composer.plus` toggles the mode for every chat until it is switched off; while on it shows as a chip above the input. A new chat has no id before its first reply, so a per-chat toggle would not fit the composer.
- While on, a `before_agent_start` hook adds tutoring rules:
  - ask one guiding question at a time;
  - give a key hint after the user tries twice (setting 几次尝试后给答案, 1–6), or only hints with 引导力度 严格;
  - point to the lecture moment that helps.
- Its skill (the hint ladder) is the playbook of `find_tools` group `plugin:socratic`, for "一步步引导我" without the mode.
- Shows that a plugin can be only a behaviour.

### Wave 2 — connect and remember
**知识地图 `concept-map`**: actions on `course.menu`, a `pages` entry; permissions `views`, `library.read`.
- It builds a course graph from notes and transcripts. A model pass per lecture extracts concepts `{name, definition, refs}` and relations `{from, to, type: is-a | part-of | uses | contrasts | prerequisite}`.
- Results are cached per lecture in plugin storage and rebuilt only for new or changed lectures. The estimated cost is shown before a run.
- View `graph`:
  - force layout with a fixed seed, clustered and coloured by lecture;
  - filter by relation type, search;
  - a side panel with the definition, refs and 问助手;
  - 学这个之前 highlights the prerequisite path to a concept.

**闪卡复习 `flashcards`**: tool `make_cards`, `pages`, `exporters`; permissions `views`, `library.read`, `folder` (export).
- Cards are `{front, back, cloze?, refs, tags}`, made from a note or a lecture. Wrong answers from quizzes can be imported as cards.
- Scheduling uses FSRS, reimplemented from the published algorithm with provenance. There are four grades; state is kept in plugin storage.
- The 复习 page (from the course page's 插件 section, with a due count) uses view `flashcards`:
  - flip animation;
  - grade buttons 重来 / 困难 / 良好 / 简单 with the next interval shown;
  - keys Space and 1–4;
  - the card's ref opens the lecture moment.
- Exporter: Anki tab-separated import file with deck and tags.

**函数绘图 `plot`**: `blocks`, tool `make_plot`; permission `views`.
- View `plot`:
  - plot types: `y=f(x)`, parametric, polar, and point sets;
  - parameters with sliders (`a ∈ [min, max]`);
  - pan and zoom;
  - a trace cursor showing values;
  - axes with units.
- Expressions use one safe grammar, implemented twice (agent validator, app evaluator) with shared test vectors:
  - `+ - * / ^`;
  - `sin cos tan asin acos atan exp ln log sqrt abs floor ceil min max`;
  - `pi`, `e`, the variable, and the declared parameters.

### Wave 3 — connectors
**Obsidian 同步 `obsidian`**: `exporters` for a note, a course and the library; permissions `library.read`, `folder`.
- Writes one-way into the chosen vault:
  - files are `<vault>/<subfolder>/<course>/<date> <lecture>.md`;
  - YAML front matter holds course, date and source;
  - timestamps become text with the source link in front matter;
  - `mindmap`, `diagram` and `chart` blocks become Mermaid (`mindmap`, `flowchart`, `sequenceDiagram`, `stateDiagram-v2`, `timeline`, `pie`, `xychart-beta`); other views become a short text summary.
- It never overwrites a file it did not write; content hashes are tracked in plugin storage.

**日历导出 `calendar`**: `exporters` for the schedule; permission `folder`.
- Writes RFC 5545 `.ics` files (all items, or per course) with `VALARM` reminders (setting), for import into any calendar app.

**CPH 连接 `cph-bridge`**: tool `make_problem`, view `problem`; permissions `views`, `localhost`, `library.read`.
- `make_problem` takes a problem from course material: statement, limits and sample tests, which must come from the source.
- On the user's 发送到 IDE click, the plugin POSTs the Competitive Companion JSON (`name, group, url, interactive, memoryLimit, timeLimit, tests, testType, input, output, batch`) to each configured `127.0.0.1` port (default 27121, CPH).
- Result per port: 已发送 / 未在监听 / 失败.

### Wave 4 — programming and assignments
**数据结构可视化 `ds-visualizer`**: tool `show_structure`, `blocks`; permission `views`.
- Frames of `array | stack | queue | linked_list | tree | bst | heap | graph | hash_table | matrix`: 1–60 frames, each with nodes, edges, pointers, highlights and a note.
- Per-frame invariant checks (BST order, heap order, a tree without cycles) name the first violation.
- View `structure`:
  - per-kind layout, with nodes animated between frames by springs;
  - play / step / slider / speed;
  - 问这一步.

**Codex 作业代理 `codex-acp`**: action on `assignment.actions`, view `run-log`; permissions `exec` (`codex-acp`), `workspace`, `views`, `library.read`.
- Drives `codex-acp` over the Agent Client Protocol in the assignment folder ([agent-operator spec](0005-agent-operator.md)):
  - `initialize`, then `session/new {cwd}`, then `session/prompt` with the reviewed brief;
  - `session/update` streams plan, tool calls, messages and changed files into `run-log`;
  - `session/request_permission` becomes an app dialog, unless the `edits` policy covers edits inside the folder;
  - 停止 sends `session/cancel`.
- After `end_turn`, the assistant runs `verify_assignment`. 让 Codex 修复未通过项 sends the failures as a follow-up prompt. Codex usage is billed to the user's Codex account.

## Plan
One PR per wave after the platform. Each wave adds its views to the app catalog, its plugins with skills and README, catalog entries and icons, and tests. `docs/plugins.md` walks through writing `mindmap` as the reference plugin.

## Verification
- `node --test` per plugin:
  - validators and limits;
  - the shared expression vectors;
  - FSRS intervals against published reference values;
  - Obsidian output, Mermaid conversion and the no-overwrite rule;
  - `.ics` lines checked against RFC 5545 required properties;
  - the Competitive Companion payload against a local HTTP fixture;
  - the ACP client against a scripted fake agent.
- Widget tests per view: layout of fixtures, interaction (collapse, step, flip and grade, slider, filter), ref links, and the reduced-motion path.
- Live, per wave:
  - Wave 1: a real note shown as a mind map; a flowchart and a derivation saved in a note.
  - Wave 2: a course knowledge map; a review session; a plot with a slider.
  - Wave 3: a vault export opened in Obsidian; an `.ics` import; a problem received on port 27121.
  - Wave 4: a BST deletion; a small assignment delegated to the installed `codex-acp` and verified.

## Evidence
Pending until implementation.
