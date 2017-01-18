//
//  AppDelegate.h
//  DisplayBacklight
//
//  Created by Thomas Buck on 21.12.15.
//  Copyright © 2015 xythobuz. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>

@class Serial;

@interface AppDelegate : NSObject <NSApplicationDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>

@property (weak) IBOutlet NSApplication *application;

- (void)stopAmbilight;
- (void)newDisplayList:(NSArray *)displayIDs;

@end

// ToDo: add support for display names or IDs here, so we can distinguish
// between multiple displays with the same resolution
struct DisplayAssignment {
    int width, height;
    int shown;
};

struct LEDStrand {
    int idMin, count;
    int display;
    int startX, startY;
    int direction;
    int size;
};

#define DIR_LEFT 0
#define DIR_RIGHT 1
#define DIR_UP 2
#define DIR_DOWN 3
