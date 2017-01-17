//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

#import "RTSPClientConnection.h"
#import "RTSPMessage.h"
#import "arpa/inet.h"
#import "NALUnit.h"
#import "Defaults.h"

void tonet_short(uint8_t* p, unsigned short s)
{
    p[0] = (s >> 8) & 0xff;
    p[1] = s & 0xff;
}
void tonet_long(uint8_t* p, unsigned long l)
{
    p[0] = (l >> 24) & 0xff;
    p[1] = (l >> 16) & 0xff;
    p[2] = (l >> 8) & 0xff;
    p[3] = l & 0xff;
}

static const char* Base64Mapping = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
static const int max_packet_size = 1200;

NSString* encodeLong(unsigned long val, int nPad)
{
    char ch[4];
    int cch = 4 - nPad;
    for (int i = 0; i < cch; i++)
    {
        int shift = 6 * (cch - (i+1));
        int bits = (val >> shift) & 0x3f;
        ch[i] = Base64Mapping[bits];
    }
    for (int i = 0; i < nPad; i++)
    {
        ch[cch + i] = '=';
    }
    NSString* s = [[NSString alloc] initWithBytes:ch length:4 encoding:NSUTF8StringEncoding];
    return s;
}

NSString* encodeToBase64(NSData* data)
{
    NSString* s = @"";
    
    const uint8_t* p = (const uint8_t*) [data bytes];
    int cBytes = (int)[data length];
    while (cBytes >= 3)
    {
        unsigned long val = (p[0] << 16) + (p[1] << 8) + p[2];
        p += 3;
        cBytes -= 3;
        
        s = [s stringByAppendingString:encodeLong(val, 0)];
    }
    if (cBytes > 0)
    {
        int nPad;
        unsigned long val;
        if (cBytes == 1)
        {
            // pad 8 bits to 2 x 6 and add 2 ==
            nPad = 2;
            val = p[0] << 4;
        }
        else
        {
            // must be two bytes -- pad 16 bits to 3 x 6 and add one =
            nPad = 1;
            val = (p[0] << 8) + p[1];
            val = val << 2;
        }
        s = [s stringByAppendingString:encodeLong(val, nPad)];
    }
    return s;
}

enum ServerState
{
    ServerIdle,
    Setup,
    Playing,
};

@interface RTSPClientConnection ()
{
    CFSocketRef _s;
    RTSPServer* _server;
    CFRunLoopSourceRef _rls;
    NSString* _session;
    ServerState _state;
    
    k_rtp_stream stream[10];
    int streams_count;
}

- (RTSPClientConnection*) initWithSocket:(CFSocketNativeHandle) s Server:(RTSPServer*) server;
- (void) onSocketData:(CFDataRef)data;
- (void) onRTCP:(CFDataRef) data;

@end

static void onSocket (
               CFSocketRef s,
               CFSocketCallBackType callbackType,
               CFDataRef address,
               const void *data,
               void *info
               )
{
    RTSPClientConnection* conn = (__bridge RTSPClientConnection*)info;
    switch (callbackType)
    {
        case kCFSocketDataCallBack:
            [conn onSocketData:(CFDataRef) data];
            break;
            
        default:
            NSLog(@"unexpected socket event");
            break;
    }
    
}

static void onRTCP(CFSocketRef s,
                   CFSocketCallBackType callbackType,
                   CFDataRef address,
                   const void *data,
                   void *info
                   )
{
    RTSPClientConnection* conn = (__bridge RTSPClientConnection*)info;
    switch (callbackType)
    {
        case kCFSocketDataCallBack:
            [conn onRTCP:(CFDataRef) data];
            break;
            
        default:
            NSLog(@"unexpected socket event");
            break;
    }
}

@implementation RTSPClientConnection

+ (RTSPClientConnection*) createWithSocket:(CFSocketNativeHandle) s server:(RTSPServer*) server
{
    RTSPClientConnection* conn = [RTSPClientConnection alloc];
    if ([conn initWithSocket:s Server:server] != nil)
    {
        return conn;
    }
    return nil;
}

- (RTSPClientConnection*) initWithSocket:(CFSocketNativeHandle)s Server:(RTSPServer *)server
{
    _state = ServerIdle;
    _server = server;
    CFSocketContext info;
    memset(&info, 0, sizeof(info));
    info.info = (void*)CFBridgingRetain(self);
    
    _s = CFSocketCreateWithNative(nil, s, kCFSocketDataCallBack, onSocket, &info);
    
    _rls = CFSocketCreateRunLoopSource(nil, _s, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), _rls, kCFRunLoopCommonModes);

    return self;
}

