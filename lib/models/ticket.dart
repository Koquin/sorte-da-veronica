class Ticket {
  const Ticket({
    required this.id,
    required this.numbers,
    required this.sellerId,
    required this.isSold,
    required this.soldAt,
    required this.createdAt,
    required this.assignedBy,
    required this.buyerName,
    required this.buyerContact,
  });

  final int id;
  final List<int> numbers;
  final int? sellerId;
  final bool isSold;
  final DateTime? soldAt;
  final DateTime createdAt;
  final int? assignedBy;
  final String? buyerName;
  final String? buyerContact;

  Ticket copyWith({
    int? id,
    List<int>? numbers,
    int? sellerId,
    bool? isSold,
    DateTime? soldAt,
    DateTime? createdAt,
    int? assignedBy,
    String? buyerName,
    String? buyerContact,
    bool clearSoldAt = false,
    bool clearBuyerName = false,
    bool clearBuyerContact = false,
  }) {
    return Ticket(
      id: id ?? this.id,
      numbers: numbers ?? this.numbers,
      sellerId: sellerId ?? this.sellerId,
      isSold: isSold ?? this.isSold,
      soldAt: clearSoldAt ? null : (soldAt ?? this.soldAt),
      createdAt: createdAt ?? this.createdAt,
      assignedBy: assignedBy ?? this.assignedBy,
      buyerName: clearBuyerName ? null : (buyerName ?? this.buyerName),
      buyerContact: clearBuyerContact
          ? null
          : (buyerContact ?? this.buyerContact),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'numbers': numbers,
      'seller_id': sellerId,
      'is_sold': isSold,
      'sold_at': soldAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'assigned_by': assignedBy,
      'buyer_name': buyerName,
      'buyer_contact': buyerContact,
    };
  }

  factory Ticket.fromJson(Map<String, dynamic> json) {
    return Ticket(
      id: json['id'] as int,
      numbers: List<int>.from(json['numbers'] as List<dynamic>),
      sellerId: json['seller_id'] as int?,
      isSold: json['is_sold'] as bool,
      soldAt: json['sold_at'] == null
          ? null
          : DateTime.parse(json['sold_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      assignedBy: json['assigned_by'] as int?,
      buyerName: json['buyer_name'] as String?,
      buyerContact: json['buyer_contact'] as String?,
    );
  }
}
