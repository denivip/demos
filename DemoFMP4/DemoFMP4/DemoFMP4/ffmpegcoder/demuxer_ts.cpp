//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "muxers.h"
#import "ts.h"

int avDemuxTS(const char* ts_filepath) {

    ts::demuxer cpp_demuxer;
    cpp_demuxer.parse_only=false;
    cpp_demuxer.es_parse=false;
    cpp_demuxer.dump=0;
    cpp_demuxer.av_only=false;
    cpp_demuxer.channel=0;
    cpp_demuxer.pes_output=false;
    //cpp_demuxer.prefix = [[[NSProcessInfo processInfo] globallyUniqueString] UTF8String];
    //cpp_demuxer.dst = [[CacheFileManager cachePathForKey:@"test"] cStringUsingEncoding:[NSString defaultCStringEncoding]];
    
    double current_video_fps = -1;
    int res = cpp_demuxer.demux_file(ts_filepath, &current_video_fps);
    
    return 0;
}
