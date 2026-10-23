package library

import (
	"os"
	"path/filepath"
)

// readme documents the library for people and for AI agents that are pointed
// at the folder directly (Claude Code, Codex, the Look Tongji Notes skill...).
const readme = `# Look Studio 课程库

本目录由 Look Studio 维护，既给人看，也给 AI 读。**文件是事实来源**；
` + "`library.db`" + ` 只是可随时重建的索引（设置 → 存储 → 重建索引）。

## 目录结构

` + "```" + `
courses/
  <课程名>/
    course.json                 课程元数据 (schema: look-studio/course@1)
    notes/<标题>-<id>.md         课程级笔记
    <日期> <节次标题>/
      lecture.json              本节清单：身份、时间、本地文件列表 (look-studio/lecture@1)
      transcript.md             转写稿，按约 60 秒分段，每段以 [mm:ss] 开头 —— AI 首选阅读入口
      transcript.srt            逐句字幕（毫秒级时间轴）
      slides/0001_t00-12-03.jpg 课堂 PPT 快照，文件名含出现时间
      slides/index.json         快照列表与时间
      timeline.txt              时间轴大纲，每行 "起始-结束：内容"（与 skill 的 *_timeline.txt 同格式）
      courseware/               用户上传的课件 (pdf/pptx/docx/图片)
      courseware/<文件>.parsed/full.md  MinerU 解析出的 Markdown（含 images/）
      video.mp4                 录像（如已下载）
      notes/<标题>-<id>.md       本节笔记（YAML front matter + Markdown）
notes/                          不属于任何课程的笔记
library.db                      SQLite 索引（WAL 模式）
` + "```" + `

## 给 AI 的阅读建议

1. 先读 ` + "`courses/*/course.json`" + ` 了解有哪些课程。
2. 对某一节课，先读 ` + "`lecture.json`" + `，再读 ` + "`transcript.md`" + `；需要精确定位时用 ` + "`transcript.srt`" + `。
3. 有 ` + "`timeline.txt`" + ` 时先看大纲，再按时间段读转写稿；课件的解析结果在 ` + "`courseware/*.parsed/full.md`" + `。
4. PPT 快照文件名中的 ` + "`tHH-MM-SS`" + ` 与转写稿时间对齐，可据此把板书与讲解对应起来。
5. 笔记写入 ` + "`notes/`" + `，文件需带 front matter：` + "`id`, `title`, `course_id`, `lecture_id`, `source`" + `。
   Look Studio 会在“重建索引”时收录新文件。
6. 笔记里的应用内链接：` + "`[12:03](look://lecture/<课次id>?t=723)`" + ` 跳到录像时间；` + "`![PPT 12](look://slide/<课次id>/12)`" + ` 是该节第 12 张 PPT（对应 ` + "`slides/`" + ` 里按序号排列的文件）；` + "`look://file/<相对课程库的路径>`" + ` 指课程库里的文件（如课件插图）；` + "`look://courseware/<课次id>?file=<课件路径>&q=<关键词>`" + ` 指课件中的一段。

## 索引表 (library.db)

| 表 | 内容 |
|---|---|
| courses | 课程（含用户自定义：pinned / alias / color） |
| lectures | 节次（时间、教室、主讲、本地目录 dir） |
| assets | 本地文件（kind: video/slides/courseware/transcript/...，path 相对本目录） |
| slides | PPT 快照（t_sec 为出现秒数） |
| segments + segments_fts | 转写句子，FTS5 trigram 全文索引（中文子串检索，≥3 字） |
| notes + notes_fts | 笔记与全文索引 |
| jobs | 下载/转写/课件解析任务队列 |
| schedule | 日程：作业、考试、活动（due_date、提及时间 t_ms 与原话 quote） |
| timeline | 时间轴大纲（与 timeline.txt 同步） |
| playback / bookmarks | 播放进度与时间书签 |

示例：` + "`sqlite3 library.db \"SELECT l.title, g.start_ms/1000 AS sec, g.text FROM segments_fts f JOIN segments g ON g.rowid=f.rowid JOIN lectures l ON l.id=g.lecture_id WHERE segments_fts MATCH '板块构造' LIMIT 10\"`" + `

## 导出到 Obsidian

设置 → 存储 → Obsidian 会把课程库导出到 Obsidian 仓库的子文件夹（默认 ` + "`LookStudio/`" + `）：一个总的“课程库.md”，每门课一个文件夹，里面分“笔记”（按节次分文件夹，含笔记引用的 PPT/课件附件）和“转写稿”。
链接改为相对路径的标准 Markdown，时间戳改为 ` + "`lookstudio://lecture/<课次id>?t=<秒>`" + `（点击后由 Look Studio 打开）。
在 Obsidian 里改过的文件不会被覆盖，新版本另存为“(Look Studio)”副本。

## 与 Look Tongji Notes skill 互通

设置 → 存储 → “导出到 skill 工作区” 会生成 ` + "`raw/<课程>/<节次>/原始数据/`" + ` 结构（硬链接，不重复占用空间），
可直接用 skill 的 ` + "`index` / `build`" + ` 生成课程知识库网站。
`

func (l *Library) writeReadme() {
	p := filepath.Join(l.Root, "README.md")
	if b, err := os.ReadFile(p); err == nil && string(b) == readme {
		return
	}
	os.WriteFile(p, []byte(readme), 0o644)
}
