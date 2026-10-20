# A resident bot keeps Markdown memory files and operates the app through cards

## Status
Accepted
Class: architecture

## Context and Problem Statement
The assistant was a list of interchangeable chat threads that forgot everything between them, and it could only suggest buttons. Users asked for a resident bot that knows them and can do what they can do in the app, next to conversations bound to one course (see [resident bot spec](../specs/0007-resident-bot-and-course-agents.md)). Two choices shape it: how the bot remembers, and how it acts on the app without surprising the user.

## Decision Drivers
- The user can read, edit and delete everything the bot remembers, on their own machine.
- Memory stays small and stable in the prompt so provider caching keeps working, and it grows without filling the context.
- No new runtime dependency (no embedding model or vector store) in a desktop app with bring-your-own model keys.
- Actions that cost bandwidth or disk, delete files or change the assistant's behaviour must not happen without a user click; cheap reversible ones should not need one.
- Memory must never collect credentials or identity numbers, even when a transcript contains them.

## Considered Options
- A. Markdown files per topic (profile, preferences, routines, courses, notes), with hash-checked edit tools, the profile and preferences injected in full and the rest as an index, and a background consolidation run after idle time (RikkaHub's file memory and "dreaming").
- B. Automatically extracted typed memories (identity, workflow, voice, instructions) in a database, injected as a list (Kelivo).
- C. Embedding memory with retrieval per message.
- D. No persistent memory; rely on longer threads and compaction.
For acting on the app: (1) every operation runs at once; (2) every operation needs a card; (3) reversible, cheap operations run at once with undo, the rest become cards.

## Decision Outcome
Chosen options: A and (3). Files are inspectable and editable on the bot page, versioned by content hash so the bot and the user never overwrite each other blindly, and the pinned files give a stable prompt prefix. Consolidation runs as its own small session that may add and edit but not delete, with a content guard that refuses sensitive values. Operations record their undo, so a chip's 撤销 and a card's 应用 use one proposal store in the host, built from validated tool input only.

### Consequences
- Good: memory is plain text the user owns; course agents read the same profile and preferences without being able to change them.
- Good: the bot can change appearance, the player, courses and downloads at once and the user can undo; downloads and deletions still start from a user click.
- Bad: consolidation costs model calls in the background; it is capped (16 tool calls, 3 minutes, transcripts ≤ 24 000 characters) and can be switched off.
- Bad: the guard is pattern based and can miss unusual formats or refuse harmless numbers; the user can still edit files on the bot page.

## Pros and Cons of the Options
### A. Markdown files with consolidation
- Good: transparent, diff-able, works with any model; routines double as reusable procedures (Grok Bot's skills-to-routines idea).
- Bad: retrieval is by index and file reads, not semantic search.
### B. Typed automatic extraction
- Good: no tool calls during conversation.
- Bad: opaque rows, harder to correct; extraction after every message costs a model call each time.
### C. Embeddings
- Good: recall over large histories.
- Bad: needs an embedding provider or a local model, a vector store and re-indexing; results are hard for the user to inspect.
### D. No memory
- Good: nothing to manage.
- Bad: does not meet the request; long threads cost more per message and still forget across threads.
### Acting: (1) at once / (2) always a card / (3) by risk
- (1) is fast but violates the download and deletion rule; (2) is safe but makes "make the text bigger" tedious; (3) needs a risk table, kept in `agent/src/operate.mjs`.

## Links
- RikkaHub file memory and dreaming (PR 2130): https://github.com/rikkahub/rikkahub/pull/2130
- Kelivo memory extraction (AGPL; design only): https://github.com/chevey339/kelivo
- Grok Bot (persistent bots with identity, memory and routines): https://www.infoq.com/news/2026/08/grok-bot-agent/ ; https://www.memorylake.ai/en/blogs/grok-bot-per-bot-memory
- OpenAI dots (always-on agent with memory across threads): https://www.macstories.net/stories/openais-dots-a-first-look/
- Codex and Claude Code session models: https://www.morphllm.com/comparisons/codex-vs-claude-code
- Mascot morphing (MIT): https://github.com/jeremy-prt/bloub
