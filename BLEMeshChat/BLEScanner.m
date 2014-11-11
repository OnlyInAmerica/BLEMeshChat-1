//
//  BLEScanner.m
//  BLEMeshChat
//
//  Created by Christopher Ballinger on 10/10/14.
//  Copyright (c) 2014 Christopher Ballinger. All rights reserved.
//

#import "BLEScanner.h"
#import "BLEBroadcaster.h"
#import "BLEMessagePacket.h"
#import "BLEIdentityPacket.h"

static NSString * const kBLEScannerRestoreIdentifier = @"kBLEScannerRestoreIdentifier";

@interface BLEScanner()
@property (nonatomic, strong) CBCentralManager *centralManager;
@property (nonatomic) dispatch_queue_t eventQueue;

@property (nonatomic, strong) NSMutableDictionary *peerToPeripheralCache;

@property (nonatomic, strong) NSMutableSet *allDiscoveredPeripherals;

@property (nonatomic, strong) NSMutableDictionary *characteristicsDictionary;

/** Requests to execute against all discovered peripherals */
@property (nonatomic, strong) NSMutableArray *requests;

/** _requests for convenient lookup when discovering characteristics. @see makeRequestKeyForCharacteristicUUID */
@property (nonatomic, strong) NSMutableDictionary *requestsForKeyDictionary;

/** Request queues for each discovered peripheral's identifier. Requests are executed by increasing index. */
@property (nonatomic, strong) NSMutableDictionary *requestsForPeripheralDictionary;

@end

@implementation BLEScanner

- (instancetype) initWithDataStorage:(id<BLEDataStorage>)dataStorage
 {
    if (self = [super initWithDataStorage:dataStorage]) {
        _eventQueue = dispatch_queue_create("BLEScanner Event Queue", 0);
        _centralManager = [[CBCentralManager alloc] initWithDelegate:self
                                                                     queue:_eventQueue
                                                                   options:@{CBCentralManagerOptionRestoreIdentifierKey: kBLEScannerRestoreIdentifier}];
        _peerToPeripheralCache = [NSMutableDictionary dictionary];
        _allDiscoveredPeripherals = [NSMutableSet set];
        _characteristicsDictionary = [NSMutableDictionary dictionary];
        _requests = [NSMutableArray array];
        _requestsForKeyDictionary = [NSMutableDictionary dictionary];
        _requestsForPeripheralDictionary = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void) addRequest: (BLEScannerRequest*) request {
    [self.requests addObject:request];
    [self.requestsForKeyDictionary setObject:request forKey: [self makeRequestKeyForCharacteristicUUID:request.characteristicUUID type:request.type]];
}

- (BOOL) start {
    if (self.centralManager.state == CBCentralManagerStatePoweredOn) {
        BOOL allowDuplicates = YES;
        NSArray *services = @[[BLEBroadcaster meshChatServiceUUID]];
        [self.centralManager scanForPeripheralsWithServices:services
                                                    options:@{CBCentralManagerScanOptionAllowDuplicatesKey: @(allowDuplicates)}];
        DDLogInfo(@"Scanning for %@", services);
        return YES;
    } else {
        DDLogWarn(@"Central Manager not powered on!");
        return NO;
    }
}

- (void) stop {
    [self.centralManager stopScan];
}

- (BLEIdentityPacket*) peerForPeripheral:(CBPeripheral*)peripheral {
    BLEIdentityPacket *peer = [self.peerToPeripheralCache objectForKey:peripheral.identifier];
    return peer;
}

- (CBCharacteristic*) characteristicForUUID:(CBUUID*)uuid {
    return [self.characteristicsDictionary objectForKey:uuid.UUIDString];
}

- (void) setPeer:(BLEIdentityPacket*)peer forPeripheral:(CBPeripheral*)peripheral {
    [self.peerToPeripheralCache setObject:peer forKey:peripheral.identifier];
}

#pragma mark - CBCentralManagerDelegate methods

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    DDLogVerbose(@"%@: %@ %d", THIS_FILE, THIS_METHOD, (int)central.state);
    if (central.state == CBCentralManagerStatePoweredOn) {
        [self start];
    }
}

