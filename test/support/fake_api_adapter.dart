import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

typedef ApiHandler =
    FutureOr<ResponseBody> Function(
      RequestOptions options,
      Future<void>? cancelFuture,
    );

class FakeApiAdapter implements HttpClientAdapter {
  final ApiHandler handler;
  final List<RequestOptions> requests = [];
  FakeApiAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(Object? body, [int status = 200]) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

const referencesJson = {
  'manufacturers': [
    {
      'id': 1,
      'name': 'Завод',
      'country': 'Россия',
      'contactEmail': 'plant@example.com',
    },
  ],
  'categories': [
    {'id': 1, 'name': 'Категория', 'description': 'Описание'},
  ],
  'suppliers': [
    {
      'id': 1,
      'name': 'Поставщик',
      'contactPerson': 'Контакт',
      'country': 'Россия',
      'phone': '123',
      'email': 'supply@example.com',
      'partnershipYear': 2020,
      'manufacturerIds': [1],
    },
  ],
  'licenses': [
    {
      'id': 1,
      'supplierId': 1,
      'number': 'ЛИЦ-1',
      'issuedYear': 2020,
      'expiresYear': 2030,
    },
  ],
};

Map<String, dynamic> drugJson(int id) => {
  'id': id,
  'name': 'Препарат $id',
  'registrationNumber': 'ЛП-$id',
  'productionYear': 2025,
  'price': 100.0,
  'stock': 10,
  'manufacturer': {'id': 1},
  'supplier': {'id': 1},
  'categories': [
    {'id': 1},
  ],
};

Map<String, dynamic> pageJson(int id, {int page = 1}) => {
  'items': [drugJson(id)],
  'page': page,
  'size': 10,
  'total': 20,
};
