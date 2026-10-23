import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/profile.dart';
import '../../theme/tokens.dart';
import '../../widgets/horizontal_scroller.dart';
import '../../widgets/states.dart';
import '../../widgets/user_avatar.dart';

/// Edit nickname and avatar. Changes apply immediately.
Future<void> showProfileDialog(BuildContext context) =>
    showDialog(context: context, useRootNavigator: true, builder: (_) => const _ProfileDialog());

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog();
  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final _name = TextEditingController(text: context.read<UserProfile>().nickname);
  final _menu = MenuController();
  List<String> _ideas = List.generate(6, (_) => UserProfile.randomSeed());

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final f = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: '图片', extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'], mimeTypes: ['image/*']),
    ]);
    if (f == null || !mounted) return;
    try {
      await context.read<UserProfile>().setFile(f.path);
    } catch (e) {
      if (mounted) showSnack(context, '没能使用这张图片：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<UserProfile>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final a = context.select<AppState, (String, String)>((s) => (s.auth.realname, s.auth.username));
    final fallback = a.$1.isNotEmpty ? a.$1 : a.$2;
    final toned = p.kind == AvatarKind.emoji || p.kind == AvatarKind.initial;

    final menuItems = [
      MenuItemButton(
        leadingIcon: const Icon(Icons.emoji_emotions_outlined),
        onPressed: () async {
          final r = await showEmojiPicker(context, initial: p.kind == AvatarKind.emoji ? p.value : '');
          if (r != null) p.setEmoji(r);
        },
        child: const Text('选择表情'),
      ),
      MenuItemButton(leadingIcon: const Icon(Icons.image_outlined), onPressed: _pickFile, child: const Text('从图片文件…')),
      MenuItemButton(
        leadingIcon: const Icon(Icons.link_rounded),
        onPressed: () async {
          final r = await _showLinkDialog(context, qq: false);
          if (r != null) p.setUrl(r);
        },
        child: const Text('输入图片链接…'),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.chat_bubble_outline_rounded),
        onPressed: () async {
          final r = await _showLinkDialog(context, qq: true);
          if (r != null) p.setQQ(r);
        },
        child: const Text('使用 QQ 头像…'),
      ),
      MenuItemButton(leadingIcon: const Icon(Icons.auto_awesome_outlined), onPressed: () => p.setArt(UserProfile.randomSeed()), child: const Text('随机生成图形')),
      const Divider(height: 1),
      MenuItemButton(leadingIcon: const Icon(Icons.restart_alt_rounded), onPressed: p.reset, child: const Text('重置为首字')),
    ];

    return Dialog(
      backgroundColor: cs.surfaceContainerHigh,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, Space.lg),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('个人资料', style: tt.headlineSmall),
            const SizedBox(height: Space.xs),
            Text('昵称和头像只保存在这台设备上', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: Space.xl),
            Center(
              child: MenuAnchor(
                controller: _menu,
                alignmentOffset: const Offset(-40, 8),
                menuChildren: menuItems,
                child: _EditableAvatar(onTap: () => _menu.isOpen ? _menu.close() : _menu.open()),
              ),
            ),
            const SizedBox(height: Space.xl),
            TextField(
              controller: _name,
              maxLength: 24,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: '昵称',
                hintText: fallback,
                helperText: '留空则显示「$fallback」',
                prefixIcon: const Icon(Icons.badge_outlined),
              ),
              onChanged: p.setNickname,
              onSubmitted: (_) => Navigator.pop(context),
            ),
            const SizedBox(height: Space.lg),
            Row(children: [
              Text('灵感', style: tt.titleSmall),
              const SizedBox(width: Space.sm),
              Text('点一下换上', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              const Spacer(),
              IconButton(
                tooltip: '换一批',
                onPressed: () => setState(() => _ideas = List.generate(6, (_) => UserProfile.randomSeed())),
                icon: const Icon(Icons.shuffle_rounded),
              ),
            ]),
            const SizedBox(height: Space.xs),
            AnimatedSwitcher(
              duration: Motion.medium2,
              child: Row(
                key: ValueKey(_ideas.first),
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final seed in _ideas)
                    _Pick(
                      selected: p.kind == AvatarKind.art && p.value == seed,
                      onTap: () => p.setArt(seed),
                      child: AvatarView(kind: AvatarKind.art, value: seed, frame: p.frame, size: 52),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.lg),
            Text('轮廓', style: tt.titleSmall),
            const SizedBox(height: Space.sm),
            SegmentedButton<AvatarFrame>(
              showSelectedIcon: false,
              segments: [for (final f in AvatarFrame.values) ButtonSegment(value: f, label: Text(f.label))],
              selected: {p.frame},
              onSelectionChanged: (s) => p.update((x) => x.frame = s.first),
            ),
            AnimatedSize(
              duration: Motion.medium2,
              curve: Motion.emphasized,
              alignment: Alignment.topCenter,
              child: toned
                  ? Padding(
                      padding: const EdgeInsets.only(top: Space.lg),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('底色', style: tt.titleSmall),
                        const SizedBox(height: Space.sm),
                        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
                          for (var i = 0; i < kAvatarTones.length; i++) _ToneDot(index: i, selected: p.tone == i, onTap: () => p.update((x) => x.tone = i)),
                        ]),
                      ]),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: Space.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('首页显示一言'),
              subtitle: const Text('欢迎语下方展示一句文学、诗词或哲思'),
              value: p.showQuote,
              onChanged: (v) => p.update((x) => x.showQuote = v),
            ),
            const SizedBox(height: Space.sm),
            Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('完成'))),
          ]),
        ),
      ),
    );
  }
}

class _EditableAvatar extends StatefulWidget {
  const _EditableAvatar({required this.onTap});
  final VoidCallback onTap;
  @override
  State<_EditableAvatar> createState() => _EditableAvatarState();
}

class _EditableAvatarState extends State<_EditableAvatar> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: '更换头像',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _hover ? 1.04 : 1,
            duration: Motion.medium2,
            curve: Motion.emphasized,
            child: Stack(clipBehavior: Clip.none, children: [
              AnimatedSwitcher(
                duration: Motion.medium2,
                switchInCurve: Motion.emphasizedDecelerate,
                transitionBuilder: (c, a) => ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(a), child: FadeTransition(opacity: a, child: c)),
                child: KeyedSubtree(key: ValueKey(context.select<UserProfile, Object>((p) => (p.kind, p.value, p.frame))), child: const UserAvatar(size: 104)),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle, border: Border.all(color: cs.surfaceContainerHigh, width: 3)),
                  child: Icon(Icons.edit_rounded, size: 16, color: cs.onPrimary),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Pick extends StatelessWidget {
  const _Pick({required this.selected, required this.onTap, required this.child});
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkResponse(
      onTap: onTap,
      radius: 32,
      child: AnimatedContainer(
        duration: Motion.medium1,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? cs.primary : Colors.transparent, width: 2)),
        child: child,
      ),
    );
  }
}

class _ToneDot extends StatelessWidget {
  const _ToneDot({required this.index, required this.selected, required this.onTap});
  final int index;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg) = avatarToneColors(context, index);
    return Tooltip(
      message: index == 0 ? '跟随主题' : '底色 $index',
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: AnimatedContainer(
          duration: Motion.medium1,
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(color: selected ? cs.primary : cs.outlineVariant, width: selected ? 2.5 : 1),
          ),
          child: selected ? Icon(Icons.check_rounded, size: 16, color: fg) : (index == 0 ? Icon(Icons.palette_outlined, size: 14, color: fg) : null),
        ),
      ),
    );
  }
}

/// Image link or QQ number input with a live, debounced preview.
Future<String?> _showLinkDialog(BuildContext context, {required bool qq}) {
  final ctl = TextEditingController();
  Timer? debounce;
  var preview = '';
  bool valid(String s) => qq ? UserProfile.validQQ(s) : RegExp(r'^https?://\S+$').hasMatch(s.trim());
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(builder: (context, set) {
      final ok = valid(ctl.text);
      return AlertDialog(
        icon: Icon(qq ? Icons.chat_bubble_outline_rounded : Icons.link_rounded),
        title: Text(qq ? '使用 QQ 头像' : '图片链接'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedSwitcher(
              duration: Motion.medium2,
              child: preview.isEmpty
                  ? Container(
                      key: const ValueKey(0),
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, shape: BoxShape.circle),
                      child: Icon(Icons.image_search_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    )
                  : AvatarView(key: ValueKey(preview), kind: AvatarKind.url, value: preview, size: 88, name: '?'),
            ),
            const SizedBox(height: Space.lg),
            TextField(
              controller: ctl,
              autofocus: true,
              keyboardType: qq ? TextInputType.number : TextInputType.url,
              decoration: InputDecoration(
                labelText: qq ? 'QQ 号' : '图片地址',
                hintText: qq ? '5–12 位数字' : 'https://example.com/avatar.png',
                errorText: ctl.text.isNotEmpty && !ok ? (qq ? '请输入 5–12 位 QQ 号' : '需要 http(s) 链接') : null,
              ),
              onChanged: (s) {
                set(() {});
                debounce?.cancel();
                debounce = Timer(const Duration(milliseconds: 450), () {
                  if (!context.mounted) return;
                  set(() => preview = valid(s) ? (qq ? UserProfile.qqAvatarUrl(s.trim()) : s.trim()) : '');
                });
              },
              onSubmitted: (s) {
                if (valid(s)) Navigator.pop(context, s.trim());
              },
            ),
            if (qq) ...[
              const SizedBox(height: Space.sm),
              Text('头像从 QQ 公开头像服务加载，需要联网', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: ok ? () => Navigator.pop(context, ctl.text.trim()) : null, child: const Text('使用')),
        ],
      );
    }),
  ).whenComplete(() {
    debounce?.cancel();
    // The route is still animating out; release the controller afterwards.
    Future.delayed(Motion.long2, ctl.dispose);
  });
}

const _emojiGroups = <(String, String)>[
  ('学习', '📚 📖 ✏️ 📝 🎓 🧠 💡 🔬 🔭 🧪 🧮 📐 📏 🖊️ 🗂️ 📎 🎒 🏫 💻 ⌨️ 📊 🧭 🌏 🗺️'),
  ('表情', '😀 😄 😁 😆 😊 🙂 😉 😍 🥰 😎 🤓 🧐 🤔 😴 🥱 😌 😇 🤗 🤩 🥳 😺 😸 🫠 🫡'),
  ('动物', '🐱 🐶 🐼 🐨 🦊 🐻 🐰 🐹 🐯 🦁 🐮 🐷 🐸 🐵 🐧 🐦 🦉 🦄 🐝 🦋 🐢 🐬 🐳 🦕'),
  ('自然', '🌸 🌼 🌻 🌷 🌹 🍀 🌿 🌵 🌲 🍁 🍂 🌙 ⭐ 🌈 ☀️ ⛅ ❄️ 🌊 🔥 ⚡ 🪐 🌍 🍄 🌾'),
  ('食物', '🍎 🍊 🍋 🍉 🍓 🍑 🍒 🥝 🍞 🥐 🍩 🍪 🍰 🧁 🍫 🍬 🍙 🍜 🍣 🥟 ☕ 🧋 🍵 🥤'),
  ('爱好', '⚽ 🏀 🏸 🏓 🎾 🏐 🎮 🎧 🎸 🎹 🎨 📷 🎬 🚀 ✈️ 🚲 ⛵ 🏝️ 🎈 🎁 🔑 🧩 🪴 ⏰'),
];

/// Grid of curated emoji plus free input for any emoji.
Future<String?> showEmojiPicker(BuildContext context, {String initial = ''}) {
  final ctl = TextEditingController(text: initial);
  var group = 0;
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(builder: (context, set) {
      final cs = Theme.of(context).colorScheme;
      final typed = ctl.text.trim().isEmpty ? '' : ctl.text.trim().characters.first;
      final list = _emojiGroups[group].$2.split(' ');
      return AlertDialog(
        title: const Text('选择表情'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: ctl,
              decoration: InputDecoration(
                hintText: '输入或粘贴任意表情',
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(Space.sm),
                  child: Text(typed.isEmpty ? '🙂' : typed, style: TextStyle(fontSize: 22, color: typed.isEmpty ? cs.outline : null)),
                ),
              ),
              onChanged: (_) => set(() {}),
              onSubmitted: (_) {
                if (typed.isNotEmpty) Navigator.pop(context, typed);
              },
            ),
            const SizedBox(height: Space.md),
            HorizontalScroller(fade: true, builder: (c) => SingleChildScrollView(
              controller: c,
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (var i = 0; i < _emojiGroups.length; i++) ...[
                  ChoiceChip(label: Text(_emojiGroups[i].$1), selected: group == i, onSelected: (_) => set(() => group = i)),
                  const SizedBox(width: Space.xs),
                ],
              ]),
            )),
            const SizedBox(height: Space.md),
            SizedBox(
              height: 200,
              child: AnimatedSwitcher(
                duration: Motion.medium1,
                child: GridView.builder(
                  key: ValueKey(group),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 48, mainAxisSpacing: 4, crossAxisSpacing: 4),
                  itemCount: list.length,
                  itemBuilder: (context, i) => InkWell(
                    borderRadius: BorderRadius.circular(Corners.md),
                    onTap: () => Navigator.pop(context, list[i]),
                    child: Center(child: Text(list[i], style: const TextStyle(fontSize: 26))),
                  ),
                ),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: typed.isEmpty ? null : () => Navigator.pop(context, typed), child: const Text('使用')),
        ],
      );
    }),
  ).whenComplete(() => Future.delayed(Motion.long2, ctl.dispose));
}
