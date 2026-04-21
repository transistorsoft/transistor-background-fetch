//
//  TSBackgroundFetch.m
//  TSBackgroundFetch
//
//  Created by Christopher Scott on 2016-08-02.
//  Copyright © 2016 Christopher Scott. All rights reserved.
//

#import "TSBackgroundFetch.h"
#import "TSBGTask.h"
#import "TSBGAppRefreshSubscriber.h"

static NSString *const TAG = @"TSBackgroundFetch";

static NSString *const TRANSISTOR_IDENTIFIER_PREFIX = @"com.transistorsoft";
static NSString *const BACKGROUND_REFRESH_TASK_ID   = @"com.transistorsoft.fetch";
static NSString *const PERMITTED_IDENTIFIERS_KEY    = @"BGTaskSchedulerPermittedIdentifiers";

@implementation TSBackgroundFetch {
    BOOL enabled;
    BOOL launched;

    NSTimeInterval minimumFetchInterval;
    id bgAppRefreshTask;
    BOOL fetchScheduled;
}

+(void)load {
    // Create singleton early so it can observe UIApplicationDidFinishLaunchingNotification
    // and auto-register BGTask handlers before app launch completes.
    [self sharedInstance];
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
    launched = NO;
    minimumFetchInterval = UIApplicationBackgroundFetchIntervalMinimum;

    _fetchTaskId = BACKGROUND_REFRESH_TASK_ID;
    _stopOnTerminate = YES;
    _configured = NO;
    _active = NO;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didFinishLaunching) name:UIApplicationDidFinishLaunchingNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onAppTerminate) name:UIApplicationWillTerminateNotification object:nil];
    return self;
}

- (void) didFinishLaunching {
    if (launched) return;
    launched = YES;

    NSArray *permittedIdentifiers = [[NSBundle mainBundle] objectForInfoDictionaryKey:PERMITTED_IDENTIFIERS_KEY];
    if (!permittedIdentifiers) return;

    for (NSString *identifier in permittedIdentifiers) {
        if ([identifier isEqualToString:BACKGROUND_REFRESH_TASK_ID]) {
            [self registerAppRefreshTask];
        } else if ([self isTransistorTask:identifier]) {
            // Only register tasks prefixed with "com.transistorsoft".
            [self registerBGProcessingTask:identifier];
        }
    }
}

-(BOOL) isTransistorTask:(NSString*)identifier
{
    return [identifier rangeOfString:TRANSISTOR_IDENTIFIER_PREFIX].location != NSNotFound;
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
            if (error) {
                if (error.code == BGTaskSchedulerErrorCodeUnavailable) {
                    // Handle case for Simulator where BGTaskScheduler doesn't work.
                    NSLog(@"[%@] BGTaskScheduler unavailable — falling back to legacy API. %@", TAG, error);
                    [self setMinimumFetchInterval];
                    error = nil;
                } else {
                    NSLog(@"[%@ scheduleBGAppRefresh] ERROR: %@", TAG, error);
                }
            } else {
                NSLog(@"[%@ scheduleBGAppRefresh] submitted BGAppRefreshTaskRequest, earliestBeginDate: %@", TAG, request.earliestBeginDate);
            }
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
        fetchScheduled = NO;
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[UIApplication sharedApplication] setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalNever];
        });
    }
}

-(void) setMinimumFetchInterval {
    __block NSTimeInterval interval = minimumFetchInterval;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] setMinimumBackgroundFetchInterval:interval];
    });
}

/// Callback from BGTaskScheduler
-(void) handleBGAppRefreshTask:(BGAppRefreshTask*)task API_AVAILABLE(ios(13.0)) {
    NSLog(@"[%@ handleBGAppRefreshTask]", TAG);
            
    __block BGAppRefreshTask *weakTask = task;
    task.expirationHandler = ^{
        NSLog(@"[%@ handleBGAppRefreshTask] WARNING: expired before #finish was executed.", TAG);
        // If any registered listeners has registered an onTimeout callback, let them run and execute #finish as desired.  Otherwise, automatically setTaskCompleted immediately.
        if (![TSBGAppRefreshSubscriber onTimeout] && weakTask) [weakTask setTaskCompletedWithSuccess:NO];
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
    
    _completionHandler = handler;
    if (_backgroundTask != UIBackgroundTaskInvalid) [[UIApplication sharedApplication] endBackgroundTask:_backgroundTask];
    // Create a UIBackgroundTask for detecting task-expiration with old API.
    _backgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        if (self.completionHandler) {
            [TSBGAppRefreshSubscriber onTimeout];
        }
        @synchronized (self) {
            [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTask];
            self.backgroundTask = UIBackgroundTaskInvalid;
        }
    }];
    
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

-(NSError*) scheduleProcessingTaskWithIdentifier:(NSString*)identifier type:(NSInteger)type delay:(NSTimeInterval)delay periodic:(BOOL)periodic callback:(void (^)(NSString* taskId, BOOL timeout))callback {
    return [self scheduleProcessingTaskWithIdentifier:identifier type:(NSInteger)type delay:delay periodic:periodic requiresExternalPower:NO requiresNetworkConnectivity:NO callback:callback];
}

