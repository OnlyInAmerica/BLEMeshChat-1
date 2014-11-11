//
//  BLEScannerRequest.m
//  BLEMeshChat
//
//  Created by David Brodsky on 11/10/14.
//  Copyright (c) 2014 Christopher Ballinger. All rights reserved.
//

#import "BLEScannerRequest.h"

@interface BLEScannerRequest()
@property (nonatomic, strong) CBCharacteristic *characteristic;
@end

@implementation BLEScannerRequest

- (instancetype) initWithUUID:(CBUUID*) uuid type:(RequestType)type
 {
     if (self = [super init]) {
         _type = type;
         _characteristicUUID = uuid;
     }
     return self;
 }

- (void) didDiscoverMatchingPeripheralCharacteristic:(CBCharacteristic*) characteristic {
    self.characteristic = characteristic;
}


- (BOOL) performRequestForPeripheral: (CBPeripheral*) peripheral {
    if ([self type] == Read) {
        [peripheral readValueForCharacteristic:[self characteristic]];
        return YES;
    } else {
        // If we're a write request a more specific implementation should be provided by subclass
        [NSException raise:NSInternalInconsistencyException
                    format:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)];
    }
    return NO;
}

- (BOOL) handleResponseFromPeripheral: (CBPeripheral*) peripheral characteristic: (CBCharacteristic *) characteristic {
    
    [NSException raise:NSInternalInconsistencyException
                format:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)];
    return NO;
}


@end