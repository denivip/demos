//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CacheFileManager.h"
#import "FFRedecoder.h"
#import "muxers.h"
#import "ts.h"

static const int ddLogLevel = LOG_LEVEL_ERROR;
@implementation FFRedecoder

dispatch_queue_t ffRedecoderDispatchQueue;
+ (void)initialize
{
    ffRedecoderDispatchQueue = dispatch_queue_create("FFRedecoderSession", DISPATCH_QUEUE_SERIAL);
}


- (void)addTSFiles2Play:(NSArray*)files {
    NSURL* fileUrl = [files lastObject];
    ts::demuxer cpp_demuxer;
    cpp_demuxer.parse_only=false;
    cpp_demuxer.es_parse=false;
    cpp_demuxer.dump=0;
    cpp_demuxer.av_only=false;
    cpp_demuxer.channel=0;
    cpp_demuxer.pes_output=false;
    cpp_demuxer.prefix = [[[NSProcessInfo processInfo] globallyUniqueString] UTF8String];
    cpp_demuxer.dst = [[CacheFileManager cachePathForKey:@"test"] cStringUsingEncoding:[NSString defaultCStringEncoding]];
    
    double current_video_fps = -1;
    int res = cpp_demuxer.demux_file([[fileUrl path] UTF8String], &current_video_fps);
}

- (void)startCrunchingFiles {
    
}
@end

