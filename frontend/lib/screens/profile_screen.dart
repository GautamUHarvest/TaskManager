import 'package:material_ui/material_ui.dart';

import '../auth/auth_api.dart';
import '../auth/auth_controller.dart';
import '../common/error_messages.dart';
import '../common/submit_state.dart';
import '../common/widgets/form_error_text.dart';
import '../common/widgets/initial_avatar.dart';
import '../common/widgets/message_card.dart';

/// The signed-in user's account details and the sign-out button. Rendered
/// as the workspace's Profile pane.
class ProfileContent extends StatefulWidget {
  const ProfileContent({super.key, required this.controller});

  final AuthController controller;

  @override
  State<ProfileContent> createState() => _ProfileContentState();
}

class _ProfileContentState extends State<ProfileContent>
    with SubmitStateMixin {
  late Future<AuthUser> _profile;

  @override
  void initState() {
    super.initState();
    _profile = widget.controller.loadProfile();
  }

  void _reload() {
    setState(() {
      submitError = null;
      _profile = widget.controller.loadProfile();
    });
  }

  Future<void> _logout() => runSubmit(
        widget.controller.logout,
        unreachableMessage: 'Could not reach the server to sign out.',
      );

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: FutureBuilder<AuthUser>(
            future: _profile,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(48),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(
                          errorMessage(
                            snapshot.error,
                            fallback: 'Unable to load your profile.',
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        RetryButton(onPressed: _reload),
                      ],
                    ),
                  ),
                );
              }

              final user = snapshot.requireData;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InitialAvatar(
                        name: user.displayName,
                        radius: 34,
                        textStyle: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        user.displayName,
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 28),
                      _ProfileField(
                        label: 'Employee ID',
                        value: user.employeeId,
                      ),
                      const Divider(height: 28),
                      _ProfileField(
                        label: 'Email',
                        value: user.email,
                      ),
                      if (submitError != null) ...[
                        const SizedBox(height: 20),
                        FormErrorText(
                          submitError!,
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (submitting) ...[
                        const SizedBox(height: 20),
                        const LinearProgressIndicator(),
                      ],
                      const SizedBox(height: 24),
                      OutlinedButton(
                        onPressed: submitting ? null : _logout,
                        child:
                            Text(submitting ? 'Signing out...' : 'Sign out'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              SelectableText(
                value,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
