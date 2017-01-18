//
//  AppDelegate.m
//  DisplayBacklight
//
//  Created by Thomas Buck on 21.12.15.
//  Copyright © 2015 xythobuz. All rights reserved.
//

#import "AppDelegate.h"
#import "Serial.h"
#import "Screenshot.h"

// ----------------------- Config starts here -----------------------

// The idea behind this algorithm is very simple. It assumes that each LED strand
// follows one edge of one of your displays. So one of the two coordinates should
// always be zero or the width / height of your display.

// Define the amount of LEDs in your strip here
#define LED_COUNT 156

// This defines how large the averaging-boxes should be in the dimension perpendicular
// to the strand. So eg. for a bottom strand, how high the box should be in px.
#define COLOR_AVERAGE_OTHER_DIMENSION_SIZE 100

// Identify your displays here. Currently they're only distinguished by their resolution.
// The ID will be the index in the list, so the first entry is display 0 and so on.
// The third parameter is used internally for keeping track of the visualized displays,
// simply set it to 0.
struct DisplayAssignment displays[] = {
    { 1920, 1080, 0 },
    {  900, 1600, 0 }
};

// This defines the orientation and placement of your strands and is the most important part.
// It begins with the LED IDs this strand includes, starting with ID 0 up to LED_COUNT - 1.
// The second item is the length of this strip, as in the count of LEDs in it.
// The third item is the display ID, defined by the previous struct.
// The fourth and fifth items are the starting X and Y coordinates of the strand.
// As described above, one should always be zero or the display width / height.
// The sixth element is the direction the strand goes (no diagonals supported yet).
// The last element is the size of the averaging-box for each LED, moving with the strand.
// So, if your strand contains 33 LEDs and spans 1920 pixels, this should be (1920 / 33).
// By default you can always use (length in pixel / LED count) for the last item, except
// if your strand does not span the whole length of this screen edge.
//
// For example, this is my personal dual-monitor home setup. The strand starts at the 0
// in the bottom-right of D1, then goes left around D1, and from there around D2 back
// to the start.
//
//                                       29
//                                 |------------|
//                               5 | /|\ --> -->|
//                  33             |  |         |
//     |---------------------------|         |  |
//     |-->   -->   -->   -->   -->|        \|/ |
//     |                           |            |
//  19 | /|\        D1             |     D2     | 48
//     |  |      1920x1080         |  900x1600  |
//     |                           |            |
//     |<--   <--   <--   <--   <--| 0       |  |
//     |---------------------------| /|\    \|/ |
//                  33             |  |         |
//                               4 |  <--  <--  |
//                                 |------------|
//                                       29

struct LEDStrand strands[] = {
    {   0, 33, 0, 1920, 1080,  DIR_LEFT, 1920 / 33 },
    {  33, 19, 0,    0, 1080,    DIR_UP, 1080 / 19 },
    {  52, 33, 0,    0,    0, DIR_RIGHT, 1920 / 33 },
    {  85,  5, 1,    0,  250,    DIR_UP,  250 / 5 },
    {  90, 17, 1,    0,    0, DIR_RIGHT,  900 / 17 },
    { 107, 28, 1,  900,    0,  DIR_DOWN, 1600 / 28 },
    { 135, 17, 1,  900, 1600,  DIR_LEFT,  900 / 17 },
    { 152,  4, 1,    0, 1600,    DIR_UP,  180 / 4 }
};

// This defines the update-speed of the Ambilight, in seconds.
// With a baudrate of 115200 and 156 LEDs and 14-bytes Magic-Word,
// theoretically you could transmit:
//     115200 / (14 + (156 * 3)) * 8 =~ 30 Frames per Second
// Inserting (1.0 / 30.0) here would try to reach these 30FPS,
// but will probably cause high CPU-Usage.
// (Run-Time of the algorithm is ignored here, so real speed will be
// slightly lower.)
#define DISPLAY_DELAY (1.0 / 10.0)

// How many pixels to skip when calculating the average color.
// Slightly increases performance and doesn't really alter the result.
#define AVERAGE_PIXEL_SKIP 2

// Magic identifying string used to differntiate start of packets.
// Has to be the same here and in the Arduino Sketch.
#define MAGIC_WORD @"xythobuzRGBled"

