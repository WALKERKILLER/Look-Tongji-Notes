# Security notes

## Credentials

- Credentials are stored in `<SKILL_DIR>/.env`.
- Do not commit `.env` to git. This skill includes `.gitignore` for it.
- Avoid pasting passwords into chat. Prefer interactive terminal input.

## Auth cache

- `<SKILL_DIR>/state/auth_session.json` may contain a JWT token.
- Treat JWT tokens like passwords. Keep the `state/` folder private.

## Output artifacts

- The CLI writes transcripts and subtitles to `./tongji-output/` under your current working directory.
- Transcripts may include personal information. Be careful before sharing them.
