import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:loqui/core/api/endpoints.dart';
import 'package:loqui/core/auth/auth_service.dart';
import 'package:loqui/core/gateway/gateway_providers.dart';
import 'package:loqui/shared/models/models.dart';

final channelsProvider =
    AsyncNotifierProvider.autoDispose<ChannelsController, List<Channel>>(
      ChannelsController.new,
    );

class ChannelsController extends AsyncNotifier<List<Channel>> {
  @override
  Future<List<Channel>> build() async {
    final api = ref.watch(apiClientProvider);
    final data = await api.get(Endpoints.channels) as List<dynamic>;
    final channels = data
        .map((e) => Channel.fromJson(e as Map<String, dynamic>))
        .toList();
    //let gateway background-sub to all known channels
    ref
        .read(gatewayClientProvider)
        .registerChannels(channels.map((c) => c.id).toList());
    return channels;
  }

  Future<Channel> create(String name) async {
    final api = ref.read(apiClientProvider);
    final data =
        await api.post(Endpoints.channels, {'name': name})
            as Map<String, dynamic>;
    final channel = Channel.fromJson(data);
    state = AsyncData([...?state.value, channel]);
    ref.read(gatewayClientProvider).registerChannels([channel.id]);
    return channel;
  }
}
