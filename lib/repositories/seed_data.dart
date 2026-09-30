import '../models/category.dart';
import '../models/drug.dart';
import '../models/manufacturer.dart';
import '../models/supplier.dart';
import '../models/supplier_license.dart';

const seedManufacturers = <Manufacturer>[
  Manufacturer(
    id: 1,
    name: 'Фармстандарт',
    country: 'Россия',
    contactEmail: 'info@pharmstandard.ru',
  ),
  Manufacturer(
    id: 2,
    name: 'Bayer',
    country: 'Германия',
    contactEmail: 'info@bayer.de',
  ),
  Manufacturer(
    id: 3,
    name: 'KRKA',
    country: 'Словения',
    contactEmail: 'info@krka.si',
  ),
  Manufacturer(
    id: 4,
    name: 'Гедеон Рихтер',
    country: 'Венгрия',
    contactEmail: 'info@richter.hu',
  ),
  Manufacturer(
    id: 5,
    name: 'Озон',
    country: 'Россия',
    contactEmail: 'info@ozonpharm.ru',
  ),
  Manufacturer(
    id: 6,
    name: 'Sanofi',
    country: 'Франция',
    contactEmail: 'info@sanofi.fr',
  ),
];

const seedCategories = <Category>[
  Category(
    id: 1,
    name: 'Анальгетики',
    description: 'Средства для облегчения боли',
  ),
  Category(
    id: 2,
    name: 'Противовоспалительные',
    description: 'Противовоспалительные средства',
  ),
  Category(
    id: 3,
    name: 'Антибиотики',
    description: 'Антибактериальные препараты',
  ),
  Category(
    id: 4,
    name: 'Антигистаминные',
    description: 'Средства против аллергии',
  ),
  Category(
    id: 5,
    name: 'ЖКТ',
    description: 'Средства для пищеварительной системы',
  ),
  Category(
    id: 6,
    name: 'Сердечно-сосудистые',
    description: 'Препараты для сердца и сосудов',
  ),
];

const seedSuppliers = <Supplier>[
  Supplier(
    id: 1,
    name: 'Фармстандарт',
    contactPerson: 'Анна Волкова',
    country: 'Россия',
    phone: '+7 495 100-10-01',
    email: 'order@pharmstandard.ru',
    partnershipYear: 2016,
    manufacturerIds: [1, 5],
  ),
  Supplier(
    id: 2,
    name: 'Bayer',
    contactPerson: 'Марк Шульц',
    country: 'Германия',
    phone: '+49 30 100-20-02',
    email: 'supply@bayer.de',
    partnershipYear: 2018,
    manufacturerIds: [2],
  ),
  Supplier(
    id: 3,
    name: 'KRKA',
    contactPerson: 'Майя Новак',
    country: 'Словения',
    phone: '+386 1 100-30-03',
    email: 'sales@krka.si',
    partnershipYear: 2017,
    manufacturerIds: [3],
  ),
  Supplier(
    id: 4,
    name: 'Гедеон Рихтер',
    contactPerson: 'Иштван Сабо',
    country: 'Венгрия',
    phone: '+36 1 100-40-04',
    email: 'export@richter.hu',
    partnershipYear: 2019,
    manufacturerIds: [4],
  ),
  Supplier(
    id: 5,
    name: 'Озон Фармацевтика',
    contactPerson: 'Илья Соколов',
    country: 'Россия',
    phone: '+7 846 100-50-05',
    email: 'trade@ozonpharm.ru',
    partnershipYear: 2020,
    manufacturerIds: [5],
  ),
  Supplier(
    id: 6,
    name: 'Sanofi',
    contactPerson: 'Клер Мартен',
    country: 'Франция',
    phone: '+33 1 100-60-06',
    email: 'supply@sanofi.fr',
    partnershipYear: 2015,
    manufacturerIds: [6],
  ),
  Supplier(
    id: 7,
    name: 'Sandoz',
    contactPerson: 'Лука Мюллер',
    country: 'Швейцария',
    phone: '+41 44 100-70-07',
    email: 'orders@sandoz.ch',
    partnershipYear: 2021,
    manufacturerIds: [1, 2, 3, 4, 5, 6],
  ),
  Supplier(
    id: 8,
    name: 'ПОЛИСАН',
    contactPerson: 'Мария Орлова',
    country: 'Россия',
    phone: '+7 812 100-80-08',
    email: 'info@polysan.ru',
    partnershipYear: 2018,
    manufacturerIds: [1, 2, 3, 4, 5, 6],
  ),
  Supplier(
    id: 9,
    name: 'Teva',
    contactPerson: 'Ноа Коэн',
    country: 'Израиль',
    phone: '+972 3 100-90-09',
    email: 'sales@teva.co.il',
    partnershipYear: 2022,
    manufacturerIds: [1, 2, 3, 4, 5, 6],
  ),
  Supplier(
    id: 10,
    name: 'Dr. Reddy’s',
    contactPerson: 'Аша Патель',
    country: 'Индия',
    phone: '+91 40 100-00-10',
    email: 'export@drreddys.in',
    partnershipYear: 2023,
    manufacturerIds: [1, 2, 3, 4, 5, 6],
  ),
];

final seedLicenses = List<SupplierLicense>.generate(
  10,
  (index) => SupplierLicense(
    id: index + 1,
    supplierId: index + 1,
    number: 'ЛИЦ-${(1001 + index)}',
    issuedYear: 2020 + index % 3,
    expiresYear: 2030 + index % 3,
  ),
);

final seedDrugs = List<Drug>.generate(24, (index) {
  const names = [
    'Парацетамол',
    'Ибупрофен',
    'Амоксициллин',
    'Лоратадин',
    'Омепразол',
    'Дротаверин',
    'Аскорбиновая кислота',
    'Цетиризин',
    'Азитромицин',
    'Метформин',
    'Каптоприл',
    'Ацетилсалициловая кислота',
    'Панкреатин',
    'Амлодипин',
    'Диклофенак',
    'Флуконазол',
    'Эналаприл',
    'Лоперамид',
    'Мелоксикам',
    'Розувастатин',
    'Фуросемид',
    'Кларитромицин',
    'Бисопролол',
    'Нимесулид',
  ];
  final id = index + 1;
  final manufacturerId = index % 6 + 1;
  final supplierId = manufacturerId;
  return Drug(
    id: id,
    name: names[index],
    registrationNumber: 'ЛП-00${(1200 + id).toString().padLeft(4, '0')}',
    categoryIds: [index % 6 + 1],
    manufacturerId: manufacturerId,
    productionYear: 2020 + index % 6,
    price: 85 + index * 27.5,
    stock: 8 + (index * 13) % 94,
    supplierId: supplierId,
  );
});
