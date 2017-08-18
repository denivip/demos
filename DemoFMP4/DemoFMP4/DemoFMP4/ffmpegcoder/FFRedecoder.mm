//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CacheFileManager.h"
#import "FFRedecoder.h"
#import "muxers.h"


//static const int ddLogLevel = LOG_LEVEL_ERROR;

@interface FFRedecoder ()
@property (strong, nonatomic) NSMutableArray* playlistFiles;
@end

@implementation FFRedecoder
dispatch_queue_t ffRedecoderDispatchQueue;
+ (void)initialize
{
    ffRedecoderDispatchQueue = dispatch_queue_create("FFRedecoderSession", DISPATCH_QUEUE_SERIAL);
}

- (void)addTSFiles2Play:(NSArray*)files {
    if(self.playlistFiles == nil){
        self.playlistFiles = @[].mutableCopy;
    }
    [self.playlistFiles addObjectsFromArray:files];
}

- (void)startCrunchingFiles:(H264VideoView*)target {
    NSURL* fileUrl = [self.playlistFiles lastObject];
    //NSLog(@"startCrunchingFiles %@", fileUrl);
    if(fileUrl == nil){
        return;
    }
    NSMutableData* vdt = [[NSMutableData alloc] initWithCapacity:500000];
    NSMutableData* adt = [[NSMutableData alloc] initWithCapacity:500000];
    avDemuxTS([[fileUrl path] UTF8String],
              ^(const char* data, int64_t datalen){
                  [vdt appendBytes:data length:datalen];
                  //NSMutableString *dumphex = [NSMutableString stringWithCapacity:datalen];
                  //for (int i=0; i < datalen; i++) {
                  //    [dumphex appendFormat:@"%02x ", (unsigned char)data[i]];
                  //}
                  //NSLog(@"+vb: %@", dumphex);
              },
              ^(const char* data, int64_t datalen){
                  [adt appendBytes:data length:datalen];
              });
    self.activeH264stream = vdt;
    self.activeAACstream = adt;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        long offset = 0;
        while(offset >= 0 && offset < self.activeH264stream.length){
            offset = offset+[target receivedRawVideoFrame:(uint8_t *)self.activeH264stream.bytes+offset withSize:(uint32_t)(self.activeH264stream.length-offset)];
            offset = [target findNextNALUOffsetIn:(uint8_t *)self.activeH264stream.bytes withSize:(uint32_t)(self.activeH264stream.length) startAt:offset+3];
            NSLog(@"Next NALU at %lu", offset);
            [NSThread sleepForTimeInterval:0.001];
        }
    });
}
@end

