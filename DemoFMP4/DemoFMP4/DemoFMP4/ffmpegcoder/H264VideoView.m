//
//  BebopVideoView.m
//  Arbieye-test2
//
//  Created by morishi on 2016/12/10.
//  Copyright © 2016年 morishi. All rights reserved.
//

#import "H264VideoView.h"
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>


@interface H264VideoView ()

@property (nonatomic, retain) AVSampleBufferDisplayLayer *videoLayer;
@property (nonatomic, assign) long spsSize;
@property (nonatomic, assign) long ppsSize;
@property (nonatomic, assign) CMVideoFormatDescriptionRef formatDesc;
@property (nonatomic, assign) BOOL canDisplayVideo;
@property (nonatomic, assign) BOOL lastDecodeHasFailed;

//@property (nonatomic, assign) VTDecompressionSessionRef decompressionSessionRef;
@end
@implementation H264VideoView

int curSta=0;

- (id)init {
    self = [super init];
    if (self) {
        [self customInit];
    }
    return self;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self customInit];
    }
    
    return self;
}

- (id)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self customInit];
    }
    return self;
}

- (void)customInit {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(enteredBackground:) name:UIApplicationDidEnterBackgroundNotification object: nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(enterForeground:) name:UIApplicationWillEnterForegroundNotification object: nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(decodingDidFail:) name:AVSampleBufferDisplayLayerFailedToDecodeNotification object:nil];
    
    _canDisplayVideo = YES;
    
    // create CVSampleBufferDisplayLayer and add it to the view
    _videoLayer = [[AVSampleBufferDisplayLayer alloc] init];
    _videoLayer.frame = self.frame;
    _videoLayer.bounds = self.bounds;
    _videoLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    _videoLayer.backgroundColor = [[UIColor blackColor] CGColor];
    //CMTimebaseRef controlTimebase;
    //CMTimebaseCreateWithMasterClock(CFAllocatorGetDefault(), CMClockGetHostTimeClock(), &controlTimebase);
    ////videoLayer.controlTimebase = controlTimebase;
    //CMTimebaseSetTime(self.videoLayer.controlTimebase, kCMTimeZero);
    //CMTimebaseSetRate(self.videoLayer.controlTimebase, 1.0);
    [[self layer] addSublayer:_videoLayer];
    [self setBackgroundColor:[UIColor blackColor]];
}

-(void)dealloc {
    if (NULL != _formatDesc) {
        CFRelease(_formatDesc);
        _formatDesc = NULL;
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name: UIApplicationDidEnterBackgroundNotification object: nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name: UIApplicationWillEnterForegroundNotification object: nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name: AVSampleBufferDisplayLayerFailedToDecodeNotification object: nil];
}

- (void)layoutSubviews {
    _videoLayer.frame = self.bounds;
}

