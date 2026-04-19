<p align="center">
  <a href="README.md"><strong>English</strong></a> | <strong>中文</strong>
</p>

<p align="center">
  <a href="LOGO"><img src="images/logo.svg"></a>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge" alt="MIT License"></a>
</p>

这是一个 agent `skill` + CLI，用来处理同济录课平台 `look.tongji.edu.cn`：
- 使用 Playwright 完成同济统一认证登录
- 列出课程（最近课程 / 全量搜索）
- 转写指定课程节次，输出字幕 `SRT` 与纯文本 `TXT`
- 根据字幕 `SRT` 由当前 Agent 生成“时间轴大纲”（`*_timeline.txt`，中文）
- 下载指定课程节次的 slide 截图（文件名包含截图时间）
- 再由当前 Agent 基于转写文本 + slide 图片生成 Markdown 笔记

## 安装

### 方法 1

复制仓库链接给你的 Agent，并告诉它：`帮我安装这个 skill`。

### 方法 2

下载并解压仓库，把整个 `look-tongji-notes/` 文件夹复制到你的 skills 目录：
- Codex：`~/.codex/skills/look-tongji-notes`
- Claude Code：`~/.claude/skills/look-tongji-notes`

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

## 单独使用（CLI）

`<SKILL_DIR>` 指包含 `SKILL.md` 的那个目录。

配置账号密码（强烈建议先做这一步）：

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" setup
```

列出最近课程：

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" list
```

按课程名搜索课程（更准确；内部会调用 `get_all_courses` 获取全量课程清单）：

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" list --all --query "<课程名关键词>"
```

仅转写指定节次（`transcribe`，别名 `transcript` / `trans`）：

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" transcribe --lecture-url "<课程链接>"
```

组合模式（`note`，默认并行执行转写 + slide 拉取）：

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" note --lecture-url "<课程链接>"
```

下载该节课的 slide 截图：

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" slide --lecture-url "<课程链接>"
```

若怀疑触发限流，可降低并发：

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" slide --course-id "<COURSE_ID>" --sub-id "<SUB_ID>" --concurrency 2 --retries 5
```
在 `look-tongji:note` 的工作流中，Agent 会在 `SRT` 生成后，额外输出一份用于视频总览的时间轴大纲：
- 文件：`./tongji-output/<course_id>_<sub_id>_timeline.txt`
- 格式（每行一个时间段，中文）：`起始时间-结束时间：课程阶段内容`
  - 示例：`00:00-05:30：课程定位与考核说明`
- 仅当用户明确提出 `不要大纲` / `不要时间线` / `no outline` / `no timeline` 时才跳过生成。

字幕/转写会输出到你当前工作目录的 `./tongji-output/`。

## Agent Note

当用户说 `look-tongji:setup` / `look-tongji:list` / `look-tongji:note` 时，按 `SKILL.md` 的流程执行，并运行 `scripts/look_tongji.py` 的对应命令。
`look-tongji:note` 默认并行执行转录和 slide 拉取；仅在用户显式提出不下载 slide/PPT 时才只做转录。
整理笔记时默认同时参考转录结果和 slide 图片。
如果用户给的是“课程名称”，优先用 `list --all --query ...`，避免最近课程列表遗漏导致选错课程。

## 声明 / 合规

> [!CAUTION]
> 强烈建议在交给 Agent 生成笔记之前，先使用 CLI 的 `setup` 配置学号密码，避免把学号密码直接输入给 Agent 造成安全风险。

> [!NOTE]
> - 灵感与部分源代码来源于：[Fudan_iCourse_Subscriber](https://github.com/LeafCreeper/Fudan_iCourse_Subscriber)
> - 本项目仅用于辅助本校学生进行**个人学习与复习**与技术交流，默认不保存完整视频文件。
> - 使用者必须遵守平台规则与校纪校规；任何滥用（含传播未授权课程视频/音频等）造成的后果由使用者自行承担。
> - 若未处于校园网环境或未使用同济 VPN，可能触发加强认证；在校外部署 Agent 时需要特别注意。

## ToDo

- [ ] 制作课程面板前端（汇聚个人课程视频、时间轴大纲、字幕、笔记等资源）。
- [ ] 适配触发加强认证时的登录流程。
- [ ] 适配针对课程的 LLM WIKI + 笔记数据库，用于由笔记/字幕驱动的复习。
- [ ] 制作 standalone 的 TUI/GUI 工具，不打开 Agent 也能手动转写字幕/笔记/Q&A。

## 最佳实践

- 生成最新课程字幕与笔记：
  - `/look-tongji-notes 帮我生成最新一节课的字幕和笔记`
  
- 生成指定课程字幕与笔记：
  - `/look-tongji-notes 帮我生成今天的高等数学课程字幕和笔记`
  
- 查看最近课程列表并选择：
  - `/look-tongji-notes 为我列出最新几门课，让我挑选要生成笔记的`
  
- Agent 找不到相应课程时：
  
  先用 `list --all --query "<关键词>"` 在全量课程清单里搜索；或者直接在平台打开对应节次并复制课程链接。
  
  ![example_link](images/example_link.png)
  
  然后告诉Agent: ``/look-tongji-notes 这是课程链接，为我生成笔记``

## 贡献指南

Coming soon.

