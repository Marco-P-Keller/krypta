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

  /// Generation token incremented on every successful copy. Each clear
  /// path captures the generation it belongs to and only mutates global
  /// state if the current generation still matches. Without this, a
  /// timer-fired clear that is mid-`await getData` can race with a new
  /// `copyEphemeral` and orphan the new state in its `finally`.
  static int _generation = 0;

  /// Copy [text] to the clipboard and schedule an automatic clear after
  /// [_autoClearAfter]. If the user copies something else in the
  /// meantime, the auto-clear is a no-op (we don't clobber their copy).
  ///
  /// The previous timer is only cancelled after the new clipboard write
  /// succeeds. If the write throws, the existing auto-clear stays armed
  /// so the prior sensitive value still gets wiped on schedule.
  static Future<void> copyEphemeral(String text) async {
    final previousTimer = _pendingClearTimer;
    await Clipboard.setData(ClipboardData(text: text));
    previousTimer?.cancel();
    final gen = ++_generation;
    _lastEphemeralText = text;
    _pendingClearTimer = Timer(
      _autoClearAfter,
      () => _clearIfStillOurs(text, gen),
    );
  }

  static Future<void> _clearIfStillOurs(String expected, int gen) async {
    if (_generation != gen || _lastEphemeralText != expected) return;
    try {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (_generation == gen &&
          _lastEphemeralText == expected &&
          current?.text == expected) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } catch (_) {
      // Best effort — never throw out of a clipboard helper.
    } finally {
      if (_generation == gen && _lastEphemeralText == expected) {
        _lastEphemeralText = null;
        _pendingClearTimer = null;
      }
    }
  }

  /// Cancel pending auto-clear AND immediately wipe the clipboard if it
  /// still holds our last ephemeral value. Call from app lifecycle
  /// handlers (background/lock) — the 60s timer would not survive an
  /// app-kill, so we have to clear synchronously when we still can.
  static Future<void> clearEphemeralNow() async {
    final expected = _lastEphemeralText;
    final gen = _generation;
    _pendingClearTimer?.cancel();
    _pendingClearTimer = null;
    if (expected == null) return;
    await _clearIfStillOurs(expected, gen);
  }

  /// Cancel any pending auto-clear without touching the clipboard. Call
  /// from emergency wipe right before its explicit `Clipboard.setData('')`
  /// so a stale auto-clear timer cannot fire after the wipe. Bumps the
  /// generation so any in-flight `_clearIfStillOurs` becomes a no-op.
  static void cancelPending() {
    _pendingClearTimer?.cancel();
    _pendingClearTimer = null;
    _lastEphemeralText = null;
    _generation++;
  }
}
