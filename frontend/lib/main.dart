import 'package:material_ui/material_ui.dart';

import 'api/api_client.dart';
import 'auth/auth_api.dart';
import 'auth/auth_controller.dart';
import 'screens/auth_screen.dart';
import 'screens/task_workspace_screen.dart';
import 'tasks/data_api.dart';

void main() {
  final client = ApiClient();
  runApp(
    TaskManagerApp(
      controller: AuthController(
        AuthApi(client: client),
        data: DataApi(client: client),
      ),
    ),
  );
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
        builder: (context, _) => controller.isAuthenticated
            ? TaskWorkspaceScreen(controller: controller)
            : AuthScreen(controller: controller),
      ),
    );
  }
}
