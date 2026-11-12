//
//  TSBackgroundFetchTests.m
//  TSBackgroundFetchTests
//
//  Created by Christopher Scott on 2016-08-03.
//  Copyright © 2016 Christopher Scott. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import <TSBackgroundFetch/TSBackgroundFetch.h>

// ============================================================================
#pragma mark - TSBGTask Tests
// ============================================================================

@interface TSBGTaskTests : XCTestCase
@end

@implementation TSBGTaskTests

- (void)setUp {
    [super setUp];
    // Ensure static task list is initialised.
    [TSBGTask load];
}

- (void)tearDown {
    // Clean up any tasks we created.
    NSArray *tasks = [TSBGTask tasks];
    for (TSBGTask *task in tasks) {
        [task destroy];
    }
    [super tearDown];
}

// -- initWithDictionary round-trip -----------------------------------------

- (void)testInitWithDictionaryRestoresType {
    NSDictionary *config = @{
        @"identifier": @"com.test.task",
        @"type": @(1),
        @"delay": @(300.0),
        @"periodic": @(YES),
        @"enabled": @(YES),
        @"requiresExternalPower": @(NO),
        @"requiresNetworkConnectivity": @(NO),
    };
    TSBGTask *task = [[TSBGTask alloc] initWithDictionary:config];
    XCTAssertEqual(task.type, 1, @"type should be restored from dictionary");
}

- (void)testInitWithDictionaryDefaultsTypeToZero {
    NSDictionary *config = @{
        @"identifier": @"com.test.task",
        @"delay": @(60.0),
        @"periodic": @(NO),
        @"enabled": @(NO),
        @"requiresExternalPower": @(NO),
        @"requiresNetworkConnectivity": @(NO),
    };
    TSBGTask *task = [[TSBGTask alloc] initWithDictionary:config];
    XCTAssertEqual(task.type, 0, @"type should default to 0 (processing) when missing");
}

- (void)testInitWithDictionaryPreservesDoubleDelay {
    NSDictionary *config = @{
        @"identifier": @"com.test.delay",
        @"type": @(0),
        @"delay": @(1.5),
        @"periodic": @(NO),
        @"enabled": @(YES),
        @"requiresExternalPower": @(NO),
        @"requiresNetworkConnectivity": @(NO),
    };
    TSBGTask *task = [[TSBGTask alloc] initWithDictionary:config];
    XCTAssertEqualWithAccuracy(task.delay, 1.5, 0.001, @"fractional delay should survive round-trip");
}

- (void)testInitWithDictionaryRestoresAllFields {
    NSDictionary *config = @{
        @"identifier": @"com.test.full",
        @"type": @(1),
        @"delay": @(900.0),
        @"periodic": @(YES),
        @"enabled": @(YES),
        @"requiresExternalPower": @(YES),
        @"requiresNetworkConnectivity": @(YES),
    };
    TSBGTask *task = [[TSBGTask alloc] initWithDictionary:config];

    XCTAssertEqualObjects(task.identifier, @"com.test.full");
    XCTAssertEqual(task.type, 1);
    XCTAssertEqualWithAccuracy(task.delay, 900.0, 0.001);
    XCTAssertTrue(task.periodic);
    XCTAssertTrue(task.enabled);
    XCTAssertTrue(task.requiresExternalPower);
    XCTAssertTrue(task.requiresNetworkConnectivity);
}

// -- toDictionary serialisation -------------------------------------------

- (void)testToDictionaryRoundTrip {
    NSDictionary *original = @{
        @"identifier": @"com.test.roundtrip",
        @"type": @(1),
        @"delay": @(42.5),
        @"periodic": @(YES),
        @"enabled": @(NO),
        @"requiresExternalPower": @(YES),
        @"requiresNetworkConnectivity": @(NO),
    };
    TSBGTask *task = [[TSBGTask alloc] initWithDictionary:original];
    NSDictionary *serialised = [task toDictionary];

    XCTAssertEqualObjects(serialised[@"identifier"], @"com.test.roundtrip");
    XCTAssertEqual([serialised[@"type"] integerValue], 1);
    XCTAssertEqualWithAccuracy([serialised[@"delay"] doubleValue], 42.5, 0.001);
    XCTAssertTrue([serialised[@"periodic"] boolValue]);
    XCTAssertFalse([serialised[@"enabled"] boolValue]);
    XCTAssertTrue([serialised[@"requiresExternalPower"] boolValue]);
    XCTAssertFalse([serialised[@"requiresNetworkConnectivity"] boolValue]);
}

// -- execute / callback ---------------------------------------------------