- (void) centralManager:(CBCentralManager *)central willRestoreState:(NSDictionary *)state {
    DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
    NSArray *peripherals = state[CBCentralManagerRestoredStatePeripheralsKey];
    if (peripherals.count) {
        DDLogInfo(@"Restored peripherals: %@", peripherals);
    }
    [peripherals enumerateObjectsUsingBlock:^(CBPeripheral *peripheral, NSUInteger idx, BOOL *stop) {
        peripheral.delegate = self;
        if (peripheral.state == CBPeripheralStateDisconnected) {
            [central connectPeripheral:peripheral options:nil];
        }
    }];
}

- (void)centralManager:(CBCentralManager *)central didRetrievePeripherals:(NSArray *)peripherals {
    DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
}

- (void)centralManager:(CBCentralManager *)central didRetrieveConnectedPeripherals:(NSArray *)peripherals {
    DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
    [peripheral discoverServices:@[[BLEBroadcaster meshChatServiceUUID]]];
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    if (error) {
        DDLogError(@"%@: %@ %@", THIS_FILE, THIS_METHOD, error.userInfo);
    } else {
        DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
    }
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    if (error) {
        DDLogError(@"%@: %@ %@", THIS_FILE, THIS_METHOD, error.userInfo);
    } else {
        DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
    }
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI {
    if (peripheral.state != CBPeripheralStateConnected) {
        DDLogVerbose(@"didDiscoverPeripheral: %@\tadvertisementData: %@\tRSSI:%@", peripheral, advertisementData, RSSI);
    }
    [self.allDiscoveredPeripherals addObject:peripheral];
    peripheral.delegate = self;
    if (peripheral.state == CBPeripheralStateDisconnected) {
        [central connectPeripheral:peripheral options:nil];
    }
}

#pragma mark CBPeripheralDelegate methods

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    if (error) {
        DDLogError(@"%@: %@ %@", THIS_FILE, THIS_METHOD, error.userInfo);
    } else {
        DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
    }
    NSArray *services = peripheral.services;
    [services enumerateObjectsUsingBlock:^(CBService *service, NSUInteger idx, BOOL *stop) {
        DDLogInfo(@"Discovered service: %@", service);
        // Don't we want only to discover characteristics for the chat service? -DB
        [peripheral discoverCharacteristics:@[[BLEBroadcaster identityReadCharacteristicUUID], [BLEBroadcaster messagesReadCharacteristicUUID],
                                              [BLEBroadcaster identityWriteCharacteristicUUID], [BLEBroadcaster messagesWriteCharacteristicUUID]]
                                 forService:service];
    }];
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    if (error) {
        DDLogError(@"%@: %@ %@", THIS_FILE, THIS_METHOD, error.description);
    } else {
        DDLogVerbose(@"%@: %@ %@", THIS_FILE, THIS_METHOD, characteristic);
        [self handleResponseFromPeripheral:peripheral characteristic:characteristic type:Read];
//        CBUUID *uuid = characteristic.UUID;
//        BLEIdentityPacket *peer = [self peerForPeripheral:peripheral];
        
//        if ([uuid isEqual:[BLEBroadcaster messagesReadCharacteristicUUID]]) {
//            NSData *messagePacketData = characteristic.value;
//            BLEMessagePacket *message = [self.dataStorage transport:self messageForMessageData:messagePacketData];
//            if (messagePacketData.length) {
//                [self.dataStorage transport:self receivedMessage:message fromPeer:peer];
//            }
//            // Keep reading outgoing messages
//            [peripheral readValueForCharacteristic:characteristic];
//        } else if ([uuid isEqual:[BLEBroadcaster identityReadCharacteristicUUID]]) {
//            NSData *identityPacketData = characteristic.value;
//            BLEIdentityPacket *identity = [self.dataStorage transport:self identityForIdentityData:identityPacketData];
//            if (identity) {
//                // Right now we assume the first peer response
//                // corresponds to the peripheral's identity. This should be verified
//                // cryptographically using a handshake to establish
//                // ownership of the claimed public key.
//#warning Peer spoofing vulnerability
//                if (!peer) {
//                    peer = identity;
//                    [self setPeer:peer forPeripheral:peripheral];
//
//                    // Start reading outgoing messages
//                    CBCharacteristic *messageRead = [self characteristicForUUID:[BLEBroadcaster messagesReadCharacteristicUUID]];
//                    [peripheral readValueForCharacteristic:messageRead];
//                    
//                    // Start sending your outgoing messages
//                    [self sendNextMessageToPeripheral:peripheral];
//                }
//                [self.dataStorage transport:self receivedIdentity:identity fromPeer:peer];
//                // Keep reading outgoing identities
//                [peripheral readValueForCharacteristic:characteristic];
//            }
//        }
    }
}

