# Plugin platform and marketplace

Artifact-Version: 1
Status: Implemented

## Intent
The assistant's abilities are fixed in `agent/src/tools.mjs`. Course-specific help (data-structure animations, sending problems to an IDE, delegating coursework to a coding agent) does not belong in the core, and users should choose what they enable. Outcome: Look Studio loads plugins that add assistant tools, playbooks and interactive views, and users browse, install, configure and remove them in a marketplace.

The design follows Pi packages (an npm/git/local package with resources declared in `package.json`), Cordis/DeepSeek Harness (`apply(ctx)` where everything a plugin registers is undone when it unloads) and Claude Code marketplaces (a JSON catalog listing plugins and their sources). See [decision 0005](../decisions/0005-plugins-as-pi-extensions-with-declarative-views.md).

Non-goals: isolating plugins from each other or from the user account (Pi and dsh do not either; see Security), plugin-supplied Flutter or HTML code, paid plugins, auto-update without consent.

## Contract

### Package
A plugin is a directory or npm/git package whose `package.json` has a `lookStudio` key:

```json
{
  "name": "@look-studio/ds-visualizer",
  "version": "1.0.0",
  "lookStudio": {
    "id": "ds-visualizer",
    "title": "数据结构可视化",
    "summary": "让助手用可交互的动画讲解数组、链表、树、图和堆",
    "icon": "account_tree",
    "categories": ["visualize", "programming"],
    "engine": "^1.0.0",
    "agent": "./agent.mjs",
    "skills": ["./skills"],
    "views": ["structure"],
    "permissions": ["views"],
    "settings": { "type": "object", "properties": { "speed": { "type": "number", "title": "播放速度", "default": 1, "minimum": 0.25, "maximum": 4 } } },
    "examples": ["用动画演示在 BST 里删除一个有两个孩子的节点"]
  }
}
```

