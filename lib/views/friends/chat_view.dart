import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_palette.dart';
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
  // Texts of this screen
  static const _offlineText = "No connection · showing saved messages. New ones go out when you're back online";
  static const _queuedText = "No connection: your message will be sent when you're back online";
  // The counter appears when fewer than this many characters are left
  static const _counterFrom = 50;

  final _textController = TextEditingController();

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  // "13:44" (24 h); a message from another day: "Nov 18 · 13:44"
  static String _chatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    final now = DateTime.now();
    final sameDay = date.year == now.year && date.month == now.month && date.day == now.day;
    return sameDay ? '$hour:$minute' : '${_months[date.month - 1]} ${date.day} · $hour:$minute';
  }

  String _firstName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.first;
  }

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
        ..showSnackBar(const SnackBar(content: Text(_queuedText)));
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
        backGap: 14,
        subtitleGap: 0,
        leading: AvatarWidget(
          url: friend.avatarUrl,
          name: friend.name,
          size: 36,
          silhouette: true,
          border: Border.all(color: AppColors.background.withValues(alpha: 0.25), width: 1.5),
        ),
      ),
      body: Column(
        children: [
          if (vm.isOffline) const OfflineBanner(message: _offlineText, boxed: true),
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
              Icon(Icons.chat_bubble_outline_rounded, size: 56, color: context.palette.contrast.withValues(alpha: 0.12)),
              const SizedBox(height: 12),
              Text(
                vm.isOffline
                    ? 'No connection and no saved messages with ${_firstName(vm.friend.name)} yet.'
                    : 'No messages yet. Say hi to ${_firstName(vm.friend.name)}!',
                textAlign: TextAlign.center,
                style: AppFonts.body().copyWith(color: context.palette.contrast.withValues(alpha: 0.45)),
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
                border: mine ? null : Border.all(color: context.palette.contrast.withValues(alpha: 0.1), width: 1),
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
                  _chatTime(message.createdAt),
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
    final reason = vm.failReason(message.clientId) ?? "Couldn't send this message";
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
              'Retry',
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
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _textController,
          builder: (context, value, _) {
            final length = value.text.length;
            final hasText = value.text.trim().isNotEmpty;
            final showCounter = ChatViewModel.maxLength - length < _counterFrom;

            return Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      TextField(
                        controller: _textController,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        inputFormatters: [LengthLimitingTextInputFormatter(ChatViewModel.maxLength)],
                        style: AppFonts.body().copyWith(fontSize: 14, color: context.palette.contrast),
                        decoration: InputDecoration(
                          hintText: 'Write a message',
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
                      if (showCounter)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, right: 4),
                          child: Text(
                            '$length/${ChatViewModel.maxLength}',
                            style: AppFonts.body().copyWith(
                              fontSize: 11,
                              color: context.palette.contrast.withValues(alpha: 0.45),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                // Coral only when there is text; empty field: gray and it does not answer
                IconButton(
                  onPressed: hasText ? _send : null,
                  icon: Icon(
                    Icons.send_rounded,
                    color: hasText ? AppColors.accent1 : context.palette.contrast.withValues(alpha: 0.25),
                  ),
                  tooltip: 'Enviar',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