- (void) onSocketData:(CFDataRef)data
{
    // https://www.ietf.org/rfc/rfc2326.txt
    if (CFDataGetLength(data) == 0)
    {
        [self tearDownAll];
        CFSocketInvalidate(_s);
        _s = nil;
        [_server shutdownConnection:self];
        return;
    }
    RTSPMessage* msg = [RTSPMessage createWithData:data];
    if (msg != nil)
    {
        NSString* response = nil;
        NSString* cmd = msg.command;
        if ([cmd caseInsensitiveCompare:@"options"] == NSOrderedSame)
        {
            response = [msg createResponse:200 text:@"OK"];
            response = [response stringByAppendingString:@"Server: DemoRTSP/1.0\r\n"];
            response = [response stringByAppendingString:@"Public: DESCRIBE, SETUP, TEARDOWN, PLAY, OPTIONS\r\n\r\n"];
        }
        else if ([cmd caseInsensitiveCompare:@"describe"] == NSOrderedSame)
        {
            [self tearDownAll];
            NSString* sdp = [self makeSDP];
            response = [msg createResponse:200 text:@"OK"];
            NSString* date = [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterLongStyle timeStyle:NSDateFormatterLongStyle];
            CFDataRef dlocaladdr = CFSocketCopyAddress(_s);
            struct sockaddr_in* localaddr = (struct sockaddr_in*) CFDataGetBytePtr(dlocaladdr);
            
            response = [response stringByAppendingFormat:@"Content-base: rtsp://%s/\r\n", inet_ntoa(localaddr->sin_addr)];
            CFRelease(dlocaladdr);
            response = [response stringByAppendingFormat:@"Date: %@\r\nContent-Type: application/sdp\r\nContent-Length: %d\r\n\r\n", date, (int)[sdp length] ];
            response = [response stringByAppendingString:sdp];
        }
        else if ([cmd caseInsensitiveCompare:@"setup"] == NSOrderedSame)
        {
            NSString* transport = [msg valueForOption:@"transport"];
            NSString* session_name = [msg valueForOption:@"session"];
            if (_session != nil && ![_session isEqualToString:session_name])
            {
                response = [msg createResponse:459 text:@"Aggregate Operation Not Allowed"];
            }
            if(response == nil){
                NSArray* props = [transport componentsSeparatedByString:@";"];
                NSArray* ports = nil;
                for (NSString* s in props)
                {
                    if ([s length] > 14)
                    {
                        if ([s compare:@"client_port=" options:0 range:NSMakeRange(0, 12)] == NSOrderedSame)
                        {
                            NSString* val = [s substringFromIndex:12];
                            ports = [val componentsSeparatedByString:@"-"];
                            break;
                        }
                    }
                }
                if ([ports count] == 2)
                {
                    int portRTP = (int)[ports[0] integerValue];
                    int portRTCP = (int) [ports[1] integerValue];
                    
                    k_rtp_stream* stx = [self setupStream:portRTP rtcp:portRTCP session:session_name];
                    if ([msg.command_full rangeOfString:[NSString stringWithFormat:@"_stx_%i",RTPSTREAM_TYPE_VIDEO]].location != NSNotFound) {
                        stx->streamType = RTPSTREAM_TYPE_VIDEO;
                    }else{
                        stx->streamType = RTPSTREAM_TYPE_AUDIO;
                    }
                    if([_session length] > 0)
                    {
                        response = [msg createResponse:200 text:@"OK"];
                        response = [response stringByAppendingFormat:@"Session: %@\r\nTransport: RTP/AVP;unicast;client_port=%d-%d;server_port=6970-6971\r\n\r\n",
                                    _session,
                                    portRTP,portRTCP];
                    }
                }
            }
            if (response == nil)
            {
                response = [msg createResponse:451 text:@"Unknown command"];
            }
        }
        else if ([cmd caseInsensitiveCompare:@"play"] == NSOrderedSame)
        {
            @synchronized(self)
            {
                if (_state != Setup)
                {
                    response = [msg createResponse:451 text:@"Wrong state"];
                }
                else
                {
                    _state = Playing;
                    for(int i=0;i<streams_count;i++){
                        stream[i]._bFirst = YES;
                    }
                    response = [msg createResponse:200 text:@"OK"];
                    response = [response stringByAppendingFormat:@"Session: %@\r\n\r\n", _session];
                }
            }
        }
        else if ([cmd caseInsensitiveCompare:@"teardown"] == NSOrderedSame)
        {
            [self tearDownAll];
            response = [msg createResponse:200 text:@"OK"];
        }
        else
        {
            NSLog(@"RTSP method %@ not handled", cmd);
            response = [msg createResponse:451 text:@"Method not recognised"];
        }
        if (response != nil)
        {
            NSData* dataResponse = [response dataUsingEncoding:NSUTF8StringEncoding];
            CFSocketError e = CFSocketSendData(_s, NULL, (__bridge CFDataRef)(dataResponse), 2);
            if (e)
            {
                NSLog(@"RTSPMessage send error: %ld", e);
            }else{
                NSLog(@"RTSPMessage answer: %@", response);
            }
        }
    }
}

