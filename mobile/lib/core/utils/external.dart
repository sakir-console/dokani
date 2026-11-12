import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the phone's share sheet (WhatsApp, Messenger, SMS, …) with some text.
/// Behind a provider so tests can observe what would be shared.
final shareTextProvider = Provider<Future<void> Function(String text)>(
  (ref) => (text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  },
);

/// Opens a link in the phone's browser. Returns false when nothing could open it.
final openUrlProvider = Provider<Future<bool> Function(Uri url)>(
  (ref) => (url) => launchUrl(url, mode: LaunchMode.externalApplication),
);

/// Hands a file to the phone's share sheet: save it, open it in Excel or a
/// PDF reader, or send it by WhatsApp or email.
final shareFileProvider = Provider<Future<void> Function(String path, String name)>(
  (ref) => (path, name) async {
    await SharePlus.instance.share(ShareParams(files: [XFile(path, name: name)]));
  },
);
