import 'dart:async';

import 'package:flutter/material.dart';

import 'member_card_request_service.dart';
import 'payment_api_service.dart';

class MemberCardQrPaymentDialog extends StatefulWidget {
  const MemberCardQrPaymentDialog({
    required this.order,
    required this.requestId,
    required this.userUid,
    required this.paymentApi,
    required this.requestService,
    super.key,
  });

  final PaymentOrder order;
  final String requestId;
  final String userUid;
  final PaymentApiService paymentApi;
  final MemberCardRequestService requestService;

  @override
  State<MemberCardQrPaymentDialog> createState() =>
      _MemberCardQrPaymentDialogState();
}

class _MemberCardQrPaymentDialogState extends State<MemberCardQrPaymentDialog> {
  Timer? _pollTimer;
  bool _checking = false;
  bool _confirmed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.order.status == 'paid') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _confirmPayment();
      });
    } else {
      _pollTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => _checkPayment(),
      );
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkPayment() async {
    if (_checking || _confirmed || !mounted) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final status =
          await widget.paymentApi.getOrderStatus(widget.order.id);
      if (!mounted) return;
      if (status == 'paid') {
        await _confirmPayment();
      } else if (status == 'failed' || status == 'expired') {
        _pollTimer?.cancel();
        await widget.requestService.markQrPaymentFailed(
          requestId: widget.requestId,
          userUid: widget.userUid,
        );
        if (!mounted) return;
        setState(() {
          _error = status == 'failed'
              ? 'El proveedor rechazó el pago.'
              : 'El QR venció. Contacta a Gerencia para generar otra solicitud.';
        });
      }
    } catch (error, stackTrace) {
      debugPrint('No se pudo verificar el pago QR de Member Card: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _error = 'No se pudo consultar el pago. Seguiremos intentando.';
        });
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _confirmPayment() async {
    if (_confirmed || !mounted) return;
    try {
      await widget.requestService.reportQrPayment(
        requestId: widget.requestId,
        userUid: widget.userUid,
      );
      if (!mounted) return;
      _pollTimer?.cancel();
      setState(() {
        _confirmed = true;
        _checking = false;
        _error = null;
      });
    } catch (error, stackTrace) {
      debugPrint('No se pudo reportar el pago de Member Card: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _error =
              'El pago se confirmó, pero no se pudo actualizar la solicitud. '
              'Conserva el número de orden y contacta a Gerencia.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFC8A46A);
    const cream = Color(0xFFF0E7D7);
    const muted = Color(0xFFB5AAA0);
    return AlertDialog(
      backgroundColor: const Color(0xFF171717),
      title: const Text(
        'Paga tu Member Card',
        style: TextStyle(color: cream),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_confirmed)
              Image.network(
                widget.order.qrImageUrl.toString(),
                width: 220,
                height: 220,
                errorBuilder: (context, error, stackTrace) {
                  debugPrint('No se pudo cargar el QR de Member Card: $error');
                  return const SizedBox(
                    width: 220,
                    height: 220,
                    child: Center(
                      child: Text(
                        'No se pudo cargar el QR. Cierra y vuelve a intentarlo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: muted),
                      ),
                    ),
                  );
                },
              )
            else
              const Icon(Icons.check_circle_outline, color: gold, size: 72),
            const SizedBox(height: 16),
            Text(
              _confirmed
                  ? '¡Pago confirmado y solicitud enviada a Gerencia! Tu tarjeta será preparada y enviada al TPV para entrega en un plazo de 7 días.'
                  : 'Escanea para pagar Bs ${widget.order.amount.toStringAsFixed(2)}. Al confirmarse el pago, enviaremos la solicitud a Gerencia.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: cream, height: 1.45),
            ),
            const SizedBox(height: 8),
            Text(
              _confirmed
                  ? 'Orden ${widget.order.id}'
                  : _checking
                      ? 'Verificando el pago…'
                      : 'Verificamos el pago automáticamente.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 11),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFFFB4A9)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_confirmed && !_checking)
          TextButton(
            onPressed: _checkPayment,
            child: const Text('VERIFICAR AHORA'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, _confirmed),
          child: const Text('CERRAR'),
        ),
      ],
    );
  }
}
