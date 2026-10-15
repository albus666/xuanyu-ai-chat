/// Short app sounds must not take audio focus or change the native audio mode
/// while RTC owns the microphone and playback route.
class RtcAudioActivity {
  RtcAudioActivity._();

  static final _owners = Set<Object>.identity();
  static final _stoppers = <Future<void> Function()>{};

  static bool get active => _owners.isNotEmpty;

  static void registerSound(Future<void> Function() stop) =>
      _stoppers.add(stop);
  static void unregisterSound(Future<void> Function() stop) =>
      _stoppers.remove(stop);

  static Future<void> acquire(Object owner) async {
    if (!_owners.add(owner)) return;
    // Mark ownership before awaiting: queued sounds must also see the guard.
    // Drain pending player setup before the SDK configures its audio route.
    await Future.wait(List.of(_stoppers).map((stop) async {
      try {
        await stop().timeout(const Duration(seconds: 1));
      } catch (_) {
        // A failed sound player must not prevent connecting a call.
      }
    }));
  }

  static void release(Object owner) => _owners.remove(owner);
}
