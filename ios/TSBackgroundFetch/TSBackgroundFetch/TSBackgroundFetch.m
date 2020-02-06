//
//  RNBackgroundFetchManager.m
//  RNBackgroundFetch
//
//  Created by Christopher Scott on 2016-08-02.
//  Copyright © 2016 Christopher Scott. All rights reserved.
//

#import "TSBackgroundFetch.h"
#import "TSBGTask.h"

static NSString *const TAG = @"TSBackgroundFetch";


@implementation TSBackgroundFetch {
    BOOL enabled;

    NSMutableDictionary *responses;
    
    void (^completionHandler)(UIBackgroundFetchResult);
    BOOL hasReceivedEvent;
    BOOL launchedInBackground;
    
    NSTimer *bootBufferTimer;
}

+ (TSBackgroundFetch *)sharedInstance
{
    static TSBackgroundFetch *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [TSBGTask load];
        instance = [[self alloc] init];
    });
    return instance;
}

-(instancetype)init
{
    self = [super init];
    
    hasReceivedEvent = NO;
    
    _stopOnTerminate = YES;
    _configured = NO;
    _active = NO;
    
    bootBufferTimer = nil;
    responses = [NSMutableDictionary new];
                    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onAppTerminate) name:UIApplicationWillTerminateNotification object:nil];
    return self;
}

- (void) registerBackgroundFetchTask:(NSString*)identifier {
    if (@available(iOS 13.0, *)) {
        [TSBGTask registerForTaskWithIdentifier:identifier isFetch:YES];
    }
}

- (void) registerBackgroundProcessingTask:(NSString *)identifier {
    if (@available(iOS 13.0, *)) {        
        [TSBGTask registerForTaskWithIdentifier:identifier isFetch:NO];
    }
}

-(void) status:(void(^)(UIBackgroundRefreshStatus status))callback
{
    dispatch_async(dispatch_get_main_queue(), ^{
        callback([[UIApplication sharedApplication] backgroundRefreshStatus]);
    });
}

-(NSError*) scheduleFetchWithIdentifier:(NSString*)identifier delay:(NSTimeInterval)delay callback:(void (^)(NSString* taskId))callback {
    TSBGTask *tsTask = [TSBGTask get:identifier];
                
    if (!tsTask) {
        tsTask = [[TSBGTask alloc] initWithIdentifier:identifier delay:delay periodic:YES callback:callback];
    } else {
        tsTask.delay = delay;
        tsTask.callback = callback;
        //tsTask.stopOnTerminate = stopOnTerminate;
    }
    
    /*
    if ([TSBGTask useFetchTaskScheduler]) {
        if (@available(iOS 13.0, *)) {
            if (tsTask.task && !tsTask.executed) {
                [tsTask execute];
            } else if (tsTask.enabled) {
                return [tsTask scheduleFetchTask];
            }
        }
    } else {
        // Run callback immediately if app was launched due to background-fetch event.
        if (launchedInBackground && !tsTask.executed) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [tsTask execute];
            });
            return nil;
        } else {
            return [tsTask scheduleFetchTask];
        }
    }
     */
    return nil;
}

-(NSError*) scheduleProcessingTaskWithIdentifier:(NSString*)identifier delay:(NSTimeInterval)delay periodic:(BOOL)periodic callback:(void (^)(NSString* taskId))callback {
    TSBGTask *tsTask = [TSBGTask get:identifier];
    if (tsTask) {
        tsTask.delay = delay;
        tsTask.periodic = periodic;
        tsTask.callback = callback;
        if (@available(iOS 13.0, *)) {
            if (tsTask.task && !tsTask.executed) {
                [tsTask execute];
                return nil;
            } else {
                return [tsTask scheduleProcessingTask];
            }
        }
    } else {
        tsTask = [[TSBGTask alloc] initWithIdentifier:identifier delay:delay periodic:periodic callback:callback];
        tsTask.callback = callback;
    }
    
    NSError *error = [tsTask scheduleProcessingTask];
    if (error) {
        NSLog(@"[%@ scheduleTask] ERROR:  Failed to submit task request: %@", TAG, error);
    }
    return error;
}

-(BOOL) hasListener:(NSString*)identifier
{
    return ([TSBGTask get:identifier] != nil);
}

-(void) removeListener:(NSString*)identifier
{
    TSBGTask *tsTask = [TSBGTask get:identifier];
    if (tsTask) {
        [tsTask stop];
    }
}

