# Security notes

## Credentials

- Credentials are stored in `<SKILL_DIR>/.env`.
- Do not commit `.env` to git. This skill includes `.gitignore` for it.
- Avoid pasting passwords into chat. Prefer interactive terminal input.

## Auth cache

- `<SKILL_DIR>/state/auth_session.json` may contain a JWT token.
- Treat JWT tokens like passwords. Keep the `state/` folder private.

## Output artifacts

- By default, the CLI writes transcripts, subtitles, slides, imported materials, and the generated site to the configured course wiki workspace.
- The workspace config is stored outside the skill folder so skill updates do not overwrite it.
- `LOOK_TONGJI_CONFIG_PATH` can override the config file location.
- `LOOK_TONGJI_WORKSPACE_ROOT` can override the workspace root for non-interactive runs.
- Transcripts may include personal information. Be careful before sharing them.
- Supplementary materials are copied into `raw/<course>/<session>/原始数据/materials/`.
  Only import files you are allowed to process locally.
- Do not commit `.env`, `state/`, JWT cache files, or private course materials to a public repository.
