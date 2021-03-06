//
//  TUTViewController.m
//  tutanota
//
//  Created by Tutao GmbH on 13.07.18.
//  Copyright © 2018 Tutao GmbH. All rights reserved.
//

// Sweet, sweet sugar
#import "Swiftier.h"
#import "PSPDFFastEnumeration.h"

// App classes
#import "TUTAppDelegate.h"
#import "TUTViewController.h"
#import "TUTCrypto.h"
#import "TUTFileChooser.h"
#import "TUTContactsSource.h"
#import "TUTEncodingConverter.h"

// Frameworks
#import <WebKit/WebKit.h>
#import <SafariServices/SafariServices.h>
#import <UIkit/UIkit.h>

// Runtime magic
#import <objc/message.h>

typedef void(^VoidCallback)(void);

@interface TUTViewController () <WKNavigationDelegate, WKScriptMessageHandler>
@property WKWebView *webView;
@property double keyboardSize;
@property (readonly, nonnull) TUTCrypto *crypto;
@property (readonly, nonnull) TUTFileChooser *fileChooser;
@property (readonly, nonnull) TUTFileUtil *fileUtil;
@property (readonly, nonnull) TUTContactsSource *contactsSource;
@property (readonly, nonnull) NSMutableDictionary<NSString *, void(^)(NSDictionary * _Nullable value)> *requests;
@property NSInteger requestId;
@property (nullable) NSString *pushTokenRequestId;
@property BOOL webViewInitialized;
@property (readonly, nonnull) NSMutableArray<VoidCallback> *requestsBeforeInit;
@end

@implementation TUTViewController

- (instancetype)init
{
	self = [super init];
	if (self) {
		_crypto = [TUTCrypto new];
		_fileChooser = [[TUTFileChooser alloc] initWithViewController:self];
		_fileUtil = [[TUTFileUtil alloc] initWithViewController:self];
		_contactsSource = [TUTContactsSource new];
		_keyboardSize = 0;
		_webViewInitialized = false;
		_requestsBeforeInit = [NSMutableArray new];
	}
	return self;
}

