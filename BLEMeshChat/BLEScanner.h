//
//  BLEScanner.h
//  BLEMeshChat
//
//  Created by Christopher Ballinger on 10/10/14.
//  Copyright (c) 2014 Christopher Ballinger. All rights reserved.
//

#import "BLETransport.h"
#import "BLEScannerRequest.h"

@interface BLEScanner : BLETransport <CBCentralManagerDelegate, CBPeripheralDelegate>

/**
 * Add a request to be executed against all appropriate peripherals discovered.
 * Requests added in this way are executed in-order.
 */
- (void) addRequest: (BLEScannerRequest*) request;

@end
