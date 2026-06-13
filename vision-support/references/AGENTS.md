<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-06-13 | Updated: 2026-06-13 -->

# references

## Purpose
Reference documentation for vision-support, listing supported vision-capable AI models across OpenAI-compatible, Google Gemini, and Anthropic providers, along with config examples and recommended model combinations for various use cases.

## Key Files

| File | Description |
|------|-------------|
| `supported-models.md` | Catalog of tested vision models by provider type (openai, google, anthropic) with endpoint details, config JSON examples, and recommended setups for budget, quality, local, and Chinese-provider scenarios |

## Subdirectories

*None.*

## For AI Agents

### Working In This Directory
This directory contains static reference documentation only. Files here are source-of-truth for which models are tested and how to configure them. The primary file (`supported-models.md`) should be updated when new models or providers are validated.

### Testing Requirements
Reference files do not require automated testing. Verify that all provider names, model strings, and endpoint URLs are accurate when editing.

### Common Patterns
- Provider type determines API format (`openai` = `/v1/chat/completions` with `image_url`, `google` = `/v1beta/models/{model}:generateContent` with `inlineData`, `anthropic` = `/v1/messages` with `image` blocks)
- Config JSON uses `provider`, `model`, `baseUrl`, and `apiKeyEnv` fields
- Configuration examples serve as templates for user-facing setup

## Dependencies

### Internal
- `scripts/vision.mjs` (references the model configurations and `callModel()` provider handlers)

### External
- OpenAI Chat Completions API
- Google Generative AI API
- Anthropic Messages API

<!-- MANUAL: -->
