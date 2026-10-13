import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
  cn('国内'),
  global('海外'),
  local('本地');

  const Region(this.label);
  final String label;
}

const kProviderPresets = <ProviderPreset>[
  // ---- 国内 ----
  ProviderPreset(id: 'deepseek', pi: 'deepseek', name: 'DeepSeek', logo: 'deepseek-color.svg', catalog: 'deepseek', region: Region.cn,
      keyUrl: 'https://platform.deepseek.com/api_keys', blurb: '深度求索，性价比高的推理与对话模型', aliases: ['深度求索']),
  ProviderPreset(id: 'siliconflow', name: '硅基流动', logo: 'siliconcloud-color.svg', baseUrl: 'https://api.siliconflow.cn/v1', catalog: 'siliconflow-cn',
      region: Region.cn, keyUrl: 'https://cloud.siliconflow.cn/account/ak', blurb: '聚合 Qwen、DeepSeek、GLM 等开源模型', aliases: ['SiliconFlow', 'siliconcloud']),
  ProviderPreset(id: 'bailian', name: '阿里云百炼', logo: 'bailian-color.svg', baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1', catalog: 'alibaba-cn',
      region: Region.cn, keyUrl: 'https://bailian.console.aliyun.com/?apiKey=1', blurb: '通义千问 Qwen 全系列', aliases: ['qwen', 'dashscope', '通义', 'alibaba']),
  ProviderPreset(id: 'zhipu', name: '智谱 BigModel', logo: 'zhipu-color.svg', baseUrl: 'https://open.bigmodel.cn/api/paas/v4', catalog: 'zhipuai',
      region: Region.cn, keyUrl: 'https://bigmodel.cn/usercenter/proj-mgmt/apikeys', blurb: 'GLM 系列', aliases: ['glm', 'zhipuai', 'chatglm']),
  ProviderPreset(id: 'moonshotai-cn', pi: 'moonshotai-cn', name: 'Kimi 月之暗面', logo: 'kimi-color.svg', catalog: 'moonshotai-cn', region: Region.cn,
      keyUrl: 'https://platform.moonshot.cn/console/api-keys', blurb: '长上下文的 Kimi 模型', aliases: ['moonshot']),
  ProviderPreset(id: 'volcengine', name: '火山方舟 · 豆包', logo: 'doubao-color.svg', baseUrl: 'https://ark.cn-beijing.volces.com/api/v3', catalog: 'volcengine',
      region: Region.cn, keyUrl: 'https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey', blurb: '字节跳动豆包大模型', aliases: ['doubao', 'ark', 'bytedance']),
  ProviderPreset(id: 'minimax-cn', pi: 'minimax-cn', name: 'MiniMax', logo: 'minimax-color.svg', catalog: 'minimax-cn', region: Region.cn,
      keyUrl: 'https://platform.minimaxi.com/user-center/basic-information/interface-key', blurb: '稀宇科技 MiniMax 模型'),
  ProviderPreset(id: 'hunyuan', name: '腾讯混元', logo: 'hunyuan-color.svg', baseUrl: 'https://api.hunyuan.cloud.tencent.com/v1', region: Region.cn,
      keyUrl: 'https://console.cloud.tencent.com/hunyuan/api-key', blurb: '腾讯混元大模型', aliases: ['tencent']),
  ProviderPreset(id: 'qianfan', name: '百度千帆', logo: 'wenxin-color.svg', baseUrl: 'https://qianfan.baidubce.com/v2', region: Region.cn,
      keyUrl: 'https://console.bce.baidu.com/iam/#/iam/apikey/list', blurb: '文心 ERNIE 系列', aliases: ['ernie', '文心', 'baidu']),
  ProviderPreset(id: 'stepfun', name: '阶跃星辰', logo: 'stepfun-color.svg', baseUrl: 'https://api.stepfun.com/v1', catalog: 'stepfun', region: Region.cn,
      keyUrl: 'https://platform.stepfun.com/interface-key', blurb: 'Step 系列多模态模型', aliases: ['stepfun', 'step']),
  ProviderPreset(id: 'xiaomi', pi: 'xiaomi', name: '小米 MiMo', logo: 'xiaomimimo.svg', mono: true, catalog: 'xiaomi', region: Region.cn,
      keyUrl: 'https://platform.xiaomimimo.com', blurb: '小米 MiMo 推理模型', aliases: ['mimo']),
  ProviderPreset(id: 'modelscope', name: '魔搭 ModelScope', logo: 'modelscope-color.svg', baseUrl: 'https://api-inference.modelscope.cn/v1', catalog: 'modelscope',
      region: Region.cn, keyUrl: 'https://modelscope.cn/my/myaccesstoken', blurb: '每日免费额度的开源模型推理'),
  ProviderPreset(id: 'ai302', name: '302.AI', logo: 'ai302-color.svg', baseUrl: 'https://api.302.ai/v1', catalog: '302ai', region: Region.cn,
      keyUrl: 'https://dash.302.ai/apis/list', blurb: '按量付费的模型聚合平台'),
  ProviderPreset(id: 'aihubmix', name: 'AiHubMix', logo: 'aihubmix-color.svg', baseUrl: 'https://aihubmix.com/v1', catalog: 'aihubmix', region: Region.cn,
      keyUrl: 'https://console.aihubmix.com/token', blurb: '一个 Key 调用多家模型'),
  ProviderPreset(id: 'ppio', name: 'PPIO 派欧云', logo: 'ppio-color.svg', baseUrl: 'https://api.ppinfra.com/v3/openai', region: Region.cn,
      keyUrl: 'https://ppio.com/settings/key-management', blurb: '分布式云上的开源模型 API'),
  // ---- 海外 ----
  ProviderPreset(id: 'openai', pi: 'openai', name: 'OpenAI', logo: 'openai.svg', mono: true, catalog: 'openai',
      keyUrl: 'https://platform.openai.com/api-keys', blurb: 'GPT 系列', aliases: ['gpt', 'chatgpt']),
  ProviderPreset(id: 'anthropic', pi: 'anthropic', name: 'Anthropic', logo: 'claude-color.svg', catalog: 'anthropic',
      keyUrl: 'https://console.anthropic.com/settings/keys', blurb: 'Claude 系列', aliases: ['claude']),
  ProviderPreset(id: 'google', pi: 'google', name: 'Google Gemini', logo: 'gemini-color.svg', catalog: 'google',
      keyUrl: 'https://aistudio.google.com/apikey', blurb: 'Gemini 系列，AI Studio 密钥', aliases: ['gemini']),
  ProviderPreset(id: 'openrouter', pi: 'openrouter', name: 'OpenRouter', logo: 'openrouter-color.svg', catalog: 'openrouter',
      keyUrl: 'https://openrouter.ai/keys', blurb: '数百个模型的统一入口'),
  ProviderPreset(id: 'xai', pi: 'xai', name: 'xAI', logo: 'grok.svg', mono: true, catalog: 'xai', keyUrl: 'https://console.x.ai', blurb: 'Grok 系列', aliases: ['grok']),
  ProviderPreset(id: 'mistral', pi: 'mistral', name: 'Mistral', logo: 'mistral-color.svg', catalog: 'mistral', keyUrl: 'https://console.mistral.ai/api-keys'),
  ProviderPreset(id: 'groq', pi: 'groq', name: 'Groq', logo: 'groq.svg', mono: true, catalog: 'groq', keyUrl: 'https://console.groq.com/keys', blurb: 'LPU 极速推理'),
  ProviderPreset(id: 'together', pi: 'together', name: 'Together AI', logo: 'together-color.svg', catalog: 'togetherai', keyUrl: 'https://api.together.ai/settings/api-keys'),
  ProviderPreset(id: 'fireworks', pi: 'fireworks', name: 'Fireworks', logo: 'fireworks-color.svg', catalog: 'fireworks-ai', keyUrl: 'https://app.fireworks.ai/settings/users/api-keys'),
  ProviderPreset(id: 'cerebras', pi: 'cerebras', name: 'Cerebras', logo: 'cerebras-color.svg', catalog: 'cerebras', keyUrl: 'https://cloud.cerebras.ai'),
  ProviderPreset(id: 'huggingface', pi: 'huggingface', name: 'Hugging Face', logo: 'huggingface-color.svg', catalog: 'huggingface', keyUrl: 'https://huggingface.co/settings/tokens'),
  ProviderPreset(id: 'nvidia', pi: 'nvidia', name: 'NVIDIA NIM', logo: 'nvidia-color.svg', catalog: 'nvidia', keyUrl: 'https://build.nvidia.com', blurb: '免费试用额度'),
  ProviderPreset(id: 'novita', name: 'Novita AI', logo: 'novita-color.svg', baseUrl: 'https://api.novita.ai/openai', catalog: 'novita-ai', keyUrl: 'https://novita.ai/settings/key-management'),
  ProviderPreset(id: 'perplexity', name: 'Perplexity', logo: 'perplexity-color.svg', baseUrl: 'https://api.perplexity.ai', catalog: 'perplexity',
      keyUrl: 'https://www.perplexity.ai/settings/api', blurb: '联网搜索的 Sonar 模型'),
  // ---- 本地 ----
  ProviderPreset(id: 'ollama', name: 'Ollama', logo: 'ollama.svg', mono: true, baseUrl: 'http://localhost:11434/v1', region: Region.local,
      needsKey: false, keyUrl: 'https://ollama.com/download', blurb: '在本机运行开源模型'),
  ProviderPreset(id: 'lmstudio', name: 'LM Studio', logo: 'lmstudio.svg', mono: true, baseUrl: 'http://127.0.0.1:1234/v1', catalog: 'lmstudio',
      region: Region.local, needsKey: false, keyUrl: 'https://lmstudio.ai', blurb: '图形化的本地模型服务'),
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
