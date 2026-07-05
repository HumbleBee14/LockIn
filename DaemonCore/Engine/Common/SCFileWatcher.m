//
//  SCFileWatcher.m
//  SelfControl
//
//  Created by Charlie Stigler on 3/20/21.
//

#import "SCFileWatcher.h"
#include <CoreServices/CoreServices.h>

@interface SCFileWatcher ()
// keeps the FSEvents callback queue alive for the stream's lifetime
@property (strong) dispatch_queue_t eventQueue;
@end

@implementation SCFileWatcher

static void SCFileWatcherGlobalCallback(
    ConstFSEventStreamRef streamRef,
    void *callbackCtxInfo,
    size_t numEvents,
    void *eventPaths, // CFArrayRef
    const FSEventStreamEventFlags eventFlags[],
    const FSEventStreamEventId eventIds[])
{
    NSArray* paths = (__bridge NSArray*)eventPaths;
    SCFileWatcher* watcher = (__bridge SCFileWatcher*)callbackCtxInfo;
    [watcher directoryWatcherTriggered: paths flags: eventFlags];
}

- (void)directoryWatcherTriggered:(NSArray<NSString*>*)eventPaths flags:(const FSEventStreamEventFlags[])eventFlags {
    BOOL triggerFileWatcher = NO;

    for (unsigned int i = 0; i < eventPaths.count; i++) {
        NSString* eventPath = [eventPaths[i] stringByStandardizingPath];
        
        if ([eventPath isEqualToString: self.filePath]) {
            triggerFileWatcher = YES;
        }
    }
    
    if (triggerFileWatcher) {
        self.callbackBlock(nil);
    }
}

+ (instancetype)watcherWithFile:(NSString*)watchPath block:(void(^)(NSError* error))callbackBlock {
    return [[SCFileWatcher new] initWithFile: watchPath block: callbackBlock];
}

- (instancetype)initWithFile:(NSString*)watchPath block:(void(^)(NSError* error))callbackBlock {
    self = [super init];

    NSFileManager* fileMan = [NSFileManager defaultManager];
    _filePath = [watchPath stringByStandardizingPath];
    BOOL isDirectory;
    [fileMan fileExistsAtPath: self.filePath isDirectory: &isDirectory];
    
    NSString* directoryPath;
    if (isDirectory) {
        directoryPath = self.filePath;
    } else {
        directoryPath = [self.filePath stringByDeletingLastPathComponent];
    }

    FSEventStreamContext callbackCtx;
    callbackCtx.version = 0;
    callbackCtx.info = (__bridge void *)self;
    callbackCtx.retain = NULL;
    callbackCtx.release = NULL;
    callbackCtx.copyDescription = NULL;

    FSEventStreamRef eventStream = FSEventStreamCreate(
        kCFAllocatorDefault,
        &SCFileWatcherGlobalCallback,
        &callbackCtx, // context
        (__bridge CFArrayRef)@[directoryPath],
        kFSEventStreamEventIdSinceNow,
        1.5, // seconds to throttle callbacks
        kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagMarkSelf | kFSEventStreamCreateFlagIgnoreSelf | kFSEventStreamCreateFlagFileEvents
    );
    
    // dispatch-queue scheduling (the run-loop API is deprecated); callbacks arrive on this serial queue
    dispatch_queue_t eventQueue = dispatch_queue_create("org.eyebeam.SelfControl.filewatcher", DISPATCH_QUEUE_SERIAL);
    FSEventStreamSetDispatchQueue(eventStream, eventQueue);
    if (!FSEventStreamStart(eventStream)) {
        NSLog(@"WARNING: failed to start watching file %@", watchPath);
        FSEventStreamInvalidate(eventStream);
        FSEventStreamRelease(eventStream);
        return nil;
    }
    _eventQueue = eventQueue;
    
    _eventStream = eventStream;
    _callbackBlock = callbackBlock;
    
    return self;
}

- (void)stopWatching {
    FSEventStreamStop(self.eventStream);
    // FSEventStreamInvalidate unschedules from the dispatch queue; no separate unschedule call exists
    FSEventStreamInvalidate(self.eventStream);
    FSEventStreamRelease(self.eventStream);

    _eventStream = NULL;
    self.eventQueue = nil;
}

@end