/*
- (BOOL)configureDecoderWithSps:(NSData*)sps pps:(NSData*)pps {
    OSStatus osstatus;
    NSError *error = nil;
    BOOL success = NO;
    if (sps != nil && pps != nil) {
        _lastDecodeHasFailed = NO;
        if (_canDisplayVideo) {
            
            uint8_t* props[] = {
                (unsigned char*)sps.bytes+4,
                (unsigned char*)pps.bytes+4
            };
            
            size_t sizes[] = {
                sps.length-4,
                sps.length-4
            };
            
            if (NULL != _formatDesc) {
                CFRelease(_formatDesc);
                _formatDesc = NULL;
            }

            osstatus = CMVideoFormatDescriptionCreateFromH264ParameterSets(NULL, 2,
                                                                           (const uint8_t *const*)props,
                                                                           sizes, 4, &_formatDesc);
            
            if (osstatus != kCMBlockBufferNoErr) {
                error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                            code:osstatus
                                        userInfo:nil];
                
                NSLog(@"Error creating the format description = %@", [error description]);
                [self cleanFormatDesc];
            } else {
                //Video Decompression
                VTDecompressionOutputCallbackRecord callback;
                callback.decompressionOutputCallback = my_decompression_callback;
                callback.decompressionOutputRefCon = (__bridge void *)(self);
                VTDecompressionSessionCreate(NULL,
                                             _formatDesc,
                                             NULL,
                                             NULL,
                                             &callback,
                                             &_decompressionSessionRef);
                
                success = YES;
            }
        }
    }
    return success;
}

- (BOOL)displayFrame:(ARCONTROLLER_Frame_t *)frame
{
    BOOL success = !_lastDecodeHasFailed;

    if (success && _canDisplayVideo) {
        CMBlockBufferRef blockBufferRef = NULL;
        CMSampleTimingInfo timing = kCMTimingInfoInvalid;
        CMSampleBufferRef sampleBufferRef = NULL;
        
        OSStatus osstatus;
        NSError *error = nil;
        
        // on error, flush the video layer and wait for the next iFrame
        if (!_videoLayer || [_videoLayer status] == AVQueuedSampleBufferRenderingStatusFailed) {
            ARSAL_PRINT(ARSAL_PRINT_ERROR, "PilotingViewController", "Video layer status is failed : flush and wait for next iFrame");
            [self cleanFormatDesc];
            success = NO;
        }
        
        if (success) {
            osstatus  = CMBlockBufferCreateWithMemoryBlock(CFAllocatorGetDefault(), frame->data, frame->used, kCFAllocatorNull, NULL, 0, frame->used, 0, &blockBufferRef);
            if (osstatus != kCMBlockBufferNoErr) {
                error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                            code:osstatus
                                        userInfo:nil];
                
                NSLog(@"Error creating the block buffer = %@", [error description]);
                success = NO;
            }
        }

        if (success) {
            const size_t sampleSize = frame->used;
            osstatus = CMSampleBufferCreate(kCFAllocatorDefault, blockBufferRef, true, NULL, NULL, _formatDesc, 1, 0, NULL, 1, &sampleSize, &sampleBufferRef);
            if (osstatus != noErr) {
                success = NO;
                error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                            code:osstatus
                                        userInfo:nil];
                NSLog(@"Error creating the sample buffer = %@", [error description]);
            }
        }
        
        if (success) {
            // add the attachment which says that sample should be displayed immediately
            CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBufferRef, YES);
            CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
            CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
        }

 

        if (success &&
            [_videoLayer status] != AVQueuedSampleBufferRenderingStatusFailed &&
            _videoLayer.isReadyForMoreMediaData)
        
        {
            
            osstatus = VTDecompressionSessionDecodeFrame(_decompressionSessionRef,
                                                         sampleBufferRef,
                                                         kVTDecodeFrame_1xRealTimePlayback,
                                                         NULL,
                                                         NULL);
            dispatch_sync(dispatch_get_main_queue(), ^{
                if (_canDisplayVideo)
                {

                    [_videoLayer enqueueSampleBuffer:sampleBufferRef];
                }
            });
        }
        // free memory
        if (NULL != sampleBufferRef) {
            CMSampleBufferInvalidate(sampleBufferRef);
            CFRelease(sampleBufferRef);
            sampleBufferRef = NULL;
        }
        
        if (NULL != blockBufferRef) {
            CFRelease(blockBufferRef);
            blockBufferRef = NULL;
        }
    }
    return success;
}

void my_decompression_callback(void *decompressionOutputRefCon,
                               void *sourceFrameRefCon,
                               OSStatus status,
                               VTDecodeInfoFlags infoFlags,
                               CVImageBufferRef imageBuffer,
                               CMTime presentationTimeStamp,
                               CMTime presentationDuration)
{
    IplImage *iplimage = 0;
    if (imageBuffer) {
        CVPixelBufferLockBaseAddress(imageBuffer, 0);
        // get information of the image in the buffer
        uint8_t *bufferBaseAddress = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);
        size_t bufferWidth = CVPixelBufferGetWidth(imageBuffer);
        size_t bufferHeight = CVPixelBufferGetHeight(imageBuffer);
        
        // create IplImage
        if (bufferBaseAddress) {
            iplimage = cvCreateImage(cvSize(bufferWidth, bufferHeight), IPL_DEPTH_8U, 4);
            iplimage->imageData = (char*)bufferBaseAddress;
        }
   
        
        //=============iplImage to UIImage ===================
        CGColorSpaceRef colorSpace;
        colorSpace = CGColorSpaceCreateDeviceRGB();
        NSData *data = [NSData dataWithBytes:iplimage->imageData length:iplimage->imageSize];
        
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
        
        
        CGImageRef imageRef = CGImageCreate(iplimage->width,
                                            iplimage->height,
                                            iplimage->depth,
                                            iplimage->depth * iplimage->nChannels,
                                            iplimage->widthStep,
                                            colorSpace,
                                            kCGImageAlphaNone|kCGBitmapByteOrderDefault,
                                            provider,
                                            NULL,
                                            false,
                                            kCGRenderingIntentDefault
                                            );
        
        
        UIImage *outputImage = [UIImage imageWithCGImage:imageRef];
        
        
        CGImageRelease(imageRef);
        CGDataProviderRelease(provider);
        CGColorSpaceRelease(colorSpace);
        
        // =====================================================
        
    }

}


- (void)cleanFormatDesc {
    dispatch_sync(dispatch_get_main_queue(), ^{
        if (NULL != _formatDesc) {
            [_videoLayer flushAndRemoveImage];
            CFRelease(_formatDesc);
            _formatDesc = NULL;
        }
    });
}
*/


