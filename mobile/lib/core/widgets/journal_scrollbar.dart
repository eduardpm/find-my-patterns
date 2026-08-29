import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A slim, persistent scroll indicator drawn inside [child]'s right edge.
///
/// It exists because a box of text that continues below the fold looks
/// exactly like a box of text that has ended. It is *persistent* rather than
/// fading out after a scroll — [RawScrollbar.thumbVisibility] is always
/// on — because its whole job is to say "there is more here" to someone who
/// has not touched the screen yet, and a scrollbar that has already faded by
/// the time someone looks for it has failed at that job.
///
/// It brightens while a scroll is in progress, tracked through
/// [controller]'s `position.isScrollingNotifier`, and [RawScrollbar] draws
/// nothing at all when [child] has nothing to scroll — a scrollbar on
/// content that fits is noise. The thumb is decorative in the strict sense
/// (the content it hints at is reachable by scrolling and readable by a
/// screen reader either way), so it adds nothing of its own to the
/// accessibility tree.
class JournalScrollbar extends StatefulWidget {
  /// Wraps [child] with a scrollbar that tracks [controller].
  const JournalScrollbar({
    super.key,
    required this.controller,
    required this.child,
  });

  /// The controller attached to the scrollable [child] contains.
  final ScrollController controller;

  /// The scrollable content.
  final Widget child;

  @override
  State<JournalScrollbar> createState() => _JournalScrollbarState();
}

class _JournalScrollbarState extends State<JournalScrollbar> {
  static const double _thickness = 3;
  static const double _minThumbLength = 24;
  static const double _restingAlpha = 0.25;
  static const double _scrollingAlpha = 0.5;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScrollChanged);
  }

  @override
  void didUpdateWidget(covariant JournalScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScrollChanged);
      widget.controller.addListener(_onScrollChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScrollChanged);
    super.dispose();
  }

  void _onScrollChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final isScrolling =
        widget.controller.hasClients &&
        widget.controller.position.isScrollingNotifier.value;
    return RawScrollbar(
      controller: widget.controller,
      thumbVisibility: true,
      thickness: _thickness,
      minThumbLength: _minThumbLength,
      radius: const Radius.circular(_thickness / 2),
      thumbColor: context.journalColors.onSurfaceVariant.withValues(
        alpha: isScrolling ? _scrollingAlpha : _restingAlpha,
      ),
      child: widget.child,
    );
  }
}
