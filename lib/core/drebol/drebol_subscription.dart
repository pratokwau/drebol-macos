import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Drebol subscriptions: only links from our own panel host are accepted,
/// and every subscription request carries the device id the panel requires.
abstract final class DrebolSubscriptionValidator {
  static const subscriptionHost = 'key.drbl.tech';

  static bool isDrebolSubscriptionUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    return uri != null && uri.host.toLowerCase() == subscriptionHost;
  }

  /// Extracts a Drebol subscription link from mixed text (e.g. a whole bot
  /// message). Adds https:// when the scheme is missing and strips trailing
  /// punctuation. Returns null when there is no Drebol link in the text.
  static String? extractSubscriptionUrl(String text) {
    final match = RegExp(
      r'(?:https?://)?key\.drbl\.tech/[^\s<>\x22\x27\)\]]+',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    var url = match.group(0)!.replaceAll(RegExp(r'[.,;:!?]+$'), '');
    if (!url.toLowerCase().startsWith('http')) url = 'https://$url';
    return isDrebolSubscriptionUrl(url) ? url : null;
  }
}

/// Stable per-install device id, sent as the x-hwid header. The Remnawave
/// panel requires it, otherwise it answers subscription requests with a stub
/// instead of the servers.
abstract final class DrebolDevice {
  static String? _id;
  static final _fallbackId = const Uuid().v4();

  /// The id to send. Before [ensureInitialized] runs (app start) this is an
  /// in-memory UUID; after init it is the persisted one.
  static String get id => _id ?? _fallbackId;

  static Future<void> ensureInitialized() async {
    if (_id != null) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/drebol-device.json');
      if (await file.exists()) {
        final stored = (jsonDecode(await file.readAsString()) as Map)['hwid'];
        if (stored is String && stored.isNotEmpty) {
          _id = stored;
          return;
        }
      }
      _id = const Uuid().v4();
      await file.writeAsString(jsonEncode({'hwid': _id}));
    } catch (_) {
      // storage unavailable: keep the in-memory id for this run
      _id ??= _fallbackId;
    }
  }
}
