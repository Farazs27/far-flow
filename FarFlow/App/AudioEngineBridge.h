#import <AVFoundation/AVFoundation.h>
#import <CoreAudio/CoreAudio.h>

NS_ASSUME_NONNULL_BEGIN
/// AVAudioEngine can raise Objective-C exceptions that Swift do/catch cannot catch.
@interface FFAudioEngineBridge : NSObject
+ (nullable NSError *)startEngine:(AVAudioEngine *)engine
                         deviceID:(AudioDeviceID)deviceID
                          handler:(void (^)(AVAudioPCMBuffer *))handler
    NS_SWIFT_NAME(start(_:deviceID:handler:));
+ (void)stopEngine:(AVAudioEngine *)engine NS_SWIFT_NAME(stop(_:));
@end
NS_ASSUME_NONNULL_END
