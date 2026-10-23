import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

// Every user-facing string lives in app_zh.arb under a key; code reads it as
// `l10n.someKey` or `l10n.someKey(arg)`. Run `flutter gen-l10n` (or any
// build) after editing the ARB file.

/// Strings of the app's locale, also for code without a BuildContext
/// (controllers, services, top-level tables). [LookApp] keeps it in step
/// with the locale MaterialApp resolves.
AppLocalizations l10n = lookupAppLocalizations(const Locale('zh'));