- `id`: `[a-z][a-z0-9-]{1,31}`, unique, not `catalog`, `catalogs`, `install` or `third-party` (route names); tool names a plugin registers are prefixed `<id>__` by the host.
- `title` (≤ 24 chars), `summary` (≤ 80), optional `description` (≤ 2000), `icon` (a Material icon name from the app's list in `app/lib/core/plugins.dart`, else a puzzle piece), `categories` (`notes`, `visualize`, `review`, `programming`, `connector`, `tutor`, `assignment`), `examples` (≤ 6 prompts).
- `engine`: semver range of the plugin API (`PLUGIN_API_VERSION`, starts at 1.0.0); out of range → not loadable, shown as incompatible.
- `agent`: an ES module with two optional exports. `activate(look)` runs once each time the plugin loads; it registers actions and starts background work. `default function (pi, look)` is a Pi extension factory and runs for every new conversation, because Pi binds an extension runtime to one session; it registers tools and hooks and has no other side effects. `pi` is Pi's `ExtensionAPI` with `registerProvider`, `registerVirtualModel`, `registerMcpServer`, `setModel`, `setThinkingLevel` and `setActiveTools` blocked; `look` is the Look API below. A plugin can also be skills and views only.
- `skills`: directories holding `SKILL.md` (or the files themselves). Look has no file-reading tool, so the host does not list them like Pi skills: `find_tools` returns a plugin's skills as the playbook when the model loads the `plugin:<id>` group.
- `views`: names from the host's view catalog the plugin's tools may return (see Views).
- `permissions`: subset of the table below; the host refuses calls outside them.
- `exec` (commands) and `hosts` (domain names): required by the `exec` and `network` permissions.
- `settings`: JSON Schema subset (object of string, number, integer, boolean, enum, and arrays of string/number/integer; `title`, `description`, `default`, `minimum`, `maximum`, `format: "port" | "path"`) rendered as a form. Version 1 has no secret settings: a manifest with `secret: true` is rejected (sealed secrets in lookd are future work).
- `contributes`: see Contribution points.

### Permissions
| Permission | Grants (`look.*`) | Shown to the user as |
| --- | --- | --- |
| `library.read` | read courses, lectures, transcripts, notes, courseware via lookd | 读取课程资料 |
| `library.write` | save notes, quizzes, schedule marks (same guards as core tools) | 写入笔记、练习和日程 |
| `views` | return interactive views in chat and notes | 在对话中显示交互视图 |
| `localhost` | HTTP to `127.0.0.1` ports listed in `settings` (`format: port`) | 连接本机程序 |
| `exec` | spawn executables named in `lookStudio.exec` (absolute path or name on `PATH`) | 启动本机程序 |
| `workspace` | read/write files under a plugin workspace inside the library (`<library>/workspaces/<plugin>/…`) | 在课程库中创建工作目录 |
| `network` | fetch from hosts listed in `lookStudio.hosts` | 访问网络：<hosts> |
| `folder` | read/write inside a folder the user picks in the plugin's settings (`format: path`) | 读写你选择的文件夹 |

`look` API (calls outside the granted permissions throw):
- `look.lookd.get(path)`: `library.read`; GET on courses, a course's lectures, a lecture with its slides list, transcript, timeline and courseware (text, search), recent, search, notes, activity (and a day), quizzes, schedule. Media and slide images are not readable.
- `look.lookd.post/put/patch/delete(path, body)`: `library.write`; exactly PUT `/api/notes`, DELETE `/api/notes/{id}`, POST `/api/quizzes`, DELETE `/api/quizzes/{id}`, POST `/api/quizzes/{id}/attempts`, POST `/api/schedule`, PATCH and DELETE `/api/schedule/{id}`, PUT and DELETE `/api/lectures/{id}/timeline`, POST `/api/lectures/{id}/bookmarks`.
- Paths are checked as sent and must already be normal: a method's exact route list (each `{id}` one non-empty segment), no `.` or `..` segments, no `%2e`, `%2f` or `%5c` in the path, no backslash, `#`, whitespace or control characters, no empty segments, and the same path after URL parsing; anything else is refused before it reaches lookd.
- `look.view(kind, data, text?)`: `views`; a declared kind, data ≤ 256 KB; returns a tool result whose `details.view` the app renders.
- `look.action(name, handler)`, `look.effect(dispose)` (Cordis-style cleanup, run on reload, disable, uninstall and shutdown), `look.status(value)` (small public state, e.g. `{active: true}` for a composer mode, sent to the app).
- `look.settings()`, `look.storage.get/set/dir` (JSON in `<agent data>/plugins/data/<id>/`, 0600).
- `look.workspace(name)`: `workspace`. `look.folder(key)`: `folder`, the path setting `key`. `look.inside(base, rel)` resolves a path refusing escapes.
- `look.spawn(cmd, args, opts)`: `exec`, a declared command, no shell, `LOOKD_TOKEN` cleared, killed on cleanup.
- `look.fetch(url)`: `localhost` for 127.0.0.1/localhost ports found in port settings, `network` for declared hosts.
- `look.notify(text)` (app snackbar) and `look.emit(data)`: `plugin_event` on lookd's event bus.

### Lifecycle
- State in `<agent data>/plugins.json` (mode 0600): `allow_third_party`, user `catalogs`, and per plugin `{source, version, official, enabled, granted:[…], settings}`; third-party copies under `<agent data>/plugins/pkgs/<id>/` (directory 0700). Official plugins load from the bundled directory.
- Install: fetch the source into a staging directory → validate `package.json` → the preview returns the manifest and a token → the app shows consent (permissions, publisher, source) → confirm moves the copy in, running `npm install --omit=dev --ignore-scripts` when it has dependencies, and records it. Previews expire after 10 minutes. Granted permissions are exactly those consented. A plugin whose package on disk asks for more stays unloaded (`needs_consent`) until the user grants them.
- Enable/disable/settings change reload the plugins and close idle conversations, so the next message opens a conversation with the new set; a running conversation keeps its tools until it ends (Pi sessions cannot drop extensions mid-run). A reload runs every `look.effect` cleanup first.
- Load failures (syntax, engine, missing dependency) mark the plugin `error` with the message; the core assistant always starts.
- Uninstall removes the package and its storage; workspaces and library content it produced stay.

### Marketplace
- Catalogs: the bundled official catalog (`agent/plugins/catalog.json`: `{name, owner, plugins:[{source: <dir>, featured?}]}`, plugins under `agent/plugins/<id>/`, shipped with the agent) and user-added catalogs (HTTPS URL, or `owner/repo` for `look-catalog.json` on its default branch): `{name, owner, plugins:[{id, source, version, title, summary, icon, categories, author}]}`. `source` is `npm:<pkg>@<exact version>`, `git:<https url>#<ref>` or `path:<absolute dir>`. A user catalog is read as a stream and refused (reported in `errors`) past 1 MB; only its first 500 entries are listed.
- Only the bundled catalog may mark plugins `official`. Third-party installs are off until 插件 → 来源 → 允许第三方插件 is on, and their consent dialog states that plugin code runs with the assistant's permissions.

### Agent integration
- Plugin tools register with `exposure: "deferred"` and the plugin's `namespace`; `find_tools` lists loaded plugins as groups `plugin:<id>` (label = title, words from summary and categories) next to the core groups, so their schemas cost no context until loaded. Loading a group returns its tools and its skills as the playbook.
- The system prompt gains one line per loaded plugin (title, summary, and its group) so the model knows they exist.
- Hooks (`pi.on`) see every turn of every conversation; `before_agent_start` may extend that turn's system prompt.
- Every plugin tool goes through the core `guard` (turn budget, result cap) and is recorded in the usage ledger like core tools.

### Views
Plugins never ship UI code. They return payloads for views the app implements (`details.view = {kind, version, plugin, data}`); unknown kinds render as a card saying the app needs an update, with the data expandable. This spec ships the registry and `checklist` (`{title?, items:[{text, done?, note?}]}`, a progress header and the items). Other view contracts live in the specs that introduce them:
- `checklist` and `files`: the agent-operator spec.
- `mindmap`, `graph`, `diagram`, `chart`, `plot`, `steps`, `flashcards`, `structure`, `problem` and `run-log`: the official plugins spec.

A note or reply can embed a view as a fenced block ` ```look-view ` holding `{kind, data}`. The chat renders it while an active plugin lists the kind in `contributes.blocks`, and otherwise shows the code. Notes will render these blocks when the first plugin that writes them ships (the official plugins spec).

### Contribution points
Besides tools and skills, the manifest's `contributes` declares where a plugin appears outside the chat. Each entry names an `action` the plugin's agent module registers with `look.action(name, handler)`. The app calls the action as `POST /agent/plugins/{id}/actions/{name} {context}`; `context` holds the ids of what the user is looking at. The handler returns one of:
- `{view: {kind, data, title?}}` (shown in a sheet; may carry a `toast`);
- `{prompt}` (sent to the assistant; from the composer it goes into the current chat);
- `{toast, state?}` (`state` also becomes the plugin's status);
- `{open: <look:// reference or https URL>}`.

A handler is called as `handler(context, {signal})` and times out after 60 s (504). On timeout the signal aborts, the plugin's `look.fetch` requests are cancelled, and `look` calls made afterwards from that handler (lookd, fetch, storage writes, spawn, notify, emit, status) are refused, so a timed-out action has no further side effects.

| Point | Where it shows | Example |
| --- | --- | --- |
| `noteViews` | the note toolbar's plugin menu, under 换种方式看; the handler gets the note and returns a view | 思维导图 |
| `actions` with `surface` | `note.toolbar`, `lecture.menu`, `course.menu`, `schedule.item`, `assignment.actions`, `composer.plus` | 生成知识地图, 委派给 Codex |
| `exporters` | 导出 menus of a note, a course or the library; the handler writes files with `folder` or `workspace` | Obsidian, Anki, 日历 |
| `pages` | chips on the plugin's detail page, opening the returned view | 闪卡复习 |
| `blocks` | lets the model write ` ```look-view ` blocks of the plugin's views into notes (the note playbook lists them) | 图表, 推导步骤 |

Actions run without a model call unless they return `{prompt}`. That keeps visualisations of existing notes instant and free. The menus show only when an active plugin contributes to them. Composer toggles whose status is `{active: true}` show as removable chips above the input.

### API (agent host, via `/agent/…`)
- `GET /plugins` → `{plugins, allow_third_party}`: installed plugins, each with `state` (`enabled`, `disabled`, `error`, `needs_consent`), `error`, `needs_permissions`, `tools`, `skills`, `status`, `settings_values`.
- `GET /plugins/catalog` → `{plugins, catalogs, errors, allow_third_party}`: merged catalogs with `installed` and `update`.
- `POST /plugins/install {source}` → `{token, official, source, manifest, update}` preview. `POST /plugins/install/confirm {token}`.
- `PUT /plugins/{id} {enabled?, settings?, grant?}`. `DELETE /plugins/{id}`.
- `PUT /plugins/third-party {allow}`. `POST /plugins/catalogs {url}`. `POST /plugins/catalogs/remove {url}`.
- `POST /plugins/{id}/actions/{name} {context}`.
- Errors → 400/403/404/409/410/502/504 with a Chinese message.

lookd relays `plugin_event` (`{plugin, kind: notify | status | update, …}`, ≤ 64 KB) from the agent host through `POST /api/agent/event` to `/api/events`.

### UI (rail destination 插件)
- Navigation: rail destination 插件 between 定时 and 设置, with a badge counting plugins that need attention (需要授权 or 出错). Phones leave it off the bottom bar; 设置 → 插件 (已安装的插件, 发现插件) and the composer's "+" menu (发现插件, 管理插件) open the tab on the matching view, closing the assistant first.
- Header: title, a summary line (installed, enabled, needing attention, updatable), a 发现 / 已安装 segmented button, and a 来源 menu: 允许第三方插件 (with a confirmation), 插件目录…, 从文件夹、npm 或 Git 安装… (both need third-party plugins on), 刷新.
- 发现: a search bar, category filter chips, a featured hero (a carousel when several are featured), then one section per catalog (Look Studio 官方 first, then each added catalog by name) of cards: tonal icon tile, title, publisher, summary, categories, 安装 / 已安装 / 更新. A failed catalog shows a banner; with third-party plugins off, a closing banner offers to allow them. On windows ≥ 880 px a card opens the plugin in a closable side pane; narrower windows push a detail page.
- 已安装: plugins grouped 需要处理 / 已启用 / 已停用. On windows ≥ 880 px a selectable list sits beside the selected plugin's detail in a tonal pane; narrower windows show cards with an enable switch (none while consent is pending) that push the detail page.
- Detail (pane or page): icon, title, state pill, publisher and version (and the available version), enable switch; actions 安装, 查看并授权, 更新, the plugin's pages, 卸载, 主页; load error; description; 试试这样问 (example prompts as chips that open the assistant once enabled); sections 助手获得的能力 (tools and skills), 会出现在, 权限, 设置 (the form from the schema); license and source.
- Consent dialog lists permissions with icons (sensitive ones emphasized, new ones marked 新增); third-party sources show the warning in a tertiary-container banner.
- Card grid columns follow the available width (one to four).

### Security
Plugins run in the agent host process with the user's OS permissions; the permission list gates the `look` API and is a statement of intent, not a sandbox (as in Pi and dsh). Mitigations: official plugins are reviewed in this repository; third-party installs are opt-in with consent, pinned versions, `--ignore-scripts`; plugins cannot read lookd settings, auth or provider keys through the `look` API and spawned commands do not inherit `LOOKD_TOKEN`; plugins cannot start downloads. Scheduled task runs (spec 0003) may only call tools of plugins whose permissions are all read-only (`library.read`, `views`); tools of any other plugin are refused in a run, whatever the task's `writes`. Inside a run those tools also cannot write the plugin's own storage (`look.storage.set` and `look.storage.dir` throw), so a run leaves no persistent plugin state.

## Plan
1. Agent:
   - `plugins.mjs`: manifest validation, state, install/uninstall, catalogs;
   - per conversation, a `DefaultResourceLoader` with one inline extension per loaded plugin;
   - Look API with permission checks;
   - actions and contribution points;
   - `find_tools` groups (with skills as playbooks) and routes;
   - the first official plugin, 引导式提问 (`socratic`).
2. lookd: relay `plugin_event`.
3. App:
   - the 插件 tab (发现, 已安装, detail pane or page), consent dialog, settings form from the schema;
   - view registry with the `checklist` view, and `look-view` blocks in `LookMarkdown`;
   - the contribution points: note view switcher, surface menus, export menus, plugin pages.
4. Docs: architecture (plugin seam), overview, a plugin author guide in [agent/plugins/README.md](../../agent/plugins/README.md).

## Verification
- `node --test agent/src/plugins.test.mjs`: manifest validation (id, engine, permissions, settings schema), install from a local fixture, consent required for added permissions, tool prefixing and deferred exposure, permission refusal, load error isolation, effects run on disable.
- Widget tests: contributions of active plugins only, checklist and unknown view fallback, `look-view` blocks only for declared kinds, consent dialog, settings form validation and round trip, the 插件 tab on wide and narrow windows.
- `go test ./internal/server`: event types and size limit.
- Live: install the official fixture plugin, its tool appears in `find_tools`, disable removes it from new conversations.

## Evidence
- Agent: [plugins.mjs](../../agent/src/plugins.mjs) with [plugins.test.mjs](../../agent/src/plugins.test.mjs): manifest validation (id and reserved names, engine, permissions, exec and network declarations, views, paths, secret settings, surfaces); settings defaults and ranges; install, 0600 state, tools prefixed, deferred and namespaced through Pi's real `DefaultResourceLoader`; groups with skills as playbook; actions and undeclared views refused; `look.lookd` refusing a route outside the allow-list, and paths with dot segments (plain or encoded), encoded slashes, backslashes, empty segments or a method off the route list; user catalogs stopped past 1 MB and cut to 500 entries; scheduled runs refused tools of plugins with side-effect permissions and storage writes from read-only ones; tool calls counted against the conversation budget; a failing plugin isolated and cleanups run on disable; the third-party opt-in, consent for added permissions and official ids reserved; a timed-out action aborted with its later `look` calls refused; `close()` running every cleanup (the host awaits it on SIGINT/SIGTERM, within 3 s); the bundled catalog valid; the socratic mode extending the system prompt. Wiring in [host.mjs](../../agent/src/host.mjs) and plugin groups in [tools.mjs](../../agent/src/tools.mjs).
- lookd: `plugin_event` relay in [agent_event.go](../../lookd/internal/server/agent_event.go) with [agent_event_test.go](../../lookd/internal/server/agent_event_test.go).
- App: [plugins.dart](../../app/lib/core/plugins.dart), [plugins_page.dart](../../app/lib/features/plugins/plugins_page.dart), [plugin_views.dart](../../app/lib/features/plugins/plugin_views.dart), rail destination in [shell.dart](../../app/lib/shell.dart); [plugins_test.dart](../../app/test/plugins_test.dart) (contributions of active plugins only, checklist and unknown views, `look-view` blocks only for declared kinds, consent dialog, settings form; the 插件 tab: summary line, catalog sections, side pane open and closed, 已安装 groups with the plugin needing consent selected first, enable switch only in the pane, and on a narrow window switch cards that push the detail page).
- Official plugin and guide: [socratic](../../agent/plugins/socratic/package.json), [author guide](../../agent/plugins/README.md).
- Live check (2026-10-16, release build): the catalog listed 引导式提问 as official and featured; preview and confirm installed it with its skill; its toggle answered with a toast and lookd's event stream carried the `plugin_event` status; a folder install was refused until 允许第三方插件 was on; the author guide's example, installed from a folder, loaded with its tool and skill; in a chat turn `find_tools` loaded `plugin:hello` with the skill as playbook and `hello__lectures` returned a `checklist` view built from lookd, with the socratic hook active; `plugins.json` was 0600 and `plugins/` 0700; a non-plugin event type returned 400. The test conversation and plugins were removed afterwards and the third-party switch turned off. After the 插件 tab redesign the release build started with lookd and the agent host, and `/agent/plugins` and `/agent/plugins/catalog`, which the tab reads, answered.
- Not verified: npm and Git sources and user catalogs against the network (validation unit-tested), the surface menus with a plugin that contributes to them (no official plugin does yet), and the screens' look.