-(NSError*) scheduleProcessingTaskWithIdentifier:(NSString*)identifier type:(NSInteger)type delay:(NSTimeInterval)delay periodic:(BOOL)periodic requiresExternalPower:(BOOL)requiresExternalPower requiresNetworkConnectivity:(BOOL)requiresNetworkConnectivity callback:(void (^)(NSString* taskId, BOOL timeout))callback {
    
    TSBGTask *tsTask = [TSBGTask get:identifier];
    if (tsTask) {
        tsTask.type = type;
        tsTask.delay = delay;
        tsTask.periodic = periodic;
        tsTask.callback = callback;
        tsTask.requiresNetworkConnectivity = requiresNetworkConnectivity;
        tsTask.requiresExternalPower = requiresExternalPower;
        if (@available(iOS 13.0, *)) {
            if (tsTask.task && !tsTask.executed) {
                [tsTask execute];
                return nil;
            } else {
                return [tsTask schedule];
            }
        }
    } else {
        tsTask = [[TSBGTask alloc] initWithIdentifier:identifier
                                                 type:type
                                                delay:delay
                                             periodic:periodic
                                requiresExternalPower:requiresExternalPower
                          requiresNetworkConnectivity:requiresNetworkConnectivity
                                             callback:callback];
        tsTask.callback = callback;
    }
    
    NSError *error = [tsTask schedule];
    if (error) {
        NSLog(@"[%@ scheduleTask] ERROR:  Failed to submit task request: %@", TAG, error);
    }
    return error;
}

/// @deprecated.
-(void) addListener:(NSString*)componentName callback:(void (^)(NSString* componentName))callback {
    [self addListener:componentName callback:callback timeout:nil];
}

-(void) addListener:(NSString*)componentName callback:(void (^)(NSString* componentName))callback timeout:(void (^)(NSString* componentName))timeout {
    TSBGAppRefreshSubscriber *subscriber = [TSBGAppRefreshSubscriber get:componentName];
    if (subscriber) {
        subscriber.callback = callback;
        subscriber.timeout = timeout;
    } else {
        subscriber = [[TSBGAppRefreshSubscriber alloc] initWithIdentifier:componentName callback:callback timeout:timeout];
    }
    if (bgAppRefreshTask || _completionHandler) {
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
            [self _finishProcessingTask:tsTask];
        }
        return;
    }
    [self _finishAppRefreshWithTaskId:taskId];
}

/// Complete a BGProcessingTask.
- (void) _finishProcessingTask:(TSBGTask*)tsTask {
    [tsTask finish:YES];
}

/// Complete a background app-refresh event.
/// Uses subscriber counting: the BGTask (or legacy completionHandler) is signalled
/// only once ALL registered subscribers have called finish:.
- (void) _finishAppRefreshWithTaskId:(NSString*)taskId {
    if (!bgAppRefreshTask && !_completionHandler) {
        NSLog(@"[%@ finish] %@ Called without a task to finish.  Ignoring.", TAG, taskId);
        return;
    }

    TSBGAppRefreshSubscriber *subscriber = [TSBGAppRefreshSubscriber get:taskId];
    if (!subscriber) {
        NSLog(@"[%@ finish] Failed to find Fetch subscriber %@", TAG, taskId);
        return;
    }

    [subscriber finish];

    NSArray *subscribers = [[TSBGAppRefreshSubscriber subscribers] allValues];
    long total = [subscribers count];
    long count = 0;
    for (TSBGAppRefreshSubscriber *s in subscribers) {
        if (s.finished) count++;
    }
    NSLog(@"[%@ finish] %@ (%ld of %ld)", TAG, subscriber.identifier, count, total);

    if (total != count) return;

    // All subscribers have finished — signal the OS.
    if (bgAppRefreshTask) {
        if (@available(iOS 13.0, *)) {
            [(BGAppRefreshTask*) bgAppRefreshTask setTaskCompletedWithSuccess:YES];
        }
        bgAppRefreshTask = nil;
    } else if (_completionHandler) {
        _completionHandler(UIBackgroundFetchResultNewData);
        _completionHandler = nil;
        @synchronized (self) {
            if (_backgroundTask != UIBackgroundTaskInvalid) {
                [[UIApplication sharedApplication] endBackgroundTask:_backgroundTask];
                _backgroundTask = UIBackgroundTaskInvalid;
            }
        }
    }
}

- (void) onAppTerminate {
    NSLog(@"[%@ onAppTerminate] stopOnTerminate=%d", TAG, _stopOnTerminate);
    // [self stop] is intentionally not called here.
    // Tasks are persisted in NSUserDefaults and re-registered on next launch
    // via didFinishLaunching. Plugins manage their own listener teardown.
}

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
@end

