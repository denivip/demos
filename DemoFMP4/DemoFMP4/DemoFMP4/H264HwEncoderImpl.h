//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

#ifndef DemoFMP4_H264HwEncoderImpl_h
#define DemoFMP4_H264HwEncoderImpl_h


#import <Foundation/Foundation.h>
@import AVFoundation;
@protocol H264HwEncoderImplDelegate <NSObject>

@optional
- (void)inmemEncodeStart;
- (void)inmemEncodeStop;
- (id)inmemGetStateToken;
- (BOOL)inmemOnBeforeIFrame:(id)stateToken;
- (void)inmemSpsPps:(NSData*)spspps;
- (void)inmemEncodedVideoData:(NSData*)data isKeyFrame:(BOOL)isKeyFrame;
- (void)inmemEncodedAudioData:(NSData*)data;
@end
@interface H264HwEncoderImpl : NSObject

- (instancetype)init;
- (BOOL) setupEncoding;
- (void) encodeVideo:(CMSampleBufferRef)sampleBuffer;
- (void) encodeAudio:(CMSampleBufferRef)sampleBuffer;
- (void) stopEncoding;


@property (weak, nonatomic) NSString *error;
@property (weak, nonatomic) id<H264HwEncoderImplDelegate> delegate;
@property (assign) int isActive;
@property (strong) NSDictionary *audioSettings;
@property (strong) NSDictionary *videoSettings;
@end


#endif
