"""Look Tongji Notes — configuration.

This module is vendored from `tongji/backend/config.py`, but simplified for
the CLI-only skill. It loads environment variables from the skill root `.env`.
"""

from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv

# Skill root: <skill>/scripts/tongji_backend/config.py -> parents[2] == <skill>/
_SKILL_ROOT = Path(__file__).resolve().parents[2]
_ENV_PATH = Path(os.environ.get("LOOK_TONGJI_ENV_PATH", str(_SKILL_ROOT / ".env")))
if _ENV_PATH.is_file():
    load_dotenv(_ENV_PATH, override=False)

# ── Tongji Look platform ──
TONGJI_BASE_URL = os.environ.get("TONGJI_BASE_URL", "https://look.tongji.edu.cn")
TONGJI_TENANT_CODE = os.environ.get("TONGJI_TENANT_CODE", "222")
TONGJI_USERNAME = os.environ.get("TONGJI_USERNAME", "")
TONGJI_PASSWORD = os.environ.get("TONGJI_PASSWORD", "")

USER_AGENT = os.environ.get(
    "TONGJI_USER_AGENT",
    (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    ),
)

# ── ASR ──
ASR_ENGINE = os.environ.get("ASR_ENGINE", "bcut")
MAX_ASR_RETRIES = int(os.environ.get("MAX_ASR_RETRIES", "5"))
ASR_RETRY_BACKOFF = int(os.environ.get("ASR_RETRY_BACKOFF", "30"))
