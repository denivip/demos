//
//  PBJMediaWriter.h
//  Vision
//
//  Created by Patrick Piemonte on 1/27/14.
//  Copyright (c) 2013-present, Patrick Piemonte, http://patrickpiemonte.com
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of
//  this software and associated documentation files (the "Software"), to deal in
//  the Software without restriction, including without limitation the rights to
//  use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
//  the Software, and to permit persons to whom the Software is furnished to do so,
//  subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
//  FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
//  COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
//  IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
//  CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "H264HwEncoderImpl.h"

typedef NS_ENUM(NSInteger, PBJInmemEncoding) {
    PBJInmemEncodingNone = 0,
    PBJInmemEncodingExclusive = 1
};

@protocol PBJMediaWriterDelegate;
@interface PBJMediaWriter : NSObject

- (id)initWithOutputURL:(NSURL *)outputURL format:(NSString*)format inmem:(PBJInmemEncoding)inmemEnc;

@property (nonatomic, weak) id<PBJMediaWriterDelegate, H264HwEncoderImplDelegate> delegate;

@property (nonatomic, readonly) NSURL *outputURL;
@property (nonatomic, readonly) NSError *error;

// configure settings before writing
@property (nonatomic, readonly, getter=isAudioReady) BOOL audioReady;
@property (nonatomic, readonly, getter=isVideoReady) BOOL videoReady;

- (BOOL)setupAudioWithSettings:(NSDictionary *)audioSettings;
- (BOOL)setupVideoWithSettings:(NSDictionary *)videoSettings;

// write methods, time durations
@property (nonatomic, readonly) CMTime audioTimestamp;
@property (nonatomic, readonly) CMTime videoTimestamp;

- (void)muteAudio:(BOOL)muteOrNot;
- (void)muteVideo:(BOOL)muteOrNot;
- (void)writeSampleBuffer:(CMSampleBufferRef)sampleBuffer withMediaTypeVideo:(BOOL)video;
- (void)finishWritingWithCompletionHandler:(void (^)(void))handler;
- (BOOL)canBeFinalized;
- (NSURL*)getOutputURL;
- (void)setDelegate:(id<PBJMediaWriterDelegate,H264HwEncoderImplDelegate>)delegate;
- (void)finalize;
- (NSDictionary*)videoEncodingSettings;
- (AudioStreamBasicDescription)audioEncodingSettings;
@end

@protocol PBJMediaWriterDelegate <NSObject>

@optional
// authorization status provides the opportunity to prompt the user for allowing capture device access
- (void)mediaWriterDidObserveAudioAuthorizationStatusDenied:(PBJMediaWriter *)mediaWriter;
- (void)mediaWriterDidObserveVideoAuthorizationStatusDenied:(PBJMediaWriter *)mediaWriter;

@end
