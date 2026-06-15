// lib/models/models.dart
// ─────────────────────────────────────────────────────────────
// RoomzyFind — Domain Models
// Each model has: fromJson, toJson, copyWith
// ─────────────────────────────────────────────────────────────

// ─── Helpers ──────────────────────────────────────────────────
int _parseInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v.toString()) ?? fallback;
}

List<Map<String, dynamic>> _parseSchedule(dynamic v) {
  if (v == null) return const [];
  if (v is! List) return const [];
  return v
      .whereType<Map>()
      .map((e) => e.map((k, val) => MapEntry(k.toString(), val)))
      .toList();
}

double _parseDouble(dynamic v, [double fallback = 0.0]) {
  if (v == null) return fallback;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  return double.tryParse(v.toString()) ?? fallback;
}

bool _parseBool(dynamic v, [bool fallback = false]) {
  if (v == null) return fallback;
  if (v is bool) return v;
  final s = v.toString().toLowerCase();
  return s == '1' || s == 'true' || s == 'yes';
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  // Firestore Timestamp
  try {
    // ignore: avoid_dynamic_calls
    return (v as dynamic).toDate() as DateTime;
  } catch (_) {}
  return DateTime.tryParse(v.toString());
}

String _dateToString(DateTime? d) => d?.toIso8601String() ?? '';

// ─── UserModel ────────────────────────────────────────────────
/// Roles: 'admin' | 'landlord' | 'student'
class UserModel {
  final String id;
  final String username;
  final String email;
  final String phone;
  final String role;

  /// Only set when role == 'landlord'. Links to the Landlord document.
  final String? landlordId;

  const UserModel({
    required this.id,
    required this.username,
    required this.email,
    required this.phone,
    required this.role,
    this.landlordId,
  });

  bool get isAdmin => role == 'admin';
  bool get isLandlord => role == 'landlord';
  bool get isStudent => role == 'student';

  factory UserModel.fromJson(String docId, Map<String, dynamic> json) =>
      UserModel(
        id: docId,
        username: json['username']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        phone: json['phone']?.toString() ?? '',
        role: json['role']?.toString() ?? 'student',
        landlordId: json['landlord_id']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'username': username,
        'email': email,
        'phone': phone,
        'role': role,
        if (landlordId != null) 'landlord_id': landlordId,
      };

  UserModel copyWith({
    String? id,
    String? username,
    String? email,
    String? phone,
    String? role,
    String? landlordId,
  }) =>
      UserModel(
        id: id ?? this.id,
        username: username ?? this.username,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        role: role ?? this.role,
        landlordId: landlordId ?? this.landlordId,
      );
}

// ─── Landlord ─────────────────────────────────────────────────
class Landlord {
  final String id;
  final String fullName;
  final String email;
  final String phone;
  final String? address;
  final String landlordCode;

  /// Optional: Firebase Auth UID linked to this landlord record.
  final String? authUid;

  const Landlord({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    this.address,
    required this.landlordCode,
    this.authUid,
  });

  factory Landlord.fromJson(String docId, Map<String, dynamic> json) =>
      Landlord(
        id: docId,
        fullName: json['full_name']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        phone: json['phone']?.toString() ?? '',
        address: json['address']?.toString(),
        landlordCode: json['landlord_code']?.toString() ?? '',
        authUid: json['auth_uid']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'full_name': fullName,
        'email': email,
        'phone': phone,
        'address': address,
        'landlord_code': landlordCode,
        if (authUid != null) 'auth_uid': authUid,
      };

  Landlord copyWith({
    String? id,
    String? fullName,
    String? email,
    String? phone,
    String? address,
    String? landlordCode,
    String? authUid,
  }) =>
      Landlord(
        id: id ?? this.id,
        fullName: fullName ?? this.fullName,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        address: address ?? this.address,
        landlordCode: landlordCode ?? this.landlordCode,
        authUid: authUid ?? this.authUid,
      );
}

// ─── Hostel ───────────────────────────────────────────────────
class Hostel {
  final String id;
  final String landlordId;
  final String landlordName;
  final String landlordCode;
  final String hostelName;
  final String hostelCode;
  final String? address;
  final String? town;
  final String schoolId;
  final String? description;
  final int roomsAvailable;
  final String? image;
  final String? images;
  final String phone;
  final String durationType;
  final String paymentMomo;
  final String paymentCash;
  final String paymentBank;
  final String paymentOther;
  final String? googleMap;
  final String? schoolName;
  final String? schoolShortName;
  final String? priceRange;

