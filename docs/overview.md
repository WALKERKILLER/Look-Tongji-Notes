# Look Studio — overview

A Material 3 desktop/mobile client for Tongji's lecture-recording platform (look.tongji.edu.cn), built on the Look-Tongji-Notes skill.

## Architecture

```
app/    Flutter UI (MD3, media_kit player, gpt_markdown streaming rendering)
  └─ starts lookd and talks to it over 127.0.0.1 + token
lookd/  Go daemon: IAM login and auto-renewal, Look API, segmented downloader, transcription, SQLite index, SSE events
  └─ supervises agent/
agent/  Node.js host for the embedded Pi Agent (@earendil-works/pi-coding-agent SDK), exposed under /agent/*
```

- Login: plain-HTTP IAM SSO, no browser needed. The JWT is renewed at about 80% of its lifetime: silent SSO first, then the password sealed with AES-GCM on this machine.
- Downloads: preallocated `.part` file, multiple connections with work stealing, resume from checkpoint, automatic re-signing on 401/403/410, and a global speed limit.
- The assistant reads courses, transcripts, notes and courseware, and offers clickable action buttons; downloads always start from a user click. Its writes are limited to notes, schedule marks and outlines. Only a small core tool set is declared up front; `find_tools` loads the other groups (course, notes, schedule, outline, courseware, help) on demand. Each turn is capped at 24 tool calls, and tool results at 16 000 characters.
- Notes: when asked to write lecture notes the assistant loads the notes toolkit, which returns a playbook: read the whole transcript first (saving a lecture note is refused while more than 10% of it is unread), collect key points and uncertain spots, look at the slides on screen at those moments (`view_slides`), search and read the parsed courseware and its figures (`search_courseware`, `view_images`), then save a new note. It never overwrites the user's own notes, and replaces one of its own only with `replace: true` when the user asked for it. Images go straight to a chat model that accepts them; for text-only models a vision model chosen in 设置 → 助手 → 识图模型 transcribes them (cached by image hash in `agent/vision-cache.json`). lookd serves any slide at `/api/lectures/{id}/slides/{idx}/image` (downloaded file or the platform image) and searches courseware at `/api/lectures/{id}/courseware/search`.
- Reading: notes open in a reader with contents (tracks the section being read), reading progress and in-document search; timestamps, `look://slide/…` and `look://courseware/…` references open the recording moment (slide on screen plus transcript), the slide or the courseware passage in a supporting pane (a bottom sheet on narrow windows). Parsed courseware uses the same reader. Markdown everywhere goes through one renderer (`app/lib/widgets/look_markdown.dart`): `$…$`, `$$…$$`, `\(…\)`, `\[…\]`, bare `\begin{aligned}` blocks and `$ x $` are normalized outside code, inline math is set at text size, wide display math scrolls.
- Schedule (日程): homework, exams, activities, deadlines and to-dos with a month calendar and an agenda. The assistant's `mark_schedule` only creates an item when the source states a date, and the quoted words must be found in the transcript (near the given time), the user's message, courseware or a note. Agent marks are deduplicated by title, date and course. Items are stored in the `schedule` table and mirrored to `<library>/schedule.json`; marks with a time show up in the transcript and as dots on the seek bar.
- Outline (大纲): the assistant splits a lecture into chapters (`POST /agent/timeline`, a single model call over a digest of the transcript) in the original skill's `timeline.txt` format (`MM:SS-MM:SS：标题`). lookd normalizes the chapters (contiguous, covering the whole duration), writes `timeline.txt` and the `timeline` table, and includes `<course>_timeline.txt` in exports. The player shows chapters in a 大纲 tab, as transcript headers and as seek-bar segments.
- Courseware (课件): Look provides none, so files are uploaded per lecture (player → 资料 → 课件; PDF, Office documents and images, up to 200 MB) into `courseware/`. A `parse` job sends them to MinerU: precise API v4 (`/api/v4/file-urls/batch`, VLM or pipeline model) when a token is set, otherwise the token-free agent API (10 MB / 20 pages, no images). Results are unpacked to `courseware/<file>.parsed/` (`full.md`, `images/`). The token is sealed with the same key as the session and only its last 4 characters are ever returned; daily page usage is counted locally against the 1000-page high-priority quota (设置 → 课件解析). MinerU icon: `app/assets/brands/NOTICE`.
- Storage: Downloads → "已下载" lists files per lecture and kind and deletes them (`DELETE /api/lectures/{id}/assets/{kind}`); finished tasks can be removed with their files. With "转写完成后删除视频" (`transcript.delete_video`), the lecture's video is deleted as soon as its transcript is saved.
- Models: preset providers (logos from `@lobehub/icons-static-svg`, MIT, see `app/assets/providers/NOTICE`), model lists pulled from the provider's `/models`, and context/price metadata from models.dev (cached 24 h in `agent/models-dev.json`).
- Profile: nickname and avatar (emoji, generated shape, image file, image URL or QQ avatar; circle/squircle/cookie/petal outline) are device-local, kept in shared preferences with copied image files under the app support directory's `avatar/`. The home greeting shows them with a line from hitokoto.cn (一言), cached for offline use.
- Transcription: free cloud ASR over two channels, Bilibili 必剪 (bcut) and 剪映 (JianYing; protocol per VideoCaptioner, requests signed by VideoCaptioner's public signing service). Audio is cut into 20-minute chunks with 15 s overlap and spread over enabled channels (必剪 at most 2 chunks at a time, 剪映 1; requests are paced and each step retried with backoff, status polling gives up after repeated errors). A failing channel cools down (1 → 15 min for rate limits) while others take over; finished chunks are kept for 6 h so a retried job only redoes the missing ones, and a job fails with a clear message after 20 min with every channel cooling. Each channel is capped at 6 h of audio per 12 h; usage and the last 40 chunk attempts are in `asr-usage.json` and shown under 设置 → 转写 → 最近识别记录. ASR uses its own HTTP/1.1 transport, separate from the Tongji session.
- Timestamps such as `[07:58]` or `[07:58]–[10:22]` in notes and chat render as chips that seek the open player or open the lecture (`look://lecture/<id>?t=<s>` for other lectures).

## Build

Build and run instructions for each platform are in the [README](../README.md#build-from-source). ffmpeg is needed for transcription, and Node.js for the assistant.

## Data

| Location | Contents |
| --- | --- |
| `~/LookStudio/` | Course library: one folder per lecture (`video.mp4`, `slides/`, `courseware/` with `*.parsed/full.md`, `transcript.md/.srt`, `timeline.txt`, `lecture.json`), `notes/*.md`, `schedule.json`, and a `README.md` for AI tools |
| `~/LookStudio/library.db` | SQLite (WAL + FTS5 trigram) index; can be rebuilt from the files under Library → "Rebuild index from files" |
| `~/.local/share/look-studio/` | `session.json` (login state), `seal.key`, `asr-usage.json`, `mineru.json` (sealed token, options, parse usage), `agent/` (model config, keys, conversations, `models-dev.json` cache, `provider-links.json`) |

Settings → Course library can export to the skill's `raw/<course>/<lecture>/原始数据/` layout using hard links.

Settings → Course library → Obsidian exports the library into a folder of an Obsidian vault as plain Markdown (course and lecture pages, notes with properties, transcripts, linked slides and courseware), on demand or automatically after notes change (`POST /api/library/obsidian`). Links become relative Markdown links and timestamps `lookstudio://lecture/<id>?t=<s>` deep links that open the app; files edited in the vault are never overwritten (the new version goes beside them as `(Look Studio)`). Contract: [0000-obsidian-export](specs/0000-obsidian-export.md).
