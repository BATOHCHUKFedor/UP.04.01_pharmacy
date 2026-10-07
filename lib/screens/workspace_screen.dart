import 'package:flutter/material.dart';
import '../widgets/responsive_cards.dart';
import 'package:provider/provider.dart';
import '../core/api_exceptions.dart';
import '../core/auth_validators.dart';
import '../core/validators.dart';
import '../models/auth_user.dart';
import '../repositories/workspace_repository.dart';
import '../state/workspace_notifier.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/screen_state_view.dart';

class WorkspaceScreen extends StatelessWidget {
  final String path;
  final int? drugId;
  const WorkspaceScreen({super.key, required this.path, this.drugId});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    key: ValueKey(path),
    create: (context) =>
        WorkspaceNotifier(context.read<WorkspaceRepository>(), path)..load(),
    child: _WorkspaceBody(path: path, drugId: drugId),
  );
}

class _WorkspaceBody extends StatelessWidget {
  final String path;
  final int? drugId;
  const _WorkspaceBody({required this.path, this.drugId});
  bool get _mine => path.endsWith('/mine');
  bool get _reservations => path.contains('reservations');
  bool get _stats => path.endsWith('statistics');
  bool get _admin => path == '/admin/users';
  String get _title => _stats
      ? 'Статистика'
      : _reservations
      ? (_mine ? 'Мои бронирования' : 'Работа с бронированиями')
      : _admin
      ? 'Пользователи и роли'
      : 'Пользователи аптеки';
  @override
  Widget build(BuildContext context) {
    final state = context.watch<WorkspaceNotifier>();
    return AppScaffold(
      title: _title,
      actions: [
        IconButton(
          tooltip: 'Обновить',
          onPressed: state.busy ? null : state.load,
          icon: const Icon(Icons.refresh),
        ),
        if (!_mine && !_stats)
          IconButton(
            tooltip: 'Создать',
            onPressed: state.busy
                ? null
                : () => showDialog<void>(
                    context: context,
                    builder: (_) => _CreateDialog(
                      state: state,
                      reservation: _reservations,
                      admin: _admin,
                      drugId: drugId,
                    ),
                  ),
            icon: const Icon(Icons.add),
          ),
      ],
      body: ScreenStateView(
        status: state.status,
        error: state.error,
        isEmpty:
            !_stats &&
            (_reservations ? state.reservations.isEmpty : state.users.isEmpty),
        emptyMessage: _reservations
            ? 'Бронирований пока нет'
            : 'Пользователей пока нет',
        onRetry: state.load,
        child: ResponsiveCards(
          padding: const EdgeInsets.all(16),
          children: [
            if (_stats)
              for (final entry in state.statistics.entries)
                Card(
                  child: ListTile(
                    title: Text(
                      const {
                            'drugs': 'Действующие препараты',
                            'stock': 'Свободные упаковки',
                            'users': 'Все учётные записи',
                            'customers': 'Пользователи',
                            'reserved': 'Открытые бронирования',
                            'completed': 'Выданные бронирования',
                          }[entry.key] ??
                          entry.key,
                    ),
                    trailing: Text('${entry.value}'),
                  ),
                ),
            if (_reservations)
              for (final item in state.reservations)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item.drugName} · ${item.quantity} уп.',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (!_mine) Text('Пользователь: ${item.customerName}'),
                        Text(
                          '${item.statusLabel} · Забрать до ${_date(item.expiresAt)}',
                        ),
                        if (item.extended)
                          const Text('Срок получения уже продлён'),
                        if (item.status == 'reserved')
                          Wrap(
                            spacing: 8,
                            children: [
                              if (_mine &&
                                  !item.extended &&
                                  item.expiresAt.isAfter(DateTime.now()))
                                TextButton(
                                  onPressed: state.busy
                                      ? null
                                      : () => _action(
                                          context,
                                          state,
                                          '/reservations/${item.id}/extend',
                                        ),
                                  child: const Text('Продлить на 3 дня'),
                                ),
                              if (!_mine) ...[
                                TextButton(
                                  onPressed: state.busy
                                      ? null
                                      : () => _action(
                                          context,
                                          state,
                                          '/reservations/${item.id}/complete',
                                        ),
                                  child: const Text('Выдать'),
                                ),
                                TextButton(
                                  onPressed: state.busy
                                      ? null
                                      : () => _action(
                                          context,
                                          state,
                                          '/reservations/${item.id}/cancel',
                                        ),
                                  child: const Text('Отменить'),
                                ),
                              ],
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
            if (!_reservations && !_stats)
              for (final user in state.users)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${user.name} (${user.username})'),
                        Text(
                          '${user.role.label} · ${user.active ? 'Активен' : 'Отключён'}',
                        ),
                        if (_admin)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SizedBox(
                                width: 220,
                                child: DropdownButtonFormField<AppRole>(
                                  key: ValueKey('${user.id}-${user.role.name}'),
                                  initialValue: user.role,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Роль',
                                  ),
                                  items: AppRole.values
                                      .map(
                                        (role) => DropdownMenuItem(
                                          value: role,
                                          child: Text(role.label),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: state.busy
                                      ? null
                                      : (role) {
                                          if (role != null &&
                                              role != user.role) {
                                            _action(
                                              context,
                                              state,
                                              '/admin/users/${user.id}',
                                              update: true,
                                              data: {'role': role.name},
                                            );
                                          }
                                        },
                                ),
                              ),
                              TextButton(
                                onPressed: state.busy
                                    ? null
                                    : () => _action(
                                        context,
                                        state,
                                        '/admin/users/${user.id}',
                                        update: true,
                                        data: {'active': !user.active},
                                      ),
                                child: Text(
                                  user.active ? 'Отключить' : 'Включить',
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
  Future<void> _action(
    BuildContext context,
    WorkspaceNotifier state,
    String route, {
    bool update = false,
    Map<String, dynamic> data = const {},
  }) async {
    if (!await confirmAction(
      context,
      title: 'Подтвердить действие?',
      message: 'Изменение будет сохранено на сервере.',
      confirmLabel: 'Подтвердить',
    )) {
      return;
    }
    try {
      await state.mutate(route, data, update: update);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

class _CreateDialog extends StatefulWidget {
  final WorkspaceNotifier state;
  final bool reservation;
  final bool admin;
  final int? drugId;
  const _CreateDialog({
    required this.state,
    required this.reservation,
    required this.admin,
    this.drugId,
  });
  @override
  State<_CreateDialog> createState() => _CreateDialogState();
}

class _CreateDialogState extends State<_CreateDialog> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  final _errors = <String, String>{};
  int? _userId;
  AppRole _role = AppRole.customer;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    for (final key in ['drugId', 'quantity', 'name', 'username', 'password']) {
      _fields[key] = TextEditingController(
        text: key == 'quantity'
            ? '1'
            : key == 'drugId'
            ? '${widget.drugId ?? ''}'
            : '',
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _errors.clear();
      _error = null;
    });
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.state.mutate(
        widget.reservation
            ? '/reservations'
            : widget.admin
            ? '/admin/users'
            : '/customers',
        widget.reservation
            ? {
                'drugId': int.parse(_fields['drugId']!.text),
                'quantity': int.parse(_fields['quantity']!.text),
                'userId': _userId,
              }
            : {
                'name': _fields['name']!.text.trim(),
                'username': _fields['username']!.text.trim(),
                'password': _fields['password']!.text,
                if (widget.admin) 'role': _role.name,
              },
      );
      if (mounted) Navigator.pop(context);
    } on ValidationException catch (error) {
      if (mounted) setState(() => _errors.addAll(error.errors));
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.reservation ? 'Новое бронирование' : 'Новый пользователь',
    ),
    content: SizedBox(
      width: 450,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (widget.reservation) ...[
                _field(
                  'drugId',
                  'Код препарата (из карточки)',
                  Validators.integer(min: 1, max: 2147483647),
                ),
                DropdownButtonFormField<int>(
                  initialValue: _userId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Пользователь',
                    errorText: _errors['userId'],
                  ),
                  items: widget.state.users
                      .map(
                        (user) => DropdownMenuItem(
                          value: user.id,
                          child: Text(
                            '${user.name} (${user.username})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _saving ? null : (value) => _userId = value,
                  validator: (value) =>
                      value == null ? 'Выберите пользователя' : null,
                ),
                const SizedBox(height: 16),
                _field(
                  'quantity',
                  'Количество упаковок',
                  Validators.integer(min: 1, max: 1000000),
                ),
                const Text(
                  'Упаковки резервируются на 3 дня. Пользователь может один раз продлить срок получения.',
                ),
              ] else ...[
                _field('name', 'Имя', AuthValidators.name),
                _field('username', 'Логин', AuthValidators.username),
                _field('password', 'Пароль', AuthValidators.password),
                if (widget.admin)
                  DropdownButtonFormField<AppRole>(
                    initialValue: _role,
                    decoration: const InputDecoration(labelText: 'Роль'),
                    items: AppRole.values
                        .map(
                          (role) => DropdownMenuItem(
                            value: role,
                            child: Text(role.label),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) => _role = value ?? AppRole.customer,
                  ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Сохраняем…' : 'Сохранить'),
      ),
    ],
  );
  Widget _field(
    String key,
    String label,
    String? Function(String?) validator,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: _fields[key],
      enabled: !_saving,
      obscureText: key == 'password',
      validator: validator,
      autovalidateMode: key == 'password'
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      decoration: InputDecoration(labelText: label, errorText: _errors[key]),
      onChanged: (_) {
        if (_errors.containsKey(key)) setState(() => _errors.remove(key));
      },
    ),
  );
}
