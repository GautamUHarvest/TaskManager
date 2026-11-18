import 'package:material_ui/material_ui.dart';

import '../auth/auth_api.dart';
import '../auth/auth_controller.dart';

class ProfileContent extends StatefulWidget {
  const ProfileContent({super.key, required this.controller});

  final AuthController controller;

  @override
  State<ProfileContent> createState() => _ProfileContentState();
}

class _ProfileContentState extends State<ProfileContent> {
  late Future<AuthUser> _profile;
  bool _loggingOut = false;
  String? _logoutError;

  @override
  void initState() {
    super.initState();
    _profile = widget.controller.loadProfile();
  }

  void _reload() {
    setState(() {
      _logoutError = null;
      _profile = widget.controller.loadProfile();
    });
  }

  Future<void> _logout() async {
    setState(() {
      _loggingOut = true;
      _logoutError = null;
    });
    try {
      await widget.controller.logout();
    } on AuthApiException catch (error) {
      if (mounted) setState(() => _logoutError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
            () => _logoutError = 'Could not reach the server to sign out.');
      }
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                final error = snapshot.error is AuthApiException
                    ? (snapshot.error! as AuthApiException).message
                    : 'Unable to load your profile.';
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(error, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _reload,
                          child: const Text('Try again'),
                        ),
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
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: scheme.primaryContainer,
                        foregroundColor: scheme.onPrimaryContainer,
                        child: Text(
                          user.displayName.isEmpty
                              ? '?'
                              : user.displayName[0].toUpperCase(),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
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
                      if (_logoutError != null) ...[
                        const SizedBox(height: 20),
                        Text(
                          _logoutError!,
                          style: TextStyle(color: scheme.error),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (_loggingOut) ...[
                        const SizedBox(height: 20),
                        const LinearProgressIndicator(),
                      ],
                      const SizedBox(height: 24),
                      OutlinedButton(
                        onPressed: _loggingOut ? null : _logout,
                        child:
                            Text(_loggingOut ? 'Signing out...' : 'Sign out'),
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
