// This app only ships to Flutter Web (see CLAUDE.md), so `dart:html`'s
// WebSocket is the right fit and avoids pulling in web_socket_channel. The
// `package:web` migration can wait until the rest of the project moves off
// `dart:html` (token_storage.dart has the same note).
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import '../api/api_client.dart';
import '../tasks/task_models.dart';

/// Derives the WebSocket URL from the REST base URL, so both follow the same
/// `API_BASE_URL` dart-define and the same origin in production.
///
/// `/api` (the production default, served by nginx on the page's own origin)
/// becomes `ws(s)://<page host>/ws/notifications`; an absolute base such as
/// `https://192.168.0.23/api` becomes `wss://192.168.0.23/ws/notifications`.
/// The scheme follows the base: https -> wss, http -> ws.
String resolveSocketUrl({String? baseUrl, Uri? pageUri}) {
  final base = normalizeBaseUrl(baseUrl);
  final page = pageUri ?? Uri.base;

  // Relative base (same origin as the page).
  if (!base.startsWith('http://') && !base.startsWith('https://')) {
    final scheme = page.scheme == 'https' ? 'wss' : 'ws';
    return '$scheme://${page.authority}/ws/notifications';
  }

  final parsed = Uri.parse(base);
  final scheme = parsed.scheme == 'https' ? 'wss' : 'ws';
  return '$scheme://${parsed.authority}/ws/notifications';
}

/// Live channel for blocker alerts.
///
/// The browser cannot set an `Authorization` header on a WebSocket handshake,
/// and a token in the query string would land in nginx/Drogon access logs, so
/// this sends `{"type":"auth","access_token":...}` as its first frame and the
/// server binds the socket to that user. The server closes any socket that
/// has not authenticated within its grace period.
///
/// Reconnects with capped exponential backoff. Because the access token is
/// short-lived (10 min) and may have rotated between attempts, the token is
/// fetched fresh for each connect through the [tokenProvider] callback rather
/// than captured once.
class BlockerSocket {
  BlockerSocket({
    required Future<String> Function() tokenProvider,
    String? baseUrl,
  })  : _tokenProvider = tokenProvider,
        _url = resolveSocketUrl(baseUrl: baseUrl);

  final Future<String> Function() _tokenProvider;
  final String _url;

  final _alerts = StreamController<BlockerAlert>.broadcast();

  html.WebSocket? _socket;
  Timer? _reconnect;
  Timer? _heartbeat;
  int _attempt = 0;
  bool _closedByUs = false;
  bool _authenticated = false;

  /// Blocker alerts pushed by the server. Broadcast, so the UI can listen
  /// without worrying about being the only subscriber.
  Stream<BlockerAlert> get alerts => _alerts.stream;

  /// True only once the server has accepted our token — not merely when the
  /// socket is open. A socket with a rejected token still reports OPEN for the
  /// moment before the server closes it, and treating that as "live" would let
  /// the polling fallback stand down exactly when it is needed.
  bool get isReady =>
      _authenticated && _socket?.readyState == html.WebSocket.OPEN;

  Future<void> connect() async {
    if (_closedByUs) return;
    // Null it as well as cancelling: _scheduleReconnect treats a non-null
    // timer as "a retry is already pending" and would otherwise never arm
    // another one again.
    _reconnect?.cancel();
    _reconnect = null;
    // Drop any half-open socket before opening another, so a reconnect can
    // never leave two live sockets delivering duplicate alerts.
    _teardownSocket();

    final String token;
    try {
      token = await _tokenProvider();
    } catch (_) {
      // Not signed in, or the refresh failed — try again later rather than
      // hammering the server.
      _scheduleReconnect();
      return;
    }
    // dispose() may have run while the token refresh was in flight (signing
    // out during a reconnect). Without this re-check we would open a socket
    // nothing owns or closes, and its first frame would hit a closed stream.
    if (_closedByUs) return;

    final html.WebSocket socket;
    try {
      socket = html.WebSocket(_url);
    } catch (_) {
      _scheduleReconnect();
      return;
    }
    _socket = socket;

    socket.onOpen.listen((_) {
      socket.send(jsonEncode({'type': 'auth', 'access_token': token}));
      // Keep idle proxies (nginx defaults to a 60s read timeout) from reaping
      // an otherwise healthy connection.
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
        if (socket.readyState == html.WebSocket.OPEN) {
          socket.send(jsonEncode({'type': 'ping'}));
        }
      });
    });

    socket.onMessage.listen((event) {
      final data = event.data;
      if (data is! String) return;
      Map<String, dynamic> frame;
      try {
        final decoded = jsonDecode(data);
        if (decoded is! Map<String, dynamic>) return;
        frame = decoded;
      } on FormatException {
        return;
      }
      final frameType = frame['type'];
      if (frameType == 'auth_ok') {
        // Backoff resets here, not on open: a socket whose token is rejected
        // still opens and is then closed by the server, so resetting at open
        // would turn a bad token into a 1-second reconnect loop.
        _attempt = 0;
        _authenticated = true;
        return;
      }
      if (frameType != 'blocker') return;
      // dispose() may have closed the stream between this frame arriving and
      // being handled.
      if (_alerts.isClosed) return;
      try {
        _alerts.add(BlockerAlert.fromJson(frame));
      } catch (_) {
        // Malformed payload — ignore it rather than killing the stream, which
        // would take the whole channel down for one bad frame.
      }
    });

    socket.onClose.listen((_) => _scheduleReconnect());
    // An error is always followed by a close event, which schedules the
    // retry; listening here only stops it surfacing as an unhandled error.
    socket.onError.listen((_) {});
  }

  void _scheduleReconnect() {
    _authenticated = false;
    _heartbeat?.cancel();
    _heartbeat = null;
    if (_closedByUs || _reconnect != null) return;
    _attempt = _attempt >= 6 ? 6 : _attempt + 1;
    // 1s, 2s, 4s … capped at 64s.
    final delay = Duration(seconds: 1 << (_attempt - 1));
    _reconnect = Timer(delay, () {
      _reconnect = null;
      connect();
    });
  }

  void _teardownSocket() {
    final socket = _socket;
    _socket = null;
    _authenticated = false;
    _heartbeat?.cancel();
    _heartbeat = null;
    if (socket != null &&
        socket.readyState != html.WebSocket.CLOSED &&
        socket.readyState != html.WebSocket.CLOSING) {
      socket.close();
    }
  }

  /// Closes for good — call on sign-out. The instance is not reusable
  /// afterwards; make a new one on the next sign-in.
  void dispose() {
    _closedByUs = true;
    _reconnect?.cancel();
    _reconnect = null;
    _teardownSocket();
    _alerts.close();
  }
}
