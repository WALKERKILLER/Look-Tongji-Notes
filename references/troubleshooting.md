# Troubleshooting

## Setup / dependencies

If `setup` reports missing dependencies:

- Python deps:
  - `pip install -r "<SKILL_DIR>/requirements.txt"`
- Playwright browser:
  - `python -m playwright install chromium`
- `ffmpeg` not found:
  - Install ffmpeg and make sure `ffmpeg` is available in `PATH`.

## Login issues (Tongji IAM)

Common errors:

- "Playwright is required for Tongji SSO login"
  - Fix: install requirements, then install Chromium (see above).
- "IAM login form not found on page"
  - Cause: the SSO page changed and the selectors in `scripts/tongji_backend/auth.py`
    no longer match.
  - Fix: update the selectors (`#j_username`, `#j_password`, `#loginButton`) based on
    the current login page HTML.

## Auth cache issues

If cached JWT expires, the CLI will login again automatically.

If you want to force a fresh login:

- `python "<SKILL_DIR>/scripts/look_tongji.py" list --force-login`
- `python "<SKILL_DIR>/scripts/look_tongji.py" note ... --force-login`

## Transcription issues (ASR / ffmpeg)

- "No audio stream"
  - Meaning: the media stream has no audio track. This lecture cannot be transcribed.
- "ASR task timed out"
  - Meaning: the ASR service did not return results in time.
  - Fix: retry later, or retry multiple times (network / service instability happens).
