import 'package:flutter/material.dart';

import '../core/validators.dart';
import '../models/catalog_item.dart';

enum CatalogInputKind { text, integer, decimal, email, select, multiSelect }

class CatalogFieldSpec {
  final String key;
  final String label;
  final CatalogInputKind kind;
  final TextValidator? validator;
  final EntityKind? optionsKind;
  final String? group;
  const CatalogFieldSpec({
    required this.key,
    required this.label,
    this.kind = CatalogInputKind.text,
    this.validator,
    this.optionsKind,
    this.group,
  });
}

class CatalogForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final List<CatalogFieldSpec> fields;
  final Map<String, dynamic> values;
  final Map<String, TextEditingController> controllers;
  final Map<String, String> serverErrors;
  final List<CatalogItem> Function(CatalogFieldSpec field) optionsOf;
  final void Function(String key, dynamic value) onChanged;
  final VoidCallback onSubmit;
  final bool saving;
  final bool validateOnInteraction;

  const CatalogForm({
    super.key,
    required this.formKey,
    required this.fields,
    required this.values,
    required this.controllers,
    required this.serverErrors,
    required this.optionsOf,
    required this.onChanged,
    required this.onSubmit,
    required this.saving,
    required this.validateOnInteraction,
  });

  @override
  Widget build(BuildContext context) => Form(
    key: formKey,
    autovalidateMode: validateOnInteraction
        ? AutovalidateMode.onUserInteraction
        : AutovalidateMode.disabled,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < fields.length; index++) ...[
          if (fields[index].group != null &&
              (index == 0 ||
                  fields[index - 1].group != fields[index].group)) ...[
            const SizedBox(height: 16),
            const Divider(),
            Text(
              fields[index].group!,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: _field(fields[index]),
          ),
        ],
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: saving ? null : onSubmit,
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Сохранить'),
          ),
        ),
      ],
    ),
  );

  Widget _field(CatalogFieldSpec spec) {
    if (spec.kind == CatalogInputKind.select) {
      final options = optionsOf(spec);
      final selected = values[spec.key] as int?;
      return DropdownButtonFormField<int>(
        key: ValueKey(
          '${spec.key}-$selected-${options.map((item) => item.id).join(',')}',
        ),
        initialValue: options.any((item) => item.id == selected)
            ? selected
            : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: spec.label,
          border: const OutlineInputBorder(),
        ),
        items: options
            .map(
              (item) => DropdownMenuItem(
                value: item.id,
                child: Text(item.title, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        validator: (value) =>
            serverErrors[spec.key] ?? Validators.requiredId(value),
        onChanged: (value) => onChanged(spec.key, value),
      );
    }
    if (spec.kind == CatalogInputKind.multiSelect) {
      final options = optionsOf(spec);
      return FormField<List<int>>(
        key: ValueKey(
          '${spec.key}-${options.map((item) => item.id).join(',')}',
        ),
        initialValue: List<int>.from(values[spec.key] as List<int>? ?? []),
        validator: (value) =>
            serverErrors[spec.key] ?? Validators.requiredIds(value),
        builder: (state) => InputDecorator(
          decoration: InputDecoration(
            labelText: spec.label,
            border: const OutlineInputBorder(),
            errorText: state.errorText,
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: options.map((item) {
              final selected = (state.value ?? []).contains(item.id);
              return FilterChip(
                label: Text(item.title),
                selected: selected,
                onSelected: (select) {
                  final next = [...?state.value];
                  select ? next.add(item.id) : next.remove(item.id);
                  state.didChange(next);
                  onChanged(spec.key, next);
                },
              );
            }).toList(),
          ),
        ),
      );
    }
    return TextFormField(
      controller: controllers[spec.key],
      decoration: InputDecoration(
        labelText: spec.label,
        border: const OutlineInputBorder(),
      ),
      keyboardType: switch (spec.kind) {
        CatalogInputKind.integer => TextInputType.number,
        CatalogInputKind.decimal => const TextInputType.numberWithOptions(
          decimal: true,
        ),
        CatalogInputKind.email => TextInputType.emailAddress,
        _ => TextInputType.text,
      },
      validator: (value) =>
          serverErrors[spec.key] ?? spec.validator?.call(value),
      onChanged: (value) => onChanged(spec.key, value),
    );
  }
}
