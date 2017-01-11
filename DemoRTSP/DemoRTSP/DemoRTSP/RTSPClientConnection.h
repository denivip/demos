//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RTSPServer.h"

typedef struct {
    int streamType;
    CFDataRef _addrRTP;
    CFSocketRef _sRTP;
    CFDataRef _addrRTCP;
    CFSocketRef _sRTCP;
    
    long _packets;
    long _bytesSent;
    long _ssrc;
    BOOL _bFirst;
    
    // time mapping using NTP
    uint64_t _ntpBase;
    uint64_t _rtpBase;
    double _ptsBase;
    
    // RTCP stats
    long _packetsReported;
    long _bytesReported;
    NSTimeInterval _sentRTCP;
    
    // reader reports
    CFSocketRef _recvRTCP;
    CFRunLoopSourceRef _rlsRTCP;
} k_rtp_stream;

@interface RTSPClientConnection : NSObject
+ (RTSPClientConnection*) createWithSocket:(CFSocketNativeHandle) s server:(RTSPServer*) server;
- (void) onAudioData:(NSArray*) data time:(double) pts;
- (void) onVideoData:(NSArray*) data time:(double) pts;
- (void) shutdown;

@end
