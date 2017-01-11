//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreAudio/CoreAudioTypes.h>
#include <sys/socket.h> 
#include <netinet/in.h>

@interface RTSPServerConfig : NSObject
@property (strong) NSData* spsNal;
@property (strong) NSData* ppsNal;
@property (assign) AudioStreamBasicDescription audioSettings;
@end

@interface RTSPServer : NSObject
+ (NSString*) getIPAddress;
+ (RTSPServer*) setupListener:(RTSPServerConfig*) configData;

- (RTSPServerConfig*)getConfigData;
- (void) onAudioData:(NSArray*) data time:(double) pts;
- (void) onVideoData:(NSArray*) data time:(double) pts;
- (void) shutdownConnection:(id) conn;
- (void) shutdownServer;

//@property (readwrite, atomic) int bitrate;

@end
