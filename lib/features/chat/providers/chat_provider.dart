import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:loqui/core/api/endpoints.dart';
import 'package:loqui/core/auth/auth_service.dart';
import 'package:loqui/core/gateway/gateway_client.dart';
import 'package:loqui/core/gateway/gateway_events.dart';
import 'package:loqui/core/gateway/gateway_providers.dart';
import 'package:loqui/shared/models/models.dart';

// immutable chat state: loaded messages (oldest-first) plus pagination flags
class ChatState {
  const ChatState({
    required this.messages,
    required this.hasMore,
    this.loadingOlder = false,
    this.pending = const [],
  });

  final List<Message> messages;
  final bool hasMore;
  final bool loadingOlder;
  final List<Message> pending; //newer msgs held back while scrolled up

  ChatState copyWith({
    List<Message>? messages,
    bool? hasMore,
    bool? loadingOlder,
    List<Message>? pending,
  }) => ChatState(
    messages: messages ?? this.messages,
    hasMore: hasMore ?? this.hasMore,
    loadingOlder: loadingOlder ?? this.loadingOlder,
    pending: pending ?? this.pending,
  );
}

// messages for one channel: latest page from REST, older pages on demand,
// plus live gateway events merged in an deduped by id. oldest-first
final channelMessagesProvider = AsyncNotifierProvider.autoDispose
    .family<ChannelMessagesController, ChatState, String>(
      ChannelMessagesController.new,
    );

class ChannelMessagesController extends AsyncNotifier<ChatState> {
  ChannelMessagesController(this.channelId);
  final String channelId;

  static const _pageSize = 50;
  bool _disposed = false;
  bool _atBottom = true; //view is pinned to newest
  bool _everConnected = false;
  bool _sawDisconnect = false;
  bool _catchingUp = false;

  @override
  Future<ChatState> build() async {
    _disposed = false;
    _sawDisconnect = false;
    _catchingUp = false;
    _everConnected =
        ref.read(gatewayStatusProvider).value == GatewayStatus.connected;
    final api = ref.watch(apiClientProvider);
    final gateway = ref.watch(gatewayClientProvider);

    //priortize this channel and make sure its subed
    gateway.openChannel(channelId);

    final sub = gateway.events.listen((event) {
      switch (event) {
        case MessageCreateEvent() when event.message.channelId == channelId:
          _append(event.message);
        case MessageUpdateEvent() when event.message.channelId == channelId:
          _replace(event.message);
        case MessageDeleteEvent() when event.channelId == channelId:
          _remove(event.id);
        default:
          break;
      }
    });
    ref.onDispose(() {
      _disposed = true;
      sub.cancel();
    });

    //catch up on messages missed while socket was down
    ref.listen(gatewayStatusProvider, (_, next) {
      final s = next.value;
      if (s == null) return;
      if (s != GatewayStatus.connected) {
        if (_everConnected) _sawDisconnect = true;
        return;
      }
      if (_sawDisconnect) {
        _sawDisconnect = false;
        _catchUp();
      }
      _everConnected = true;
    });

    final data =
        await api.get(
              Endpoints.channelMessages(channelId),
              query: {'limit': '$_pageSize'},
            )
            as List<dynamic>;

    final messages =
        data.map((e) => Message.fromJson(e as Map<String, dynamic>)).toList()
          ..sort(_byId);

    return ChatState(messages: messages, hasMore: data.length == _pageSize);
  }

  Future<void> send(String content) async {
    final api = ref.read(apiClientProvider);
    //wait for gateway echo before appending
    await api.post(Endpoints.channelMessages(channelId), {'content': content});
  }

  //edit + delete land back via gateway echo, like send
  Future<void> edit(String messageId, String content) async {
    final api = ref.read(apiClientProvider);
    await api.patch(Endpoints.channelMessage(channelId, messageId), {
      'content': content,
    });
  }

  Future<void> delete(String messageId) async {
    final api = ref.read(apiClientProvider);
    await api.delete(Endpoints.channelMessage(channelId, messageId));
  }

  // fetch one older page before oldest loaded message
  Future<void> loadOlder() async {
    final s = state.value;
    if (s == null || !s.hasMore || s.loadingOlder || s.messages.isEmpty) return;
    state = AsyncData(s.copyWith(loadingOlder: true));

    final api = ref.read(apiClientProvider);
    try {
      final data =
          await api.get(
                Endpoints.channelMessages(channelId),
                query: {'limit': '$_pageSize', 'before': s.messages.first.id},
              )
              as List<dynamic>;
      if (_disposed) return;

      final fetched = data
          .map((e) => Message.fromJson(e as Map<String, dynamic>))
          .toList();
      final existing = {for (final m in s.messages) m.id};
      final merged = [
        ...fetched.where((m) => !existing.contains(m.id)),
        ...s.messages,
      ]..sort(_byId);

      state = AsyncData(
        ChatState(
          messages: merged,
          hasMore: data.length == _pageSize,
          loadingOlder: false,
        ),
      );
    } catch (_) {
      //keep hasMore so a later scroll can retry
      if (_disposed) return;
      final cur = state.value;
      if (cur != null) state = AsyncData(cur.copyWith(loadingOlder: false));
    }
  }

