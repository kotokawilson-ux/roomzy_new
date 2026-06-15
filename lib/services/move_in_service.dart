import 'package:cloud_firestore/cloud_firestore.dart';
import 'balance_reminder_service.dart';

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

  Future<void> confirmMoveIn(String bookingId) async {
    final snap = await _db.collection('bookings').doc(bookingId).get();
    final data = snap.data()!;
    final moveIn = DateTime.now();
    final durationType = data['duration_type'] ?? 'year';
    final totalAmount = (data['amount'] as num).toDouble();

    final schedule = buildSchedule(moveIn, durationType, totalAmount);

    await _db.collection('bookings').doc(bookingId).update({
      'move_in_date': Timestamp.fromDate(moveIn),
      'payment_schedule': schedule,
      'balance_due_date': schedule.first['due_date'],
      'status': 'active',
    });
    await BalanceReminderService.instance.cancelMoveInReminders(bookingId);
  }

  Future<void> landlordSetMoveIn(String bookingId, DateTime date) async {
    final snap = await _db.collection('bookings').doc(bookingId).get();
    final data = snap.data()!;
    final durationType = data['duration_type'] ?? 'year';
    final totalAmount = (data['amount'] as num).toDouble();

    final schedule = buildSchedule(date, durationType, totalAmount);

    await _db.collection('bookings').doc(bookingId).update({
      'move_in_date': Timestamp.fromDate(date),
      'payment_schedule': schedule,
      'balance_due_date': schedule.first['due_date'],
      'status': 'active',
      'move_in_set_by': 'landlord_or_admin',
    });
    await BalanceReminderService.instance.cancelMoveInReminders(bookingId);
  }
}