  // ── Deposit ─────────────────────────────────────────────────
  /// 'none' | 'percent' | 'fixed'
  final String depositType;

  /// Percentage (0–100) when depositType == 'percent',
  /// or a fixed GHS amount when depositType == 'fixed'.
  /// Ignored (treated as 0) when depositType == 'none'.
  final double depositValue;

  const Hostel({
    required this.id,
    required this.landlordId,
    required this.landlordName,
    required this.landlordCode,
    required this.hostelName,
    required this.hostelCode,
    this.address,
    this.town,
    required this.schoolId,
    this.description,
    required this.roomsAvailable,
    this.image,
    this.images,
    required this.phone,
    required this.durationType,
    required this.paymentMomo,
    required this.paymentCash,
    required this.paymentBank,
    required this.paymentOther,
    this.googleMap,
    this.schoolName,
    this.schoolShortName,
    this.priceRange,
    this.depositType = 'none',
    this.depositValue = 0.0,
  });

  /// Calculates the deposit amount for a given room price.
  /// Returns 0 when depositType is 'none'.
  double depositAmountFor(double roomPrice) {
    switch (depositType) {
      case 'percent':
        return roomPrice * depositValue / 100.0;
      case 'fixed':
        return depositValue;
      default:
        return 0.0;
    }
  }

  factory Hostel.fromJson(String docId, Map<String, dynamic> json) => Hostel(
        id: docId,
        landlordId: json['landlord_id']?.toString() ?? '',
        landlordName: json['landlord_name']?.toString() ?? '',
        landlordCode: json['landlord_code']?.toString() ?? '',
        hostelName: json['hostel_name']?.toString() ?? '',
        hostelCode: json['hostel_code']?.toString() ?? '',
        address: json['address']?.toString(),
        town: json['town']?.toString(),
        schoolId: json['school_id']?.toString() ?? '',
        description: json['description']?.toString(),
        roomsAvailable: _parseInt(json['rooms_available']),
        image: json['image']?.toString(),
        images: json['images']?.toString(),
        phone: json['phone']?.toString() ?? '',
        durationType: json['duration_type']?.toString() ?? 'per year',
        paymentMomo: json['payment_momo']?.toString() ?? '',
        paymentCash: json['payment_cash']?.toString() ?? '',
        paymentBank: json['payment_bank']?.toString() ?? '',
        paymentOther: json['payment_other']?.toString() ?? '',
        googleMap: json['google_map']?.toString(),
        schoolName: json['school_name']?.toString(),
        schoolShortName: json['short_name']?.toString(),
        priceRange: json['price_range']?.toString(),
        depositType: json['deposit_type']?.toString() ?? 'none',
        depositValue: _parseDouble(json['deposit_value']),
      );

  Map<String, dynamic> toJson() => {
        'landlord_id': landlordId,
        'landlord_name': landlordName,
        'landlord_code': landlordCode,
        'hostel_name': hostelName,
        'hostel_code': hostelCode,
        'address': address,
        'town': town,
        'school_id': schoolId,
        'description': description,
        'rooms_available': roomsAvailable,
        'image': image,
        'images': images,
        'phone': phone,
        'duration_type': durationType,
        'payment_momo': paymentMomo,
        'payment_cash': paymentCash,
        'payment_bank': paymentBank,
        'payment_other': paymentOther,
        'google_map': googleMap,
        'school_name': schoolName,
        'short_name': schoolShortName,
        'price_range': priceRange,
        'deposit_type': depositType,
        'deposit_value': depositValue,
      };

  Hostel copyWith({
    String? id,
    String? landlordId,
    String? landlordName,
    String? landlordCode,
    String? hostelName,
    String? hostelCode,
    String? address,
    String? town,
    String? schoolId,
    String? description,
    int? roomsAvailable,
    String? image,
    String? images,
    String? phone,
    String? durationType,
    String? paymentMomo,
    String? paymentCash,
    String? paymentBank,
    String? paymentOther,
    String? googleMap,
    String? schoolName,
    String? schoolShortName,
    String? priceRange,
    String? depositType,
    double? depositValue,
  }) =>
      Hostel(
        id: id ?? this.id,
        landlordId: landlordId ?? this.landlordId,
        landlordName: landlordName ?? this.landlordName,
        landlordCode: landlordCode ?? this.landlordCode,
        hostelName: hostelName ?? this.hostelName,
        hostelCode: hostelCode ?? this.hostelCode,
        address: address ?? this.address,
        town: town ?? this.town,
        schoolId: schoolId ?? this.schoolId,
        description: description ?? this.description,
        roomsAvailable: roomsAvailable ?? this.roomsAvailable,
        image: image ?? this.image,
        images: images ?? this.images,
        phone: phone ?? this.phone,
        durationType: durationType ?? this.durationType,
        paymentMomo: paymentMomo ?? this.paymentMomo,
        paymentCash: paymentCash ?? this.paymentCash,
        paymentBank: paymentBank ?? this.paymentBank,
        paymentOther: paymentOther ?? this.paymentOther,
        googleMap: googleMap ?? this.googleMap,
        schoolName: schoolName ?? this.schoolName,
        schoolShortName: schoolShortName ?? this.schoolShortName,
        priceRange: priceRange ?? this.priceRange,
        depositType: depositType ?? this.depositType,
        depositValue: depositValue ?? this.depositValue,
      );
}

