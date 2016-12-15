//
//  RNBackgroundFetchManager.m
//  RNBackgroundFetch
//
//  Created by Christopher Scott on 2016-08-02.
//  Copyright © 2016 Christopher Scott. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TSBackgroundFetch.h"

static NSString *const TAG = @"TSBackgroundFetch";

@implementation TSBackgroundFetch {
    NSMutableDictionary *listeners;
    NSMutableDictionary *responses;
    
    void (^completionHandler)(UIBackgroundFetchResult);
    BOOL launchedInBackground;
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
    
    UIApplication *app = [UIApplication sharedApplication];
    launchedInBackground = app.applicationState == UIApplicationStateBackground;
    
    _stopOnTerminate = YES;
    _configured = NO;
    _active = NO;
    
    bootBufferTimer = nil;
    listeners = [NSMutableDictionary new];
    responses = [NSMutableDictionary new];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onAppTerminate) name:UIApplicationWillTerminateNotification object:nil];
    return self;
}

- (void) configure:(NSDictionary*)config
{
    [self applyConfig:config];
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:config forKey:TAG];
    _configured = YES;
}

- (void) applyConfig:(NSDictionary*)config
{
    if (config[@"stopOnTerminate"]) {
        _stopOnTerminate = [[config objectForKey:@"stopOnTerminate"] boolValue];
    }
}

-(void) addListener:(NSString*)componentName callback:(void (^)(void))callback
{
    NSLog(@"- %@ addListener: %@", TAG, componentName);
    [listeners setObject:callback forKey:componentName];
    
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
    if ([listeners objectForKey:componentName]) {
        NSLog(@"- %@ removeListener: %@", TAG, componentName);
        [listeners removeObjectForKey:componentName];
    }
}

- (BOOL) start
{
    UIApplication *app = [UIApplication sharedApplication];
    
    if (![app respondsToSelector:@selector(setMinimumBackgroundFetchInterval:)]) {
        NSLog(@"- %@: background fetch unsupported for this version of iOS", TAG);
        return NO;
    }
    
    [app setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalMinimum];
    NSLog(@"- %@ started", TAG);
    return YES;
}

- (void) stop
{
    UIApplication *app = [UIApplication sharedApplication];
    [app setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalNever];
}

- (void) performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))handler
{
    NSLog(@"- %@ performFetchWithCompletionHandler", TAG);
    _active = YES;
    [responses removeAllObjects];
    
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

- (void) finish:(NSString*)componentName result:(UIBackgroundFetchResult) result
{
    if (completionHandler == nil) {
        NSLog(@"- %@ WARNING: completionHandler is nil.  No fetch event to finish.  Ignored", TAG);
        return;
    }
    if ([responses objectForKey:componentName]) {
        NSLog(@"- %@ WARNING: finish already called for %@.  Ignored", TAG, componentName);
        return;
    }
    if (![self hasListener:componentName]) {
        NSLog(@"- %@ WARNING: no listener found to finish for %@.  Ignored", TAG, componentName);
        return;
    }
    NSLog(@"- %@ finish: %@", TAG, componentName);
    [responses setObject:@(result) forKey:componentName];
    
    if (launchedInBackground && (bootBufferTimer == nil)) {
        // Give other modules 5 second buffer before we finish.  Other modules may not yet have registed their callback when booted in background
        bootBufferTimer = [NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(onBootBufferTimeout:) userInfo:nil repeats:NO];
    } else {
        [self doFinish];
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
        NSLog(@"- %@ Complete, UIBackgroundFetchResult: %lu, responses: %lu", TAG, (long)fetchResult, (long)[responses count]);
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

- (void) onAppTerminate
{
    NSLog(@"- TSBackgroundFetch onAppTerminate");
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

