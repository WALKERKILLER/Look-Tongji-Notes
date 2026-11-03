# Optional NAS service adapter

The NAS page connects an existing personal deployment to Studio. It does not install workers or configure the WebDAV course sync. It is disabled until the daemon has an explicit SSH host; browsing the rest of Studio does not require a NAS.

Set these environment variables when starting `lookd`:

| Variable | Meaning |
|---|---|
| `LOOK_NAS_HOST` | Existing SSH host alias with a verified host key and noninteractive authentication |
| `LOOK_NAS_COURSES` | Absolute local path to synchronized semester material |
| `LOOK_NAS_CALENDAR` | Absolute local path to synchronized deadline Markdown files |

Course files follow `<course>/<category>/<file>`, where categories include `1.课程总览`, `2.录课转写`, `3.课程资料` and `4.课程作业`. The [bridge](../lookd/internal/nasbridge/bridge.go) owns accepted types and bounds. The UI explicitly maps each NAS course to a Studio course; it does not infer identity from similar titles.

Deadline files are non-hidden `.md` files directly inside `LOOK_NAS_CALENDAR` (subdirectories and symlinks are skipped). Each file starts with `---` followed by a newline and has single-line frontmatter fields; `due` must be an RFC 3339 timestamp including its time zone. The reader accepts `title`, `course`, `due`, `completed` and `generated_key`; it is not a general YAML parser. Use a stable, unique `generated_key` to retain the deadline identity across renames; when absent, the filename determines the identity. Files without a valid `due` are skipped. JSON files are not read.

```markdown
---
title: "操作系统 · 实验一"
course: "操作系统"
due: "2026-11-10T23:59:00+08:00"
completed: false
generated_key: os-lab-1
---
https://elearning.fudan.edu.cn/courses/123/assignments/456
```

An optional Fudan eLearning assignment URL in the document supplies the course and assignment IDs. Keep deadline files below 64,000 bytes, the reader's input limit. Course material scans return an error when a directory cannot be listed or an entry cannot be statted; any accompanying list may be partial. File content read errors are reported when opening or reading the material.

The remote [probe](../lookd/internal/nasbridge/probe.py) reads `~/.local/share/course-homework-worker` on the SSH account and expects `health.json`, `calendar-health.json` and `queue.sqlite3`. It observes the user services `course-homework` and `course-calendar-nightly`, and the containers `icourse-subscriber` and `course-calendar-sync`. This is a deployment-specific adapter, not a generic NAS protocol. Deployments with a different schema need a separate adapter; missing files or services are reported as unavailable.

The two manual buttons request the fixed homework or calendar service after confirmation. They do not pass model-supplied shell commands or unit names. Acknowledgement means the request was accepted, not that processing finished. Studio does not enforce the remote worker's batch size or submission policy: configure and verify that worker before enabling the integration. The assistant's NAS tools are read-only. Credentials, raw queue payloads and remote logs are not returned to the UI.

The [approved local contract](specs/0017-nas-learning-services.md) records the pilot deployment and its historical verification. Maintainer approval for upstream inclusion is separate from that local approval.
