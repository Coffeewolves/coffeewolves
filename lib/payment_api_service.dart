import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const wolvesPaymentsApiUrl = String.fromEnvironment(
  'WOLVES_PAYMENTS_API_URL',
);

class PaymentApiException implements Exception {
  const PaymentApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PaymentOrder {
  const PaymentOrder({
    required this.id,
    required this.amount,
    required this.qrImageUrl,
    required this.status,
  });

  final String id;
  final double amount;
  final Uri qrImageUrl;
  final String status;

  factory PaymentOrder.fromJson(Map<String, dynamic> json) {
    final id = json['orderId'];
    final amount = json['amount'];
    final qr = json['qrImageUrl'];
    final status = json['status'];
    final qrUri = qr is String ? Uri.tryParse(qr) : null;
    final normalizedStatus = _normalizePaymentStatus(status);
    if (id is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,160}$').hasMatch(id) ||
        amount is! num ||
        !amount.toDouble().isFinite ||
        amount <= 0 ||
        qrUri == null ||
        qrUri.scheme != 'https' ||
        qrUri.host.isEmpty ||
        normalizedStatus == null) {
      throw const FormatException('Respuesta de orden de pago no válida.');
    }
    return PaymentOrder(
      id: id,
      amount: amount.toDouble(),
      qrImageUrl: qrUri,
      status: normalizedStatus,
    );
  }
}

class PaymentOrderStatus {
  const PaymentOrderStatus({
    required this.id,
    required this.amount,
    required this.status,
  });

  final String id;
  final double amount;
  final String status;

  factory PaymentOrderStatus.fromJson(
    Map<String, dynamic> json, {
    required String expectedOrderId,
  }) {
    final id = json['orderId'];
    final amount = json['amount'];
    final status = _normalizePaymentStatus(json['status']);
    if (id is! String ||
        id != expectedOrderId ||
        amount is! num ||
        !amount.toDouble().isFinite ||
        amount <= 0 ||
        status == null) {
      throw const FormatException(
        'La pasarela no devolvió un importe verificable para la orden.',
      );
    }
    return PaymentOrderStatus(
      id: id,
      amount: amount.toDouble(),
      status: status,
    );
  }
}

String? _normalizePaymentStatus(Object? value) {
  if (value is! String) return null;
  return switch (value.trim().toLowerCase()) {
    'pending' || 'pendiente' => 'pending',
    'paid' || 'success' || 'successful' || 'exitoso' || 'aprobado' => 'paid',
    'failed' || 'fallido' || 'rechazado' => 'failed',
    'expired' || 'expirado' || 'vencido' => 'expired',
    _ => null,
  };
}

class PaymentApiService {
  PaymentApiService({
    required FirebaseAuth auth,
    http.Client? client,
  })  : _auth = auth,
        _client = client ?? http.Client();

  final FirebaseAuth _auth;
  final http.Client _client;
  final String _configuredBaseUrl = wolvesPaymentsApiUrl;

  bool get hasConfiguredUrl => _configuredBaseUrl.trim().isNotEmpty;

  bool get isConfigured {
    final uri = Uri.tryParse(_configuredBaseUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      return false;
    }
    return uri.scheme == 'https' ||
        (kDebugMode && const {'localhost', '127.0.0.1'}.contains(uri.host));
  }

  Future<PaymentOrder> createOrder({
    required double total,
    required List<Map<String, dynamic>> items,
    required String idempotencyKey,
  }) async {
    final response = await _client
        .post(
          _endpoint('orders'),
          headers: await _headers(idempotencyKey: idempotencyKey),
          body: jsonEncode({
            'amount': total,
            'currency': 'BOB',
            'items': items,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw PaymentApiException(
        'El servidor no pudo crear la orden (HTTP ${response.statusCode}).',
      );
    }
    return PaymentOrder.fromJson(_decodeObject(response.body));
  }

  Future<String> getOrderStatus(String orderId) async {
    final response = await _client
        .get(
          _endpoint('orders/${Uri.encodeComponent(orderId)}'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw PaymentApiException(
        'No se pudo consultar el pago (HTTP ${response.statusCode}).',
      );
    }
    final json = _decodeObject(response.body);
    final status = _normalizePaymentStatus(json['status']);
    if (json['orderId'] != orderId || status == null) {
      throw const FormatException('Estado de pago no válido.');
    }
    return status;
  }

  Future<PaymentOrderStatus> getOrderPaymentStatus(String orderId) async {
    final response = await _client
        .get(
          _endpoint('orders/${Uri.encodeComponent(orderId)}'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw PaymentApiException(
        'No se pudo verificar el importe del pago (HTTP ${response.statusCode}).',
      );
    }
    final json = _decodeObject(response.body);
    return PaymentOrderStatus.fromJson(
      json,
      expectedOrderId: orderId,
    );
  }

  void close() => _client.close();

  Uri _endpoint(String path) {
    if (!isConfigured) {
      throw const PaymentApiException(
        'Configura WOLVES_PAYMENTS_API_URL con la URL HTTPS del backend.',
      );
    }
    final base = Uri.parse(_configuredBaseUrl);
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(path: '$basePath/$path');
  }

  Future<Map<String, String>> _headers({String? idempotencyKey}) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw const PaymentApiException(
        'Inicia sesión con tu cuenta Wolves Club para pagar.',
      );
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const PaymentApiException(
        'No se pudo autenticar la solicitud de pago.',
      );
    }
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
    };
  }

  Map<String, dynamic> _decodeObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Respuesta del backend no válida.');
    }
    return decoded;
  }
}
