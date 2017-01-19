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
struct DisplayAssignment displays[] = {
    { 1920, 1080 },
    {  900, 1600 }
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
// in the bottom-right of D1, then goes left arount D1, and from there around D2 back
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
//     115200 / ((14 + (156 * 3)) * 8) =~ 30 Frames per Second
// Inserting (1.0 / 30.0) here would try to reach these 30FPS,
// but will probably cause high CPU-Usage.
// (Run-Time of the algorithm is ignored here, so real speed will be
// slightly lower.)
#define DISPLAY_DELAY (1.0 / 30.0)

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
//#define DEBUG_PRINT_FPS 10

// ToDo Change color-temperature depending on time of day to match f.lux adjustments
#define TARGET_COLOR_TEMPERATURE 2800.0

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
    
    [Screenshot init:self];
    lastDisplayIDs = [Screenshot listDisplays];
    
    if (ambilightIsOn) {
        timer = [NSTimer scheduledTimerWithTimeInterval:DISPLAY_DELAY target:self selector:@selector(visualizeDisplay:) userInfo:nil repeats:NO];
        
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
        
        [self sendNullFrame];
        
        // Store state
        NSUserDefaults *store = [NSUserDefaults standardUserDefaults];
        [store setObject:[NSNumber numberWithBool:NO] forKey:PREF_TURNED_ON];
        [store synchronize];
    } else {
        [sender setState:NSOnState];
        
        timer = [NSTimer scheduledTimerWithTimeInterval:DISPLAY_DELAY target:self selector:@selector(visualizeDisplay:) userInfo:nil repeats:NO];
        
        // Store state
        NSUserDefaults *store = [NSUserDefaults standardUserDefaults];
        [store setObject:[NSNumber numberWithBool:YES] forKey:PREF_TURNED_ON];
        [store synchronize];
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
        
        timer = [NSTimer scheduledTimerWithTimeInterval:DISPLAY_DELAY target:self selector:@selector(visualizeDisplay:) userInfo:nil repeats:NO];
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
                
#ifdef TARGET_COLOR_TEMPERATURE
                struct Color3 c = { ((color & 0xFF0000) >> 16) / 255.0, ((color & 0x00FF00) >> 8) / 255.0, (color & 0x0000FF) / 255.0 };
                c = getRGBfromTemperature(TARGET_COLOR_TEMPERATURE, c);
                
                ledColorData[led * 3] = (int)(c.r * 255.0);
                ledColorData[(led * 3) + 1] = (int)(c.g * 255.0);
                ledColorData[(led * 3) + 2] = (int)(c.b * 255.0);
#else
                ledColorData[led * 3] = (color & 0xFF0000) >> 16;
                ledColorData[(led * 3) + 1] = (color & 0x00FF00) >> 8;
                ledColorData[(led * 3) + 2] = color & 0x0000FF;
#endif
                
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
    
    timer = [NSTimer scheduledTimerWithTimeInterval:DISPLAY_DELAY target:self selector:@selector(visualizeDisplay:) userInfo:nil repeats:NO];
}

// ----------------------------------------------------
// ----------- Color Temperature Adjustment -----------
// ----------------------------------------------------

#define LUMINANCE_PRESERVATION 0.75
#define EPSILON 1e-10
#define SATURATION_FACTOR 0.9

struct Color3 {
    float r, g, b;
};

float saturateFloat(float v) {
    if (v < 0.0f) {
        return 0.0f;
    } else if (v > 1.0f) {
        return 1.0f;
    } else {
        return v;
    }
}

struct Color3 saturateColor(struct Color3 v) {
    v.r = saturateFloat(v.r);
    v.g = saturateFloat(v.g);
    v.b = saturateFloat(v.b);
    return v;
}

struct Color3 colorTemperatureToRGB(float temperatureInKelvins) {
    struct Color3 retColor;
    
    if (temperatureInKelvins < 1000.0) {
        temperatureInKelvins = 1000.0;
    } else if (temperatureInKelvins > 40000) {
        temperatureInKelvins = 40000.0;
    }
    
    temperatureInKelvins /= 100.0;
    
    if (temperatureInKelvins <= 66.0) {
        retColor.r = 1.0;
        retColor.g = saturateFloat(0.39008157876901960784 * log(temperatureInKelvins) - 0.63184144378862745098);
    } else {
        float t = temperatureInKelvins - 60.0;
        retColor.r = saturateFloat(1.29293618606274509804 * pow(t, -0.1332047592));
        retColor.g = saturateFloat(1.12989086089529411765 * pow(t, -0.0755148492));
    }
    
