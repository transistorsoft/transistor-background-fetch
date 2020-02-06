//
//  TSBGTask.m
//  TSBackgroundFetch
//
//  Created by Christopher Scott on 2020-01-23.
//  Copyright © 2020 Christopher Scott. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "TSBGTask.h"

static NSString *const TAG = @"TSBackgroundFetch";
static NSString *const TASKS_STORAGE_KEY = @"TSBackgroundFetch:tasks";

static BOOL _hasRegisteredFetchTaskScheduler        = NO;
static BOOL _hasRegisteredProcessingTaskScheduler   = NO;

static NSString *const ERROR_PROCESSING_TASK_NOT_REGISTERED = @"Background procssing task was not registered in AppDelegate didFinishLaunchingWithOptions.  See iOS Setup Guide.";
static NSString *const ERROR_PROCESSING_TASK_NOT_AVAILABLE = @"Background procssing tasks are only available with iOS 13+";

static NSMutableArray *_tasks;

@implementation TSBGTask {
    BOOL isFetchTask;
    BOOL scheduled;
}

#pragma mark Class Methods

+(void)registerForTaskWithIdentifier:(NSString*)identifier isFetch:(BOOL)isFetch API_AVAILABLE(ios(13)) {
    if (isFetch) {
        _hasRegisteredFetchTaskScheduler = YES;
    } else {
        _hasRegisteredProcessingTaskScheduler = YES;
    }
    
    __block NSString *type = (isFetch) ? @"Fetch" : @"Processing";
    NSLog(@"[%@ registerBackground%@Task: %@", TAG, type, identifier);
    
    [[BGTaskScheduler sharedScheduler] registerForTaskWithIdentifier:identifier usingQueue:nil launchHandler:^(BGTask* task) {
        TSBGTask *tsTask = [self get:task.identifier];
        if (!tsTask) {
            NSLog(@"[%@ registerBackground%@Task] ERROR:  Failed to find TSBGTask in Fetch event: %@", type, TAG, task.identifier);
            [task setTaskCompletedWithSuccess:NO];
            return;
        }
        [tsTask setTask:task];
    }];
}

+(void)registerFetchTaskScheduler {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _hasRegisteredFetchTaskScheduler = YES;
    });
}

+(BOOL)useFetchTaskScheduler {
    return _hasRegisteredFetchTaskScheduler;
}

+(BOOL)useProcessingTaskScheduler {
    return _hasRegisteredProcessingTaskScheduler;
}

+(void)load {
    [[self class] tasks];
}

+(int) countFetch {
    NSArray *tasks = [[self class] tasks];
    int count = 0;
    @synchronized (tasks) {
        for (TSBGTask *tsTask in tasks) {
            if (tsTask.isFetchTask && tsTask.enabled) count++;
        }
    }
    return count;
}

+ (NSMutableArray*)tasks
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _tasks = [NSMutableArray new];
        // Load the set of taskIds, eg: ["foo, "bar"]
        NSArray *taskIds = [defaults objectForKey:TASKS_STORAGE_KEY];
        // Foreach taskId, load TSBGTask config from NSDefaults, eg: "TSBackgroundFetch:foo"
        for (NSString *taskId in taskIds) {
            NSString *key = [NSString stringWithFormat:@"%@:%@", TAG, taskId];
            NSDictionary *config = [defaults objectForKey:key];
            TSBGTask *tsTask = [[TSBGTask alloc] initWithDictionary:config];
            [_tasks addObject:tsTask];
        }
        NSLog(@"[%@ load]: %@", TAG, _tasks);
    });
    return _tasks;
}



+ (TSBGTask*) get:(NSString*)identifier {
    NSMutableArray *tasks = [[self class] tasks];
    TSBGTask *found = nil;
    @synchronized (tasks) {
        for (TSBGTask *tsTask in tasks) {
            if ([tsTask.identifier isEqualToString:identifier]) {
                found = tsTask;
                break;
            }
        }
    }
    return found;
}

