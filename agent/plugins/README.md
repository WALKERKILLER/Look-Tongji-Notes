# Writing a Look Studio plugin

This guide walks through a plugin from an empty folder to an installed, working plugin. The full contract (manifest fields, permissions, the `look` API, routes) is [spec 0004](../../docs/specs/0004-plugin-platform.md); this folder holds the official plugins and their [catalog](catalog.json).

## 1. The manifest

A plugin is a folder with a `package.json` that has a `lookStudio` key:

```json
{
	"name": "look-plugin-hello",
	"version": "1.0.0",
	"type": "module",
	"license": "MIT",
	"author": "you",
	"lookStudio": {
		"id": "hello",
		"title": "你好",
		"summary": "一个最小的示例插件",
		"icon": "lightbulb",
		"categories": ["tutor"],
		"engine": "^1.0.0",
		"agent": "index.mjs",
		"skills": ["skills"],
		"views": ["checklist"],
		"permissions": ["views", "library.read"],
		"examples": ["用你好插件列出这门课的节次"],
		"contributes": {
			"actions": [{ "id": "hi", "title": "打个招呼", "icon": "lightbulb", "surface": "composer.plus", "action": "hi" }]
		}
	}
}
```

Ask only for the permissions you use; the user sees every one before installing, and calls outside them throw.

## 2. The agent module

`index.mjs` may export `activate(look)`, which runs once when the plugin loads, and a default function, which runs for every new conversation:

```js
export function activate(look) {
	look.action("hi", async () => ({ toast: "你好！" }));
}

export default function (pi, look) {
	pi.registerTool({
		name: "lectures",
		label: "列出节次",
		description: "List the lectures of a course as a checklist.",
		parameters: { type: "object", properties: { course_id: { type: "string" } }, required: ["course_id"] },
		execute: async (_id, { course_id }) => {
			const { lectures } = await look.lookd.get(`/api/courses/${encodeURIComponent(course_id)}/lectures`);
			const items = lectures.map((l) => ({ text: `${l.date} ${l.title}`, done: l.assets.includes("transcript") }));
			return look.view("checklist", { title: "已转写的节次", items });
		},
	});
}
```

- The host prefixes tool names with your id (`hello__lectures`) and keeps them out of the model's context until it loads the group `plugin:hello` with `find_tools`. Write descriptions in English, first sentence first: that sentence is what `find_tools` shows.
- `pi` is Pi's extension API. Hooks such as `pi.on("before_agent_start", …)` work; registering providers, models or MCP servers is blocked.
- Keep the default function free of side effects: it runs once per conversation and once when the plugin loads, to learn its tools. Start background work in `activate` and register its cleanup with `look.effect(() => …)`.
- Tool results go through the same per-turn budget and size cap as the built-in tools.

## 3. Skills

Each folder under `skills/` with a `SKILL.md` (front matter `name`, `description`) becomes part of the playbook `find_tools` returns for your group. Use it for the workflow the model should follow with your tools.

## 4. Views

Return views with `look.view(kind, data)` from tools, or `{view: {kind, data, title}}` from actions. The app draws them; plugins never ship UI code. A kind must be listed in `views`, and the app must know it (`checklist` today; the [official plugins spec](../../docs/specs/0006-official-plugins.md) adds more). Unknown kinds show a card asking the user to update the app.

## 5. Try it

1. 设置 → 插件 → 允许第三方插件.
2. 从其他来源安装 → 文件夹 → choose your plugin folder; check the permissions and install.
3. The plugin's card shows 出错 with the message if it failed to load. After editing, toggle it off and on to reload.
4. Ask the assistant something from your `examples`; the tool chip in the chat shows your plugin's title and the tool label.

## 6. Publish

Publish to npm or a Git tag, then list it in a `look-catalog.json` that users add under 插件 → 插件目录:

```json
{
	"name": "my-plugins",
	"owner": { "name": "you" },
	"plugins": [{ "id": "hello", "version": "1.0.0", "title": "你好", "summary": "一个最小的示例插件", "icon": "lightbulb", "categories": ["tutor"], "source": "npm:look-plugin-hello@1.0.0" }]
}
```

Sources must name an exact version (`npm:<name>@1.0.0`, `git:https://…#v1.0.0`). Installs run `npm install --omit=dev --ignore-scripts`, so do not rely on install scripts.
