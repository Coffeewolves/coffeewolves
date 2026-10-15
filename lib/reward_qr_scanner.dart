import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class RewardQrScanner extends StatefulWidget {
  const RewardQrScanner({
    required this.onScan,
    super.key,
  });

  final Future<void> Function(String value) onScan;

  @override
  State<RewardQrScanner> createState() => _RewardQrScannerState();
}

class _RewardQrScannerState extends State<RewardQrScanner> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _isProcessing = false;
  String? _error;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  Future<void> _handleDetection(BarcodeCapture capture) async {
    if (_isProcessing) return;
    String? value;
    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue?.trim();
      if (rawValue != null && rawValue.isNotEmpty) {
        value = rawValue;
        break;
      }
    }
    if (value == null) return;

    setState(() {
      _isProcessing = true;
      _error = null;
    });
    try {
      await _controller.stop();
      await widget.onScan(value);
      if (mounted) Navigator.of(context).pop();
    } catch (error, stackTrace) {
      debugPrint('No se pudo procesar el QR escaneado: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Bad state: ', '');
        _isProcessing = false;
      });
      await _controller.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF211E1A),
      title: const Text(
        'ESCANEAR QR',
        style: TextStyle(color: Color(0xFFC6A06A), fontSize: 15),
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enfoca el QR del beneficio emitido por el personal. '
              'Cada QR se puede canjear una sola vez.',
              style: TextStyle(color: Color(0xFFE8DDC7), fontSize: 12),
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
