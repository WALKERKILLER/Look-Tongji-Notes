# Supported Vision Models

This reference lists vision-capable models tested with vision-support. The `provider` field in config determines the API format used.

## Provider Types

### `openai` — OpenAI Chat Completions API

Covers OpenAI and all OpenAI-compatible providers. Uses the `/v1/chat/completions` endpoint with `image_url` content blocks.

**Known compatible providers:**

| Provider | baseUrl | Models |
|----------|---------|--------|
| OpenAI | `https://api.openai.com/v1` | `gpt-4o`, `gpt-4o-mini`, `gpt-4-turbo` |
| DeepSeek | `https://api.deepseek.com/v1` | *(check availability)* |
| DashScope (Qwen) | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen-vl-max`, `qwen-vl-plus` |
| ZhipuAI (GLM) | `https://open.bigmodel.cn/api/paas/v4` | `glm-4v-plus`, `glm-4v` |
| Moonshot | `https://api.moonshot.cn/v1` | *(check availability)* |
| Ollama (local) | `http://localhost:11434/v1` | `llava`, `bakllava`, `moondream` |
| LM Studio (local) | `http://localhost:1234/v1` | *(any loaded vision model)* |
| SiliconFlow | `https://api.siliconflow.cn/v1` | Various vision models |

**Config example:**
```json
{
  "name": "Qwen-VL",
  "provider": "openai",
  "model": "qwen-vl-max",
  "baseUrl": "https://dashscope.aliyuncs.com/compatible-mode/v1",
  "apiKeyEnv": "DASHSCOPE_API_KEY"
}
```

### `google` — Google Generative AI API

Uses the `/v1beta/models/{model}:generateContent` endpoint with `inlineData`.

| Model | Notes |
|-------|-------|
| `gemini-2.0-flash` | Fast, cost-effective |
| `gemini-2.5-flash` | Latest flash |
| `gemini-2.5-pro` | Best quality |
| `gemini-1.5-pro` | Older but reliable |

**Config example:**
```json
{
  "name": "Gemini Flash",
  "provider": "google",
  "model": "gemini-2.0-flash",
  "baseUrl": "https://generativelanguage.googleapis.com/v1beta",
  "apiKeyEnv": "GEMINI_API_KEY"
}
```

**Free tier:** Google offers a generous free tier for Gemini models, making it an excellent fallback option.

### `anthropic` — Anthropic Messages API

Uses the `/v1/messages` endpoint with `image` content blocks.

| Model | Notes |
|-------|-------|
| `claude-sonnet-4-20250514` | Good balance |
| `claude-opus-4-20250514` | Best quality |
| `claude-3-5-sonnet-20241022` | Previous gen |

**Config example:**
```json
{
  "name": "Claude Vision",
  "provider": "anthropic",
  "model": "claude-sonnet-4-20250514",
  "baseUrl": "https://api.anthropic.com",
  "apiKeyEnv": "ANTHROPIC_API_KEY"
}
```

## Recommended Configurations

### Budget-friendly (free/cheap models first)

```json
{
  "models": [
    { "name": "Gemini Flash", "provider": "google", "model": "gemini-2.0-flash", "apiKeyEnv": "GEMINI_API_KEY" },
    { "name": "Qwen-VL-Plus", "provider": "openai", "model": "qwen-vl-plus", "baseUrl": "https://dashscope.aliyuncs.com/compatible-mode/v1", "apiKeyEnv": "DASHSCOPE_API_KEY" },
    { "name": "GPT-4o-mini", "provider": "openai", "model": "gpt-4o-mini", "apiKeyEnv": "OPENAI_API_KEY" }
  ]
}
```

### Best quality (premium models)

```json
{
  "models": [
    { "name": "GPT-4o", "provider": "openai", "model": "gpt-4o", "apiKeyEnv": "OPENAI_API_KEY" },
    { "name": "Gemini Pro", "provider": "google", "model": "gemini-2.5-pro", "apiKeyEnv": "GEMINI_API_KEY" },
    { "name": "Claude", "provider": "anthropic", "model": "claude-sonnet-4-20250514", "apiKeyEnv": "ANTHROPIC_API_KEY" }
  ]
}
```

### Local-only (offline, Ollama)

```json
{
  "models": [
    { "name": "LLaVA", "provider": "openai", "model": "llava", "baseUrl": "http://localhost:11434/v1", "apiKeyEnv": "OLLAMA_API_KEY" }
  ]
}
```

### Chinese providers (domestic network)

```json
{
  "models": [
    { "name": "Qwen-VL-Max", "provider": "openai", "model": "qwen-vl-max", "baseUrl": "https://dashscope.aliyuncs.com/compatible-mode/v1", "apiKeyEnv": "DASHSCOPE_API_KEY" },
    { "name": "GLM-4V-Plus", "provider": "openai", "model": "glm-4v-plus", "baseUrl": "https://open.bigmodel.cn/api/paas/v4", "apiKeyEnv": "GLM_API_KEY" },
    { "name": "Step-1V", "provider": "openai", "model": "step-1v-8k", "baseUrl": "https://api.stepfun.com/v1", "apiKeyEnv": "STEPFUN_API_KEY" }
  ]
}
```

## Adding Custom Models

Any model with an OpenAI-compatible `/v1/chat/completions` endpoint that accepts `image_url` content blocks will work. Just set `provider: "openai"` and point `baseUrl` to the API root.

For completely custom APIs, modify `callModel()` in `scripts/vision.mjs` to add a new provider handler.
