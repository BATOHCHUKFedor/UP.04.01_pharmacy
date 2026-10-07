class AuthValidators {
  static String? username(String? value) =>
      RegExp(r'^[a-zA-Z0-9_.-]{3,40}$').hasMatch(value?.trim() ?? '')
      ? null
      : 'Логин: 3–40 латинских букв, цифр, точек, дефисов или подчёркиваний';
  static String? name(String? value) =>
      (value?.trim().length ?? 0) >= 2 && (value?.trim().length ?? 0) <= 80
      ? null
      : 'Имя: от 2 до 80 символов';
  static String? required(String? value) =>
      value == null || value.trim().isEmpty ? 'Заполните поле' : null;
  static bool hasDigit(String value) => RegExp(r'\d').hasMatch(value);
  static bool hasSpecial(String value) =>
      RegExp(r'[^\p{L}\p{N}\s]', unicode: true).hasMatch(value);
  static String? password(String? value) {
    final text = value ?? '';
    if (text.length < 8 || text.length > 128) {
      return 'Пароль: от 8 до 128 символов';
    }
    if (!hasDigit(text)) return 'Добавьте хотя бы одну цифру';
    if (!hasSpecial(text)) return 'Добавьте специальный символ';
    return null;
  }
}
