import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_project/core/api_client.dart';

void main() {
  test('API: явно переданный адрес используется без подмены', () {
    final dio = buildDio(baseUrl: 'https://api.example.test/api');
    addTearDown(() => dio.close(force: true));
    expect(dio.options.baseUrl, 'https://api.example.test/api');
  });

  test('API: пустой адрес отклоняется с подсказкой о dart-define', () {
    expect(
      () => buildDio(baseUrl: ''),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('--dart-define=API_BASE_URL='),
        ),
      ),
    );
  });
}
