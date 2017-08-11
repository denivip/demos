//
//  PBJMediaWriter.m
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

#import "PBJMediaWriter.h"
#import "PBJVisionUtilities.h"

#import <UIKit/UIDevice.h>
#import <MobileCoreServices/UTCoreTypes.h>


#define LOG_WRITER 0
#if !defined(NDEBUG) && LOG_WRITER
#   define DLog(fmt, ...) NSLog((@"writer: " fmt), ##__VA_ARGS__);
#else
#   define DLog(...)
#endif

@interface PBJMediaWriter ()
{
    H264HwEncoderImpl *h264enc;
    AVAssetWriter *_assetWriter;
	AVAssetWriterInput *_assetWriterAudioInput;
	AVAssetWriterInput *_assetWriterVideoInput;
    
    NSURL *_outputURL;
    
    CMTime _audioTimestamp;
    CMTime _videoTimestamp;
    BOOL isAudioMuted;
    BOOL isVideoMuted;
    PBJInmemEncoding inmemEncoding;
}

@end

@implementation PBJMediaWriter

@synthesize delegate = _delegate;
@synthesize outputURL = _outputURL;
@synthesize audioTimestamp = _audioTimestamp;
@synthesize videoTimestamp = _videoTimestamp;

#pragma mark - getters/setters
- (NSURL*)getOutputURL
{
    return _outputURL;
}
- (BOOL)isAudioReady
{
    if(inmemEncoding == PBJInmemEncodingExclusive && h264enc.isActive == 0){
        return NO;
    }
    if(inmemEncoding != PBJInmemEncodingExclusive && _assetWriterAudioInput != nil){
        return YES;
    }
    AVAuthorizationStatus audioAuthorizationStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    BOOL isAudioNotAuthorized = (audioAuthorizationStatus == AVAuthorizationStatusNotDetermined || audioAuthorizationStatus == AVAuthorizationStatusDenied);
    BOOL isAudioSetup = !isAudioNotAuthorized;
    return isAudioSetup;
}

- (BOOL)isVideoReady
{
    if(inmemEncoding == PBJInmemEncodingExclusive && h264enc.isActive == 0){
        return NO;
    }
    if(inmemEncoding != PBJInmemEncodingExclusive && _assetWriterVideoInput != nil){
        return YES;
    }
    AVAuthorizationStatus videoAuthorizationStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    BOOL isVideoNotAuthorized = (videoAuthorizationStatus == AVAuthorizationStatusNotDetermined || videoAuthorizationStatus == AVAuthorizationStatusDenied);
    BOOL isVideoSetup = !isVideoNotAuthorized;
    return isVideoSetup;
}

- (NSError *)error
{
    return _assetWriter.error;
}

#pragma mark - init
- (id)initWithOutputURL:(NSURL *)outputURL format:(NSString*)format inmem:(PBJInmemEncoding)inmemEnc
{
    self = [super init];
    if (self) {
        inmemEncoding = inmemEnc;
        NSError *error = nil;
        if(format == nil){
            format = (NSString *)kUTTypeMPEG4;
        }
        if(inmemEncoding == PBJInmemEncodingExclusive){
            h264enc = [[H264HwEncoderImpl alloc] init];
        }else{
            _assetWriter = [AVAssetWriter assetWriterWithURL:outputURL fileType:format error:&error];
            if (error) {
                DLog(@"error setting up the asset writer (%@)", error);
                _assetWriter = nil;
                return nil;
            }
            _assetWriter.shouldOptimizeForNetworkUse = YES;
            _assetWriter.metadata = [self _metadataArray];
        }

        _outputURL = outputURL;
        _audioTimestamp = kCMTimeInvalid;
        _videoTimestamp = kCMTimeInvalid;

        // ensure authorization is permitted, if not already prompted
        // it's possible to capture video without audio or audio without video
        if ([[AVCaptureDevice class] respondsToSelector:@selector(authorizationStatusForMediaType:)]) {
            AVAuthorizationStatus audioAuthorizationStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
            if (audioAuthorizationStatus == AVAuthorizationStatusNotDetermined || audioAuthorizationStatus == AVAuthorizationStatusDenied) {
                if (audioAuthorizationStatus == AVAuthorizationStatusDenied && [_delegate respondsToSelector:@selector(mediaWriterDidObserveAudioAuthorizationStatusDenied:)]) {
                    [_delegate mediaWriterDidObserveAudioAuthorizationStatusDenied:self];
                }
            }
            
            AVAuthorizationStatus videoAuthorizationStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
            if (videoAuthorizationStatus == AVAuthorizationStatusNotDetermined || videoAuthorizationStatus == AVAuthorizationStatusDenied) {
                if (videoAuthorizationStatus == AVAuthorizationStatusDenied && [_delegate respondsToSelector:@selector(mediaWriterDidObserveVideoAuthorizationStatusDenied:)]) {
                    [_delegate mediaWriterDidObserveVideoAuthorizationStatusDenied:self];
                }
            }
        }
        //DLog(@"%@: prepared to write to (%@)", self, outputURL);
    }
    return self;
}

