import 'package:material_ui/material_ui.dart';

import 'api/api_client.dart';
import 'auth/auth_api.dart';
import 'auth/auth_controller.dart';
import 'screens/auth_screen.dart';
import 'screens/task_workspace_screen.dart';
import 'tasks/data_api.dart';

void main() {
  final client = ApiClient();
  final controller = AuthController(
    AuthApi(client: client),
    data: DataApi(client: client),
  );
  // Fire and forget — the UI listens via AnimatedBuilder and shows a splash
  // while `isRestoring` is true, then flips to the signed-in shell if the
  // persisted refresh token swapped cleanly, or the sign-in screen if not.
  controller.restore();
  runApp(TaskManagerApp(controller: controller));
}

/// Shown for the brief moment between app launch and the restore-refresh
/// completing. Keeps the reload from flashing the sign-in screen when the
/// user actually has a valid persisted session.
class _RestoreSplash extends StatelessWidget {
  const _RestoreSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class TaskManagerApp extends StatelessWidget {
  const TaskManagerApp({super.key, required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF176B57),
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: 'Task Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF4F7F5),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          if (controller.isRestoring) {
            return const _RestoreSplash();
          }
          return controller.isAuthenticated
              ? TaskWorkspaceScreen(controller: controller)
              : AuthScreen(controller: controller);
        },
      ),
    );
  }
}