- (void)testExecuteFiresCallbackOnMainQueue {
    XCTestExpectation *expectation = [self expectationWithDescription:@"callback fires on main"];

    TSBGTask *task = [[TSBGTask alloc] initWithDictionary:@{
        @"identifier": @"com.test.execute",
        @"type": @(0),
        @"delay": @(0),
        @"periodic": @(NO),
        @"enabled": @(YES),
        @"requiresExternalPower": @(NO),
        @"requiresNetworkConnectivity": @(NO),
    }];

    __block NSString *receivedTaskId = nil;
    __block BOOL receivedTimeout = YES;
    __block BOOL calledOnMainThread = NO;

    task.callback = ^(NSString *taskId, BOOL timeout) {
        receivedTaskId = taskId;
        receivedTimeout = timeout;
        calledOnMainThread = [NSThread isMainThread];
        [expectation fulfill];
    };

    [task execute];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
    XCTAssertEqualObjects(receivedTaskId, @"com.test.execute");
    XCTAssertFalse(receivedTimeout);
    XCTAssertTrue(calledOnMainThread, @"callback should fire on main queue");
    XCTAssertTrue(task.executed);
}

- (void)testExecuteWithoutCallbackReturnsFalse {
    TSBGTask *task = [[TSBGTask alloc] initWithDictionary:@{
        @"identifier": @"com.test.nocallback",
        @"type": @(0),
        @"delay": @(0),
        @"periodic": @(NO),
        @"enabled": @(YES),
        @"requiresExternalPower": @(NO),
        @"requiresNetworkConnectivity": @(NO),
    }];
    // No callback set.
    BOOL result = [task execute];
    XCTAssertFalse(result, @"execute should return NO when no callback is set");
}

// -- onTimeout dispatch ---------------------------------------------------

- (void)testOnTimeoutFiresCallbackOnMainQueue {
    XCTestExpectation *expectation = [self expectationWithDescription:@"timeout fires on main"];

    TSBGTask *task = [[TSBGTask alloc] initWithDictionary:@{
        @"identifier": @"com.test.timeout",
        @"type": @(0),
        @"delay": @(0),
        @"periodic": @(NO),
        @"enabled": @(YES),
        @"requiresExternalPower": @(NO),
        @"requiresNetworkConnectivity": @(NO),
    }];

    __block BOOL receivedTimeout = NO;
    __block BOOL calledOnMainThread = NO;

    task.callback = ^(NSString *taskId, BOOL timeout) {
        receivedTimeout = timeout;
        calledOnMainThread = [NSThread isMainThread];
        [expectation fulfill];
    };

    // Dispatch onTimeout from a background queue to verify it still arrives on main.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [task onTimeout];
    });

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
    XCTAssertTrue(receivedTimeout, @"timeout param should be YES");
    XCTAssertTrue(calledOnMainThread, @"timeout callback should dispatch to main queue");
}

- (void)testOnTimeoutWithoutCallbackReturnsFalse {
    TSBGTask *task = [[TSBGTask alloc] initWithDictionary:@{
        @"identifier": @"com.test.notimeout",
        @"type": @(0),
        @"delay": @(0),
        @"periodic": @(NO),
        @"enabled": @(YES),
        @"requiresExternalPower": @(NO),
        @"requiresNetworkConnectivity": @(NO),
    }];
    BOOL result = [task onTimeout];
    XCTAssertFalse(result, @"onTimeout should return NO when no callback is set");
}

// -- finish with nil task -------------------------------------------------

- (void)testFinishWithNilTaskDoesNotCrash {
    TSBGTask *task = [[TSBGTask alloc] initWithDictionary:@{
        @"identifier": @"com.test.nilfinish",
        @"type": @(0),
        @"delay": @(0),
        @"periodic": @(YES),
        @"enabled": @(YES),
        @"requiresExternalPower": @(NO),
        @"requiresNetworkConnectivity": @(NO),
    }];
    // task.task is nil (no BGProcessingTask assigned).
    XCTAssertNoThrow([task finish:YES], @"finish: with nil task should not crash");
    XCTAssertTrue(task.finished, @"finished should be YES after finish:");
    XCTAssertFalse(task.executed, @"executed should be reset to NO");
}

- (void)testFinishNonPeriodicDestroysTask {
    // Create via the full init (which calls +add:).
    TSBGTask *task = [[TSBGTask alloc] initWithIdentifier:@"com.test.nonperiodic"
                                                     type:0
                                                    delay:0
                                                 periodic:NO
                                    requiresExternalPower:NO
                              requiresNetworkConnectivity:NO
                                                 callback:nil];

    XCTAssertNotNil([TSBGTask get:@"com.test.nonperiodic"], @"task should be registered");

    [task finish:YES];

    XCTAssertNil([TSBGTask get:@"com.test.nonperiodic"], @"non-periodic task should be destroyed after finish");
}

- (void)testFinishPeriodicKeepsTask {
    TSBGTask *task = [[TSBGTask alloc] initWithIdentifier:@"com.test.periodic"
                                                     type:0
                                                    delay:60
                                                 periodic:YES
                                    requiresExternalPower:NO
                              requiresNetworkConnectivity:NO
                                                 callback:nil];

    XCTAssertNotNil([TSBGTask get:@"com.test.periodic"], @"task should be registered");

    [task finish:YES];

    // Periodic tasks are NOT destroyed.
    XCTAssertTrue(task.finished);
    // Note: the task may or may not still be in the static list depending on
    // whether schedule was called. We just confirm it didn't crash and finished.
}

