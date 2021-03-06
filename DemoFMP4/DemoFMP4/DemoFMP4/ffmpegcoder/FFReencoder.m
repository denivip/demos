//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//


#import <Foundation/Foundation.h>
#import "FFReencoder.h"
#import "tsmuxer.h"

static const int ddLogLevel = LOG_LEVEL_ERROR;
@implementation FFReencoder


+ (void)initialize
{
}



+(double)getSampleDuration:(CMSampleBufferRef)sampleBuffer {
    CMTime cmDuration = CMSampleBufferGetDuration(sampleBuffer);
    double totalDuration = CMTimeGetSeconds(cmDuration);
    return totalDuration;
}

+(BOOL)muxVideoBuffer:(CBCircularData*)video audioBuffer:(CBCircularData*)audio completion:(MuxCompletionBlock)onok {
    NSUInteger totallen = video.size;
    if(totallen == 0){
        return NO;
    }
    int code = noErr;
    @autoreleasepool {
        NSData* vpkts_buff = [video readData:video.lowOffset length:video.size];
        NSData* apkts_buff = [audio readData:audio.lowOffset length:audio.size];
        
        int64_t moov_data_size = 0;
        void* moov_data_bytes = NULL;
        int64_t moof_data_size = 0;
        void* moof_data_bytes = NULL;
        code = avMuxH264Aac(vpkts_buff.bytes, [vpkts_buff length],
                                apkts_buff.bytes, [apkts_buff length],
                            &moov_data_bytes, &moov_data_size,
                            &moof_data_bytes, &moof_data_size);
        if(code == noErr){
            NSData* moof_chunk = [NSData dataWithBytes:moof_data_bytes length:(NSUInteger)moof_data_size];
            NSData* moov_chunk = [NSData dataWithBytes:moov_data_bytes length:(NSUInteger)moov_data_size];
            if(onok){
                onok(moov_chunk, moof_chunk);
            }
        }
        free(moov_data_bytes);
        free(moof_data_bytes);
    }
    if(code != noErr){
        DDLogError(@"muxIntoTsVideoBuffer: error code=%i", code);
        return NO;
    }
    return YES;
}
@end

