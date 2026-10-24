import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/look_logo.dart';
import '../../widgets/loading.dart';
import '../../l10n/l10n.dart';
import '../canvas/school_emblem.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final cs = Theme.of(context).colorScheme;
    final form = Center(
      child: SingleChildScrollView(
        padding: context.isCompact ? const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.xl) : const EdgeInsets.all(Space.xl),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400), child: LoginForm(brand: !wide)),
      ),
    );
    return Scaffold(
      backgroundColor: wide ? cs.surfaceContainer : cs.surface,
      body: SafeArea(
        child: wide
            ? Row(children: [
                const Expanded(flex: 6, child: _BrandPanel()),
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: const EdgeInsets.all(Space.lg),
                    child: Material(color: cs.surface, borderRadius: BorderRadius.circular(Corners.xxl), child: form),
                  ),
                ),
              ])
            : form,
      ),
    );
  }
}

/// Left pane: a quiet composition of M3 shapes behind the product statement.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return LayoutBuilder(builder: (context, c) {
      final s = math.min(c.maxWidth, c.maxHeight);
      return Stack(children: [
        Positioned(
          right: -s * 0.12,
          top: -s * 0.10,
          child: _Shape(size: s * 0.62, color: cs.primaryContainer, shape: const StarBorder(points: 9, innerRadiusRatio: 0.86, pointRounding: 0.6, valleyRounding: 0.4)),
        ),
        Positioned(
          left: s * 0.10,
          bottom: -s * 0.16,
          child: _Shape(size: s * 0.46, color: cs.tertiaryContainer, shape: const StarBorder.polygon(sides: 5, pointRounding: 0.5)),
        ),
        Positioned(
          right: s * 0.18,
          bottom: s * 0.16,
          child: _Shape(size: s * 0.16, color: cs.secondaryContainer, shape: const CircleBorder()),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.huge, Space.huge, Space.huge, Space.huge),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            const _BrandMark(size: 32),
            const SizedBox(height: Space.xxl),
            Text(l10n.loginHeadline, style: tt.displaySmall?.copyWith(height: 1.25, color: cs.onSurface)),
            const SizedBox(height: Space.xl),
            for (final (icon, text) in [
              (Icons.bolt_rounded, l10n.loginFeatureDownload),
              (Icons.subject_rounded, l10n.loginFeatureTranscribe),
              (Icons.auto_awesome_outlined, l10n.loginFeatureAssistant),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: Space.md),
                child: Row(children: [
                  Icon(icon, size: 20, color: cs.onSurfaceVariant),
                  const SizedBox(width: Space.md),
                  Text(text, style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
          ]),
        ),
      ]);
    });
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = size > 24 ? Theme.of(context).textTheme.titleLarge : Theme.of(context).textTheme.titleMedium;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      LookLogo(size: size + Space.lg, label: null),
      SizedBox(width: size > 24 ? Space.md : Space.sm),
      Text('Look Studio', style: style?.copyWith(color: cs.primary, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _Shape extends StatelessWidget {
  const _Shape({required this.size, required this.color, required this.shape});
  final double size;
  final Color color;
  final ShapeBorder shape;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.85, end: 1),
        duration: const Duration(milliseconds: 1200),
        curve: Motion.emphasizedDecelerate,
        builder: (_, v, child) => Transform.scale(scale: v, child: Opacity(opacity: ((v - 0.85) / 0.15).clamp(0, 1), child: child)),
        child: Container(width: size, height: size, decoration: ShapeDecoration(color: color, shape: shape)),
      );
}

class LoginForm extends StatefulWidget {
  const LoginForm({super.key, this.dialog = false, this.brand = false, this.api});

  /// Signing in again after the session lapsed: the school stays fixed.
  final bool dialog;

  /// Shows the product mark above the title (phones, where the brand pane is hidden).
  final bool brand;

