import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import 'error_messages.dart';

/// The busy-flag + inline-error bookkeeping every form in the app needs.
///
/// [runSubmit] marks the form busy, clears the previous error, runs the
/// action, and turns any failure into [submitError]: the server's message for
/// an [AuthApiException], [unreachableMessage] for anything else (network,
/// CORS, TLS). Every state change is guarded by `mounted`, so an action that
/// pops the route is safe.
mixin SubmitStateMixin<W extends StatefulWidget> on State<W> {
  bool submitting = false;
  String? submitError;

  Future<void> runSubmit(
    Future<void> Function() action, {
    String unreachableMessage = kServerUnreachableMessage,
  }) async {
    setState(() {
      submitting = true;
      submitError = null;
    });
    try {
      await action();
    } on AuthApiException catch (error) {
      if (mounted) setState(() => submitError = error.message);
    } catch (_) {
      if (mounted) setState(() => submitError = unreachableMessage);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }
}
