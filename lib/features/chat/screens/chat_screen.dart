import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:loqui/core/auth/auth_service.dart';

import 'package:loqui/core/gateway/gateway_client.dart';
import 'package:loqui/features/chat/providers/chat_provider.dart';
import 'package:loqui/shared/models/models.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.channelId});
  final String channelId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  bool _hasNewBelow = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(channelMessagesProvider(widget.channelId).notifier)
          .send(text);
      _input.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _edit(Message m) async {
    final controller = TextEditingController(text: m.content);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          maxLength: 2000,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = result?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == m.content) return;
    try {
      await ref
          .read(channelMessagesProvider(widget.channelId).notifier)
          .edit(m.id, trimmed);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _delete(Message m) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref
          .read(channelMessagesProvider(widget.channelId).notifier)
          .delete(m.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  // reverse:true, so newest is offset 0 and older is maxScrollExtent
  bool get _atBottom => !_scroll.hasClients || _scroll.position.pixels <= 60;

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    //near top: pull an older page
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      ref.read(channelMessagesProvider(widget.channelId).notifier).loadOlder();
    }
    //back at bottom: clear new-messages hint
    if (_hasNewBelow && pos.pixels <= 60) {
      setState(() => _hasNewBelow = false);
    }
  }

  void _jumpToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(channelMessagesProvider(widget.channelId));
    final status = ref.watch(gatewayStatusProvider).value;
    final auth = ref.watch(authControllerProvider);
    final myId = auth is Authenticated ? auth.user.id : null;

    // on new bottom message: pin if already at bottom, otherwise keep
    // reading position (compensate for inserted height) and hint
    ref.listen(channelMessagesProvider(widget.channelId), (prev, next) {
      final after = next.value;
      if (after == null || after.messages.isEmpty) return;
      final prevMsgs = prev?.value?.messages ?? const <Message>[];
      final grewAtBottom =
          after.messages.length > prevMsgs.length &&
          (prevMsgs.isEmpty || after.messages.last.id != prevMsgs.last.id);
      if (!grewAtBottom) return;

      if (_atBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
      } else {
        final oldMax = _scroll.hasClients
            ? _scroll.position.maxScrollExtent
            : 0.0;
        final oldPixels = _scroll.hasClients ? _scroll.position.pixels : 0.0;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scroll.hasClients) return;
          final delta = _scroll.position.maxScrollExtent - oldMax;
          if (delta > 0) _scroll.jumpTo(oldPixels + delta);
        });
        if (!_hasNewBelow) setState(() => _hasNewBelow = true);
      }
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_outlined),
          onPressed: () => context.go('/'),
        ),
        title: const Text('Channel'),
        bottom: status != null && status != GatewayStatus.connected
            ? PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.errorContainer,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    status.name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                messages.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Failed to load\n$e')),
                  data: (chat) => ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount:
                        chat.messages.length + (chat.loadingOlder ? 1 : 0),
                    itemBuilder: (_, i) {
                      //trailing slot (top in reverse) is older page loader
                      if (chat.loadingOlder && i == chat.messages.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final m = chat.messages[chat.messages.length - 1 - i];
                      return _MessageTile(
                        key: ValueKey(m.id),
                        message: m,
                        isMine: m.author.id == myId,
                        onEdit: () => _edit(m),
                        onDelete: () => _delete(m),
                      );
                    },
                  ),
                ),
                if (_hasNewBelow)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 8,
                    child: Center(
                      child: ActionChip(
                        avatar: const Icon(
                          Icons.arrow_downward_rounded,
                          size: 16,
                        ),
                        label: const Text('New messages'),
                        onPressed: () {
                          _jumpToBottom();
                          setState(() => _hasNewBelow = false);
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: Focus(
                      onKeyEvent: (node, event) {
                        if (!kIsWeb || event is! KeyDownEvent) {
                          return KeyEventResult.ignored;
                        }

                        if (event.logicalKey == LogicalKeyboardKey.enter) {
                          if (HardwareKeyboard.instance.isShiftPressed) {
                            //let TextField insert newline
                            return KeyEventResult.ignored;
                          }

                          _send();
                          return KeyEventResult.ignored;
                        }

                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: 2000,
                        decoration: const InputDecoration(hintText: 'Message'),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send_outlined),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({
    super.key,
    required this.message,
    this.isMine = false,
    this.onEdit,
    this.onDelete,
  });
  final Message message;
  final bool isMine;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final t = message.createdAt.toLocal();
    final time =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.outline,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                message.author.handle,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Text(time, style: muted),
              if (message.editedAt != null) ...[
                const SizedBox(width: 6),
                Text('(edited)', style: muted),
              ],
              if (isMine) ...[
                const Spacer(),
                SizedBox(
                  height: 20,
                  width: 28,
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    onSelected: (v) {
                      if (v == 'edit') onEdit?.call();
                      if (v == 'delete') onDelete?.call();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(message.content),
        ],
      ),
    );
  }
}
