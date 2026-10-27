#import <XCTest/XCTest.h>
#import "../FarFlow/App/AudioEngineBridge.h"

@interface FFInvalidFormatEngine : AVAudioEngine
@end
@implementation FFInvalidFormatEngine
- (AVAudioInputNode *)inputNode {
    [NSException raise:NSInvalidArgumentException format:@"Synthetic microphone format mismatch"];
    return nil;
}
@end

@interface AudioEngineBridgeTests : XCTestCase
@end
@implementation AudioEngineBridgeTests
- (void)testNativeFormatExceptionReturnsRecoverableError {
    // No microphone is opened: the fake node accessor raises the same exception
    // family as AVFAudio. Swift's do/catch alone cannot handle this failure.
    NSError *error = [FFAudioEngineBridge startEngine:[FFInvalidFormatEngine new]
        deviceID:1 handler:^(AVAudioPCMBuffer *buffer) {}];
    XCTAssertEqualObjects(error.domain, @"FarFlow.Microphone");
    XCTAssertEqual(error.code, -4);
    XCTAssertTrue([error.localizedDescription containsString:@"microphone format changed"]);
}
@end