- (void)loadView {
	[super loadView];
	[self hideAccessoryBar];
	WKWebViewConfiguration *config = [WKWebViewConfiguration new];
	_webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
	[_webView.configuration.preferences setValue:@YES forKey:@"allowFileAccessFromFileURLs"];
	_webView.navigationDelegate = self;
	_webView.scrollView.bounces = false;
	_webView.scrollView.scrollEnabled = NO;
	_webView.scrollView.delegate = self;
	if (@available(iOS 11.0, *)) {
  		_webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
	}


    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(onKeyboardDidShow:) name:UIKeyboardDidShowNotification object:nil];
    [nc addObserver:self selector:@selector(onKeyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    [nc addObserver:self selector:@selector(onKeyboardSizeChange:) name:UIKeyboardDidChangeFrameNotification object:nil];

	[config.userContentController addScriptMessageHandler:self name:@"nativeApp"];
	[self keyboardDisplayDoesNotRequireUserAction];
}

- (void)hideAccessoryBar {
	let WKClassString = [@[@"WK", @"Content", @"View"] componentsJoinedByString:@""];
	let method = class_getInstanceMethod(NSClassFromString(WKClassString), @selector(inputAccessoryView));
	IMP newImp = imp_implementationWithBlock(^(id _s) {
		return nil;
	});
	method_setImplementation(method, newImp);
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self.view addSubview:_webView];
	_webView.translatesAutoresizingMaskIntoConstraints = NO;
	[_webView.leftAnchor constraintEqualToAnchor:self.view.leftAnchor].active = YES;
	[_webView.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = YES;
	[_webView.rightAnchor constraintEqualToAnchor:self.view.rightAnchor].active = YES;
	[_webView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;
	[self loadMainPageWithParams:nil];
}

- (void)userContentController:(nonnull WKUserContentController *)userContentController didReceiveScriptMessage:(nonnull WKScriptMessage *)message {
	let jsonData = [[message body] dataUsingEncoding:NSUTF8StringEncoding];
	NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
	//NSLog(@"Message dict: %@", json);
	NSString *type = json[@"type"];
	NSString *requestId = json[@"id"];
	NSArray *arguments = json[@"args"];

	void (^sendResponseBlock)(id, NSError *) = [self responseBlockForRequestId:requestId];

	if ([@"response" isEqualToString:type]) {
		id value = json[@"value"];
		[self handleResponseWithId:requestId value:value];
	} else if ([@"init" isEqualToString:type]) {
		_webViewInitialized = YES;
		[self sendResponseWithId:requestId value:@"ios"];
		foreach(callback, _requestsBeforeInit) {
			callback();
		}
		[_requestsBeforeInit removeAllObjects];
	} else if ([@"rsaEncrypt" isEqualToString:type]) {
		[_crypto rsaEncryptWithPublicKey:arguments[0] base64Data:arguments[1] base64Seed:arguments[2] completion:sendResponseBlock];
	} else if ([@"rsaDecrypt" isEqualToString:type]) {
		[_crypto rsaDecryptWithPrivateKey:arguments[0]
							   base64Data:arguments[1]
							   completion:sendResponseBlock];
	} else if ([@"reload" isEqualToString:type]) {
		_webViewInitialized = NO;
		dispatch_async(dispatch_get_main_queue(), ^{
			[self loadMainPageWithParams:arguments[0]];
		});
		[self sendResponseWithId:requestId value:[NSNull null]];
	} else if ([@"generateRsaKey" isEqualToString:type]) {
		[_crypto generateRsaKeyWithSeed:arguments[0] completion: sendResponseBlock];
	} else if ([@"openFileChooser" isEqualToString:type]) {
		NSDictionary *rectDict = arguments[0];
		let rect = CGRectMake(
							  ((NSNumber *) rectDict[@"x"]).doubleValue,
							  ((NSNumber *) rectDict[@"y"]).doubleValue,
							  ((NSNumber *) rectDict[@"width"]).doubleValue,
							  ((NSNumber *) rectDict[@"height"]).doubleValue
							  );
		[_fileChooser openWithAnchorRect:rect completion: sendResponseBlock];
	} else if ([@"getName" isEqualToString:type]) {
		[_fileUtil getNameForPath:arguments[0] completion:sendResponseBlock];
	} else if ([@"getSize" isEqualToString:type]) {
		[_fileUtil getSizeForPath:arguments[0] completion:sendResponseBlock];
	} else if ([@"getMimeType" isEqualToString:type]) {
		[_fileUtil getMimeTypeForPath:arguments[0] completion:sendResponseBlock];
	} else if ([@"changeTheme" isEqualToString:type]) {
		// No-op for now
		sendResponseBlock(NSNull.null, nil);
	} else if ([@"aesEncryptFile" isEqualToString:type]) {
		[_crypto aesEncryptFileWithKey:arguments[0] atPath:arguments[1] completion:sendResponseBlock];
	} else if ([@"aesDecryptFile" isEqualToString:type]) {
		[_crypto aesDecryptFileWithKey:arguments[0] atPath:arguments[1] completion:sendResponseBlock];
	} else if([@"upload" isEqualToString:type]) {
		[_fileUtil uploadFileAtPath:arguments[0] toUrl:arguments[1] withHeaders:arguments[2] completion:sendResponseBlock];
	} else if ([@"deleteFile" isEqualToString:type]) {
		[_fileUtil deleteFileAtPath:arguments[0] completion:^{
			sendResponseBlock(NSNull.null, nil);
		}];
	} else if ([@"clearFileData" isEqualToString:type]) {
		[_fileUtil clearFileData];
		sendResponseBlock(NSNull.null, nil);
	} else if ([@"download" isEqualToString:type]) {
		[_fileUtil downloadFileFromUrl:arguments[0]
							   forName:arguments[1]
						   withHeaders:arguments[2]
							completion:sendResponseBlock];
	} else if ([@"open" isEqualToString:type]) {
		[_fileUtil openFileAtPath:arguments[0] completion:^(NSError * _Nullable error) {
			if (error != nil) {
				[self sendErrorResponseWithId:requestId value:error];
			} else {
				[self sendResponseWithId:requestId value:NSNull.null];
			}
		}];
	} else if ([@"getPushIdentifier" isEqualToString:type]) {
		[((TUTAppDelegate *) UIApplication.sharedApplication.delegate) registerForPushNotificationsWithCallback:sendResponseBlock];
	} else if ([@"findSuggestions" isEqualToString:type]) {
		[_contactsSource searchForContactsUsingQuery:arguments[0]
										  completion:sendResponseBlock];
	} else if ([@"closePushNotifications" isEqualToString:type]) {
		[UIApplication.sharedApplication setApplicationIconBadgeNumber:0];
		sendResponseBlock(NSNull.null, nil);
	} else if ([@"openLink" isEqualToString:type]) {
		[UIApplication.sharedApplication openURL:[NSURL URLWithString:arguments[0]]
										 options:@{}
							   completionHandler:^(BOOL success) {
								   sendResponseBlock(@(success), nil);
							   }];
	} else if ([@"saveBlob" isEqualToString:type]) {
		NSString* fileDataB64 = arguments[1];
		let fileData = [TUTEncodingConverter base64ToBytes:fileDataB64];
		[_fileUtil openFile:arguments[0] fileData:fileData completion:^(NSError * _Nullable error) {
			if (error != nil) {
				[self sendErrorResponseWithId:requestId value:error];
			} else {
				[self sendResponseWithId:requestId value:NSNull.null];
			}
		}];
	} else {
		let message = [NSString stringWithFormat:@"Unknown command: %@", type];
		NSLog(@"%@", message);
		let error = [NSError errorWithDomain:@"tutanota" code:5 userInfo:@{@"message":message}];
		[self sendErrorResponseWithId:requestId value:error];
	}
}

-(void (^)(id, NSError *))responseBlockForRequestId:(NSString *)requestId {
	return ^void(id value, NSError *error) {
		if (error == nil) {
			[self sendResponseWithId:requestId value:value];
		} else {
			[self sendErrorResponseWithId:requestId value:error];
		}
	};
}

- (void) loadMainPageWithParams:(NSString * _Nullable)params {
	var fileUrl = [self appUrl];
	let folderUrl = [fileUrl URLByDeletingLastPathComponent];
	if (params != nil) {
		let newUrlString = [NSString stringWithFormat:@"%@%@", [fileUrl absoluteString], params];
		fileUrl = [NSURL URLWithString:newUrlString];
	}
	[_webView loadFileURL:fileUrl allowingReadAccessToURL:folderUrl];
}

- (void) sendResponseWithId:(NSString*)responseId value:(id)value {
	[self sendResponseWithId:responseId type:@"response" value:value];
}

- (void) sendErrorResponseWithId:(NSString*)responseId value:(NSError *)value {
	var *message = @"";
	if (value.userInfo && [value isKindOfClass:NSDictionary.class]) {
		let dict = (NSDictionary *)value.userInfo;
		let newDict = [NSMutableDictionary new];
		foreach(key, dict) {
			const NSObject *value = dict[key];
			newDict[key] = value.description;
		}
		message = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:newDict options:0 error:nil]
										encoding:NSUTF8StringEncoding];
	}

	let errorDict = @{
					  @"name":[value domain],
					  @"message":[NSString stringWithFormat:@"code: %ld message: %@", (long)value.code, message]
					  };
	[self postMessage:@{
					 @"id":responseId,
					 @"type":@"requestError",
					 @"error":errorDict
					 }];
}

