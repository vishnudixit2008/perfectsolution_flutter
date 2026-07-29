import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr/qr.dart';
import 'package:intl/intl.dart';
import '../models/sale.dart';
import '../models/sale_item.dart';

// Top-level function required for compute() - cannot be a static method inside a class
Future<Uint8List> _buildInvoicePdf(Map<String, dynamic> args) async {
  final sale = args['sale'] as Sale;
  final items = args['items'] as List<SaleItem>;
  final activeUpiId = args['activeUpiId'] as String?;

  final formattedDate = DateFormat('dd/MM/yy hh:mm a').format(sale.saleDate);
  final String upiVpa = activeUpiId ?? '9810207643@upi';
  final String upiUrl =
      'upi://pay?pa=$upiVpa&am=${sale.totalAmount.toStringAsFixed(2)}&cu=INR&tn=Invoice%20${sale.invoiceNo}';

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

  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(16),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header
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
            // Billed To & Invoice
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
            // Items Table
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
                  final qty = item.quantity;
                  final price = item.activePrice;
                  final amt = item.totalAmount;
                  return pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(
                          desc,
                          style: const pw.TextStyle(fontSize: 8),
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
            // Footer
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
                        'Advance Received: Rs. ${sale.advance.toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey700,
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
                    pw.SizedBox(height: 4),
                    if (sale.paymentMode == 'UPI') ...[
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

class PdfInvoiceHelper {
  /// Generates the invoice PDF in a background isolate so the UI never freezes,
  /// then opens it natively.
  static Future<void> printInvoice({
    required Sale sale,
    required List<SaleItem> items,
    required String? activeUpiId,
  }) async {
    // Generate PDF bytes entirely in a background isolate - never blocks UI
    final pdfBytes = await compute(_buildInvoicePdf, {
      'sale': sale,
      'items': items,
      'activeUpiId': activeUpiId,
    });

    if (!kIsWeb && Platform.isMacOS) {
      // On macOS: save to temp file, open in Preview (avoids NSPrintPanel deadlock)
      try {
        final dir = Directory.systemTemp;
        final file = File('${dir.path}/Invoice_${sale.invoiceNo}.pdf');
        await file.writeAsBytes(pdfBytes);
        // 'open' launches the file in macOS Preview — user can Cmd+P from there
        await Process.run('/usr/bin/open', [file.path]);
        return;
      } catch (e) {
        if (kDebugMode) print('macOS PDF open error: $e');
      }
    }

    // On Android / other platforms: use native print dialog
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: 'Invoice_${sale.invoiceNo}.pdf',
    );
  }
}
