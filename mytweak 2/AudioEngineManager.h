#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

// Singleton that owns the entire local audio graph for the tweak.
// IMPORTANT DESIGN RULE (fixes the "listener's own voice echoes back" bug):
// This engine only ever reads/writes the MICROPHONE (input) path.
// It never taps, records, or mixes the REMOTE/OUTPUT path (the other person's
// voice coming out of the earpiece/speaker). Looping that signal back into
// the input is what causes the far-end party to hear their own voice
// bounced back to them. Keep those two paths fully separate.
@interface AudioEngineManager : NSObject

+ (instancetype)sharedManager;

// Call once when a call starts (e.g. from a CoreTelephony/CallKit hook).
- (void)startForCall;

// Call when the call ends. Always tear the graph down fully or the next
// call will layer a second engine on top of the first -> doubled/echoey audio.
- (void)stopForCall;

// Pitch shift in cents, e.g. -1200 = one octave down, +1200 = one octave up.
- (void)setPitchCents:(float)cents;

// Starts/stops mixing a music file INTO the outgoing mic signal
// (i.e. "phát nhạc qua mic" - the other person hears the mic + the music).
- (void)playMusicOverMic:(NSURL *)fileURL loop:(BOOL)loop;
- (void)stopMusicOverMic;

// The buffer the call's outgoing (uplink) audio unit should actually send.
// This is the ONLY thing that should ever be handed back to the telephony
// render callback in Tweak.xm.
- (AVAudioPCMBuffer *)pullNextOutgoingBuffer;

@end