+ (void) add:(TSBGTask*)tsTask {
    NSMutableArray *tasks = [[self class] tasks];
    @synchronized (tasks) {
        [tasks addObject:tsTask];
    }
}

+ (void) remove:(TSBGTask*)tsTask {
    NSMutableArray *tasks = [[self class] tasks];
    if (!tasks) return;
    @synchronized (tasks) {
        [tasks removeObject:tsTask];
    }
}

# pragma mark Instance Methods

-(instancetype)init {
    self = [super init];
    isFetchTask = YES;
    scheduled = NO;
    
    _enabled = NO;
    _executed = NO;
    
    return self;
}

-(instancetype) initWithIdentifier:(NSString*)identifier delay:(NSTimeInterval)delay periodic:(BOOL)periodic callback:(void (^)(NSString* taskId))callback {
    self = [self init];
    
    if (self) {
        _identifier = identifier;
        _delay = delay;
        _periodic = periodic;
        [TSBGTask add:self];
    }
    return self;
}

-(instancetype) initWithDictionary:(NSDictionary*)config {
    self = [self init];
    if (self) {
        _identifier = [config objectForKey:@"identifier"];
        _delay = [[config objectForKey:@"delay"] longValue];
        _periodic = [[config objectForKey:@"periodic"] boolValue];
        _enabled = [[config objectForKey:@"enabled"] boolValue];
        isFetchTask = [[config objectForKey:@"isFetchTask"] boolValue];
    }
    return self;
}

- (NSError*) scheduleFetchTask {
    if (scheduled) return nil;
    
    NSLog(@"[%@ scheduleFetchTask] %@, %d", TAG, self, [TSBGTask useFetchTaskScheduler]);
    
    isFetchTask = YES;
    
    NSError *error = nil;
    
    if (@available (iOS 13.0, *)) {
        if ([TSBGTask useFetchTaskScheduler]) {
            BGTaskScheduler *scheduler = [BGTaskScheduler sharedScheduler];
            BGAppRefreshTaskRequest *request = [[BGAppRefreshTaskRequest alloc] initWithIdentifier:_identifier];
            request.earliestBeginDate = [NSDate dateWithTimeIntervalSinceNow:_delay];
            [scheduler submitTaskRequest:request error:&error];
        } else {
            [self setMinimumFetchInterval];
        }
    } else {
        [self setMinimumFetchInterval];
    }
    if (!error) {
        scheduled = YES;
        if (!_enabled) {
            _enabled = YES;
            [self save];
        }
    }
    return error;
}

-(void) setMinimumFetchInterval {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] setMinimumBackgroundFetchInterval:_delay];
    });
}
- (NSError*) scheduleProcessingTask {
    if (@available (iOS 13.0, *)) {
        if (![TSBGTask useProcessingTaskScheduler]) {
            return [[NSError alloc] initWithDomain:TAG code:0 userInfo:@{NSLocalizedFailureReasonErrorKey:ERROR_PROCESSING_TASK_NOT_REGISTERED}];
        }
        
        NSLog(@"[%@ scheduleProcessingTask] %@", TAG, self);
        
        isFetchTask = NO;
        
        BGTaskScheduler *scheduler = [BGTaskScheduler sharedScheduler];
        
        if (scheduled) {
            [[BGTaskScheduler sharedScheduler] cancelTaskRequestWithIdentifier:_identifier];
        }
        
        BGProcessingTaskRequest *request = [[BGProcessingTaskRequest alloc] initWithIdentifier:_identifier];
        request.earliestBeginDate = [NSDate dateWithTimeIntervalSinceNow:_delay];
        
        NSError *error = nil;
        [scheduler submitTaskRequest:request error:&error];
        if (!error) {
            scheduled = YES;
            if (!_enabled) {
                _enabled = YES;
                [self save];
            }
        }
        return error;
    } else {
        return [[NSError alloc] initWithDomain:TAG code:-1 userInfo:@{NSLocalizedFailureReasonErrorKey:ERROR_PROCESSING_TASK_NOT_AVAILABLE}];
    }
}

