//
//  WebOSTVServiceSocketClientTests.m
//  ConnectSDK
//
//  Created by Eugene Nikolskyi on 2/6/15.
//  Copyright (c) 2015 LG Electronics. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>

#import "WebOSTVService.h"
#import "WebOSTVServiceSocketClient_Private.h"

/// Tests for the @c WebOSTVServiceSocketClient class.
@interface WebOSTVServiceSocketClientTests : XCTestCase

@end

@implementation WebOSTVServiceSocketClientTests

#pragma mark - Registration Tests

/// Tests that -[WebOSTVServiceSocketClientDelegate socket:registrationFailed:]
/// method is called when the user has reject pairing on the TV. In this case,
/// the TV first sends a response with pairing info, then an error with the same
/// message id.
/// https://github.com/ConnectSDK/Connect-SDK-iOS/issues/130
- (void)testDeniedPairingShouldCallRegistrationFailed {
    // Arrange
    id serviceMock = OCMClassMock([WebOSTVService class]);
    id webSocketMock = OCMClassMock([LGSRWebSocket class]);

    id socketClientDelegateMock = OCMProtocolMock(@protocol(WebOSTVServiceSocketClientDelegate));
    OCMStub([socketClientDelegateMock socket:OCMOCK_ANY didReceiveMessage:OCMOCK_ANY]).andReturn(YES);
    XCTestExpectation *registrationFailedCalled = [self expectationWithDescription:@"socket:registrationFailed: is called"];
    OCMExpect([socketClientDelegateMock socket:OCMOCK_NOTNIL
                            registrationFailed:OCMOCK_NOTNIL]).andDo(^(NSInvocation *_) {
        [registrationFailedCalled fulfill];
    });

    // have to install a partial mock on the SUT (class under test) to stub
    // the web socket object (LGSRWebSocket) and some manifest.
    WebOSTVServiceSocketClient *socketClient = OCMPartialMock([[WebOSTVServiceSocketClient alloc] initWithService:serviceMock]);
    socketClient.delegate = socketClientDelegateMock;
    OCMStub([socketClient createSocketWithURLRequest:OCMOCK_ANY]).andReturn(webSocketMock);
    OCMStub([socketClient manifest]).andReturn(@{});

    // Act
    [socketClient connect];

    OCMStub([webSocketMock send:OCMOCK_ANY]).andDo(^(NSInvocation *inv) {
        __unsafe_unretained NSString *tmp;
        [inv getArgument:&tmp atIndex:2];
        NSString *msg = tmp;

        if (NSNotFound != [msg rangeOfString:@"\"hello\""].location) {
            NSString *response = @"{\"type\":\"hello\",\"payload\":{\"protocolVersion\":1,\"deviceType\":\"tv\",\"deviceOS\":\"webOS\",\"deviceOSVersion\":\"4.0.3\",\"deviceOSReleaseVersion\":\"1.3.2\",\"deviceUUID\":\"3C763B8E-8AED-4330-8838-3B1CFABBC16A\",\"pairingTypes\":[\"PIN\",\"PROMPT\"]}}";
            dispatch_async(dispatch_get_main_queue(), ^{
                [socketClient webSocket:webSocketMock didReceiveMessage:response];
            });
        } else if (NSNotFound != [msg rangeOfString:@"\"register\""].location) {
            // here a pairing alert is displayed on TV
            NSString *response = @"{\"type\":\"response\",\"id\":\"2\",\"payload\":{\"pairingType\":\"PROMPT\",\"returnValue\":true}}";
            dispatch_async(dispatch_get_main_queue(), ^{
                [socketClient webSocket:webSocketMock didReceiveMessage:response];
            });

            // here the user has rejected access
            NSString *error = @"{\"type\":\"error\",\"id\":\"2\",\"error\":\"403 User denied access\",\"payload\":\"\"}";
            dispatch_async(dispatch_get_main_queue(), ^{
                [socketClient webSocket:webSocketMock didReceiveMessage:error];
            });
        } else {
            XCTFail(@"Unexpected request %@", msg);
        }
    });
    [socketClient webSocketDidOpen:webSocketMock];

    // Assert
    [self waitForExpectationsWithTimeout:kDefaultAsyncTestTimeout
                                 handler:^(NSError *error) {
                                     XCTAssertNil(error);
                                     OCMVerifyAll(socketClientDelegateMock);
                                 }];
}

@end
