class Reservation {
  final int id;
  final String drugName;
  final String customerName;
  final int quantity;
  final String status;
  final DateTime expiresAt;
  final bool extended;
  const Reservation({
    required this.id,
    required this.drugName,
    required this.customerName,
    required this.quantity,
    required this.status,
    required this.expiresAt,
    required this.extended,
  });
  factory Reservation.fromJson(Map<String, dynamic> json) => Reservation(
    id: (json['id'] as num?)?.toInt() ?? 0,
    drugName: json['drugName'] as String? ?? '',
    customerName: json['customerName'] as String? ?? '',
    quantity: (json['quantity'] as num?)?.toInt() ?? 0,
    status: json['status'] as String? ?? 'reserved',
    extended: json['extended'] as bool? ?? false,
    expiresAt:
        DateTime.tryParse(json['expiresAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
  String get statusLabel => switch (status) {
    'completed' => 'Выдано',
    'cancelled' => 'Отменено',
    _ => 'Забронировано',
  };
  Map<String, dynamic> toJson() => {
    'id': id,
    'drugName': drugName,
    'customerName': customerName,
    'quantity': quantity,
    'status': status,
    'expiresAt': expiresAt.toIso8601String(),
    'extended': extended,
  };
}