- (void) sendResponseWithId:(NSString *)responseId type:(NSString *)type value:(id)value {
	let response = @{
					 @"id":responseId,
					 @"type":type,
					 @"value":value
					 };

	[self postMessage:response];
}

- (void) postMessage:(NSDictionary *)message {
	let jsonData = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
	dispatch_async(dispatch_get_main_queue(), ^{
		let base64 = [jsonData base64EncodedStringWithOptions:0];
		let js = [NSString stringWithFormat:@"tutao.nativeApp.handleMessageFromNative('%@')", base64];
		[self->_webView evaluateJavaScript:js completionHandler:nil];
	});
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
	// We need to implement this bridging from native because we don't know if we are an iOS app before the init event
	[_webView evaluateJavaScript:@"window.nativeApp = {invoke: (message) => window.webkit.messageHandlers.nativeApp.postMessage(message)}"
			   completionHandler:nil];
}

- (nonnull NSURL *)appUrl {
	NSString *filePath = [NSString stringWithFormat:@"%@%@", NSBundle.mainBundle.infoDictionary[@"TutanotaApplicationPath"], @"app"];
	let path = [NSBundle.mainBundle pathForResource:filePath ofType:@"html"];
	// For running tests
	if (path == nil) {
		return NSBundle.mainBundle.resourceURL;
	}
	return [NSURL fileURLWithPath:path];
}

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
	if ([[navigationAction.request.URL absoluteString] hasPrefix:[self appUrl].absoluteString]) {
		decisionHandler(WKNavigationActionPolicyAllow);
	} else {
		decisionHandler(WKNavigationActionPolicyCancel);
		[[UIApplication sharedApplication] openURL:navigationAction.request.URL options:@{} completionHandler:NULL];
	}
}

