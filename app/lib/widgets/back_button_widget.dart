import 'package:flutter/material.dart';

import '../services/locale_service.dart';

class BackButtonWidget extends StatelessWidget {
  const BackButtonWidget({
    super.key,
    this.onPressed,
    this.tooltip,
    this.icon,
  });

  final VoidCallback? onPressed;
  final String? tooltip;
  final IconData? icon;

  void _defaultAction(BuildContext context) {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    ScaffoldState? state = Scaffold.maybeOf(context);
    if (state == null || state.widget.drawer == null) {
      state = context.findRootAncestorStateOfType<ScaffoldState>();
    }
    if (state == null || state.widget.drawer == null) return;
    state.openDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return IconButton(
      onPressed: onPressed ?? () => _defaultAction(context),
      tooltip:
          tooltip ?? (icon == Icons.menu ? l.t('menu') : l.t('back')),
      style: IconButton.styleFrom(
        foregroundColor: const Color(0xFF3D5AFE),
      ),
      icon: Icon(icon ?? Icons.arrow_back_ios_new),
    );
  }
}