- (void) stop {
    _enabled = NO;
    scheduled = NO;
    
    if (isFetchTask) {
        [self save];
    } else {
        [self destroy];
    }
    
    if ([TSBGTask useFetchTaskScheduler] || [TSBGTask useProcessingTaskScheduler]) {
        if (@available(iOS 13.0, *)) {
            [[BGTaskScheduler sharedScheduler] cancelTaskRequestWithIdentifier:_identifier];
        }
    } else if ([TSBGTask countFetch] < 1) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[UIApplication sharedApplication] setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalNever];
        });
    }
}

-(void) setTask:(BGTask*)task {
    scheduled = NO;
    
    _task = (isFetchTask) ? (BGAppRefreshTask*) task : (BGProcessingTask*) task;
    
    task.expirationHandler = ^{
        NSLog(@"[%@ expirationHandler] WARNING: %@ '%@' expired before #finish was executed.", TAG, NSStringFromClass([_task class]), _identifier);
        [self finish:NO];
    };

    // If no callback registered for TSTask, the app was launched in background.  The event will be handled once task is scheduled.
    if (_callback) {
        [self execute];
    }
}

- (BOOL) execute {
    if (@available(iOS 13.0, *)) {
        if (_periodic && !scheduled) {
            if (isFetchTask && [TSBGTask useFetchTaskScheduler]) {
                [self scheduleFetchTask];
            } else if ([TSBGTask useProcessingTaskScheduler]){
                [self scheduleProcessingTask];
            }
        }
    }
    
    if (_callback) {
        _callback(_identifier);
        _executed = YES;
        return YES;
    } else {
        return NO;
    }    
}

-(void) finish:(BOOL)success {
    [_task setTaskCompletedWithSuccess:success];
    _task = nil;
    _executed = NO;
    if (!_periodic) {
        [self destroy];
    }
}

-(void) save {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *taskIds = [[defaults objectForKey:TASKS_STORAGE_KEY] mutableCopy];
    if (!taskIds) {
        taskIds = [NSMutableArray new];
    }
        
    if (![taskIds containsObject:_identifier]) {
        [taskIds addObject:_identifier];
        [defaults setObject:taskIds forKey:TASKS_STORAGE_KEY];
    }
    NSString *key = [NSString stringWithFormat:@"%@:%@", TAG, _identifier];
    NSLog(@"[TSBGTask save]: %@", self);
    [defaults setObject:[self toDictionary] forKey:key];
}

-(void) destroy {
    [TSBGTask remove:self];
            
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *taskIds = [[defaults objectForKey:TASKS_STORAGE_KEY] mutableCopy];
    if (!taskIds) {
        taskIds = [NSMutableArray new];
    }
    if ([taskIds containsObject:_identifier]) {
        [taskIds removeObject:_identifier];
        [defaults setObject:taskIds forKey:TASKS_STORAGE_KEY];
    }
    NSString *key = [NSString stringWithFormat:@"%@:%@", TAG, _identifier];
    if ([defaults objectForKey:key]) {
        [defaults removeObjectForKey:key];
    }
    NSLog(@"[TSBGTask destroy] %@", _identifier);
}

-(BOOL) isFetchTask {
    return isFetchTask;
}

-(NSDictionary*) toDictionary {
    return @{
        @"identifier": _identifier,
        @"delay": @(_delay),
        @"periodic": @(_periodic),
        @"isFetchTask": @(isFetchTask),
        @"enabled": @(_enabled)
    };
}

-(NSString*) description {
    return [NSString stringWithFormat:@"<TSBGTask identifier=%@, delay=%ld, periodic=%d enabled=%d>", _identifier, (long)_delay, _periodic, _enabled];
}
@end
