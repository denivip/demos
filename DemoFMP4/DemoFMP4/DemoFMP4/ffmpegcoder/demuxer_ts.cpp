//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "muxers.h"
#import "ts.h"

int avDemuxTS(const char* ts_filepath, void** videobuf, int64_t* videobuf_len, void** audiobuf, int64_t* audiobuf_len) {

    ts::demuxer cpp_demuxer;
    cpp_demuxer.parse_only=false;
    cpp_demuxer.es_parse=false;
    cpp_demuxer.dump=0;
    cpp_demuxer.av_only=false;
    cpp_demuxer.channel=0;
    cpp_demuxer.pes_output=false;
    cpp_demuxer.writeBlockCb = ^(const char* data, int64_t datalen, void* s){
        ts::stream* strm = (ts::stream*)s;
        printf("\nNew block %lld of type %x", datalen, strm->type);
    };
    //cpp_demuxer.prefix = [[[NSProcessInfo processInfo] globallyUniqueString] UTF8String];
    //cpp_demuxer.dst = [[CacheFileManager cachePathForKey:@"test"] cStringUsingEncoding:[NSString defaultCStringEncoding]];
    
    double current_video_fps = -1;
    cpp_demuxer.demux_file(ts_filepath, &current_video_fps);
    if(current_video_fps > 0){
        printf("\nFile demuxed, fps %f", current_video_fps);
        //for(int i = 0; i< cpp_demuxer.streams.size(); i++){
        //    ts::stream& strm = cpp_demuxer.streams[i];
        //}
        return 0;
    }
    return 1;
}
