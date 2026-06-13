<p align="center">
  <a href="README.md"><strong>English</strong></a> | <strong>中文</strong>
</p>

<p align="center">
  <a href="#"><img src="images/logo.svg"></a>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge" alt="MIT License"></a>
  <a href="SKILL.md"><img src="https://img.shields.io/badge/Version-1.1.1-7C3AED.svg?style=for-the-badge" alt="Version 1.1.1"></a>
</p>

这是一个 agent skill 套件（9 个原子化 `/command` 技能）+ CLI，用来处理同济录课平台 `look.tongji.edu.cn`：
- 使用 Playwright 完成同济统一认证登录
- 列出课程（最近课程 / 全量搜索）
- 转写指定课程节次，输出字幕 `SRT` 与纯文本 `TXT`
- 根据字幕 `SRT` 由当前 Agent 生成"时间轴大纲"（`*_timeline.txt`，简体中文）
- 下载指定课程节次的 slide 截图
- 由当前 Agent 基于转写文本 + slide 图片生成 Markdown 笔记

## Commands

| 命令 | 说明 |
|------|------|
| `/setup` | 配置凭据，检查依赖（Python、Node.js、ffmpeg、vision-support、TeX），设置工作区 |
| `/list` | 列出课程，关键词搜索，交互式选择 |
| `/trans` | 单节转写为 SRT + TXT；可选并行下载 slide |
| `/note` | 从转写文本 + slide 生成学习笔记 + 时间轴大纲 |
| `/add` | 导入补充资料（PDF、PPTX、DOCX）到课程节次 |
| `/wiki` | 构建并本地 serve 静态课程知识库 |
| `/page` | 将构建的课程 wiki 部署到 GitHub Pages（通过 gh CLI） |
| `/cheatsheet` | 从课程笔记生成 A4 速查表（LaTeX 或 HTML） |
| `/ralphtrans` | 批量转写整门课程全部节次，支持断点续传 |

## 安装

### 推荐：通过 npx skills

如果你的 Agent 支持 [skills](https://github.com/topics/skills) 协议：

```bash
npx skills install https://github.com/walkerkiller/look-tongji-notes
```

### Claude Code 市场安装

在 Claude Code 中执行：

```text
/plugin marketplace add https://github.com/walkerkiller/look-tongji-notes
/plugin install look-tongji-notes
```

### 其他平台

| 平台 | 安装方式 |
|------|----------|
| Claude Code | 市场安装（见上方）或仓库根目录作为插件根 |
| Codex CLI | `.codex-plugin/plugin.json` → `./skills/` |
| Cursor | `.cursor-plugin/plugin.json` → `./skills/` |
| Gemini CLI / OpenClaw / OpenCode / Hermes Agent | `plugin.json` → `./skills/` |

## CLI 单独使用

`<SKILL_DIR>` 指包含 `SKILL.md` 的目录。

配置账号密码（推荐）：

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" setup
```

列出最近课程：

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" list
```

按课程名搜索（推荐，内部调用 `get_all_courses` 全量搜索）：

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" list --all --query "<课程名关键词>"
```

仅转写（`transcribe`，别名 `transcript` / `trans`）：

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" transcribe --lecture-url "<课程链接>"
```

组合模式（`note`，默认并行执行转写 + slide 拉取）：

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" note --lecture-url "<课程链接>"
```

笔记风格（影响笔记格式）：

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" note --lecture-url "<课程链接>" --note-style dialogue
```
支持 `standard`（课堂笔记，默认）和 `dialogue`（问答格式）。

> [!TIP]
> CLI 会自动检测课时是否不足 1 小时，若发现时长短于 1 小时会输出非阻塞警告：`[Warning] 课时不足1小时`，提示转录可能不完整，建议重试。

下载 slide 截图：

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" slide --lecture-url "<课程链接>"
```

若怀疑触发限流，可降低并发：

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" slide --course-id "<COURSE_ID>" --sub-id "<SUB_ID>" --concurrency 2 --retries 5
```

在 `/note` 工作流中，Agent 会在 `SRT` 字幕文件生成后，额外输出一份时间轴大纲：
- 文件：`<工作区>/raw/<课程>/<节次>/原始数据/<course_id>_<sub_id>_timeline.txt`
- 格式（每行一个时间段，简体中文）：`起始时间-结束时间：课程阶段内容`
  - 示例：`00:00-05:30：课程定位与考核说明`
- 仅当用户明确说"不要大纲" / "不要时间线"时才跳过。

默认输出写入配置好的课程知识库工作区。

## Agent Note

当用户说 `/setup` / `/list` / `/trans` / `/note` / `/wiki` / `/add` / `/page` / `/cheatsheet` / `/ralphtrans` 时，按对应 `skills/<name>/SKILL.md` 的流程执行，并运行 `scripts/look_tongji.py` 的对应命令。
`/note` 默认并行执行转录和 slide 拉取；仅在用户显式提出不下载 slide/PPT 时才只做转录。
整理笔记时默认同时参考转录结果和 slide 图片。
如果用户提供的是课程名称，优先用 `list --all --query ...`，避免最近课程列表遗漏导致选错课程。

笔记生成或更新后，重建并预览站点：

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" index
python "<SKILL_DIR>/../../scripts/look_tongji.py" build
python "<SKILL_DIR>/../../scripts/look_tongji.py" serve --port 8765
```

生成的工作区也可以作为用户自己的 GitHub Pages 仓库。包含以下文件：

- `llmwiki/`
- `index.py`
- `build.sh`
- `serve.sh`
- `.github/workflows/wiki-checks.yml`
- `.github/workflows/pages.yml`

## 声明 / 合规

> [!CAUTION]
> 强烈建议在交给 Agent 生成笔记之前，先使用 CLI 的 `setup` 配置学号密码，避免把学号密码直接输入给 Agent 造成安全风险。

> [!NOTE]
> - 灵感与部分源代码来源于：[Fudan_iCourse_Subscriber](https://github.com/LeafCreeper/Fudan_iCourse_Subscriber)
> - 本项目仅用于辅助本校学生进行**个人学习与复习**与技术交流，默认不保存完整视频文件。
> - 使用者必须遵守平台规则与校纪校规；任何滥用（含传播未授权课程视频/音频等）造成的后果由使用者自行承担。
> - 若未处于校园网环境或未使用同济 VPN，可能触发加强认证；在校外部署 Agent 时需要特别注意。

## ToDo

- [x] 生成课程知识库静态站点骨架（课程、节次、视频、时间轴、i18n 控件）。
- [ ] 适配触发加强认证时的登录流程。
- [x] 适配针对课程的 LLM WIKI + 笔记数据库基础目录。
- [ ] 制作 standalone 的 TUI/GUI 工具，不打开 Agent 也能手动转写字幕/笔记/Q&A。

## 最佳实践

- 生成最新课程字幕与笔记：
  - `/note 帮我生成最新一节课的字幕和笔记`

- 生成指定课程字幕与笔记：
  - `/note 帮我生成今天的高等数学课程字幕和笔记`

- 查看最近课程列表并选择：
  - `/trans 为我列出最新几门课，让我挑选要生成笔记的`

- Agent 找不到相应课程时：

  先用 `list --all --query "<关键词>"` 在全量课程清单里搜索；或者直接在平台打开对应节次并复制课程链接。

  ![example_link](images/example_link.png)

  然后告诉 Agent: `/trans 这是课程链接，为我生成笔记`

## 贡献指南

Coming soon.
