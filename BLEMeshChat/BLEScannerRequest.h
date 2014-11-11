//
//  BLEScannerRequest.h
//  BLEMeshChat
//
//  Created by David Brodsky on 11/10/14.
//  Copyright (c) 2014 Christopher Ballinger. All rights reserved.
//

#include "BLERemotePeer.h"

/**
 * An abstract class representing a request a BLEScanner should make to a BLEBroadcaster,
 * as well as the corresponding logic to handle the response.
 */
@interface BLEScannerRequest : NSObject

typedef NS_ENUM(NSInteger, RequestType) {
    Read,
    Write
};

- (instancetype) initWithUUID:(CBUUID*) uuid type:(RequestType) type;

@property (readonly) RequestType type;
@property (nonatomic, strong, readonly) CBUUID *characteristicUUID;

/**
 * Indicates a characteristic with UUID matching the characteristicUUID of this request
 * was discovered on a remote peripheral. Must always be called before performRequestForPeripheral.
 *
 * Note : This is necessary until we are able to construct a CBCharacteristic a priori.
 */
- (void) didDiscoverMatchingPeripheralCharacteristic:(CBCharacteristic*) characteristic;

/**
 * Called when a peripheral is available for this request.
 *
 * @return whether the request was performed
 */
- (BOOL) performRequestForPeripheral: (CBPeripheral*) peripheral;

/**
 * Called when a response is received following a successful call to performRequestForPeer.
 * 
 * Note : We pass in the characteristic again so we can read offset and value if provided by the peripheral
 * @return whether the request is complete. If NO, preformRequestForPeripheral will be called again e.g: To request the next item in this series.
 */
- (BOOL) handleResponseFromPeripheral: (CBPeripheral*) peripheral characteristic: (CBCharacteristic *) characteristic;


@end