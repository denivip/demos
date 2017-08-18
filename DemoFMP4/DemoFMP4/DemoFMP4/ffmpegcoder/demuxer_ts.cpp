//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "muxers.h"
#import "ts.h"

int avDemuxTS(const char* ts_filepath, OnH264VideoData videocb, OnH264AudioData audiocb) {

    ts::demuxer cpp_demuxer;
    cpp_demuxer.parse_only=false;
    cpp_demuxer.parse_channel=-1;
    cpp_demuxer.av_only=false;
    cpp_demuxer.es_parse=false;
    cpp_demuxer.pes_output=false;
    cpp_demuxer.writeBlockCb = ^(const char* data, int64_t datalen, void* s){
        ts::stream* strm = (ts::stream*)s;
        //printf("New block %lld of type %x\n", datalen, strm->type);
        if(strm->type == 15){// fourcc 0f, audio
            audiocb(data,datalen);
        }
        if(strm->type == 27){// fourcc 1b, video
            videocb(data,datalen);
        }
    };
    //cpp_demuxer.prefix = [[[NSProcessInfo processInfo] globallyUniqueString] UTF8String];
    //cpp_demuxer.dst = [[CacheFileManager cachePathForKey:@"test"] cStringUsingEncoding:[NSString defaultCStringEncoding]];
    
    double current_video_fps = -1;
    cpp_demuxer.demux_file(ts_filepath, &current_video_fps);
    if(current_video_fps > 0){
        printf("File demuxed, fps %f\n", current_video_fps);
        //for(int i = 0; i< cpp_demuxer.streams.size(); i++){
        //    ts::stream& strm = cpp_demuxer.streams[i];
        //}
        return 0;
    }
    return 1;
}