- (void)setDelegate:(id<PBJMediaWriterDelegate,H264HwEncoderImplDelegate>)delegate
{
    _delegate = delegate;
    h264enc.delegate = delegate;
}

#pragma mark - private

- (NSArray *)_metadataArray
{
    UIDevice *currentDevice = [UIDevice currentDevice];
    
    // device model
    AVMutableMetadataItem *modelItem = [[AVMutableMetadataItem alloc] init];
    [modelItem setKeySpace:AVMetadataKeySpaceCommon];
    [modelItem setKey:AVMetadataCommonKeyModel];
    [modelItem setValue:[currentDevice localizedModel]];

    // software
    AVMutableMetadataItem *softwareItem = [[AVMutableMetadataItem alloc] init];
    [softwareItem setKeySpace:AVMetadataKeySpaceCommon];
    [softwareItem setKey:AVMetadataCommonKeySoftware];
    [softwareItem setValue:@"PBJVision"];

    // creation date
    AVMutableMetadataItem *creationDateItem = [[AVMutableMetadataItem alloc] init];
    [creationDateItem setKeySpace:AVMetadataKeySpaceCommon];
    [creationDateItem setKey:AVMetadataCommonKeyCreationDate];
    [creationDateItem setValue:[NSString PBJformattedTimestampStringFromDate:[NSDate date]]];

    return @[modelItem, softwareItem, creationDateItem];
}

#pragma mark - setup

- (BOOL)setupAudioWithSettings:(NSDictionary *)audioSettings
{
    if(inmemEncoding == PBJInmemEncodingExclusive){
        h264enc.audioSettings = audioSettings;
        [h264enc setupEncoding];
        return YES;
    }
	if (!_assetWriterAudioInput && [_assetWriter canApplyOutputSettings:audioSettings forMediaType:AVMediaTypeAudio]) {
    
		_assetWriterAudioInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:audioSettings];
		_assetWriterAudioInput.expectsMediaDataInRealTime = YES;
        
		if (_assetWriterAudioInput && [_assetWriter canAddInput:_assetWriterAudioInput]) {
			[_assetWriter addInput:_assetWriterAudioInput];
		
            DLog(@"%@: setup audio input with settings sampleRate (%f) channels (%lu) bitRate (%ld)", self,
                [[audioSettings objectForKey:AVSampleRateKey] floatValue],
                (unsigned long)[[audioSettings objectForKey:AVNumberOfChannelsKey] unsignedIntegerValue],
                (long)[[audioSettings objectForKey:AVEncoderBitRateKey] integerValue]);
        
        } else {
			DLog(@"couldn't add asset writer audio input");
		}
        
	} else {
    
        _assetWriterAudioInput = nil;
		DLog(@"couldn't apply audio output settings");
	
    }
    
    return self.isAudioReady;
}

- (BOOL)setupVideoWithSettings:(NSDictionary *)videoSettings
{
    if(inmemEncoding == PBJInmemEncodingExclusive){
        h264enc.videoSettings = videoSettings;
        [h264enc setupEncoding];
        return YES;
    }
	if (!_assetWriterVideoInput && [_assetWriter canApplyOutputSettings:videoSettings forMediaType:AVMediaTypeVideo]) {
    
		_assetWriterVideoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
		_assetWriterVideoInput.expectsMediaDataInRealTime = YES;
		_assetWriterVideoInput.transform = CGAffineTransformIdentity;

		if (_assetWriterVideoInput && [_assetWriter canAddInput:_assetWriterVideoInput]) {
			[_assetWriter addInput:_assetWriterVideoInput];

#if !defined(NDEBUG) && LOG_WRITER
            NSDictionary *videoCompressionProperties = videoSettings[AVVideoCompressionPropertiesKey];
            if (videoCompressionProperties) {
                DLog(@"%@: setup video with compression settings bps (%f) frameInterval (%ld)", self,
                        [videoCompressionProperties[AVVideoAverageBitRateKey] floatValue],
                        (long)[videoCompressionProperties[AVVideoMaxKeyFrameIntervalKey] integerValue]);
            } else {
                DLog(@"setup video");
            }
#endif

		} else {
			DLog(@"couldn't add asset writer video input");
		}
        
	} else {
    
        _assetWriterVideoInput = nil;
		DLog(@"couldn't apply video output settings");
        
	}
    
    return self.isVideoReady;
}

