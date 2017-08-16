//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CacheFileManager.h"
#import "FFRedecoder.h"
#import "muxers.h"

static const int ddLogLevel = LOG_LEVEL_ERROR;
@implementation FFRedecoder

dispatch_queue_t ffRedecoderDispatchQueue;
+ (void)initialize
{
    ffRedecoderDispatchQueue = dispatch_queue_create("FFRedecoderSession", DISPATCH_QUEUE_SERIAL);
}


- (void)addTSFiles2Play:(NSArray*)files {
    NSURL* fileUrl = [files lastObject];
    avDemuxTS([[fileUrl path] UTF8String]);
}

- (void)startCrunchingFiles {
    
}
@end

