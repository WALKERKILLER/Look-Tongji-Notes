<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-06-13 | Updated: 2026-06-13 -->

# llmwiki

## Purpose
Core Python package for the llmwiki project. Version 1.3.82.

## Key Files

| File | Description |
|------|-------------|
| `__init__.py` | Package root with lazy re-exports and version metadata |
| `__main__.py` | Module entry point |
| `_frontmatter.py` | Frontmatter parser (stdlib-only) |
| `_system_pages.py` | System page slugs and filenames |
| `adapter_config.py` | Adapter config validation |
| `backlinks.py` | Backlink injection |
| `build.py` | Static HTML site builder |
| `cache.py` | Prompt caching scaffolding |
| `candidates.py` | Candidate approval workflow |
| `categories.py` | Category page generator |
| `changelog_timeline.py` | Changelog and timeline renderer |
| `cli.py` | CLI entry point |
| `compare.py` | Entity comparison pages |
| `completion.py` | Shell completion generators |
| `confidence.py` | Confidence scoring for wiki pages |
| `config_schedule.py` | Schedule configuration |
| `context_md.py` | Folder-level context helpers |
| `convert.py` | Session transcript converter |
| `docs_pages.py` | Docs-site compiler |
| `exporters.py` | AI-consumable export formats |
| `freshness.py` | Content freshness badges |
| `graph.py` | Knowledge graph builder |
| `graphify_bridge.py` | Graphify integration bridge |
| `ingest_queue.py` | Ingest queue |
| `lifecycle.py` | Page lifecycle state machine |
| `link_checker.py` | Link checker |
| `log_reader.py` | Log parser |
| `manifest.py` | Build manifest |
| `models_page.py` | Models page rendering |
| `obsidian_output.py` | Obsidian vault export |
| `pipeline.py` | Pipeline orchestrator |
| `project_topics.py` | Project topic tags |
| `py.typed` | PEP 561 marker |
| `quarantine.py` | Convert error quarantine |
| `queue.py` | Back-compat shim |
| `references.py` | Reverse-reference index |
| `schema.py` | Entity schema |
| `search_facets.py` | Search facets |
| `search_tree.py` | Tree-aware search |
| `serve.py` | HTTP server |
| `skill_installer.py` | Skill installer |
| `tag_utils.py` | Tag parsing utilities |
| `tags.py` | Tag operations |
| `vault.py` | Vault-overlay mode |
| `viz_heatmap.py` | Activity heatmap |
| `viz_tokens.py` | Token visualizations |
| `viz_tools.py` | Tool bar chart |
| `watch.py` | File watcher |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `adapters/` | Session store adapters |
| `lint/` | Lint rules and runner |
| `mcp/` | MCP server |
| `render/` | CSS and JS assets |
| `sync/` | Sync status |
| `synth/` | LLM synthesis |

## For AI Agents

### Working In This Directory
- Core llmwiki Python package.
- Modules are loosely coupled by domain.

### Testing Requirements
- Tests in tests/ directory.
- Independently testable modules.

### Common Patterns
- Lazy imports.
- Stdlib-only.
- Frontmatter parsing.

## Dependencies

### Internal
- llmwiki.adapters
- llmwiki.lint
- llmwiki.synth
- llmwiki.render
- llmwiki.sync

### External
- markdown
- graphify
- ollama

<!-- MANUAL: -->
