//
//  Screenshot.m
//  DisplayBacklight
//
//  Based on the Apple ScreenSnapshot example:
//  https://developer.apple.com/library/mac/samplecode/ScreenSnapshot/Listings/ScreenSnapshot_ScreenSnapshotAppDelegate_m.html
//
//  Created by Thomas Buck on 27.12.15.
//  Copyright © 2015 xythobuz. All rights reserved.
//

// Uncomment to store a screenshot for each display in the build directory
//#define DEBUG_SCREENSHOT

#import "AppDelegate.h"
#import "Screenshot.h"

static BOOL displayRegistrationCallBackSuccessful;

static void displayRegisterReconfigurationCallback(CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, void *userInfo) {
    AppDelegate *appDelegate = (__bridge AppDelegate*)userInfo;
    static BOOL DisplayConfigurationChanged = NO;
    
    // Before display reconfiguration, this callback fires to inform
    // applications of a pending configuration change. The callback runs
    // once for each on-line display.  The flags passed in are set to
    // kCGDisplayBeginConfigurationFlag.  This callback does not
    // carry other per-display information, as details of how a
    // reconfiguration affects a particular device rely on device-specific
    // behaviors which may not be exposed by a device driver.
    //
    // After display reconfiguration, at the time the callback function
    // is invoked, all display state reported by CoreGraphics, QuickDraw,
    // and the Carbon Display Manager API will be up to date.  This callback
    // runs after the Carbon Display Manager notification callbacks.
    // The callback runs once for each added, removed, and currently
    // on-line display.  Note that in the case of removed displays, calls into
    // the CoreGraphics API with the removed display ID will fail.
    
    // Because the callback is called for each display I use DisplayConfigurationChanged to
    // make sure we only disable the menu to change displays once and then refresh it only once.
    if (flags == kCGDisplayBeginConfigurationFlag) {
        if (DisplayConfigurationChanged == NO) {
            [appDelegate stopAmbilight];
            DisplayConfigurationChanged = YES;
        }
    } else if (DisplayConfigurationChanged == YES) {
        [appDelegate newDisplayList:[Screenshot listDisplays]];
        DisplayConfigurationChanged = NO;
    }
}

@implementation Screenshot

+ (void)init:(AppDelegate *)appDelegate {
    // Applications who want to register for notifications of display changes would use
    // CGDisplayRegisterReconfigurationCallback
    //
    // Display changes are reported via a callback mechanism.
    //
    // Callbacks are invoked when the app is listening for events,
    // on the event processing thread, or from within the display
    // reconfiguration function when in the program that is driving the
    // reconfiguration.
    displayRegistrationCallBackSuccessful = NO; // Hasn't been tried yet.
    CGError err = CGDisplayRegisterReconfigurationCallback(displayRegisterReconfigurationCallback, (__bridge void * _Nullable)(appDelegate));
    if (err == kCGErrorSuccess) {
        displayRegistrationCallBackSuccessful = YES;
    }
}

+ (void)close:(AppDelegate *)appDelegate {
    // CGDisplayRemoveReconfigurationCallback Removes the registration of a callback function that’s invoked
    // whenever a local display is reconfigured.  We only remove the registration if it was successful in the first place.
    if (displayRegistrationCallBackSuccessful == YES) {
        CGDisplayRemoveReconfigurationCallback(displayRegisterReconfigurationCallback, (__bridge void * _Nullable)(appDelegate));
    }
}

+ (NSArray *)listDisplays {
    CGDisplayCount dspCount = 0;
    CGError err = CGGetActiveDisplayList(0, NULL, &dspCount);
    if (err != CGDisplayNoErr) {
        NSLog(@"Couldn't list any active displays (%d)!\n", err);
        return nil;
    }
    
    CGDirectDisplayID *displays = calloc((size_t)dspCount, sizeof(CGDirectDisplayID));
    err = CGGetActiveDisplayList(dspCount, displays, &dspCount);
    if (err != CGDisplayNoErr) {
        NSLog(@"Couldn't get active display list (%d)!\n", err);
        return nil;
    }
    
    if (dspCount > 0) {
        NSMutableArray *array = [NSMutableArray arrayWithCapacity:dspCount];
        for (int i = 0; i < dspCount; i++) {
            [array addObject:[NSNumber numberWithInt:displays[i]]];
        }
    
        return [array copy];
    } else {
        NSLog(@"No displays found!\n");
        return nil;
    }
}

+ (NSString *)displayNameFromDisplayID:(NSNumber *)displayID {
    NSDictionary *displayInfo = CFBridgingRelease(IODisplayCreateInfoDictionary(CGDisplayIOServicePort([displayID unsignedIntValue]), kIODisplayOnlyPreferredName));
    NSDictionary *localizedNames = [displayInfo objectForKey:[NSString stringWithUTF8String:kDisplayProductName]];
    
    // Use the first name
    NSString *displayProductName = nil;
    if ([localizedNames count] > 0) {
        displayProductName = [localizedNames objectForKey:[[localizedNames allKeys] objectAtIndex:0]];
        
#ifdef DEBUG
        NSLog(@"Display %u named \"%@\"!\n", [displayID unsignedIntValue], displayProductName);
#endif
    }
    
    return displayProductName;
}

+ (NSBitmapImageRep *)screenshot:(NSNumber *)displayID {
    CGImageRef image = CGDisplayCreateImage([displayID unsignedIntValue]);
    NSBitmapImageRep *imgRep = [[NSBitmapImageRep alloc] initWithCGImage:image];
    CFRelease(image);
    
#ifdef DEBUG_SCREENSHOT
    NSData *data = [imgRep representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]];
    NSString *path = [NSString stringWithFormat:@"test-%u-%@.png", [displayID unsignedIntValue], [Screenshot displayNameFromDisplayID:displayID]];
    NSError *error;
    if ([data writeToFile:path options:0 error:&error] == YES) {
        NSLog(@"Wrote debug image to \"%@\"\n", path);
    } else {
        NSLog(@"Error writing debug image to \"%@\": %@\n", path, error);
    }
#endif
    
    return imgRep;
}

@end
