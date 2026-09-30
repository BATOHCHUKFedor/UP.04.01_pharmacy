typedef TextValidator = String? Function(String? value);

class Validators {
  static TextValidator requiredText({int maxLength = 100}) => (value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Заполните поле';
    if (text.length > maxLength) return 'Не более $maxLength символов';
    return null;
  };

  static TextValidator optionalText({int maxLength = 250}) => (value) {
    if ((value ?? '').trim().length > maxLength) {
      return 'Не более $maxLength символов';
    }
    return null;
  };

  static TextValidator email() => (value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Заполните поле';
    if (text.length > 254) return 'Не более 254 символов';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
      return 'Введите корректный адрес почты';
    }
    return null;
  };

  static TextValidator integer({required int min, required int max}) =>
      (value) {
        if ((value ?? '').trim().isEmpty) return 'Заполните поле';
        final parsed = int.tryParse(value!.trim());
        if (parsed == null) return 'Введите целое число';
        if (parsed < min || parsed > max) return 'Число от $min до $max';
        return null;
      };

  static TextValidator decimal({required double min, required double max}) =>
      (value) {
        if ((value ?? '').trim().isEmpty) return 'Заполните поле';
        final parsed = double.tryParse(value!.trim().replaceAll(',', '.'));
        if (parsed == null) return 'Введите число';
        if (parsed < min || parsed > max) return 'Число от $min до $max';
        return null;
      };

  static String? requiredId(int? id) =>
      id == null || id <= 0 ? 'Выберите значение' : null;
  static String? requiredIds(List<int>? ids) =>
      ids == null || ids.isEmpty ? 'Выберите хотя бы одно значение' : null;
}
