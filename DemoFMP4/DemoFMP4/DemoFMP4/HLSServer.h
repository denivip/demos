//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

#ifndef DemoFMP4_HLSServer_h
#define DemoFMP4_HLSServer_h
#import "Defaults.h"
#import "GCDWebServer.h"

#include <fcntl.h>         // open
#include <unistd.h>        // close
#include <sys/stat.h>      // fstat
#include <sys/types.h>     // fstat
#include "CBCircularData.h"

@interface HLSServer : NSObject <GCDWebServerDelegate>
@property (strong, nonatomic) GCDWebServer* webServer;
@property (strong, nonatomic) NSData *liveEncodedTsHeader;
@property (strong, nonatomic) CBCircularData *liveEncodedTsBuffer;
@property (assign) NSUInteger liveEncodedTsBufferOffset;
@property (assign) double lastNwa;
@property (assign) NSInteger stat_bytesIn;
@property (assign) NSInteger stat_bytesOut;


+(instancetype)sharedInstance;
-(void)bootstrapServer;
-(double)lastNetworkActivity;
-(void)resetLiveEncodedBuffers;
+(void)bumpLastNetworkActivity;
+(void)bumpNetworkStatsBytesIn:(NSInteger)bi bytesOut:(NSInteger)bo;


@end



#endif
