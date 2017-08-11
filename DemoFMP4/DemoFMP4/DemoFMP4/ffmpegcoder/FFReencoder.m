//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//


#import <Foundation/Foundation.h>
#import "FFReencoder.h"
#include "muxers.h"

static const int ddLogLevel = LOG_LEVEL_ERROR;
@implementation FFReencoder

dispatch_queue_t ffReencoderDispatchQueue;
+ (void)initialize
{
    ffReencoderDispatchQueue = dispatch_queue_create("FFReencoderSession", DISPATCH_QUEUE_SERIAL);
}

+(double)getSampleDuration:(CMSampleBufferRef)sampleBuffer {
    CMTime cmDuration = CMSampleBufferGetDuration(sampleBuffer);
    double totalDuration = CMTimeGetSeconds(cmDuration);
    return totalDuration;
}

+(BOOL)muxVideoBuffer:(NSData*)vpkts_buff audioBuffer:(NSData*)apkts_buff completion:(MuxCompletionBlock)onok {
    NSUInteger totallen = vpkts_buff.length;
    if(totallen == 0){
        return NO;
    }
    @autoreleasepool {
        //NSLog(@"muxVideoBuffer video %lu (%@-%@), audio %lu (%@-%@)",video.dataBuffers.count,video.firstWriteTs,video.lastWriteTs,audio.dataBuffers.count,audio.firstWriteTs,audio.lastWriteTs);
        //NSData* vpkts_buff = [video readCurrentData:NO];
        //NSData* apkts_buff = [audio readCurrentData:NO];
        dispatch_async(ffReencoderDispatchQueue, ^{
            int code = noErr;
            int64_t moov_data_size = 0;
            void* moov_data_bytes = NULL;
            int64_t moof_data_size = 0;
            void* moof_data_bytes = NULL;
            code = avMuxH264AacMP4(vpkts_buff.bytes, [vpkts_buff length],
                                  apkts_buff.bytes, [apkts_buff length],
                                  &moov_data_bytes, &moov_data_size,
                                  &moof_data_bytes, &moof_data_size);
            if(code == noErr){
                NSData* moof_chunk = moof_data_bytes?[NSData dataWithBytes:moof_data_bytes length:(NSUInteger)moof_data_size]:NULL;
                NSData* moov_chunk = moov_data_bytes?[NSData dataWithBytes:moov_data_bytes length:(NSUInteger)moov_data_size]:NULL;
                if(onok){
                    onok(moov_chunk, moof_chunk);
                }
            }
            free(moov_data_bytes);
            free(moof_data_bytes);
        });
    }
    return YES;
}
@end