// These are the values stored persistently in the preferences
#define PREF_SERIAL_PORT @"SerialPort"
#define PREF_BRIGHTNESS @"Brightness"
#define PREF_TURNED_ON @"IsEnabled"

// If this is defined it will print the FPS every DEBUG_PRINT_FPS seconds
#define DEBUG_PRINT_FPS 2.5

// ------------------------ Config ends here ------------------------

@interface AppDelegate ()

@property (weak) IBOutlet NSMenu *statusMenu;
@property (weak) IBOutlet NSMenu *menuPorts;
@property (weak) IBOutlet NSMenuItem *buttonAmbilight;
@property (weak) IBOutlet NSMenuItem *brightnessItem;
@property (weak) IBOutlet NSSlider *brightnessSlider;
@property (weak) IBOutlet NSMenuItem *brightnessLabel;

@property (strong) NSStatusItem *statusItem;
@property (strong) NSImage *statusImage;
@property (strong) NSTimer *timer;
@property (strong) Serial *serial;
@property (strong) NSArray *lastDisplayIDs;
@property (assign) BOOL restartAmbilight;
@property (strong) NSArray *captureSessions;
@property (strong) NSLock *lock;

@end

@implementation AppDelegate

@synthesize statusMenu, application;
@synthesize menuPorts, buttonAmbilight;
@synthesize brightnessItem, brightnessSlider, brightnessLabel;
@synthesize statusItem, statusImage, lastDisplayIDs;
@synthesize timer, serial, restartAmbilight;
@synthesize captureSessions, lock;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    serial = [[Serial alloc] init];
    lock = [[NSLock alloc] init];
    timer = nil;
    restartAmbilight = NO;
    captureSessions = nil;
    
    // Set default configuration values
    NSUserDefaults *store = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *appDefaults = [NSMutableDictionary dictionaryWithObject:@"" forKey:PREF_SERIAL_PORT];
    [appDefaults setObject:[NSNumber numberWithFloat:50.0] forKey:PREF_BRIGHTNESS];
    [appDefaults setObject:[NSNumber numberWithBool:NO] forKey:PREF_TURNED_ON];
    [store registerDefaults:appDefaults];
    [store synchronize];
    
    // Load existing configuration values
    NSString *savedPort = [store stringForKey:PREF_SERIAL_PORT];
    float brightness = [store floatForKey:PREF_BRIGHTNESS];
    BOOL ambilightIsOn = [store boolForKey:PREF_TURNED_ON];
    
    // Prepare status bar menu
    statusImage = [NSImage imageNamed:@"MenuIcon"];
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    [statusImage setTemplate:YES];
    [statusItem setImage:statusImage];
    [statusItem setMenu:statusMenu];
    
    // Prepare brightness menu
    brightnessItem.view = brightnessSlider;
    [brightnessSlider setFloatValue:brightness];
    [brightnessLabel setTitle:[NSString stringWithFormat:@"Value: %.0f%%", brightness]];
    
    // Prepare serial port menu
    BOOL foundPort = NO;
    NSArray *ports = [Serial listSerialPorts];
    if ([ports count] > 0) {
        [menuPorts removeAllItems];
        for (int i = 0; i < [ports count]; i++) {
            // Add Menu Item for this port
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[ports objectAtIndex:i] action:@selector(selectedSerialPort:) keyEquivalent:@""];
            [menuPorts addItem:item];
            
            // Set Enabled if it was used the last time
            if ((savedPort != nil) && [[ports objectAtIndex:i] isEqualToString:savedPort]) {
                // Try to open serial port
                [serial setPortName:savedPort];
                if (![serial openPort]) {
                    foundPort = YES;
                    [[menuPorts itemAtIndex:i] setState:NSOnState];
                }
            }
        }
        
        if (!foundPort) {
            // I'm using a cheap chinese Arduino Nano clone with a CH340 chipset.
            // This driver creates device-files in /dev/cu.* that don't correspond
            // to the chip-id and change every time the adapter is re-enumerated.
            // That means we may have to try and find the device again after the
            // stored name does no longer exist. In this case, we simply try the first
            // device that starts with /dev/cu.wchusbserial*...
            for (int i = 0; i < [ports count]; i++) {
                if ([[ports objectAtIndex:i] hasPrefix:@"/dev/cu.wchusbserial"]) {
                    // Try to open serial port
                    [serial setPortName:savedPort];
                    if (![serial openPort]) {
                        [[menuPorts itemAtIndex:i] setState:NSOnState];
                        
                        // Reattempt next matching device when opening this one fails.
                        break;
                    }
                }
            }
        }
    }
    
    // Enumerate displays and start ambilight if required
    [Screenshot init:self];
    restartAmbilight = ambilightIsOn;
    [self newDisplayList:[Screenshot listDisplays]];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    [self stopAmbilightTimer];
    
    // Remove display callback
    [Screenshot close:self];
    
    // Turn off all lights if possible
    if ([serial isOpen]) {
        [self sendNullFrame];
        [serial closePort];
    }
}

