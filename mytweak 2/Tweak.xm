#import <CoreTelephony/CTCall.h>
#import <CoreTelephony/CTCallCenter.h>
#import <AudioToolbox/AudioToolbox.h>
#import "AudioEngineManager.h"

// ---------------------------------------------------------------------
// PART 1: know when a call starts/ends, so the engine only ever runs
// during an active call (running it outside a call is pointless and
// just wastes battery / risks stray audio).
// ---------------------------------------------------------------------

#define kPrefsPath @"/var/mobile/Library/Preferences/com.yourname.callvoicefx.plist"
#define kMusicFolder @"/var/mobile/Media/CallVoiceFX"

static BOOL gEnabled = YES;
static BOOL gMusicEnabled = NO;
static BOOL gMusicLoop = YES;
static float gPitchCents = 0;
static NSString *gMusicFile = nil;

static void CVFReloadPrefs(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath];
    gEnabled = prefs[@"CVFEnabled"] ? [prefs[@"CVFEnabled"] boolValue] : YES;
    gMusicEnabled = [prefs[@"CVFMusicEnabled"] boolValue];
    gMusicLoop = prefs[@"CVFMusicLoop"] ? [prefs[@"CVFMusicLoop"] boolValue] : YES;
    gPitchCents = prefs[@"CVFPitchCents"] ? [prefs[@"CVFPitchCents"] floatValue] : 0;
    gMusicFile = prefs[@"CVFMusicFile"];

    [[AudioEngineManager sharedManager] setPitchCents:gPitchCents];
    if (gMusicEnabled && gMusicFile) {
        NSString *fullPath = [kMusicFolder stringByAppendingPathComponent:gMusicFile];
        [[AudioEngineManager sharedManager] playMusicOverMic:[NSURL fileURLWithPath:fullPath] loop:gMusicLoop];
    } else {
        [[AudioEngineManager sharedManager] stopMusicOverMic];
    }
}

static void CVFPrefsChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                     const void *object, CFDictionaryRef userInfo) {
    CVFReloadPrefs();
}

%hook CTCallCenter

- (void)setCallEventHandler:(void (^)(CTCall *))callEventHandler {
    void (^wrapped)(CTCall *) = ^(CTCall *call) {
        if (!gEnabled) {
            if (callEventHandler) callEventHandler(call);
            return;
        }
        if ([call.callState isEqualToString:CTCallStateConnected]) {
            [[AudioEngineManager sharedManager] startForCall];
            CVFReloadPrefs(); // apply current pitch/music settings right when the call goes live
        } else if ([call.callState isEqualToString:CTCallStateDisconnected]) {
            [[AudioEngineManager sharedManager] stopForCall];
        }
        if (callEventHandler) callEventHandler(call);
    };
    %orig(wrapped);
}

%end

// ---------------------------------------------------------------------
// PART 2: hand our processed buffer to the call's OUTGOING (uplink) audio
// unit only - and ONLY that one specific unit instance.
//
// ROOT CAUSE OF THE "double echo, both sides hear the changed voice" BUG:
// mediaserverd runs AudioUnitRender for MANY audio units at once (system
// sounds, sidetone, media playback, the call itself...). The previous
// version hooked AudioUnitRender globally and matched on bus number
// alone, which is not a reliable enough filter - bus 1 is used by other
// units too, including the phone's normal SIDETONE unit (letting you
// faintly hear your own mic while on a call - that's a stock iOS
// feature, not a bug). Substituting sidetone's buffer is exactly why you
// heard your own altered voice, and because the substitution touched
// more than one render call per audio frame, the far end ended up
// receiving a duplicated copy too.
//
// Fix: only ever touch a render call once we've positively identified it
// as *the specific call unit instance*, captured via
// AudioComponentInstanceNew. Every other AudioUnitRender call, on any
// bus, is passed through completely untouched.
// ---------------------------------------------------------------------

static AudioUnit gCallAudioUnit = NULL; // set once we spot the real call unit

static OSStatus (*orig_AudioComponentInstanceNew)(AudioComponent inComponent, AudioUnit *outInstance);
static OSStatus replaced_AudioComponentInstanceNew(AudioComponent inComponent, AudioUnit *outInstance) {
    OSStatus status = orig_AudioComponentInstanceNew(inComponent, outInstance);
    if (status == noErr && outInstance && *outInstance) {
        AudioComponentDescription desc;
        AudioComponentGetDescription(inComponent, &desc);
        // VoiceProcessingIO (kAudioUnitSubType_VoiceProcessingIO = 'vpio')
        // is the subtype iOS actually uses for the phone call path.
        // Sidetone/system sounds use plain RemoteIO ('rioc'), so filtering
        // on 'vpio' specifically already excludes sidetone.
        if (desc.componentType == kAudioUnitType_Output &&
            desc.componentSubType == kAudioUnitSubType_VoiceProcessingIO) {
            gCallAudioUnit = *outInstance;
            NSLog(@"[CallVoiceFX] captured call audio unit instance: %p", (void *)gCallAudioUnit);
        }
    }
    return status;
}

static OSStatus (*orig_AudioUnitRender)(AudioUnit inUnit,
                                        AudioUnitRenderActionFlags *ioActionFlags,
                                        const AudioTimeStamp *inTimeStamp,
                                        UInt32 inOutputBusNumber,
                                        UInt32 inNumberFrames,
                                        AudioBufferList *ioData);

static OSStatus replaced_AudioUnitRender(AudioUnit inUnit,
                                         AudioUnitRenderActionFlags *ioActionFlags,
                                         const AudioTimeStamp *inTimeStamp,
                                         UInt32 inOutputBusNumber,
                                         UInt32 inNumberFrames,
                                         AudioBufferList *ioData) {
    OSStatus status = orig_AudioUnitRender(inUnit, ioActionFlags, inTimeStamp,
                                            inOutputBusNumber, inNumberFrames, ioData);

    // Hard gate: not the call unit at all -> never touch it. This is what
    // stops sidetone / other system audio from being altered.
    if (inUnit != gCallAudioUnit) {
        return status;
    }

    // Within the call unit, bus 1 = mic/uplink (what the OTHER person
    // receives). Bus 0 = downlink (what YOU hear from the earpiece,
    // i.e. the other person's real voice) - never substitute bus 0, or
    // the remote party's own voice gets processed and reflected, which
    // is a second, independent way to produce the exact bug you saw.
    if (inOutputBusNumber == 1) {
        AVAudioPCMBuffer *processed = [[AudioEngineManager sharedManager] pullNextOutgoingBuffer];
        if (processed && ioData->mNumberBuffers > 0) {
            AudioBufferList *processedABL = processed.audioBufferList;
            for (UInt32 i = 0; i < ioData->mNumberBuffers && i < processedABL->mNumberBuffers; i++) {
                UInt32 bytesToCopy = MIN(ioData->mBuffers[i].mDataByteSize,
                                          processedABL->mBuffers[i].mDataByteSize);
                memcpy(ioData->mBuffers[i].mData, processedABL->mBuffers[i].mData, bytesToCopy);
            }
        }
    }
    return status;
}

%ctor {
    MSHookFunction((void *)AudioComponentInstanceNew, (void *)replaced_AudioComponentInstanceNew, (void **)&orig_AudioComponentInstanceNew);
    MSHookFunction((void *)AudioUnitRender, (void *)replaced_AudioUnitRender, (void **)&orig_AudioUnitRender);

    CVFReloadPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                     NULL, CVFPrefsChangedCallback,
                                     CFSTR("com.yourname.callvoicefx/reload"),
                                     NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
