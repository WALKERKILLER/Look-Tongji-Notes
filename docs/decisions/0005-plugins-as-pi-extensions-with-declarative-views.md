# Plugins load as Pi extensions and show declarative views

## Status
Accepted
Class: architecture

## Context and Problem Statement
Look Studio needs plugins that add assistant tools and interactive results (see [plugin platform spec](../specs/0004-plugin-platform.md)). Two choices shape everything else:
- where plugin code runs, and how it reaches the assistant;
- how a plugin's results appear in the Flutter app.

The agent host already embeds the Pi SDK. Pi supports inline extension factories, skill paths, deferred tools with namespaces, and MCP server registration through `DefaultResourceLoader`.

## Decision Drivers
- Reuse what the embedded agent runtime already does well (tool registry, deferred exposure, skills, lifecycle events).
- Keep tool schemas out of the context until needed (the current `find_tools` design).
- Plugin results must look native (Material 3, dynamic colour, dark mode, accessibility) on Linux, Windows, macOS and Android.
- Honest security: Node offers no practical in-process isolation, and Pi and dsh do not isolate plugins either.
- Small surface: plugin authors write one ES module and a manifest.

## Considered Options
- A. Plugins are Pi extensions (`default (pi, look)`, plus `activate(look)` for work outside conversations), loaded as inline factories, plus a Look API gated by declared permissions. Results are payloads for a catalog of app-implemented views.
- B. A Cordis-style runtime of our own (`apply(ctx)` with services and effects) beside Pi.
- C. Plugins are MCP servers only (stdio or HTTP), connected through Pi's MCP support.
- D. Each plugin in its own Node child process with the Node permission model, over JSON-RPC.
- E. Plugin UI as HTML in a WebView, or as Remote Flutter Widgets libraries shipped by the plugin.

## Decision Outcome
Chosen option: A. It reuses Pi's tool, skill and lifecycle machinery, so a Look plugin is close to a Pi package. The `look` API supplies Cordis-style cleanup (`look.effect`) without a second runtime. Version 1 blocks `pi.registerMcpServer` (and provider registration), so every outside connection a plugin makes goes through a declared permission; MCP can come back later behind a permission. Views come from a versioned catalog in the app, so every result renders natively and plugins ship no UI code.

### Consequences
- Good: one mechanism for core and plugin tools; plugin tools stay deferred until `find_tools` loads them; plugins work in scheduled task runs too.
- Good: views look native and are testable in Flutter; notes can embed them as data.
- Bad: plugins share the host process. A crash or a malicious plugin affects the assistant. Mitigations: consent, opt-in third-party installs, `--ignore-scripts`, no access to lookd settings or keys through the Look API.
- Bad: a plugin needing a new kind of view waits for an app release that adds it to the catalog.

## Pros and Cons of the Options
### A. Pi extensions + Look API + view catalog
- Good: smallest new runtime; follows Pi's documented extension contract and package layout.
- Bad: tied to Pi's extension API version; mitigated by the `engine` range.
### B. Own Cordis-style runtime
- Good: full control of services and hot reload.
- Bad: duplicates Pi's registry and lifecycle, and needs a second tool bridge into Pi sessions.
### C. MCP servers only
- Good: language-agnostic and process-isolated; an existing ecosystem.
- Bad: no access to Look views, settings forms or assignment workspaces without a parallel protocol. Every plugin is a process even when it is a single tool.
### D. Child process per plugin
- Good: crash isolation; the Node permission model can restrict the file system.
- Bad: network is not restricted, and a JSON-RPC bridge is needed for every API. Startup cost per plugin. It can be added later for third-party plugins without changing the manifest.
### E. WebView or Remote Flutter Widgets
- Good: plugins could add any UI.
- Bad: no maintained WebView on Linux desktop for Flutter. RFW needs a curated widget library anyway, which is the view catalog under another name, and it makes Material 3 consistency and accessibility the plugin's problem.

## Links
- Pi packages and extensions: `agent/node_modules/@earendil-works/pi-coding-agent/docs/packages.md`, `extensions.md`, `sdk.md` (version 1.0.0 as pinned in `agent/package.json`); https://pi.dev/packages
- Cordis lifecycle and effects: https://deepwiki.com/koishijs/docs/3.1-cordis-meta-framework ; DeepSeek Harness Cordis tutorial: https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/cordis-tutorial/index.md
- dsh plugin installation and trust model: https://www.ssdnodes.com/learn/dsh-plugins-safely
- Claude Code marketplaces: https://code.claude.com/docs/en/plugin-marketplaces
- Agent Client Protocol prompt turn: https://agentclientprotocol.com/protocol/prompt-turn
- Competitive Companion format: https://github.com/jmerle/competitive-companion
