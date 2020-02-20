//
//  RNBackgroundFetchManager.m
//  RNBackgroundFetch
//
//  Created by Christopher Scott on 2016-08-02.
//  Copyright © 2016 Christopher Scott. All rights reserved.
//

#import "TSBackgroundFetch.h"
#import "TSBGTask.h"
#import "TSBGAppRefreshSubscriber.h"

static NSString *const TAG = @"TSBackgroundFetch";

static NSString *const BACKGROUND_REFRESH_TASK_ID   = @"com.transistorsoft.fetch";
static NSString *const PERMITTED_IDENTIFIERS_KEY    = @"BGTaskSchedulerPermittedIdentifiers";

@implementation TSBackgroundFetch {
    BOOL enabled;
    
    NSTimeInterval minimumFetchInterval;
        
    id bgAppRefreshTask;
    void (^completionHandler)(UIBackgroundFetchResult);
    BOOL fetchScheduled;
}

+ (TSBackgroundFetch *)sharedInstance
{
    static TSBackgroundFetch *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [TSBGTask load];
        [TSBGAppRefreshSubscriber load];
        instance = [[self alloc] init];
    });
    return instance;
}

-(instancetype)init
{
    self = [super init];
        
    fetchScheduled = NO;

    minimumFetchInterval = UIApplicationBackgroundFetchIntervalMinimum;
    
    _fetchTaskId = BACKGROUND_REFRESH_TASK_ID;
    _stopOnTerminate = YES;
    _configured = NO;
    _active = NO;
                            
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onAppTerminate) name:UIApplicationWillTerminateNotification object:nil];
    return self;
}

- (void) didFinishLaunching {
    NSArray *permittedIdentifiers = [[NSBundle mainBundle] objectForInfoDictionaryKey:PERMITTED_IDENTIFIERS_KEY];
    if (!permittedIdentifiers) return;

    for (NSString *identifier in permittedIdentifiers) {
        if ([identifier isEqualToString:BACKGROUND_REFRESH_TASK_ID]) {
            [self registerAppRefreshTask];
        } else {
            [self registerBGProcessingTask:identifier];
        }
    }
}

- (void) registerAppRefreshTask {
    if (@available(iOS 13.0, *)) {
        [TSBGAppRefreshSubscriber registerTaskScheduler];
        
        [[BGTaskScheduler sharedScheduler] registerForTaskWithIdentifier:BACKGROUND_REFRESH_TASK_ID usingQueue:nil launchHandler:^(BGTask* task) {
            [self handleBGAppRefreshTask:(BGAppRefreshTask*)task];
        }];
    }
}

- (void) registerBGProcessingTask:(NSString *)identifier {
    if (@available(iOS 13.0, *)) {
        [TSBGTask registerForTaskWithIdentifier:identifier];
    }
}

- (NSError*) scheduleBGAppRefresh {
    if (fetchScheduled) return nil;
    
    NSLog(@"[%@ scheduleBGAppRefresh] %@", TAG, BACKGROUND_REFRESH_TASK_ID);
        
    NSError *error = nil;
    
    if (@available (iOS 13.0, *)) {
        if ([TSBGAppRefreshSubscriber useTaskScheduler]) {
            BGTaskScheduler *scheduler = [BGTaskScheduler sharedScheduler];
            BGAppRefreshTaskRequest *request = [[BGAppRefreshTaskRequest alloc] initWithIdentifier:BACKGROUND_REFRESH_TASK_ID];
            request.earliestBeginDate = [NSDate dateWithTimeIntervalSinceNow:minimumFetchInterval];
            [scheduler submitTaskRequest:request error:&error];
        } else {
            [self setMinimumFetchInterval];
        }
    } else {
        [self setMinimumFetchInterval];
    }
    if (!error) {
        fetchScheduled = YES;
    }
    return error;
}

-(void) cancelBGAppRefresh {
    if (@available (iOS 13.0, *)) {
        BGTaskScheduler *scheduler = [BGTaskScheduler sharedScheduler];
        [scheduler cancelTaskRequestWithIdentifier:BACKGROUND_REFRESH_TASK_ID];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[UIApplication sharedApplication] setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalNever];
        });
    }
}

-(void) setMinimumFetchInterval {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] setMinimumBackgroundFetchInterval:minimumFetchInterval];
    });
}

/// Callback from BGTaskScheduler
-(void) handleBGAppRefreshTask:(BGAppRefreshTask*)task API_AVAILABLE(ios(13.0)) {
    NSLog(@"[%@ handleBGAppRefreshTask]", TAG);
            
    __block BGAppRefreshTask *weakTask = task;
    task.expirationHandler = ^{
        NSLog(@"[%@ handleBGAppRefreshTask] WARNING: expired before #finish was executed.", TAG);
        if (weakTask) [weakTask setTaskCompletedWithSuccess:NO];
    };
    
    fetchScheduled = NO;
    [self scheduleBGAppRefresh];
    
    bgAppRefreshTask = task;
    [TSBGAppRefreshSubscriber execute];
}

/// @deprecated Old-syle fetch callback.
- (void) performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))handler applicationState:(UIApplicationState)state {
    NSLog(@"[%@ performFetchWithCompletionHandler]", TAG);
        
    fetchScheduled = NO;
    [self scheduleBGAppRefresh];
    
    completionHandler = handler;
    [TSBGAppRefreshSubscriber execute];
}

