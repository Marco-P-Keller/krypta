import 'dart:async';
import 'package:flutter/services.dart';

/// M2-Client (audit 2026-05): clipboard helper that auto-clears the
/// clipboard after a configurable window. Without this, anything copied
/// (safety numbers, message content, user IDs) sits indefinitely on the
/// system clipboard where clipboard-history tools and accessibility
/// services can read it.
///
/// Use [copyEphemeral] in place of `Clipboard.setData(...)` everywhere
/// the copied content is sensitive.
class ClipboardHelper {
  static const _autoClearAfter = Duration(seconds: 60);

  /// The text we wrote on the most recent ephemeral copy. Used to
  /// compare-and-clear so we don't wipe a value the user has already
  /// replaced with their own copy/paste.
  static String? _lastEphemeralText;
  static Timer? _pendingClearTimer;

  /// Copy [text] to the clipboard and schedule an automatic clear after
  /// [_autoClearAfter]. If the user copies something else in the
  /// meantime, the auto-clear is a no-op (we don't clobber their copy).
  static Future<void> copyEphemeral(String text) async {
    _pendingClearTimer?.cancel();
    await Clipboard.setData(ClipboardData(text: text));
    _lastEphemeralText = text;
    _pendingClearTimer = Timer(_autoClearAfter, _clearIfStillOurs);
  }

  static Future<void> _clearIfStillOurs() async {
    final last = _lastEphemeralText;
    if (last == null) return;
    try {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == last) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } catch (_) {
      // Best effort — never throw out of a clipboard helper.
    } finally {
      _lastEphemeralText = null;
      _pendingClearTimer = null;
    }
  }

  /// Cancel any pending auto-clear. Call from emergency wipe so the
  /// emergency wipe's explicit `Clipboard.setData('')` is final.
  static void cancelPending() {
    _pendingClearTimer?.cancel();
    _pendingClearTimer = null;
    _lastEphemeralText = null;
  }
}
