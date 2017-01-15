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

// These are the values stored persistently in the preferences
#define PREF_SERIAL_PORT @"SerialPort"
#define PREF_BRIGHTNESS @"Brightness"

#define DISPLAY_DELAY (1.0 / 10.0)

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

@end

@implementation AppDelegate

@synthesize statusMenu, application;
@synthesize menuPorts, buttonAmbilight;
@synthesize brightnessItem, brightnessSlider, brightnessLabel;
@synthesize statusItem, statusImage, lastDisplayIDs;
@synthesize timer, serial, restartAmbilight;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    serial = [[Serial alloc] init];
    timer = nil;
    restartAmbilight = NO;
    
    // Set default configuration values
    NSUserDefaults *store = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *appDefaults = [NSMutableDictionary dictionaryWithObject:@"" forKey:PREF_SERIAL_PORT];
    [appDefaults setObject:[NSNumber numberWithFloat:50.0] forKey:PREF_BRIGHTNESS];
    [store registerDefaults:appDefaults];
    [store synchronize];
    
    // Load existing configuration values
    NSString *savedPort = [store stringForKey:PREF_SERIAL_PORT];
    float brightness = [store floatForKey:PREF_BRIGHTNESS];
    
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
    BOOL startTimer = NO;
    NSArray *ports = [Serial listSerialPorts];
    if ([ports count] > 0) {
        [menuPorts removeAllItems];
        for (int i = 0; i < [ports count]; i++) {
            // Add Menu Item for this port
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[ports objectAtIndex:i] action:@selector(selectedSerialPort:) keyEquivalent:@""];
            [menuPorts addItem:item];
            
            // Set Enabled if it was used the last time
            if ((savedPort != nil) && [[ports objectAtIndex:i] isEqualToString:savedPort]) {
                [[menuPorts itemAtIndex:i] setState:NSOnState];
                
                // Try to open serial port
                [serial setPortName:savedPort];
                if ([serial openPort]) {
                    // Unselect it when an error occured opening the port
                    [[menuPorts itemAtIndex:i] setState:NSOffState];
                } else {
                    startTimer = YES;
                }
            }
        }
        
        if (!startTimer) {
            // TODO try to find out new UART port name for controller
        }
    }
    
    [Screenshot init:self];
    lastDisplayIDs = [Screenshot listDisplays];
    
    if (startTimer) {
        timer = [NSTimer scheduledTimerWithTimeInterval:DISPLAY_DELAY target:self selector:@selector(visualizeDisplay:) userInfo:nil repeats:YES];
        
        [buttonAmbilight setState:NSOnState];
    }
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Stop previous timer setting
    if (timer != nil) {
        [timer invalidate];
        timer = nil;
    }
    
    // Remove display callback
    [Screenshot close:self];
    
    // Turn off all lights if possible
    if ([serial isOpen]) {
        [self sendNullFrame];
        [serial closePort];
    }
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
    
    // Stop previous timer setting
    if (timer != nil) {
        [timer invalidate];
        timer = nil;
    }
    
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
        
        // Stop previous timer setting
        if (timer != nil) {
            [timer invalidate];
            timer = nil;
        }
    } else {
        [sender setState:NSOnState];
        
        timer = [NSTimer scheduledTimerWithTimeInterval:DISPLAY_DELAY target:self selector:@selector(visualizeDisplay:) userInfo:nil repeats:YES];
    }
}

- (void)stopAmbilight {
    restartAmbilight = NO;
    if (timer != nil) {
        restartAmbilight = YES;
        [timer invalidate];
        timer = nil;
        
        [buttonAmbilight setState:NSOffState];
    }
}