BOOL timerRunning = NO;

- (void)startAmbilightTimer {
    //timer = [NSTimer scheduledTimerWithTimeInterval:DISPLAY_DELAY target:self selector:@selector(visualizeDisplay:) userInfo:nil repeats:NO];
    
    timerRunning = YES;
    if (captureSessions != nil) {
        for (int i = 0; i < [captureSessions count]; i++) {
            [[captureSessions objectAtIndex:i] startRunning];
        }
    }
}

- (void)stopAmbilightTimer {
    // Stop previous timer setting
    //if (timer != nil) {
    //    [timer invalidate];
    //    timer = nil;
    //}
    
    timerRunning = NO;
    if (captureSessions != nil) {
        for (int i = 0; i < [captureSessions count]; i++) {
            [[captureSessions objectAtIndex:i] stopRunning];
        }
    }
}

- (BOOL)isAmbilightRunning {
    //return (timer != nil) ? YES : NO;
    return timerRunning;
}

- (IBAction)relistSerialPorts:(id)sender {
    // Refill port list
    NSArray *ports = [Serial listSerialPorts];
    [menuPorts removeAllItems];
    for (int i = 0; i < [ports count]; i++) {
        // Add Menu Item for this port
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[ports objectAtIndex:i] action:@selector(selectedSerialPort:) keyEquivalent:@""];
        [menuPorts addItem:item];
        
        // Mark it if it is currently open
        if ([serial isOpen]) {
            if ([[ports objectAtIndex:i] isEqualToString:[serial portName]]) {
                [[menuPorts itemAtIndex:i] setState:NSOnState];
            }
        }
    }
}

- (void)selectedSerialPort:(NSMenuItem *)source {
    // Store selection for next start-up
    NSUserDefaults *store = [NSUserDefaults standardUserDefaults];
    [store setObject:[source title] forKey:PREF_SERIAL_PORT];
    [store synchronize];
    
    // De-select all other ports
    for (int i = 0; i < [menuPorts numberOfItems]; i++) {
        [[menuPorts itemAtIndex:i] setState:NSOffState];
    }
    
    // Select only the current port
    [source setState:NSOnState];
    
    // Close previously opened port, if any
    if ([serial isOpen]) {
        [serial closePort];
    }
    
    [self stopAmbilightTimer];
    
    // Turn off ambilight button
    [buttonAmbilight setState:NSOffState];
    
    // Try to open selected port
    [serial setPortName:[source title]];
    if ([serial openPort] != 0) {
        [source setState:NSOffState];
    }
}

- (IBAction)toggleAmbilight:(NSMenuItem *)sender {
    if ([sender state] == NSOnState) {
        [sender setState:NSOffState];
        [self stopAmbilightTimer];
        [self sendNullFrame];
        
        // Store state
        NSUserDefaults *store = [NSUserDefaults standardUserDefaults];
        [store setObject:[NSNumber numberWithBool:NO] forKey:PREF_TURNED_ON];
        [store synchronize];
    } else {
        [sender setState:NSOnState];
        [self startAmbilightTimer];
        
        // Store state
        NSUserDefaults *store = [NSUserDefaults standardUserDefaults];
        [store setObject:[NSNumber numberWithBool:YES] forKey:PREF_TURNED_ON];
        [store synchronize];
    }
}

- (void)stopAmbilight {
    restartAmbilight = [self isAmbilightRunning];
    [buttonAmbilight setState:NSOffState];
    [self stopAmbilightTimer];
}

