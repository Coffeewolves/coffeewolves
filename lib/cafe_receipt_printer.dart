import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class CafeReceiptLine {
  const CafeReceiptLine({
    required this.quantity,
    required this.description,
    required this.unitPrice,
    required this.amount,
  });

  final int quantity;
  final String description;
  final double unitPrice;
  final double amount;
}

class CafeReceiptPrinter {
  static Future<bool> printSaleReceipt({
    required String saleId,
    required String sellerName,
    required DateTime paidAt,
    required List<CafeReceiptLine> lines,
    required double total,
    required String paymentMethod,
    required double cashReceived,
    required double changeDue,
  }) async {
    final document = pw.Document();
    final date = '${paidAt.day.toString().padLeft(2, '0')}/'
        '${paidAt.month.toString().padLeft(2, '0')}/${paidAt.year}';
    final time = '${paidAt.hour.toString().padLeft(2, '0')}:'
        '${paidAt.minute.toString().padLeft(2, '0')}:'
        '${paidAt.second.toString().padLeft(2, '0')}';
    final paymentLabel = switch (paymentMethod) {
      'cash' => 'EFECTIVO',
      'qr' => 'QR',
      'card' => 'TARJETA',
      _ => paymentMethod.toUpperCase(),
    };
    final shortSaleId = saleId
        .substring(0, saleId.length < 8 ? saleId.length : 8)
        .toUpperCase();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        build: (context) => [
          pw.Center(
            child: pw.Text(
              'COFFEE WOLVES',
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Center(
            child: pw.Text(
              'COMPROBANTE DE PAGO',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Center(
            child: pw.Text(
              'No válido como factura tributaria',
              style: const pw.TextStyle(fontSize: 6),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text('VENDEDOR: $sellerName',
              style: const pw.TextStyle(fontSize: 8)),
          pw.Text(
            'FECHA: $date    HORA: $time',
            style: const pw.TextStyle(fontSize: 8),
          ),
          pw.Text(
            'VENTA: $shortSaleId',
            style: const pw.TextStyle(fontSize: 7),
          ),
          pw.Divider(),
          pw.Table(
            columnWidths: {
              0: const pw.FixedColumnWidth(24),
              1: const pw.FlexColumnWidth(),
              2: const pw.FixedColumnWidth(42),
              3: const pw.FixedColumnWidth(46),
            },
            children: [
              _tableRow(
                const ['UNID.', 'DESCRIPCION', 'PRECIO', 'IMPORTE'],
                bold: true,
              ),
              ...lines.map(
                (line) => _tableRow([
                  line.quantity.toString(),
                  line.description,
                  _money(line.unitPrice),
                  _money(line.amount),
                ]),
              ),
            ],
          ),
          pw.Divider(),
          _summaryRow('TOTAL A PAGAR:', _money(total), bold: true),
          _summaryRow('PAGO CON:',
              paymentLabel == 'EFECTIVO' ? _money(cashReceived) : paymentLabel),
          if (paymentLabel == 'EFECTIVO')
            _summaryRow('CAMBIO:', _money(changeDue)),
          pw.Divider(),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text(
              'LE ATENDIO ${sellerName.toUpperCase()}',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              '¡GRACIAS POR SU COMPRA!',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    return Printing.layoutPdf(
      name: 'Coffee-Wolves-$shortSaleId',
      format: PdfPageFormat.roll80,
      onLayout: (_) => document.save(),
    );
  }

  static pw.TableRow _tableRow(List<String> values, {bool bold = false}) {
    return pw.TableRow(
      children: values
          .asMap()
          .entries
          .map(
            (entry) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Text(
                entry.value,
                textAlign:
                    entry.key < 2 ? pw.TextAlign.left : pw.TextAlign.right,
                style: pw.TextStyle(
                  fontSize: 7,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  static pw.Widget _summaryRow(String label, String value,
      {bool bold = false}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ],
    );
  }

  static String _money(double amount) =>
      amount.toStringAsFixed(2).replaceAll('.', ',');
}