  /// Answers lookd calls in tests; defaults to the app's daemon.
  final ApiCall? api;
  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> with SingleTickerProviderStateMixin {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _captcha = TextEditingController();
  final _passFocus = FocusNode();
  List<Map<String, dynamic>>? _schools;
  Object? _schoolsError;
  String _school = 'tongji';
  bool _obscure = true;
  bool _remember = true;
  bool _busy = false;
  bool _needCaptcha = false;
  int _captchaNonce = 0;
  String? _error;
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  ApiCall get _call => widget.api ?? context.read<AppState>().api.call;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AppState?>()?.auth;
    _user.text = auth?.username ?? '';
    _school = auth?.school ?? 'tongji';
    _loadSchools();
  }

  /// The schools whose lecture platform lookd signs in to (`look: true`).
  Future<void> _loadSchools() async {
    setState(() => _schoolsError = null);
    try {
      final r = await _call('GET', '/api/schools') as List;
      if (!mounted) return;
      setState(() => _schools = [for (final s in r.cast<Map>()) if (s['look'] == true) s.cast<String, dynamic>()]);
    } catch (e) {
      if (mounted) setState(() => _schoolsError = e);
    }
  }

  void _pick(String id) {
    if (id == _school) return;
    setState(() {
      _school = id;
      _error = null;
      _needCaptcha = false;
      _captcha.clear();
    });
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _captcha.dispose();
    _passFocus.dispose();
    _shake.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = l10n.loginMissingCredentials);
      _shake.forward(from: 0);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = <String, Object>{'school': _school, 'username': _user.text.trim(), 'password': _pass.text, 'captcha': _captcha.text.trim(), 'remember': _remember};
      if (widget.api case final call?) {
        await call('POST', '/api/auth/login', body);
      } else {
        await context.read<AppState>().login(body);
      }
      if (mounted && widget.dialog) Navigator.of(context).pop();
    } on ApiError catch (e) {
      setState(() {
        _error = e.message;
        if (e.captcha) {
          _needCaptcha = true;
          _captchaNonce++;
          _captcha.clear();
        }
      });
      _shake.forward(from: 0);
      HapticFeedback.mediumImpact();
    } catch (e) {
      setState(() => _error = '$e');
      _shake.forward(from: 0);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final captcha = _needCaptcha && _school == 'tongji';
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final t = _shake.value;
        final dx = math.sin(t * math.pi * 5) * 10 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Padding(
        padding: widget.dialog ? const EdgeInsets.all(Space.xl) : EdgeInsets.zero,
        child: AutofillGroup(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.brand && !widget.dialog) ...[
              const Align(alignment: AlignmentDirectional.centerStart, child: _BrandMark(size: 24)),
              const SizedBox(height: Space.xxl),
            ],
            Text(widget.dialog ? l10n.loginSignInAgain : l10n.loginSignIn, style: tt.headlineMedium),
            const SizedBox(height: Space.sm),
            Text(widget.dialog ? _schoolName : l10n.loginChooseSchool, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: Space.xl),
            if (!widget.dialog) ...[
              _schoolPicker(cs, tt),
              const SizedBox(height: Space.sm),
            ],
            Text(_school == 'fudan' ? l10n.loginHintFudan : l10n.loginHintTongji, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: Space.xl),
            TextField(
              controller: _user,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _passFocus.requestFocus(),
              decoration: InputDecoration(labelText: l10n.loginStudentId, prefixIcon: Icon(Icons.badge_outlined)),
            ),
            const SizedBox(height: Space.lg),
            TextField(
              controller: _pass,
              focusNode: _passFocus,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              textInputAction: captcha ? TextInputAction.next : TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: l10n.commonPassword,
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: _obscure ? l10n.commonShowPassword : l10n.commonHidePassword,
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: AnimatedSwitcher(
                    duration: Motion.short4,
                    child: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, key: ValueKey(_obscure)),
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: Motion.medium4,
              curve: Motion.emphasized,
              child: !captcha
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: Space.lg),
                      child: Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _captcha,
                            onSubmitted: (_) => _submit(),
                            decoration: InputDecoration(labelText: l10n.loginCaptcha, prefixIcon: Icon(Icons.pin_outlined)),
                          ),
                        ),
                        const SizedBox(width: Space.md),
                        InkWell(
                          borderRadius: BorderRadius.circular(Corners.sm),
                          onTap: () => setState(() => _captchaNonce++),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(Corners.sm),
                            child: Image.network(
                              '${context.read<AppState>().api.baseUrl}/api/auth/captcha?n=$_captchaNonce',
                              headers: {'Authorization': 'Bearer ${context.read<AppState>().api.token}'},
                              width: 120,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(width: 120, height: 56, color: cs.surfaceContainerHigh, child: const Icon(Icons.refresh_rounded)),
                            ),
                          ),
                        ),
                      ]),
                    ),
            ),
            const SizedBox(height: Space.md),
            MergeSemantics(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.loginStaySignedIn),
                subtitle: Text(l10n.loginStaySignedInHint),
                trailing: Switch(value: _remember, onChanged: (v) => setState(() => _remember = v)),
                onTap: () => setState(() => _remember = !_remember),
              ),
            ),
            AnimatedSize(
              duration: Motion.medium2,
              curve: Motion.emphasized,
              child: _error == null
                  ? const SizedBox(width: double.infinity)
                  : Container(
                      margin: const EdgeInsets.only(top: Space.sm),
                      padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
                      decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(Corners.md)),
                      child: Row(children: [
                        Icon(Icons.error_outline_rounded, color: cs.onErrorContainer, size: 20),
                        const SizedBox(width: Space.md),
                        Expanded(child: Text(_error!, style: tt.bodyMedium?.copyWith(color: cs.onErrorContainer))),
                      ]),
                    ),
            ),
            const SizedBox(height: Space.xl),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(textStyle: tt.titleMedium),
                child: AnimatedSwitcher(
                  duration: Motion.short4,
                  child: _busy
                      ? ExpressiveLoader(key: const ValueKey('l'), size: 28, color: cs.onSurface.withValues(alpha: 0.6))
                      : Text(l10n.loginSignIn, key: ValueKey('t')),
                ),
              ),
            ),
            const SizedBox(height: Space.lg),
            Text(
              l10n.loginPrivacy,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      ),
    );
  }

  String get _schoolName {
    for (final s in _schools ?? const <Map<String, dynamic>>[]) {
      if (s['id'] == _school) return '${s['name']}';
    }
    return _school == 'fudan' ? l10n.schoolFudan : l10n.schoolTongji;
  }

  Widget _schoolPicker(ColorScheme cs, TextTheme tt) {
    final schools = _schools;
    if (_schoolsError != null) {
      return Row(children: [
        Expanded(child: Text(l10n.loginSchoolsFailed(_schoolsError!), style: tt.bodyMedium?.copyWith(color: cs.error))),
        TextButton(onPressed: _loadSchools, child: Text(l10n.commonRetry)),
      ]);
    }
    if (schools == null) return const SizedBox(height: _SchoolTile.height);
    return Semantics(
      label: l10n.commonSchool,
      child: Row(children: [
        for (final (i, s) in schools.indexed) ...[
          if (i > 0) const SizedBox(width: Space.md),
          Expanded(child: _SchoolTile(school: s, selected: s['id'] == _school, onTap: () => _pick('${s['id']}'))),
        ],
      ]),
    );
  }
}

/// One school in the picker: emblem, name, and a radio mark for the choice.
class _SchoolTile extends StatelessWidget {
  const _SchoolTile({required this.school, required this.selected, required this.onTap});
  final Map<String, dynamic> school;
  final bool selected;
  final VoidCallback onTap;
  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final name = '${school['name']}';
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Corners.lg),
      side: BorderSide(color: selected ? cs.primary : cs.outlineVariant),
    );
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected ? cs.surfaceContainerHighest : Colors.transparent,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: Space.md, end: Space.sm),
              child: Row(children: [
                SchoolEmblem(id: '${school['id']}', name: name, url: '${school['emblem_url'] ?? ''}', size: 36),
                const SizedBox(width: Space.sm),
                Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.titleSmall)),
                Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 20, color: selected ? cs.primary : cs.outline),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
