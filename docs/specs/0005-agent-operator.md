# Assistant as guide, operator and producer

Artifact-Version: 1
Status: Approved

## Intent
The resident assistant mostly answers and writes notes, which a plain chat can do. It should earn its place by doing three things a chat cannot:
- **guide**: show the user where things are and walk them through the app;
- **operate**: navigate and change the app's configuration on request;
- **produce**: create course work products, including notes, quizzes and assignments with an acceptance checklist.

The assistant stays available on every page: docked on wide windows, a FAB elsewhere.

This widens the assistant's write boundary (settings, assignment files), so it changes the project rule "The assistant writes only notes, schedule marks and outlines" in `AGENTS.md`.

Non-goals:
- secrets (passwords, API keys, tokens) through the assistant;
- starting downloads;
- signing in or out;
- submitting work to a course site;
- interactive exercise types beyond multiple choice (a later spec).

## Contract

### Guide
- Starter prompts: an empty composer shows chips for the current screen. Examples:
  - player: "总结这一段", "这页 PPT 讲了什么";
  - schedule item: "帮我拆解这份作业".
  Enabled plugins' `examples` show in a 插件 row. Chips come from a static table per screen plus plugins; the model is not called to make them.
- `open_page` tool (core, direct): targets `home | courses | course | lecture(t?) | note | schedule(day?) | downloads | library | tasks | settings(section?) | plugins | marketplace(plugin?) | assignment`. The app navigates at once and shows a chip `已打开 <page> · 返回` in the reply. It is not used for actions with side effects.
- `highlight` tool (core, direct): `{anchor, text}`. The app scrolls to a registered anchor, dims the rest of the window and shows an MD3 rich tooltip with `text` and 知道了. It cancels on any tap or after 15 s.
  - Anchors are named keys the app registers (`settings.models.add`, `settings.vision`, `player.outline`, `player.transcribe`, `downloads.limit`, `marketplace.search`, …). Unknown anchor → tool error listing the valid ones.
  - Used with `open_page` for "怎么…" questions; `app_guide` stays the text reference.

### Operate
- `read_settings` (core group `settings`): non-secret settings as `{key, label, value, where}`:
  - app appearance and player prefs, pushed by the app to the host on change via `PUT /agent/app-state`;
  - lookd download, transcription and parsing settings (MinerU token only as set/unset);
  - assistant model, thinking and vision prefs;
  - plugins and scheduled tasks summary.
- `propose_settings {changes:[{key, value}], reason}`: validated against a registry `{key, type, range|enum, label, where, risk}`. It returns a `settings` proposal card listing `label: old → new`.
  - `risk: low` keys (theme, contrast, text scale, chat style, player speeds, subtitle size) apply immediately, with 撤销 for 30 s.
  - All others wait for the user's 应用 (download concurrency, speed limit, ASR channels, default model, library location excluded).
  - Unknown key or out-of-range value → tool error with the allowed values.
- `propose_task`: same fields as `POST /agent/tasks`, shown as a card with 创建 / 修改.
- `propose_plugin {id, enabled}`: a card with 启用 / 停用. Installing always goes through the marketplace consent dialog: the tool can `open_page` the plugin's detail page, never install.

### Produce: assignments
An assignment (作业) is a folder in the library: `courses/<course>/assignments/<slug>/`. It holds `assignment.json`, `README.md` (generated) and the work files.

```json
{"id","course_id","schedule_id?","title","due?","status":"planning|working|review|done",
 "requirements":[{"text","ref?"}],"deliverables":[{"path","kind":"doc|code|data|other"}],
 "checklist":[{"id","text","verify","state":"todo|done|failed","evidence?","checked_at?"}],
 "policy_note?","log":[{"at","actor":"user|assistant|plugin:<id>","text"}]}
```

- The assistant creates it from a schedule item (kind 作业), courseware or the chat:
  - `requirements` quote the source with `look://` refs;
  - every checklist item has a concrete `verify` (what file or behaviour proves it).
- Tools (group `assignment`):
  - `create_assignment`, `read_assignment`, `update_checklist`, `list_assignment_files`, `read_assignment_file`;
  - `write_assignment_file {path, content}`: text only, ≤ 512 KB, relative path inside the folder, no `..`, no executable bit, at most 200 files;
  - `verify_assignment`: walks the checklist, reads the evidence files and sets `state` + `evidence` per item. It returns a summary; it never marks an item done without naming its evidence.
- lookd owns the folder (`/api/assignments…` routes, index table `assignments`, reindex from `assignment.json`) like notes and quizzes, and publishes `assignment_changed`.
- Plugins with `workspace` permission (for example the Codex delegate) work in the same folder through `look.assignment(id)`.
- Policy: an optional `policy_note` (the course's rule on AI help, entered by the user) shows on the assignment page and is passed to the assistant and plugins. Export adds an "AI 协助说明" section listing which actors wrote which files from the log.

### UI
- Assignment page, opened from a schedule item (开始作业), the course page (作业 section) or `open_page`:
  - header: title, course colour, due countdown and status segmented control;
  - 要求: requirements with source refs;
  - 验收清单: the `checklist` view. Items are tappable to toggle, with an evidence line; a progress ring sits in the header;
  - 文件: the `files` view. Open text files in the reader and reveal the folder.
  - Actions: 让助手起草, 验收, plus plugin actions (委派给 Codex).
- `checklist` view (shared with plugins), payload `{title?, items:[{id, text, state, evidence?}]}`. It renders as an MD3 list:
  - state icons: outline circle, check in primary, error in error;
  - a filled progress indicator at the top.
- Proposal cards (settings, task, plugin) use a filled tonal card with the change list and 应用 / 撤销, or 已应用 · 撤销 once applied.

## Plan
1. Agent:
   - core `open_page` and `highlight`;
   - `settings` group with the registry and `PUT /agent/app-state`;
   - proposal tools;
   - `assignment` group.
2. lookd: assignments store, files API with the path guards, reindex, events; both clients updated.
3. App:
   - starter chips;
   - navigation executor and anchor registry with the spotlight overlay;
   - proposal cards with apply/undo;
   - assignment page;
   - `checklist` and `files` views;
   - entry points from schedule and course pages.
4. `AGENTS.md` project rule and `overview.md` updated to the new write boundary.

## Verification
- `go test`:
  - assignment path guards (`..`, absolute, size, count);
  - reindex from `assignment.json`;
  - checklist update validation.
- `node --test`:
  - settings registry validation;
  - low-risk vs confirm split;
  - no secret key is readable or writable;
  - `verify_assignment` refuses `done` without evidence.
- Widget tests:
  - starter chips per screen;
  - `open_page` navigation and back chip;
  - spotlight on a registered anchor and the unknown-anchor error;
  - proposal apply/undo;
  - checklist toggling.
- Live: "怎么设置识图模型" opens 设置 → 助手 and highlights the picker. "字号调大一点" applies with 撤销. An assignment created from a schedule item gets a checklist, a drafted file and a verification pass.

## Evidence
Pending until implementation.
