import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/nexaryo_colors.dart';

/// One pickable category. [icon] is the tab glyph; [emojis] is the
/// pre-curated grid contents. Marked `const` everywhere so the entire
/// data model is constant-folded at compile time — zero parse cost on
/// first open (the historical pain point of `emoji_picker_flutter`).
class EmojiCategory {
  final String label;
  final String icon;
  final List<String> emojis;
  const EmojiCategory({
    required this.label,
    required this.icon,
    required this.emojis,
  });
}

/// Curated set covering ~95% of real chat usage. Keeping the data set
/// small (~250 entries) means the GridView only ever has a few dozen
/// children visible at once and the whole panel renders in one frame.
const List<EmojiCategory> kEmojiCategories = [
  EmojiCategory(
    label: 'Smileys',
    icon: '😀',
    emojis: [
      '😀',
      '😃',
      '😄',
      '😁',
      '😆',
      '😅',
      '🤣',
      '😂',
      '🙂',
      '🙃',
      '😉',
      '😊',
      '😇',
      '🥰',
      '😍',
      '🤩',
      '😘',
      '😗',
      '😚',
      '😙',
      '😋',
      '😛',
      '😜',
      '🤪',
      '😝',
      '🤑',
      '🤗',
      '🤭',
      '🤫',
      '🤔',
      '🤐',
      '🤨',
      '😐',
      '😑',
      '😶',
      '😏',
      '😒',
      '🙄',
      '😬',
      '🤥',
      '😌',
      '😔',
      '😪',
      '🤤',
      '😴',
      '😷',
      '🤒',
      '🤕',
      '🤢',
      '🤮',
      '🤧',
      '🥵',
      '🥶',
      '😵',
      '🤯',
      '🥳',
      '🥺',
      '😎',
      '🤓',
      '🧐',
      '😕',
      '😟',
      '🙁',
      '☹️',
      '😮',
      '😯',
      '😲',
      '😳',
      '🥺',
      '😦',
      '😧',
      '😨',
      '😰',
      '😥',
      '😢',
      '😭',
      '😱',
      '😖',
      '😣',
      '😞',
      '😓',
      '😩',
      '😫',
      '😤',
      '😡',
      '😠',
      '🤬',
      '😈',
      '👿',
      '💀',
    ],
  ),
  EmojiCategory(
    label: 'Hearts',
    icon: '❤️',
    emojis: [
      '❤️',
      '🧡',
      '💛',
      '💚',
      '💙',
      '💜',
      '🖤',
      '🤍',
      '🤎',
      '💔',
      '❣️',
      '💕',
      '💞',
      '💓',
      '💗',
      '💖',
      '💘',
      '💝',
      '💟',
      '♥️',
      '💌',
      '💋',
      '😍',
      '🥰',
      '😘',
      '💑',
      '💏',
      '💒',
      '👩‍❤️‍👨',
      '👨‍❤️‍👨',
    ],
  ),
  EmojiCategory(
    label: 'Gestures',
    icon: '👍',
    emojis: [
      '👍',
      '👎',
      '👌',
      '✌️',
      '🤞',
      '🤟',
      '🤘',
      '🤙',
      '👈',
      '👉',
      '👆',
      '🖕',
      '👇',
      '☝️',
      '✋',
      '🤚',
      '🖐️',
      '🖖',
      '👋',
      '🤝',
      '🙏',
      '✍️',
      '💪',
      '🦾',
      '🦵',
      '🦶',
      '👂',
      '👃',
      '🧠',
      '🦷',
      '🦴',
      '👀',
      '👁️',
      '👅',
      '👄',
      '💋',
      '🩸',
      '👏',
      '🙌',
      '🤲',
      '🤳',
      '💅',
      '🤛',
      '🤜',
      '👊',
      '✊',
      '🤚',
    ],
  ),
  EmojiCategory(
    label: 'Animals',
    icon: '🐶',
    emojis: [
      '🐶',
      '🐱',
      '🐭',
      '🐹',
      '🐰',
      '🦊',
      '🐻',
      '🐼',
      '🐨',
      '🐯',
      '🦁',
      '🐮',
      '🐷',
      '🐽',
      '🐸',
      '🐵',
      '🙈',
      '🙉',
      '🙊',
      '🐒',
      '🐔',
      '🐧',
      '🐦',
      '🐤',
      '🐣',
      '🐥',
      '🦆',
      '🦅',
      '🦉',
      '🦇',
      '🐺',
      '🐗',
      '🐴',
      '🦄',
      '🐝',
      '🐛',
      '🦋',
      '🐌',
      '🐞',
      '🐜',
      '🦟',
      '🦗',
      '🕷️',
      '🦂',
      '🐢',
      '🐍',
      '🦎',
      '🦖',
      '🦕',
      '🐙',
      '🦑',
      '🦐',
      '🦞',
      '🦀',
      '🐡',
      '🐠',
      '🐟',
      '🐬',
      '🐳',
      '🐋',
      '🦈',
      '🐊',
      '🐅',
      '🐆',
      '🦓',
      '🦍',
      '🦧',
      '🐘',
      '🦛',
      '🦏',
      '🐪',
      '🐫',
      '🦒',
      '🦘',
      '🐃',
      '🐂',
      '🐄',
      '🐎',
      '🐖',
      '🐏',
    ],
  ),
  EmojiCategory(
    label: 'Food',
    icon: '🍕',
    emojis: [
      '🍏',
      '🍎',
      '🍐',
      '🍊',
      '🍋',
      '🍌',
      '🍉',
      '🍇',
      '🍓',
      '🫐',
      '🍈',
      '🍒',
      '🍑',
      '🥭',
      '🍍',
      '🥥',
      '🥝',
      '🍅',
      '🍆',
      '🥑',
      '🥦',
      '🥬',
      '🥒',
      '🌶️',
      '🫑',
      '🌽',
      '🥕',
      '🫒',
      '🧄',
      '🧅',
      '🥔',
      '🍠',
      '🥐',
      '🥯',
      '🍞',
      '🥖',
      '🥨',
      '🧀',
      '🥚',
      '🍳',
      '🧈',
      '🥞',
      '🧇',
      '🥓',
      '🥩',
      '🍗',
      '🍖',
      '🌭',
      '🍔',
      '🍟',
      '🍕',
      '🥪',
      '🥙',
      '🧆',
      '🌮',
      '🌯',
      '🫔',
      '🥗',
      '🥘',
      '🍝',
      '🍜',
      '🍲',
      '🍛',
      '🍣',
      '🍱',
      '🥟',
      '🦪',
      '🍤',
      '🍙',
      '🍚',
      '🍘',
      '🍥',
      '🥠',
      '🥮',
      '🍢',
      '🍡',
      '🍧',
      '🍨',
      '🍦',
      '🥧',
      '🧁',
      '🍰',
      '🎂',
      '🍮',
      '🍭',
      '🍬',
      '🍫',
      '🍿',
      '🍩',
      '🍪',
      '🌰',
      '🥜',
      '🍯',
      '🥛',
      '🍼',
      '☕',
      '🫖',
      '🍵',
      '🧃',
      '🥤',
      '🍶',
      '🍺',
      '🍻',
      '🥂',
      '🍷',
      '🥃',
      '🍸',
      '🍹',
      '🧉',
      '🍾',
    ],
  ),
  EmojiCategory(
    label: 'Symbols',
    icon: '🔥',
    emojis: [
      '🔥',
      '💯',
      '✨',
      '⭐',
      '🌟',
      '💫',
      '⚡',
      '💥',
      '🎉',
      '🎊',
      '🎁',
      '🎈',
      '🎀',
      '🎂',
      '🌈',
      '☀️',
      '🌙',
      '⛅',
      '☁️',
      '🌧️',
      '⛈️',
      '🌩️',
      '🌨️',
      '❄️',
      '☃️',
      '⛄',
      '🌬️',
      '💨',
      '💧',
      '💦',
      '🌊',
      '✅',
      '❌',
      '⭕',
      '❗',
      '❓',
      '❕',
      '❔',
      '‼️',
      '⁉️',
      '〽️',
      '⚠️',
      '🚸',
      '🔱',
      '⚜️',
      '🔰',
      '♻️',
      '✳️',
      '❇️',
      '✴️',
      '💢',
      '💬',
      '💭',
      '🗯️',
      '♨️',
      '💤',
      '🆗',
      '🆒',
      '🆕',
      '🆙',
      '🆓',
      '🅰️',
      '🅱️',
      '🅾️',
      '🆎',
      '🆑',
      '🆘',
      '⛔',
      '📛',
      '🚫',
    ],
  ),
];

