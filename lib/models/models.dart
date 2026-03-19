// lib/models/models.dart

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

  Hostel({
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
  });

  factory Hostel.fromJson(String docId, Map<String, dynamic> json) => Hostel(
        id: docId,
        landlordId: json['landlord_id']?.toString() ?? '',
        landlordName: json['landlord_name'] ?? '',
        landlordCode: json['landlord_code'] ?? '',
        hostelName: json['hostel_name'] ?? '',
        hostelCode: json['hostel_code'] ?? '',
        address: json['address'],
        town: json['town'],
        schoolId: json['school_id']?.toString() ?? '',
        description: json['description'],
        roomsAvailable: int.parse(json['rooms_available']?.toString() ?? '0'),
        image: json['image'],
        images: json['images'],
        phone: json['phone'] ?? '',
        durationType: json['duration_type'] ?? 'per year',
        paymentMomo: json['payment_momo'] ?? '',
        paymentCash: json['payment_cash'] ?? '',
        paymentBank: json['payment_bank'] ?? '',
        paymentOther: json['payment_other'] ?? '',
        googleMap: json['google_map'],
        schoolName: json['school_name'],
        schoolShortName: json['short_name'],
        priceRange: json['price_range'],
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
      };
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

  Room({
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

  factory Room.fromJson(String docId, Map<String, dynamic> json) => Room(
        id: docId,
        hostelId: json['hostel_id']?.toString() ?? '',
        hostelName: json['hostel_name'] ?? '',
        hostelCode: json['hostel_code'] ?? '',
        roomNumber: json['room_number'] ?? '',
        type: json['type'] ?? '',
        capacity: int.parse(json['capacity']?.toString() ?? '0'),
        price: double.parse(json['price']?.toString() ?? '0'),
        available:
            json['available'].toString() == '1' || json['available'] == true,
        image: json['image'],
        images: json['images'],
        booked: int.parse(json['booked']?.toString() ?? '0'),
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
}

// ─── User ─────────────────────────────────────────────────────
class UserModel {
  final String id;
  final String username;
  final String email;
  final String phone;
  final String role;

  UserModel({
    required this.id,
    required this.username,
    required this.email,
    required this.phone,
    required this.role,
  });

  factory UserModel.fromJson(String docId, Map<String, dynamic> json) =>
      UserModel(
        id: docId,
        username: json['username'] ?? '',
        email: json['email'] ?? '',
        phone: json['phone'] ?? '',
        role: json['role'] ?? 'student',
      );

  Map<String, dynamic> toJson() => {
        'username': username,
        'email': email,
        'phone': phone,
        'role': role,
      };
}

// ─── Booking ──────────────────────────────────────────────────
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
  final String school;
  final String? schoolId;
  final bool notStudent;
  final String? notes;
  final String paymentMethod;
  final String paymentInfo;
  final String status;
  final String bookedAt;
  final int slotsBooked;

  Booking({
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
    this.schoolId,
    required this.notStudent,
    this.notes,
    required this.paymentMethod,
    required this.paymentInfo,
    required this.status,
    required this.bookedAt,
    required this.slotsBooked,
  });

  factory Booking.fromJson(String docId, Map<String, dynamic> json) => Booking(
        id: docId,
        roomId: json['room_id']?.toString() ?? '',
        hostelId: json['hostel_id']?.toString() ?? '',
        hostelCode: json['hostel_code'] ?? '',
        hostelName: json['hostel_name'] ?? '',
        roomNumber: json['room_number'] ?? '',
        name: json['name'] ?? '',
        email: json['email'] ?? '',
        phone: json['phone'] ?? '',
        school: json['school'] ?? '',
        schoolId: json['school_id']?.toString(),
        notStudent: json['not_student'].toString() == '1' ||
            json['not_student'] == true,
        notes: json['notes'],
        paymentMethod: json['payment_method'] ?? '',
        paymentInfo: json['payment_info'] ?? '',
        status: json['status'] ?? 'booked',
        bookedAt: json['booked_at'] ?? '',
        slotsBooked: int.parse(json['slots_booked']?.toString() ?? '1'),
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
        'notes': notes,
        'payment_method': paymentMethod,
        'payment_info': paymentInfo,
        'status': status,
        'booked_at': bookedAt,
        'slots_booked': slotsBooked,
      };
}

// ─── School ───────────────────────────────────────────────────
class School {
  final String id;
  final String fullName;
  final String shortName;
  final String town;
  final String schoolCode;

  School({
    required this.id,
    required this.fullName,
    required this.shortName,
    required this.town,
    required this.schoolCode,
  });

  factory School.fromJson(String docId, Map<String, dynamic> json) => School(
        id: docId,
        fullName: json['full_name'] ?? '',
        shortName: json['short_name'] ?? '',
        town: json['town'] ?? '',
        schoolCode: json['school_code'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'full_name': fullName,
        'short_name': shortName,
        'town': town,
        'school_code': schoolCode,
      };
}

// ─── Landlord ─────────────────────────────────────────────────
class Landlord {
  final String id;
  final String fullName;
  final String email;
  final String phone;
  final String? address;
  final String landlordCode;

  Landlord({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    this.address,
    required this.landlordCode,
  });

  factory Landlord.fromJson(String docId, Map<String, dynamic> json) =>
      Landlord(
        id: docId,
        fullName: json['full_name'] ?? '',
        email: json['email'] ?? '',
        phone: json['phone'] ?? '',
        address: json['address'],
        landlordCode: json['landlord_code'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'full_name': fullName,
        'email': email,
        'phone': phone,
        'address': address,
        'landlord_code': landlordCode,
      };
}

// ─── Facility ─────────────────────────────────────────────────
class Facility {
  final String id;
  final String hostelId;
  final String hostelCode;
  final String hostelName;
  final String facilityName;

  Facility({
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
        hostelCode: json['hostel_code'] ?? '',
        hostelName: json['hostel_name'] ?? '',
        facilityName: json['facility_name'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'hostel_id': hostelId,
        'hostel_code': hostelCode,
        'hostel_name': hostelName,
        'facility_name': facilityName,
      };
}
