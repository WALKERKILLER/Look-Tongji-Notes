"""Compatibility shim for the old course site builder entry points.

The actual site pipeline now reuses the vendored `llmwiki` package
directly through `index_workspace_wiki()`, `build_workspace_wiki()`,
and `serve_workspace_wiki()`.
"""

from __future__ import annotations

from pathlib import Path

from .workspace import (
    WorkspaceConfig,
    build_workspace_wiki,
    index_workspace_wiki,
    serve_workspace_wiki,
)


def index_site(config: WorkspaceConfig) -> list[Path]:
    """Compatibility wrapper for manifest -> llmwiki source indexing."""
    return index_workspace_wiki(config)


def build_site(config: WorkspaceConfig) -> Path:
    """Compatibility wrapper for building the reused llm-wiki site."""
    return build_workspace_wiki(config)


def serve_site(
    config: WorkspaceConfig,
    *,
    port: int = 8765,
    host: str = "127.0.0.1",
    open_browser: bool = False,
) -> int:
    """Compatibility wrapper for serving the reused llm-wiki site."""
    return serve_workspace_wiki(
        config,
        port=port,
        host=host,
        open_browser=open_browser,
    )
