import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [raw] in the browser — a new tab on web, the system browser on
/// mobile/desktop. A bare domain is normalised to https. If the launch fails
/// for any reason, the link is copied to the clipboard and the user is told, so
/// tapping "open" never silently does nothing.
Future<void> openLink(BuildContext context, String raw) async {
  final messenger = ScaffoldMessenger.of(context);
  final uri = normaliseLinkUri(raw);

  var launched = false;
  if (uri != null) {
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
  }
  if (launched) return;

  await Clipboard.setData(ClipboardData(text: raw));
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(content: Text("Couldn't open — link copied instead")),
    );
}

/// A bare domain (`vercel.com`) becomes `https://vercel.com`; anything that
/// already carries a scheme (`http:`, `https:`, `mailto:`…) is left alone.
/// Returns null for empty/invalid input.
Uri? normaliseLinkUri(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final parsed = Uri.tryParse(trimmed);
  if (parsed != null && parsed.hasScheme) return parsed;
  return Uri.tryParse('https://$trimmed');
}
