import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ActivityLogger {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  /// Call this everywhere you do a Firestore write.
  static Future<void> log({
    required String action,
    String details = '',
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      await _db.collection('activityLog').add({
        'userId': user.uid,
        'userEmail': user.email ?? 'unknown',
        'action': action,
        'details': details,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Never crash the app because of a logging failure
      debugPrint('ActivityLogger error: $e');
    }
  }
}
