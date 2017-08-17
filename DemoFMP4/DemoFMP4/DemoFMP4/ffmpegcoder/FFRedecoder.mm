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
    NSLog(@"startCrunchingFiles %@", fileUrl);
    if(fileUrl == nil){
        return;
    }
    void* videobuf = nil;
    int64_t videobuf_len = 0;
    void* audiobuf = nil;
    int64_t audiobuf_len = 0;
    avDemuxTS([[fileUrl path] UTF8String],&videobuf,&videobuf_len,&audiobuf,&audiobuf_len);
}
@end

