import 'package:flutter/material.dart';

import '../theme/journal_metrics.dart';

/// The Material 3 default height of an *extended* [FloatingActionButton] --
/// what `TodayScreen`'s "Write an entry" button always is, whichever way
/// [FloatingActionButton.extended]'s own `isExtended` flag currently reads.
///
/// The framework keys a button's size constraints off which constructor
/// built it, not off that flag: `isExtended` only swaps the label in and out
/// and animates the button's *width* between a circle and a pill: the
/// height stays this fixed 48 the whole time
/// (`_FABDefaultsM3.extendedSizeConstraints` in
/// `package:flutter/src/material/floating_action_button.dart`, not exposed
/// as a public constant the way [kFloatingActionButtonMargin] is). A screen
/// that instead built a plain `FloatingActionButton()` would get the
/// "regular" 56-tall circle and should not reach for this constant.
const double _extendedFabHeight = 48;

/// How far a scrollable's bottom padding must clear a
/// [Scaffold.floatingActionButton] parked at its default `endFloat`
/// location, so the last item never ends up drawn partly behind it.
///
/// Built from fixed Material dimensions rather than measured from
/// [MediaQuery]: unlike a status bar or a system gesture inset, neither a
/// FAB's own height nor the margin [Scaffold] leaves around it changes with
/// device or orientation, so this is one constant every screen with a FAB
/// can share rather than a fresh guess at each call site.
/// [kFloatingActionButtonMargin] is the gap the framework itself always
/// leaves between the button and the scaffold's safe content edge;
/// [JournalSpacing.x6] on top of that is breathing room so the last card
/// clears the button by more than a hair -- together landing on the same
/// 96-logical-pixel gap `TodayScreen` used before it was a guess with a
/// name.
const double journalFabScrollClearance =
    _extendedFabHeight + kFloatingActionButtonMargin + JournalSpacing.x6;
