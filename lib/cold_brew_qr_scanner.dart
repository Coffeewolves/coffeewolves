import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ColdBrewQrScanner extends StatefulWidget {
  const ColdBrewQrScanner({
    required this.resolveCustomer,
    required this.resolveFigure,
    required this.redeem,
    super.key,
  });

  final Future<String> Function(String qrValue) resolveCustomer;
  final String Function(String qrValue) resolveFigure;
  final Future<void> Function(String customerUid, String figureId) redeem;

  @override
  State<ColdBrewQrScanner> createState() => _ColdBrewQrScannerState();
}

class _ColdBrewQrScannerState extends State<ColdBrewQrScanner> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  String? _customerUid;
  String? _error;
  bool _isProcessing = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  Future<void> _handleDetection(BarcodeCapture capture) async {
    if (_isProcessing) return;
    String? qrValue;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value != null && value.isNotEmpty) {
        qrValue = value;
        break;
      }
    }
    if (qrValue == null) return;

    setState(() {
      _isProcessing = true;
      _error = null;
    });
    try {
      await _controller.stop();
      final customerUid = _customerUid;
      if (customerUid == null) {
        final resolvedUid = await widget.resolveCustomer(qrValue);
        if (!mounted) return;
        setState(() => _customerUid = resolvedUid);
        await _controller.start();
      } else {
        final figureId = widget.resolveFigure(qrValue);
        await widget.redeem(customerUid, figureId);
        if (mounted) Navigator.of(context).pop();
      }
    } catch (error, stackTrace) {
      debugPrint('No se pudo procesar el QR de canje: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _error = error.toString());
      await _controller.start();
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customerScanned = _customerUid != null;
    return AlertDialog(
      backgroundColor: const Color(0xFF211E1A),
      title: Text(
        customerScanned
            ? '2 de 2 · ESCANEA EL PREMIO'
            : '1 de 2 · ESCANEA AL USUARIO',
        style: const TextStyle(color: Color(0xFFC6A06A), fontSize: 15),
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              customerScanned
                  ? 'Usuario identificado. Ahora escanea el QR de premio emitido por el personal.'
                  : 'Enfoca el QR Wolves Member Card del usuario.',
              style: const TextStyle(color: Color(0xFFE8DDC7), fontSize: 12),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 300,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: MobileScanner(
                  controller: _controller,
                  onDetect: _handleDetection,
                  errorBuilder: (context, error, child) => ColoredBox(
                    color: const Color(0xFF151311),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No se pudo iniciar la cámara (${error.errorCode.name}). '
                          'Permite el acceso a la cámara y vuelve a intentarlo.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFE8DDC7),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_isProcessing) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(color: Color(0xFFC6A06A)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFE6A296), fontSize: 11),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCELAR'),
        ),
      ],
    );
  }
}