/// Lightweight, instant-mount emoji picker. Renders a horizontal tab
/// strip plus a fixed-height grid for the active category. No async
/// loading, no JSON parsing, no recents storage.
///
/// Cost: one [GridView.builder] over <=120 const strings. Builds in
/// well under a frame on every device we care about.
class EmojiPickerPanel extends StatefulWidget {
  /// Called with the selected emoji. The caller is responsible for
  /// closing the host overlay.
  final ValueChanged<String> onPicked;
  final double height;
  const EmojiPickerPanel({
    super.key,
    required this.onPicked,
    this.height = 300,
  });

  @override
  State<EmojiPickerPanel> createState() => _EmojiPickerPanelState();
}

class _EmojiPickerPanelState extends State<EmojiPickerPanel> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cat = kEmojiCategories[_index];
    return SizedBox(
      height: widget.height,
      child: Column(
        children: [
          // Category tabs.
          SizedBox(
            height: 44,
            child: Row(
              children: [
                for (var i = 0; i < kEmojiCategories.length; i++)
                  Expanded(
                    child: _CategoryTab(
                      icon: kEmojiCategories[i].icon,
                      selected: i == _index,
                      accent: c.primary,
                      onTap: () {
                        if (i == _index) return;
                        HapticFeedback.selectionClick();
                        setState(() => _index = i);
                      },
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: c.cardBorder),
          // Grid of emojis. RepaintBoundary keeps tile rebuilds isolated
          // from the host overlay's transitions.
          Expanded(
            child: RepaintBoundary(
              child: GridView.builder(
                key: ValueKey('emoji-grid-$_index'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 44,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemCount: cat.emojis.length,
                itemBuilder: (_, i) {
                  final e = cat.emojis[i];
                  return _EmojiTile(
                    emoji: e,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onPicked(e);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTab extends StatelessWidget {
  final String icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  const _CategoryTab({
    required this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(child: Text(icon, style: const TextStyle(fontSize: 22))),
          if (selected)
            Positioned(
              bottom: 4,
              child: Container(
                width: 18,
                height: 2,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmojiTile extends StatelessWidget {
  final String emoji;
  final VoidCallback onTap;
  const _EmojiTile({required this.emoji, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // No Material/InkWell ripple — it triples build cost per tile and
    // we're aiming for instant tap-and-dismiss.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 26))),
    );
  }
}