//- (void) sendNextMessageToPeripheral:(CBPeripheral*)peripheral {
//    BLEIdentityPacket *peer = [self peerForPeripheral:peripheral];
//    BLEMessagePacket *message = [self.dataStorage transport:self nextOutgoingMessageForPeer:peer];
//    if (!message) {
//        return;
//    }
//    NSData *messagePacketData = [message packetData];
//    [self.dataStorage transport:self willWriteMessage:message toPeer:peer];
//    CBCharacteristic *messageWrite = [self characteristicForUUID:[BLEBroadcaster messagesWriteCharacteristicUUID]];
//    [peripheral writeValue:messagePacketData forCharacteristic:messageWrite type:CBCharacteristicWriteWithResponse];
//}
//
//- (void) sendNextIdentityToPeripheral:(CBPeripheral*)peripheral {
//    // Write your identity
//    BLEIdentityPacket *peer = [self peerForPeripheral:peripheral];
//    BLEIdentityPacket *identity = [self.dataStorage transport:self nextOutgoingIdentityForPeer:peer];
//    if (!identity) {
//        return;
//    }
//    NSData *identityPacketData = [identity packetData];
//    [self.dataStorage transport:self willWriteIdentity:identity toPeer:peer];
//    CBCharacteristic *identityWrite = [self characteristicForUUID:[BLEBroadcaster identityWriteCharacteristicUUID]];
//    [peripheral writeValue:identityPacketData forCharacteristic:identityWrite type:CBCharacteristicWriteWithResponse];
//}


- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    if (error) {
        DDLogError(@"%@: %@ %@", THIS_FILE, THIS_METHOD, error.userInfo);
    } else {
        DDLogVerbose(@"%@: %@ %@", THIS_FILE, THIS_METHOD, characteristic);
        [self handleResponseFromPeripheral:peripheral characteristic:characteristic type:Write];
//        CBUUID *uuid = characteristic.UUID;
//        if ([uuid isEqual:[BLEBroadcaster identityWriteCharacteristicUUID]]) {
//            [self sendNextIdentityToPeripheral:peripheral];
//        } else if ([uuid isEqual:[BLEBroadcaster messagesWriteCharacteristicUUID]]) {
//            [self sendNextMessageToPeripheral:peripheral];
//        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    if (error) {
        DDLogError(@"%@: %@ %@", THIS_FILE, THIS_METHOD, error.userInfo);
    } else {
        DDLogVerbose(@"%@: %@ %@", THIS_FILE, THIS_METHOD, service.characteristics);
        
        [service.characteristics enumerateObjectsUsingBlock:^(CBCharacteristic *characteristic, NSUInteger idx, BOOL *stop) {
            [self.characteristicsDictionary setObject:characteristic forKey:characteristic.UUID.UUIDString];
            // If a request is registered for this characteristic uuid, inform the request that a matching characteristic was found.
            // This is necessary until we can construct CBCharacteristics a priori
            // TODO : Make this more flexible so we don't have to adjust for new request types. We could just keep another NSDictionary of CBUUID -> BLEScannerRequest
            NSString *readRequestKey = [self makeRequestKeyForCharacteristicUUID:characteristic.UUID type:Read];
            NSString *writeRequestKey = [self makeRequestKeyForCharacteristicUUID:characteristic.UUID type:Write];
            
            if ([self.requestsForKeyDictionary objectForKey:readRequestKey]) {
                [[self.requestsForKeyDictionary objectForKey:readRequestKey] didDiscoverMatchingPeripheralCharacteristic:characteristic];
            }
            if ([self.requestsForKeyDictionary objectForKey:writeRequestKey]) {
                [[self.requestsForKeyDictionary objectForKey:writeRequestKey] didDiscoverMatchingPeripheralCharacteristic:characteristic];
            }
            
        }];
        
        [self beginRequestFlowForPeripheral:peripheral];
        
//        All requests against peripherals will be handled by performNextRequestForPeripheral
//        // Write your identity
//        [self sendNextIdentityToPeripheral:peripheral];
//        
//        // Read peripheral's identity
//        CBCharacteristic *identityRead = [self characteristicForUUID:[BLEBroadcaster identityReadCharacteristicUUID]];
//        [peripheral readValueForCharacteristic:identityRead];
    }
}

