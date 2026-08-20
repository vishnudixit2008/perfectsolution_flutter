import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
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
// PDF build function (runs on main isolate — the pdf package is pure Dart
// and completes in <100ms for a typical invoice, so no isolate needed).
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> _buildPdf(
  Sale sale,
  List<SaleItem> items,
  String? activeUpiId,
  InvoiceLayoutConfig config,
) async {
  pw.Font? regularFont;
  pw.Font? boldFont;
  try {
    regularFont = await PdfGoogleFonts.robotoRegular();
    boldFont = await PdfGoogleFonts.robotoBold();
  } catch (_) {
    regularFont = pw.Font.helvetica();
    boldFont = pw.Font.helveticaBold();
  }

  final theme = pw.ThemeData.withFont(
    base: regularFont,
    bold: boldFont,
  );

  final formattedDate = DateFormat('dd/MM/yy · hh:mma').format(sale.saleDate);
  final String upiVpa = activeUpiId ?? '9810207643@okbizaxis';
  final String upiUrl =
      'upi://pay?pa=$upiVpa&am=${sale.dueAmount > 0 ? sale.dueAmount.toStringAsFixed(2) : sale.totalAmount.toStringAsFixed(2)}&cu=INR&tn=Invoice%20${sale.invoiceNo}';

  // Determine Google Review URL
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
    if (listingKey == 'laptop_repairing') {
      reviewUrl = 'https://g.page/r/CXHBpmozvG4AEBM/review';
    } else {
      reviewUrl = 'https://g.page/r/CaqZxhuvkW-7EBM/review';
    }
  }

  final displayItems = items.isNotEmpty
      ? items
      : [
          SaleItem(
            id: '1',
            invoiceNo: sale.invoiceNo,
            lineType: 'Product',
            itemDescription: 'Sale Order Items',
            quantity: 1,
            itemPrice: sale.totalAmount,
            totalAmount: sale.totalAmount,
          ),
        ];

  final pdf = pw.Document(compress: true);

  pdf.addPage(
    pw.Page(
      pageFormat: config.pdfPageFormat,
      margin: pw.EdgeInsets.symmetric(
        vertical: config.marginTBPts,
        horizontal: config.marginLRPts,
      ),
      theme: theme,
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // ── Top Header ───────────────────────────────────────────────────
            if (config.showHeader) ...[
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'PERFECT SOLUTION',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                          letterSpacing: 0.5,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'R E P A I R  ·  S A L E S  ·  S U P P O R T',
                        style: pw.TextStyle(
                          fontSize: 6,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'ESTIMATE',
                        style: pw.TextStyle(
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey600,
                          letterSpacing: 1.2,
                        ),
                      ),
                      pw.SizedBox(height: 1),
                      pw.Text(
                        '#${sale.invoiceNo}',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      'F-13, SKY PLAZA, SHRI RADHA SKY GARDEN, SECTOR 16B, GREATER NOIDA WEST',
                      style: const pw.TextStyle(
                        fontSize: 5.8,
                        color: PdfColors.grey700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Text(
                    '9810207643 · 9212117643',
                    style: const pw.TextStyle(
                      fontSize: 5.8,
                      color: PdfColors.grey700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 5),
              pw.Divider(thickness: 0.75, color: PdfColors.grey400),
              pw.SizedBox(height: 6),
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
                        letterSpacing: 0.4,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      sale.customerName?.trim().isNotEmpty == true
                          ? sale.customerName!
                          : 'Walk-in Customer',
                      style: pw.TextStyle(
                        fontSize: 9.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.black,
                      ),
                    ),
                    if (sale.customerNumber != null &&
                        sale.customerNumber!.trim().isNotEmpty) ...[
                      pw.SizedBox(height: 1),
                      pw.Text(
                        sale.customerNumber!.startsWith('+')
                            ? sale.customerNumber!
                            : '+91${sale.customerNumber}',
                        style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800),
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
                        letterSpacing: 0.4,
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
            pw.SizedBox(height: 8),

            // ── Table Header Bar (Soft Charcoal Header) ─────────────────────
            pw.Container(
              decoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF2D3748),
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
              ),
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    flex: 5,
                    child: pw.Text(
                      'DESCRIPTION OF GOODS',
                      style: pw.TextStyle(
                        fontSize: 6.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  pw.SizedBox(
                    width: 35,
                    child: pw.Text(
                      'QTY',
                      style: pw.TextStyle(
                        fontSize: 6.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                        letterSpacing: 0.5,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                  pw.SizedBox(
                    width: 65,
                    child: pw.Text(
                      'UNIT PRICE',
                      style: pw.TextStyle(
                        fontSize: 6.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                        letterSpacing: 0.5,
                      ),
                      textAlign: pw.TextAlign.right,
                    ),
                  ),
                  pw.SizedBox(
                    width: 65,
                    child: pw.Text(
                      'AMOUNT',
                      style: pw.TextStyle(
                        fontSize: 6.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                        letterSpacing: 0.5,
                      ),
                      textAlign: pw.TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),

            // ── Items Table Rows ─────────────────────────────────────────────
            ...displayItems.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              final desc = item.itemDescription?.trim() ?? 'Line Item';
              final notes = item.notes?.trim();
              final qty = item.quantity;
              final price = item.activePrice;
              final amt = item.totalAmount > 0 ? item.totalAmount : (qty * price);
              final isEven = idx % 2 == 0;

              // Parse primary title vs sub-details (e.g. Serial numbers, notes or newline)
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

              return pw.Container(
                decoration: pw.BoxDecoration(
                  color: isEven ? PdfColors.white : PdfColor.fromHex('#F8F9FA'),
                  border: const pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
                  ),
                ),
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Expanded(
                      flex: 5,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            primaryTitle,
                            style: pw.TextStyle(
                              fontSize: 7.5,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.black,
                            ),
                          ),
                          if (subDetails != null && subDetails.isNotEmpty) ...[
                            pw.SizedBox(height: 1),
                            pw.Text(
                              subDetails,
                              style: const pw.TextStyle(
                                fontSize: 6,
                                color: PdfColors.grey700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    pw.SizedBox(
                      width: 35,
                      child: pw.Text(
                        '$qty',
                        style: const pw.TextStyle(fontSize: 7.5),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                    pw.SizedBox(
                      width: 65,
                      child: pw.Text(
                        '₹ ${price.toStringAsFixed(2)}',
                        style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800),
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                    pw.SizedBox(
                      width: 65,
                      child: pw.Text(
                        '₹ ${amt.toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          fontSize: 7.5,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                  ],
                ),
              );
            }),

            // ── Totals Section ───────────────────────────────────────────────
            (() {
              final double itemsSubtotal = displayItems.fold(
                0.0,
                (sum, it) => sum + (it.totalAmount > 0 ? it.totalAmount : (it.quantity * it.activePrice)),
              );

              return pw.Column(
                children: [
                  pw.SizedBox(height: 8),
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        if (sale.discount > 0 || sale.advance > 0)
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(vertical: 1),
                            child: pw.Row(
                              mainAxisSize: pw.MainAxisSize.min,
                              children: [
                                pw.Text(
                                  'SUBTOTAL: ',
                                  style: pw.TextStyle(
                                    fontSize: 7.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.grey700,
                                  ),
                                ),
                                pw.Text(
                                  '₹ ${itemsSubtotal.toStringAsFixed(2)}',
                                  style: pw.TextStyle(
                                    fontSize: 8,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.grey900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (sale.discount > 0)
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(vertical: 1),
                            child: pw.Row(
                              mainAxisSize: pw.MainAxisSize.min,
                              children: [
                                pw.Text(
                                  'DISCOUNT: ',
                                  style: pw.TextStyle(
                                    fontSize: 7.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.grey600,
                                  ),
                                ),
                                pw.Text(
                                  '- ₹ ${sale.discount.toStringAsFixed(2)}',
                                  style: pw.TextStyle(
                                    fontSize: 8,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.red700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (sale.advance > 0)
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(vertical: 1),
                            child: pw.Row(
                              mainAxisSize: pw.MainAxisSize.min,
                              children: [
                                pw.Text(
                                  'ADVANCE PAID: ',
                                  style: pw.TextStyle(
                                    fontSize: 7.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.grey600,
                                  ),
                                ),
                                pw.Text(
                                  '- ₹ ${sale.advance.toStringAsFixed(2)}',
                                  style: pw.TextStyle(
                                    fontSize: 8,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.green700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 3, bottom: 2),
                          child: pw.Row(
                            mainAxisSize: pw.MainAxisSize.min,
                            children: [
                              pw.Text(
                                'GRAND TOTAL',
                                style: pw.TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.black,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              pw.SizedBox(width: 14),
                              pw.Text(
                                '₹ ${sale.totalAmount.toStringAsFixed(2)}',
                                style: pw.TextStyle(
                                  fontSize: 12.5,
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
                ],
              );
            })(),
            pw.SizedBox(height: 6),

            // ── Dynamic Payment & Review Row (Aligned horizontally on baseline) ─────
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Left: Google Review Card
                pw.Container(
                  width: 145,
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#F4F8FF'),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                    border: pw.Border.all(
                      color: PdfColor.fromHex('#D0E2FF'),
                      width: 0.6,
                    ),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      // Google Logo Styled Text
                      pw.Row(
                        mainAxisSize: pw.MainAxisSize.min,
                        children: [
                          pw.Text('G', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#4285F4'))),
                          pw.Text('o', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#EA4335'))),
                          pw.Text('o', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#FBBC05'))),
                          pw.Text('g', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#4285F4'))),
                          pw.Text('l', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#34A853'))),
                          pw.Text('e', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#EA4335'))),
                        ],
                      ),
                      pw.SizedBox(height: 3),
                      _buildQr(reviewUrl, 46),
                      pw.SizedBox(height: 3),
                      pw.Row(
                        mainAxisSize: pw.MainAxisSize.min,
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          _buildVectorStar(size: 6.5),
                          pw.SizedBox(width: 2.5),
                          pw.Text(
                            'Rate Us & Review',
                            style: pw.TextStyle(
                              fontSize: 6.5,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.black,
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 1),
                      pw.Text(
                        'Get a free Cleaner or Mouse Pad',
                        style: const pw.TextStyle(fontSize: 5, color: PdfColors.grey800),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.Text(
                        'completely free',
                        style: const pw.TextStyle(fontSize: 5, color: PdfColors.grey800),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.SizedBox(height: 1),
                      pw.Text(
                        'Scan to leave a review',
                        style: const pw.TextStyle(fontSize: 4.5, color: PdfColors.grey500),
                        textAlign: pw.TextAlign.center,
                      ),
                    ],
                  ),
                ),

                // Right: UPI Payment Card
                if (config.showQr)
                  pw.Container(
                    width: 145,
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        // Spacer to match Google logo height so QR codes are horizontally aligned
                        pw.SizedBox(height: 13),
                        _buildQr(upiUrl, 46),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Pay via UPI',
                          style: pw.TextStyle(
                            fontSize: 7,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.black,
                          ),
                        ),
                        pw.SizedBox(height: 1),
                        pw.Text(
                          'Scan with any UPI app',
                          style: const pw.TextStyle(fontSize: 5, color: PdfColors.grey700),
                          textAlign: pw.TextAlign.center,
                        ),
                        pw.Text(
                          'to pay instantly',
                          style: const pw.TextStyle(fontSize: 5, color: PdfColors.grey700),
                          textAlign: pw.TextAlign.center,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            pw.SizedBox(height: 6),

            // ── Terms & Conditions ───────────────────────────────────────────
            pw.Divider(thickness: 0.5, color: PdfColors.grey300),
            pw.SizedBox(height: 3),
            pw.Text(
              'T E R M S   &   C O N D I T I O N S',
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
                letterSpacing: 0.8,
              ),
            ),
            pw.SizedBox(height: 2.5),
            pw.Text(
              '1. Warranty for new products/parts is provided solely by the respective Principal Company / Brand Service Center as per their policy.',
              style: const pw.TextStyle(fontSize: 6.2, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 1.8),
            pw.Text(
              '2. Warranty stands VOID in case of Physical Damage, Liquid Damage, Electrical Burn / Short-Circuiting, or if the Serial Number / Warranty Sticker is missing, broken, or tampered with.',
              style: const pw.TextStyle(fontSize: 6.2, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 1.8),
            pw.Text(
              '3. Original bill is required for any warranty claims.',
              style: const pw.TextStyle(fontSize: 6.2, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 6),

            // ── Final Center Footer ──────────────────────────────────────────
            pw.Align(
              alignment: pw.Alignment.center,
              child: pw.Text(
                'Thank you for your business!',
                style: pw.TextStyle(
                  fontSize: 7.5,
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
  /// Generates the invoice PDF bytes on the calling isolate.
  /// The [pdf] package is pure Dart and completes in < 100 ms for a typical
  /// invoice, so no background isolate is needed. PDF generation is kicked off
  /// immediately when the preview dialog opens so the user sees a short
  /// loading spinner rather than any blocking delay.
  static Future<Uint8List> generatePdfBytes({
    required Sale sale,
    required List<SaleItem> items,
    required String? activeUpiId,
    InvoiceLayoutConfig config = const InvoiceLayoutConfig(),
  }) {
    return _buildPdf(sale, items, activeUpiId, config);
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

      // On Windows: launches default OS PDF application (Edge, Acrobat, SumatraPDF, Chrome)
      if (!kIsWeb && Platform.isWindows) {
        try {
          final res = await Process.run('cmd.exe', ['/c', 'start', '', file.path], runInShell: true);
          if (res.exitCode == 0) return true;
        } catch (_) {}

        try {
          final res = await Process.run('powershell', ['-c', 'Start-Process', '"${file.path}"']);
          if (res.exitCode == 0) return true;
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
