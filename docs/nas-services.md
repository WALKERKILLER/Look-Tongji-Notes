# Optional NAS service adapter

The NAS page connects an existing personal deployment to Studio. It does not install workers or configure Syncthing. It is disabled until the daemon has an explicit SSH host; browsing the rest of Studio does not require a NAS.

Set these environment variables when starting `lookd`:

| Variable | Meaning |
|---|---|
| `LOOK_NAS_HOST` | Existing SSH host alias with a verified host key and noninteractive authentication |
| `LOOK_NAS_COURSES` | Absolute local path to synchronized semester material |
| `LOOK_NAS_CALENDAR` | Absolute local path to synchronized deadline JSON files |

Course files follow `<course>/<category>/<file>`, where categories include `1.课程总览`, `2.录课转写`, `3.课程资料` and `4.课程作业`. The [bridge](../lookd/internal/nasbridge/bridge.go) owns accepted types and bounds. The UI explicitly maps each NAS course to a Studio course; it does not infer identity from similar titles.

The remote [probe](../lookd/internal/nasbridge/probe.py) reads `~/.local/share/course-homework-worker` on the SSH account and expects `health.json`, `calendar-health.json` and `queue.sqlite3`. It observes the user services `course-homework` and `course-calendar-nightly`, and the containers `icourse-subscriber` and `course-calendar-sync`. This is a deployment-specific adapter, not a generic NAS protocol. Deployments with a different schema need a separate adapter; missing files or services are reported as unavailable.

The two manual buttons request the fixed homework or calendar service after confirmation. They do not pass model-supplied shell commands or unit names. Acknowledgement means the request was accepted, not that processing finished. Studio does not enforce the remote worker's batch size or submission policy: configure and verify that worker before enabling the integration. The assistant's NAS tools are read-only. Credentials, raw queue payloads and remote logs are not returned to the UI.

The [approved local contract](specs/0017-nas-learning-services.md) records the pilot deployment and its historical verification. Maintainer approval for upstream inclusion is separate from that local approval.
