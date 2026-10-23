import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../l10n/l10n.dart';

/// A provider the user can add in one step, in the spirit of Kelivo's presets.
/// [pi] names a provider already built into the Pi SDK (only a key is needed);
/// otherwise the preset becomes a custom endpoint in Pi's models.json.
class ProviderPreset {
  const ProviderPreset({
    required this.id,
    required this.name,
    required this.logo,
    this.pi,
    this.baseUrl = '',
    this.api = 'openai-completions',
    this.catalog,
    this.keyUrl = '',
    this.blurb = '',
    this.region = Region.global,
    this.mono = false,
    this.needsKey = true,
    this.aliases = const [],
  });

  final String id;
  final String name;
  final String logo; // asset file name under assets/providers
  final String? pi;
  final String baseUrl;
  final String api;
  final String? catalog; // models.dev provider id
  final String keyUrl;
  final String blurb;
  final Region region;
  final bool mono; // single-colour logo, tinted with onSurface
  final bool needsKey;
  final List<String> aliases;

  /// Provider id as stored in Pi (built-in id or our custom id).
  String get providerId => pi ?? id;
  bool get builtin => pi != null;

  bool matches(String q) {
    final s = q.toLowerCase();
    return name.toLowerCase().contains(s) ||
        id.contains(s) ||
        (pi ?? '').contains(s) ||
        blurb.toLowerCase().contains(s) ||
        aliases.any((a) => a.toLowerCase().contains(s));
  }
}

enum Region {
  cn,
  global,
  local;

  String get label => switch (this) {
        cn => l10n.regionChina,
        global => l10n.regionGlobal,
        local => l10n.commonLocal,
      };
}