- (NSString*) makeSDP
{
    // http://stackoverflow.com/questions/2378609/how-to-decode-sprop-parameter-sets-in-a-h264-sdp
    // https://tools.ietf.org/html/rfc3890
    RTSPServerConfig* config = [_server getConfigData];
    SeqParamSet seqParams;
    NALUnit* spsNal = new NALUnit((const BYTE*)config.spsNal.bytes, (int)[config.spsNal length]);
    seqParams.Parse(spsNal);
    int cx = (int)seqParams.EncodedWidth();
    int cy = (int)seqParams.EncodedHeight();
    
    NSString* profile_level_id = [NSString stringWithFormat:@"%02x%02x%02x", seqParams.Profile(), seqParams.Compat(), seqParams.Level()];
    
    NSData* data = config.spsNal;
    NSString* sps = encodeToBase64(data);
    data = config.ppsNal;
    NSString* pps = encodeToBase64(data);
    
    // !! o=, s=, u=, c=, b=? control for track?
    unsigned long verid = random();
    
    CFDataRef dlocaladdr = CFSocketCopyAddress(_s);
    struct sockaddr_in* localaddr = (struct sockaddr_in*) CFDataGetBytePtr(dlocaladdr);
    NSString* sdp = [NSString stringWithFormat:@"v=0\r\no=- %ld %ld IN IP4 %s\r\ns=%@\r\nc=IN IP4 0.0.0.0\r\nt=0 0\r\na=control:*\r\n", verid, verid, inet_ntoa(localaddr->sin_addr),STREAM_TITLE];
    CFRelease(dlocaladdr);
    
    //int packets = (_server.bitrate / (max_packet_size * 8)) + 1;
    //sdp = [sdp stringByAppendingFormat:@"m=video 0 RTP/AVP 96\r\nb=TIAS:%d\r\na=maxprate:%d.0000\r\na=control:streamid=1\r\n", _server.bitrate, packets];
    sdp = [sdp stringByAppendingFormat:@"m=video 0 RTP/AVP %i\r\na=control:streamid=_stx_%i\r\n", RTPSTREAM_TYPE_VIDEO, RTPSTREAM_TYPE_VIDEO];
    sdp = [sdp stringByAppendingFormat:@"a=rtpmap:%i H264/90000\r\na=mimetype:string;\"video/H264\"\r\n", RTPSTREAM_TYPE_VIDEO];
    sdp = [sdp stringByAppendingFormat:@"a=framesize:%i %d-%d\r\na=Width:integer;%d\r\na=Height:integer;%d\r\n", RTPSTREAM_TYPE_VIDEO, cx, cy, cx, cy];
    sdp = [sdp stringByAppendingFormat:@"a=fmtp:%i packetization-mode=1;profile-level-id=%@;sprop-parameter-sets=%@,%@\r\n", RTPSTREAM_TYPE_VIDEO, profile_level_id, sps, pps];
    delete spsNal;
    
    // Audio part http://nto.github.io/AirPlay.html
    AudioStreamBasicDescription audio = config.audioSettings;
    sdp = [sdp stringByAppendingFormat:@"m=audio 0 RTP/AVP %i\r\na=control:streamid=_stx_%i\r\n", RTPSTREAM_TYPE_AUDIO, RTPSTREAM_TYPE_AUDIO];
    sdp = [sdp stringByAppendingFormat:@"a=rtpmap:%i mpeg4-generic/%i/%i\r\n", RTPSTREAM_TYPE_AUDIO, (int)audio.mSampleRate,(int)audio.mChannelsPerFrame];
    sdp = [sdp stringByAppendingFormat:@"a=fmtp:%i mode=AAC-hbr;\r\n", RTPSTREAM_TYPE_AUDIO];
    // a=fmtp:97 profile-level-id=41; cpresent=0; config=400024203fc0
    
    //NSLog(@"Rtsp sdp: %@", sdp);
    return sdp;
}

