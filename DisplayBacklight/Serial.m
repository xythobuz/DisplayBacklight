//
//  Serial.m
//  DisplayBacklight
//
//  For more informations refer to this document:
//  https://developer.apple.com/library/mac/documentation/DeviceDrivers/Conceptual/WorkingWSerial/WWSerial_SerialDevs/SerialDevices.html
//
//  Created by Thomas Buck on 14.12.15.
//  Copyright © 2015 xythobuz. All rights reserved.
//

//#define DEBUG_TEXT
//#define DEBUG_DATA

#import <Cocoa/Cocoa.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/serial/IOSerialKeys.h>

#import <termios.h>
#import <fcntl.h>
#import <unistd.h>
#import <poll.h>
#import <sys/ioctl.h>

#import "Serial.h"

#define MAX_SEND_ERRORS 10

@interface Serial ()

@property (assign) int fd;

+ (kern_return_t)findSerialPorts:(io_iterator_t *)matches;
+ (kern_return_t)getSerialPortPath:(io_iterator_t)serialPortIterator to:(char **)deviceFilePath with:(CFIndex)maxPathCount and:(CFIndex)maxPathSize;

@end

@implementation Serial

@synthesize fd, portName;

- (id)init {
    self = [super init];
    if (self != nil) {
        fd = -1;
        portName = nil;
    }
    return self;
}

