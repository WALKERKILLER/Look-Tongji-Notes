# Vision Support

> **铁律：本技能配置的模型仅用于图片内容识别，绝不参与主逻辑推理。**

为 Claude Code、Codex、Pi Agent 等开发工具中的**非多模态模型**（如 deepseek-v4-pro、GLM-5.1、mimo-v2.5-pro）提供图片识别能力。

当主模型无法"看"图片时，自动调用配置好的视觉模型来识别图片内容，把结果返回给主模型继续工作。

## 特性

- 🖼️ **多图识别** — 支持同时传入多张图片进行对比分析
- 🔄 **自动回退** — 主模型失败后依次尝试 fallback 模型
- 🌍 **19+ 平台** — 覆盖国内外主流 API（OpenAI / Gemini / 通义千问 / GLM / Ollama 等）
- 🎯 **零依赖** — 仅需 Node.js 18+，无需 npm install
- 🛠️ **交互式配置** — `init` 命令引导选平台、填密钥、选模型
- 🔌 **跨工具** — 适用于任何支持 Agent Skills 的工具

## 截图

![在终端中运行 vision-support](images/usage-recognize.png)

![识别结果输出](images/usage-result.png)

## 安装

### `npx skills`（推荐）

```bash
npx skills add https://github.com/penfick/skills --skill vision-support -g -y
```

### npm

```bash
npm install -g vision-support
```

安装后自动注册全局命令 `vision-support`，同时自动将 skill 文件复制到所有 agent 的 skills 目录。

### Mac / Linux 一行命令

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/penfick/skills/main/vision-support/install.sh)"
```

### Git Clone（手动安装）

```bash
git clone https://github.com/penfick/skills.git ~/.agents/skills
```

### 卸载

```bash
# npm
npm uninstall -g vision-support

# npx skills
npx skills remove vision-support

# 手动安装的
node install.mjs --uninstall
```

## 初始化（配置模型）

安装后需要配置一个识图模型，只做一次。

### npm 用户

```bash
vision-support init
```

### git / npx skills 用户

```bash
# Git Bash / Mac / Linux 终端
node ~/.agents/skills/vision-support/scripts/vision.mjs init

# Windows PowerShell
node "$HOME\.agents\skills\vision-support\scripts\vision.mjs" init
```

### 在 Agent 中（Pi / Claude Code）

```
/vision-support 帮我初始化配置
/vision-support 帮我用 gemini-2.5-flash 配置主模型，API key 是 xxx
```

## 使用方法

### npm 用户

```bash
vision-support ./image.png
vision-support img1.png img2.png "对比两张图"
vision-support https://example.com/img.png "描述图片"
```

### git / npx skills 用户

```bash
# Git Bash / Mac / Linux
node ~/.agents/skills/vision-support/scripts/vision.mjs ./image.png

# Windows PowerShell
node "$HOME\.agents\skills\vision-support\scripts\vision.mjs" ./image.png
```

### 在 Agent 中

发送图片后说 `看看这张图` / `分析这个截图`，自动触发。或手动：

```
/vision-support 看看这张图
```

## 配置管理

```bash
# npm 用户直接用 vision-support 命令
# git / npx skills 用户替换为 node ~/.agents/skills/vision-support/scripts/vision.mjs

vision-support init                    # 交互式初始化
vision-support config add              # 添加 fallback 模型
vision-support config edit [name]      # 编辑模型
vision-support config list             # 列出模型
vision-support config primary [name]   # 设置主模型
vision-support config remove <name>    # 删除模型
vision-support config set-key <n> <k>  # 设置密钥
vision-support config set-url <n> <u>  # 设置 API 地址
vision-support config test [name]      # 测试连通性
```

## 支持的平台

| 分类 | 平台 |
|------|------|
| 国际 | OpenAI、Google Gemini、Anthropic Claude、DeepSeek、Groq、Mistral、xAI (Grok)、OpenRouter、Fireworks AI |
| 国内 | 通义千问 (Qwen VL)、智谱 GLM (GLM-4V)、Moonshot (Kimi)、阶跃星辰 (Step)、MiniMax、SiliconFlow (硅基流动)、小米 MiMo |
| 本地 | Ollama、LM Studio |
| 自定义 | 任何 OpenAI 兼容平台（自填 baseUrl） |

## 工作原理

```
用户发图片 + 问题
       ↓
 Agent 读取 SKILL.md，调用 vision.mjs
       ↓
 主视觉模型 (Gemini) ──成功──→ 返回识别结果
       ↓ 失败
 Fallback 1 (GPT-4o) ──成功──→ 返回识别结果
       ↓ 失败
 Fallback 2 (Qwen-VL) ──成功──→ 返回识别结果
       ↓
 stdout 输出文本描述 → 主模型继续工作
```

## 目录结构

```
skills/
├── README.md                    ← repo 说明
├── LICENSE
└── vision-support/
    ├── SKILL.md                 ← skill 入口（Agent 自动读取）
    ├── package.json
    ├── bin/
    │   ├── cli.mjs              ← npm 全局命令入口
    │   └── postinstall.mjs      ← npm 安装后自动部署 skill 文件
    ├── install.mjs              ← 跨平台安装脚本
    ├── install.sh               ← Mac/Linux 一键安装
    ├── config.example.json      ← 配置模板
    ├── scripts/
    │   └── vision.mjs           ← 核心脚本（零依赖）
    └── references/
        └── supported-models.md
```

## License

MIT

---

[English Documentation](README.md)
