// lib/services/receipt_pdf_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

class ReceiptPdfService {
  static final _money = NumberFormat('#,##0.00');
  static final _dateFmt = DateFormat('dd MMM yyyy, hh:mm a');

  /// Full receipt — booking details + every payment made against it.
  static Future<void> printBookingReceipt({
    required Map<String, dynamic> booking,
    required String bookingId,
    required List<Map<String, dynamic>> payments,
  }) async {
    final doc = await _build(
        booking: booking, bookingId: bookingId, payments: payments);
    final bytes = await doc.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'RoomzyFind_Receipt_${bookingId.substring(0, 8).toUpperCase()}.pdf',
    );
  }

  /// Same layout, scoped to one payment (e.g. "just this installment").
  static Future<void> printSinglePaymentReceipt({
    required Map<String, dynamic> booking,
    required String bookingId,
    required Map<String, dynamic> payment,
  }) =>
      printBookingReceipt(
          booking: booking, bookingId: bookingId, payments: [payment]);

  static Future<pw.Document> _build({
    required Map<String, dynamic> booking,
    required String bookingId,
    required List<Map<String, dynamic>> payments,
  }) async {
    final doc = pw.Document();
    final primary = PdfColor.fromInt(0xFF0F766E);
    final dark = PdfColor.fromInt(0xFF0D1B2A);
    final grey = PdfColor.fromInt(0xFF64748B);
    final border = PdfColor.fromInt(0xFFE2E8F0);

    final totalPaidHere = payments.fold<double>(
        0, (sum, p) => sum + ((p['amount'] as num?)?.toDouble() ?? 0));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('RoomzyFind',
                    style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: primary)),
                pw.Text('PAYMENT RECEIPT',
                    style: pw.TextStyle(
                        fontSize: 11, color: grey, letterSpacing: 1.2)),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text('Booking Ref: ${bookingId.toUpperCase().substring(0, 8)}',
                style: pw.TextStyle(fontSize: 10, color: grey)),
            pw.Divider(color: border, thickness: 1),
          ],
        ),
        footer: (ctx) => pw.Column(children: [
          pw.Divider(color: border),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Generated ${_dateFmt.format(DateTime.now())}',
                  style: pw.TextStyle(fontSize: 8, color: grey)),
              pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                  style: pw.TextStyle(fontSize: 8, color: grey)),
            ],
          ),
        ]),
        build: (ctx) => [
          pw.SizedBox(height: 12),
          _sectionTitle('Guest Details', primary),
          _kv('Name', booking['name'] ?? '—', dark, grey),
          _kv('Email', booking['email'] ?? '—', dark, grey),
          _kv('Phone', booking['phone'] ?? '—', dark, grey),
          pw.SizedBox(height: 16),
          _sectionTitle('Booking Details', primary),
          _kv('Hostel', booking['hostel_name'] ?? '—', dark, grey),
          _kv('Room', booking['room_number'] ?? '—', dark, grey),
          _kv('Slots', '${booking['slots_booked'] ?? 1}', dark, grey),
          pw.SizedBox(height: 16),
          _sectionTitle('Payment Summary', primary),
          _kv(
              'Total Amount',
              'GHS ${_money.format((booking['amount'] ?? 0).toDouble())}',
              dark,
              grey),
          _kv(
              'Amount Paid (to date)',
              'GHS ${_money.format((booking['amount_paid'] ?? 0).toDouble())}',
              dark,
              grey),
          _kv(
              'Balance Remaining',
              'GHS ${_money.format((booking['balance'] ?? 0).toDouble())}',
              dark,
              grey),
          pw.SizedBox(height: 20),
          _sectionTitle(
              payments.length == 1
                  ? 'Payment'
                  : 'Payment History (${payments.length})',
              primary),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: border, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(0.6),
              1: pw.FlexColumnWidth(1.4),
              2: pw.FlexColumnWidth(1.2),
              3: pw.FlexColumnWidth(1.8),
              4: pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                decoration:
                    pw.BoxDecoration(color: PdfColor.fromInt(0xFFF8FAFC)),
                children: [
                  _th('#'),
                  _th('Date'),
                  _th('Amount'),
                  _th('Reference'),
                  _th('Status')
                ],
              ),
              for (final p in payments)
                pw.TableRow(children: [
                  _td('${p['payment_number'] ?? '—'}'),
                  _td(p['paid_at'] is Timestamp
                      ? _dateFmt.format((p['paid_at'] as Timestamp).toDate())
                      : '—'),
                  _td('GHS ${_money.format((p['amount'] ?? 0).toDouble())}'),
                  _td('${p['reference'] ?? '—'}'),
                  _td((p['status'] ?? '—').toString().toUpperCase()),
                ]),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
                'Total on this receipt: GHS ${_money.format(totalPaidHere)}',
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold, fontSize: 12, color: dark)),
          ),
        ],
      ),
    );
    return doc;
  }

  static pw.Widget _sectionTitle(String t, PdfColor c) => pw.Text(t,
      style:
          pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: c));

  static pw.Widget _kv(String k, String v, PdfColor dark, PdfColor grey) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(children: [
          pw.SizedBox(
              width: 130,
              child:
                  pw.Text(k, style: pw.TextStyle(fontSize: 10, color: grey))),
          pw.Text(v,
              style: pw.TextStyle(
                  fontSize: 10, color: dark, fontWeight: pw.FontWeight.bold)),
        ]),
      );

  static pw.Widget _th(String t) => pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(t,
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)));

  static pw.Widget _td(String t) => pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(t, style: const pw.TextStyle(fontSize: 9)));
}
