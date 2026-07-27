#import "AudioEngineManager.h"

@interface AudioEngineManager ()
@property (nonatomic, strong) AVAudioEngine *engine;
@property (nonatomic, strong) AVAudioUnitTimePitch *pitchUnit;
@property (nonatomic, strong) AVAudioPlayerNode *musicPlayer;
@property (nonatomic, strong) AVAudioMixerNode *outgoingMixer;
@property (nonatomic, strong) AVAudioFile *musicFile;
@property (atomic, assign) BOOL running;
@property (atomic, strong) AVAudioPCMBuffer *latestBuffer;
@end

@implementation AudioEngineManager

+ (instancetype)sharedManager {
    static AudioEngineManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [AudioEngineManager new];
    });
    return instance;
}

- (void)startForCall {
    if (self.running) {
        // Never double-start. A stacked second engine is a classic cause
        // of doubled/echoey audio on the next call.
        [self stopForCall];
    }

    self.engine = [AVAudioEngine new];
    AVAudioInputNode *input = self.engine.inputNode;

    // --- Voice-processing OFF, intentionally ---
    // kAudioUnitSubType_VoiceProcessingIO adds the iOS system AEC, which
    // assumes your speaker output = what the *local* person hears, and
    // your mic input = what it needs to cancel. In a call-audio tweak,
    // the "output" you touch is the call uplink, not a real speaker the
    // mic can physically pick up. Turning voice processing on here makes
    // the system try to cancel a signal that was never acoustically
    // present, which is what produces the phantom "echo of the other
    // person's voice" bug. Keep this OFF for a call-injection tweak.
    [input setVoiceProcessingEnabled:NO error:nil];

    AVAudioFormat *inputFormat = [input inputFormatForBus:0];

    self.pitchUnit = [AVAudioUnitTimePitch new];
    self.pitchUnit.pitch = 0; // cents, set via setPitchCents:

    self.musicPlayer = [AVAudioPlayerNode new];
    self.outgoingMixer = [AVAudioMixerNode new];

    [self.engine attachNode:self.pitchUnit];
    [self.engine attachNode:self.musicPlayer];
    [self.engine attachNode:self.outgoingMixer];

    // Graph: mic -> pitch -> outgoingMixer
    //         musicPlayer ---------^
    // Nothing from the engine's main output (remote party) ever feeds
    // back into this graph. That separation is the fix.
    [self.engine connect:input to:self.pitchUnit format:inputFormat];
    [self.engine connect:self.pitchUnit to:self.outgoingMixer format:inputFormat];
    [self.engine connect:self.musicPlayer to:self.outgoingMixer format:inputFormat];

    // We don't route outgoingMixer to engine.mainMixerNode/output at all -
    // we tap it instead and hand buffers to Tweak.xm's render callback,
    // so nothing is ever played out loud (which is what would let the
    // mic re-pick-up its own processed signal - another common echo cause).
    __weak typeof(self) weakSelf = self;
    [self.outgoingMixer installTapOnBus:0
                              bufferSize:1024
                                  format:inputFormat
                                   block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
        [weakSelf handleOutgoingBuffer:buffer];
    }];

    NSError *err;
    [self.engine startAndReturnError:&err];
    if (err) {
        NSLog(@"[CallVoiceFX] engine start failed: %@", err);
        return;
    }
    self.running = YES;
}

- (void)stopForCall {
    [self.musicPlayer stop];
    [self.outgoingMixer removeTapOnBus:0];
    [self.engine stop];
    self.engine = nil;
    self.pitchUnit = nil;
    self.musicPlayer = nil;
    self.outgoingMixer = nil;
    self.running = NO;
}

- (void)setPitchCents:(float)cents {
    self.pitchUnit.pitch = cents;
}

- (void)playMusicOverMic:(NSURL *)fileURL loop:(BOOL)loop {
    NSError *err;
    self.musicFile = [[AVAudioFile alloc] initForReading:fileURL error:&err];
    if (err) {
        NSLog(@"[CallVoiceFX] could not open music file: %@", err);
        return;
    }
    [self.musicPlayer scheduleFile:self.musicFile atTime:nil completionHandler:^{
        if (loop) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self playMusicOverMic:fileURL loop:loop];
            });
        }
    }];
    [self.musicPlayer play];
}

- (void)stopMusicOverMic {
    [self.musicPlayer stop];
}

// Simple hand-off to whatever pulls buffers for the call's uplink render
// callback (implemented on the Tweak.xm side).
//
// IMPORTANT: pullNextOutgoingBuffer clears latestBuffer after returning it.
// The real-time render callback runs far more often than our tap fires,
// so without this a stale buffer would get resent on every subsequent
// render call until the next tap - which is a second, independent way to
// produce a "doubled/echoed" sound on the far end. Returning nil when
// there is nothing new yet is correct; the render callback should just
// pass through original mic audio for that one frame rather than resend
// old data.
- (void)handleOutgoingBuffer:(AVAudioPCMBuffer *)buffer {
    @synchronized (self) {
        self.latestBuffer = buffer;
    }
}

- (AVAudioPCMBuffer *)pullNextOutgoingBuffer {
    @synchronized (self) {
        AVAudioPCMBuffer *buf = self.latestBuffer;
        self.latestBuffer = nil;
        return buf;
    }
}

@end
