import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';

import '../services/auth_service.dart';
import 'token_storage.dart';

class RealtimeService {
  final AuthService _auth;

  StompClient? _client;
  bool _opening = false;

  // destination -> the stream of messages for that topic
  final Map<String, StreamController<Map<String, dynamic>>> _topics = {};

  // destination -> the function that cancels its current subscription
  final Map<String, dynamic> _active = {};

  // Fires on every successful connection or reconnection.
  final StreamController<void> _connected =
  StreamController<void>.broadcast();

  Stream<void> get onConnected => _connected.stream;

  bool get isConnected => _client?.connected ?? false;

  RealtimeService(this._auth) {
    _auth.addListener(_syncWithAuth);
    _syncWithAuth();
  }

  void _syncWithAuth() {
    if (_auth.isLoggedIn) {
      if (_client == null) _open();
    } else {
      _close();
    }
  }

  Future<void> _open() async {
    if (_opening || _client != null) return;

    _opening = true;
    try {
      final token = await TokenStorage().getToken();

      // The user may have logged out while we awaited.
      if (token == null || !_auth.isLoggedIn) return;

      final base = dotenv.env['API_BASE_URL'] ?? '';
      final wsBase = base.replaceFirst('http', 'ws');

      _client = StompClient(
        config: StompConfig(
          url: '$wsBase/ws?token=$token',
          reconnectDelay: const Duration(seconds: 5),
          onConnect: _onConnect,
          onDisconnect: (_) => debugPrint('STOMP disconnected'),
          onWebSocketError: (e) => debugPrint('WS error: $e'),
          onStompError: (f) => debugPrint('STOMP error: ${f.body}'),
        ),
      );

      _client!.activate();
    } finally {
      _opening = false;
    }
  }

  void _onConnect(StompFrame frame) {
    // Re-create subscriptions after reconnecting.
    for (final unsubscribe in _active.values) {
      try {
        unsubscribe();
      } catch (_) {
        // The old connection may already be closed.
      }
    }
    _active.clear();

    for (final destination in _topics.keys) {
      _subscribe(destination);
    }

    // Screens can re-fetch REST data after reconnecting.
    _connected.add(null);
  }

  void _subscribe(String destination) {
    final client = _client;
    final controller = _topics[destination];

    if (client == null || !client.connected || controller == null) return;

    _active[destination] = client.subscribe(
      destination: destination,
      callback: (frame) {
        final body = frame.body;
        if (body == null) return;

        try {
          final decoded = jsonDecode(body);
          if (decoded is Map<String, dynamic>) {
            controller.add(decoded);
          }
        } catch (e) {
          debugPrint('Bad message on $destination: $e');
        }
      },
    );
  }

  /// Safe to call before the socket connects.
  /// The subscription attaches when the connection is ready.
  Stream<Map<String, dynamic>> topic(String destination) {
    final controller = _topics.putIfAbsent(
      destination,
          () => StreamController<Map<String, dynamic>>.broadcast(),
    );

    if (isConnected && !_active.containsKey(destination)) {
      _subscribe(destination);
    }

    return controller.stream;
  }

  void sendLocation({
    required double latitude,
    required double longitude,
    double? heading,
  }) {
    final client = _client;
    if (client == null || !client.connected) return;

    client.send(
      destination: '/app/location.update',
      body: jsonEncode({
        'latitude': latitude,
        'longitude': longitude,
        'heading': (heading != null && heading.isFinite) ? heading : null,
      }),
    );
  }

  void _close() {
    _client?.deactivate();
    _client = null;
    _active.clear();
  }

  void dispose() {
    _auth.removeListener(_syncWithAuth);
    _close();

    for (final controller in _topics.values) {
      controller.close();
    }

    _connected.close();
  }
}