  // view cllas this a it crossed bottom threshold, flush on arrival
  void setAtBottom(bool value) {
    _atBottom = value;
    if (value) _flushPending();
  }

  void _flushPending() {
    final s = state.value;
    if (s == null || s.pending.isEmpty) return;
    final existing = {for (final m in s.messages) m.id};
    final merged = [
      ...s.messages,
      ...s.pending.where((m) => !existing.contains(m.id)),
    ]..sort(_byId);
    state = AsyncData(s.copyWith(messages: merged, pending: []));
  }

  void _append(Message m) => _ingestNewer([m]);

  void _replace(Message m) {
    final s = state.value;
    if (s == null) return;
    final inMsgs = s.messages.any((x) => x.id == m.id);
    final inPend = s.pending.any((x) => x.id == m.id);
    if (!inMsgs && !inPend) return;
    state = AsyncData(
      s.copyWith(
        messages: inMsgs
            ? [for (final x in s.messages) x.id == m.id ? m : x]
            : null,
        pending: inPend
            ? [for (final x in s.pending) x.id == m.id ? m : x]
            : null,
      ),
    );
  }

  void _remove(String id) {
    final s = state.value;
    if (s == null) return;
    final inMsgs = s.messages.any((x) => x.id == id);
    final inPend = s.pending.any((x) => x.id == id);
    if (!inMsgs && !inPend) return;
    state = AsyncData(
      s.copyWith(
        messages: inMsgs
            ? [
                for (final x in s.messages)
                  if (x.id != id) x,
              ]
            : null,
        pending: inPend
            ? [
                for (final x in s.pending)
                  if (x.id != id) x,
              ]
            : null,
      ),
    );
  }

  // route newer messages to view if pinned, else hold as pending
  void _ingestNewer(Iterable<Message> incoming) {
    final s = state.value;
    if (s == null) return;
    final known = {
      for (final m in s.messages) m.id,
      for (final m in s.pending) m.id,
    };
    final fresh = [
      for (final m in incoming)
        if (!known.contains(m.id)) m,
    ];
    if (fresh.isEmpty) return;
    if (_atBottom) {
      state = AsyncData(
        s.copyWith(messages: [...s.messages, ...fresh]..sort(_byId)),
      );
    } else {
      state = AsyncData(
        s.copyWith(pending: [...s.pending, ...fresh]..sort(_byId)),
      );
    }
  }

  String? _newestId(ChatState s) {
    final ids = [
      if (s.messages.isNotEmpty) s.messages.last.id,
      if (s.pending.isNotEmpty) s.pending.last.id,
    ];
    if (ids.isEmpty) return null;
    ids.sort((a, b) => BigInt.parse(a).compareTo(BigInt.parse(b)));
    return ids.last;
  }

  // pages forward from newest loaded id until it reaches present
  Future<void> _catchUp() async {
    if (_catchingUp) return;
    final start = state.value;
    if (start == null) return;
    final newest = _newestId(start);
    if (newest == null) return; //nothing loaded, initial fetch covers it
    var cursor = newest;
    _catchingUp = true;

    final api = ref.read(apiClientProvider);
    try {
      while (true) {
        final data =
            await api.get(
                  Endpoints.channelMessages(channelId),
                  query: {'limit': '$_pageSize', 'after': cursor},
                )
                as List<dynamic>;
        if (_disposed) return;
        if (data.isEmpty) break;

        final batch =
            data
                .map((e) => Message.fromJson(e as Map<String, dynamic>))
                .toList()
              ..sort(_byId);
        _ingestNewer(batch);
        cursor = batch.last.id; //newest so far, strictly advances
        if (data.length < _pageSize) break;
      }
    } catch (_) {
      //may retry on reconnect or reload
    } finally {
      _catchingUp = false;
    }
  }

  //compare as bigInt
  static int _byId(Message a, Message b) =>
      BigInt.parse(a.id).compareTo(BigInt.parse(b.id));
}

//exposes connections status for a small banner
final gatewayStatusProvider = StreamProvider<GatewayStatus>((ref) {
  return ref.watch(gatewayClientProvider).status;
});
