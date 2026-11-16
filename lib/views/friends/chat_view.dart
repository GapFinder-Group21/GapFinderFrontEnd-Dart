import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_palette.dart';
import 'package:gapfinderfrontend_dart/core/utils/display_formatters.dart';
import 'package:gapfinderfrontend_dart/models/chat_message.dart';
import 'package:gapfinderfrontend_dart/viewmodels/friends/chat_view_model.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/avatar_widget.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_top_bar.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/offline_banner.dart';

/// Chat with one friend: the messages and a field to write a new one.
class ChatView extends StatefulWidget {
  const ChatView({super.key});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _send() {
    final vm = context.read<ChatViewModel>();
    final error = vm.send(_textController.text);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    _textController.clear();
    // Offline: the message waits in the outbox, the user is told right away
    if (vm.isOffline) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(ChatViewModel.queuedNotice)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ChatViewModel>();
    final friend = vm.friend;

    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: CustomTopBar(
        title: friend.name,
        subtitle: friend.career,
        leading: AvatarWidget(url: friend.avatarUrl, name: friend.name, size: 36),
      ),
      body: Column(
        children: [
          if (vm.isOffline) const OfflineBanner(message: ChatViewModel.offlineMessage),
          Expanded(child: _buildMessages(vm)),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildMessages(ChatViewModel vm) {
    if (vm.isLoading) return const Center(child: CircularProgressIndicator());

    if (vm.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline_rounded, size: 48, color: context.palette.contrast.withValues(alpha: 0.1)),
              const SizedBox(height: 12),
              Text(
                vm.isOffline
                    ? 'Sin conexión y aún no hay mensajes guardados con ${vm.friend.name}'
                    : 'Aún no hay mensajes. ¡Saluda a ${vm.friend.name}!',
                textAlign: TextAlign.center,
                style: AppFonts.body().copyWith(color: context.palette.contrast.withValues(alpha: 0.4)),
              ),
            ],
          ),
        ),
      );
    }

    final messages = vm.messages;
    // Reversed list: the newest message is at the bottom and the list starts there
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[messages.length - 1 - index];
        return _buildBubble(vm, message);
      },
    );
  }

  Widget _buildBubble(ChatViewModel vm, ChatMessage message) {
    final mine = message.isMine(vm.userId ?? -1);
    final failed = message.status == ChatMessageStatus.failed;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: mine ? AppColors.accent1 : context.palette.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(mine ? 16 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 16),
                ),
                border: mine ? null : Border.all(color: AppColors.accent2.withValues(alpha: 0.3), width: 1.5),
              ),
              child: Text(
                message.content,
                style: AppFonts.body().copyWith(
                  fontSize: 14,
                  color: mine ? Colors.white : context.palette.contrast,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DisplayFormatters.time(message.createdAt),
                  style: AppFonts.body().copyWith(
                    fontSize: 10,
                    color: context.palette.contrast.withValues(alpha: 0.4),
                  ),
                ),
                if (mine) ...[
                  const SizedBox(width: 4),
                  _buildStatusIcon(message.status),
                ],
              ],
            ),
            if (mine && failed) _buildRetry(vm, message),
          ],
        ),
      ),
    );
  }

  // ✓ sent · clock pending · ⚠ failed
  Widget _buildStatusIcon(ChatMessageStatus status) {
    switch (status) {
      case ChatMessageStatus.sent:
        return const Icon(Icons.check_rounded, size: 13, color: AppColors.accent2);
      case ChatMessageStatus.pending:
        return Icon(Icons.schedule_rounded, size: 13, color: context.palette.contrast.withValues(alpha: 0.4));
      case ChatMessageStatus.failed:
        return const Icon(Icons.warning_amber_rounded, size: 13, color: AppColors.accent1);
    }
  }

  Widget _buildRetry(ChatViewModel vm, ChatMessage message) {
    final reason = vm.failReason(message.clientId) ?? 'No se pudo enviar';
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            reason,
            textAlign: TextAlign.end,
            style: AppFonts.body().copyWith(fontSize: 11, color: AppColors.accent1),
          ),
          TextButton(
            onPressed: () => vm.retry(message.clientId),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Reintentar',
              style: AppFonts.body(weight: FontWeight.w700).copyWith(fontSize: 12, color: AppColors.accent1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      color: context.palette.surface,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [LengthLimitingTextInputFormatter(ChatViewModel.maxLength)],
                style: AppFonts.body().copyWith(fontSize: 14, color: context.palette.contrast),
                decoration: InputDecoration(
                  hintText: 'Escribe un mensaje',
                  hintStyle: AppFonts.body().copyWith(color: context.palette.contrast.withValues(alpha: 0.4)),
                  filled: true,
                  fillColor: context.palette.background,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              onPressed: _send,
              icon: const Icon(Icons.send_rounded, color: AppColors.accent1),
              tooltip: 'Enviar',
            ),
          ],
        ),
      ),
    );
  }
}
