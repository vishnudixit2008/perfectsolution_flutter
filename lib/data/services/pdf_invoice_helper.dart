import 'dart:isolate';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr/qr.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/sale.dart';
import '../models/sale_item.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Invoice layout configuration (passed from Settings)
// ─────────────────────────────────────────────────────────────────────────────
class InvoiceLayoutConfig {
  final String pageSize;    // 'A5' | 'A4' | 'Thermal80'
  final double marginTB;    // top / bottom in mm
  final double marginLR;    // left / right in mm
  final bool showHeader;
  final bool showQr;
  final String? reviewUrl;
  final String? reviewBusinessName;

  const InvoiceLayoutConfig({
    this.pageSize = 'A5',
    this.marginTB = 10.0,
    this.marginLR = 10.0,
    this.showHeader = true,
    this.showQr = true,
    this.reviewUrl,
    this.reviewBusinessName,
  });

  PdfPageFormat get pdfPageFormat {
    switch (pageSize) {
      case 'A4':
        return PdfPageFormat.a4;
      case 'Thermal80':
        // 80 mm wide roll; height is flexible — use a generous default
        return PdfPageFormat(
          80 * PdfPageFormat.mm,
          297 * PdfPageFormat.mm,
        );
      case 'A5':
      default:
        return PdfPageFormat.a5;
    }
  }

  double get marginTBPts => marginTB * PdfPageFormat.mm;
  double get marginLRPts => marginLR * PdfPageFormat.mm;
}

// ─────────────────────────────────────────────────────────────────────────────
// Plain-Dart parameter bundle — all fields are sendable across isolates.
// Main isolate populates this; background isolate consumes it.
// ─────────────────────────────────────────────────────────────────────────────
class _PdfParams {
  // Sale fields
  final int invoiceNo;
  final int saleDateMs;          // DateTime.millisecondsSinceEpoch
  final String? customerName;
  final String? customerNumber;
  final double totalAmount;
  final double discount;
  final double advance;
  final String paymentMode;

  // Items — each item is a simple map of primitives
  final List<Map<String, dynamic>> items;

  // Computed / config strings
  final String upiVpa;
  final String reviewUrl;
  final String pageSize;
  final double marginTB;
  final double marginLR;
  final bool showHeader;
  final bool showQr;

  // Font bytes (loaded on main isolate via rootBundle, passed as Uint8List)
  final Uint8List? arialRoundedBytes;
  final Uint8List? bookmanBytes;
  final Uint8List? interBytes;

