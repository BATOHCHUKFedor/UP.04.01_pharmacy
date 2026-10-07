import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/access_policy.dart';
import '../core/api_exceptions.dart';
import '../core/auth_validators.dart';
import '../state/auth_notifier.dart';
import '../widgets/screen_state_view.dart';

class AuthScreen extends StatefulWidget {
  final bool register;
  final String? from;
  const AuthScreen({super.key, this.register = false, this.from});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  Map<String, String> _errors = {};
  String? _error;
  @override
  void dispose() {
    _username.dispose();
    _name.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthNotifier>();
    if (auth.busy) return;
    setState(() {
      _errors = {};
      _error = null;
    });
    if (!_form.currentState!.validate()) return;
    try {
      await auth.login({
        'username': _username.text.trim(),
        'password': _password.text,
        if (widget.register) 'name': _name.text.trim(),
      }, register: widget.register);
      if (mounted && auth.authenticated) {
        context.go(safeReturnPath(widget.from));
      }
    } on ValidationException catch (error) {
      if (mounted) setState(() => _errors = error.errors);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    final title = widget.register ? 'Регистрация' : 'Вход в аптечный каталог';
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (auth.notice != null) ...[
                    Text(auth.notice!),
                    const SizedBox(height: 16),
                  ],
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (widget.register)
                    _field(_name, 'Имя', 'name', AuthValidators.name),
                  _field(
                    _username,
                    'Логин',
                    'username',
                    widget.register
                        ? AuthValidators.username
                        : AuthValidators.required,
                  ),
                  _field(
                    _password,
                    'Пароль',
                    'password',
                    widget.register
                        ? AuthValidators.password
                        : AuthValidators.required,
                    password: true,
                  ),
                  if (widget.register) ...[
                    ValueListenableBuilder(
                      valueListenable: _password,
                      builder: (_, value, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _rule(
                            'От 8 до 128 символов',
                            value.text.length >= 8 && value.text.length <= 128,
                          ),
                          _rule(
                            'Хотя бы одна цифра',
                            AuthValidators.hasDigit(value.text),
                          ),
                          _rule(
                            'Хотя бы один специальный символ',
                            AuthValidators.hasSpecial(value.text),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                    _field(
                      _confirmation,
                      'Повторите пароль',
                      'confirmation',
                      (value) => value == _password.text && value!.isNotEmpty
                          ? null
                          : 'Пароли должны совпадать',
                      password: true,
                    ),
                  ],
                  FilledButton(
                    onPressed: auth.busy ? null : _submit,
                    child: Text(
                      auth.busy
                          ? 'Подождите…'
                          : widget.register
                          ? 'Зарегистрироваться'
                          : 'Войти',
                    ),
                  ),
                  TextButton(
                    onPressed: auth.busy
                        ? null
                        : () => context.go(
                            Uri(
                              path: widget.register ? '/login' : '/register',
                              queryParameters: {
                                'from': safeReturnPath(widget.from),
                              },
                            ).toString(),
                          ),
                    child: Text(
                      widget.register
                          ? 'Уже есть аккаунт? Войти'
                          : 'Создать аккаунт',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String key,
    String? Function(String?) validator, {
    bool password = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      obscureText: password,
      enabled: !context.read<AuthNotifier>().busy,
      autocorrect: !password,
      enableSuggestions: !password,
      autovalidateMode: widget.register && controller == _password
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      validator: validator,
      onChanged: (_) {
        if (_errors.containsKey(key)) setState(() => _errors.remove(key));
      },
      textInputAction:
          (widget.register
              ? controller == _confirmation
              : controller == _password)
          ? TextInputAction.done
          : TextInputAction.next,
      onFieldSubmitted: (_) {
        if (widget.register
            ? controller == _confirmation
            : controller == _password) {
          _submit();
        } else {
          FocusScope.of(context).nextFocus();
        }
      },
      decoration: InputDecoration(
        labelText: label,
        errorText: _errors[key],
        border: const OutlineInputBorder(),
      ),
    ),
  );
  Widget _rule(String text, bool valid) => Row(
    children: [
      Icon(
        valid ? Icons.check_circle_outline : Icons.circle_outlined,
        size: 16,
        color: valid ? Colors.teal : Colors.grey,
      ),
      const SizedBox(width: 8),
      Flexible(child: Text(text)),
    ],
  );
}

class SessionScreen extends StatelessWidget {
  const SessionScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    return Scaffold(
      body: CenteredMessage(
        child: auth.initializing
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Аптечный каталог'),
                  SizedBox(height: 16),
                  CircularProgressIndicator(),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(auth.bootstrapError ?? 'Восстановление сессии'),
                  FilledButton(
                    onPressed: auth.restore,
                    child: const Text('Повторить'),
                  ),
                  TextButton(
                    onPressed: auth.logout,
                    child: const Text('Перейти ко входу'),
                  ),
                ],
              ),
      ),
    );
  }
}