// ─── Room ─────────────────────────────────────────────────────
class Room {
  final String id;
  final String hostelId;
  final String hostelName;
  final String hostelCode;
  final String roomNumber;
  final String type;
  final int capacity;
  final double price;
  final bool available;
  final String? image;
  final String? images;
  final int booked;

  const Room({
    required this.id,
    required this.hostelId,
    required this.hostelName,
    required this.hostelCode,
    required this.roomNumber,
    required this.type,
    required this.capacity,
    required this.price,
    required this.available,
    this.image,
    this.images,
    required this.booked,
  });

  /// How many slots are still open in this room.
  int get slotsLeft => (capacity - booked).clamp(0, capacity);

  /// True only when there are open slots.
  bool get hasSpace => available && slotsLeft > 0;

  factory Room.fromJson(String docId, Map<String, dynamic> json) => Room(
        id: docId,
        hostelId: json['hostel_id']?.toString() ?? '',
        hostelName: json['hostel_name']?.toString() ?? '',
        hostelCode: json['hostel_code']?.toString() ?? '',
        roomNumber: json['room_number']?.toString() ?? '',
        type: json['type']?.toString() ?? '',
        capacity: _parseInt(json['capacity']),
        price: _parseDouble(json['price']),
        available: _parseBool(json['available']),
        image: json['image']?.toString(),
        images: json['images']?.toString(),
        booked: _parseInt(json['booked']),
      );

  Map<String, dynamic> toJson() => {
        'hostel_id': hostelId,
        'hostel_name': hostelName,
        'hostel_code': hostelCode,
        'room_number': roomNumber,
        'type': type,
        'capacity': capacity,
        'price': price,
        'available': available,
        'image': image,
        'images': images,
        'booked': booked,
      };

  Room copyWith({
    String? id,
    String? hostelId,
    String? hostelName,
    String? hostelCode,
    String? roomNumber,
    String? type,
    int? capacity,
    double? price,
    bool? available,
    String? image,
    String? images,
    int? booked,
  }) =>
      Room(
        id: id ?? this.id,
        hostelId: hostelId ?? this.hostelId,
        hostelName: hostelName ?? this.hostelName,
        hostelCode: hostelCode ?? this.hostelCode,
        roomNumber: roomNumber ?? this.roomNumber,
        type: type ?? this.type,
        capacity: capacity ?? this.capacity,
        price: price ?? this.price,
        available: available ?? this.available,
        image: image ?? this.image,
        images: images ?? this.images,
        booked: booked ?? this.booked,
      );
}

// ─── Booking ──────────────────────────────────────────────────
/// status values: 'booked' | 'confirmed' | 'active' | 'cancelled' | 'declined' | 'completed'
/// - 'booked'/'confirmed': awaiting payment confirmation or move-in
/// - 'active': move_in_date set, payment_schedule running
/// - 'cancelled'/'declined': revoked or rejected
class Booking {
  final String id;
  final String roomId;
  final String hostelId;
  final String hostelCode;
  final String hostelName;
  final String roomNumber;
  final String name;
  final String email;
  final String phone;

  // ── Academic ────────────────────────────────────────────────
  final String school;
  final String schoolId;
  final bool notStudent;

  // ── Payment ─────────────────────────────────────────────────
  final String paymentMethod;
  final String paymentInfo;
  final double amount;
  final double amountPaid;
  final double balance;
  final double depositAmount;
  final String momoNumber;
  final String paymentReference;
  final String paymentStatus;

  // ── Misc ────────────────────────────────────────────────────
  final String notes;
  final String status;
  final DateTime bookedAt;
  final int slotsBooked;

