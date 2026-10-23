import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/loading.dart';
import '../../l10n/l10n.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final cs = Theme.of(context).colorScheme;
    final form = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xl),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400), child: const LoginForm()),
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
            Row(children: [
              Icon(Icons.motion_photos_on_rounded, color: cs.primary, size: 32),
              const SizedBox(width: Space.md),
              Text('Look Studio', style: tt.titleLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w600)),
            ]),
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
  const LoginForm({super.key, this.dialog = false});
  final bool dialog;
  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> with SingleTickerProviderStateMixin {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _captcha = TextEditingController();
  final _passFocus = FocusNode();
  bool _obscure = true;
  bool _remember = true;
  bool _busy = false;
  bool _needCaptcha = false;
  int _captchaNonce = 0;
  String? _error;
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void initState() {
    super.initState();
    final auth = context.read<AppState>().auth;
    _user.text = auth.username;
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
      await context.read<AppState>().login(_user.text.trim(), _pass.text, captcha: _captcha.text.trim(), remember: _remember);
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
    final api = context.read<AppState>().api;
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
            Text(widget.dialog ? l10n.loginSignInAgain : l10n.loginSignIn, style: tt.headlineMedium),
            const SizedBox(height: Space.sm),
            Text(l10n.loginWithTongji, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: Space.xxl),
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
              textInputAction: _needCaptcha ? TextInputAction.next : TextInputAction.done,
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
              child: !_needCaptcha
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
                              '${api.baseUrl}/api/auth/captcha?n=$_captchaNonce',
                              headers: {'Authorization': 'Bearer ${api.token}'},
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
}
