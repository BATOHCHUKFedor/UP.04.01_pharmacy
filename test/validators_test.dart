import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_project/core/validators.dart';
import 'package:pharmacy_project/core/auth_validators.dart';

void main() {
  test('обязательное поле: null, пробелы, предел длины', () {
    final validate = Validators.requiredText(maxLength: 3);
    expect(validate(null), isNotNull);
    expect(validate('  '), isNotNull);
    expect(validate(' abc '), isNull);
    expect(validate('abcd'), isNotNull);
  });
  test('необязательное поле: пустое допустимо, длина ограничена', () {
    final validate = Validators.optionalText(maxLength: 3);
    expect(validate(null), isNull);
    expect(validate('abc'), isNull);
    expect(validate('abcd'), isNotNull);
  });
  test('почта: обязательность, формат и максимальная длина', () {
    final validate = Validators.email();
    for (final invalid in [
      null,
      '',
      'mail',
      'a b@example.com',
      '${'a' * 250}@b.ru',
    ]) {
      expect(validate(invalid), isNotNull);
    }
    expect(validate(' user@example.com '), isNull);
  });
  test('целое число: граничные значения, дробь, текст', () {
    final validate = Validators.integer(min: 1, max: 10);
    for (final valid in ['1', '10']) {
      expect(validate(valid), isNull);
    }
    for (final invalid in [null, '0', '11', '1.5', 'текст']) {
      expect(validate(invalid), isNotNull);
    }
  });
  test('цена: десятичная запятая, границы, NaN и бесконечность', () {
    final validate = Validators.decimal(min: 0.01, max: 100);
    for (final valid in ['0,01', '12.50', '100']) {
      expect(validate(valid), isNull);
    }
    for (final invalid in [null, '-1', '101', 'NaN', 'Infinity', '-Infinity']) {
      expect(validate(invalid), isNotNull);
    }
  });
  test('связь: положительный идентификатор обязателен', () {
    expect(Validators.requiredId(null), isNotNull);
    expect(Validators.requiredId(0), isNotNull);
    expect(Validators.requiredId(1), isNull);
  });
  test('множественная связь: нужен хотя бы один выбор', () {
    expect(Validators.requiredIds(null), isNotNull);
    expect(Validators.requiredIds([]), isNotNull);
    expect(Validators.requiredIds([1, 2]), isNull);
  });
  test('регистрация: пароль, логин, имя', () {
    expect(AuthValidators.password('Password1!'), isNull);
    for (final invalid in ['', 'a1!', 'Password!', 'Password1']) {
      expect(AuthValidators.password(invalid), isNotNull);
    }
    expect(AuthValidators.username('valid.user'), isNull);
    expect(AuthValidators.username('логин'), isNotNull);
    expect(AuthValidators.name('Иван'), isNull);
    expect(AuthValidators.name(' '), isNotNull);
  });
}