- (void)newDisplayList:(NSArray *)displayIDs {
    lastDisplayIDs = displayIDs;
    
    // Create capturing sessions for each display
    AVCaptureSession *sessions[[displayIDs count]];
    for (int i = 0; i < [displayIDs count]; i++) {
        sessions[i] = [[AVCaptureSession alloc] init];
        [sessions[i] beginConfiguration];
        
        if ([sessions[i] canSetSessionPreset:AVCaptureSessionPresetHigh]) {
            // TODO could use other presets?
            sessions[i].sessionPreset = AVCaptureSessionPresetHigh;
        } else {
            NSLog(@"Can't set preset for display %ld!", (long)[[displayIDs objectAtIndex:i] integerValue]);
        }
        
        // Add Screen Capture input for this screen
        AVCaptureScreenInput *input = [[AVCaptureScreenInput alloc] initWithDisplayID:[[displayIDs objectAtIndex:i] unsignedIntValue]];
        [input setCapturesCursor:YES]; // Enable mouse cursor capturing (ToDo disable for performance?)
        [input setMinFrameDuration:CMTimeMakeWithSeconds(DISPLAY_DELAY, 1000)]; // Set out target frame rate
        
        if ([sessions[i] canAddInput:input]) {
            [sessions[i] addInput:input];
        } else {
            NSLog(@"Can't add screen grab input for display %ld!", (long)[[displayIDs objectAtIndex:i] integerValue]);
        }
        
        // Add Screen Capture output into this object
        AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
        [output setSampleBufferDelegate:self queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)];
        [output setVideoSettings:@{ (NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) }];
        
        NSArray *formats = [output availableVideoCVPixelFormatTypes];
        for (int i = 0; i < [formats count]; i++) {
            NSLog(@"Supported format: 0x%lX", (long)[[formats objectAtIndex:i] integerValue]);
        }
        
        if ([sessions[i] canAddOutput:output]) {
            [sessions[i] addOutput:output];
        } else {
            NSLog(@"Can't add screen grab output for display %ld!", (long)[[displayIDs objectAtIndex:i] integerValue]);
        }
        
        [sessions[i] commitConfiguration];
        
        NSLog(@"Added output for display %ld", (long)[[displayIDs objectAtIndex:i] integerValue]);
    }
    captureSessions = [NSArray arrayWithObjects:sessions count:[displayIDs count]];
    
    if (restartAmbilight) {
        restartAmbilight = NO;
        [buttonAmbilight setState:NSOnState];
        [self startAmbilightTimer];
    }
}

- (IBAction)brightnessMoved:(NSSlider *)sender {
    [brightnessLabel setTitle:[NSString stringWithFormat:@"Value: %.0f%%", [sender floatValue]]];
    
    // Store changed value in preferences
    NSUserDefaults *store = [NSUserDefaults standardUserDefaults];
    [store setObject:[NSNumber numberWithFloat:[sender floatValue]] forKey:PREF_BRIGHTNESS];
    [store synchronize];
}

- (IBAction)showAbout:(id)sender {
    [NSApp activateIgnoringOtherApps:YES];
    [application orderFrontStandardAboutPanel:self];
}

- (void)sendLEDFrame {
    //NSLog(@"New LED frame");
    
    if ([serial isOpen]) {
        [serial sendString:MAGIC_WORD];
        [serial sendData:(char *)ledColorData withLength:(sizeof(ledColorData) / sizeof(ledColorData[0]))];
    }
}

- (void)sendNullFrame {
    for (int i = 0; i < (sizeof(ledColorData) / sizeof(ledColorData[0])); i++) {
        ledColorData[i] = 0;
    }
    [self sendLEDFrame];
}

// ----------------------------------------------------
// ------------ 'Ambilight' Visualizations ------------
// ----------------------------------------------------

UInt8 ledColorData[LED_COUNT * 3];

