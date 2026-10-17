import 'package:flutter/material.dart';

import '../analysis/exercises.dart';
import '../workout/session.dart';
import 'device_page.dart';
import 'session_feedback_page.dart';
import 'sessions_page.dart';
import 'weight_input_page.dart';

/// Stance's workout navigation (notes §16):
/// Home → Sessions → Weight → Record → Session feedback, and from an
/// active feedback page "New set" → Weight → Record → back to it.

const _sessionsRoute = 'workout_sessions';
const _feedbackRoute = 'workout_session_feedback';

Future<void> openSessions(BuildContext context, Exercise exercise) =>
    Navigator.of(context).push(MaterialPageRoute(
      settings: const RouteSettings(name: _sessionsRoute),
      builder: (_) => SessionsPage(exercise: exercise),
    ));

/// [active] shows "New set": the session is live or still continuable.
Future<void> openSessionFeedback(BuildContext context, Session session,
        {bool active = false}) =>
    Navigator.of(context).push(_feedbackPage(session, active: active));

Route<void> _feedbackPage(Session session, {required bool active}) =>
    MaterialPageRoute(
      settings: const RouteSettings(name: _feedbackRoute),
      builder: (_) => SessionFeedbackPage(session: session, active: active),
    );

/// Starts the next set: weight input, then recording. [session] is the
/// session to add to, or null for a new one.
Future<void> startSet(BuildContext context, Exercise exercise,
        {Session? session}) =>
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WeightInputPage(exercise: exercise, session: session),
    ));

/// After a set is saved. A set added from a feedback page returns to it
/// (it reloads from the store). A new session's first set replaces the
/// weight and record pages with its feedback page, so back leads to the
/// Sessions list (Stance's `popUpTo(sessions)`).
void showFeedbackAfterSet(BuildContext context, Session session,
    {required bool continuing}) {
  final nav = Navigator.of(context);
  if (continuing) {
    nav.popUntil((r) => r.settings.name == _feedbackRoute || r.isFirst);
  } else {
    nav.pushAndRemoveUntil(_feedbackPage(session, active: true),
        (r) => r.settings.name == _sessionsRoute || r.isFirst);
  }
}

Future<void> openDevice(BuildContext context) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => const DevicePage()));
