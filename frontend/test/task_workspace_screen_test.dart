import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_frontend/auth/auth_api.dart';
import 'package:task_manager_frontend/auth/auth_controller.dart';
import 'package:task_manager_frontend/screens/task_workspace_screen.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('navigation starts closed and opens from the menu button',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TaskWorkspaceScreen(
          controller: AuthController(AuthApi()),
        ),
      ),
    );

    expect(find.text('My Tasks'), findsNothing);
    await tester.tap(find.byTooltip('Open navigation'));
    await tester.pumpAndSettle();
    expect(find.text('My Tasks'), findsOneWidget);
  });

  testWidgets('Team in the drawer opens the team directory', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TaskWorkspaceScreen(
          controller: AuthController(AuthApi()),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Open navigation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Team'));
    await tester.pumpAndSettle();
    // The Team pane renders its header even while the directory load fails
    // (no backend in the test), and the drawer has closed behind it.
    expect(find.text('Team'), findsOneWidget);
    expect(find.text('My Tasks'), findsNothing);
  });
}
