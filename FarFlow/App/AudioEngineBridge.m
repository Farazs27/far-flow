#import "AudioEngineBridge.h"
#import <AudioToolbox/AudioToolbox.h>

static NSError *FFMicrophoneError(NSInteger code, NSString *reason) {
    return [NSError errorWithDomain:@"FarFlow.Microphone" code:code
                            userInfo:@{NSLocalizedDescriptionKey:reason}];
}

@implementation FFAudioEngineBridge
+ (NSError *)startEngine:(AVAudioEngine *)engine deviceID:(AudioDeviceID)deviceID
                  handler:(void (^)(AVAudioPCMBuffer *))handler {
    @try {
        AudioDeviceID device = deviceID;
        if (device == kAudioObjectUnknown) {
            AudioObjectPropertyAddress address = {kAudioHardwarePropertyDefaultInputDevice,
                kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
            UInt32 size = sizeof(device);
            OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, &device);
            if (status != noErr || device == kAudioObjectUnknown)
                return FFMicrophoneError(status, @"No system microphone is available. Choose an input in Settings.");
        }
        AVAudioInputNode *input = engine.inputNode;
        AudioUnit unit = input.audioUnit;
        if (!unit) return FFMicrophoneError(-1, @"The microphone could not be opened. Choose another input in Settings.");
        AudioDeviceID current = kAudioObjectUnknown;
        UInt32 size = sizeof(current);
        OSStatus read = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0, &current, &size);
        // Do not reconfigure the default device on every key press.
        // The engine owns an aggregate route when default input/output clocks
        // differ. Keep that route intact for System default; only override an
        // explicitly selected microphone.
        if (deviceID != kAudioObjectUnknown && (read != noErr || current != device)) {
            OSStatus status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0, &device, sizeof(device));
            if (status != noErr)
                return FFMicrophoneError(status, @"This microphone is unavailable. Choose another input in Settings.");
        }
        AVAudioFormat *hardware = [input inputFormatForBus:0];
        AVAudioFormat *output = [input outputFormatForBus:0];
        if (hardware.sampleRate <= 0 || hardware.channelCount == 0 ||
            output.sampleRate <= 0 || output.channelCount == 0)
            return FFMicrophoneError(-2, @"No microphone input is available. Check the selected input in Settings.");
        // On macOS the default output may be 44.1 kHz while this microphone is
        // 48 kHz. outputFormat (and a nil tap format) can retain that output rate
        // after CurrentDevice changes. Input nodes cannot convert: use their
        // hardware INPUT format, never the previous client/output format.
        [input installTapOnBus:0 bufferSize:2048 format:hardware block:^(AVAudioPCMBuffer *buffer, AVAudioTime *time) {
            handler(buffer);
        }];
        [engine prepare];
        NSError *error = nil;
        if (![engine startAndReturnError:&error]) {
            [self stopEngine:engine];
            return error ?: FFMicrophoneError(-3, @"The microphone could not start. Try again or select another input.");
        }
        return nil;
    } @catch (NSException *exception) {
        [self stopEngine:engine];
        return FFMicrophoneError(-4, @"The microphone format changed while starting. Try again or select another input in Settings.");
    }
}
+ (void)stopEngine:(AVAudioEngine *)engine {
    @try { [engine stop]; [engine.inputNode removeTapOnBus:0]; }
    @catch (NSException *exception) { /* The graph may already have been invalidated by macOS. */ }
}
@end
