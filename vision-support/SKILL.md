---
name: vision-support
description: "为非多模态模型（如 deepseek-v4-pro、GLM-5.1、mimo-v2.5-pro 等纯文本模型）提供图片识别能力。当主模型无法识别图片、用户发送了截图/设计稿/UI 截图需要分析、或者用户说'看看这张图'、'分析这个截图'、'这张图片有什么问题'时，自动触发此技能。也适用于用户粘贴了图片但当前模型不支持图片输入的任何场景。支持同时识别多张图片，通过配置多个识图模型实现主备回退。使用指令 /skill:vision-support 或 /vision 也可手动触发。铁律：本技能配置的模型仅用于图片内容识别，绝不参与主逻辑推理。注意：如果当前模型本身是多模态模型（如 Claude Sonnet 4、GPT-4o、Gemini 等可以直接识图的模型），不要使用此技能，直接让主模型识别即可。"
---

# Vision Support — 非多模态模型的图片识别桥接

> **铁律：本技能配置的所有模型仅用于图片内容识别，绝不参与主逻辑推理。**
> 这些模型不会代替主模型做任何决策、分析或编码，它们只负责"看"图片然后把看到的内容用文字描述出来。

## 什么时候使用此技能

- **用户在对话中附带了图片**，但当前模型不支持图片理解
- **用户提到截图/图片/界面/设计**："看看这个截图"、"界面有问题"、"这个设计稿"
- **用户描述了一个视觉问题但说不清楚**："网页显示不对"、"布局乱了"
- **agent 在工作中遇到图片文件**（PNG/JPG/WebP 等）
- **通过指令 `/vision` 或 `/skill:vision-support` 手动触发**

## 首次使用 — 一键初始化

```bash
node SKILL_DIR/scripts/vision.mjs init
```

交互式引导，只需三步：
1. **选 Provider** — 从预置的主流平台列表中选择
2. **填密钥** — 输入 API Key（或环境变量名）
3. **选模型** — 自动从 API 拉取可用模型列表供选择（如拉取失败则显示推荐列表）

支持的平台覆盖国内外主流：

| 分类 | 平台 |
|------|------|
| 国际 | OpenAI、Google Gemini、Anthropic Claude、DeepSeek、Groq、Mistral、xAI (Grok)、OpenRouter、Fireworks AI |
| 国内 | 通义千问 (Qwen VL)、智谱 GLM (GLM-4V)、Moonshot (Kimi)、阶跃星辰 (Step)、MiniMax、SiliconFlow (硅基流动)、小米 MiMo |
| 本地 | Ollama、LM Studio |
| 自定义 | 任何 OpenAI 兼容的第三方平台（自填 baseUrl） |

## 添加备用模型

```bash
node SKILL_DIR/scripts/vision.mjs config add
```

同样的交互式引导，添加的模型作为 fallback 回退。主模型失败后自动尝试。

## 所有配置命令

```bash
# 交互式
node SKILL_DIR/scripts/vision.mjs init                    # 初始化主模型
node SKILL_DIR/scripts/vision.mjs config add              # 添加 fallback
node SKILL_DIR/scripts/vision.mjs config edit [name]      # 编辑模型

# 快捷命令
node SKILL_DIR/scripts/vision.mjs config list             # 列出所有模型
node SKILL_DIR/scripts/vision.mjs config primary [name]   # 设置主模型
node SKILL_DIR/scripts/vision.mjs config remove <name>    # 删除模型
node SKILL_DIR/scripts/vision.mjs config set-key <name> <key>   # 设置密钥
node SKILL_DIR/scripts/vision.mjs config set-url <name> <url>   # 设置 API 地址
node SKILL_DIR/scripts/vision.mjs config test [name]      # 测试连通性
```

## 使用方法 — 识别图片

### 单张

```bash
node SKILL_DIR/scripts/vision.mjs ./screenshot.png
node SKILL_DIR/scripts/vision.mjs ./ui.png "这个界面的布局有什么问题？"
node SKILL_DIR/scripts/vision.mjs "https://example.com/img.png" "描述这张图片"
```

### 多张

```bash
node SKILL_DIR/scripts/vision.mjs img1.png img2.png "对比这两张图的差异"
node SKILL_DIR/scripts/vision.mjs ./screenshots/*.png "分析这些界面截图"
node SKILL_DIR/scripts/vision.mjs ./local.png https://example.com/remote.jpg "描述这两张"
```

### 查找图片

如果用户提到图片但没给路径，先搜索：

```bash
find . -name "*.png" -o -name "*.jpg" -o -name "*.webp" | head -20
ls -lt *.png *.jpg *.webp 2>/dev/null
```

## 获取结果后的工作流

脚本成功后 stdout 输出的纯文本就是识别结果（stderr 是日志不影响）。

1. **读取识别结果**：stdout 内容即为图片描述
2. **结合用户问题**：把描述和用户需求结合
3. **主模型继续工作**：用识别结果作为上下文，主模型完成后续任务

## 回退机制

`config list` 中排第一位的 ★ 主模型优先调用。失败后自动依次尝试后续模型。所有模型都失败则非零退出码退出。

## 环境变量

| 变量 | 说明 |
|------|------|
| `VISION_CONFIG_PATH` | 自定义配置文件路径 |
| `VISION_DEFAULT_MODEL` | 临时覆盖主模型（按 name 匹配） |
| `VISION_API_KEY` | 全局密钥回退 |
