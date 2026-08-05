import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr/qr.dart';
import 'package:intl/intl.dart';
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

  const InvoiceLayoutConfig({
    this.pageSize = 'A5',
    this.marginTB = 10.0,
    this.marginLR = 10.0,
    this.showHeader = true,
    this.showQr = true,
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

  final formattedDate = DateFormat('dd/MM/yy hh:mm a').format(sale.saleDate);
  final String upiVpa = activeUpiId ?? '9810207643@upi';
  final String upiUrl =
      'upi://pay?pa=$upiVpa&am=${sale.dueAmount.toStringAsFixed(2)}&cu=INR&tn=Invoice%20${sale.invoiceNo}';

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
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // ── Shop Header ──────────────────────────────────────────────────
            if (config.showHeader) ...[
              pw.Align(
                alignment: pw.Alignment.center,
                child: pw.Column(
                  children: [
                    pw.Text(
                      'ESTIMATE',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'PERFECT SOLUTION',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'F-13, Sky Plaza, Sky Garden, Sector 16B, Greater Noida West',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                    pw.SizedBox(height: 1),
                    pw.Text(
                      'Phone - 9810207643 | 9212117643',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 0.5, color: PdfColors.grey400),
              pw.SizedBox(height: 4),
            ],

            // ── Billed-To & Invoice Meta ─────────────────────────────────────
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
                        fontSize: 7,
                        color: PdfColors.grey600,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 1),
                    pw.Text(
                      sale.customerName ?? 'Cash',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (sale.customerNumber != null &&
                        sale.customerNumber!.isNotEmpty) ...[
                      pw.SizedBox(height: 1),
                      pw.Text(
                        'Mob: ${sale.customerNumber}',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Invoice No. : ${sale.invoiceNo}',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 1),
                    pw.Text(
                      'Date & Time: $formattedDate',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),

            // ── Items Table ──────────────────────────────────────────────────
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(4),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(1.5),
                3: const pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text(
                        'Description of Goods',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text(
                        'Qty',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text(
                        'Unit Price',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text(
                        'Amount',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                  ],
                ),
                ...displayItems.map((item) {
                  final desc = item.itemDescription ?? 'Line Item';
                  final notes = item.notes?.trim();
                  final qty = item.quantity;
                  final price = item.activePrice;
                  final amt = item.totalAmount;
                  return pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          mainAxisSize: pw.MainAxisSize.min,
                          children: [
                            pw.Text(
                              desc,
                              style: pw.TextStyle(
                                fontSize: 8,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            if (notes != null && notes.isNotEmpty) ...[
                              pw.SizedBox(height: 1),
                              pw.Text(
                                notes,
                                style: const pw.TextStyle(
                                  fontSize: 6.5,
                                  color: PdfColors.grey700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(
                          '$qty',
                          style: const pw.TextStyle(fontSize: 8),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(
                          'Rs. ${price.toStringAsFixed(2)}',
                          style: const pw.TextStyle(fontSize: 8),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(
                          'Rs. ${amt.toStringAsFixed(2)}',
                          style: const pw.TextStyle(fontSize: 8),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 24),

            // ── Footer ───────────────────────────────────────────────────────
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    _buildQr('https://g.page/r/CaqZxhuvkW-7EBM/review', 48),
                    pw.SizedBox(width: 8),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Please rate us on google & get a',
                          style: pw.TextStyle(
                            fontSize: 6,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          'free CLEANER or MOUSE PAD',
                          style: pw.TextStyle(
                            fontSize: 6,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          'for completely free.',
                          style: pw.TextStyle(
                            fontSize: 6,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 12),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    if (sale.discount > 0)
                      pw.Text(
                        'Discount Applied: Rs. ${sale.discount.toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    if (sale.advance > 0) ...[
                      pw.SizedBox(height: 1),
                      pw.Text(
                        'Advance Paid: Rs. ${sale.advance.toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'GRAND TOTAL: Rs. ${sale.totalAmount.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (config.showQr) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Scan to Pay via UPI:',
                        style: pw.TextStyle(
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      _buildQr(upiUrl, 48),
                    ],
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 0.5, color: PdfColors.grey400),
            pw.SizedBox(height: 2),
            pw.Align(
              alignment: pw.Alignment.center,
              child: pw.Text(
                'Thank you for your business!',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
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

      // Universal fallback (url_launcher)
      try {
        final uri = Uri.file(file.path);
        if (await canLaunchUrl(uri)) {
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
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
