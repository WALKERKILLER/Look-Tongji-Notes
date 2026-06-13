"""Lifecycle state machine for wiki pages (v1.0 · Sprint 1).

Implements the 5-state lifecycle from the LLM Book design spec
(08-quality-maintenance.md):

    draft → reviewed → verified
      ↓        ↓          ↓
    stale ← stale  ←   stale
      ↓
    archived

State definitions:
    draft     — Newly compiled, unreviewed.
    reviewed  — Lint passed, basic quality confirmed.
    verified  — High confidence (≥ 0.8), human-confirmed.
    stale     — May be outdated (90+ days no update, or source change).
    archived  — Kept for history, inactive (manual transition only).

Auto transitions:
    Created by LLM        → draft
    Basic lint passes      → reviewed
    Confidence drops < 0.5 → stale
    No update for 90 days  → stale  (auto-stale)

Manual transitions:
    Human reviews + approves → verified
    Human archives           → archived  (manual-only per decision #18)
"""

from __future__ import annotations

from datetime import datetime, timezone
from enum import Enum
from typing import Optional


class LifecycleState(str, Enum):
    """The five lifecycle states a wiki page can be in."""

    DRAFT = "draft"
    REVIEWED = "reviewed"
    VERIFIED = "verified"
    STALE = "stale"
    ARCHIVED = "archived"


# ─── Valid transitions ─────────────────────────────────────────────────

# Map from current state → set of allowed target states
_TRANSITIONS: dict[LifecycleState, set[LifecycleState]] = {
    LifecycleState.DRAFT: {
        LifecycleState.REVIEWED,
        LifecycleState.STALE,
    },
    LifecycleState.REVIEWED: {
        LifecycleState.VERIFIED,
        LifecycleState.STALE,
    },
    LifecycleState.VERIFIED: {
        LifecycleState.STALE,
    },
    LifecycleState.STALE: {
        LifecycleState.REVIEWED,  # re-verification
        LifecycleState.ARCHIVED,  # manual only
    },
    LifecycleState.ARCHIVED: {
        LifecycleState.REVIEWED,  # restoration (rare)
    },
}


class InvalidTransition(ValueError):
    """Raised when a lifecycle state transition is not allowed."""


def can_transition(current: LifecycleState, target: LifecycleState) -> bool:
    """Return True if the transition from *current* → *target* is valid."""
    return target in _TRANSITIONS.get(current, set())


def transition(
    current: LifecycleState,
    target: LifecycleState,
    *,
    reason: str = "",
) -> LifecycleState:
    """Attempt a state transition. Returns the new state or raises."""
    if not can_transition(current, target):
        raise InvalidTransition(
            f"Cannot transition from {current.value!r} to {target.value!r}"
            + (f": {reason}" if reason else "")
        )
    return target


# ─── Auto-transition checks ───────────────────────────────────────────

AUTO_STALE_DAYS = 90
"""Pages with no update for this many days are auto-transitioned to stale."""


def check_auto_stale(
    current: LifecycleState,
    last_updated: Optional[str],
    *,
    now: Optional[datetime] = None,
) -> Optional[LifecycleState]:
    """Check if a page should auto-transition to stale.

    Returns ``LifecycleState.STALE`` if the page is overdue, otherwise
    ``None`` (no transition needed).

    Only pages in draft, reviewed, or verified can auto-stale.
    Archived pages are already inactive.
    """
    if current in (LifecycleState.STALE, LifecycleState.ARCHIVED):
        return None

    if not last_updated:
        return LifecycleState.STALE  # no date → treat as stale

    try:
        dt = datetime.fromisoformat(last_updated)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
    except (ValueError, TypeError):
        return LifecycleState.STALE

    ref = now or datetime.now(timezone.utc)
    age_days = (ref - dt).days
    if age_days >= AUTO_STALE_DAYS:
        return LifecycleState.STALE
    return None


def check_confidence_stale(
    current: LifecycleState,
    confidence: float,
) -> Optional[LifecycleState]:
    """Auto-stale if confidence drops below 0.5."""
    if current in (LifecycleState.STALE, LifecycleState.ARCHIVED):
        return None
    if confidence < 0.5:
        return LifecycleState.STALE
    return None


def initial_state() -> LifecycleState:
    """The state assigned to newly created wiki pages."""
    return LifecycleState.DRAFT


# ─── Frontmatter helpers ──────────────────────────────────────────────

def parse_lifecycle(value: str) -> LifecycleState:
    """Parse a lifecycle string from YAML frontmatter.

    Accepts lowercase values like "draft", "reviewed", etc.
    Returns the corresponding LifecycleState or raises ValueError.
    """
    try:
        return LifecycleState(value.lower().strip())
    except ValueError:
        valid = ", ".join(s.value for s in LifecycleState)
        raise ValueError(
            f"Invalid lifecycle state {value!r}. Valid: {valid}"
        ) from None