- (void) muteAudioVideoInBuffer:(CMSampleBufferRef)sampleBuffer
{
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (CVPixelBufferLockBaseAddress(imageBuffer, 0) == kCVReturnSuccess){
        //http://10.0.1.14:7000/index.m3u8
        //videoSettings = @{ (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) };
        //videoSettings = @{ (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) };
        int planes = CVPixelBufferGetPlaneCount(imageBuffer);
        if(planes > 0){
            // http://stackoverflow.com/questions/4085474/how-to-get-the-y-component-from-cmsamplebuffer-resulted-from-the-avcapturesessio
            OSType pixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer);
            for(int i=0; i < planes; i++){
                Byte* baseAddress = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, i);
                size_t bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, i);
                size_t height = CVPixelBufferGetHeightOfPlane(imageBuffer, i);
                size_t totalBytes = bytesPerRow*height;
                if (pixelFormat == '420v' || pixelFormat == '420f') {
                    memset(baseAddress,i == 1?0x80:0x10,totalBytes);
//                    for(uint32_t j = 0; j < totalBytes-4; j += 4) {
//                        if(i == 1){
//                            // grayscale from green
//                            baseAddress[j+0] = 0x80;
//                            baseAddress[j+1] = 0x80;
//                            baseAddress[j+2] = 0x80;
//                            baseAddress[j+3] = 0x80;
//                        }else{
//                            baseAddress[j+0] = 0x10;
//                            baseAddress[j+1] = 0x10;
//                            baseAddress[j+2] = 0x10;
//                            baseAddress[j+3] = 0x10;
//                        }
//                    }
                }else{
                    //if (pixelFormat == '2vuy') {
                    memset(baseAddress,0,totalBytes);
                }
            }
        }else{
            Byte* baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
            // Get the number of bytes per row for the pixel buffer
            size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
            // Get the pixel buffer width and height
            //size_t width = CVPixelBufferGetWidth(imageBuffer);
            size_t height = CVPixelBufferGetHeight(imageBuffer);
            size_t totalBytes = bytesPerRow*height;
            memset(baseAddress,255,totalBytes);
            //for(uint32_t i = 0; i < totalBytes-4; i += 4) {
            //    baseAddress[i+0] = 0x00;
            //    baseAddress[i+1] = 0x00;
            //    baseAddress[i+2] = 0x00;
            //    baseAddress[i+3] = 0x00;
            //}
        }
        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
        return;
    }
    CMItemCount numSamples = CMSampleBufferGetNumSamples(sampleBuffer);
    if(numSamples == 0){
        return;
    }
    NSUInteger channelIndex = 0;
    CMBlockBufferRef audioBlockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t sampleSize = CMSampleBufferGetSampleSize(sampleBuffer, 0);//sizeof(SInt16)
    size_t audioBlockBufferOffset = (channelIndex * numSamples * sampleSize);
    size_t lengthAtOffset = 0;
    size_t totalLength = 0;
    Byte *samples = NULL;
    CMBlockBufferGetDataPointer(audioBlockBuffer, audioBlockBufferOffset, &lengthAtOffset, &totalLength, (char **)(&samples));
    memset(samples, 0, numSamples*sampleSize);
    //for (NSInteger i=0; i<numSamples; i++) {
    //    samples[i] = (SInt16)0;
    //}
    
}

- (void)muteVideo:(BOOL)muteOrNot {
    isVideoMuted = muteOrNot;
}

- (void)muteAudio:(BOOL)muteOrNot {
    isAudioMuted = muteOrNot;
}

