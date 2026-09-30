enum EntityKind { drugs, suppliers, manufacturers, categories, licenses }

extension EntityKindInfo on EntityKind {
  String get path => name;
  String get title => switch (this) {
    EntityKind.drugs => 'Препараты',
    EntityKind.suppliers => 'Поставщики',
    EntityKind.manufacturers => 'Производители',
    EntityKind.categories => 'Категории',
    EntityKind.licenses => 'Лицензии поставщиков',
  };
  String get singular => switch (this) {
    EntityKind.drugs => 'Препарат',
    EntityKind.suppliers => 'Поставщик',
    EntityKind.manufacturers => 'Производитель',
    EntityKind.categories => 'Категория',
    EntityKind.licenses => 'Лицензия',
  };
}

abstract interface class CatalogItem {
  int get id;
  DateTime? get deletedAt;
  String get title;
  bool get isDeleted => deletedAt != null;
  Map<String, dynamic> toJson();
  CatalogItem withId(int id);
  CatalogItem withDeletedAt(DateTime? value);
}

int jsonInt(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
double jsonDouble(Object? value, [double fallback = 0]) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;
String jsonString(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;
DateTime? jsonDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
List<int> jsonIds(Object? value) => value is List
    ? value.map((item) => jsonInt(item, -1)).where((id) => id > 0).toList()
    : <int>[];