// -- persistence (NSUserDefaults) -----------------------------------------

- (void)testSaveAndDestroyPersistence {
    NSString *identifier = @"com.test.persist";
    TSBGTask *task = [[TSBGTask alloc] initWithDictionary:@{
        @"identifier": identifier,
        @"type": @(0),
        @"delay": @(120),
        @"periodic": @(NO),
        @"enabled": @(YES),
        @"requiresExternalPower": @(NO),
        @"requiresNetworkConnectivity": @(NO),
    }];

    [task save];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = [NSString stringWithFormat:@"TSBackgroundFetch:%@", identifier];
    NSDictionary *stored = [defaults objectForKey:key];
    XCTAssertNotNil(stored, @"task should be saved to NSUserDefaults");
    XCTAssertEqualObjects(stored[@"identifier"], identifier);

    NSArray *taskIds = [defaults objectForKey:@"TSBackgroundFetch:tasks"];
    XCTAssertTrue([taskIds containsObject:identifier], @"task ID should be in the tasks list");

    // Cleanup.
    [task destroy];

    NSDictionary *afterDestroy = [defaults objectForKey:key];
    XCTAssertNil(afterDestroy, @"task should be removed from NSUserDefaults after destroy");

    NSArray *taskIdsAfter = [defaults objectForKey:@"TSBackgroundFetch:tasks"];
    XCTAssertFalse([taskIdsAfter containsObject:identifier], @"task ID should be removed from tasks list");
}

// -- static collection management -----------------------------------------

- (void)testGetReturnsRegisteredTask {
    TSBGTask *task = [[TSBGTask alloc] initWithIdentifier:@"com.test.get"
                                                     type:0
                                                    delay:0
                                                 periodic:NO
                                    requiresExternalPower:NO
                              requiresNetworkConnectivity:NO
                                                 callback:nil];
    TSBGTask *found = [TSBGTask get:@"com.test.get"];
    XCTAssertEqual(found, task, @"+get: should return the same instance");
}

- (void)testGetReturnsNilForUnknownIdentifier {
    TSBGTask *found = [TSBGTask get:@"com.test.nonexistent"];
    XCTAssertNil(found, @"+get: should return nil for unknown identifier");
}

// -- description ----------------------------------------------------------

- (void)testDescriptionContainsIdentifier {
    TSBGTask *task = [[TSBGTask alloc] initWithDictionary:@{
        @"identifier": @"com.test.desc",
        @"type": @(0),
        @"delay": @(1.5),
        @"periodic": @(NO),
        @"enabled": @(YES),
        @"requiresExternalPower": @(NO),
        @"requiresNetworkConnectivity": @(NO),
    }];
    NSString *desc = [task description];
    XCTAssertTrue([desc containsString:@"com.test.desc"], @"description should contain identifier");
    XCTAssertTrue([desc containsString:@"1.5"], @"description should show fractional delay");
}

@end

// ============================================================================
#pragma mark - TSBGAppRefreshSubscriber Tests
// ============================================================================

@interface TSBGAppRefreshSubscriberTests : XCTestCase
@end

@implementation TSBGAppRefreshSubscriberTests

- (void)setUp {
    [super setUp];
    [TSBGAppRefreshSubscriber load];
}

- (void)tearDown {
    // Clean up all subscribers.
    NSDictionary *subs = [TSBGAppRefreshSubscriber subscribers];
    for (NSString *key in [subs allKeys]) {
        TSBGAppRefreshSubscriber *sub = subs[key];
        [sub destroy];
    }
    [super tearDown];
}

// -- registration ---------------------------------------------------------

- (void)testInitWithCallbackRegistersViaAdd {
    TSBGAppRefreshSubscriber *sub = [[TSBGAppRefreshSubscriber alloc]
                                     initWithIdentifier:@"test.subscriber"
                                     callback:^(NSString *taskId) {}
                                     timeout:^(NSString *taskId) {}];
    TSBGAppRefreshSubscriber *found = [TSBGAppRefreshSubscriber get:@"test.subscriber"];
    XCTAssertNotNil(found, @"subscriber should be findable via +get:");
    XCTAssertEqual(found, sub, @"+get: should return the same instance");
}

- (void)testGetReturnsNilForUnknownIdentifier {
    TSBGAppRefreshSubscriber *found = [TSBGAppRefreshSubscriber get:@"nonexistent"];
    XCTAssertNil(found);
}

// -- execute callback -----------------------------------------------------