final kProviderPresets = <ProviderPreset>[
  // ---- 国内 ----
  ProviderPreset(id: 'deepseek', pi: 'deepseek', name: 'DeepSeek', logo: 'deepseek-color.svg', catalog: 'deepseek', region: Region.cn,
      keyUrl: 'https://platform.deepseek.com/api_keys', blurb: l10n.providerDeepseekBlurb, aliases: ['深度求索']),
  ProviderPreset(id: 'siliconflow', name: l10n.providerSiliconflow, logo: 'siliconcloud-color.svg', baseUrl: 'https://api.siliconflow.cn/v1', catalog: 'siliconflow-cn',
      region: Region.cn, keyUrl: 'https://cloud.siliconflow.cn/account/ak', blurb: l10n.providerSiliconflowBlurb, aliases: ['SiliconFlow', 'siliconcloud']),
  ProviderPreset(id: 'bailian', name: l10n.providerBailian, logo: 'bailian-color.svg', baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1', catalog: 'alibaba-cn',
      region: Region.cn, keyUrl: 'https://bailian.console.aliyun.com/?apiKey=1', blurb: l10n.providerBailianBlurb, aliases: ['qwen', 'dashscope', '通义', 'alibaba']),
  ProviderPreset(id: 'zhipu', name: l10n.providerZhipu, logo: 'zhipu-color.svg', baseUrl: 'https://open.bigmodel.cn/api/paas/v4', catalog: 'zhipuai',
      region: Region.cn, keyUrl: 'https://bigmodel.cn/usercenter/proj-mgmt/apikeys', blurb: l10n.providerZhipuBlurb, aliases: ['glm', 'zhipuai', 'chatglm']),
  ProviderPreset(id: 'moonshotai-cn', pi: 'moonshotai-cn', name: l10n.providerMoonshot, logo: 'kimi-color.svg', catalog: 'moonshotai-cn', region: Region.cn,
      keyUrl: 'https://platform.moonshot.cn/console/api-keys', blurb: l10n.providerMoonshotBlurb, aliases: ['moonshot']),
  ProviderPreset(id: 'volcengine', name: l10n.providerVolcengine, logo: 'doubao-color.svg', baseUrl: 'https://ark.cn-beijing.volces.com/api/v3', catalog: 'volcengine',
      region: Region.cn, keyUrl: 'https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey', blurb: l10n.providerVolcengineBlurb, aliases: ['doubao', 'ark', 'bytedance']),
  ProviderPreset(id: 'minimax-cn', pi: 'minimax-cn', name: 'MiniMax', logo: 'minimax-color.svg', catalog: 'minimax-cn', region: Region.cn,
      keyUrl: 'https://platform.minimaxi.com/user-center/basic-information/interface-key', blurb: l10n.providerMinimaxBlurb),
  ProviderPreset(id: 'hunyuan', name: l10n.providerHunyuan, logo: 'hunyuan-color.svg', baseUrl: 'https://api.hunyuan.cloud.tencent.com/v1', region: Region.cn,
      keyUrl: 'https://console.cloud.tencent.com/hunyuan/api-key', blurb: l10n.providerHunyuanBlurb, aliases: ['tencent']),
  ProviderPreset(id: 'qianfan', name: l10n.providerQianfan, logo: 'wenxin-color.svg', baseUrl: 'https://qianfan.baidubce.com/v2', region: Region.cn,
      keyUrl: 'https://console.bce.baidu.com/iam/#/iam/apikey/list', blurb: l10n.providerQianfanBlurb, aliases: ['ernie', '文心', 'baidu']),
  ProviderPreset(id: 'stepfun', name: l10n.providerStepfun, logo: 'stepfun-color.svg', baseUrl: 'https://api.stepfun.com/v1', catalog: 'stepfun', region: Region.cn,
      keyUrl: 'https://platform.stepfun.com/interface-key', blurb: l10n.providerStepfunBlurb, aliases: ['stepfun', 'step']),
  ProviderPreset(id: 'xiaomi', pi: 'xiaomi', name: l10n.providerMimo, logo: 'xiaomimimo.svg', mono: true, catalog: 'xiaomi', region: Region.cn,
      keyUrl: 'https://platform.xiaomimimo.com', blurb: l10n.providerMimoBlurb, aliases: ['mimo']),
  ProviderPreset(id: 'modelscope', name: l10n.providerModelscope, logo: 'modelscope-color.svg', baseUrl: 'https://api-inference.modelscope.cn/v1', catalog: 'modelscope',
      region: Region.cn, keyUrl: 'https://modelscope.cn/my/myaccesstoken', blurb: l10n.providerModelscopeBlurb),
  ProviderPreset(id: 'ai302', name: '302.AI', logo: 'ai302-color.svg', baseUrl: 'https://api.302.ai/v1', catalog: '302ai', region: Region.cn,
      keyUrl: 'https://dash.302.ai/apis/list', blurb: l10n.providerPayAsYouGoBlurb),
  ProviderPreset(id: 'aihubmix', name: 'AiHubMix', logo: 'aihubmix-color.svg', baseUrl: 'https://aihubmix.com/v1', catalog: 'aihubmix', region: Region.cn,
      keyUrl: 'https://console.aihubmix.com/token', blurb: l10n.providerOneKeyBlurb),
  ProviderPreset(id: 'ppio', name: l10n.providerPpio, logo: 'ppio-color.svg', baseUrl: 'https://api.ppinfra.com/v3/openai', region: Region.cn,
      keyUrl: 'https://ppio.com/settings/key-management', blurb: l10n.providerPpioBlurb),
  // ---- 海外 ----
  ProviderPreset(id: 'openai', pi: 'openai', name: 'OpenAI', logo: 'openai.svg', mono: true, catalog: 'openai',
      keyUrl: 'https://platform.openai.com/api-keys', blurb: l10n.providerOpenaiBlurb, aliases: ['gpt', 'chatgpt']),
  ProviderPreset(id: 'anthropic', pi: 'anthropic', name: 'Anthropic', logo: 'claude-color.svg', catalog: 'anthropic',
      keyUrl: 'https://console.anthropic.com/settings/keys', blurb: l10n.providerAnthropicBlurb, aliases: ['claude']),
  ProviderPreset(id: 'google', pi: 'google', name: 'Google Gemini', logo: 'gemini-color.svg', catalog: 'google',
      keyUrl: 'https://aistudio.google.com/apikey', blurb: l10n.providerGoogleBlurb, aliases: ['gemini']),
  ProviderPreset(id: 'openrouter', pi: 'openrouter', name: 'OpenRouter', logo: 'openrouter-color.svg', catalog: 'openrouter',
      keyUrl: 'https://openrouter.ai/keys', blurb: l10n.providerOpenrouterBlurb),
  ProviderPreset(id: 'xai', pi: 'xai', name: 'xAI', logo: 'grok.svg', mono: true, catalog: 'xai', keyUrl: 'https://console.x.ai', blurb: l10n.providerXaiBlurb, aliases: ['grok']),
  ProviderPreset(id: 'mistral', pi: 'mistral', name: 'Mistral', logo: 'mistral-color.svg', catalog: 'mistral', keyUrl: 'https://console.mistral.ai/api-keys'),
  ProviderPreset(id: 'groq', pi: 'groq', name: 'Groq', logo: 'groq.svg', mono: true, catalog: 'groq', keyUrl: 'https://console.groq.com/keys', blurb: l10n.providerGroqBlurb),
  ProviderPreset(id: 'together', pi: 'together', name: 'Together AI', logo: 'together-color.svg', catalog: 'togetherai', keyUrl: 'https://api.together.ai/settings/api-keys'),
  ProviderPreset(id: 'fireworks', pi: 'fireworks', name: 'Fireworks', logo: 'fireworks-color.svg', catalog: 'fireworks-ai', keyUrl: 'https://app.fireworks.ai/settings/users/api-keys'),
  ProviderPreset(id: 'cerebras', pi: 'cerebras', name: 'Cerebras', logo: 'cerebras-color.svg', catalog: 'cerebras', keyUrl: 'https://cloud.cerebras.ai'),
  ProviderPreset(id: 'huggingface', pi: 'huggingface', name: 'Hugging Face', logo: 'huggingface-color.svg', catalog: 'huggingface', keyUrl: 'https://huggingface.co/settings/tokens'),
  ProviderPreset(id: 'nvidia', pi: 'nvidia', name: 'NVIDIA NIM', logo: 'nvidia-color.svg', catalog: 'nvidia', keyUrl: 'https://build.nvidia.com', blurb: l10n.providerFreeTrialBlurb),
  ProviderPreset(id: 'novita', name: 'Novita AI', logo: 'novita-color.svg', baseUrl: 'https://api.novita.ai/openai', catalog: 'novita-ai', keyUrl: 'https://novita.ai/settings/key-management'),
  ProviderPreset(id: 'perplexity', name: 'Perplexity', logo: 'perplexity-color.svg', baseUrl: 'https://api.perplexity.ai', catalog: 'perplexity',
      keyUrl: 'https://www.perplexity.ai/settings/api', blurb: l10n.providerPerplexityBlurb),
  // ---- 本地 ----
  ProviderPreset(id: 'ollama', name: 'Ollama', logo: 'ollama.svg', mono: true, baseUrl: 'http://localhost:11434/v1', region: Region.local,
      needsKey: false, keyUrl: 'https://ollama.com/download', blurb: l10n.providerOllamaBlurb),
  ProviderPreset(id: 'lmstudio', name: 'LM Studio', logo: 'lmstudio.svg', mono: true, baseUrl: 'http://127.0.0.1:1234/v1', catalog: 'lmstudio',
      region: Region.local, needsKey: false, keyUrl: 'https://lmstudio.ai', blurb: l10n.providerLmstudioBlurb),
];

