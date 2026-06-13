<p align="center">
  <a href="README.md"><strong>English</strong></a> | <strong>中文</strong>
</p>

<p align="center">
  <a href="LOGO"><img src="images/logo.svg"></a>
</p>
<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge" alt="MIT License"></a>
</p>


[![Works with Claude Code](https://img.shields.io/badge/Claude%20Code-✓-7C3AED.svg?style=for-the-badge)](https://claude.com/claude-code)
[![Works with Codex CLI](https://img.shields.io/badge/Codex%20CLI-✓-7C3AED.svg?style=for-the-badge)](https://github.com/openai/codex)
[![Works with Cursor](https://img.shields.io/badge/Cursor-✓-7C3AED.svg?style=for-the-badge)](https://cursor.com)
[![Works with Copilot](https://img.shields.io/badge/GitHub%20Copilot-✓-7C3AED.svg?style=for-the-badge)](https://github.com/features/copilot)
[![Works with Gemini CLI](https://img.shields.io/badge/Gemini%20CLI-✓-7C3AED.svg?style=for-the-badge)](https://ai.google.dev/gemini-api)
[![Works with Obsidian](https://img.shields.io/badge/Obsidian-✓-7C3AED.svg?style=for-the-badge)](https://obsidian.md)
[![Version](https://img.shields.io/badge/Version-1.0.0-7C3AED.svg?style=for-the-badge)](SKILL.md)



这是一个 agent skill 套件（8 个原子化 `/command` 技能）+ CLI，用来处理同济录课平台 `look.tongji.edu.cn`：
- 使用 Playwright 完成同济统一认证登录
- 列出课程（最近课程 / 全量搜索）
- 首次配置一个持久化的课程知识库工作区
- 转写指定课程节次，输出字幕 `SRT` 与纯文本 `TXT`
- 根据字幕 `SRT` 由当前 Agent 生成“时间轴大纲”（`*_timeline.txt`）
- 下载指定课程节次的 slide 截图
- 支持导入补充资料，并用 [`markitdown`](https://github.com/microsoft/markitdown)转成可索引文本
- 由当前 Agent 基于转写文本 + slide 图片 + 补充资料生成 Markdown 笔记
- 生成一个基于 `llm-wiki`的课程知识库页面

## 安装

### 方法 1

复制仓库链接给你的 Agent，并告诉它：`帮我安装这个 skill`。

### 方法 2

下载并解压仓库。仓库提供两种结构：

- 兼容入口：根目录 `SKILL.md`
- 扁平技能目录：`skills/<name>/SKILL.md`（8 个原子化命令）

如果你的 Agent 支持插件或 marketplace，直接使用仓库根目录作为插件根即可。
`.claude-plugin/`、`.codex-plugin/`、`.cursor-plugin/`、`.agents/plugins/`
各平台 manifests 在根目录下，`skills/` 下为 8 个命令的 `SKILL.md`。

如果只能手动复制 skill：

- Codex：复制到 `~/.codex/skills/look-tongji-notes`
- Claude Code：复制到 `~/.claude/skills/look-tongji-notes`

### 方法 3（Codex）

打开 Codex 后执行：

```text
$skill-installer install https://github.com/walkerkiller/look-tongji-notes
```

### 方法 4（Claude Code）

打开 Claude Code 后执行：

```text
/plugin marketplace add https://github.com/walkerkiller/look-tongji-notes
/plugin install look-tongji-notes
```

## 多 Agent Skill 结构

本仓库按多平台插件格式组织，其中：

- 根目录：源码仓库与 catalog 元数据
- `.claude-plugin/`：Claude Code marketplace/plugin 元数据
- `.codex-plugin/`：Codex 插件元数据
- `.cursor-plugin/`：Cursor 插件元数据
- `.agents/plugins/`：通用 agents marketplace 元数据
- `.gemini-plugin/`：Gemini CLI 插件元数据
- `.openclaw-plugin/`：OpenClaw 插件元数据
- `.opencode-plugin/`：OpenCode 插件元数据
- `.hermes-agent-plugin/`：Hermes Agent 插件元数据
- `skills/`：8 个原子化命令技能（`skills/<name>/SKILL.md`）

平台对齐说明：

- `Claude Code`：标准扫描目录是 `skills/<skill-name>/SKILL.md`
- `Codex`：`plugin.json` 指向 `./skills/`
- `Cursor`：`plugin.json` 指向 `./skills/`
- `Gemini CLI`、`OpenClaw`、`OpenCode`、`Hermes Agent`：各平台 plugin.json 均指向 `./skills/`

8 个命令：

- `/setup` — 配置凭据，检查依赖（Python、Node.js、ffmpeg、vision-support、TeX），设置工作区
- `/list` — 列出课程，关键词搜索，交互式选择
- `/trans` — 单节转写为 SRT + TXT；可选并行下载 slide
- `/note` — 从转写文本 + slide 生成学习笔记 + 时间轴大纲
- `/add` — 导入补充资料（PDF、PPTX、DOCX）到课程节次
- `/wiki` — 构建并本地 serve 静态课程知识库
- `/cheatsheet` — 从课程笔记生成 A4 速查表（LaTeX 或 HTML）
- `/ralphtrans` — 批量转写整门课程全部节次，支持断点续传

## 单独使用（CLI）

`<SKILL_DIR>` 指包含 `SKILL.md` 的那个目录。

配置账号密码（强烈建议先做这一步）：

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" setup
```

第一次运行会询问课程知识库保存路径。这个路径不会放在 skill 目录里，
所以后续更新 skill 时不会被覆盖。

也可以直接指定：

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" setup \
  --workspace-root "~/Documents/tongji-course-wiki" \
  --owner-name "WALKERKILLER"
```

列出最近课程：

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" list
```

按课程名搜索课程（更准确；内部会调用 `get_all_courses` 获取全量课程清单）：

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" list --all --query "<课程名关键词>"
```

仅转写指定节次（`transcribe`，别名 `transcript` / `trans`）：

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

如果这节课还有老师发的资料、PDF、PPT、Word 或其他文件，可以一并导入：

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" note \
  --lecture-url "<课程链接>" \
  --material "课件=/path/to/slides.pdf" \
  --material "阅读材料=/path/to/reading.docx"
```

下载该节课的 slide 截图：

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" slide --lecture-url "<课程链接>"
```

若怀疑触发限流，可降低并发：

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" slide --course-id "<COURSE_ID>" --sub-id "<SUB_ID>" --concurrency 2 --retries 5
```
在 `/note` 的工作流中，Agent 会在 `SRT` 生成后，额外输出一份用于视频总览的时间轴大纲：
- 文件：`./tongji-output/<course_id>_<sub_id>_timeline.txt`
- 新版默认位置：`<工作区>/raw/<课程>/<节次>/原始数据/<course_id>_<sub_id>_timeline.txt`
- 格式（每行一个时间段，中文）：`起始时间-结束时间：课程阶段内容`
  - 示例：`00:00-05:30：课程定位与考核说明`
- 仅当用户明确提出 `不要大纲` / `不要时间线` / `no outline` / `no timeline` 时才跳过生成。

默认输出写入配置好的课程知识库工作区：

```text
<工作区>/
├── raw/
│   └── <课程名称>/
│       └── <节次>/
│           └── 原始数据/
│               ├── <course_id>_<sub_id>.txt
│               ├── <course_id>_<sub_id>.srt
│               ├── slides/
│               ├── materials/
│               └── manifest.json
├── wiki/
└── site/
```

如果你显式传入 `--output-dir`，CLI 仍然会尊重这个路径，方便兼容旧流程。

## Agent Note

当用户说 `/setup` / `/list` / `/trans` / `/note` / `/wiki` / `/add` / `/cheatsheet` / `/ralphtrans` 时，按对应 `skills/<name>/SKILL.md` 的流程执行，并运行 `scripts/look_tongji.py` 的对应命令。
`/note` 默认并行执行转录和 slide 拉取；仅在用户显式提出不下载 slide/PPT 时才只做转录。
整理笔记时默认同时参考转录结果、slide 图片和 `materials/*/converted.md`。
如果用户给的是“课程名称”，优先用 `list --all --query ...`，避免最近课程列表遗漏导致选错课程。

生成或更新笔记后，执行：

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" index
python "<SKILL_DIR>/../../scripts/look_tongji.py" build
python "<SKILL_DIR>/../../scripts/look_tongji.py" serve --port 8765
```

它会在工作区的 `site/` 下生成课程知识库页面，并用本地 HTTP server 预览。
这里对齐 `llm-wiki` 的真实形态：不是 React/Vite/Next 项目，也不是单 HTML，
而是 Python 静态站点生成器，输出多级 HTML、`style.css`、`script.js`，
再用 `serve` 命令提供本地预览。
中英切换只影响面板控件，不会翻译课程内容。

## GitHub Pages 部署

如果要把 `site/` 部署到 GitHub Pages，可以把工作区做成一个普通 Git 仓库：

```bash
cd "<工作区>"
git init
git add raw wiki site llmwiki .github build.sh serve.sh index.py
git commit -m "build course wiki"
```

然后在 GitHub 仓库设置里选择从 `site/` 目录发布，或按项目习惯配置
GitHub Actions。初始化工作区时会自动写入：

- `llmwiki/`：直接复用 `llm-wiki` 的前端与构建包
- `index.py`：将课程节次 `manifest.json` 编成 `llm-wiki` 输入层
- `build.sh`：调用 `python -m llmwiki build --out ./site`
- `serve.sh`：调用 `python -m llmwiki serve --dir ./site`
- `.github/workflows/wiki-checks.yml`
- `.github/workflows/pages.yml`

不要提交 `.env`、账号密码、JWT 或未授权传播的课程视频。

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
> [!NOTE]
> 建议在agent工具中使用具有**视觉**的llm模型来保证对图片资料的理解来保持最佳体验。若必须使用本身不具备视觉能力的llm，建议通过配置来自[vision-support](https://github.com/penfick/skills)仓库中的`vision-support`这一skill来外挂视觉模型理解图片资料。


- 生成最新课程字幕与笔记：
  - `/note 帮我生成最新一节课的字幕和笔记`
  
- 生成指定课程字幕与笔记：
  - `/note 帮我生成今天的高等数学课程字幕和笔记`
  
- 查看最近课程列表并选择：
  - `/trans 为我列出最新几门课，让我挑选要生成笔记的`
  
- Agent 找不到相应课程时：
  
  先用 `list --all --query "<关键词>"` 在全量课程清单里搜索；或者直接在平台打开对应节次并复制课程链接。
  
  ![example_link](images/example_link.png)
  
  然后告诉Agent: ``/trans 这是课程链接，为我生成笔记``

## 贡献指南

Coming soon.