- (UInt32)calculateAverage:(unsigned char *)data Width:(NSInteger)width Height:(NSInteger)height SPP:(NSInteger)spp Alpha:(BOOL)alpha StartX:(NSInteger)startX StartY:(NSInteger)startY EndX:(NSInteger)endX EndY:(NSInteger)endY {
    //int redC = 0, greenC = 1, blueC = 2;
    int redC = 2, greenC = 1, blueC = 0;
    if (alpha) {
        //redC = 3; greenC = 2; blueC = 1;
    }
    
    NSInteger xa, xb, ya, yb;
    if (startX < endX) {
        xa = startX;
        xb = endX;
    } else {
        xa = endX;
        xb = startX;
    }
    if (startY < endY) {
        ya = startY;
        yb = endY;
    } else {
        ya = endY;
        yb = startY;
    }
    
    unsigned long red = 0, green = 0, blue = 0, count = 0;
    for (NSInteger i = xa; i < xb; i += AVERAGE_PIXEL_SKIP) {
        for (NSInteger j = ya; j < yb; j++) {
            count++;
            unsigned long index = i + (j * width);
            red += data[(index * spp) + redC];
            green += data[(index * spp) + greenC];
            blue += data[(index * spp) + blueC];
        }
    }
    red /= count;
    green /= count;
    blue /= count;
    
    red *= [brightnessSlider floatValue] / 100.0f;
    green *= [brightnessSlider floatValue] / 100.0f;
    blue *= [brightnessSlider floatValue] / 100.0f;
    
    return ((UInt32)red << 16) | ((UInt32)green << 8) | ((UInt32)blue);
}

- (void)visualizeSingleDisplay:(NSInteger)disp Data:(unsigned char *)data Width:(unsigned long)width Height:(unsigned long)height SPP:(NSInteger)spp Alpha:(BOOL)alpha {
    displays[disp].shown = 1;
    
    for (int i = 0; i < (sizeof(strands) / sizeof(strands[0])); i++) {
        if (strands[i].display == disp) {
            // Walk the strand, calculating value for each LED
            unsigned long x = strands[i].startX;
            unsigned long y = strands[i].startY;
            unsigned long blockWidth = COLOR_AVERAGE_OTHER_DIMENSION_SIZE;
            unsigned long blockHeight = COLOR_AVERAGE_OTHER_DIMENSION_SIZE;

            if ((strands[i].direction == DIR_LEFT) || (strands[i].direction == DIR_RIGHT)) {
                blockWidth = strands[i].size;
            } else {
                blockHeight = strands[i].size;
            }
            
            for (int led = strands[i].idMin; led < (strands[i].idMin + strands[i].count); led++) {
                // First move appropriately in the direction of the strand
                unsigned long endX = x, endY = y;
                if (strands[i].direction == DIR_LEFT) {
                    endX -= blockWidth;
                } else if (strands[i].direction == DIR_RIGHT) {
                    endX += blockWidth;
                } else if (strands[i].direction == DIR_UP) {
                    endY -= blockHeight;
                } else if (strands[i].direction == DIR_DOWN) {
                    endY += blockHeight;
                }
                
                // But also span the averaging-square in the other dimension, depending on which
                // side of the monitor we're at.
                if ((strands[i].direction == DIR_LEFT) || (strands[i].direction == DIR_RIGHT)) {
                    if (y == 0) {
                        endY = blockHeight;
                    } else if (y == displays[disp].height) {
                        endY -= blockHeight;
                    }
                } else {
                    if (x == 0) {
                        endX = blockWidth;
                    } else if (x == displays[disp].width) {
                        endX -= blockWidth;
                    }
                }
                
                // Calculate average color for this led
                UInt32 color = [self calculateAverage:data Width:width Height:height SPP:spp Alpha:alpha StartX:x StartY:y EndX:endX EndY:endY];
                
                ledColorData[led * 3] = (color & 0xFF0000) >> 16;
                ledColorData[(led * 3) + 1] = (color & 0x00FF00) >> 8;
                ledColorData[(led * 3) + 2] = color & 0x0000FF;
                
                // Move to next LED
                if ((strands[i].direction == DIR_LEFT) || (strands[i].direction == DIR_RIGHT)) {
                    x = endX;
                } else {
                    y = endY;
                }
            }
        }
    }
    
    int doneCount = 0;;
    for (int i = 0; i < (sizeof(displays) / sizeof(displays[0])); i++) {
        if (displays[i].shown != 0) {
            doneCount++;
        }
    }
    
    if (doneCount >= (sizeof(displays) / sizeof(displays[0]))) {
        [self sendLEDFrame];
        
        for (int i = 0; i < (sizeof(displays) / sizeof(displays[0])); i++) {
            displays[i].shown = 0;
        }
    }
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    [lock lock];

#ifdef DEBUG_PRINT_FPS
    static NSInteger frameCount = 0;
    static NSDate *lastPrintTime = nil;
    if (lastPrintTime == nil) {
        lastPrintTime = [NSDate date];
    }
#endif
    
    if (![self isAmbilightRunning]) {
        [lock unlock];
        return;
    }

    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
    
    //NSLog(@"W=%d H=%d", dimensions.width, dimensions.height);
    
    // Try to find the matching display id for the strand associations
    for (int n = 0; n < (sizeof(displays) / sizeof(displays[0])); n++) {
        if ((dimensions.width == displays[n].width) && (dimensions.height == displays[n].height)) {
            //NSLog(@"Capture conversion for %d...", n);
            
            // Convert our frame to an NSImage
            CVPixelBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
            CVPixelBufferLockBaseAddress(imageBuffer, 0);
            
            void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
            size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
            size_t width = CVPixelBufferGetWidth(imageBuffer);
            size_t height = CVPixelBufferGetHeight(imageBuffer);
            
            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
            CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8, bytesPerRow,
                                                         colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Little);
            if (context == nil) {
                NSLog(@"Error creating context!");
                break;
            }
            
            CGImageRef quartzImage = CGBitmapContextCreateImage(context);
            CVPixelBufferUnlockBaseAddress(imageBuffer,0);
            
            CGContextRelease(context);
            CGColorSpaceRelease(colorSpace);
            
            NSBitmapImageRep *image = [[NSBitmapImageRep alloc] initWithCGImage:quartzImage];
            CGImageRelease(quartzImage);
            
            [self visualizeThisImage:image];
            break;
        }
    }
    
