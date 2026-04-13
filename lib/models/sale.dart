class Sale {
  const Sale({
    required this.id,
    required this.ticketId,
    required this.value,
    required this.sellerId,
    required this.createdAt,
  });

  final int id;
  final int ticketId;
  final double value;
  final int sellerId;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ticket_id': ticketId,
      'value': value,
      'seller_id': sellerId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Sale.fromJson(Map<String, dynamic> json) {
    return Sale(
      id: json['id'] as int,
      ticketId: json['ticket_id'] as int,
      value: (json['value'] as num).toDouble(),
      sellerId: json['seller_id'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