- (NSError*) start:(NSString*)identifier
{
    NSLog(@"[%@ start] %@", TAG, identifier);
    
    TSBGTask *tsTask = [TSBGTask get:identifier];
    if (!tsTask) {
        NSString *msg = [NSString stringWithFormat:@"Could not find TSBGTask %@", identifier];
        NSLog(@"[%@ start] ERROR:  %@", TAG, msg);
        NSError *error = [[NSError alloc] initWithDomain:TAG code:-2 userInfo:@{NSLocalizedFailureReasonErrorKey:msg}];
        return error;
    }
    return [tsTask scheduleFetchTask];
}

- (void) stop:(NSString*)identifier
{
    NSLog(@"[%@ stop] %@", TAG, identifier);
    
    TSBGTask *tsTask = [TSBGTask get:identifier];
    [tsTask stop];    
}

// @deprecated
- (void) performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))handler applicationState:(UIApplicationState)state
{
    NSLog(@"[%@ performFetchWithCompletionHandler]", TAG);
    if (!hasReceivedEvent) {
        hasReceivedEvent = YES;
        launchedInBackground = (state == UIApplicationStateBackground);
    }
    _active = YES;
    @synchronized (responses) {
        [responses removeAllObjects];
    }
    if ([TSBGTask countFetch] > 0) {
        completionHandler = handler;
        NSArray *tasks = [TSBGTask tasks];
        @synchronized(tasks) {
            for (TSBGTask *tsTask in tasks) {
                if (tsTask.isFetchTask && tsTask.callback) {
                    [tsTask execute];
                }
            }
        }
    } else if (launchedInBackground) {
        // Wait for handlers to arrive
        completionHandler = handler;
    } else {
        // No handlers?
        handler(UIBackgroundFetchResultNoData);
    }
}

- (void) finish:(NSString*)taskId
{
    TSBGTask *tsTask = [TSBGTask get:taskId];
    
    if ([TSBGTask useProcessingTaskScheduler] || [TSBGTask useFetchTaskScheduler]) {
        if (@available(iOS 13.0, *)) {
            if (!taskId) { taskId = @"com.transistorsoft.fetch"; }
            if (tsTask) {
                [tsTask finish:YES];                
            } else {
                NSLog(@"[%@ finish] ERROR:  Failed to find task '%@'", TAG, taskId);
            }
        }
    } else {
        @synchronized (responses) {
            if (completionHandler == nil) {
                NSLog(@"[%@ finish] WARNING: completionHandler is nil.  No fetch event to finish.  Ignored", TAG);
                return;
            }
            if ([responses objectForKey:taskId]) {
                NSLog(@"[%@ finish] WARNING: finish already called for %@.  Ignored", TAG, taskId);
                return;
            }
            if (![self hasListener:tsTask.identifier]) {
                NSLog(@"%@ finish] WARNING: no listener found to finish for %@.  Ignored", TAG, taskId);
                return;
            }
            
            NSLog(@"[%@ finish]: %@", TAG, tsTask.identifier);
            [responses setObject:@(UIBackgroundFetchResultNewData) forKey:tsTask.identifier];
            
            if (launchedInBackground && (bootBufferTimer == nil)) {
                // Give other modules 5 second buffer before we finish.  Other modules may not yet have registed their callback when booted in background
                bootBufferTimer = [NSTimer timerWithTimeInterval:5 target:self selector:@selector(doFinish) userInfo:nil repeats:NO];
                [[NSRunLoop mainRunLoop] addTimer:bootBufferTimer forMode:NSRunLoopCommonModes];
                
            } else {
                [self doFinish];
            }
        }
    }
}

- (void) onBootBufferTimeout:(NSTimer*)timer
{
    [self doFinish];
}

- (void) doFinish
{
    if (bootBufferTimer != nil) {
        [bootBufferTimer invalidate];
        bootBufferTimer = nil;
    }
    
    @synchronized (responses) {                
        if ([[responses allKeys] count] == [TSBGTask countFetch]) {
            NSUInteger fetchResult = UIBackgroundFetchResultNewData;
            for (NSString* componentName in responses) {
                id response = [responses objectForKey:componentName];
                if ([response integerValue] == UIBackgroundFetchResultFailed) {
                    fetchResult = UIBackgroundFetchResultFailed;
                    break;
                } else if ([response integerValue] == UIBackgroundFetchResultNewData) {
                    fetchResult = UIBackgroundFetchResultNewData;
                }
            }
            NSLog(@"[%@ doFinish] Complete, UIBackgroundFetchResult: %lu, responses: %lu", TAG, (long)fetchResult, (long)[responses count]);
            completionHandler(fetchResult);
            _active = NO;
            [responses removeAllObjects];
            completionHandler = nil;
                        
            launchedInBackground = NO;
        }
    }
}

- (void) onAppTerminate
{
    NSLog(@"[%@ onAppTerminate]", TAG);
    if (_stopOnTerminate) {
        //[self stop];
    }
}

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [responses removeAllObjects];
}
@end

