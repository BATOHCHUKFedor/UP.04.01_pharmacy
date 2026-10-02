import 'dart:convert';
import 'dart:io';

import 'package:pharmacy_project/repositories/seed_data.dart';

void main() {
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'drugs': seedDrugs
          .map(
            (item) => (item.id == 1 ? item.copyWith(stock: 0) : item).toJson(),
          )
          .toList(),
      'suppliers': seedSuppliers.map((item) => item.toJson()).toList(),
      'manufacturers': seedManufacturers.map((item) => item.toJson()).toList(),
      'categories': seedCategories.map((item) => item.toJson()).toList(),
      'licenses': seedLicenses.map((item) => item.toJson()).toList(),
    }),
  );
}