#pragma mark - sample buffer writing
- (void)writeSampleBuffer:(CMSampleBufferRef)sampleBuffer withMediaTypeVideo:(BOOL)video
{
    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
        DLog("%@: skipping buffer, samples not ready", self);
        return;
    }

    if(inmemEncoding == PBJInmemEncodingExclusive){
        if(video){
            if(isVideoMuted){
                [self muteAudioVideoInBuffer:sampleBuffer];
            }
            [h264enc encodeVideo:sampleBuffer];
        }else{
            if(isAudioMuted){
                [self muteAudioVideoInBuffer:sampleBuffer];
            }
            // sampleBuffer contains encoded aac samples
            // AVFormatIDKey -> kAudioFormatMPEG4AAC
            [h264enc encodeAudio:sampleBuffer];
        }
        return;
    }
    
    // setup the writer
	if ( _assetWriter.status == AVAssetWriterStatusUnknown ) {
    
        if ([_assetWriter startWriting]) {
            CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
			[self initializeWriting:timestamp];
            DLog(@"%@: started writing with status (%ld)", self, (long)_assetWriter.status);
		} else {
			DLog(@"%@: error when starting to write (%@)", self, [_assetWriter error]);
            return;
		}
        
	}
    
    // check for completion state
    if ( _assetWriter.status == AVAssetWriterStatusFailed ) {
        DLog(@"writer failure, (%@)", _assetWriter.error.localizedDescription);
        return;
    }
    
    if (_assetWriter.status == AVAssetWriterStatusCancelled) {
        DLog(@"writer cancelled");
        return;
    }
    
    if ( _assetWriter.status == AVAssetWriterStatusCompleted) {
        DLog(@"writer finished and completed");
        return;
    }
	
    // perform write
	if ( _assetWriter.status == AVAssetWriterStatusWriting ) {

        CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        CMTime duration = CMSampleBufferGetDuration(sampleBuffer);
        if (duration.value > 0) {
            timestamp = CMTimeAdd(timestamp, duration);
        }
        
		if (video) {
            if(isVideoMuted){
                [self muteAudioVideoInBuffer:sampleBuffer];
            }
			if (_assetWriterVideoInput.readyForMoreMediaData) {
				if ([_assetWriterVideoInput appendSampleBuffer:sampleBuffer]) {
                    //DLog("%@: appendSampleBuffer ok", self);
                    _videoTimestamp = timestamp;
				} else {
					DLog(@"writer error appending video (%@)", [_assetWriter error]);
                }
            }
            else{
                DLog("%@: skipping buffer", self);
            }
		} else {
            if(isAudioMuted){
                [self muteAudioVideoInBuffer:sampleBuffer];
            }
			if (_assetWriterAudioInput.readyForMoreMediaData) {
				if ([_assetWriterAudioInput appendSampleBuffer:sampleBuffer]) {
                    _audioTimestamp = timestamp;
				} else {
					DLog(@"writer error appending audio (%@)", [_assetWriter error]);
                }
			}
		}
        
	}
}

- (void)initializeWriting:(CMTime)timestamp
{
    if(inmemEncoding == PBJInmemEncodingExclusive){
        return;
    }
    [_assetWriter startSessionAtSourceTime:timestamp];
}

- (void)finalize
{
    if(h264enc){
        [h264enc stopEncoding];
        h264enc = nil;
    }
}

- (void)finalizeWriting
{
    if(CMTIME_IS_INVALID(_videoTimestamp)){
        return;
    }
    if(inmemEncoding == PBJInmemEncodingExclusive){
        [h264enc stopEncoding];
        return;
    }
    [_assetWriter endSessionAtSourceTime:_videoTimestamp];
    return;
}

- (BOOL)canBeFinalized
{
    if(CMTIME_IS_INVALID(_videoTimestamp)){
        return NO;
    }
    return YES;
}

- (void)finishWritingWithCompletionHandler:(void (^)(void))handler
{
    DLog("%@: finalizing", self);
    if (_assetWriter && _assetWriter.status == AVAssetWriterStatusUnknown) {
        DLog(@"%@: asset writer is in an unknown state, wasn't recording", self);
        return;
    }
    if(inmemEncoding != PBJInmemEncodingExclusive && ![self canBeFinalized]){
        // Nothing to save
        DLog(@"%@: asset writer recorded nothing", self);
        return;
    }
    [self finalizeWriting];
    if(inmemEncoding == PBJInmemEncodingExclusive){
        handler();
        return;
    }
    [_assetWriter finishWritingWithCompletionHandler:handler];
}


@end
