import 'package:material_ui/material_ui.dart';

import '../auth/auth_controller.dart';
import '../auth/auth_validators.dart';
import '../common/submit_state.dart';
import '../common/widgets/button_spinner.dart';

/// Sign-in / registration screen, shown whenever no session is active.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.controller});

  final AuthController controller;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SubmitStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _employeeId = TextEditingController();
  final _email = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  bool _registering = false;
  bool _obscurePassword = true;
  String? _notice;

  @override
  void dispose() {
    _employeeId.dispose();
    _email.dispose();
    _displayName.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) {
    // Cleared here; the setState inside runSubmit repaints it away.
    _notice = null;
    return runSubmit(
      action,
      unreachableMessage:
          'Could not reach the server. Check the API URL and connection.',
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_registering) {
      await _run(() async {
        await widget.controller.register(
          employeeId: _employeeId.text.trim(),
          email: _email.text.trim(),
          displayName: _displayName.text.trim(),
          password: _password.text,
        );
        if (!mounted) return;
        setState(() {
          _registering = false;
          _notice = 'Account created. Please sign in.';
        });
      });
      return;
    }

    await _run(() => widget.controller.login(
          _employeeId.text.trim(),
          _password.text,
        ));
  }

  void _setMode(bool registering) {
    setState(() {
      _registering = registering;
      submitError = null;
      _notice = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = _registering ? 'Create your account' : 'Welcome back';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                elevation: 1,
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(Icons.task_alt, size: 44, color: scheme.primary),
                        const SizedBox(height: 16),
                        Text(
                          'Task Manager',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 24),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                              value: false,
                              label: Text('Sign in'),
                              icon: Icon(Icons.login),
                            ),
                            ButtonSegment(
                              value: true,
                              label: Text('Register'),
                              icon: Icon(Icons.person_add_alt),
                            ),
                          ],
                          selected: {_registering},
                          onSelectionChanged: submitting
                              ? null
                              : (value) => _setMode(value.first),
                        ),
                        const SizedBox(height: 20),
                        if (_registering) ...[
                          TextFormField(
                            controller: _displayName,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Full name',
                              prefixIcon: Icon(Icons.badge_outlined),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Enter your name';
                              }
                              if (value.trim().length > 100) {
                                return 'Name must be 100 characters or fewer';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                        ],
                        TextFormField(
                          controller: _employeeId,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: _registering
                                ? 'Employee ID'
                                : 'Employee ID or email',
                            prefixIcon: const Icon(Icons.person_outline),
                          ),
                          validator: (value) {
                            final input = value?.trim() ?? '';
                            if (input.isEmpty) return 'This field is required';
                            if (_registering && !isValidEmployeeId(input)) {
                              return 'Use letters, numbers, dots, _ or -';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        if (_registering) ...[
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Company email',
                              prefixIcon: Icon(Icons.email_outlined),
                              hintText: 'name@uharvest.in',
                            ),
                            validator: (value) =>
                                isValidCompanyEmail(value?.trim() ?? '')
                                    ? null
                                    : 'Use a valid @uharvest.in email',
                          ),
                          const SizedBox(height: 14),
                        ],
                        TextFormField(
                          controller: _password,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                              icon: Icon(_obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Enter your password';
                            }
                            if (_registering && !isValidPassword(value)) {
                              return 'Use 6+ characters with uppercase, number and symbol';
                            }
                            return null;
                          },
                        ),
                        if (submitError != null) ...[
                          const SizedBox(height: 16),
                          _MessageBox(message: submitError!, isError: true),
                        ],
                        if (_notice != null) ...[
                          const SizedBox(height: 16),
                          _MessageBox(message: _notice!, isError: false),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: submitting ? null : _submit,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: submitting
                                ? const ButtonSpinner(size: 20)
                                : Text(_registering
                                    ? 'Create account'
                                    : 'Sign in'),
                          ),
                        ),
                        if (!_registering) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed:
                                submitting ? null : () => _setMode(true),
                            child: const Text('New here? Create an account'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBox extends StatelessWidget {
  const _MessageBox({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background =
        isError ? scheme.errorContainer : scheme.secondaryContainer;
    final foreground =
        isError ? scheme.onErrorContainer : scheme.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, style: TextStyle(color: foreground)),
    );
  }
}
