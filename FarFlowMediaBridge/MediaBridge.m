#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef void (*FFPlaying)(dispatch_queue_t, void (^)(BOOL));
typedef void (*FFPID)(dispatch_queue_t, void (^)(int));
typedef BOOL (*FFSend)(unsigned int, CFDictionaryRef);

// A local stdin/stdout transport hosted by the macOS Perl platform binary.
// MediaRemote access changed in macOS 15.4; see docs/ARCHITECTURE.md.
__attribute__((visibility("default"))) void FarFlowMediaRun(void) {
    @autoreleasepool {
        void *library = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        FFPlaying playing = library ? dlsym(library, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") : NULL;
        FFPID pid = library ? dlsym(library, "MRMediaRemoteGetNowPlayingApplicationPID") : NULL;
        FFSend send = library ? dlsym(library, "MRMediaRemoteSendCommand") : NULL;
        if (!playing || !pid || !send) return;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            char line[128];
            while (fgets(line, sizeof(line), stdin)) {
                unsigned long long request = 0; int command = -9;
                if (sscanf(line, "%llu %d", &request, &command) != 2) continue;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (command == -1) {
                        pid(dispatch_get_main_queue(), ^(int process) {
                            playing(dispatch_get_main_queue(), ^(BOOL active) {
                                printf("{\"id\":%llu,\"pid\":%d,\"playing\":%s}\n", request, process, active ? "true" : "false");
                                fflush(stdout);
                            });
                        });
                    } else if (command == 0 || command == 1) {
                        BOOL accepted = send((unsigned int)command, NULL);
                        printf("{\"id\":%llu,\"accepted\":%s}\n", request, accepted ? "true" : "false");
                        fflush(stdout);
                    }
                });
            }
            dispatch_async(dispatch_get_main_queue(), ^{ exit(0); });
        });
        dispatch_main();
    }
}
