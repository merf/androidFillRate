//
//  AppDelegate.h
//  Test
//
//  Created by Neil Wallace on 04/02/2014.
//  Copyright (c) 2014 Neil Wallace. All rights reserved.
//

#import <UIKit/UIKit.h>

@class ViewController;
@class DFVideoAdDelegate;
@class FuseBridge;

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) ViewController *viewController;
@property (strong, nonatomic) DFVideoAdDelegate *videoAdDelegate;
@property (strong, nonatomic) FuseBridge *bridgeObject;

@end