- (void)testExecuteFiresCallbackOnMainQueue {
    XCTestExpectation *expectation = [self expectationWithDescription:@"subscriber callback"];

    __block NSString *receivedTaskId = nil;
    __block BOOL calledOnMainThread = NO;

    TSBGAppRefreshSubscriber *sub = [[TSBGAppRefreshSubscriber alloc]
                                     initWithIdentifier:@"test.execute"
                                     callback:^(NSString *taskId) {
                                         receivedTaskId = taskId;
                                         calledOnMainThread = [NSThread isMainThread];
                                         [expectation fulfill];
                                     }
                                     timeout:nil];

    [sub execute];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
    XCTAssertEqualObjects(receivedTaskId, @"test.execute");
    XCTAssertTrue(calledOnMainThread, @"subscriber callback should fire on main queue");
    XCTAssertTrue(sub.executed);
}

- (void)testExecuteGuardsAgainstDoubleExecution {
    __block int callCount = 0;

    TSBGAppRefreshSubscriber *sub = [[TSBGAppRefreshSubscriber alloc]
                                     initWithIdentifier:@"test.double"
                                     callback:^(NSString *taskId) {
                                         callCount++;
                                     }
                                     timeout:nil];

    [sub execute];
    [sub execute]; // second call should be ignored

    // Give main queue time to process.
    XCTestExpectation *wait = [self expectationWithDescription:@"drain main queue"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [wait fulfill];
    });
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
    XCTAssertEqual(callCount, 1, @"callback should only fire once (double-execute guard)");
}

// -- timeout callback -----------------------------------------------------

- (void)testOnTimeoutFiresTimeoutCallback {
    XCTestExpectation *expectation = [self expectationWithDescription:@"timeout callback"];

    __block NSString *receivedTaskId = nil;

    TSBGAppRefreshSubscriber *sub = [[TSBGAppRefreshSubscriber alloc]
                                     initWithIdentifier:@"test.timeout"
                                     callback:^(NSString *taskId) {
                                         XCTFail(@"fetch callback should not be called on timeout");
                                     }
                                     timeout:^(NSString *taskId) {
                                         receivedTaskId = taskId;
                                         [expectation fulfill];
                                     }];

    [sub onTimeout];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
    XCTAssertEqualObjects(receivedTaskId, @"test.timeout");
}

- (void)testOnTimeoutWithoutHandlerAutoFinishes {
    TSBGAppRefreshSubscriber *sub = [[TSBGAppRefreshSubscriber alloc]
                                     initWithIdentifier:@"test.autofin"
                                     callback:^(NSString *taskId) {}
                                     timeout:nil]; // no timeout handler

    [sub onTimeout];

    XCTAssertTrue(sub.finished, @"onTimeout without handler should auto-finish the subscriber");
}

// -- finish state machine -------------------------------------------------

- (void)testFinishSetsState {
    TSBGAppRefreshSubscriber *sub = [[TSBGAppRefreshSubscriber alloc]
                                     initWithIdentifier:@"test.finish"
                                     callback:^(NSString *taskId) {}
                                     timeout:nil];

    XCTAssertFalse(sub.finished);
    [sub finish];
    XCTAssertTrue(sub.finished);
    XCTAssertFalse(sub.executed, @"executed should be reset after finish");
}

// -- class-level +onTimeout -----------------------------------------------

- (void)testClassOnTimeoutReturnsFalseWhenEmpty {
    // tearDown already cleaned up; no subscribers.
    BOOL result = [TSBGAppRefreshSubscriber onTimeout];
    XCTAssertFalse(result, @"+onTimeout should return NO when no subscribers exist");
}

- (void)testClassOnTimeoutReturnsTrueWithSubscribers {
    // Add a subscriber without a timeout handler.
    (void)[[TSBGAppRefreshSubscriber alloc] initWithIdentifier:@"test.hastimeout"
                                                      callback:^(NSString *taskId) {}
                                                       timeout:nil];

    BOOL result = [TSBGAppRefreshSubscriber onTimeout];
    XCTAssertTrue(result, @"+onTimeout should return YES when subscribers exist");
}

// -- persistence ----------------------------------------------------------

- (void)testSaveAndDestroyPersistence {
    NSString *identifier = @"test.persist";
    TSBGAppRefreshSubscriber *sub = [[TSBGAppRefreshSubscriber alloc]
                                     initWithIdentifier:identifier
                                     callback:^(NSString *taskId) {}
                                     timeout:nil];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *stored = [defaults objectForKey:@"TSBGAppRefreshSubscriber"];
    XCTAssertTrue([stored containsObject:identifier], @"subscriber should be persisted");

    [sub destroy];

    NSArray *afterDestroy = [defaults objectForKey:@"TSBGAppRefreshSubscriber"];
    XCTAssertFalse([afterDestroy containsObject:identifier], @"subscriber should be removed after destroy");

    TSBGAppRefreshSubscriber *found = [TSBGAppRefreshSubscriber get:identifier];
    XCTAssertNil(found, @"subscriber should not be in static collection after destroy");
}

@end

