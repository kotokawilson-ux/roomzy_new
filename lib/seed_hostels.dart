// seed_hostels.dart
// ─────────────────────────────────────────────────────────────
// Adds 12 hostels (5 HTU, 4 UHAS, 3 NTC) to Firestore.
// Place this file in your lib/ folder and run:
//     dart run lib/seed_hostels.dart
// ─────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  final db = FirebaseFirestore.instance;
  final hostelsRef = db.collection('hostels');

  final List<Map<String, dynamic>> hostels = [
    // ══════════════════════════════════════════
    //  HTU — school_id: "1"
    //  Landlord: Mr. Daniel — landlord_id: "11"
    // ══════════════════════════════════════════

    {
      'hostel_name': 'Akpome Court Hostel',
      'hostel_code': 'AKPOMECOURT-HTU',
      'landlord_id': '11',
      'landlord_name': 'Mr. Daniel',
      'landlord_code': 'MR.DANIEL-035',
      'address': 'Akpome Road, Near HTU Main Gate',
      'town': 'HO',
      'school_id': '1',
      'school_name': 'Ho Technical University',
      'short_name': 'HTU',
      'description':
          'A quiet and secure hostel just 5 minutes walk from HTU main gate. Tiled rooms with good ventilation.',
      'rooms_available': 20,
      'image': '',
      'images': '',
      'phone': '0257219035',
      'duration_type': 'per year',
      'payment_momo': '0257219035',
      'payment_cash': 'Pay in cash at reception',
      'payment_bank': '',
      'payment_other': '',
      'price_range': 'GHS 800 - 2200',
      'google_map': '',
    },

    {
      'hostel_name': 'Dome View Hostel',
      'hostel_code': 'DOMEVIEW-HTU',
      'landlord_id': '11',
      'landlord_name': 'Mr. Daniel',
      'landlord_code': 'MR.DANIEL-035',
      'address': 'Dome Road, Ho',
      'town': 'HO',
      'school_id': '1',
      'school_name': 'Ho Technical University',
      'short_name': 'HTU',
      'description':
          'Affordable student hostel on Dome Road. Close to HTU and local markets. Constant water supply.',
      'rooms_available': 15,
      'image': '',
      'images': '',
      'phone': '0257219035',
      'duration_type': 'per year',
      'payment_momo': '0257219035',
      'payment_cash': 'Pay in cash at reception',
      'payment_bank': '',
      'payment_other': '',
      'price_range': 'GHS 800 - 1800',
      'google_map': '',
    },

    {
      'hostel_name': 'Grace Hostel',
      'hostel_code': 'GRACE-HTU',
      'landlord_id': '11',
      'landlord_name': 'Mr. Daniel',
      'landlord_code': 'MR.DANIEL-035',
      'address': 'Bankoe, Near HTU',
      'town': 'HO',
      'school_id': '1',
      'school_name': 'Ho Technical University',
      'short_name': 'HTU',
      'description':
          'Grace Hostel offers self-contained and non-self-contained rooms near HTU. 24-hour security and reliable electricity.',
      'rooms_available': 18,
      'image': '',
      'images': '',
      'phone': '0257219035',
      'duration_type': 'per year',
      'payment_momo': '0257219035',
      'payment_cash': 'Pay in cash at reception',
      'payment_bank': '',
      'payment_other': '',
      'price_range': 'GHS 900 - 2000',
      'google_map': '',
    },

    {
      'hostel_name': 'Serwaa Hostel',
      'hostel_code': 'SERWAA-HTU',
      'landlord_id': '11',
      'landlord_name': 'Mr. Daniel',
      'landlord_code': 'MR.DANIEL-035',
      'address': 'Kpodzi, Ho — 10 mins from HTU',
      'town': 'HO',
      'school_id': '1',
      'school_name': 'Ho Technical University',
      'short_name': 'HTU',
      'description':
          'Serwaa Hostel is a clean and affordable option for HTU students. Free Wi-Fi in common areas.',
      'rooms_available': 10,
      'image': '',
      'images': '',
      'phone': '0257219035',
      'duration_type': 'per year',
      'payment_momo': '0257219035',
      'payment_cash': 'Pay in cash at reception',
      'payment_bank': '',
      'payment_other': '',
      'price_range': 'GHS 800 - 1600',
      'google_map': '',
    },

    {
      'hostel_name': 'Bright Future Hostel',
      'hostel_code': 'BRIGHTFUTURE-HTU',
      'landlord_id': '11',
      'landlord_name': 'Mr. Daniel',
      'landlord_code': 'MR.DANIEL-035',
      'address': 'Mawuli Road, Ho',
      'town': 'HO',
      'school_id': '1',
      'school_name': 'Ho Technical University',
      'short_name': 'HTU',
      'description':
          'Spacious rooms with ceiling fans and reading desks. Ideal for HTU engineering and science students.',
      'rooms_available': 25,
      'image': '',
      'images': '',
      'phone': '0257219035',
      'duration_type': 'per year',
      'payment_momo': '0257219035',
      'payment_cash': 'Pay in cash at reception',
      'payment_bank': '',
      'payment_other': '',
      'price_range': 'GHS 1000 - 2200',
      'google_map': '',
    },

    // ══════════════════════════════════════════
    //  UHAS — school_id: "11"
    //  Landlord: Mr. John — landlord_id: "12"
    // ══════════════════════════════════════════

    {
      'hostel_name': 'Medics Lodge',
      'hostel_code': 'MEDICSLODGE-UHAS',
      'landlord_id': '12',
      'landlord_name': 'Mr. John',
      'landlord_code': 'MR.JOHN-901',
      'address': 'Sokode Road, Near UHAS Main Campus',
      'town': 'HO',
      'school_id': '11',
      'school_name': 'University of Health and Allied Sciences - Ho',
      'short_name': 'UHAS',
      'description':
          'Purpose-built student hostel for UHAS students. Quiet study environment, secure compound, and borehole water.',
      'rooms_available': 30,
      'image': '',
      'images': '',
      'phone': '0506160901',
      'duration_type': 'per year',
      'payment_momo': '0506160901',
      'payment_cash': 'Pay in cash at reception',
      'payment_bank': '',
      'payment_other': '',
      'price_range': 'GHS 1000 - 2400',
      'google_map': '',
    },

    {
      'hostel_name': 'Healing Springs Hostel',
      'hostel_code': 'HEALINGSPRINGS-UHAS',
      'landlord_id': '12',
      'landlord_name': 'Mr. John',
      'landlord_code': 'MR.JOHN-901',
      'address': 'Sokode Lokoe, Ho — Near UHAS',
      'town': 'HO',
      'school_id': '11',
      'school_name': 'University of Health and Allied Sciences - Ho',
      'short_name': 'UHAS',
      'description':
          'Comfortable self-contained rooms for health science students. Close to UHAS teaching hospital.',
      'rooms_available': 22,
      'image': '',
      'images': '',
      'phone': '0506160901',
      'duration_type': 'per year',
      'payment_momo': '0506160901',
      'payment_cash': 'Pay in cash at reception',
      'payment_bank': '',
      'payment_other': '',
      'price_range': 'GHS 900 - 2100',
      'google_map': '',
    },

    {
      'hostel_name': 'Volta Crest Hostel',
      'hostel_code': 'VOLTACREST-UHAS',
      'landlord_id': '12',
      'landlord_name': 'Mr. John',
      'landlord_code': 'MR.JOHN-901',
      'address': 'Abutia Road, Ho — 8 mins from UHAS',
      'town': 'HO',
      'school_id': '11',
      'school_name': 'University of Health and Allied Sciences - Ho',
      'short_name': 'UHAS',
      'description':
          'Affordable hostel with both self-contained and shared bath options. Walking distance from UHAS campus.',
      'rooms_available': 16,
      'image': '',
      'images': '',
      'phone': '0506160901',
      'duration_type': 'per year',
      'payment_momo': '0506160901',
      'payment_cash': 'Pay in cash at reception',
      'payment_bank': '',
      'payment_other': '',
      'price_range': 'GHS 800 - 1900',
      'google_map': '',
    },

    {
      'hostel_name': 'Tranquil Hostel',
      'hostel_code': 'TRANQUIL-UHAS',
      'landlord_id': '12',
      'landlord_name': 'Mr. John',
      'landlord_code': 'MR.JOHN-901',
      'address': 'Sokode, Ho',
      'town': 'HO',
      'school_id': '11',
      'school_name': 'University of Health and Allied Sciences - Ho',
      'short_name': 'UHAS',
      'description':
          'Serene and well-maintained hostel ideal for UHAS students. Includes kitchen space and secure parking.',
      'rooms_available': 12,
      'image': '',
      'images': '',
      'phone': '0506160901',
      'duration_type': 'per year',
      'payment_momo': '0506160901',
      'payment_cash': 'Pay in cash at reception',
      'payment_bank': '',
      'payment_other': '',
      'price_range': 'GHS 1000 - 2300',
      'google_map': '',
    },

    // ══════════════════════════════════════════
    //  NTC — school_id: "10"
    //  Landlord: Mr. John — landlord_id: "12"
    // ══════════════════════════════════════════

    {
      'hostel_name': 'Nurses Nest Hostel',
      'hostel_code': 'NURSESNEST-NTC',
      'landlord_id': '12',
      'landlord_name': 'Mr. John',
      'landlord_code': 'MR.JOHN-901',
      'address': 'Ho Nursing College Road, Ho',
      'town': 'HO',
      'school_id': '10',
      'school_name': 'Nursing Training College',
      'short_name': 'NTC',
      'description':
          'Convenient hostel for nursing students. Safe, clean, and just a short walk to NTC campus.',
      'rooms_available': 14,
      'image': '',
      'images': '',
      'phone': '0506160901',
      'duration_type': 'per year',
      'payment_momo': '0506160901',
      'payment_cash': 'Pay in cash at reception',
      'payment_bank': '',
      'payment_other': '',
      'price_range': 'GHS 800 - 1800',
      'google_map': '',
    },

    {
      'hostel_name': 'Pearl Hostel',
      'hostel_code': 'PEARL-NTC',
      'landlord_id': '12',
      'landlord_name': 'Mr. John',
      'landlord_code': 'MR.JOHN-901',
      'address': 'Ho Town Centre, Near NTC',
      'town': 'HO',
      'school_id': '10',
      'school_name': 'Nursing Training College',
      'short_name': 'NTC',
      'description':
          'Pearl Hostel provides well-lit, ventilated rooms for nursing students. Borehole water and reliable power.',
      'rooms_available': 8,
      'image': '',
      'images': '',
      'phone': '0506160901',
      'duration_type': 'per year',
      'payment_momo': '0506160901',
      'payment_cash': 'Pay in cash at reception',
      'payment_bank': '',
      'payment_other': '',
      'price_range': 'GHS 800 - 1600',
      'google_map': '',
    },

    {
      'hostel_name': 'Golden Gate Hostel',
      'hostel_code': 'GOLDENGATE-NTC',
      'landlord_id': '12',
      'landlord_name': 'Mr. John',
      'landlord_code': 'MR.JOHN-901',
      'address': 'Bankoe, Ho — Near NTC',
      'town': 'HO',
      'school_id': '10',
      'school_name': 'Nursing Training College',
      'short_name': 'NTC',
      'description':
          'Modern rooms with en-suite bathrooms available. Popular among NTC female students for its secure environment.',
      'rooms_available': 11,
      'image': '',
      'images': '',
      'phone': '0506160901',
      'duration_type': 'per year',
      'payment_momo': '0506160901',
      'payment_cash': 'Pay in cash at reception',
      'payment_bank': '',
      'payment_other': '',
      'price_range': 'GHS 900 - 2000',
      'google_map': '',
    },
  ];

  print('Starting hostel seed for Ho Municipality...');
  print('Total hostels to add: ${hostels.length}');
  print('');

  int count = 0;
  for (final hostel in hostels) {
    try {
      await hostelsRef.add(hostel);
      count++;
      print('[$count/${hostels.length}] ✓ Added: ${hostel['hostel_name']}');
    } catch (e) {
      print('✗ Failed to add ${hostel['hostel_name']}: $e');
    }
  }

  print('');
  print('════════════════════════════════════');
  print('Seed complete! $count/${hostels.length} hostels added.');
  print('════════════════════════════════════');
}
