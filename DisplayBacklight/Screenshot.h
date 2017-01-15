//
//  Screenshot.h
//  DisplayBacklight
//
//  Created by Thomas Buck on 27.12.15.
//  Copyright © 2015 xythobuz. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Screenshot : NSThread

// Register and de-register the callback for configuration changes
+ (void)init:(AppDelegate *)appDelegate;
+ (void)close:(AppDelegate *)appDelegate;

// List available displays. Returns an array of numbers.
+ (NSArray *)listDisplays;

+ (NSString *)displayNameFromDisplayID:(NSNumber *)displayID;
+ (NSBitmapImageRep *)screenshot:(NSNumber *)displayID;

@end
