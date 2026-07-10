import 'dart:convert';

import 'package:loqui/shared/models/models.dart';

// events pushed by server over gateway
sealed class GatewayEvent {
  const GatewayEvent();

  static GatewayEvent? tryParse(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      switch (j['op']) {
        case 'hello':
          return HelloEvent(j['user_id'] as String);
        case 'subscribed':
          return SubscribedEvent(j['channel_id'] as String);
        case 'unsubscribed':
          return UnsubscribedEvent(j['channel_id'] as String);
        case 'message_create':
          return MessageCreateEvent(
            Message.fromJson(j['data'] as Map<String, dynamic>),
          );
        case 'message_update':
          return MessageUpdateEvent(
            Message.fromJson(j['data'] as Map<String, dynamic>),
          );
        case 'message_delete':
          final d = j['data'] as Map<String, dynamic>;
          return MessageDeleteEvent(
            id: d['id'] as String,
            channelId: d['channel_id'] as String,
          );
        case 'error':
          return GatewayErrorEvent(j['message'] as String? ?? 'error');
      }
    } catch (_) {
      /*ignore malformed frames*/
    }
    return null;
  }
}

class HelloEvent extends GatewayEvent {
  const HelloEvent(this.userId);
  final String userId;
}

class SubscribedEvent extends GatewayEvent {
  const SubscribedEvent(this.channelId);
  final String channelId;
}

class UnsubscribedEvent extends GatewayEvent {
  const UnsubscribedEvent(this.channelId);
  final String channelId;
}

class MessageCreateEvent extends GatewayEvent {
  const MessageCreateEvent(this.message);
  final Message message;
}

class MessageUpdateEvent extends GatewayEvent {
  const MessageUpdateEvent(this.message);
  final Message message;
}

class MessageDeleteEvent extends GatewayEvent {
  const MessageDeleteEvent({required this.id, required this.channelId});
  final String id;
  final String channelId;
}

class GatewayErrorEvent extends GatewayEvent {
  const GatewayErrorEvent(this.message);
  final String message;
}
