//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

#import "PBJVision.h"
#import "CBCircularData.h"
#ifndef DemoFMP4_FFReencoder_h
#define DemoFMP4_FFReencoder_h

typedef void (^MuxCompletionBlock)(NSData* moov_dat, NSData* moof_dat);

@interface FFReencoder : NSObject
+(double)getSampleDuration:(CMSampleBufferRef)sampleBuffer;
+(BOOL)muxVideoBuffer:(NSData*)vpkts_buff audioBuffer:(NSData*)apkts_buff completion:(MuxCompletionBlock)onok;
@end

#endif