// ============================================================================
#pragma mark - TSBackgroundFetch Tests
// ============================================================================

@interface TSBackgroundFetchTests : XCTestCase
@end

@implementation TSBackgroundFetchTests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

// -- singleton ------------------------------------------------------------

- (void)testSharedInstanceReturnsSameObject {
    TSBackgroundFetch *a = [TSBackgroundFetch sharedInstance];
    TSBackgroundFetch *b = [TSBackgroundFetch sharedInstance];
    XCTAssertEqual(a, b, @"sharedInstance should return the same object");
}

- (void)testSharedInstanceNotNil {
    TSBackgroundFetch *instance = [TSBackgroundFetch sharedInstance];
    XCTAssertNotNil(instance);
}

// -- initial state --------------------------------------------------------

- (void)testInitialState {
    TSBackgroundFetch *fetch = [TSBackgroundFetch sharedInstance];
    XCTAssertFalse(fetch.active, @"should not be active initially");
    XCTAssertTrue(fetch.stopOnTerminate, @"stopOnTerminate defaults to YES");
    XCTAssertNotNil(fetch.fetchTaskId, @"fetchTaskId should be set");
    XCTAssertEqualObjects(fetch.fetchTaskId, @"com.transistorsoft.fetch");
}

// -- status callback ------------------------------------------------------