-(void)sendRequestWithType:(NSString * _Nonnull)type
					  args:(NSArray<id> * _Nonnull)args
				completion:(void(^ _Nullable)(NSDictionary * _Nullable value))completion {
	if (!_webViewInitialized) {
		let callback = ^void() { [self sendRequestWithType:type args:args completion:completion]; };
		[_requestsBeforeInit addObject:callback];
		return;
	}

	let requestId = [NSString stringWithFormat:@"app%ld", (long) _requestId++];
	if (completion) {
		_requests[requestId] = completion;
	}
	let json = @{
				 @"id": requestId,
				 @"type": type,
				 @"args": args
				 };
	[self postMessage:json];
}

-(void)handleResponseWithId:(NSString *)requestId value:(id)value {
	let request = _requests[requestId];
	if (request) {
		[_requests removeObjectForKey:requestId];
		request(value);
	}

}

// Swizzling WebKit to be show keyboard when we call focus() on fields
// Work quite slowly so forms should not be focused at the time of animation
// https://github.com/Telerik-Verified-Plugins/WKWebView/commit/04e8296adeb61f289f9c698045c19b62d080c7e3#L609-L620
- (void) keyboardDisplayDoesNotRequireUserAction {
   Class class = NSClassFromString(@"WKContentView");
    NSOperatingSystemVersion iOS_11_3_0 = (NSOperatingSystemVersion){11, 3, 0};

    if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion: iOS_11_3_0]) {
        SEL selector = sel_getUid("_startAssistingNode:userIsInteracting:blurPreviousNode:changingActivityState:userObject:");
        Method method = class_getInstanceMethod(class, selector);
        IMP original = method_getImplementation(method);
        IMP override = imp_implementationWithBlock(^void(id me, void* arg0, BOOL arg1, BOOL arg2, BOOL arg3, id arg4) {
            ((void (*)(id, SEL, void*, BOOL, BOOL, BOOL, id))original)(me, selector, arg0, TRUE, arg2, arg3, arg4);
        });
        method_setImplementation(method, override);
    } else {
        SEL selector = sel_getUid("_startAssistingNode:userIsInteracting:blurPreviousNode:userObject:");
        Method method = class_getInstanceMethod(class, selector);
        IMP original = method_getImplementation(method);
        IMP override = imp_implementationWithBlock(^void(id me, void* arg0, BOOL arg1, BOOL arg2, id arg3) {
            ((void (*)(id, SEL, void*, BOOL, BOOL, id))original)(me, selector, arg0, TRUE, arg2, arg3);
        });
        method_setImplementation(method, override);
    }
}

- (void)onKeyboardSizeChange:(NSNotification *)note {
    let rect = [[note.userInfo valueForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    int currentSize = rect.size.height;
	if (_keyboardSize != 0 && _keyboardSize != currentSize) {
		_keyboardSize = currentSize;
		[self sendRequestWithType:@"keyboardSizeChanged" args:@[[NSNumber numberWithDouble:_keyboardSize]]completion:nil];
	}
}

- (void)onKeyboardDidShow:(NSNotification *)note {
	let rect = [[note.userInfo valueForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
	_keyboardSize = rect.size.height;
	[self sendRequestWithType:@"keyboardSizeChanged" args:@[[NSNumber numberWithDouble:_keyboardSize]]completion:nil];
}

- (void)onKeyboardWillHide:(NSNotification *)note {
	_keyboardSize = 0;
  	[self sendRequestWithType:@"keyboardSizeChanged" args:@[[NSNumber numberWithDouble:_keyboardSize]]completion:nil];
}


-(void)scrollViewDidScroll:(UIScrollView *)scrollView {
	// disable scrolling of the web view to avoid that the keyboard moves the body out of the screen
	scrollView.contentOffset = CGPointZero;
}

@end
