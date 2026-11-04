import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../models/money.dart';

/// Swipe an entry left to delete it, with Undo. With [hint], the row slides
/// open by itself once to show that it can be swiped, and a tip appears.
class SwipeToDelete extends StatefulWidget {
  const SwipeToDelete({
    super.key,
    required this.txn,
    required this.child,
    this.hint = false,
  });

  final Txn txn;
  final Widget child;
  final bool hint;

  @override
  State<SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<SwipeToDelete>
    with SingleTickerProviderStateMixin {
  static const _peek = 88.0;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  // Wait, slide open, close, slide open again, close.
  late final Animation<double> _offset = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(0), weight: 20),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.0,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 18,
    ),
    TweenSequenceItem(tween: ConstantTween(1), weight: 14),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 0.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 16,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.0,
        end: 0.7,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 14,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.7,
        end: 0.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 18,
    ),
  ]).animate(_c);

  @override
  void initState() {
    super.initState();
    if (widget.hint) {
      _c.forward().whenComplete(_showTip);
    }
  }

  void _showTip() {
    if (!mounted) return;
    context.store.markSwipeHintSeen();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(tr('Tip: swipe an entry left to delete it')),
        action: SnackBarAction(label: tr('Got it'), onPressed: () {}),
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _delete() {
    final store = context.store;
    final t = widget.txn;
    store.deleteTxn(t.id);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(tr('Deleted {0}', [formatRupees(t.amount)])),
          action: SnackBarAction(
            label: tr('Undo'),
            onPressed: () => store.restoreTxn(t),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = Container(
      color: scheme.errorContainer,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 6),
          Text(
            tr('Delete'),
            style: TextStyle(
              color: scheme.onErrorContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    Widget child = widget.child;
    if (widget.hint) {
      child = AnimatedBuilder(
        animation: _offset,
        builder: (context, tile) => _offset.value == 0
            ? tile!
            : Stack(
                children: [
                  Positioned.fill(child: background),
                  Transform.translate(
                    offset: Offset(-_peek * _offset.value, 0),
                    child: Material(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: tile,
                    ),
                  ),
                ],
              ),
        child: widget.child,
      );
    }
    return Dismissible(
      key: ValueKey('txn-${widget.txn.id}'),
      direction: DismissDirection.endToStart,
      background: background,
      onDismissed: (_) => _delete(),
      child: child,
    );
  }
}