- (NSInteger)openPort {
    // We need a port name
    if (portName == nil) {
        NSLog(@"Can't open serial port without name!\n");
        return 1;
    }
    
    // Check if there was already a port opened
    if (fd > -1) {
        NSLog(@"Closing previously opened serial port \"%@\"!\n", portName);
        close(fd);
    }
    
#ifdef DEBUG
    NSLog(@"Opening serial port \"%@\"...\n", portName);
#endif
    
    // Open port read-only, without controlling terminal, non-blocking
    fd = open([portName UTF8String], O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (fd == -1) {
        NSLog(@"Error opening serial port \"%@\": %s (%d)!\n", portName, strerror(errno), errno);
        return 1;
    }
    
    // Prevent additional opens except by root-owned processes
    if (ioctl(fd, TIOCEXCL) == -1) {
        NSLog(@"Error enabling exclusive access on \"%@\": %s (%d)!\n", portName, strerror(errno), errno);
        return 1;
    }
    
    fcntl(fd, F_SETFL, 0); // Enable blocking I/O
    
    // Read current settings
    struct termios options;
    tcgetattr(fd, &options);
    
    // Clear all settings
    options.c_lflag = 0;
    options.c_oflag = 0;
    options.c_iflag = 0;
    options.c_cflag = 0;
    
    options.c_cflag |= CS8; // 8 data bits
    options.c_cflag |= CREAD; // Enable receiver
    options.c_cflag |= CLOCAL; // Ignore modem status lines
    
    // Set Baudrate
    cfsetispeed(&options, B115200);
    cfsetospeed(&options, B115200);
    
    options.c_cc[VMIN] = 0; // Return even with zero bytes...
    options.c_cc[VTIME] = 1; // ...but only after .1 seconds
    
    // Set new settings
    tcsetattr(fd, TCSANOW, &options);
    tcflush(fd, TCIOFLUSH);
    
    return 0;
}

- (void)closePort {
#ifdef DEBUG
    NSLog(@"Closing serial port \"%@\"...\n", portName);
#endif
    
    if (fd > -1) {
        close(fd);
    } else {
        NSLog(@"Trying to close already closed port!\n");
    }
    fd = -1;
}

- (BOOL)isOpen {
    if (fd > -1) {
        return YES;
    } else {
        return NO;
    }
}

- (BOOL)hasData {
    if (fd < 0) {
        NSLog(@"Error trying to poll a closed port!\n");
        return NO;
    }
    
    struct pollfd fds;
    fds.fd = fd;
    fds.events = (POLLIN | POLLPRI); // Data may be read
    int val = poll(&fds, 1, 0);
    if (val > 0) {
        return YES;
    } else if (val == 0) {
        return NO;
    } else {
        NSLog(@"Error polling serial port: %s (%d)!\n", strerror(errno), errno);
        return NO;
    }
}

- (void)sendString:(NSString *)string {
    if (fd < 0) {
        NSLog(@"Error trying to send to a closed port!\n");
        return;
    }
    
    const char *data = [string UTF8String];
    size_t length = strlen(data);
    
#ifdef DEBUG_TEXT
    NSLog(@"Sending string %s", data);
#endif
    
    [self sendData:data withLength:length];
}

- (void)sendData:(const char *)data withLength:(size_t)length {
#ifdef DEBUG_DATA
    NSLog(@"Sending binary-data with %zu bytes.", length);
#endif

    int errorCount = 0;
    ssize_t sent = 0;
    while (sent < length) {
        ssize_t ret = write(fd, data + sent, length - sent);
        if (ret < 0) {
            NSLog(@"Error writing to serial port: %s (%d)!\n", strerror(errno), errno);
            errorCount++;
            if (errorCount >= MAX_SEND_ERRORS) {
#ifdef DEBUG
                NSLog(@"Too many send errors! Giving up...\n");
#endif
                return;
            }
        } else {
            sent += ret;
        }
    }
}

+ (NSArray *)listSerialPorts {
    // Get Iterator with all serial ports
    io_iterator_t serialPortIterator;
    kern_return_t kernResult = [Serial findSerialPorts:&serialPortIterator];
    
    // Create 2D array
    char **portList;
    portList = malloc(100 * sizeof(char *));
    for (int i = 0; i < 100; i++) portList[i] = malloc(200 * sizeof(char));
    
    // Copy device name into C-String array
    kernResult = [Serial getSerialPortPath:serialPortIterator to:portList with:100 and:200];
    IOObjectRelease(serialPortIterator);
    
    // Copy contents into NSString Array
    NSString *stringList[100];
    NSUInteger realCount = 0;
    while (portList[realCount] != NULL) {
        stringList[realCount] = [NSString stringWithCString:portList[realCount] encoding:NSUTF8StringEncoding];
        realCount++;
    }
    
    // Destroy 2D array
    for (int i = 0; i < 100; i++) free(portList[i]);
    free(portList);
    
    // And return them as NSArray
    return [[NSArray alloc] initWithObjects:stringList count:realCount];
}

+ (kern_return_t)findSerialPorts:(io_iterator_t *)matches {
    kern_return_t kernResult;
    mach_port_t masterPort;
    CFMutableDictionaryRef classesToMatch;
    
    kernResult = IOMasterPort(MACH_PORT_NULL, &masterPort);
    if (KERN_SUCCESS != kernResult) {
        NSLog(@"IOMasterPort returned %d\n", kernResult);
        return kernResult;
    }
    
    // Serial devices are instances of class IOSerialBSDClient.
    classesToMatch = IOServiceMatching(kIOSerialBSDServiceValue);
    if (classesToMatch == NULL) {
        NSLog(@"IOServiceMatching returned a NULL dictionary.\n");
    } else {
        CFDictionarySetValue(classesToMatch,
                             CFSTR(kIOSerialBSDTypeKey),
                             CFSTR(kIOSerialBSDAllTypes));
        
        // Each serial device object has a property with key
        // kIOSerialBSDTypeKey and a value that is one of
        // kIOSerialBSDAllTypes, kIOSerialBSDModemType,
        // or kIOSerialBSDRS232Type. You can change the
        // matching dictionary to find other types of serial
        // devices by changing the last parameter in the above call
        // to CFDictionarySetValue.
    }
    
    kernResult = IOServiceGetMatchingServices(masterPort, classesToMatch, matches);
    if (KERN_SUCCESS != kernResult) {
        NSLog(@"IOServiceGetMatchingServices returned %d\n", kernResult);
        return kernResult;
    }
    
    return kernResult;
}

+ (kern_return_t)getSerialPortPath:(io_iterator_t)serialPortIterator to:(char **)deviceFilePath with:(CFIndex)maxPathCount and:(CFIndex)maxPathSize {
    io_object_t modemService;
    kern_return_t kernResult = KERN_FAILURE;
    CFIndex i = 0;
    
    while ((modemService = IOIteratorNext(serialPortIterator)) && (i < (maxPathCount - 1))) {
        CFTypeRef   deviceFilePathAsCFString;
        
        // Get the callout device's path (/dev/cu.xxxxx).
        // The callout device should almost always be
        // used. You would use the dialin device (/dev/tty.xxxxx) when
        // monitoring a serial port for
        // incoming calls, for example, a fax listener.
        
        deviceFilePathAsCFString = IORegistryEntryCreateCFProperty(modemService,
                                                                   CFSTR(kIOCalloutDeviceKey),
                                                                   kCFAllocatorDefault,
                                                                   0);
        if (deviceFilePathAsCFString) {
            Boolean result;
            
            deviceFilePath[i][0] = '\0';
            
            // Convert the path from a CFString to a NULL-terminated C string
            // for use with the POSIX open() call.
            
            result = CFStringGetCString(deviceFilePathAsCFString,
                                        deviceFilePath[i],
                                        maxPathSize,
                                        kCFStringEncodingASCII);
            CFRelease(deviceFilePathAsCFString);
            
            if (result) {
                //NSLog(@"BSD path: %s\n", deviceFilePath[i]);
                i++;
                kernResult = KERN_SUCCESS;
            }
        }
        
        // Release the io_service_t now that we are done with it.
        
        (void) IOObjectRelease(modemService);
    }
    
    deviceFilePath[i] = NULL;
    
    return kernResult;
}

@end