  // ── Move-in / Payment Schedule ──────────────────────────────
  final String durationType; // 'year' | 'academic_year' | 'semester' | 'month'
  final DateTime? moveInDate;
  final List<Map<String, dynamic>> paymentSchedule;
  final DateTime? balanceDueDate;
  final String? moveInSetBy; // 'student' | 'landlord_or_admin'

  const Booking({
    required this.id,
    required this.roomId,
    required this.hostelId,
    required this.hostelCode,
    required this.hostelName,
    required this.roomNumber,
    required this.name,
    required this.email,
    required this.phone,
    required this.school,
    required this.schoolId,
    required this.notStudent,
    required this.paymentMethod,
    required this.paymentInfo,
    required this.amount,
    this.amountPaid = 0.0,
    this.balance = 0.0,
    this.depositAmount = 0.0,
    required this.momoNumber,
    required this.paymentReference,
    required this.paymentStatus,
    required this.notes,
    required this.status,
    required this.bookedAt,
    required this.slotsBooked,
    this.durationType = 'year',
    this.moveInDate,
    this.paymentSchedule = const [],
    this.balanceDueDate,
    this.moveInSetBy,
  });

  // ── Convenience getters ─────────────────────────────────────
  bool get isPending => status == 'booked';
  bool get isConfirmed => status == 'confirmed';
  bool get isCancelled => status == 'cancelled';
  bool get isCompleted => status == 'completed';

  /// True once the student has logged a move-in date and the
  /// payment schedule/due dates are active.
  bool get isActive => status == 'active';

  /// True when status is 'confirmed' but move-in hasn't been logged yet.
  bool get awaitingMoveIn => status == 'confirmed' && moveInDate == null;

  /// The next unpaid schedule entry, or null if fully paid / no schedule.
  Map<String, dynamic>? get nextUnpaidEntry {
    for (final entry in paymentSchedule) {
      if (entry['paid'] != true) return entry;
    }
    return null;
  }