- (k_rtp_stream*) setupStream:(int) portRTP rtcp:(int) portRTCP session:(NSString*)sess
{
    // !! most basic possible for initial testing
    k_rtp_stream* stx = nil;
    @synchronized(self)
    {
        stx = &stream[streams_count];
        streams_count++;
        CFDataRef data = CFSocketCopyPeerAddress(_s);
        struct sockaddr_in* paddr = (struct sockaddr_in*) CFDataGetBytePtr(data);
        paddr->sin_port = htons(portRTP);
        stx->_addrRTP = CFDataCreate(nil, (uint8_t*) paddr, sizeof(struct sockaddr_in));
        stx->_sRTP = CFSocketCreate(nil, PF_INET, SOCK_DGRAM, IPPROTO_UDP, 0, nil, nil);
        
        paddr->sin_port = htons(portRTCP);
        stx->_addrRTCP = CFDataCreate(nil, (uint8_t*) paddr, sizeof(struct sockaddr_in));
        stx->_sRTCP = CFSocketCreate(nil, PF_INET, SOCK_DGRAM, IPPROTO_UDP, 0, nil, nil);
        CFRelease(data);
        
        // reader reports received here
        CFSocketContext info;
        memset(&info, 0, sizeof(info));
        info.info = (void*)CFBridgingRetain(self);
        stx->_recvRTCP = CFSocketCreate(nil, PF_INET, SOCK_DGRAM, IPPROTO_UDP, kCFSocketDataCallBack, onRTCP, &info);
        
        struct sockaddr_in addr;
        addr.sin_addr.s_addr = INADDR_ANY;
        addr.sin_family = AF_INET;
        addr.sin_port = htons(6971);
        CFDataRef dataAddr = CFDataCreate(nil, (const uint8_t*)&addr, sizeof(addr));
        CFSocketSetAddress(stx->_recvRTCP, dataAddr);
        CFRelease(dataAddr);
        
        stx->_rlsRTCP = CFSocketCreateRunLoopSource(nil, stx->_recvRTCP, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), stx->_rlsRTCP, kCFRunLoopCommonModes);
        
        // flag that setup is valid
        if(sess != nil){
            _session = sess;
        }else{
            long sessionid = random();
            _session = [NSString stringWithFormat:@"%ld", sessionid];
        }
        _state = Setup;
        stx->_ssrc = random();
        stx->_packets = 0;
        stx->_bytesSent = 0;
        stx->_rtpBase = 0;
    
        stx->_sentRTCP = 0;
        stx->_packetsReported = 0;
        stx->_bytesReported = 0;
    }
    return stx;
}

