import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:loqui/core/api/endpoints.dart';
import 'package:loqui/core/auth/auth_service.dart';
import 'package:loqui/core/gateway/gateway_client.dart';
import 'package:loqui/core/gateway/gateway_events.dart';
import 'package:loqui/core/gateway/gateway_providers.dart';
import 'package:loqui/shared/models/models.dart';

// messages for one channel: latest page from REST, plus live gateway
// events merged in an deduped by id. ordered oldest-first
final channelMessagesProvider = AsyncNotifierProvider.autoDispose
    .family<ChannelMessagesController, List<Message>, String>(
      ChannelMessagesController.new,
    );

class ChannelMessagesController extends AsyncNotifier<List<Message>> {
  ChannelMessagesController(this.channelId);
  final String channelId;

  @override
  Future<List<Message>> build() async {
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
    ref.onDispose(sub.cancel);

    final data =
        await api.get(
              Endpoints.channelMessages(channelId),
              query: {'limit': '50'},
            )
            as List<dynamic>;

    return data.map((e) => Message.fromJson(e as Map<String, dynamic>)).toList()
      ..sort(_byId);
  }

  Future<void> send(String content) async {
    final api = ref.read(apiClientProvider);
    //wait for gateway echo before appending
    await api.post(Endpoints.channelMessages(channelId), {'content': content});
  }

  void _append(Message m) {
    final current = state.value ?? const [];
    if (current.any((x) => x.id == m.id)) return; //dedupe by id
    state = AsyncData([...current, m]..sort(_byId));
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

  void _replace(Message m) {
    final current = state.value ?? const [];
    if (!current.any((x) => x.id == m.id)) return;
    state = AsyncData([for (final x in current) x.id == m.id ? m : x]);
  }

  void _remove(String id) {
    final current = state.value ?? const [];
    if (!current.any((x) => x.id == id)) return;
    state = AsyncData([
      for (final x in current)
        if (x.id != id) x,
    ]);
  }

  //compare as bigInt
  static int _byId(Message a, Message b) =>
      BigInt.parse(a.id).compareTo(BigInt.parse(b.id));
}

//exposes connections status for a small banner
final gatewayStatusProvider = StreamProvider<GatewayStatus>((ref) {
  return ref.watch(gatewayClientProvider).status;
});
