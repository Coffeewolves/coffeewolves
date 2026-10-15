import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'cold_brew_qr_payload.dart';

class MemberCardPrintService {
  static const double widthMm = 85.5;
  static const double heightMm = 54;

  static Future<bool> printCard({
    required String memberName,
    required String memberId,
  }) async {
    final document = pw.Document();
    final pageFormat = PdfPageFormat(
      widthMm * PdfPageFormat.mm,
      heightMm * PdfPageFormat.mm,
      marginAll: 0,
    );
    final emblem = await _loadEmblem();

    document.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (_) => _front(memberName, memberId, emblem),
      ),
    );
    document.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (_) => _back(memberName, memberId),
      ),
    );

    return Printing.layoutPdf(
      name: 'Wolves-Member-Card-$memberId.pdf',
      format: pageFormat,
      onLayout: (_) => document.save(),
    );
  }

  static Future<pw.MemoryImage?> _loadEmblem() async {
    try {
      final data =
          await rootBundle.load('assets/images/coffee_wolves_logo.webp');
      final decoded = img.decodeImage(data.buffer.asUint8List());
      if (decoded == null) {
        throw const FormatException('No se pudo decodificar el emblema.');
      }
      return pw.MemoryImage(img.encodePng(decoded));
    } catch (error, stackTrace) {
      debugPrint(
          'No se pudo cargar el emblema para imprimir la tarjeta: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  static pw.Widget _front(
    String memberName,
    String memberId,
    pw.MemoryImage? emblem,
  ) {
    const cream = PdfColor(0.94, 0.90, 0.83);
    const silver = PdfColor(0.76, 0.78, 0.80);
    const gold = PdfColor(0.76, 0.59, 0.34);
    return pw.Container(
      color: const PdfColor(0.08, 0.08, 0.08),
      padding: const pw.EdgeInsets.all(5 * PdfPageFormat.mm),
      child: pw.Stack(
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                children: [
                  if (emblem != null)
                    pw.Image(emblem, width: 10 * PdfPageFormat.mm)
                  else
                    pw.Container(
                      width: 10 * PdfPageFormat.mm,
                      height: 10 * PdfPageFormat.mm,
                      decoration: pw.BoxDecoration(
                        shape: pw.BoxShape.circle,
                        border: pw.Border.all(color: silver, width: 0.7),
                      ),
                      child: pw.Center(
                        child: pw.Text(
                          'W',
                          style: pw.TextStyle(
                            color: silver,
                            fontSize: 17,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  pw.SizedBox(width: 2 * PdfPageFormat.mm),
                  pw.Text(
                    'COFFEE WOLVES',
                    style: pw.TextStyle(
                      color: cream,
                      fontSize: 10,
                      letterSpacing: 1.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Spacer(),
                  pw.Text(
                    'MEMBER',
                    style: pw.TextStyle(
                      color: gold,
                      fontSize: 7,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              pw.Spacer(),
              pw.Text(
                memberName.toUpperCase(),
                maxLines: 1,
                style: pw.TextStyle(
                  color: cream,
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              pw.SizedBox(height: 1 * PdfPageFormat.mm),
              pw.Row(
                children: [
                  pw.Text(
                    memberId,
                    style: pw.TextStyle(
                      color: silver,
                      fontSize: 8,
                      letterSpacing: 1,
                    ),
                  ),
                  pw.Spacer(),
                  pw.Text(
                    'WOLVES CLUB',
                    style: pw.TextStyle(
                      color: gold,
                      fontSize: 6,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _back(String memberName, String memberId) {
    const cream = PdfColor(0.94, 0.90, 0.83);
    const silver = PdfColor(0.76, 0.78, 0.80);
    final payload = membershipCardQrPayload(
      memberId: memberId,
      memberName: memberName,
    );
    return pw.Container(
      color: const PdfColor(0.08, 0.08, 0.08),
      padding: const pw.EdgeInsets.all(4 * PdfPageFormat.mm),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  'IDENTIFICACIÓN DE MIEMBRO',
                  style: pw.TextStyle(
                    color: silver,
                    fontSize: 6,
                    letterSpacing: 0.8,
                  ),
                ),
                pw.SizedBox(height: 3 * PdfPageFormat.mm),
                pw.Text(
                  memberName.toUpperCase(),
                  maxLines: 2,
                  style: pw.TextStyle(
                    color: cream,
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2 * PdfPageFormat.mm),
                pw.Text(
                  memberId,
                  style: pw.TextStyle(
                    color: silver,
                    fontSize: 7,
                    letterSpacing: 0.7,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 4 * PdfPageFormat.mm),
          pw.Container(
            color: PdfColors.white,
            padding: const pw.EdgeInsets.all(1.5 * PdfPageFormat.mm),
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: payload,
              width: 25 * PdfPageFormat.mm,
              height: 25 * PdfPageFormat.mm,
            ),
          ),
        ],
      ),
    );
  }
}