#ifdef DEBUG_PRINT_FPS
    frameCount++;
    NSDate *now = [NSDate date];
    NSTimeInterval interval = [now timeIntervalSinceDate:lastPrintTime];
    if (interval >= DEBUG_PRINT_FPS) {
        NSLog(@"FPS: ~%.2f / %lu = %.2f", frameCount / interval,
              (sizeof(displays) / sizeof(displays[0])), frameCount / interval / (sizeof(displays) / sizeof(displays[0])));
        frameCount = 0;
        lastPrintTime = now;
    }
#endif
    
    [lock unlock];
}

- (void)visualizeThisImage:(NSBitmapImageRep *)screen {
    unsigned long width = [screen pixelsWide];
    unsigned long height = [screen pixelsHigh];
    
    // Ensure we can handle the format of this display
    NSInteger spp = [screen samplesPerPixel];
    if (((spp != 3) && (spp != 4)) || ([screen isPlanar] == YES) || ([screen numberOfPlanes] != 1)) {
        NSLog(@"Unknown image format for (%ld, %c, %ld)!\n", (long)spp, ([screen isPlanar] == YES) ? 'p' : 'n', (long)[screen numberOfPlanes]);
        return;
    }
    
    // Find out how the color components are ordered
    BOOL alpha = NO;
    if ([screen bitmapFormat] & NSAlphaFirstBitmapFormat) {
        alpha = YES;
    }
    
    // Try to find the matching display id for the strand associations
    for (int n = 0; n < (sizeof(displays) / sizeof(displays[0])); n++) {
        if ((width == displays[n].width) && (height == displays[n].height)) {
            unsigned char *data = [screen bitmapData];
            [self visualizeSingleDisplay:n Data:data Width:width Height:height SPP:spp Alpha:alpha];
            return;
        }
    }
}

/*
- (void)visualizeDisplay:(NSTimer *)time {
#ifdef DEBUG_PRINT_FPS
    static NSInteger frameCount = 0;
    static NSDate *lastPrintTime = nil;
    if (lastPrintTime == nil) {
        lastPrintTime = [NSDate date];
    }
#endif
    
    //NSLog(@"Running Ambilight-Algorithm (%lu)...", (unsigned long)[lastDisplayIDs count]);
    
    // Create a Screenshot for all connected displays
    for (NSInteger i = 0; i < [lastDisplayIDs count]; i++) {
        NSBitmapImageRep *screen = [Screenshot screenshot:[lastDisplayIDs objectAtIndex:i]];
        [self visualizeThisImage:screen];
    }
    
    [self sendLEDFrame];
    
#ifdef DEBUG_PRINT_FPS
    frameCount++;
    NSDate *now = [NSDate date];
    NSTimeInterval interval = [now timeIntervalSinceDate:lastPrintTime];
    if (interval >= DEBUG_PRINT_FPS) {
        NSLog(@"FPS: %.2f", frameCount / interval);
        frameCount = 0;
        lastPrintTime = now;
    }
#endif
    
    [self startAmbilightTimer];
}
*/
 
@end
