import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';

import 'token_storage.dart';

class LocationSocketService {
  StompClient? _client;
  Future<void>? _connecting;

  bool get isConnected => _client?.connected ?? false;

  Future<void> connect() {
    _connecting ??= _open();
    return _connecting!.timeout(const Duration(seconds: 10));
  }

  Future<void> _open() async {
    final token = await TokenStorage().getToken();

    if (token == null) {
      _connecting = null;
      throw StateError('Not logged in');
    }

    final base = dotenv.env['API_BASE_URL'] ?? '';
    final wsBase = base.replaceFirst('http', 'ws');

    final connected = Completer<void>();

    _client = StompClient(
      config: StompConfig(
        url: '$wsBase/ws?token=$token',
        reconnectDelay: const Duration(seconds: 5),
        onConnect: (_) {
          if (!connected.isCompleted) {
            connected.complete();
          }
        },
        onWebSocketError: (e) {
          debugPrint('WS error: $e');
        },
        onStompError: (f) {
          debugPrint('STOMP error: ${f.body}');
        },
      ),
    );

    _client!.activate();

    return connected.future;
  }

  void sendLocation({
    required double latitude,
    required double longitude,
    double? heading,
  }) {
    if (!isConnected) return;

    _client!.send(
      destination: '/app/location.update',
      body: jsonEncode({
        'latitude': latitude,
        'longitude': longitude,
        'heading': (heading != null && heading.isFinite) ? heading : null,
      }),
    );
  }

  void disconnect() {
    _client?.deactivate();
    _client = null;
    _connecting = null;
  }
}