- (void)newDisplayList:(NSArray *)displayIDs {
    lastDisplayIDs = displayIDs;
    
    if (restartAmbilight) {
        restartAmbilight = NO;
        [buttonAmbilight setState:NSOnState];
        
        timer = [NSTimer scheduledTimerWithTimeInterval:DISPLAY_DELAY target:self selector:@selector(visualizeDisplay:) userInfo:nil repeats:YES];
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

- (UInt32)calculateAverage:(unsigned char *)data Width:(NSInteger)width Height:(NSInteger)height SPP:(NSInteger)spp Alpha:(BOOL)alpha StartX:(NSInteger)startX StartY:(NSInteger)startY EndX:(NSInteger)endX EndY:(NSInteger)endY {
    int redC = 0, greenC = 1, blueC = 2;
    if (alpha) {
        redC = 1; greenC = 2; blueC = 3;
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
    for (NSInteger i = xa; i < xb; i++) {
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
    
    return ((UInt32)red << 16) | ((UInt32)green << 8) | ((UInt32)blue);
}

struct DisplayAssignment {
    int n;
    int width, height;
};

struct LEDStrand {
    int idMin, idMax;
    int display;
    int startX, startY;
    int direction;
    int size;
};

#define DIR_LEFT 0
#define DIR_RIGHT 1
#define DIR_UP 2
#define DIR_DOWN 3

// TODO remove first
struct DisplayAssignment displays[] = {
    { 0, 1920, 1080 },
    { 1,  900, 1600 }
};

struct LEDStrand strands[] = {
    {   0,  32, 0, 1920, 1080,  DIR_LEFT, 1920 / 33 },
    {  33,  51, 0,    0, 1080,    DIR_UP, 1080 / 19 },
    {  52,  84, 0,    0,    0, DIR_RIGHT, 1920 / 33 },
    {  85,  89, 1,    0,  250,    DIR_UP,  250 / 5 },
    {  90, 106, 1,    0,    0, DIR_RIGHT,  900 / 17 },
    { 107, 134, 1,  900,    0,  DIR_DOWN, 1600 / 28 },
    { 135, 151, 1,  900, 1600,  DIR_LEFT,  900 / 17 },
    { 152, 155, 1,    0, 1600,    DIR_UP,  180 / 4 }
};

UInt8 ledColorData[156 * 3];

#define COLOR_AVERAGE_OTHER_DIMENSION_SIZE 150

- (void)visualizeSingleDisplay:(NSInteger)disp Data:(unsigned char *)data Width:(unsigned long)width Height:(unsigned long)height SPP:(NSInteger)spp Alpha:(BOOL)alpha {
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
            
            for (int led = strands[i].idMin; led <= strands[i].idMax; led++) {
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
}

- (void)visualizeDisplay:(NSTimer *)time {
    //NSLog(@"Running Ambilight-Algorithm (%lu)...", (unsigned long)[lastDisplayIDs count]);
    
    // Create a Screenshot for all connected displays
    for (NSInteger i = 0; i < [lastDisplayIDs count]; i++) {
        NSBitmapImageRep *screen = [Screenshot screenshot:[lastDisplayIDs objectAtIndex:i]];
        unsigned long width = [screen pixelsWide];
        unsigned long height = [screen pixelsHigh];
        
        // Ensure we can handle the format of this display
        NSInteger spp = [screen samplesPerPixel];
        if (((spp != 3) && (spp != 4)) || ([screen isPlanar] == YES) || ([screen numberOfPlanes] != 1)) {
            NSLog(@"Unknown image format for %ld (%ld, %c, %ld)!\n", (long)i, (long)spp, ([screen isPlanar] == YES) ? 'p' : 'n', (long)[screen numberOfPlanes]);
            continue;
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
                break;
            }
        }
    }
    
    [self sendLEDFrame];
}

- (void)sendLEDFrame {
    if ([serial isOpen]) {
        [serial sendString:@"xythobuzRGBled"];
        [serial sendData:(char *)ledColorData withLength:(sizeof(ledColorData) / sizeof(ledColorData[0]))];
    }
}

- (void)sendNullFrame {
    for (int i = 0; i < (sizeof(ledColorData) / sizeof(ledColorData[0])); i++) {
        ledColorData[i] = 0;
    }
    [self sendLEDFrame];
}

+ (double)map:(double)val FromMin:(double)fmin FromMax:(double)fmax ToMin:(double)tmin ToMax:(double)tmax {
    double norm = (val - fmin) / (fmax - fmin);
    return (norm * (tmax - tmin)) + tmin;
}

@end
