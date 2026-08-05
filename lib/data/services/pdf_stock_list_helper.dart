import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/pricelist_item.dart';

class PdfStockListHelper {
  /// Clean text from invalid non-ASCII / corrupt characters like `\uFFFD` or `\u0000`
  /// and normalize double quotes so PDF rendering font does not show missing character boxes `[?]`
  static String _cleanText(String input) {
    return input
        .replaceAll('"', '"')
        .replaceAll('"', '"')
        .replaceAll('”', '"')
        .replaceAll('“', '"')
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll(RegExp(r'[^\x00-\x7F]'), '') // Remove non-ASCII characters that cause font glyph missing boxes
        .trim();
  }

  /// Generates a Stock List PDF matching the compact category-grouped template design.
  static Future<Uint8List> generateStockListPdfBytes(
      List<PricelistItem> items) async {
    final pdf = pw.Document(compress: true);

    final nowStr = DateFormat('dd-MM-yyyy hh:mm:ss a').format(DateTime.now()).toLowerCase();

    // 1. Filter out items with quantity <= 0 (only keep stockQty > 0)
    final positiveStockItems = items.where((i) => i.stockQty > 0).toList();

    // 2. Group items by Category or Category / Brand Prefix
    final Map<String, List<PricelistItem>> grouped = {};
    for (final item in positiveStockItems) {
      String cat = (item.category ?? '').trim();
      if (cat.isEmpty) {
        final parts = item.itemName.trim().split(' ');
        cat = parts.isNotEmpty ? parts.first.toUpperCase() : 'GENERAL';
      } else {
        cat = cat.toUpperCase();
      }
      cat = _cleanText(cat);
      grouped.putIfAbsent(cat, () => []).add(item);
    }

    // Sort categories alphabetically
    final sortedCategories = grouped.keys.toList()..sort();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        header: (pw.Context context) {
          // Show date/time stamp ONLY on page 1
          if (context.pageNumber == 1) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  nowStr,
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.black,
                  ),
                ),
                pw.SizedBox(height: 4),
              ],
            );
          }
          return pw.SizedBox.shrink();
        },
        footer: (pw.Context context) {
          // Compact page number on every page at bottom right
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 4),
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey700,
              ),
            ),
          );
        },
        build: (pw.Context context) {
          final List<pw.TableRow> tableRows = [];

          for (final cat in sortedCategories) {
            final catItems = grouped[cat]!;
            final int catTotalQty =
                catItems.fold(0, (sum, item) => sum + item.stockQty);

            // Group Header Row (Bold category name, total pcs, solid black top/bottom border)
            tableRows.add(
              pw.TableRow(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    top: pw.BorderSide(color: PdfColors.black, width: 1.2),
                    bottom: pw.BorderSide(color: PdfColors.black, width: 1.2),
                  ),
                ),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                        vertical: 3, horizontal: 4),
                    child: pw.Text(
                      cat,
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                        vertical: 3, horizontal: 4),
                    child: pw.Text(
                      '$catTotalQty pcs',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                      textAlign: pw.TextAlign.left,
                    ),
                  ),
                ],
              ),
            );

            // Individual Product Rows
            for (final item in catItems) {
              final cleanedName = _cleanText(item.itemName);
              tableRows.add(
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(color: PdfColors.black, width: 0.5),
                    ),
                  ),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          vertical: 2.5, horizontal: 4),
                      child: pw.Text(
                        cleanedName,
                        style: const pw.TextStyle(
                          fontSize: 8.5,
                          color: PdfColors.black,
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          vertical: 2.5, horizontal: 4),
                      child: pw.Text(
                        '${item.stockQty} pcs',
                        style: const pw.TextStyle(
                          fontSize: 8.5,
                          color: PdfColors.black,
                        ),
                        textAlign: pw.TextAlign.left,
                      ),
                    ),
                  ],
                ),
              );
            }
          }

          return [
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.black, width: 0.8),
              columnWidths: const {
                0: pw.FlexColumnWidth(4.5),
                1: pw.FlexColumnWidth(1.2),
              },
              children: tableRows,
            ),
          ];
        },
      ),
    );

    return await pdf.save();
  }

  /// Generates and opens Stock List PDF in system default viewer.
  static Future<bool> generateAndOpenStockListPdf(
      List<PricelistItem> items) async {
    try {
      final pdfBytes = await generateStockListPdfBytes(items);
      final dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final fileName = 'Stock_List_$dateStr.pdf';

      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pdfBytes, flush: true);

      // On macOS
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

      // On Windows
      if (!kIsWeb && Platform.isWindows) {
        try {
          final res = await Process.run(
              'cmd.exe', ['/c', 'start', '', file.path],
              runInShell: true);
          if (res.exitCode == 0) return true;
        } catch (_) {}
        try {
          final res = await Process.run(
              'powershell', ['-c', 'Start-Process', '"${file.path}"']);
          if (res.exitCode == 0) return true;
        } catch (_) {}
      }

      // Fallback
      final uri = Uri.file(file.path);
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }

      return false;
    } catch (e) {
      if (kDebugMode) print('generateAndOpenStockListPdf error: $e');
      return false;
    }
  }
}
