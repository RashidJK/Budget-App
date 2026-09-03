import 'package:flutter/material.dart';

import '../command/command_bar.dart';
import '../models/phosphor.dart';
import '../theme.dart';
import '../widgets/morph_nav_bar.dart';
import 'tracker/add_expense.dart';

/// The universal capture menu that rises from the nav bar's "+". Capture-first
/// (spec §4): the same set of quick actions from every screen, so logging money
/// is one tap away wherever you are.
///
/// Shared by the home shell and the account detail screen so the "+" behaves
/// identically as the bar morphs around it.
List<MorphAction> captureActions(BuildContext context) => [
  MorphAction(
    icon: PhosphorR.plus,
    label: 'Add expense',
    accent: context.scheme.primary,
    onTap: () => AddExpenseSheet.show(context),
  ),
  MorphAction(
    icon: PhosphorR.arrowDownLeft,
    label: 'Income',
    accent: context.good,
    onTap: () => CommandBar.show(context, initialText: 'Received '),
  ),
  MorphAction(
    icon: PhosphorR.arrowsLeftRight,
    label: 'Transfer',
    accent: const Color(0xFF7C6BF5),
    onTap: () => CommandBar.show(context, initialText: 'Transfer '),
  ),
  MorphAction(
    icon: PhosphorR.receipt,
    label: 'Scan or type',
    accent: context.caution,
    onTap: () => CommandBar.show(context),
  ),
];
