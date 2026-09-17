import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Test Google Fonts for F-13', () async {
    final pdf = pw.Document();
    final comfortaa = await PdfGoogleFonts.comfortaaBold();
    final lora = await PdfGoogleFonts.loraBold();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        build: (context) {
          return pw.Row(
            children: [
              pw.Text('F-', style: pw.TextStyle(font: comfortaa, fontSize: 32)),
              pw.Text('13', style: pw.TextStyle(font: lora, fontSize: 34)),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    print('SUCCESS: generated  bytes');
  });
}
