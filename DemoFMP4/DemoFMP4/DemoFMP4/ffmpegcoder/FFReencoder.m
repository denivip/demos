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
            int64_t moof_data_size = 0;
            void* moof_data_bytes = NULL;
            code = avMuxH264AacTS(vpkts_buff.bytes, [vpkts_buff length],
                                  apkts_buff.bytes, [apkts_buff length],
                                  &moof_data_bytes, &moof_data_size);
            if(code == noErr){
                NSData* moof_chunk = moof_data_bytes?[NSData dataWithBytes:moof_data_bytes length:(NSUInteger)moof_data_size]:NULL;
                if(onok){
                    onok(moof_chunk);
                }
            }
            free(moof_data_bytes);
        });
    }
    return YES;
}
@end

