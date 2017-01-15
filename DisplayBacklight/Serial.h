//
//  Serial.h
//  DisplayBacklight
//
//  Created by Thomas Buck on 14.12.15.
//  Copyright © 2015 xythobuz. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Serial : NSObject

@property (strong) NSString *portName;

- (NSInteger)openPort;
- (void)closePort;
- (BOOL)isOpen;
- (BOOL)hasData;
- (void)sendData:(const char *)data withLength:(size_t)length;
- (void)sendString:(NSString *)string;

+ (NSArray *)listSerialPorts;

@end