//=======
NSString * const naluTypesStrings[] =
{
    @"0: Unspecified (non-VCL)",
    @"1: Coded slice of a non-IDR picture (VCL)",    // P frame
    @"2: Coded slice data partition A (VCL)",
    @"3: Coded slice data partition B (VCL)",
    @"4: Coded slice data partition C (VCL)",
    @"5: Coded slice of an IDR picture (VCL)",      // I frame
    @"6: Supplemental enhancement information (SEI) (non-VCL)",
    @"7: Sequence parameter set (non-VCL)",         // SPS parameter
    @"8: Picture parameter set (non-VCL)",          // PPS parameter
    @"9: Access unit delimiter (non-VCL)",
    @"10: End of sequence (non-VCL)",
    @"11: End of stream (non-VCL)",
    @"12: Filler data (non-VCL)",
    @"13: Sequence parameter set extension (non-VCL)",
    @"14: Prefix NAL unit (non-VCL)",
    @"15: Subset sequence parameter set (non-VCL)",
    @"16: Reserved (non-VCL)",
    @"17: Reserved (non-VCL)",
    @"18: Reserved (non-VCL)",
    @"19: Coded slice of an auxiliary coded picture without partitioning (non-VCL)",
    @"20: Coded slice extension (non-VCL)",
    @"21: Coded slice extension for depth view components (non-VCL)",
    @"22: Reserved (non-VCL)",
    @"23: Reserved (non-VCL)",
    @"24: STAP-A Single-time aggregation packet (non-VCL)",
    @"25: STAP-B Single-time aggregation packet (non-VCL)",
    @"26: MTAP16 Multi-time aggregation packet (non-VCL)",
    @"27: MTAP24 Multi-time aggregation packet (non-VCL)",
    @"28: FU-A Fragmentation unit (non-VCL)",
    @"29: FU-B Fragmentation unit (non-VCL)",
    @"30: Unspecified (non-VCL)",
    @"31: Unspecified (non-VCL)",
};
//-(void) createDecompSession
//{
//    // make sure to destroy the old VTD session
//    _decompressionSessionRef = NULL;
//    VTDecompressionOutputCallbackRecord callBackRecord;
//    callBackRecord.decompressionOutputCallback = decompressionSessionDecodeFrameCallback;
//    
//    // this is necessary if you need to make calls to Objective C "self" from within in the callback method.
//    callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
//    
//    // you can set some desired attributes for the destination pixel buffer.  I didn't use this but you may
//    // if you need to set some attributes, be sure to uncomment the dictionary in VTDecompressionSessionCreate
//    //NSDictionary *destinationImageBufferAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
//    //                                                  [NSNumber numberWithBool:YES],
//    //                                                  (id)kCVPixelBufferOpenGLESCompatibilityKey,
//    //                                                  nil];
//    
//    OSStatus status =  VTDecompressionSessionCreate(NULL, _formatDesc, NULL,
//                                                    NULL, // (__bridge CFDictionaryRef)(destinationImageBufferAttributes)
//                                                    &callBackRecord, &_decompressionSessionRef);
//    NSLog(@"Video Decompression Session Create: \t %@", (status == noErr) ? @"successful!" : @"failed...");
//    if(status != noErr) NSLog(@"\t\t VTD ERROR type: %d", (int)status);
//}
//void decompressionSessionDecodeFrameCallback(void *decompressionOutputRefCon,
//                                             void *sourceFrameRefCon,
//                                             OSStatus status,
//                                             VTDecodeInfoFlags infoFlags,
//                                             CVImageBufferRef imageBuffer,
//                                             CMTime presentationTimeStamp,
//                                             CMTime presentationDuration)
//{
//    //THISCLASSNAME *streamManager = (__bridge THISCLASSNAME *)decompressionOutputRefCon;
//    if (status != noErr)
//    {
//        NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
//        NSLog(@"Decompressed error: %@", error);
//    }
//    else
//    {
//        NSLog(@"Decompressed sucessfully");
//        // do something with your resulting CVImageBufferRef that is your decompressed frame
//        //[streamManager displayDecodedFrame:imageBuffer];
//    }
//}
- (void) render:(CMSampleBufferRef)sampleBuffer
{
    //VTDecodeFrameFlags flags = kVTDecodeFrame_EnableAsynchronousDecompression;
    //VTDecodeInfoFlags flagOut;
    //NSDate* currentTime = [NSDate date];
    //VTDecompressionSessionDecodeFrame(_decompressionSessionRef, sampleBuffer, flags,
    //                                  (void*)CFBridgingRetain(currentTime), &flagOut);
    //CFRelease(sampleBuffer);
    // if you're using AVSampleBufferDisplayLayer, you only need to use this line of code
    [self.videoLayer enqueueSampleBuffer:sampleBuffer];
}

