/*
 *
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 *
 */

#import "CDVOrientation.h"
#import <Cordova/CDVViewController.h>
#import <objc/message.h>
#import <objc/runtime.h>

// ---------------------------------------------------------------------------
// cordova-ios 8.0 compatibility shim
//
// cordova-ios 8.0 removed setSupportedOrientations: and the corresponding
// supportedInterfaceOrientations override from CDVViewController.  Without
// these the view controller always reports "all orientations" to UIKit, which
// causes setNeedsUpdateOfSupportedInterfaceOrientations (called after
// requestGeometryUpdateWithPreferences:) to immediately undo the geometry
// preference we just set.
//
// The fix: swizzle -[CDVViewController supportedInterfaceOrientations] at
// +load time so we can store and return a restricted orientation mask via an
// associated object – exactly what setSupportedOrientations: used to do.
// ---------------------------------------------------------------------------

/// Associated-object key for the active UIInterfaceOrientationMask (NSNumber).
static char kCDVOrientationMaskKey;

/// Original IMP of -[CDVViewController supportedInterfaceOrientations].
static IMP _cdvOriginalSupportedOrientations = NULL;

/**
 * Swizzled replacement for -[CDVViewController supportedInterfaceOrientations].
 * Returns the mask stored by this plugin when an orientation lock is active,
 * otherwise falls through to the original implementation.
 */
static UIInterfaceOrientationMask CDVOrientation_supportedInterfaceOrientations(id self, SEL _cmd) {
    NSNumber *mask = objc_getAssociatedObject(self, &kCDVOrientationMaskKey);
    if (mask) {
        return [mask unsignedIntegerValue];
    }
    if (_cdvOriginalSupportedOrientations) {
        return ((UIInterfaceOrientationMask (*)(id, SEL))_cdvOriginalSupportedOrientations)(self, _cmd);
    }
    return UIInterfaceOrientationMaskAll;
}

@interface CDVOrientation () {}
@end

@implementation CDVOrientation

+ (void)load {
    // Only swizzle when setSupportedOrientations: is absent (cordova-ios 8.0+).
    Class vcClass = NSClassFromString(@"CDVViewController");
    if (!vcClass) return;
    if ([vcClass instancesRespondToSelector:NSSelectorFromString(@"setSupportedOrientations:")]) {
        return; // cordova-ios < 8.0 – legacy path handles orientation
    }

    SEL targetSel = @selector(supportedInterfaceOrientations);
    Method method = class_getInstanceMethod(vcClass, targetSel);
    if (method) {
        _cdvOriginalSupportedOrientations = method_getImplementation(method);
        class_replaceMethod(vcClass, targetSel,
                            (IMP)CDVOrientation_supportedInterfaceOrientations,
                            method_getTypeEncoding(method));
    }
}


-(void)handleBelowEqualIos15WithOrientationMask:(NSInteger) orientationMask viewController: (CDVViewController*) vc result:(NSMutableArray*) result selector:(SEL) selector
{
    NSValue *value;
    if (orientationMask != 15) {
        if (!_isLocked) {
            _lastOrientation = [UIApplication sharedApplication].statusBarOrientation;
        }
        UIInterfaceOrientation deviceOrientation = [UIApplication sharedApplication].statusBarOrientation;
        if(orientationMask == 8  || (orientationMask == 12  && !UIInterfaceOrientationIsLandscape(deviceOrientation))) {
            value = [NSNumber numberWithInt:UIInterfaceOrientationLandscapeLeft];
        } else if (orientationMask == 4){
            value = [NSNumber numberWithInt:UIInterfaceOrientationLandscapeRight];
        } else if (orientationMask == 1 || (orientationMask == 3 && !UIInterfaceOrientationIsPortrait(deviceOrientation))) {
            value = [NSNumber numberWithInt:UIInterfaceOrientationPortrait];
        } else if (orientationMask == 2) {
            value = [NSNumber numberWithInt:UIInterfaceOrientationPortraitUpsideDown];
        }
    } else {
        if (_lastOrientation != UIInterfaceOrientationUnknown) {
            [[UIDevice currentDevice] setValue:[NSNumber numberWithInt:_lastOrientation] forKey:@"orientation"];
            // Guard: setSupportedOrientations: was removed in cordova-ios 8.0.0
            if ([vc respondsToSelector:selector]) {
                ((void (*)(CDVViewController*, SEL, NSMutableArray*))objc_msgSend)(vc,selector,result);
            }
            [UINavigationController attemptRotationToDeviceOrientation];
        }
    }
    if (value != nil) {
        _isLocked = true;
        [[UIDevice currentDevice] setValue:value forKey:@"orientation"];
    } else {
        _isLocked = false;
    }
}

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 160000
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
// this will stop it complaining about new iOS16 APIs being used.
-(void)handleAboveEqualIos16WithOrientationMask:(NSInteger) orientationMask viewController: (CDVViewController*) vc result:(NSMutableArray*) result selector:(SEL) selector
{
    NSObject *value;
    // orientationMask 15 is "unlock" the orientation lock.
    if (orientationMask != 15) {
        if (!_isLocked) {
            _lastOrientation = [UIApplication sharedApplication].statusBarOrientation;
        }
        UIInterfaceOrientation deviceOrientation = [UIApplication sharedApplication].statusBarOrientation;
        if(orientationMask == 8  || (orientationMask == 12  && !UIInterfaceOrientationIsLandscape(deviceOrientation))) {
            value = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscapeLeft];
        } else if (orientationMask == 4){
            value = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscapeRight];
        } else if (orientationMask == 1 || (orientationMask == 3 && !UIInterfaceOrientationIsPortrait(deviceOrientation))) {
            value = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskPortrait];
        } else if (orientationMask == 2) {
            value = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskPortraitUpsideDown];
        }
    } else {
        // Guard: setSupportedOrientations: was removed in cordova-ios 8.0.0
        if ([vc respondsToSelector:selector]) {
            ((void (*)(CDVViewController*, SEL, NSMutableArray*))objc_msgSend)(vc,selector,result);
        }
        // On iOS 16+, explicitly request all orientations to truly unlock.
        value = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskAll];
    }
    if (value != nil) {
        _isLocked = (orientationMask != 15);
        UIWindowScene *scene = (UIWindowScene*)[[UIApplication.sharedApplication connectedScenes] anyObject];
        [scene requestGeometryUpdateWithPreferences:(UIWindowSceneGeometryPreferencesIOS*)value errorHandler:^(NSError * _Nonnull error) {
            NSLog(@"Failed to change orientation  %@ %@", error, [error userInfo]);
        }];
    } else {
        _isLocked = false;
    }
}
#pragma clang diagnostic pop

