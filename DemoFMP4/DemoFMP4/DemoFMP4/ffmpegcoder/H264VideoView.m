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
@property (nonatomic, assign) BOOL canDisplayVideo;
@property (nonatomic, assign) BOOL lastDecodeHasFailed;

@property (nonatomic, strong) NSData* formatSps;
@property (nonatomic, strong) NSData* formatPps;
@property (nonatomic, assign) CMVideoFormatDescriptionRef formatDesc;
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
    [self setBackgroundColor:[UIColor blackColor]];
    [self setVideoLayer];
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

- (void)remVideoLayer {
    [_videoLayer removeFromSuperlayer];
    _videoLayer = nil;
}

- (void)setVideoLayer {
    // create CVSampleBufferDisplayLayer and add it to the view
    [self remVideoLayer];
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
}

- (void)layoutSubviews {
    _videoLayer.frame = self.bounds;
}


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

-(BOOL)waitingForMoreH264 {
    if(!self.videoLayer){
        return NO;
    }
    if(![self.videoLayer isReadyForMoreMediaData]){
        return NO;
    }
    return YES;
}

- (void)resetFeed {
    if(self.formatDesc != NULL){
        CFRelease(self.formatDesc);
    }
    self.formatDesc = nil;
    self.formatSps = nil;
    self.formatPps = nil;
}

-(long)findNextNALUOffsetIn:(uint8_t *)frame withSize:(long)frameSize startAt:(long)offset
{
    // Can be "00 00 00 01" OR "00 00 01"
    long i = offset;
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

-(BOOL)feedViewWithH264:(uint8_t *)frame withSize:(long)frameSize
{
    OSStatus status = 0;
   
    int nalu_type = (frame[4] & 0x1F);
    NSLog(@"~~~~~~~ Received NALU Type \"%@\" ~~~~~~~~", naluTypesStrings[nalu_type]);
    // NALU type 7 is the SPS parameter NALU
    if (nalu_type == 7)
    {
        // find where the second PPS start code begins, (the 0x00 00 00 01 code)
        // from which we also get the length of the first SPS code
        long nextNALU = [self findNextNALUOffsetIn:frame withSize:frameSize startAt:3];
        self.formatSps = [NSData dataWithBytes:frame length:nextNALU];
        return YES;
    }
    
    // type 8 is the PPS parameter NALU
    if(nalu_type == 8)
    {
        long nextNALU = [self findNextNALUOffsetIn:frame withSize:frameSize startAt:3];
        self.formatPps = [NSData dataWithBytes:frame length:nextNALU];
        
        if(self.formatDesc != nil){
            CFRelease(self.formatDesc);
            self.formatDesc = nil;
        }
            // VTD doesn't want you to include the start code header (4 bytes long) so we add the - 4 here
            // now we set our H264 parameters
            uint8_t*  parameterSetPointers[2] = {((uint8_t*)self.formatSps.bytes)+4, ((uint8_t*)self.formatPps.bytes)+4};
            size_t parameterSetSizes[2] = {self.formatSps.length-4, self.formatPps.length-4};
            
            status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2,
                                                                         (const uint8_t *const*)parameterSetPointers,
                                                                         parameterSetSizes, 4,
                                                                         &_formatDesc);
            
            if(status != noErr) {
                NSLog(@"\t\t Creation of CMVideoFormatDescription: %@", (status == noErr) ? @"successful!" : @"failed...");
                NSLog(@"\t\t Format Description ERROR type: %d", (int)status);
            }
            
            // See if decomp session can convert from previous format description
            // to the new one, if not we need to remake the decomp session.
            // This snippet was not necessary for my applications but it could be for yours
            //BOOL needNewDecompSession = (VTDecompressionSessionCanAcceptFormatDescription(_decompressionSession, _formatDesc) == NO);
            //if(needNewDecompSession || sess == nil)
            //{
            //[self createDecompSession];
            //}
        return YES;
    }
    
    // if we havent already set up our format description with our SPS PPS parameters, we
    // can't process any frames except type 7 that has our parameters
    if (_formatDesc == NULL)
    {
        NSLog(@"Video error: Frame is not an I Frame and format description is null");
        return NO;
    }
    
    uint8_t *data = NULL;
    long blockLength = 0;
    CMSampleBufferRef sampleBuffer = NULL;
    CMBlockBufferRef blockBuffer = NULL;
    BOOL canBeEnquened = NO;
    // type 5 is an IDR frame NALU
    // NALU type 1 is non-IDR (or PFrame) picture
    if (nalu_type == 1 || nalu_type == 5)
    {
        canBeEnquened = YES;
        // non-IDR frames do not have an offset due to SPS and PSS, so the approach
        // is similar to the IDR frames just without the offset
        blockLength = frameSize;
        data = malloc(blockLength);
        data = memcpy(data, &frame[0], blockLength);
         // again, replace the start header with the size of the NALU
        uint32_t dataLength32 = htonl (blockLength - 4);
        memcpy (data, &dataLength32, sizeof (uint32_t));
        status = CMBlockBufferCreateWithMemoryBlock(NULL, data,  // memoryBlock to hold data. If NULL, block will be alloc when needed
                                                    blockLength,  // overall length of the mem block in bytes
                                                    kCFAllocatorNull, NULL,
                                                    0,     // offsetToData
                                                    blockLength,  // dataLength of relevant data bytes, starting at offsetToData
                                                    0, &blockBuffer);
        if(status != kCMBlockBufferNoErr) {
            NSLog(@"\t\t BlockBufferCreation PFrame: \t %@", (status == kCMBlockBufferNoErr) ? @"successful!" : @"failed...");
        }
    }
    if(canBeEnquened){
        // now create our sample buffer from the block buffer,
        if(status == noErr)
        {
            // here I'm not bothering with any timing specifics since in my case we displayed all frames immediately
            const size_t sampleSize = blockLength;
            status = CMSampleBufferCreate(kCFAllocatorDefault,
                                          blockBuffer, true, NULL, NULL,
                                          _formatDesc, 1, 0, NULL, 1,
                                          &sampleSize, &sampleBuffer);
            if(status != noErr) {
                NSLog(@"\t\t SampleBufferCreate: \t %@", (status == noErr) ? @"successful!" : @"failed...");
            }
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
    }
    if(sampleBuffer != NULL){
        CFRelease(sampleBuffer);
    }
    if(blockBuffer != NULL){
        CFRelease(blockBuffer);
    }
    if (data != NULL)
    {
        free (data);
        data = NULL;
    }
    return YES;
}



#pragma mark - notifications
- (void)enteredBackground:(NSNotification*)notification {
    [self remVideoLayer];
    _canDisplayVideo = NO;
}

- (void)enterForeground:(NSNotification*)notification {
    _canDisplayVideo = YES;
    [self setVideoLayer];
}

- (void)decodingDidFail:(NSNotification*)notification {
    _lastDecodeHasFailed = YES;
}

@end
