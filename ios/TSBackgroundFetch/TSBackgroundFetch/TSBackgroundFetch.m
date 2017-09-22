//
//  RNBackgroundFetchManager.m
//  RNBackgroundFetch
//
//  Created by Christopher Scott on 2016-08-02.
//  Copyright © 2016 Christopher Scott. All rights reserved.
//

#import "TSBackgroundFetch.h"

static NSString *const TAG = @"TSBackgroundFetch";

@implementation TSBackgroundFetch {
    NSMutableDictionary *listeners;
    NSMutableDictionary *responses;
    
    void (^completionHandler)(UIBackgroundFetchResult);
    BOOL hasReceivedEvent;
    BOOL launchedInBackground;
    NSTimeInterval minimumFetchInterval;
    
    NSTimer *bootBufferTimer;
}

+ (TSBackgroundFetch *)sharedInstance
{
    static TSBackgroundFetch *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
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
    minimumFetchInterval = UIApplicationBackgroundFetchIntervalMinimum;
    
    bootBufferTimer = nil;
    listeners = [NSMutableDictionary new];
    responses = [NSMutableDictionary new];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onAppTerminate) name:UIApplicationWillTerminateNotification object:nil];
    return self;
}

- (void) configure:(NSDictionary*)config callback:(void(^)(UIBackgroundRefreshStatus status))callback
{
    [self configure:config];
    [self status:callback];
}

-(void) configure:(NSDictionary*)config
{
    [self applyConfig:config];
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:config forKey:TAG];
    _configured = YES;
}
- (void) applyConfig:(NSDictionary*)config
{
    NSLog(@"[%@ configure]: %@", TAG, config);

    if ([config objectForKey:@"stopOnTerminate"]) {
        _stopOnTerminate = [[config objectForKey:@"stopOnTerminate"] boolValue];
    }
    if ([config objectForKey:@"minimumFetchInterval"]) {
        minimumFetchInterval = [[config objectForKey:@"minimumFetchInterval"] doubleValue] * 60;
    }
}

-(void) status:(void(^)(UIBackgroundRefreshStatus status))callback
{
    dispatch_async(dispatch_get_main_queue(), ^{
        callback([[UIApplication sharedApplication] backgroundRefreshStatus]);
    });
}

-(void) addListener:(NSString*)componentName callback:(void (^)(void))callback
{
    NSLog(@"[%@ addListener]: %@", TAG, componentName);
    @synchronized(listeners) {
        [listeners setObject:callback forKey:componentName];
    }
    
    // Run callback immediately if app was launched due to background-fetch event.
    if (launchedInBackground) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            callback();
        });
    }
}

-(BOOL) hasListener:(NSString*)componentName
{
    return [listeners objectForKey:componentName] != nil;
}

-(void) removeListener:(NSString*)componentName
{
    @synchronized(listeners) {
        if ([listeners objectForKey:componentName]) {
            NSLog(@"[%@ removeListener]: %@", TAG, componentName);
            [listeners removeObjectForKey:componentName];
        }
    }
}

- (void) start:(void(^)(UIBackgroundRefreshStatus status))callback
{
    [self status:^(UIBackgroundRefreshStatus status) {
        if (status == UIBackgroundRefreshStatusAvailable) { [self start]; }
        callback(status);
    }];
}

- (void) start
{
    NSLog(@"[%@ start]", TAG);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] setMinimumBackgroundFetchInterval:minimumFetchInterval];
    });
}

- (void) stop
{
    NSLog(@"[%@ stop]", TAG);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalNever];
    });
}

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
    @synchronized(listeners) {
        if ([listeners count] > 0) {
            completionHandler = handler;
            for (NSString* componentName in listeners) {
                void (^callback)() = [listeners objectForKey:componentName];
                callback();
            }
        } else if (launchedInBackground) {
            if (!_configured) {
                NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
                NSDictionary *config = [userDefaults objectForKey:TAG];
                if (config != nil) {
                    [self applyConfig:config];
                }
            }
            // Wait for handlers to arrive
            completionHandler = handler;
        } else {
            // No handlers?
            handler(UIBackgroundFetchResultNoData);
        }
    }
}

- (void) finish:(NSString*)componentName result:(UIBackgroundFetchResult) result
{
    @synchronized (responses) {
        if (completionHandler == nil) {
            NSLog(@"[%@ finish] WARNING: completionHandler is nil.  No fetch event to finish.  Ignored", TAG);
            return;
        }
        if ([responses objectForKey:componentName]) {
            NSLog(@"[%@ finish] WARNING: finish already called for %@.  Ignored", TAG, componentName);
            return;
        }
        if (![self hasListener:componentName]) {
            NSLog(@"%@ finish] WARNING: no listener found to finish for %@.  Ignored", TAG, componentName);
            return;
        }
        NSLog(@"[%@ finish]: %@", TAG, componentName);
        [responses setObject:@(result) forKey:componentName];
        
        if (launchedInBackground && (bootBufferTimer == nil)) {
            // Give other modules 5 second buffer before we finish.  Other modules may not yet have registed their callback when booted in background
            bootBufferTimer = [NSTimer timerWithTimeInterval:5 target:self selector:@selector(doFinish) userInfo:nil repeats:NO];
            [[NSRunLoop mainRunLoop] addTimer:bootBufferTimer forMode:NSRunLoopCommonModes];
            
        } else {
            [self doFinish];
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
        if ([[responses allKeys] count] == [[listeners allKeys] count]) {
            NSUInteger fetchResult = UIBackgroundFetchResultNoData;
            //for (id response in responses) {
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
            
            if (launchedInBackground && _stopOnTerminate) {
                [self stop];
            }
            launchedInBackground = NO;
        }
    }
}

- (void) onAppTerminate
{
    NSLog(@"[%@ onAppTerminate]", TAG);
    if (_stopOnTerminate) {
        [self stop];
    }
}

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [listeners removeAllObjects];
    [responses removeAllObjects];
}
@end