/**
 * Prepare a queue of requests for the given peripheral based on requests added via addRequest
 * and perform the first request
 */
- (void) beginRequestFlowForPeripheral: (CBPeripheral *) peripheral {
    // We can only have one request flow in effect for a peripheral at a given time
    // For now let's always start fresh under the assumption that any prior flow with this peripheral finished before re-connecting
    DDLogVerbose(@"CBPeripheral Identifier !? : %@", [peripheral identifier]);
    [self.requestsForPeripheralDictionary setObject:[self.requests mutableCopy] forKey: [peripheral identifier]]; // TODO Does identifer work?
    
    [self performNextRequestForPeripheral:peripheral];
}

/**
 * Perform the next request queued for the given peripheral, if available.
 */
- (void) performNextRequestForPeripheral: (CBPeripheral *) peripheral {
    NSMutableArray *requestQueue = [self.requestsForPeripheralDictionary objectForKey: [peripheral identifier]];
    if (!requestQueue || [requestQueue count] == 0) {
            DDLogVerbose(@"No requests remain for peripheral %@", [peripheral identifier]);
            return;
    }

    BLEScannerRequest *nextRequest = [requestQueue objectAtIndex:0];
    //Don't remove the request from requestQueue until we've handled the response
    
    [nextRequest performRequestForPeripheral:peripheral];
}

/**
 * Handle a response to a previous request made via performNextRequestForPeripheral
 */
- (void) handleResponseFromPeripheral: (CBPeripheral *) peripheral characteristic:(CBCharacteristic *)characteristic type: (RequestType) type {
    NSMutableArray *requestQueue = [self.requestsForPeripheralDictionary objectForKey: [peripheral identifier]];
    if (!requestQueue || [requestQueue count] == 0) {
        DDLogVerbose(@"Unexpected: No response for peripheral! %@", [peripheral identifier]);
        return;
    }
    
    BLEScannerRequest *nextRequest = [requestQueue objectAtIndex:0];
    BOOL requestComplete = [nextRequest handleResponseFromPeripheral:peripheral characteristic:characteristic];
    
    if (requestComplete) {
        [requestQueue removeObjectAtIndex:0];
    }
    
    [self performNextRequestForPeripheral:peripheral];
}

 /**
  * Create a key uniquely representing a combination of characteristic UUID and RequestType
  * for use in requestsForKeyDictionary
  */
- (NSString*) makeRequestKeyForCharacteristicUUID: (CBUUID *) characteristicUUID type: (RequestType) type {
    return [NSString stringWithFormat:@"%@-%lu", characteristicUUID, type];
}

@end
