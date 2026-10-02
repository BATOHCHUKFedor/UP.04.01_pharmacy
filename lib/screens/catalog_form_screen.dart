import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/form_leave_guard.dart';
import '../core/api_exceptions.dart';
import '../core/validators.dart';
import '../models/catalog_item.dart';
import '../models/category.dart';
import '../models/drug.dart';
import '../models/manufacturer.dart';
import '../models/supplier.dart';
import '../models/supplier_license.dart';
import '../repositories/catalog_repository.dart';
import '../state/catalog_store.dart';
import '../state/load_status.dart';
import '../widgets/screen_state_view.dart';
import '../widgets/catalog_form.dart';
import '../widgets/confirm_dialog.dart';

class CatalogFormScreen extends StatefulWidget {
  final EntityKind kind;
  final int? id;
  const CatalogFormScreen({super.key, required this.kind, this.id});
  @override
  State<CatalogFormScreen> createState() => _CatalogFormScreenState();
}

class _CatalogFormScreenState extends State<CatalogFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> _values = {};
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _serverErrors = {};
  bool _dirty = false;
  bool _allowPop = false;
  bool _saving = false;
  bool _hasSubmitted = false;
  LoadStatus _loadStatus = LoadStatus.loading;
  String? _loadError;
  late final FormLeaveGuard _leaveGuard;
  late final Future<bool> Function() _exitCheck;
  CatalogItem? _original;
  SupplierLicense? _originalLicense;

  @override
  void initState() {
    super.initState();
    _leaveGuard = context.read<FormLeaveGuard>();
    _exitCheck = _confirmExit;
    _leaveGuard.attach(_exitCheck);
    _loadForm();
  }

  Future<void> _loadForm() async {
    setState(() {
      _loadStatus = LoadStatus.loading;
      _loadError = null;
    });
    final store = context.read<CatalogStore>();
    try {
      await store.prepareForm(widget.kind, widget.id);
      if (!mounted) return;
      _original = widget.id == null
          ? null
          : store.byId(widget.kind, widget.id!);
      if (_original is Supplier) {
        _originalLicense = store
            .options(EntityKind.licenses, includeDeleted: true)
            .cast<SupplierLicense>()
            .where((license) => license.supplierId == widget.id)
            .firstOrNull;
      }
      _values.clear();
      _values.addAll(_initialValues());
      for (final controller in _controllers.values) {
        controller.dispose();
      }
      _controllers.clear();
      for (final spec in _specs) {
        if (spec.kind == CatalogInputKind.select ||
            spec.kind == CatalogInputKind.multiSelect) {
          continue;
        }
        _controllers[spec.key] = TextEditingController(
          text: _values[spec.key]?.toString() ?? '',
        );
      }
      setState(() => _loadStatus = LoadStatus.success);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadStatus = LoadStatus.error;
          _loadError = '$error';
        });
      }
    }
  }

  @override
  void dispose() {
    _leaveGuard.detach(_exitCheck);
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _initialValues() => switch (_original) {
    Drug d => {
      'name': d.name,
      'registrationNumber': d.registrationNumber,
      'categoryIds': [...d.categoryIds],
      'manufacturerId': d.manufacturerId,
      'supplierId': d.supplierId,
      'productionYear': d.productionYear,
      'price': d.price,
      'stock': d.stock,
    },
    Supplier s => {
      'name': s.name,
      'contactPerson': s.contactPerson,
      'country': s.country,
      'phone': s.phone,
      'email': s.email,
      'partnershipYear': s.partnershipYear,
      'manufacturerIds': [...s.manufacturerIds],
      'licenseNumber': _originalLicense?.number ?? '',
      'issuedYear': _originalLicense?.issuedYear ?? '',
      'expiresYear': _originalLicense?.expiresYear ?? '',
    },
    Manufacturer m => {
      'name': m.name,
      'country': m.country,
      'contactEmail': m.contactEmail,
    },
    Category c => {'name': c.name, 'description': c.description},
    SupplierLicense l => {
      'supplierId': l.supplierId,
      'number': l.number,
      'issuedYear': l.issuedYear,
      'expiresYear': l.expiresYear,
    },
    _ => {'categoryIds': <int>[], 'manufacturerIds': <int>[]},
  };

  List<CatalogFieldSpec> get _specs => switch (widget.kind) {
    EntityKind.drugs => [
      CatalogFieldSpec(
        key: 'name',
        label: 'Название',
        validator: Validators.requiredText(maxLength: 120),
      ),
      CatalogFieldSpec(
        key: 'registrationNumber',
        label: 'Регистрационный номер',
        validator: Validators.requiredText(maxLength: 40),
      ),
      const CatalogFieldSpec(
        key: 'manufacturerId',
        label: 'Производитель',
        kind: CatalogInputKind.select,
        optionsKind: EntityKind.manufacturers,
      ),
      const CatalogFieldSpec(
        key: 'supplierId',
        label: 'Поставщик',
        kind: CatalogInputKind.select,
        optionsKind: EntityKind.suppliers,
      ),
      const CatalogFieldSpec(
        key: 'categoryIds',
        label: 'Категории',
        kind: CatalogInputKind.multiSelect,
        optionsKind: EntityKind.categories,
      ),
      CatalogFieldSpec(
        key: 'productionYear',
        label: 'Год производства',
        kind: CatalogInputKind.integer,
        validator: Validators.integer(min: 1900, max: 2100),
      ),
      CatalogFieldSpec(
        key: 'price',
        label: 'Цена, ₽',
        kind: CatalogInputKind.decimal,
        validator: Validators.decimal(min: 0.01, max: 10000000),
      ),
      CatalogFieldSpec(
        key: 'stock',
        label: 'Количество упаковок',
        kind: CatalogInputKind.integer,
        validator: Validators.integer(min: 0, max: 1000000),
      ),
    ],
    EntityKind.suppliers => [
      CatalogFieldSpec(
        key: 'name',
        label: 'Название',
        validator: Validators.requiredText(maxLength: 120),
      ),
      CatalogFieldSpec(
        key: 'contactPerson',
        label: 'Контактное лицо',
        validator: Validators.requiredText(maxLength: 120),
      ),
      CatalogFieldSpec(
        key: 'country',
        label: 'Страна',
        validator: Validators.requiredText(maxLength: 80),
      ),
      CatalogFieldSpec(
        key: 'phone',
        label: 'Телефон',
        validator: Validators.requiredText(maxLength: 30),
      ),
      CatalogFieldSpec(
        key: 'email',
        label: 'Адрес почты',
        kind: CatalogInputKind.email,
        validator: Validators.email(),
      ),
      CatalogFieldSpec(
        key: 'partnershipYear',
        label: 'Год начала сотрудничества',
        kind: CatalogInputKind.integer,
        validator: Validators.integer(min: 1900, max: 2100),
      ),
      const CatalogFieldSpec(
        key: 'manufacturerIds',
        label: 'Производители',
        kind: CatalogInputKind.multiSelect,
        optionsKind: EntityKind.manufacturers,
      ),
      CatalogFieldSpec(
        key: 'licenseNumber',
        label: 'Номер лицензии',
        group: 'Лицензия поставщика',
        validator: Validators.requiredText(maxLength: 40),
      ),
      CatalogFieldSpec(
        key: 'issuedYear',
        label: 'Год выдачи',
        group: 'Лицензия поставщика',
        kind: CatalogInputKind.integer,
        validator: Validators.integer(min: 1900, max: 2100),
      ),
      CatalogFieldSpec(
        key: 'expiresYear',
        label: 'Год окончания',
        group: 'Лицензия поставщика',
        kind: CatalogInputKind.integer,
        validator: Validators.integer(min: 1900, max: 2200),
      ),
    ],
    EntityKind.manufacturers => [
      CatalogFieldSpec(
        key: 'name',
        label: 'Название',
        validator: Validators.requiredText(maxLength: 120),
      ),
      CatalogFieldSpec(
        key: 'country',
        label: 'Страна',
        validator: Validators.requiredText(maxLength: 80),
      ),
      CatalogFieldSpec(
        key: 'contactEmail',
        label: 'Контактная почта',
        kind: CatalogInputKind.email,
        validator: Validators.email(),
      ),
    ],
    EntityKind.categories => [
      CatalogFieldSpec(
        key: 'name',
        label: 'Название',
        validator: Validators.requiredText(maxLength: 100),
      ),
      CatalogFieldSpec(
        key: 'description',
        label: 'Описание',
        validator: Validators.requiredText(maxLength: 250),
      ),
    ],
    EntityKind.licenses => [
      const CatalogFieldSpec(
        key: 'supplierId',
        label: 'Поставщик',
        kind: CatalogInputKind.select,
        optionsKind: EntityKind.suppliers,
      ),
      CatalogFieldSpec(
        key: 'number',
        label: 'Номер лицензии',
        validator: Validators.requiredText(maxLength: 40),
      ),
      CatalogFieldSpec(
        key: 'issuedYear',
        label: 'Год выдачи',
        kind: CatalogInputKind.integer,
        validator: Validators.integer(min: 1900, max: 2100),
      ),
      CatalogFieldSpec(
        key: 'expiresYear',
        label: 'Год окончания',
        kind: CatalogInputKind.integer,
        validator: Validators.integer(min: 1900, max: 2200),
      ),
    ],
  };

  List<CatalogItem> _options(CatalogFieldSpec spec) {
    final store = context.read<CatalogStore>();
    var options = store.options(spec.optionsKind!);
    if (widget.kind == EntityKind.drugs && spec.key == 'supplierId') {
      final manufacturerId = _values['manufacturerId'] as int?;
      options = options
          .cast<Supplier>()
          .where(
            (supplier) =>
                manufacturerId == null ||
                supplier.manufacturerIds.contains(manufacturerId),
          )
          .toList();
    }
    if (widget.kind == EntityKind.licenses && spec.key == 'supplierId') {
      final occupied = store
          .options(EntityKind.licenses, includeDeleted: true)
          .cast<SupplierLicense>()
          .where((license) => license.id != widget.id)
          .map((license) => license.supplierId)
          .toSet();
      options = options
          .where((supplier) => !occupied.contains(supplier.id))
          .toList();
    }
    return options;
  }

  void _onChanged(String key, dynamic value) {
    setState(() {
      _values[key] = value;
      _serverErrors.remove(key);
      _dirty = true;
      if (widget.kind == EntityKind.drugs && key == 'manufacturerId') {
        _values['supplierId'] = null;
        _serverErrors.remove('supplierId');
      }
    });
  }

  int _integer(String key) => int.parse('${_values[key]}');
  double _decimal(String key) =>
      double.parse('${_values[key]}'.replaceAll(',', '.'));
  String _text(String key) => '${_values[key] ?? ''}'.trim();
  List<int> _ids(String key) =>
      List<int>.from(_values[key] as List<int>? ?? []);

  CatalogItem _buildItem() => switch (widget.kind) {
    EntityKind.drugs => Drug(
      id: widget.id ?? 0,
      name: _text('name'),
      registrationNumber: _text('registrationNumber'),
      categoryIds: _ids('categoryIds'),
      manufacturerId: _values['manufacturerId'] as int,
      supplierId: _values['supplierId'] as int,
      productionYear: _integer('productionYear'),
      price: _decimal('price'),
      stock: _integer('stock'),
      deletedAt: _original?.deletedAt,
    ),
    EntityKind.suppliers => Supplier(
      id: widget.id ?? 0,
      name: _text('name'),
      contactPerson: _text('contactPerson'),
      country: _text('country'),
      phone: _text('phone'),
      email: _text('email'),
      partnershipYear: _integer('partnershipYear'),
      manufacturerIds: _ids('manufacturerIds'),
      deletedAt: _original?.deletedAt,
    ),
    EntityKind.manufacturers => Manufacturer(
      id: widget.id ?? 0,
      name: _text('name'),
      country: _text('country'),
      contactEmail: _text('contactEmail'),
      deletedAt: _original?.deletedAt,
    ),
    EntityKind.categories => Category(
      id: widget.id ?? 0,
      name: _text('name'),
      description: _text('description'),
      deletedAt: _original?.deletedAt,
    ),
    EntityKind.licenses => SupplierLicense(
      id: widget.id ?? 0,
      supplierId: _values['supplierId'] as int,
      number: _text('number'),
      issuedYear: _integer('issuedYear'),
      expiresYear: _integer('expiresYear'),
      deletedAt: _original?.deletedAt,
    ),
  };

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _serverErrors.clear();
      _hasSubmitted = true;
    });
    if (!_formKey.currentState!.validate()) return;
    final issued = _values['issuedYear'];
    final expires = _values['expiresYear'];
    if (issued != null &&
        expires != null &&
        int.parse('$expires') < int.parse('$issued')) {
      setState(
        () => _serverErrors['expiresYear'] =
            'Год окончания должен быть не раньше года выдачи',
      );
      _formKey.currentState!.validate();
      return;
    }
    setState(() => _saving = true);
    try {
      final store = context.read<CatalogStore>();
      CatalogItem saved;
      if (widget.kind == EntityKind.suppliers) {
        final license = SupplierLicense(
          id: _originalLicense?.id ?? 0,
          supplierId: widget.id ?? 0,
          number: _text('licenseNumber'),
          issuedYear: _integer('issuedYear'),
          expiresYear: _integer('expiresYear'),
          deletedAt: null,
        );
        saved = await store.saveSupplierWithLicense(
          _buildItem() as Supplier,
          license,
        );
      } else {
        saved = await store.save(widget.kind, _buildItem());
      }
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _allowPop = true;
      });
      context.go('/${widget.kind.path}/${saved.id}');
    } on ValidationException catch (error) {
      if (!mounted) return;
      setState(() => _serverErrors.addAll(error.errors));
      _formKey.currentState!.validate();
    } on FieldIssue catch (error) {
      if (!mounted) return;
      setState(() {
        _serverErrors[error.field] = error.message;
        _saving = false;
      });
      _formKey.currentState!.validate();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не удалось сохранить: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmExit() async {
    if (!_dirty || _allowPop) return true;
    final confirmed = await confirmAction(
      context,
      title: 'Несохранённые изменения',
      message: 'Уйти со страницы и потерять изменения?',
      confirmLabel: 'Уйти',
    );
    if (!confirmed || !mounted) return false;
    setState(() {
      _allowPop = true;
      _dirty = false;
    });
    return true;
  }

  Future<void> _leave() async {
    if (!await _confirmExit() || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/${widget.kind.path}');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop || !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_allowPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Назад',
            onPressed: _leave,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(
            widget.id == null
                ? 'Новая запись: ${widget.kind.singular}'
                : 'Изменить: ${widget.kind.singular}',
          ),
        ),
        body: ScreenStateView(
          status: _loadStatus,
          error: _loadError,
          isEmpty: widget.id != null && _original == null,
          emptyMessage: 'Запись не найдена',
          onRetry: _loadForm,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: CatalogForm(
                      formKey: _formKey,
                      fields: _specs,
                      values: _values,
                      controllers: _controllers,
                      serverErrors: _serverErrors,
                      optionsOf: _options,
                      onChanged: _onChanged,
                      onSubmit: _submit,
                      saving: _saving,
                      validateOnInteraction: _hasSubmitted,
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
