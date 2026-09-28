import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/catalog.dart';
import '../playback/timeline.dart';

/// The listener's preferences, saved on the device.
class Settings extends ChangeNotifier {
  Settings(this.prefs)
      : _pauseLength = PauseLength.byName(prefs.getString(_pauseKey)),
        _preferredVoice = prefs.getString(_voiceKey),
        _downloadAllVoices = prefs.getBool(_allVoicesKey) ?? false;

  static const _pauseKey = 'pauseLength';
  static const _voiceKey = 'preferredVoice';
  static const _allVoicesKey = 'downloadAllVoices';

  final SharedPreferences prefs;

  PauseLength _pauseLength;
  String? _preferredVoice;
  bool _downloadAllVoices;

  PauseLength get pauseLength => _pauseLength;
  set pauseLength(PauseLength value) {
    if (value == _pauseLength) return;
    _pauseLength = value;
    prefs.setString(_pauseKey, value.name);
    notifyListeners();
  }

  /// Name of the voice to pick whenever a session offers it.
  String? get preferredVoice => _preferredVoice;
  set preferredVoice(String? value) {
    if (value == _preferredVoice) return;
    _preferredVoice = value;
    value == null ? prefs.remove(_voiceKey) : prefs.setString(_voiceKey, value);
    notifyListeners();
  }

  /// Whether "download group/everything" fetches every voice or just one.
  bool get downloadAllVoices => _downloadAllVoices;
  set downloadAllVoices(bool value) {
    if (value == _downloadAllVoices) return;
    _downloadAllVoices = value;
    prefs.setBool(_allVoicesKey, value);
    notifyListeners();
  }

  /// The voice a session should start with: the preferred one if the session
  /// has it, otherwise its first voice.
  Voice voiceFor(Session session) {
    final preferred = _preferredVoice?.toLowerCase();
    return session.voices.firstWhere(
      (v) => v.name.toLowerCase() == preferred,
      orElse: () => session.voices.first,
    );
  }

  /// Voices that bulk downloads should fetch for [sessions].
  List<Voice> voicesToDownload(Iterable<Session> sessions) => [
        for (final s in sessions) ...(_downloadAllVoices ? s.voices : [voiceFor(s)]),
      ];
}