-(void) status:(void(^)(UIBackgroundRefreshStatus status))callback
{
    dispatch_async(dispatch_get_main_queue(), ^{
        callback([[UIApplication sharedApplication] backgroundRefreshStatus]);
    });
}

-(void) configure:(NSTimeInterval)delay callback:(void(^)(UIBackgroundRefreshStatus status))callback {
    _configured = YES;
    minimumFetchInterval = delay;
    [self status:^(UIBackgroundRefreshStatus status) {
        if (status == UIBackgroundRefreshStatusAvailable) {
            [self scheduleBGAppRefresh];
        }
        callback(status);
    }];
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
                return [tsTask schedule];
            }
        }
    } else {
        tsTask = [[TSBGTask alloc] initWithIdentifier:identifier delay:delay periodic:periodic callback:callback];
        tsTask.callback = callback;
    }
    
    NSError *error = [tsTask schedule];
    if (error) {
        NSLog(@"[%@ scheduleTask] ERROR:  Failed to submit task request: %@", TAG, error);
    }
    return error;
}

-(void) addListener:(NSString*)componentName callback:(void (^)(NSString* componentName))callback {
    TSBGAppRefreshSubscriber *subscriber = [TSBGAppRefreshSubscriber get:componentName];
    if (subscriber) {
        subscriber.callback = callback;
    } else {
        subscriber = [[TSBGAppRefreshSubscriber alloc] initWithIdentifier:componentName callback:callback];
    }
    if (bgAppRefreshTask || completionHandler) {
        [subscriber execute];
    }
}

-(BOOL) hasListener:(NSString*)identifier {
    return ([TSBGAppRefreshSubscriber get:identifier] != nil);
}

-(void) removeListener:(NSString*)identifier {
    TSBGAppRefreshSubscriber *subscriber = [TSBGAppRefreshSubscriber get:identifier];
    if (!subscriber) {
        NSLog(@"[%@ removeListener] WARNING:  Failed to find listener for identifier: %@", TAG, identifier);
        return;
    }
    [subscriber destroy];
    if ([[TSBGAppRefreshSubscriber subscribers] count] < 1) {
        [self cancelBGAppRefresh];
    }
}

- (NSError*) start:(NSString*)identifier {
    NSLog(@"[%@ start] %@", TAG, identifier);
    
    if (!identifier) {
        return [self scheduleBGAppRefresh];
    } else {
        TSBGTask *tsTask = [TSBGTask get:identifier];
        if (!tsTask) {
            NSString *msg = [NSString stringWithFormat:@"Could not find TSBGTask %@", identifier];
            NSLog(@"[%@ start] ERROR:  %@", TAG, msg);
            NSError *error = [[NSError alloc] initWithDomain:TAG code:-2 userInfo:@{NSLocalizedFailureReasonErrorKey:msg}];
            return error;
        }
        tsTask.enabled = YES;
        [tsTask save];
        return [tsTask schedule];
    }
}

- (void) stop:(NSString*)identifier {
    NSLog(@"[%@ stop] %@", TAG, identifier);
    if (!identifier) {
        NSArray *tsTasks = [TSBGTask tasks];
        for (TSBGTask *tsTask in tsTasks) {
            [tsTask stop];
        }
    } else {
        TSBGTask *tsTask = [TSBGTask get:identifier];
        [tsTask stop];
    }
}

- (void) finish:(NSString*)taskId {
    if (!taskId) { taskId = BACKGROUND_REFRESH_TASK_ID; }

    TSBGTask *tsTask = [TSBGTask get:taskId];
    if (tsTask) {
        if (@available(iOS 13.0, *)) {
            [tsTask finish:YES];
        }
        return;
    }
    
    if (!bgAppRefreshTask && !completionHandler) {
        NSLog(@"[%@ finish] %@ Called without a task to finish.  Ignoring.", TAG, taskId);
        return;
    }
                
    TSBGAppRefreshSubscriber *subscriber = [TSBGAppRefreshSubscriber get:taskId];
    if (subscriber) {
        [subscriber finish];
        
        NSArray *subscribers = [[TSBGAppRefreshSubscriber subscribers] allValues];
        long total = [subscribers count];
        long count = 0;
        
        for (TSBGAppRefreshSubscriber *subscriber in subscribers) {
            if (subscriber.finished) count++;
        }
        
        NSLog(@"[%@ finish] %@ (%ld of %ld)", TAG, subscriber.identifier, count, total);

        if (total != count) return;

        // If we arrive here without jumping out of foreach above, all subscribers are finished.
        if (bgAppRefreshTask) {
            // If we arrive here, all Fetch tasks must be finished.
            if (@available(iOS 13.0, *)) {
                [(BGAppRefreshTask*) bgAppRefreshTask setTaskCompletedWithSuccess:YES];
            }
            bgAppRefreshTask = nil;
        } else if (completionHandler) {
            completionHandler(UIBackgroundFetchResultNewData);
            completionHandler = nil;
        }
    } else {
        NSLog(@"[%@ finish] Failed to find Fetch subscriber %@", TAG, taskId);
    }
}

- (void) onAppTerminate {
    NSLog(@"[%@ onAppTerminate]", TAG);
    if (_stopOnTerminate) {
        //[self stop];
    }
}

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
@end