- (void) onAudioData:(NSArray*) data time:(double) pts
{
    @synchronized(self)
    {
        if (_state != Playing)
        {
            return;
        }
    }
    
    k_rtp_stream* audio_stream = nil;
    for(int i=0;i<streams_count;i++){
        if(stream[i].streamType == RTPSTREAM_TYPE_AUDIO){
            audio_stream = &stream[i];
            break;
        }
    }
    if(audio_stream == nil){
        return;
    }
    
    const int rtp_header_size = 12;
    const int max_single_packet = max_packet_size - rtp_header_size;
    const int max_fragment_packet = max_single_packet - 2;
    unsigned char packet[max_packet_size];
    
    int nNALUs = (int)[data count];
    for (int i = 0; i < nNALUs; i++)
    {
        NSData* nalu = [data objectAtIndex:i];
        int cBytes = (int)[nalu length];
        BOOL bLast = (i == nNALUs-1);
        const unsigned char* pSource = (unsigned char*)[nalu bytes];
        
        if (cBytes < max_single_packet)
        {
            [self writeHeader:packet marker:bLast time:pts inStream:audio_stream];
            memcpy(packet + rtp_header_size, [nalu bytes], cBytes);
            [self sendPacket:packet length:(cBytes + rtp_header_size) inStream:audio_stream];
        }
        else
        {
            unsigned char NALU_Header = pSource[0];
            pSource += 1;
            cBytes -= 1;
            BOOL bStart = YES;
            
            while (cBytes)
            {
                int cThis = (cBytes < max_fragment_packet)? cBytes : max_fragment_packet;
                BOOL bEnd = (cThis == cBytes);
                [self writeHeader:packet marker:(bLast && bEnd) time:pts inStream:audio_stream];
                unsigned char* pDest = packet + rtp_header_size;
                
                pDest[0] = (NALU_Header & 0xe0) + 28;   // FU_A type
                unsigned char fu_header = (NALU_Header & 0x1f);
                if (bStart)
                {
                    fu_header |= 0x80;
                    bStart = false;
                }
                else if (bEnd)
                {
                    fu_header |= 0x40;
                }
                pDest[1] = fu_header;
                pDest += 2;
                memcpy(pDest, pSource, cThis);
                pDest += cThis;
                [self sendPacket:packet length:(int)(pDest - packet) inStream:audio_stream];
                
                pSource += cThis;
                cBytes -= cThis;
            }
        }
    }
}

- (void) onVideoData:(NSArray*) data time:(double) pts
{
    @synchronized(self)
    {
        if (_state != Playing)
        {
            return;
        }
    }
    
    k_rtp_stream* video_stream = nil;
    for(int i=0;i<streams_count;i++){
        if(stream[i].streamType == RTPSTREAM_TYPE_VIDEO){
            video_stream = &stream[i];
            break;
        }
    }
    if(video_stream == nil){
        return;
    }
    const int rtp_header_size = 12;
    const int max_single_packet = max_packet_size - rtp_header_size;
    const int max_fragment_packet = max_single_packet - 2;
    unsigned char packet[max_packet_size];
    
    int nNALUs = (int)[data count];
    for (int i = 0; i < nNALUs; i++)
    {
        NSData* nalu = [data objectAtIndex:i];
        int cBytes = (int)[nalu length];
        BOOL bLast = (i == nNALUs-1);
        
        const unsigned char* pSource = (unsigned char*)[nalu bytes];
 
        if (video_stream->_bFirst)
        {
            if ((pSource[0] & 0x1f) != 5)
            {
                //NSLog(@"Playback: skipped frame type=%i, searching for first IDR", (pSource[0] & 0x1f));
                continue;
            }
            video_stream->_bFirst = NO;
            NSLog(@"Playback: starting at first IDR");
        }
        
        if (cBytes < max_single_packet)
        {
            [self writeHeader:packet marker:bLast time:pts inStream:video_stream];
            memcpy(packet + rtp_header_size, [nalu bytes], cBytes);
            [self sendPacket:packet length:(cBytes + rtp_header_size) inStream:video_stream];
        }
        else
        {
            unsigned char NALU_Header = pSource[0];
            pSource += 1;
            cBytes -= 1;
            BOOL bStart = YES;
            
            while (cBytes)
            {
                int cThis = (cBytes < max_fragment_packet)? cBytes : max_fragment_packet;
                BOOL bEnd = (cThis == cBytes);
                [self writeHeader:packet marker:(bLast && bEnd) time:pts inStream:video_stream];
                unsigned char* pDest = packet + rtp_header_size;
                
                pDest[0] = (NALU_Header & 0xe0) + 28;   // FU_A type
                unsigned char fu_header = (NALU_Header & 0x1f);
                if (bStart)
                {
                    fu_header |= 0x80;
                    bStart = false;
                }
                else if (bEnd)
                {
                    fu_header |= 0x40;
                }
                pDest[1] = fu_header;
                pDest += 2;
                memcpy(pDest, pSource, cThis);
                pDest += cThis;
                [self sendPacket:packet length:(int)(pDest - packet) inStream:video_stream];
                
                pSource += cThis;
                cBytes -= cThis;
            }
        }
    }
}

