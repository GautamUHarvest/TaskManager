// This app only ships to Flutter Web (see CLAUDE.md), so `dart:html` is the
// right fit for triggering a browser download, same as token_storage.dart.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

/// Hands [content] to the browser as a file download named [filename].
/// Nothing is uploaded anywhere; the file is built and saved client-side.
void downloadTextFile(
  String filename,
  String content, {
  String mimeType = 'text/csv;charset=utf-8',
}) {
  final blob = html.Blob([utf8.encode(content)], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  // Revoke after the click has been handed off; revoking synchronously can
  // cancel the download in some browsers.
  Timer(const Duration(seconds: 1), () => html.Url.revokeObjectUrl(url));
}
