import 'package:cloud_firestore/cloud_firestore.dart';
import 'balance_reminder_service.dart';
import '../models/models.dart'; // for Hostel

class MoveInService {
  static final MoveInService instance = MoveInService._();
  MoveInService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String normalizeDurationType(String hostelDurationType) {
    switch (hostelDurationType.toLowerCase().trim()) {
      case 'per year':
        return 'year';
      case 'per academic year':
        return 'academic_year';
      case 'per semester':
        return 'semester';
      case 'per month':
        return 'month';
      default:
        return 'year';
    }
  }

  List<Map<String, dynamic>> buildSchedule(
    DateTime moveIn,
    String durationType,
    double totalAmount,
  ) {
    final label = switch (durationType) {
      'year' => 'Full Year Payment',
      'academic_year' => 'Academic Year Payment',
      'semester' => 'Semester Payment',
      _ => 'Month 1',
    };
    return [
      {
        'due_date': Timestamp.fromDate(moveIn),
        'amount': totalAmount,
        'label': label,
        'paid': false,
      },
    ];
  }

  // ── Shared: fetch the hostel and compute the real balance due date ───────
  // Both confirmMoveIn (student) and landlordSetMoveIn (admin/landlord) call
  // this so they can never calculate the due date differently again.
  Future<_DueDateResult> _resolveDueDate(
    Map<String, dynamic> bookingData,
    DateTime moveIn,
  ) async {
    final hostelId = bookingData['hostel_id']?.toString();
    if (hostelId == null || hostelId.isEmpty) {
      return _DueDateResult(dueDate: null, unit: null, amount: null);
    }

    final hostelSnap = await _db.collection('hostels').doc(hostelId).get();
    if (!hostelSnap.exists) {
      return _DueDateResult(dueDate: null, unit: null, amount: null);
    }

    final hostel = Hostel.fromJson(hostelSnap.id, hostelSnap.data()!);
    final autoDue = hostel.autoDueDate(moveIn);

    return _DueDateResult(
      dueDate: autoDue,
      unit: hostel.balanceDueUnit,
      amount: hostel.balanceDueAmount,
    );
  }

  Future<void> confirmMoveIn(String bookingId) async {
    final snap = await _db.collection('bookings').doc(bookingId).get();
    if (!snap.exists) {
      throw Exception('Booking not found');
    }
    final data = snap.data()!;

    // Guard: never activate a declined or cancelled booking (mirrors the
    // admin-side check in bookings_pane.dart's _setMoveInDate).
    final currentStatus = (data['status'] ?? '') as String;
    if (currentStatus == 'declined' || currentStatus == 'cancelled') {
      throw Exception(
          'Cannot confirm move-in on a declined or cancelled booking');
    }

    final moveIn = DateTime.now();
    final durationType = data['duration_type'] ?? 'year';
    final totalAmount = (data['amount'] as num).toDouble();

    final schedule = buildSchedule(moveIn, durationType, totalAmount);
    final due = await _resolveDueDate(data, moveIn);

    await _db.collection('bookings').doc(bookingId).update({
      'move_in_date': Timestamp.fromDate(moveIn),
      'payment_schedule': schedule,
      'balance_due_date':
          due.dueDate != null ? Timestamp.fromDate(due.dueDate!) : null,
      'balance_due_unit': due.unit,
      'balance_due_amount': due.amount,
      'status': 'active',
      'move_in_confirmed': true,
      'move_in_set_by': 'student',
    });
    await BalanceReminderService.instance.cancelMoveInReminders(bookingId);
  }

  Future<void> landlordSetMoveIn(String bookingId, DateTime date) async {
    final snap = await _db.collection('bookings').doc(bookingId).get();
    if (!snap.exists) {
      throw Exception('Booking not found');
    }
    final data = snap.data()!;

    final currentStatus = (data['status'] ?? '') as String;
    if (currentStatus == 'declined' || currentStatus == 'cancelled') {
      throw Exception(
          'Cannot set move-in date on a declined or cancelled booking');
    }

    final durationType = data['duration_type'] ?? 'year';
    final totalAmount = (data['amount'] as num).toDouble();

    final schedule = buildSchedule(date, durationType, totalAmount);
    final due = await _resolveDueDate(data, date);

    await _db.collection('bookings').doc(bookingId).update({
      'move_in_date': Timestamp.fromDate(date),
      'payment_schedule': schedule,
      'balance_due_date':
          due.dueDate != null ? Timestamp.fromDate(due.dueDate!) : null,
      'balance_due_unit': due.unit,
      'balance_due_amount': due.amount,
      'status': 'active',
      'move_in_confirmed': true,
      'move_in_set_by': 'landlord_or_admin',
    });
    await BalanceReminderService.instance.cancelMoveInReminders(bookingId);
  }
}

class _DueDateResult {
  final DateTime? dueDate;
  final String? unit;
  final int? amount;
  const _DueDateResult({
    required this.dueDate,
    required this.unit,
    required this.amount,
  });
}