  _PdfParams({
    required this.invoiceNo,
    required this.saleDateMs,
    this.customerName,
    this.customerNumber,
    required this.totalAmount,
    required this.discount,
    required this.advance,
    required this.paymentMode,
    required this.items,
    required this.upiVpa,
    required this.reviewUrl,
    required this.pageSize,
    required this.marginTB,
    required this.marginLR,
    required this.showHeader,
    required this.showQr,
    this.arialRoundedBytes,
    this.bookmanBytes,
    this.interBytes,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Orchestrator — runs on the MAIN isolate.
// Loads fonts & Hive data here (rootBundle & Hive are not available in
// background isolates), bundles everything into a _PdfParams, then offloads
// the actual CPU-heavy PDF build to a background isolate via Isolate.run().
// ─────────────────────────────────────────────────────────────────────────────
bool _isValidTtfBytes(Uint8List bytes) {
  if (bytes.length < 12) return false;
  final b0 = bytes[0], b1 = bytes[1], b2 = bytes[2], b3 = bytes[3];
  // 0x00010000 (TrueType), 0x74727565 ('true'), 0x4F54544F ('OTTO')
  return (b0 == 0 && b1 == 1 && b2 == 0 && b3 == 0) ||
      (b0 == 0x74 && b1 == 0x72 && b2 == 0x75 && b3 == 0x65) ||
      (b0 == 0x4F && b1 == 0x54 && b2 == 0x54 && b3 == 0x4F);
}

final Map<String, Uint8List?> _fontCache = {};

Future<Uint8List?> _loadFontBytes(String assetPath) async {
  if (_fontCache.containsKey(assetPath)) return _fontCache[assetPath];

  // 1. Try direct disk read (always has latest font on desktop without lock)
  try {
    final f = File(assetPath);
    if (f.existsSync()) {
      final bytes = f.readAsBytesSync();
      if (_isValidTtfBytes(bytes)) {
        _fontCache[assetPath] = bytes;
        return bytes;
      }
    }
  } catch (_) {}

  // 2. Fall back to Flutter rootBundle asset
  try {
    final bd = await rootBundle.load(assetPath);
    final bytes = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
    if (_isValidTtfBytes(bytes)) {
      _fontCache[assetPath] = bytes;
      return bytes;
    }
  } catch (_) {}

  _fontCache[assetPath] = null;
  return null;
}

Future<Uint8List> _generatePdfBytes(
  Sale sale,
  List<SaleItem> items,
  String? activeUpiId,
  InvoiceLayoutConfig config,
) async {
  // 1. Load validated fonts (rootBundle & disk checks run on main isolate).
  final arialRoundedBytes = await _loadFontBytes('assets/fonts/ARLRDBD.TTF');
  final bookmanBytes = await _loadFontBytes('assets/fonts/BOOKOSB.TTF');
  final interBytes = await _loadFontBytes('assets/fonts/Inter-Variable.ttf');

  // 2. Read Hive settings (Hive only works on main isolate).
  String reviewUrl = config.reviewUrl ?? '';
  if (reviewUrl.isEmpty) {
    String listingKey = 'perfect_solution';
    try {
      if (Hive.isBoxOpen('settings_box')) {
        final val = Hive.box('settings_box').get('google_review_listing');
        if (val != null && val.toString().isNotEmpty) {
          listingKey = val.toString();
        }
      }
    } catch (_) {}
    reviewUrl = listingKey == 'laptop_repairing'
        ? 'https://g.page/r/CXHBpmozvG4AEBM/review'
        : 'https://g.page/r/CaqZxhuvkW-7EBM/review';
  }

  // 3. Serialize Sale & SaleItems to plain maps (isolate-safe).
  final itemMaps = items
      .map((it) => {
            'itemDescription': it.itemDescription ?? '',
            'notes': it.notes ?? '',
            'quantity': it.quantity,
            'itemPrice': it.itemPrice,
            'customPrice': it.customPrice,
            'totalAmount': it.totalAmount,
          })
      .toList();

  final params = _PdfParams(
    invoiceNo: sale.invoiceNo,
    saleDateMs: sale.saleDate.millisecondsSinceEpoch,
    customerName: sale.customerName,
    customerNumber: sale.customerNumber,
    totalAmount: sale.totalAmount,
    discount: sale.discount,
    advance: sale.advance,
    paymentMode: sale.paymentMode,
    items: itemMaps,
    upiVpa: activeUpiId ?? '9810207643@okbizaxis',
    reviewUrl: reviewUrl,
    pageSize: config.pageSize,
    marginTB: config.marginTB,
    marginLR: config.marginLR,
    showHeader: config.showHeader,
    showQr: config.showQr,
    arialRoundedBytes: arialRoundedBytes,
    bookmanBytes: bookmanBytes,
    interBytes: interBytes,
  );

  // 4. Run the heavy PDF build in a background isolate — UI stays responsive.
  return Isolate.run(() => _buildPdf(params));
}

// ─────────────────────────────────────────────────────────────────────────────
// PDF build function — runs in a BACKGROUND isolate.
// Must not use rootBundle, Hive, or any Flutter-engine-bound APIs.
// All data arrives via the _PdfParams bundle.
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> _buildPdf(_PdfParams p) async {
  // Reconstruct fonts from bytes supplied by the main isolate.
  pw.Font regularFont = pw.Font.helvetica();
  pw.Font boldFont = pw.Font.helveticaBold();
  pw.Font? arialRoundedBold;
  pw.Font? bookmanBold;
  pw.Font? interFont;

  if (p.arialRoundedBytes != null && _isValidTtfBytes(p.arialRoundedBytes!)) {
    try {
      arialRoundedBold = pw.Font.ttf(ByteData.sublistView(p.arialRoundedBytes!));
    } catch (_) {}
  }
  if (p.bookmanBytes != null && _isValidTtfBytes(p.bookmanBytes!)) {
    try {
      bookmanBold = pw.Font.ttf(ByteData.sublistView(p.bookmanBytes!));
    } catch (_) {}
  }
  if (p.interBytes != null && _isValidTtfBytes(p.interBytes!)) {
    try {
      interFont = pw.Font.ttf(ByteData.sublistView(p.interBytes!));
    } catch (_) {}
  }
  arialRoundedBold ??= boldFont;
  bookmanBold ??= boldFont;

  final theme = pw.ThemeData.withFont(
    base: regularFont,
    bold: boldFont,
    fontFallback: [
      ?interFont,
      bookmanBold,
    ],
  );

  final saleDate = DateTime.fromMillisecondsSinceEpoch(p.saleDateMs);
  final formattedDate = DateFormat('dd/MM/yy · hh:mma').format(saleDate);
  final String upiUrl =
      'upi://pay?pa=${p.upiVpa}&am=${p.totalAmount.toStringAsFixed(2)}&cu=INR&tn=Invoice%20${p.invoiceNo}';

  // Build page format from params (no InvoiceLayoutConfig in isolate).
  final PdfPageFormat pageFormat;
  switch (p.pageSize) {
    case 'A4': pageFormat = PdfPageFormat.a4; break;
    case 'Thermal80': pageFormat = PdfPageFormat(80 * PdfPageFormat.mm, 297 * PdfPageFormat.mm); break;
    default: pageFormat = PdfPageFormat.a5;
  }
  final marginV = p.marginTB * PdfPageFormat.mm;
  final marginH = p.marginLR * PdfPageFormat.mm;

  // Build display items list from plain maps.
  final rawItems = p.items;
  final displayItems = rawItems.isNotEmpty
      ? rawItems
      : [
          {
            'itemDescription': 'Sale Order Items',
            'notes': '',
            'quantity': 1,
            'itemPrice': p.totalAmount,
            'customPrice': null,
            'totalAmount': p.totalAmount,
          }
        ];

  final pdf = pw.Document(compress: true);

  pdf.addPage(
    pw.Page(
      pageFormat: pageFormat,
      margin: pw.EdgeInsets.symmetric(vertical: marginV, horizontal: marginH),
      theme: theme,
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // ── Top Header ───────────────────────────────────────────────────
            if (p.showHeader) ...[
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  // Left: F-13 Box Badge (Compound Typography: Arial Rounded MT Bold for "F-" + Bookman Old Style for "13")
                  pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.black, width: 3.2),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7)),
                    ),
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          'F-',
                          style: pw.TextStyle(
                            font: arialRoundedBold,
                            fontSize: 32,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.black,
                          ),
                        ),
                        pw.Text(
                          '13',
                          style: pw.TextStyle(
                            font: bookmanBold,
                            fontSize: 34,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 10),

                  // Middle: Business details
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Text(
                          'PERFECT SOLUTION',
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.black,
                            letterSpacing: 0.6,
                          ),
                        ),
                        pw.SizedBox(height: 2.5),
                        pw.Text(
                          'R E P A I R   ·   S A L E S   ·   S U P P O R T',
                          style: pw.TextStyle(
                            fontSize: 6.2,
                            fontWeight: pw.FontWeight.bold,
                            color: const PdfColor(0.2, 0.25, 0.3),
                            letterSpacing: 1.5,
                          ),
                        ),
                        pw.SizedBox(height: 3.5),
                        pw.Text(
                          'F-13, SKY PLAZA, SHRI RADHA SKY GARDEN,',
                          style: pw.TextStyle(
                            fontSize: 6.8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.black,
                            letterSpacing: 0.1,
                          ),
                        ),
                        pw.Text(
                          'SECTOR 16B, GREATER NOIDA WEST',
                          style: pw.TextStyle(
                            fontSize: 6.8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.black,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Right: Estimate # & Phones
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      pw.Text(
                        'ESTIMATE',
                        style: pw.TextStyle(
                          fontSize: 7.0,
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor(0.4, 0.4, 0.4),
                          letterSpacing: 1.2,
                        ),
                      ),
                      pw.Text(
                        '#${p.invoiceNo}',
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        '9810207643',
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                      ),
                      pw.Text(
                        '9212117643',
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Container(height: 1.2, color: PdfColors.black),
              pw.SizedBox(height: 8),
            ],

            // ── Billed To & Date / Time ──────────────────────────────────────
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'BILLED TO',
                      style: pw.TextStyle(
                        fontSize: 6.8,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      p.customerName?.trim().isNotEmpty == true
                          ? p.customerName!.toUpperCase()
                          : 'WALK-IN CUSTOMER',
                      style: pw.TextStyle(
                        fontSize: 9.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.black,
                      ),
                    ),
                    if (p.customerNumber != null &&
                        p.customerNumber!.trim().isNotEmpty) ...[
                      pw.SizedBox(height: 1),
                      pw.Text(
                        p.customerNumber!.startsWith('+')
                            ? p.customerNumber!
                            : '+91${p.customerNumber}',
                        style: const pw.TextStyle(
                          fontSize: 7.5,
                          color: PdfColors.grey800,
                        ),
                      ),
                    ],
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'DATE & TIME',
                      style: pw.TextStyle(
                        fontSize: 6.8,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      formattedDate,
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.black,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),

            // ── Items Table (Exact Layout & Column Widths) ───────────────────
            pw.Table(
              columnWidths: const {
                0: pw.FlexColumnWidth(5.6),
                1: pw.FlexColumnWidth(1.2),
                2: pw.FlexColumnWidth(1.8),
                3: pw.FlexColumnWidth(1.8),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: PdfColor(0.14, 0.17, 0.22),
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                  ),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      child: pw.Text(
                        'DESCRIPTION OF GOODS',
                        style: pw.TextStyle(
                          fontSize: 7.2,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                      child: pw.Text(
                        'QTY',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          fontSize: 7.2,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                      child: pw.Text(
                        'UNIT PRICE',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                          fontSize: 7.2,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                      child: pw.Text(
                        'AMOUNT',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                          fontSize: 7.2,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
                ...displayItems.map((item) {
                  final desc = (item['itemDescription'] as String?)?.trim() ?? 'Line Item';
                  final notes = (item['notes'] as String?)?.trim();
                  final qty = item['quantity'] as int;
                  final customPrice = item['customPrice'] as double?;
                  final price = customPrice ?? (item['itemPrice'] as double);
                  final rawAmt = item['totalAmount'] as double;
                  final amt = rawAmt > 0 ? rawAmt : (qty * price);

                  String primaryTitle = desc;
                  String? subDetails;
                  if (desc.contains('\n')) {
                    final split = desc.split('\n');
                    primaryTitle = split.first.trim();
                    subDetails = split.sublist(1).join('\n').trim();
                  } else if (desc.contains(' - S/N:')) {
                    final split = desc.split(' - S/N:');
                    primaryTitle = split.first.trim();
                    subDetails = 'S/N: ${split[1].trim()}';
                  } else if (notes != null && notes.isNotEmpty) {
                    subDetails = notes;
                  }

                  return pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFE5E7EB), width: 0.8),
                      ),
                    ),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              primaryTitle.toUpperCase(),
                              style: pw.TextStyle(
                                fontSize: 8.0,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.black,
                              ),
                            ),
                            if (subDetails != null && subDetails.isNotEmpty) ...[
                              pw.SizedBox(height: 0.8),
                              pw.Text(
                                subDetails,
                                style: const pw.TextStyle(
                                  fontSize: 5.8,
                                  color: PdfColors.grey700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
                        child: pw.Text(
                          '$qty',
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            fontSize: 8.0,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.black,
                          ),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
                        child: pw.Text(
                          '₹ ${price.toStringAsFixed(2)}',
                          textAlign: pw.TextAlign.right,
                          style: const pw.TextStyle(
                            fontSize: 8.0,
                            color: PdfColors.black,
                          ),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
                        child: pw.Text(
                          '₹ ${amt.toStringAsFixed(2)}',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                            fontSize: 8.0,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.black,
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),

            // ── Totals Section ───────────────────────────────────────────────
            (() {
              final double itemsSubtotal = displayItems.fold(
                0.0,
                (sum, it) {
                  final itAmt = it['totalAmount'] as double;
                  final itQty = it['quantity'] as int;
                  final itCustom = it['customPrice'] as double?;
                  final itPrice = itCustom ?? (it['itemPrice'] as double);
                  return sum + (itAmt > 0 ? itAmt : (itQty * itPrice));
                },
              );

              return pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 4),
                child: pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      if (p.discount > 0 || p.advance > 0)
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 1),
                          child: pw.Row(
                            mainAxisSize: pw.MainAxisSize.min,
                            children: [
                              pw.Text(
                                'SUBTOTAL: ',
                                style: pw.TextStyle(
                                  fontSize: 7.8,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.grey700,
                                ),
                              ),
                              pw.Text(
                                '₹ ${itemsSubtotal.toStringAsFixed(2)}',
                                style: pw.TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (p.discount > 0)
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 1),
                          child: pw.Row(
                            mainAxisSize: pw.MainAxisSize.min,
                            children: [
                              pw.Text(
                                'DISCOUNT: ',
                                style: pw.TextStyle(
                                  fontSize: 7.8,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.grey700,
                                ),
                              ),
                              pw.Text(
                                '- ₹ ${p.discount.toStringAsFixed(2)}',
                                style: pw.TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.red700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (p.advance > 0)
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 1),
                          child: pw.Row(
                            mainAxisSize: pw.MainAxisSize.min,
                            children: [
                              pw.Text(
                                'ADVANCE PAID: ',
                                style: pw.TextStyle(
                                  fontSize: 7.8,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.grey700,
                                ),
                              ),
                              pw.Text(
                                '- ₹ ${p.advance.toStringAsFixed(2)}',
                                style: pw.TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.green700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 2, bottom: 2),
                        child: pw.Row(
                          mainAxisSize: pw.MainAxisSize.min,
                          children: [
                            pw.Text(
                              'GRAND TOTAL',
                              style: pw.TextStyle(
                                fontSize: 10.5,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.black,
                                letterSpacing: 0.5,
                              ),
                            ),
                            pw.SizedBox(width: 28),
                            pw.Text(
                              '₹ ${p.totalAmount.toStringAsFixed(2)}',
                              style: pw.TextStyle(
                                fontSize: 16,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            })(),
            pw.SizedBox(height: 5),

            // ── Dynamic Payment & Review Row (Symmetrical matching boxes) ───
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Left: Google Review Card
                pw.Expanded(
                  child: pw.Container(
                    height: 88,
                    margin: const pw.EdgeInsets.only(right: 7),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: const PdfColor(0.75, 0.78, 0.82), width: 1.0),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(vertical: 3),
                          decoration: const pw.BoxDecoration(
                            color: PdfColor(0.14, 0.17, 0.22),
                            borderRadius: pw.BorderRadius.only(
                              topLeft: pw.Radius.circular(5),
                              topRight: pw.Radius.circular(5),
                            ),
                          ),
                          child: pw.Center(
                            child: pw.Text(
                              'SCAN TO RATE US ON GOOGLE',
                              style: pw.TextStyle(
                                fontSize: 6.5,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.white,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ),
                        pw.Expanded(
                          child: pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                            child: pw.Column(
                              mainAxisAlignment: pw.MainAxisAlignment.center,
                              crossAxisAlignment: pw.CrossAxisAlignment.center,
                              children: [
                                _buildQr(p.reviewUrl, 40),
                                pw.SizedBox(height: 2.0),
                                pw.Row(
                                  mainAxisSize: pw.MainAxisSize.min,
                                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                                  children: [
                                    pw.Text(
                                      'Rate Us ',
                                      style: pw.TextStyle(
                                        fontSize: 6.8,
                                        fontWeight: pw.FontWeight.bold,
                                        color: PdfColors.black,
                                      ),
                                    ),
                                    ...List.generate(
                                      5,
                                      (_) => pw.Padding(
                                        padding: const pw.EdgeInsets.symmetric(horizontal: 0.8),
                                        child: _buildVectorStar(size: 5.5, color: const PdfColor(0.95, 0.75, 0.1)),
                                      ),
                                    ),
                                  ],
                                ),
                                pw.SizedBox(height: 1.0),
                                pw.Text(
                                  'Get a Laptop Cleaner or Mouse Pad Free!',
                                  style: pw.TextStyle(
                                    fontSize: 5.2,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.black,
                                  ),
                                ),
                                pw.SizedBox(height: 0.8),
                                pw.Text(
                                  'Scan with camera to rate us',
                                  style: const pw.TextStyle(
                                    fontSize: 4.6,
                                    color: PdfColors.grey700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Right: UPI Payment Card
                if (p.showQr)
                  pw.Expanded(
                    child: pw.Container(
                      height: 88,
                      margin: const pw.EdgeInsets.only(left: 7),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: const PdfColor(0.75, 0.78, 0.82), width: 1.0),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(vertical: 3),
                            decoration: const pw.BoxDecoration(
                              color: PdfColor(0.14, 0.17, 0.22),
                              borderRadius: pw.BorderRadius.only(
                                topLeft: pw.Radius.circular(5),
                                topRight: pw.Radius.circular(5),
                              ),
                            ),
                            child: pw.Center(
                              child: pw.Text(
                                'PAY VIA UPI',
                                style: pw.TextStyle(
                                  fontSize: 6.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.white,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ),
                          pw.Expanded(
                            child: pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                              child: pw.Column(
                                mainAxisAlignment: pw.MainAxisAlignment.center,
                                crossAxisAlignment: pw.CrossAxisAlignment.center,
                                children: [
                                  _buildQr(upiUrl, 40),
                                  pw.SizedBox(height: 2.0),
                                  pw.Text(
                                    'Instant UPI Payment',
                                    style: pw.TextStyle(
                                      fontSize: 6.8,
                                      fontWeight: pw.FontWeight.bold,
                                      color: PdfColors.black,
                                    ),
                                  ),
                                  pw.SizedBox(height: 1.0),
                                  pw.Text(
                                    'Scan with any UPI app to pay',
                                    style: pw.TextStyle(
                                      fontSize: 5.2,
                                      fontWeight: pw.FontWeight.bold,
                                      color: PdfColors.black,
                                    ),
                                  ),
                                  pw.SizedBox(height: 0.8),
                                  pw.Text(
                                    'GPay · PhonePe · Paytm · UPI',
                                    style: const pw.TextStyle(
                                      fontSize: 4.6,
                                      color: PdfColors.grey700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            pw.SizedBox(height: 5),

            // ── Terms & Conditions ───────────────────────────────────────────
            pw.Container(height: 1.2, color: const PdfColor(0.07, 0.09, 0.15)),
            pw.SizedBox(height: 4),
            pw.Text(
              'T E R M S   &   C O N D I T I O N S',
              style: pw.TextStyle(
                fontSize: 7.2,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
                letterSpacing: 2.2,
              ),
            ),
            pw.SizedBox(height: 4.5),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '1.  ',
                  style: pw.TextStyle(
                    fontSize: 5.8,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    'Warranty for new products/parts is provided solely by the respective Principal Company / Brand Service Center as per their policy.',
                    style: const pw.TextStyle(
                      fontSize: 5.8,
                      color: PdfColor(0.2, 0.25, 0.3),
                      lineSpacing: 1.25,
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 2.0),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '2.  ',
                  style: pw.TextStyle(
                    fontSize: 5.8,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    'Warranty stands VOID in case of Physical Damage, Liquid Damage, Electrical Burn / Short-Circuiting, or if the Serial Number / Warranty Sticker is missing, broken, or tampered with.',
                    style: const pw.TextStyle(
                      fontSize: 5.8,
                      color: PdfColor(0.2, 0.25, 0.3),
                      lineSpacing: 1.25,
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 2.0),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '3.  ',
                  style: pw.TextStyle(
                    fontSize: 5.8,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    'Original bill is required for any warranty claims.',
                    style: const pw.TextStyle(
                      fontSize: 5.8,
                      color: PdfColor(0.2, 0.25, 0.3),
                      lineSpacing: 1.25,
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),

            // ── Final Center Footer ──────────────────────────────────────────
            pw.Center(
              child: pw.Text(
                'Thank you for your business!',
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  return await pdf.save();
}

pw.Widget _buildVectorStar({double size = 7, PdfColor color = const PdfColor(0.95, 0.75, 0.1)}) {
  return pw.CustomPaint(
    size: PdfPoint(size, size),
    painter: (PdfGraphics g, PdfPoint sizePoint) {
      final double cx = sizePoint.x / 2;
      final double cy = sizePoint.y / 2;
      final double outerRadius = sizePoint.x / 2;
      final double innerRadius = outerRadius * 0.4;
      g.setFillColor(color);
      for (int i = 0; i < 10; i++) {
        final double r = i.isEven ? outerRadius : innerRadius;
        final double angle = (i * 36 - 90) * math.pi / 180;
        final double x = cx + r * math.cos(angle);
        final double y = cy - r * math.sin(angle);
        if (i == 0) {
          g.moveTo(x, y);
        } else {
          g.lineTo(x, y);
        }
      }
      g.closePath();
      g.fillPath();
    },
  );
}

pw.Widget _buildQr(String data, double size) {
  try {
    final qrCode = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final qrImage = QrImage(qrCode);
    final int moduleCount = qrImage.moduleCount;
    return pw.CustomPaint(
      size: PdfPoint(size, size),
      painter: (PdfGraphics g, PdfPoint sizePoint) {
        final double blockSize = sizePoint.x / moduleCount;
        g.setFillColor(PdfColors.black);
        for (int x = 0; x < moduleCount; x++) {
          for (int y = 0; y < moduleCount; y++) {
            if (qrImage.isDark(y, x)) {
              g.drawRect(
                x * blockSize,
                sizePoint.y - ((y + 1) * blockSize),
                blockSize + 0.05,
                blockSize + 0.05,
              );
            }
          }
        }
        g.fillPath();
      },
    );
  } catch (_) {
    return pw.SizedBox(width: size, height: size);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────
class PdfInvoiceHelper {
  /// Generates the invoice PDF bytes in a background isolate so the UI stays
  /// responsive. Fonts and Hive settings are loaded on the main isolate first,
  /// then all CPU-heavy work (layout, QR generation, PDF encoding) runs in a
  /// separate isolate via [Isolate.run].
  static Future<Uint8List> generatePdfBytes({
    required Sale sale,
    required List<SaleItem> items,
    required String? activeUpiId,
    InvoiceLayoutConfig config = const InvoiceLayoutConfig(),
  }) {
    return _generatePdfBytes(sale, items, activeUpiId, config);
  }

  /// Writes invoice [pdfBytes] to a temporary file and opens it in the default OS PDF viewer
  /// (Preview.app on macOS, default PDF application on Windows).
  /// This is 100% non-blocking, fast, and does not freeze the app.
  static Future<void> directPrint({
    required Uint8List pdfBytes,
    required String invoiceName,
    String? printerName,
    InvoiceLayoutConfig config = const InvoiceLayoutConfig(),
  }) async {
    await openPdfFile(pdfBytes: pdfBytes, fileName: invoiceName);
  }

  /// Saves [pdfBytes] to temp directory and opens in OS default viewer
  /// (Preview.app on macOS, default PDF viewer on Windows).
  static Future<bool> openPdfFile({
    required Uint8List pdfBytes,
    required String fileName,
  }) async {
    try {
      final safeName = fileName.replaceAll(RegExp(r'[/\\]'), '_');

      // On Android & iOS (Mobile Devices): Use Printing package to open native PDF Viewer & Print preview sheet
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        try {
          await Printing.layoutPdf(
            onLayout: (format) async => pdfBytes,
            name: safeName,
          );
          return true;
        } catch (e) {
          if (kDebugMode) print('Mobile Printing.layoutPdf error: $e');
          try {
            await Printing.sharePdf(bytes: pdfBytes, filename: safeName);
            return true;
          } catch (_) {}
        }
      }

      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/$safeName');
      await file.writeAsBytes(pdfBytes, flush: true);

      // On macOS: /usr/bin/open launches Preview.app natively & instantly
      if (!kIsWeb && Platform.isMacOS) {
        try {
          final res = await Process.run('/usr/bin/open', [file.path]);
          if (res.exitCode == 0) return true;
        } catch (_) {}
        try {
          await Process.run('open', [file.path]);
          return true;
        } catch (_) {}
      }

      // On Windows: launches default OS PDF application instantly
      if (!kIsWeb && Platform.isWindows) {
        try {
          final uri = Uri.file(file.path);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            return true;
          }
        } catch (_) {}

        try {
          // Process.start returns immediately without blocking on cmd.exe or child process
          await Process.start('cmd.exe', ['/c', 'start', '', file.path], runInShell: true);
          return true;
        } catch (_) {}
      }

      // On Linux: xdg-open
      if (!kIsWeb && Platform.isLinux) {
        try {
          await Process.run('xdg-open', [file.path]);
          return true;
        } catch (_) {}
      }

      // Universal fallback
      try {
        final uri = Uri.file(file.path);
        if (await canLaunchUrl(uri)) {
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (_) {}

      try {
        await Printing.layoutPdf(
          onLayout: (format) async => pdfBytes,
          name: safeName,
        );
        return true;
      } catch (_) {}

      return false;
    } catch (e) {
      if (kDebugMode) print('openPdfFile error: $e');
      return false;
    }
  }

  /// Convenience method to generate and open invoice PDF instantly in default system viewer.
  static Future<bool> printInvoice({
    required Sale sale,
    required List<SaleItem> items,
    required String? activeUpiId,
    InvoiceLayoutConfig config = const InvoiceLayoutConfig(),
  }) async {
    final pdfBytes = await generatePdfBytes(
      sale: sale,
      items: items,
      activeUpiId: activeUpiId,
      config: config,
    );

    return await openPdfFile(
      pdfBytes: pdfBytes,
      fileName: 'Invoice_${sale.invoiceNo}.pdf',
    );
  }
}
