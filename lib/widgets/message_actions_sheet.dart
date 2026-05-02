import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';

import '../theme/nexaryo_colors.dart';
import 'emoji_picker_panel.dart';

/// Quick-react row shown above any long-press menu. The "+" tile expands
/// the in-place full picker.
const List<String> kQuickReactions = ['👍', '❤️', '😂', '😮', '😢', '🔥'];

/// Outcome returned to the caller. Null if the user dismissed.
enum MessageAction { reply, copy, edit, deleteForEveryone }

/// Result returned to chat_screen for processing.
class MessageActionResult {
  /// Set if the user picked an emoji to react with. The empty string means
  /// "remove my reaction".
  final String? reaction;
  final MessageAction? action;
  const MessageActionResult({this.reaction, this.action});
}

class _ReactionTile extends StatelessWidget {
  final String emoji;
  final bool selected;
  final VoidCallback onTap;
  const _ReactionTile({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(19),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: selected ? c.primary.withValues(alpha: 0.18) : null,
          shape: BoxShape.circle,
        ),
        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final List<List<dynamic>> icon;
  final String label;
  final bool destructive;
  final VoidCallback onTap;
  const _ActionRow({
    required this.icon,
    required this.label,
    this.destructive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = destructive ? const Color(0xFFE53935) : c.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            HugeIcon(icon: icon, color: color, size: 20),
            const SizedBox(width: 14),
            Text(
              label,
              style: GoogleFonts.montserrat(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// Overlay: floats next to the long-pressed bubble instead of rising from
// the bottom. Keeps the keyboard up (no Navigator.push).
// =====================================================================

/// Show the action menu anchored to a specific bubble [anchor] (global
/// rect). The menu floats next to the message and the keyboard is left
/// untouched. Returns the same [MessageActionResult] as the sheet.
///
/// [mine] decides which bubble edge the menus align to.
Future<MessageActionResult?> showMessageActionsOverlay(
  BuildContext context, {
  required Rect anchor,
  required bool mine,
  required bool canReply,
  required bool canCopy,
  required bool canEdit,
  required bool canDelete,
  required String? myReaction,
}) {
  HapticFeedback.selectionClick();
  final overlay = Overlay.of(context, rootOverlay: true);
  final completer = Completer<MessageActionResult?>();
  late OverlayEntry entry;

  void close(MessageActionResult? r) {
    if (completer.isCompleted) return;
    completer.complete(r);
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (ctx) => _MessageActionsOverlay(
      anchor: anchor,
      mine: mine,
      canReply: canReply,
      canCopy: canCopy,
      canEdit: canEdit,
      canDelete: canDelete,
      myReaction: myReaction,
      onResult: close,
    ),
  );
  overlay.insert(entry);
  return completer.future;
}

class _MessageActionsOverlay extends StatefulWidget {
  final Rect anchor;
  final bool mine;
  final bool canReply;
  final bool canCopy;
  final bool canEdit;
  final bool canDelete;
  final String? myReaction;
  final ValueChanged<MessageActionResult?> onResult;

  const _MessageActionsOverlay({
    required this.anchor,
    required this.mine,
    required this.canReply,
    required this.canCopy,
    required this.canEdit,
    required this.canDelete,
    required this.myReaction,
    required this.onResult,
  });

  @override
  State<_MessageActionsOverlay> createState() => _MessageActionsOverlayState();
}

class _MessageActionsOverlayState extends State<_MessageActionsOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  /// When true, the small reactions strip is replaced in-place with the
  /// full categorized emoji picker. No Navigator push, no keyboard
  /// disturbance — this is what makes the open feel instant.
  bool _showPicker = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _dismiss([MessageActionResult? r]) async {
    await _ctrl.reverse();
    widget.onResult(r);
  }

  /// Toggle the in-place full picker. Cheaper than the old bottom-sheet
  /// route — no Navigator push, keyboard stays up.
  void _toggleFullPicker() {
    HapticFeedback.selectionClick();
    setState(() => _showPicker = !_showPicker);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final screenH = mq.size.height;
    final topInset = mq.padding.top;
    final bottomInset = mq.viewInsets.bottom + mq.padding.bottom;

    // Sizes (best-effort estimates so we can pick above/below before layout).
    // When the full picker is open the reactions panel grows to the
    // picker's footprint and the action menu is hidden to keep focus.
    final reactionsH = _showPicker ? 320.0 : 56.0;
    final reactionsW = _showPicker ? 320.0 : 290.0;
    const menuW = 240.0;
    final actionCount =
        (widget.canCopy ? 1 : 0) +
        (widget.canEdit ? 1 : 0) +
        (widget.canDelete ? 1 : 0);
    final menuH = (actionCount * 50.0) + 8.0;
    final showMenu = !_showPicker;

    // Vertical placement: prefer reactions above + menu below, but flip
    // either side if it doesn't fit (e.g. bubble at very top or very
    // bottom of the visible area).
    final spaceAbove = widget.anchor.top - topInset - 8;
    final spaceBelow = screenH - bottomInset - widget.anchor.bottom - 8;

    double reactionsTop;
    if (spaceAbove >= reactionsH + 8) {
      reactionsTop = widget.anchor.top - reactionsH - 8;
    } else if (spaceBelow >= reactionsH + menuH + 16) {
      // No room above — slot reactions just below, menu further below.
      reactionsTop = widget.anchor.bottom + 8;
    } else {
      // Cramped: pin to top of safe area.
      reactionsTop = topInset + 8;
    }

    double menuTop;
    if (spaceBelow >= menuH + 8) {
      menuTop = widget.anchor.bottom + 8;
      // If we placed reactions below too, push menu below reactions.
      if (reactionsTop >= widget.anchor.bottom) {
        menuTop = reactionsTop + reactionsH + 8;
      }
    } else if (spaceAbove >= menuH + reactionsH + 16) {
      menuTop = widget.anchor.top - menuH - 8;
      // And put reactions above the menu.
      reactionsTop = menuTop - reactionsH - 8;
    } else {
      // Cramped: pin to bottom of safe area.
      menuTop = screenH - bottomInset - menuH - 8;
    }

    double clampLeft(double w, {required bool alignRight}) {
      final raw = alignRight ? widget.anchor.right - w : widget.anchor.left;
      return raw.clamp(8.0, screenW - w - 8.0);
    }

    final reactionsLeft = clampLeft(reactionsW, alignRight: widget.mine);
    final menuLeft = clampLeft(menuW, alignRight: widget.mine);

    return Stack(
      children: [
        // Dim backdrop. Tap anywhere outside the menus to dismiss.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _dismiss(),
            child: FadeTransition(
              opacity: _fade,
              child: Container(color: Colors.black.withValues(alpha: 0.35)),
            ),
          ),
        ),
        // Reactions row.
        Positioned(
          top: reactionsTop,
          left: reactionsLeft,
          width: reactionsW,
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              alignment: widget.mine
                  ? Alignment.bottomRight
                  : Alignment.bottomLeft,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: _showPicker
                      ? const EdgeInsets.all(8)
                      : const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(_showPicker ? 20 : 34),
                    border: Border.all(color: c.cardBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _showPicker
                      ? EmojiPickerPanel(
                          height: reactionsH - 16,
                          onPicked: (e) =>
                              _dismiss(MessageActionResult(reaction: e)),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            for (final e in kQuickReactions)
                              _ReactionTile(
                                emoji: e,
                                selected: widget.myReaction == e,
                                onTap: () => _dismiss(
                                  MessageActionResult(
                                    reaction: widget.myReaction == e ? '' : e,
                                  ),
                                ),
                              ),
                            InkWell(
                              onTap: _toggleFullPicker,
                              borderRadius: BorderRadius.circular(20),
                              child: SizedBox(
                                width: 38,
                                height: 38,
                                child: Center(
                                  child: HugeIcon(
                                    icon: HugeIcons.strokeRoundedAdd01,
                                    color: c.textSecondary,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
        // Action menu.
        if (showMenu)
          Positioned(
            top: menuTop,
            left: menuLeft,
            width: menuW,
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                alignment: widget.mine ? Alignment.topRight : Alignment.topLeft,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: c.cardBorder),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.canCopy)
                          _ActionRow(
                            icon: HugeIcons.strokeRoundedCopy01,
                            label: 'Copy',
                            onTap: () => _dismiss(
                              const MessageActionResult(
                                action: MessageAction.copy,
                              ),
                            ),
                          ),
                        if (widget.canEdit)
                          _ActionRow(
                            icon: HugeIcons.strokeRoundedEdit02,
                            label: 'Edit',
                            onTap: () => _dismiss(
                              const MessageActionResult(
                                action: MessageAction.edit,
                              ),
                            ),
                          ),
                        if (widget.canDelete)
                          _ActionRow(
                            icon: HugeIcons.strokeRoundedDelete02,
                            label: 'Delete for everyone',
                            destructive: true,
                            onTap: () => _dismiss(
                              const MessageActionResult(
                                action: MessageAction.deleteForEveryone,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