-(void)handleWithOrientationMask:(NSInteger) orientationMask viewController: (CDVViewController*) vc result:(NSMutableArray*) result selector:(SEL) selector
{
    if (@available(iOS 16.0, *)) {
        [self handleAboveEqualIos16WithOrientationMask:orientationMask viewController:vc result:result selector:selector];
        // always double check the supported interfaces, so we update if needed
        // but do it right at the end here to avoid the "double" rotation issue reported in
        // https://github.com/apache/cordova-plugin-screen-orientation/pull/107
        [self.viewController setNeedsUpdateOfSupportedInterfaceOrientations];
    } else {
        [self handleBelowEqualIos15WithOrientationMask:orientationMask viewController:vc result:result selector:selector];
    }

}
#else
-(void)handleWithOrientationMask:(NSInteger) orientationMask viewController: (CDVViewController*) vc result:(NSMutableArray*) result selector:(SEL) selector
{
    [self handleBelowEqualIos15WithOrientationMask:orientationMask viewController:vc result:result selector:selector];
}
#endif


-(void)screenOrientation:(CDVInvokedUrlCommand *)command
{
    CDVPluginResult* pluginResult;
    NSInteger orientationMask = [[command argumentAtIndex:0] integerValue];
    CDVViewController* vc = (CDVViewController*)self.viewController;
    NSMutableArray* result = [[NSMutableArray alloc] init];

    if(orientationMask & 1) {
        [result addObject:[NSNumber numberWithInt:UIInterfaceOrientationPortrait]];
    }
    if(orientationMask & 2) {
        [result addObject:[NSNumber numberWithInt:UIInterfaceOrientationPortraitUpsideDown]];
    }
    if(orientationMask & 4) {
        [result addObject:[NSNumber numberWithInt:UIInterfaceOrientationLandscapeRight]];
    }
    if(orientationMask & 8) {
        [result addObject:[NSNumber numberWithInt:UIInterfaceOrientationLandscapeLeft]];
    }
    SEL selector = NSSelectorFromString(@"setSupportedOrientations:");

    if([vc respondsToSelector:selector]) {
        // cordova-ios < 8.0: use the legacy API
        if (orientationMask != 15 || [UIDevice currentDevice] == nil) {
            ((void (*)(CDVViewController*, SEL, NSMutableArray*))objc_msgSend)(vc,selector,result);
        }
    } else {
        // cordova-ios 8.0+: store the UIInterfaceOrientationMask as an associated
        // object on the CDVViewController so our swizzled
        // supportedInterfaceOrientations returns the restricted set.  This ensures
        // requestGeometryUpdateWithPreferences: (iOS 16+) is not overridden when
        // setNeedsUpdateOfSupportedInterfaceOrientations re-queries the VC.
        if (orientationMask == 15) {
            // Unlock: remove the override so the original implementation is used.
            objc_setAssociatedObject(vc, &kCDVOrientationMaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else {
            // Build UIInterfaceOrientationMask from the result array.
            // Each entry is a UIInterfaceOrientation enum value; the corresponding
            // mask bit is (1 << enumValue).
            UIInterfaceOrientationMask uiMask = 0;
            for (NSNumber *orientation in result) {
                uiMask |= (1 << [orientation integerValue]);
            }
            objc_setAssociatedObject(vc, &kCDVOrientationMaskKey, @(uiMask), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }

    if ([UIDevice currentDevice] != nil){
        [self handleWithOrientationMask:orientationMask viewController:vc result:result selector:selector];
    }

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];

}

@end