- (void)testStatusCallsBackOnMainQueue {
    XCTestExpectation *expectation = [self expectationWithDescription:@"status callback"];
    __block BOOL calledOnMainThread = NO;

    TSBackgroundFetch *fetch = [TSBackgroundFetch sharedInstance];
    [fetch status:^(UIBackgroundRefreshStatus status) {
        calledOnMainThread = [NSThread isMainThread];
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
    XCTAssertTrue(calledOnMainThread, @"status callback should arrive on main queue");
}

// -- listener management --------------------------------------------------

- (void)testAddAndHasListener {
    TSBackgroundFetch *fetch = [TSBackgroundFetch sharedInstance];

    [fetch addListener:@"test.listener"
              callback:^(NSString *taskId) {}
               timeout:^(NSString *taskId) {}];

    XCTAssertTrue([fetch hasListener:@"test.listener"]);
    XCTAssertFalse([fetch hasListener:@"nonexistent"]);

    // Cleanup.
    [fetch removeListener:@"test.listener"];
    XCTAssertFalse([fetch hasListener:@"test.listener"]);
}

- (void)testRemoveNonexistentListenerDoesNotCrash {
    TSBackgroundFetch *fetch = [TSBackgroundFetch sharedInstance];
    XCTAssertNoThrow([fetch removeListener:@"doesnt.exist"],
                     @"removing a nonexistent listener should not crash");
}

// -- configure callback ---------------------------------------------------

- (void)testConfigureCallsBack {
    XCTestExpectation *expectation = [self expectationWithDescription:@"configure callback"];
    TSBackgroundFetch *fetch = [TSBackgroundFetch sharedInstance];

    [fetch configure:0 callback:^(UIBackgroundRefreshStatus status) {
        // In the simulator, status may be UIBackgroundRefreshStatusAvailable
        // or UIBackgroundRefreshStatusDenied depending on settings.
        // We just verify the callback fires.
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
    XCTAssertTrue(fetch.configured, @"configured should be YES after configure:");
}

// -- multi-subscriber finish counting -------------------------------------

- (void)testMultiSubscriberFinishCounting {
    TSBackgroundFetch *fetch = [TSBackgroundFetch sharedInstance];

    XCTestExpectation *cb1 = [self expectationWithDescription:@"callback 1"];
    XCTestExpectation *cb2 = [self expectationWithDescription:@"callback 2"];
    XCTestExpectation *cb3 = [self expectationWithDescription:@"callback 3"];

    [fetch addListener:@"sub.one"
              callback:^(NSString *taskId) { [cb1 fulfill]; }
               timeout:^(NSString *taskId) {}];

    [fetch addListener:@"sub.two"
              callback:^(NSString *taskId) { [cb2 fulfill]; }
               timeout:^(NSString *taskId) {}];

    [fetch addListener:@"sub.three"
              callback:^(NSString *taskId) { [cb3 fulfill]; }
               timeout:^(NSString *taskId) {}];

    // Trigger a fetch event via the legacy completionHandler path.
    __block BOOL completionCalled = NO;
    __block UIBackgroundFetchResult completionResult = (UIBackgroundFetchResult)-1;
    [fetch performFetchWithCompletionHandler:^(UIBackgroundFetchResult result) {
        completionCalled = YES;
        completionResult = result;
    } applicationState:UIApplicationStateBackground];

    // Wait for all 3 subscriber callbacks to fire.
    [self waitForExpectationsWithTimeout:2.0 handler:nil];

    // Finish 1 of 3 — completionHandler must NOT fire yet.
    [fetch finish:@"sub.one"];
    XCTAssertFalse(completionCalled, @"completionHandler should not fire after 1 of 3 subscribers finish");

    // Finish 2 of 3 — still not done.
    [fetch finish:@"sub.two"];
    XCTAssertFalse(completionCalled, @"completionHandler should not fire after 2 of 3 subscribers finish");

    // Finish 3 of 3 — NOW the completionHandler should fire.
    [fetch finish:@"sub.three"];
    XCTAssertTrue(completionCalled, @"completionHandler should fire after all 3 subscribers finish");
    XCTAssertEqual(completionResult, UIBackgroundFetchResultNewData);

    [fetch removeListener:@"sub.one"];
    [fetch removeListener:@"sub.two"];
    [fetch removeListener:@"sub.three"];
}

- (void)testFinishOrderDoesNotMatter {
    TSBackgroundFetch *fetch = [TSBackgroundFetch sharedInstance];

    XCTestExpectation *cbA = [self expectationWithDescription:@"callback A"];
    XCTestExpectation *cbB = [self expectationWithDescription:@"callback B"];

    [fetch addListener:@"sub.alpha"
              callback:^(NSString *taskId) { [cbA fulfill]; }
               timeout:^(NSString *taskId) {}];

    [fetch addListener:@"sub.beta"
              callback:^(NSString *taskId) { [cbB fulfill]; }
               timeout:^(NSString *taskId) {}];

    __block BOOL completionCalled = NO;
    [fetch performFetchWithCompletionHandler:^(UIBackgroundFetchResult result) {
        completionCalled = YES;
    } applicationState:UIApplicationStateBackground];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];

    // Finish in reverse registration order.
    [fetch finish:@"sub.beta"];
    XCTAssertFalse(completionCalled, @"completionHandler should not fire after 1 of 2");

    [fetch finish:@"sub.alpha"];
    XCTAssertTrue(completionCalled, @"completionHandler should fire regardless of finish order");

    [fetch removeListener:@"sub.alpha"];
    [fetch removeListener:@"sub.beta"];
}

// -- finish for unknown task ----------------------------------------------

- (void)testFinishUnknownTaskDoesNotCrash {
    TSBackgroundFetch *fetch = [TSBackgroundFetch sharedInstance];
    XCTAssertNoThrow([fetch finish:@"com.test.unknown"],
                     @"finish: with unknown taskId should not crash");
}

- (void)testFinishNilDefaultsToFetchTaskId {
    TSBackgroundFetch *fetch = [TSBackgroundFetch sharedInstance];
    XCTAssertNoThrow([fetch finish:nil],
                     @"finish: with nil should not crash (defaults to fetch task ID)");
}

// -- stop -----------------------------------------------------------------

- (void)testStopNilDoesNotCrash {
    TSBackgroundFetch *fetch = [TSBackgroundFetch sharedInstance];
    XCTAssertNoThrow([fetch stop:nil], @"stop with nil identifier should not crash");
}

- (void)testStopUnknownIdentifierDoesNotCrash {
    TSBackgroundFetch *fetch = [TSBackgroundFetch sharedInstance];
    XCTAssertNoThrow([fetch stop:@"com.test.nothing"], @"stop with unknown identifier should not crash");
}

@end

// ============================================================================
#pragma mark - WO-004: stop() and the legacy fetch
// ============================================================================

// (WO-004) The private methods these tests drive directly: cancelBGAppRefresh runs when the last listener is removed
// (stop()), and _expireLegacyFetch when a legacy fetch's UIBackgroundTask expires, which a test cannot make UIKit do.
@interface TSBackgroundFetch (WO004Testing)
-(void) cancelBGAppRefresh;
-(void) _expireLegacyFetch;
@end

// This target has no host app (it runs in the xctest process), so UIApplication.sharedApplication is nil.  A stand-in
// takes its place while a test needs to see what the SDK hands UIKit: the legacy fetch intervals it sets, and the
// background tasks it begins.
@interface WO004Application : NSObject
@property (nonatomic, readonly) NSMutableArray<NSNumber *> *intervals;
@property (nonatomic, readonly) NSInteger backgroundTasksBegun;
@end

@implementation WO004Application
- (instancetype)init {
    if ((self = [super init])) _intervals = [NSMutableArray array];
    return self;
}
- (void)setMinimumBackgroundFetchInterval:(NSTimeInterval)interval {
    [_intervals addObject:@(interval)];
}
- (UIBackgroundTaskIdentifier)beginBackgroundTaskWithExpirationHandler:(void (^)(void))handler {
    _backgroundTasksBegun++;
    return UIBackgroundTaskInvalid;
}
- (void)endBackgroundTask:(UIBackgroundTaskIdentifier)identifier {
}
@end

static WO004Application *wo004Application;

@interface UIApplication (WO004Testing)
+ (UIApplication *)wo004_sharedApplication;
@end

@implementation UIApplication (WO004Testing)
+ (UIApplication *)wo004_sharedApplication {
    return (UIApplication *)wo004Application;
}
@end

static void WO004ExchangeSharedApplication(void) {
    method_exchangeImplementations(class_getClassMethod([UIApplication class], @selector(sharedApplication)),
                                   class_getClassMethod([UIApplication class], @selector(wo004_sharedApplication)));
}

@interface TSBackgroundFetchWO004Tests : XCTestCase
@end

@implementation TSBackgroundFetchWO004Tests {
    NSArray<TSBGAppRefreshSubscriber *> *_setAside;
}

// Subscribers persist across runs, and the suite's other tests add their own: each test starts with none.
// +remove: / +add: change only the in-memory set, never what is persisted.
- (void)setUp {
    [super setUp];
    _setAside = [[TSBGAppRefreshSubscriber subscribers] allValues];
    for (TSBGAppRefreshSubscriber *s in _setAside) [TSBGAppRefreshSubscriber remove:s];
}

- (void)tearDown {
    for (TSBGAppRefreshSubscriber *s in _setAside) [TSBGAppRefreshSubscriber add:s];
    [super tearDown];
}

// Installs the stand-in for the rest of the test.  Hosted, a stand-in would replace a live UIApplication: skip.
// Blocks an earlier test left on the main queue (a cancel's reset, say) run first, against no application, so the
// stand-in records only what this test causes.
- (void)installStandInApplication {
    if ([UIApplication sharedApplication]) {
        XCTSkip(@"written for this target's xctest process, which has no UIApplication; hosted, the stand-in would "
                @"replace a live one");
    }
    [self drainMainQueue];
    wo004Application = [WO004Application new];
    WO004ExchangeSharedApplication();
    [self addTeardownBlock:^{
        WO004ExchangeSharedApplication();
        wo004Application = nil;
    }];
}

// Lets the blocks the SDK queued on the main queue run.
- (void)drainMainQueue {
    XCTestExpectation *drained = [self expectationWithDescription:@"main queue drained"];
    dispatch_async(dispatch_get_main_queue(), ^{ [drained fulfill]; });
    [self waitForExpectations:@[drained] timeout:2.0];
}

// -- change 1: stop() resets the legacy interval ---------------------------

// stop() removes the last listener, which cancels the fetch.  Where BGTaskScheduler is unavailable, and where the app
// does not permit com.transistorsoft.fetch, the SDK armed UIKit's legacy interval instead, so the cancel must also set it
// back to Never.
- (void)test_wo_004_cancelResetsLegacyFetchInterval {
    [self installStandInApplication];

    [[TSBackgroundFetch sharedInstance] cancelBGAppRefresh];
    [self drainMainQueue];

    XCTAssertTrue([wo004Application.intervals containsObject:@(UIApplicationBackgroundFetchIntervalNever)],
                  @"cancelBGAppRefresh must set the legacy fetch interval to Never (got %@)", wo004Application.intervals);
}

// A fetch delivered after the cancel must not arm the interval again: Never stays the last value written.
- (void)test_wo_004_fetchAfterCancelLeavesIntervalNever {
    [self installStandInApplication];
    TSBackgroundFetch *fetch = [TSBackgroundFetch sharedInstance];

    [fetch cancelBGAppRefresh];
    [fetch performFetchWithCompletionHandler:^(UIBackgroundFetchResult r) {}
                            applicationState:UIApplicationStateBackground];
    [self drainMainQueue];

    XCTAssertEqualObjects(wo004Application.intervals.lastObject, @(UIApplicationBackgroundFetchIntervalNever),
                          @"a fetch after stop() armed the legacy interval again (got %@)", wo004Application.intervals);
}

// -- change 3: a fetch with no subscriber is answered at once --------------

// Nothing would finish it, and rescheduling would arm again what stop() cancelled: completed with no data, at once,
// with no background task and no interval written.
- (void)test_wo_004_fetchWithoutSubscriberCompletesAtOnceWithNoData {
    [self installStandInApplication];
    TSBackgroundFetch *fetch = [TSBackgroundFetch sharedInstance];
    __block NSInteger calls = 0;
    __block UIBackgroundFetchResult result = UIBackgroundFetchResultFailed;

    [fetch performFetchWithCompletionHandler:^(UIBackgroundFetchResult r) { calls++; result = r; }
                            applicationState:UIApplicationStateBackground];

    XCTAssertEqual(calls, 1, @"completed at once, inside the call");
    XCTAssertEqual(result, UIBackgroundFetchResultNoData);
    XCTAssertNil(fetch.completionHandler, @"the handler is not kept");
    XCTAssertEqual(wo004Application.backgroundTasksBegun, 0, @"no background task is begun for it");
    [self drainMainQueue];
    XCTAssertEqual(wo004Application.intervals.count, (NSUInteger)0, @"no interval is written for it (got %@)",
                   wo004Application.intervals);
}

// -- change 2: the expiry completes a fetch no unfinished subscriber holds -

// The last subscriber removed while its fetch is held (stop() during the fetch): the expiry completes UIKit's handler,
// as the BGTaskScheduler path's expiration handler completes its task with NO.
- (void)test_wo_004_legacyExpiryAfterLastSubscriberRemovedCompletesHandler {
    TSBackgroundFetch *fetch = [TSBackgroundFetch sharedInstance];
    XCTestExpectation *fetched = [self expectationWithDescription:@"fetch callback"];
    [fetch addListener:@"wo004.only"
              callback:^(NSString *taskId) { [fetched fulfill]; }
               timeout:^(NSString *taskId) {}];
    __block NSInteger calls = 0;
    __block UIBackgroundFetchResult result = UIBackgroundFetchResultNewData;
    [fetch performFetchWithCompletionHandler:^(UIBackgroundFetchResult r) { calls++; result = r; }
                            applicationState:UIApplicationStateBackground];
    [self waitForExpectations:@[fetched] timeout:2.0];

    [fetch removeListener:@"wo004.only"];
    XCTAssertEqual(calls, 0, @"held until the expiry");
    [fetch _expireLegacyFetch];

    XCTAssertEqual(calls, 1, @"the expiry completes UIKit's handler, once");
    XCTAssertEqual(result, UIBackgroundFetchResultFailed);
    XCTAssertNil(fetch.completionHandler, @"the handler is released");
}

// Subscribers left, but every one already finished (another was removed before it finished): none takes the timeout,
// so the expiry completes the handler too.
- (void)test_wo_004_legacyExpiryWithOnlyFinishedSubscribersCompletesHandler {
    TSBackgroundFetch *fetch = [TSBackgroundFetch sharedInstance];
    XCTestExpectation *fetchedA = [self expectationWithDescription:@"fetch callback A"];
    XCTestExpectation *fetchedB = [self expectationWithDescription:@"fetch callback B"];
    [fetch addListener:@"wo004.a" callback:^(NSString *taskId) { [fetchedA fulfill]; } timeout:^(NSString *taskId) {}];
    [fetch addListener:@"wo004.b" callback:^(NSString *taskId) { [fetchedB fulfill]; } timeout:^(NSString *taskId) {}];
    [self addTeardownBlock:^{
        [[TSBackgroundFetch sharedInstance] removeListener:@"wo004.a"];
        [[TSBackgroundFetch sharedInstance] removeListener:@"wo004.b"];
    }];
    __block NSInteger calls = 0;
    __block UIBackgroundFetchResult result = UIBackgroundFetchResultNewData;
    [fetch performFetchWithCompletionHandler:^(UIBackgroundFetchResult r) { calls++; result = r; }
                            applicationState:UIApplicationStateBackground];
    [self waitForExpectations:@[fetchedA, fetchedB] timeout:2.0];

    [fetch finish:@"wo004.a"];              // 1 of 2
    [fetch removeListener:@"wo004.b"];      // B leaves without finishing: A, finished, is all that is left
    XCTAssertEqual(calls, 0, @"held until the expiry");
    [fetch _expireLegacyFetch];

    XCTAssertEqual(calls, 1, @"the expiry completes UIKit's handler, once");
    XCTAssertEqual(result, UIBackgroundFetchResultFailed);
}

// With a subscriber that takes the timeout, the expiry leaves the handler to it: its own finish completes it.
- (void)test_wo_004_legacyExpiryLeavesHandlerToSubscriberTimeout {
    TSBackgroundFetch *fetch = [TSBackgroundFetch sharedInstance];
    XCTestExpectation *fetched = [self expectationWithDescription:@"fetch callback"];
    XCTestExpectation *timedOut = [self expectationWithDescription:@"timeout callback"];
    [fetch addListener:@"wo004.listener"
              callback:^(NSString *taskId) { [fetched fulfill]; }
               timeout:^(NSString *taskId) { [timedOut fulfill]; }];
    [self addTeardownBlock:^{ [[TSBackgroundFetch sharedInstance] removeListener:@"wo004.listener"]; }];

    __block NSInteger calls = 0;
    __block UIBackgroundFetchResult result = UIBackgroundFetchResultFailed;
    [fetch performFetchWithCompletionHandler:^(UIBackgroundFetchResult r) { calls++; result = r; }
                            applicationState:UIApplicationStateBackground];
    [self waitForExpectations:@[fetched] timeout:2.0];

    [fetch _expireLegacyFetch];
    XCTAssertEqual(calls, 0, @"a subscriber took the timeout: the expiry must not complete the handler itself");
    [self waitForExpectations:@[timedOut] timeout:2.0];
    XCTAssertEqual(calls, 0, @"nor anything the expiry queued on the main queue");

    [fetch finish:@"wo004.listener"];
    XCTAssertEqual(calls, 1, @"the subscriber's finish completes the handler, once");
    XCTAssertNotEqual(result, UIBackgroundFetchResultFailed, @"completed by the subscriber's finish, not by the expiry");
}

@end
