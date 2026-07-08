import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import 'package:loqui/core/api/endpoints.dart';
import 'package:loqui/core/gateway/gateway_events.dart';

enum GatewayStatus { disconnected, connecting, connected, reconnecting }

const _subprotocol = 'loqui.v1';

/// Owns a single WS connection for session. Reconnects with jittered
/// exponential backoff and restores every sub after reconnect
class GatewayClient {
  GatewayClient({required this.gatewayUrl});

  final String gatewayUrl;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Future<String?> Function()? _tokenProvider;

  bool _wantConnected = false;
  int _attempt = 0;
  Timer? _reconnectTimer;
  final _rng = Random();

  final _desired = <String>[]; // recency order, front = most recent
  final _confirmed = <String>{}; // subed on current connection

  final _events = StreamController<GatewayEvent>.broadcast();
  final _status = StreamController<GatewayStatus>.broadcast();

  Stream<GatewayEvent> get events => _events.stream;
  Stream<GatewayStatus> get status => _status.stream;
  bool get _connected => _channel != null;

  // ==== lifecycle ====

  void connect(Future<String?> Function() tokenProvider) {
    _tokenProvider = tokenProvider;
    _wantConnected = true;
    _attempt = 0;
    _open();
  }

  void disconnect() {
    _wantConnected = false;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close(ws_status.normalClosure);
    _channel = null;
    _confirmed.clear();
    _desired.clear();
    _status.add(GatewayStatus.disconnected);
  }

  Future<void> _open() async {
    if (!_wantConnected) return;
    final token = await _tokenProvider?.call();
    if (token == null) {
      _scheduleReconnect();
      return;
    }

    _status.add(GatewayStatus.connecting);
    final uri = Uri.parse('$gatewayUrl${Endpoints.gateway}');
    final ch = WebSocketChannel.connect(
      uri,
      protocols: [_subprotocol, 'access_token.$token'],
    );
    _channel = ch;
    _sub = ch.stream.listen(
      _onData,
      onError: (_) => _onClosed(),
      onDone: _onClosed,
    );

    try {
      await ch.ready;
    } catch (_) {
      return;
      // _onClosed via stream will schedule retry
    }
    _onConnected();
  }

  void _onConnected() {
    _attempt = 0;
    _status.add(GatewayStatus.connected);
    _resubscribeAll();
  }

  void _onClosed() {
    _sub?.cancel();
    _sub = null;
    _channel = null;
    _confirmed.clear();
    if (_wantConnected) {
      _status.add(GatewayStatus.reconnecting);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!_wantConnected) return;
    _reconnectTimer?.cancel();
    _attempt++;
    _reconnectTimer = Timer(_backoff(_attempt), _open);
  }

  // full jitter: uniform(0, cap) where cao grows 1s, 2s, 4s...to 30s
  Duration _backoff(int attempt) {
    final exp = 1000 * (1 << (attempt - 1).clamp(0, 20));
    final cap = min(30000, exp);
    return Duration(milliseconds: max(250, _rng.nextInt(cap + 1)));
  }

  // ===== subscriptions ====

  // openChannel makes a channel the highest priority and ensures it is
  // subed. Called when user opens a chat
  void openChannel(String channelId) {
    _desired.remove(channelId);
    _desired.insert(0, channelId);
    if (_connected && !_confirmed.contains(channelId)) {
      _sendSubscribe(channelId);
    }
  }

  // registerChannels adds known channels as lower priority, subing any
  // that are not yet covered (staggered to avoid burst)
  void registerChannels(List<String> ids) {
    for (final id in ids) {
      if (!_desired.contains(id)) _desired.add(id);
    }
    if (_connected) _subscribePending();
  }

  void _resubscribeAll() {
    _confirmed.clear();
    _subscribePending();
  }

  // stager subs to avoid startup burst
  void _subscribePending() {
    var i = 0;
    for (final id in List<String>.from(_desired)) {
      if (_confirmed.contains(id)) continue;
      if (i == 0) {
        _sendSubscribe(id);
      } else {
        final delay = Duration(milliseconds: 60 * i);
        Timer(delay, () {
          if (_connected && _desired.contains(id) && !_confirmed.contains(id)) {
            _sendSubscribe(id);
          }
        });
      }
      i++;
    }
  }

  void _sendSubscribe(String channelId) {
    _confirmed.add(channelId); //optimistic, subed ack confirms it
    _send({'op': 'subscribe', 'channel_id': channelId});
  }

  void _send(Map<String, dynamic> msg) => _channel?.sink.add(jsonEncode(msg));

  // ==== inbound ====

  void _onData(dynamic data) {
    if (data is! String) return;
    final event = GatewayEvent.tryParse(data);
    if (event == null) return;
    if (event is SubscribedEvent) _confirmed.add(event.channelId);
    _events.add(event);
  }

  void dipose() {
    disconnect();
    _events.close();
    _status.close();
  }
}