- (void) writeHeader:(uint8_t*) packet marker:(BOOL) bMarker time:(double) pts inStream:(k_rtp_stream*)stx
{
    packet[0] = 0x80;   // v= 2
    if (bMarker)
    {
        packet[1] = stx->streamType | 0x80;
    }
    else
    {
        packet[1] = stx->streamType;
    }
    unsigned short seq = stx->_packets & 0xffff;
    tonet_short(packet+2, seq);

    // map time
    while (stx->_rtpBase == 0)
    {
        stx->_rtpBase = random();
        stx->_ptsBase = pts;
        NSDate* now = [NSDate date];
        // ntp is based on 1900. There's a known fixed offset from 1900 to 1970.
        NSDate* ref = [NSDate dateWithTimeIntervalSince1970:-2208988800L];
        double interval = [now timeIntervalSinceDate:ref];
        stx->_ntpBase = (uint64_t)(interval * (1LL << 32));
    }
    pts -= stx->_ptsBase;
    uint64_t rtp = (uint64_t)(pts * 90000);
    rtp += stx->_rtpBase;
    tonet_long(packet + 4, (unsigned long)rtp);
    tonet_long(packet + 8, stx->_ssrc);
}

- (void) sendPacket:(uint8_t*) packet length:(int) cBytes inStream:(k_rtp_stream*)stx
{
    @synchronized(self)
    {
        if (stx->_sRTP)
        {
            CFDataRef data = CFDataCreate(nil, packet, cBytes);
            CFSocketSendData(stx->_sRTP, stx->_addrRTP, data, 0);
            CFRelease(data);
        }
        stx->_packets++;
        stx->_bytesSent += cBytes;
        //NSLog(@"Bytes sent to stream %i: %i", stx->streamType, cBytes);
        
        // RTCP packets
        NSTimeInterval unixtamp = [[NSDate date] timeIntervalSince1970];
        if ((stx->_sentRTCP < 1.0) || (unixtamp - stx->_sentRTCP >= 1))
        {
            uint8_t buf[7 * sizeof(uint32_t)];
            buf[0] = 0x80;
            buf[1] = 200;   // type == SR
            tonet_short(buf+2, 6);  // length (count of uint32_t minus 1)
            tonet_long(buf+4, stx->_ssrc);
            tonet_long(buf+8, (stx->_ntpBase >> 32));
            tonet_long(buf+12, (unsigned long)stx->_ntpBase);
            tonet_long(buf+16, (unsigned long)stx->_rtpBase);
            tonet_long(buf+20, (stx->_packets - stx->_packetsReported));
            tonet_long(buf+24, (stx->_bytesSent - stx->_bytesReported));
            int lenRTCP = 28;
            if (stx->_sRTCP)
            {
                CFDataRef dataRTCP = CFDataCreate(nil, buf, lenRTCP);
                CFSocketSendData(stx->_sRTCP, stx->_addrRTCP, dataRTCP, lenRTCP);
                CFRelease(dataRTCP);
            }
            
            stx->_sentRTCP = unixtamp;
            stx->_packetsReported = stx->_packets;
            stx->_bytesReported = stx->_bytesSent;
        }
    }
}

- (void) onRTCP:(CFDataRef) data
{
    // NSLog(@"RTCP recv");
}

- (void) tearDownAll
{
    for(int i=0;i<streams_count;i++){
        [self tearDownInStream:&stream[i]];
    }
    streams_count = 0;
    _session = nil;
}

- (void) tearDownInStream:(k_rtp_stream*)stx
{
    @synchronized(self)
    {
        if (stx->_sRTP)
        {
            CFSocketInvalidate(stx->_sRTP);
            stx->_sRTP = nil;
        }
        if (stx->_sRTCP)
        {
            CFSocketInvalidate(stx->_sRTCP);
            stx->_sRTCP = nil;
        }
        if (stx->_recvRTCP)
        {
            CFSocketInvalidate(stx->_recvRTCP);
            stx->_recvRTCP = nil;
        }
        if(stx->_rlsRTCP)
        {
            CFRunLoopSourceInvalidate(stx->_rlsRTCP);
            stx->_rlsRTCP = nil;
        }
        if(stx->_addrRTP)
        {
            CFRelease(stx->_addrRTP);
            stx->_addrRTP = nil;
        }
        if(stx->_addrRTCP)
        {
            CFRelease(stx->_addrRTCP);
            stx->_addrRTCP = nil;
        }
    }
}

- (void) shutdown
{
    [self tearDownAll];
    @synchronized(self)
    {
        CFSocketInvalidate(_s);
        _s = nil;
    }
}
@end
