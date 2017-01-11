#ifndef mstreamer_H264HwEncoderImpl_h
#define mstreamer_H264HwEncoderImpl_h

#define AP4_MUX_DEFAULT_VIDEO_FRAME_RATE 24
#define kSamplesPerFrame 1024
#define kAACFrequency 44100
#define kAACFrequencyAdtsId 4
#import <Foundation/Foundation.h>
#import "AppDelegate.h"

@import AVFoundation;
@protocol H264HwEncoderImplDelegate <NSObject>

@optional
- (void)inmemEncodeStart;
- (void)inmemEncodeStop;
- (void)inmemOnBeforeIframe:(double)pts;
- (void)inmemSpsPps:(NSData*)sps pps:(NSData*)pps;
- (void)inmemEncodedVideoData:(NSData*)data withPts:(double)pts isKeyFrame:(BOOL)isKeyFrame;
- (void)inmemEncodedAudioData:(NSData*)data withPts:(double)pts;
- (CVImageBufferRef)inmemOnBeforeEncodingVideoFrame:(CVImageBufferRef)imageBuffer frameSize:(CGSize)dims;
- (void)inmemOnAfterEncodingVideoFrame:(CVImageBufferRef)imageBuffer;
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
@property (strong) NSDictionary *audioSettingsMic;
@property (strong) NSDictionary *videoSettingsOut;
@property (assign) AudioStreamBasicDescription audioSettingsOut;
@end


#endif
