// The guest's CoreAudio library ordinal is redirected to libCPCompat.dylib.
// AudioBridge implements only properties backed by the real AVAudioSession;
// the remaining native audio symbols are re-exported from AudioToolbox.
void CPCoreAudioFacade(void) {}
