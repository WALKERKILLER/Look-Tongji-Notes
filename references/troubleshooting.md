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

## Workspace issues

- "Missing workspace root"
  - Meaning: the skill has not been initialized and no workspace env var was provided.
  - Fix: run `python "<SKILL_DIR>/scripts/look_tongji.py" setup`, or set `LOOK_TONGJI_WORKSPACE_ROOT`.
- Imported material has no useful Markdown
  - Meaning: MarkItDown could not extract text from that file.
  - Fix: install optional dependencies with `pip install -r "<SKILL_DIR>/requirements.txt"`, or provide a cleaner PDF/DOCX/PPTX source.
- Static site does not show new notes
  - Meaning: the agent has not written `<course_id>_<sub_id>_notes.md` yet, or the site was not rebuilt.
  - Fix: write the notes into the session raw-data folder, then run `python "<SKILL_DIR>/scripts/look_tongji.py" wiki`.
