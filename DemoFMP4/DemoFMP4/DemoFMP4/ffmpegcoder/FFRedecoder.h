//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//


#ifndef DemoFMP4_FFRedecoder_h
#define DemoFMP4_FFRedecoder_h
#import "H264VideoView.h"

@interface FFRedecoder : NSObject
@property (strong) NSData* activeH264stream;
@property (strong) NSData* activeAACstream;
- (void)addTSFiles2Play:(NSArray*)files;
- (void)startCrunchingFiles:(H264VideoView*)target;
@end

#endif