ProviderPreset? presetFor(String providerId) {
  for (final p in kProviderPresets) {
    if (p.providerId == providerId || p.id == providerId) return p;
  }
  return null;
}

/// Brand mark for a provider: bundled SVG for presets, the models.dev logo for
/// catalog entries, else a tonal monogram.
class ProviderLogo extends StatelessWidget {
  const ProviderLogo({super.key, required this.providerId, this.name = '', this.size = 40, this.networkLogo});
  final String providerId;
  final String name;
  final double size;
  final String? networkLogo;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final preset = presetFor(providerId);
    final inner = size * 0.6;
    Widget mark;
    if (preset != null) {
      mark = SvgPicture.asset(
        'assets/providers/${preset.logo}',
        width: inner,
        height: inner,
        colorFilter: preset.mono ? ColorFilter.mode(cs.onSurface, BlendMode.srcIn) : null,
      );
    } else if (networkLogo != null) {
      mark = SvgPicture.network(
        networkLogo!,
        width: inner,
        height: inner,
        colorFilter: ColorFilter.mode(cs.onSurface, BlendMode.srcIn),
        placeholderBuilder: (_) => _monogram(cs),
        errorBuilder: (_, _, _) => _monogram(cs),
      );
    } else {
      mark = _monogram(cs);
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: mark,
    );
  }

  Widget _monogram(ColorScheme cs) {
    final t = (name.isNotEmpty ? name : providerId).characters.first.toUpperCase();
    return Text(t, style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w700, color: cs.primary, height: 1));
  }
}
