//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//


#ifndef DemoFMP4_FFRedecoder_h
#define DemoFMP4_FFRedecoder_h

@interface FFRedecoder : NSObject
- (void)addTSFiles2Play:(NSArray*)files;
- (void)startCrunchingFiles;
@end

#endif