  factory Booking.fromJson(String docId, Map<String, dynamic> json) => Booking(
        id: docId,
        roomId: json['room_id']?.toString() ?? '',
        hostelId: json['hostel_id']?.toString() ?? '',
        hostelCode: json['hostel_code']?.toString() ?? '',
        hostelName: json['hostel_name']?.toString() ?? '',
        roomNumber: json['room_number']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        phone: json['phone']?.toString() ?? '',
        school: json['school']?.toString() ?? '',
        schoolId: json['school_id']?.toString() ?? '',
        notStudent: _parseBool(json['not_student']),
        paymentMethod: json['payment_method']?.toString() ?? '',
        paymentInfo: json['payment_info']?.toString() ?? '',
        amount: _parseDouble(json['amount']),
        amountPaid: _parseDouble(json['amount_paid']),
        balance: _parseDouble(json['balance']),
        depositAmount: _parseDouble(json['deposit_amount']),
        momoNumber: json['momo_number']?.toString() ?? '',
        paymentReference: json['payment_reference']?.toString() ?? '',
        paymentStatus: json['payment_status']?.toString() ?? '',
        notes: json['notes']?.toString() ?? '',
        status: json['status']?.toString() ?? 'booked',
        bookedAt: _parseDate(json['booked_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        slotsBooked: _parseInt(json['slots_booked'], 1),
        durationType: json['duration_type']?.toString() ?? 'year',
        moveInDate: _parseDate(json['move_in_date']),
        paymentSchedule: _parseSchedule(json['payment_schedule']),
        balanceDueDate: _parseDate(json['balance_due_date']),
        moveInSetBy: json['move_in_set_by']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'room_id': roomId,
        'hostel_id': hostelId,
        'hostel_code': hostelCode,
        'hostel_name': hostelName,
        'room_number': roomNumber,
        'name': name,
        'email': email,
        'phone': phone,
        'school': school,
        'school_id': schoolId,
        'not_student': notStudent,
        'payment_method': paymentMethod,
        'payment_info': paymentInfo,
        'amount': amount,
        'amount_paid': amountPaid,
        'balance': balance,
        'deposit_amount': depositAmount,
        'momo_number': momoNumber,
        'payment_reference': paymentReference,
        'payment_status': paymentStatus,
        'notes': notes,
        'status': status,
        'booked_at': _dateToString(bookedAt),
        'slots_booked': slotsBooked,
        'duration_type': durationType,
        if (moveInDate != null) 'move_in_date': moveInDate!.toIso8601String(),
        'payment_schedule': paymentSchedule,
        if (balanceDueDate != null)
          'balance_due_date': balanceDueDate!.toIso8601String(),
        if (moveInSetBy != null) 'move_in_set_by': moveInSetBy,
      };

  Booking copyWith({
    String? id,
    String? roomId,
    String? hostelId,
    String? hostelCode,
    String? hostelName,
    String? roomNumber,
    String? name,
    String? email,
    String? phone,
    String? school,
    String? schoolId,
    bool? notStudent,
    String? paymentMethod,
    String? paymentInfo,
    double? amount,
    double? amountPaid,
    double? balance,
    double? depositAmount,
    String? momoNumber,
    String? paymentReference,
    String? paymentStatus,
    String? notes,
    String? status,
    DateTime? bookedAt,
    int? slotsBooked,
    String? durationType,
    DateTime? moveInDate,
    List<Map<String, dynamic>>? paymentSchedule,
    DateTime? balanceDueDate,
    String? moveInSetBy,
  }) =>
      Booking(
        id: id ?? this.id,
        roomId: roomId ?? this.roomId,
        hostelId: hostelId ?? this.hostelId,
        hostelCode: hostelCode ?? this.hostelCode,
        hostelName: hostelName ?? this.hostelName,
        roomNumber: roomNumber ?? this.roomNumber,
        name: name ?? this.name,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        school: school ?? this.school,
        schoolId: schoolId ?? this.schoolId,
        notStudent: notStudent ?? this.notStudent,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        paymentInfo: paymentInfo ?? this.paymentInfo,
        amount: amount ?? this.amount,
        amountPaid: amountPaid ?? this.amountPaid,
        balance: balance ?? this.balance,
        depositAmount: depositAmount ?? this.depositAmount,
        momoNumber: momoNumber ?? this.momoNumber,
        paymentReference: paymentReference ?? this.paymentReference,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        notes: notes ?? this.notes,
        status: status ?? this.status,
        bookedAt: bookedAt ?? this.bookedAt,
        slotsBooked: slotsBooked ?? this.slotsBooked,
        durationType: durationType ?? this.durationType,
        moveInDate: moveInDate ?? this.moveInDate,
        paymentSchedule: paymentSchedule ?? this.paymentSchedule,
        balanceDueDate: balanceDueDate ?? this.balanceDueDate,
        moveInSetBy: moveInSetBy ?? this.moveInSetBy,
      );
}

// ─── School ───────────────────────────────────────────────────
class School {
  final String id;
  final String fullName;
  final String shortName;
  final String town;
  final String schoolCode;

  const School({
    required this.id,
    required this.fullName,
    required this.shortName,
    required this.town,
    required this.schoolCode,
  });

  factory School.fromJson(String docId, Map<String, dynamic> json) => School(
        id: docId,
        fullName: json['full_name']?.toString() ?? '',
        shortName: json['short_name']?.toString() ?? '',
        town: json['town']?.toString() ?? '',
        schoolCode: json['school_code']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'full_name': fullName,
        'short_name': shortName,
        'town': town,
        'school_code': schoolCode,
      };

  School copyWith({
    String? id,
    String? fullName,
    String? shortName,
    String? town,
    String? schoolCode,
  }) =>
      School(
        id: id ?? this.id,
        fullName: fullName ?? this.fullName,
        shortName: shortName ?? this.shortName,
        town: town ?? this.town,
        schoolCode: schoolCode ?? this.schoolCode,
      );
}

// ─── Facility ─────────────────────────────────────────────────
class Facility {
  final String id;
  final String hostelId;
  final String hostelCode;
  final String hostelName;
  final String facilityName;

  const Facility({
    required this.id,
    required this.hostelId,
    required this.hostelCode,
    required this.hostelName,
    required this.facilityName,
  });

  factory Facility.fromJson(String docId, Map<String, dynamic> json) =>
      Facility(
        id: docId,
        hostelId: json['hostel_id']?.toString() ?? '',
        hostelCode: json['hostel_code']?.toString() ?? '',
        hostelName: json['hostel_name']?.toString() ?? '',
        facilityName: json['facility_name']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'hostel_id': hostelId,
        'hostel_code': hostelCode,
        'hostel_name': hostelName,
        'facility_name': facilityName,
      };

  Facility copyWith({
    String? id,
    String? hostelId,
    String? hostelCode,
    String? hostelName,
    String? facilityName,
  }) =>
      Facility(
        id: id ?? this.id,
        hostelId: hostelId ?? this.hostelId,
        hostelCode: hostelCode ?? this.hostelCode,
        hostelName: hostelName ?? this.hostelName,
        facilityName: facilityName ?? this.facilityName,
      );
}
