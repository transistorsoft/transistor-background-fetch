//
//  RNBackgroundFetchManager.h
//  RNBackgroundFetch
//
//  Created by Christopher Scott on 2016-08-02.
//  Copyright © 2016 Christopher Scott. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <BackgroundTasks/BackgroundTasks.h>

@interface TSBackgroundFetch : NSObject

@property (nonatomic) BOOL stopOnTerminate;
@property (readonly) BOOL configured;
@property (readonly) BOOL active;

+ (TSBackgroundFetch *)sharedInstance;

-(void) registerBackgroundFetchTask:(NSString*)identifier;
-(void) registerBackgroundProcessingTask:(NSString*)identifier;

-(NSError*) scheduleFetchWithIdentifier:(NSString*)identifier delay:(NSTimeInterval)delay callback:(void (^)(NSString* taskId))callback;
-(NSError*) scheduleProcessingTaskWithIdentifier:(NSString*)identifier delay:(NSTimeInterval)delay periodic:(BOOL)periodic callback:(void (^)(NSString* taskId))callback;

-(void) removeListener:(NSString*)componentName;
-(BOOL) hasListener:(NSString*)componentName;

-(NSError*) start:(NSString*)identifier;
-(void) stop:(NSString*)identifier;
-(void) finish:(NSString*)tag;
-(void) status:(void(^)(UIBackgroundRefreshStatus status))callback;

// @deprecated API
-(void) performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))handler applicationState:(UIApplicationState)state;
@end

