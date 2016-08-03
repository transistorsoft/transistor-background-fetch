//
//  RNBackgroundFetchManager.m
//  RNBackgroundFetch
//
//  Created by Christopher Scott on 2016-08-02.
//  Copyright © 2016 Christopher Scott. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TSBackgroundFetch.h"

@implementation TSBackgroundFetch {
    NSMutableArray *listeners;
    NSMutableArray *responses;
    void (^completionHandler)(UIBackgroundFetchResult);
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
    
    listeners = [NSMutableArray new];
    responses = [NSMutableArray new];
    
    return self;
}

- (BOOL) start
{
    UIApplication *app = [UIApplication sharedApplication];
    
    if (![app respondsToSelector:@selector(setMinimumBackgroundFetchInterval:)]) {
        NSLog(@"- TSBackgroundFetch: background fetch unsupported for this version of iOS");
        return NO;
    }
    
    [app setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalMinimum];
    NSLog(@"- TSBackgroundFetch started");
    return YES;
}

- (void) stop
{
    UIApplication *app = [UIApplication sharedApplication];
    [app setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalNever];
}

- (void) performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))handler
{
    [responses removeAllObjects];
    NSLog(@"- TSBackgroundFetch#performFetchWithCompletionHandler");
    if ([listeners count] > 0) {
        completionHandler = handler;
        for (void (^callback)() in listeners) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                callback();
            });
        }
    } else {
        handler(UIBackgroundFetchResultNoData);
    }
}
-(void) addListener:(void (^)(void))handler
{
    [listeners addObject:handler];
}
- (void) finish:(UIBackgroundFetchResult) result
{
    NSLog(@"- TSBackgroundFetch#finish");
    [responses addObject:@(result)];
    if ([responses count] == [listeners count]) {
        NSLog(@"- All fetch-callbacks have returned.  Calling fetchCompletionHandler");
        completionHandler(UIBackgroundFetchResultNewData);
        // TODO iterate responses and choose which UIBackgroundFetchResult to use
        [responses removeAllObjects];
        completionHandler = nil;
    }
}

@end

