import 'package:flutter/material.dart';

// Global navigation key for navigating without context
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Global state to track if a call is currently active
String? globalActiveCallId;
