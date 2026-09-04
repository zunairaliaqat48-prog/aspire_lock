import 'package:flutter/material.dart';

/// Global navigator key, used so background/notification callbacks
/// (which don't have a BuildContext) can still push new screens.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