    if (temperatureInKelvins >= 66.0) {
        retColor.b = 1.0;
    } else if (temperatureInKelvins <= 19.0) {
        retColor.b = 0.0;
    } else {
        retColor.b = saturateFloat(0.54320678911019607843 * log(temperatureInKelvins - 10.0) - 1.19625408914);
    }
    
    return retColor;
}

float luminance(struct Color3 color) {
    float min = fmin(fmin(color.r, color.g), color.b);
    float max = fmax(fmax(color.r, color.g), color.b);
    return (max + min) / 2.0;
}

struct Color3 HUEtoRGB(float h) {
    float r = fabs(h * 6.0 - 3.0) - 1.0;
    float g = 2.0 - fabs(h * 6.0 - 2.0);
    float b = 2.0 - fabs(h * 6.0 - 4.0);
    struct Color3 ret = { r, g, b };
    return saturateColor(ret);
}

struct Color3 HSLtoRGB(struct Color3 hsl) {
    struct Color3 rgb = HUEtoRGB(hsl.r);
    float c = (1.0 - fabs(2.0 * hsl.b - 1.0)) * hsl.g;
    struct Color3 ret = { (rgb.r - 0.5) * c + hsl.b, (rgb.g - 0.5) * c + hsl.b, (rgb.b - 0.5) * c + hsl.b };
    return ret;
}

struct Color3 RGBtoHCV(struct Color3 rgb) {
    // Based on work by Sam Hocevar and Emil Persson
    
    struct Color3 p;
    float pw;
    if (rgb.g < rgb.b) {
        p.r = rgb.b;
        p.g = rgb.g;
        p.b = -1.0;
        pw = 2.0 / 3.0;
    } else {
        p.r = rgb.g;
        p.g = rgb.b;
        p.b = 0.0;
        pw = -1.0 / 3.0;
    }
    
    struct Color3 q;
    float qw;
    if (rgb.r < p.r) {
        q.r = p.r;
        q.g = p.g;
        q.b = pw;
        qw = rgb.r;
    } else {
        q.r = rgb.r;
        q.g = p.g;
        q.b = p.b;
        qw = p.r;
    }
    
    float c = q.r - fmin(qw, q.g);
    float h = fabs((qw - q.g) / (6.0 * c + EPSILON) + q.b);
    
    struct Color3 res = { h, c, q.r };
    return res;
}

struct Color3 RGBtoHSL(struct Color3 rgb) {
    struct Color3 hcv = RGBtoHCV(rgb);
    float l = hcv.b - hcv.g * 0.5;
    float s = hcv.g / (1.0 - fabs(l * 2.0 - 1.0) + EPSILON);
    struct Color3 res = { hcv.r, s, l };
    return res;
}

float mixFloat(float a, float b, float factor) {
    return a + ((b - a) * factor);
}

struct Color3 mixColor(struct Color3 a, struct Color3 b, float factor) {
    struct Color3 res;
    res.r = mixFloat(a.r, b.r, factor);
    res.g = mixFloat(a.g, b.g, factor);
    res.b = mixFloat(a.b, b.b, factor);
    return res;
}

struct Color3 blendColor(struct Color3 a, struct Color3 b) {
    struct Color3 res;
    res.r = a.r * b.r;
    res.g = a.g * b.g;
    res.b = a.b * b.b;
    return res;
}

// http://www.tannerhelland.com/4435/convert-temperature-rgb-algorithm-code/
// Given a temperature (in Kelvin), estimate an RGB equivalent
struct Color3 getRGBfromTemperature(float temperature, struct Color3 color) {
    struct Color3 tempColor = colorTemperatureToRGB(temperature);
    float originalLuminance = luminance(color);
    struct Color3 blended = mixColor(color, blendColor(color, tempColor), SATURATION_FACTOR);
    struct Color3 resultHSL = RGBtoHSL(blended);
    struct Color3 converted = { resultHSL.r, resultHSL.g, originalLuminance };
    struct Color3 luminancePreservedRGB = HSLtoRGB(converted);
    return mixColor(blended, luminancePreservedRGB, LUMINANCE_PRESERVATION);
}

@end
