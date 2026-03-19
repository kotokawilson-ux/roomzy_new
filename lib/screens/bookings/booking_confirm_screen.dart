import 'package:flutter/material.dart';

class BookingConfirmScreen extends StatelessWidget {
  final int roomId;
  const BookingConfirmScreen({super.key, required this.roomId});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text('Confirm Booking Room $roomId - Coming Soon')),
    );
  }
}
