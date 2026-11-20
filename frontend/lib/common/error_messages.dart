import '../api/api_client.dart';

/// Shown when a request fails without a server-provided message — usually a
/// dropped connection, CORS rejection, or TLS failure.
const String kServerUnreachableMessage =
    'Could not reach the server. Check the connection and try again.';

/// The user-facing text for [error]: the server's own message when the API
/// returned one, otherwise [fallback].
String errorMessage(
  Object? error, {
  String fallback = 'Something went wrong.',
}) =>
    error is AuthApiException ? error.message : fallback;