-(long)findNextNALUOffsetIn:(uint8_t *)frame withSize:(long)frameSize startAt:(long)offset
{
    // Can be "00 00 00 01" OR "00 00 01"
    uint32_t i = offset;
    while(i < frameSize-3){
        //if (frame[i] == 0x00 && frame[i+1] == 0x00 && frame[i+2] == 0x00 && frame[i+3] == 0x01){
        if (frame[i] == 0x00 && frame[i+1] == 0x00 && frame[i+2] == 0x00 && frame[i+3] == 0x01){
            return i;
        }
        if (frame[i] == 0x00 && frame[i+1] == 0x00 && frame[i+2] == 0x01){
            // All other code expects 4-bytes header for now
            return i-1;
        }
        i++;
    }
    return -1;
}

-(long)receivedRawVideoFrame:(uint8_t *)frame withSize:(long)frameSize
{
    OSStatus status = 0;
    
    uint8_t *data = NULL;
    uint8_t *pps = NULL;
    uint8_t *sps = NULL;
    
    long startCodeIndex = 0;
    long secondStartCodeIndex = 0;
    long thirdStartCodeIndex = 0;
    long blockLength = 0;
    long nextLookIndex = 0;
    
    CMSampleBufferRef sampleBuffer = NULL;
    CMBlockBufferRef blockBuffer = NULL;
    
    int nalu_type = (frame[startCodeIndex + 4] & 0x1F);
    if (nalu_type == 9){
        return NO;
    }
    NSLog(@"~~~~~~~ Received NALU Type \"%@\" ~~~~~~~~", naluTypesStrings[nalu_type]);
    // if we havent already set up our format description with our SPS PPS parameters, we
    // can't process any frames except type 7 that has our parameters
    if (nalu_type != 7 && _formatDesc == NULL)
    {
        NSLog(@"Video error: Frame is not an I Frame and format description is null");
        nextLookIndex = 3;
        return nextLookIndex;
    }
    
    // NALU type 7 is the SPS parameter NALU
    if (nalu_type == 7)
    {
        // find where the second PPS start code begins, (the 0x00 00 00 01 code)
        // from which we also get the length of the first SPS code
        secondStartCodeIndex = [self findNextNALUOffsetIn:frame withSize:frameSize startAt:startCodeIndex + 4];
        _spsSize = secondStartCodeIndex;
        //for (int i = startCodeIndex + 4; i < startCodeIndex + 40; i++)
        //{
        //    if (frame[i] == 0x00 && frame[i+1] == 0x00 && frame[i+2] == 0x00 && frame[i+3] == 0x01)
        //    {
        //        secondStartCodeIndex = i;
        //        _spsSize = secondStartCodeIndex;   // includes the header in the size
        //        break;
        //    }
        //}
        
        // find what the second NALU type is
        nalu_type = (frame[secondStartCodeIndex + 4] & 0x1F);
        nextLookIndex = secondStartCodeIndex + 4;
        NSLog(@"~~~~~~~ Received NALU Type \"%@\" ~~~~~~~~", naluTypesStrings[nalu_type]);
    }
    
    // type 8 is the PPS parameter NALU
    if(nalu_type == 8)
    {
        // find where the NALU after this one starts so we know how long the PPS parameter is
        thirdStartCodeIndex = [self findNextNALUOffsetIn:frame withSize:frameSize startAt:_spsSize + 4];
        _ppsSize = thirdStartCodeIndex - _spsSize;
        nextLookIndex = thirdStartCodeIndex + 4;
        //for (int i = _spsSize + 4; i < _spsSize + 40; i++)
        //{
        //    if (frame[i] == 0x00 && frame[i+1] == 0x00 && frame[i+2] == 0x00 && frame[i+3] == 0x01)
        //    {
        //        thirdStartCodeIndex = i;
        //        _ppsSize = thirdStartCodeIndex - _spsSize;
        //        break;
        //    }
        //}
        
        //if(_formatDesc == nil)
        {
            // allocate enough data to fit the SPS and PPS parameters into our data objects.
            // VTD doesn't want you to include the start code header (4 bytes long) so we add the - 4 here
            if(sps != nil){
                free(sps);
                sps = nil;
            }
            if(pps != nil){
                free(pps);
                pps = nil;
            }
            sps = malloc(_spsSize - 4);
            pps = malloc(_ppsSize - 4);
            
            // copy in the actual sps and pps values, again ignoring the 4 byte header
            memcpy (sps, &frame[4], _spsSize-4);
            memcpy (pps, &frame[_spsSize+4], _ppsSize-4);
            
            // now we set our H264 parameters
            uint8_t*  parameterSetPointers[2] = {sps, pps};
            size_t parameterSetSizes[2] = {_spsSize-4, _ppsSize-4};
            
            status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2,
                                                                         (const uint8_t *const*)parameterSetPointers,
                                                                         parameterSetSizes, 4,
                                                                         &_formatDesc);
            
            NSLog(@"\t\t Creation of CMVideoFormatDescription: %@", (status == noErr) ? @"successful!" : @"failed...");
            if(status != noErr) NSLog(@"\t\t Format Description ERROR type: %d", (int)status);
            
            // See if decomp session can convert from previous format description
            // to the new one, if not we need to remake the decomp session.
            // This snippet was not necessary for my applications but it could be for yours
            /*BOOL needNewDecompSession = (VTDecompressionSessionCanAcceptFormatDescription(_decompressionSession, _formatDesc) == NO);
             if(needNewDecompSession)
             {
             [self createDecompSession];
             }*/
        }
        // now lets handle the IDR frame that (should) come after the parameter sets
        // I say "should" because that's how I expect my H264 stream to work, YMMV
        nalu_type = (frame[thirdStartCodeIndex + 4] & 0x1F);
        NSLog(@"~~~~~~~ Received NALU Type \"%@\" ~~~~~~~~", naluTypesStrings[nalu_type]);
    }
    
    // create our VTDecompressionSession.  This isnt neccessary if you choose to use AVSampleBufferDisplayLayer
    //if((status == noErr) && (_decompressionSessionRef == NULL))
    //{
    //    [self createDecompSession];
    //}
    
    // type 5 is an IDR frame NALU.  The SPS and PPS NALUs should always be followed by an IDR (or IFrame) NALU, as far as I know
    if(nalu_type == 5)
    {
        // find the offset, or where the SPS and PPS NALUs end and the IDR frame NALU begins
        int offset = _spsSize + _ppsSize;
        blockLength = frameSize - offset;
        data = malloc(blockLength);
        data = memcpy(data, &frame[offset], blockLength);
        nextLookIndex = offset + 4;
        // replace the start code header on this NALU with its size.
        // AVCC format requires that you do this.
        // htonl converts the unsigned int from host to network byte order
        uint32_t dataLength32 = htonl(blockLength - 4);
        memcpy (data, &dataLength32, sizeof (uint32_t));
        
        // create a block buffer from the IDR NALU
        status = CMBlockBufferCreateWithMemoryBlock(NULL, data,  // memoryBlock to hold buffered data
                                                    blockLength,  // block length of the mem block in bytes.
                                                    kCFAllocatorNull, NULL,
                                                    0, // offsetToData
                                                    blockLength,   // dataLength of relevant bytes, starting at offsetToData
                                                    0, &blockBuffer);
        
        NSLog(@"\t\t BlockBufferCreation: \t %@", (status == kCMBlockBufferNoErr) ? @"successful!" : @"failed...");
    }
    
    // NALU type 1 is non-IDR (or PFrame) picture
    if (nalu_type == 1)
    {
        // non-IDR frames do not have an offset due to SPS and PSS, so the approach
        // is similar to the IDR frames just without the offset
        blockLength = frameSize;
        data = malloc(blockLength);
        data = memcpy(data, &frame[0], blockLength);
        nextLookIndex = 4;
         // again, replace the start header with the size of the NALU
        uint32_t dataLength32 = htonl (blockLength - 4);
        memcpy (data, &dataLength32, sizeof (uint32_t));
        
        status = CMBlockBufferCreateWithMemoryBlock(NULL, data,  // memoryBlock to hold data. If NULL, block will be alloc when needed
                                                    blockLength,  // overall length of the mem block in bytes
                                                    kCFAllocatorNull, NULL,
                                                    0,     // offsetToData
                                                    blockLength,  // dataLength of relevant data bytes, starting at offsetToData
                                                    0, &blockBuffer);

        NSLog(@"\t\t BlockBufferCreation: \t %@", (status == kCMBlockBufferNoErr) ? @"successful!" : @"failed...");
    }
    
    // now create our sample buffer from the block buffer,
    if(status == noErr)
    {
        // here I'm not bothering with any timing specifics since in my case we displayed all frames immediately
        const size_t sampleSize = blockLength;
        status = CMSampleBufferCreate(kCFAllocatorDefault,
                                      blockBuffer, true, NULL, NULL,
                                      _formatDesc, 1, 0, NULL, 1,
                                      &sampleSize, &sampleBuffer);
        
        NSLog(@"\t\t SampleBufferCreate: \t %@", (status == noErr) ? @"successful!" : @"failed...");
    }
    
    if(status == noErr)
    {
        // set some values of the sample buffer's attachments
        CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
        CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
        CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
        // either send the samplebuffer to a VTDecompressionSession or to an AVSampleBufferDisplayLayer
        [self render:sampleBuffer];
    }
    
    // free memory to avoid a memory leak
    // TBD: do the same for sps, pps and blockbuffer
    if (NULL != data)
    {
        free (data);
        data = NULL;
    }
    if(sps != nil){
        free(sps);
        sps = nil;
    }
    if(pps != nil){
        free(pps);
        pps = nil;
    }
    return nextLookIndex;
}



#pragma mark - notifications
- (void)enteredBackground:(NSNotification*)notification {
    _canDisplayVideo = NO;
}

- (void)enterForeground:(NSNotification*)notification {
    _canDisplayVideo = YES;
}

- (void)decodingDidFail:(NSNotification*)notification {
    _lastDecodeHasFailed = YES;
}

@end
