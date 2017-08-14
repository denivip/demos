//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
// https://mobisoftinfotech.com/resources/mguide/h264-encode-decode-using-videotoolbox/

#import <Foundation/Foundation.h>
#import "H264HwEncoderImpl.h"
#include "muxers.h"

static const int kSamplesPerFrame = 1024;
static const int kAACFrequency = 44100;
static const int kAACFrequencyAdtsId = 4;
//static int inmemFlush = 0;


@import VideoToolbox;
@import AVFoundation;

@implementation H264HwEncoderImpl
{
    dispatch_queue_t aQueue;
    VTCompressionSessionRef vEncodingSession;
    AudioConverterRef aEncodingSession;
    AudioStreamBasicDescription descPCMFormat;
    AudioStreamBasicDescription descAACFormat;
    
    CMSampleTimingInfo* timingInfo;
    int frameCount;
    //NSData *sps;
    //NSData *pps;
}
@synthesize error;

- (instancetype)init
{
    if (self = [super init]) {
        vEncodingSession = nil;
        aEncodingSession = nil;
        aQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        frameCount = 0;
        //sps = NULL;
        //pps = NULL;
    }
    return self;
}


- (BOOL)setupEncoding
{
    if(self.audioSettings == nil || self.videoSettings == nil){
        return NO;
    }
    if(self.delegate == nil || self.isActive > 0){
        return NO;
    }
    dispatch_sync(aQueue, ^{
        OSStatus result = 0;
        
        // Audio compression
        int bitrate = [[self.audioSettings objectForKey:AVEncoderBitRateKey] intValue];//96000;
        int frequencyInHz = [[self.audioSettings objectForKey:AVSampleRateKey] intValue];
        int channels = [[self.audioSettings objectForKey:AVNumberOfChannelsKey] intValue];//2
        
        // descAACFormat.mSampleRate       = 32000;
        // descAACFormat.mChannelsPerFrame = 1;
        // descAACFormat.mBitsPerChannel   = 0;
        // descAACFormat.mBytesPerPacket   = 0;
        // descAACFormat.mFramesPerPacket  = 1024;
        // descAACFormat.mBytesPerFrame    = 0;
        // descAACFormat.mFormatID         = kAudioFormatMPEG4AAC;
        // descAACFormat.mFormatFlags      = 0;
        // AudioConverterNew(& descPCMFormat, & descAACFormat, &aEncodingSession);
        // UInt32 ulBitRate = 96000;
        // UInt32 ulSize = sizeof(ulBitRate);
        // AudioConverterSetProperty(aEncodingSession, kAudioConverterEncodeBitRate, ulSize, &ulBitRate);
        AudioStreamBasicDescription a_in = {0}, a_out = {0};
        // passing anything except 48000, 44100, and 22050 for mSampleRate results in "!dat"
        // OSStatus when querying for kAudioConverterPropertyMaximumOutputPacketSize property
        // below
        a_in.mSampleRate = frequencyInHz;
        // passing anything except 2 for mChannelsPerFrame results in "!dat" OSStatus when
        // querying for kAudioConverterPropertyMaximumOutputPacketSize property below
        a_in.mChannelsPerFrame = channels;
        a_in.mBitsPerChannel = 16;
        a_in.mFormatFlags =  kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
        a_in.mFormatID = kAudioFormatLinearPCM;// data from mic always in PCM
        a_in.mFramesPerPacket = 1;
        a_in.mBytesPerFrame = a_in.mBitsPerChannel * a_in.mChannelsPerFrame / 8;
        a_in.mBytesPerPacket = a_in.mFramesPerPacket * a_in.mBytesPerFrame;
        descPCMFormat = a_in;
        
        a_out.mFormatID = kAudioFormatMPEG4AAC;// AVFormatIDKey -> we need AAC
        a_out.mFormatFlags = 0;
        a_out.mFramesPerPacket = kSamplesPerFrame;
        a_out.mSampleRate = kAACFrequency;
        a_out.mChannelsPerFrame = a_in.mChannelsPerFrame;
        descAACFormat = a_out;
        
        UInt32 outputBitrate = bitrate;
        UInt32 propSize = sizeof(outputBitrate);
        UInt32 outputPacketSize = 0;
        
        const OSType subtype = kAudioFormatMPEG4AAC;
        AudioClassDescription requestedCodecs[2] = {
            {
                kAudioEncoderComponentType,
                subtype,
                kAppleSoftwareAudioCodecManufacturer
            },
            {
                kAudioEncoderComponentType,
                subtype,
                kAppleHardwareAudioCodecManufacturer
            }
        };
        result = AudioConverterNewSpecific(&descPCMFormat, &descAACFormat, 2, requestedCodecs, &aEncodingSession);
        if (result != noErr)
        {
            NSLog(@"H264: Unable to create a PCM->AAC session");
            error = @"H264: Unable to create a PCM->AAC session";
            return;
        }
        if(result == noErr) {
            result = AudioConverterSetProperty(aEncodingSession, kAudioConverterEncodeBitRate, propSize, &outputBitrate);
        }
        if(result == noErr) {
            result = AudioConverterGetProperty(aEncodingSession, kAudioConverterPropertyMaximumOutputPacketSize, &propSize, &outputPacketSize);
        }
        NSLog(@"H264: AudioConverterNewSpecific %d", (int)result);
        
        int ww = [[self.videoSettings objectForKey:AVVideoWidthKey] intValue];
        int hh = [[self.videoSettings objectForKey:AVVideoHeightKey] intValue];
        // video compression
        result = VTCompressionSessionCreate(NULL, ww, hh, kCMVideoCodecType_H264, NULL, NULL, NULL, NULL, NULL,  &vEncodingSession);// encodeVideo_didCompressH264  (__bridge void *)(self)
        if (result != noErr)
        {
            NSLog(@"H264: Unable to create a H264 session %d", result);
            error = @"H264: Unable to create a H264 session";
            return;
        }
        NSLog(@"H264: VTCompressionSessionCreate %d", (int)result);

        // Set the properties
        const int efr_v = AP4_MUX_DEFAULT_VIDEO_FRAME_RATE;
        CFNumberRef efr_ref = CFNumberCreate(NULL, kCFNumberSInt32Type, &efr_v);
        VTSessionSetProperty(vEncodingSession, kVTCompressionPropertyKey_ExpectedFrameRate, efr_ref);
        
        BOOL useBaseline = NO;
        CFStringRef pl_ref = useBaseline ? kVTProfileLevel_H264_Baseline_AutoLevel : kVTProfileLevel_H264_Main_AutoLevel;//kVTProfileLevel_H264_High_AutoLevel
        VTSessionSetProperty(vEncodingSession, kVTCompressionPropertyKey_ProfileLevel, pl_ref);
        if(!useBaseline) {
            VTSessionSetProperty(vEncodingSession, kVTCompressionPropertyKey_H264EntropyMode, kVTH264EntropyMode_CABAC);
        }
        VTSessionSetProperty(vEncodingSession , kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);
        VTSessionSetProperty(vEncodingSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
        
        
        const int mkf_v = AP4_MUX_DEFAULT_VIDEO_FRAME_RATE*2;
        CFNumberRef mkf_ref = CFNumberCreate(NULL, kCFNumberSInt32Type, &mkf_v);
        result = VTSessionSetProperty(vEncodingSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, mkf_ref);
        if (result != noErr){
            NSLog(@"H264: Unable to set kVTCompressionPropertyKey_MaxKeyFrameInterval %d", (int)result);
        }
        
        //const int mfd_v = 1;
        //CFNumberRef mfd_ref = CFNumberCreate(NULL, kCFNumberSInt32Type, &mfd_v);
        //result = VTSessionSetProperty(vEncodingSession, kVTCompressionPropertyKey_MaxFrameDelayCount, mfd_ref);
        //if (result != noErr){// -12900 https://stackoverflow.com/questions/29510311/how-to-set-maxh264slicebytes-property-of-vtcompressionsession
        //    NSLog(@"H264: Unable to set kVTCompressionPropertyKey_MaxFrameDelayCount %d", (int)result);
        //}

        // Tell the encoder to start encoding
        VTCompressionSessionPrepareToEncodeFrames(vEncodingSession);
        self.isActive++;
        [self.delegate inmemEncodeStart];
    });
    return YES;
}

BOOL isSampleBufferContainIFrame(CMSampleBufferRef sampleBuffer)
{
    BOOL isIFrame = NO;
    BOOL isDependendOnOther = NO;
    CFArrayRef attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, 0);
    if (CFArrayGetCount(attachmentsArray)) {
        CFBooleanRef notSync;
        CFDictionaryRef dict = CFArrayGetValueAtIndex(attachmentsArray, 0);
        BOOL keyExists = CFDictionaryGetValueIfPresent(dict,
                                                       kCMSampleAttachmentKey_NotSync,
                                                       (const void **)&notSync);
        // An I-Frame is a sync frame
        isIFrame = !keyExists || !CFBooleanGetValue(notSync);
        
        CFBooleanRef depOthers;
        keyExists = CFDictionaryGetValueIfPresent(dict,
                                                  kCMSampleAttachmentKey_DependsOnOthers,
                                                  (const void **)&depOthers);
        isDependendOnOther = keyExists && CFBooleanGetValue(depOthers);
    }
    //bool keyframe = !CFDictionaryContainsKey( (CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0)), kCMSampleAttachmentKey_NotSync);
    return isIFrame;
}

static int vchunkSamplesCount = 0;
void encodeVideo_didCompressH264(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags,
                     CMSampleBufferRef sampleBuffer, BOOL isIFrame)
{
    //if(inmemFlush>0){NSLog(@"encodeVideo_didCompressH264 - before");}
    if (status != 0 || !CMSampleBufferDataIsReady(sampleBuffer))
    {
        return;
    }
    //CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    //CMTime dts = CMSampleBufferGetDecodeTimeStamp(sampleBuffer);
    H264HwEncoderImpl* encoder = (__bridge H264HwEncoderImpl*)outputCallbackRefCon;
    
    // Check if we have got a key frame first
    if (isIFrame)
    {
//        CMFormatDescriptionRef vformat = CMSampleBufferGetFormatDescription(sampleBuffer);
//        size_t sparameterSetSize, sparameterSetCount;
//        const uint8_t *sparameterSet;
//        OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(vformat, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, 0 );
//        if (statusCode == noErr)
//        {
//            isSps = YES;
//            // Found sps and now check for pps
//            size_t pparameterSetSize, pparameterSetCount;
//            const uint8_t *pparameterSet;
//            OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(vformat, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, 0 );
//            if (statusCode == noErr)
//            {
//                isPps = YES;
//                // Found pps
//                encoder->sps = [NSData dataWithBytes:sparameterSet length:sparameterSetSize];
//                encoder->pps = [NSData dataWithBytes:pparameterSet length:pparameterSetSize];
//                if (encoder->_delegate)
//                {
//                    [encoder->_delegate inmemSpsPps:encoder->sps pps:encoder->pps];
//                }
//            }
//        }
        CMFormatDescriptionRef description = CMSampleBufferGetFormatDescription(sampleBuffer);
        size_t numberOfParameterSets;
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description,
                                                           0, NULL, NULL,
                                                           &numberOfParameterSets,
                                                           NULL);
        for (int i = 0; i < numberOfParameterSets; i++) {
            const uint8_t *parameterSetPointer;
            size_t parameterSetLength;
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description,
                                                               i,
                                                               &parameterSetPointer,
                                                               &parameterSetLength,
                                                               NULL, NULL);
            
            // Write the parameter set to the elementary stream
            NSData* spspps = [NSData dataWithBytes:parameterSetPointer length:parameterSetLength];
            [encoder->_delegate inmemSpsPps:spspps];
        }
    }
    size_t length, totalLength;
    size_t bufferOffset = 0;
    char *dataPointer;
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (statusCodeRet == noErr) {
        static const int AVCCHeaderLength = 4;
        while (bufferOffset < totalLength - AVCCHeaderLength) {
            // Read the NAL unit length
            uint32_t NALUnitLength = 0;
            memcpy(&NALUnitLength, dataPointer + bufferOffset, AVCCHeaderLength);
            
            // Convert the length value from Big-endian to Little-endian
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
            
            NSData* data = [[NSData alloc] initWithBytes:(dataPointer + bufferOffset + AVCCHeaderLength) length:NALUnitLength];
            [encoder->_delegate inmemEncodedVideoData:data isKeyFrame:isIFrame];
            
            // Move to the next NAL unit in the block buffer
            bufferOffset += AVCCHeaderLength + NALUnitLength;
            vchunkSamplesCount++;
        }
    }
    //NSLog(@"Frame: mixed %i %i %i, parsed %li of %li", isIFrame?1:0, isPps?1:0, isSps?1:0, bufferOffset, totalLength);
    //if(inmemFlush>0){NSLog(@"encodeVideo_didCompressH264 - after");}
}

OSStatus encodeAudio_inInputDataProc(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
{
    AudioBufferList audioBufferList = *(AudioBufferList *)inUserData;
    ioData->mBuffers[0].mData = audioBufferList.mBuffers[0].mData;
    ioData->mBuffers[0].mDataByteSize = audioBufferList.mBuffers[0].mDataByteSize;
    return  noErr;
}

- (NSData*)encodeAudio_adtsDataForPacketLength:(NSUInteger)packetLength {
    int adtsLength = 7;
    char *packet = malloc(sizeof(char) * adtsLength);
    // Variables Recycled by addADTStoPacket
    int profile = 2;  //AAC LC kAudioFormatMPEG4AAC
    //39=MediaCodecInfo.CodecProfileLevel.AACObjectELD;
    int freqIdx = kAACFrequencyAdtsId;//4 for 44.1KHz
    int chanCfg = 1;  //MPEG-4 Audio Channel Configuration. 1 Channel front-center
    NSUInteger fullLength = adtsLength + packetLength;
    // fill in ADTS data
    packet[0] = (char)0xFF;	// 11111111  	= syncword
    packet[1] = (char)0xF9;	// 1111 1 00 1  = syncword MPEG-2 Layer CRC
    packet[2] = (char)(((profile-1)<<6) + (freqIdx<<2) +(chanCfg>>2));
    packet[3] = (char)(((chanCfg&3)<<6) + (fullLength>>11));
    packet[4] = (char)((fullLength&0x7FF) >> 3);
    packet[5] = (char)(((fullLength&7)<<5) + 0x1F);
    packet[6] = (char)0xFC;
    NSData *data = [NSData dataWithBytesNoCopy:packet length:adtsLength freeWhenDone:YES];
    return data;
}

- (void) encodeAudio:(CMSampleBufferRef)sampleBuffer
{
    CFRetain(sampleBuffer);
    @weakify(self);
    dispatch_sync(aQueue, ^{
        @strongify(self);
        H264HwEncoderImpl* encoder = self;
        OSStatus statusCode = 0;
        AudioBufferList inAaudioBufferList;
        CMBlockBufferRef blockBuffer;
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, NULL, &inAaudioBufferList, sizeof(inAaudioBufferList), NULL, NULL, 0, &blockBuffer);
        
        uint32_t bufferSize = inAaudioBufferList.mBuffers[0].mDataByteSize;
        uint8_t *buffer = (uint8_t *)malloc(bufferSize);
        memset(buffer, 0, bufferSize);
        AudioBufferList outAudioBufferList;
        outAudioBufferList.mNumberBuffers = 1;
        outAudioBufferList.mBuffers[0].mNumberChannels = inAaudioBufferList.mBuffers[0].mNumberChannels;
        outAudioBufferList.mBuffers[0].mDataByteSize = bufferSize;
        outAudioBufferList.mBuffers[0].mData = buffer;
        
        UInt32 ioOutputDataPacketSize = 1;
        
        statusCode = AudioConverterFillComplexBuffer(aEncodingSession, encodeAudio_inInputDataProc, &inAaudioBufferList, &ioOutputDataPacketSize, &outAudioBufferList, NULL);
        if (statusCode != noErr) {
            NSLog(@"H264: AudioConverterFillComplexBuffer failed with %d", (int)statusCode);
            error = @"H264: AudioConverterFillComplexBuffer failed";
        }else{
            //CMTime audioChunkPts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
            //NSLog(@"H264: encodeAudio pts %f", CMTimeGetSeconds(audioChunkPts));
            
            NSData *rawAAC = [NSData dataWithBytes:outAudioBufferList.mBuffers[0].mData length:outAudioBufferList.mBuffers[0].mDataByteSize];
            NSData *adtsHeader = [self encodeAudio_adtsDataForPacketLength:rawAAC.length];
            NSMutableData *fullData = [NSMutableData dataWithData:adtsHeader];
            [fullData appendData:rawAAC];
            [encoder->_delegate inmemEncodedAudioData:fullData];
        }
        free(buffer);
        CFRelease(blockBuffer);
        CFRelease(sampleBuffer);
    });
}

- (void) encodeVideo:(CMSampleBufferRef)sampleBuffer
{
    if(vEncodingSession == nil){
        return;
    }
    CFRetain(sampleBuffer);
    dispatch_sync(aQueue, ^{
        frameCount++;
        // Get the CV Image buffer
        CVImageBufferRef imageBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
        // Create properties
        CMTime presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);//CMTimeMake(frameCount, 1000);
        CMTime chunkDuration = kCMTimeInvalid;
        static CFTimeInterval tsLast = -1;
        CFTimeInterval ts = CACurrentMediaTime();
        if(tsLast > 0){
            chunkDuration = CMTimeMakeWithSeconds(ts-tsLast, 1000);
        }
        tsLast = ts;
        id delegateStateToken = nil;
        if(self->_delegate)
        {
            delegateStateToken = [self->_delegate inmemGetStateToken];
        }
        
        NSDictionary *properties = @{(__bridge NSString *)kVTEncodeFrameOptionKey_ForceKeyFrame: @YES};// TEST
        VTEncodeInfoFlags flags;
        OSStatus statusCode = VTCompressionSessionEncodeFrameWithOutputHandler(vEncodingSession, imageBuffer,
                                                              presentationTimeStamp, chunkDuration, (__bridge CFDictionaryRef)properties, &flags,
                                                                ^(OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer ){
                                                                    //CMTime videoChunkPts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
                                                                    //NSLog(@"H264: encodeVideo vchunkSamplesCount: %i pts %f", vchunkSamplesCount, CMTimeGetSeconds(videoChunkPts));
                                                                    BOOL isIFrame = isSampleBufferContainIFrame(sampleBuffer);
                                                                    if (isIFrame && self->_delegate)
                                                                    {
                                                                        // Flushing current buffers if needed
                                                                        if([self->_delegate inmemOnBeforeIFrame:delegateStateToken]){
                                                                            NSLog(@"Flushing, current vchunkSamplesCount: %i", vchunkSamplesCount);
                                                                            vchunkSamplesCount = 0;
                                                                        }
                                                                    }
                                                                    encodeVideo_didCompressH264( (__bridge void *)(self), nil, status, infoFlags, sampleBuffer, isIFrame);
                                                                });
        // Check for error
        if (statusCode != noErr) {
            NSLog(@"H264: VTCompressionSessionEncodeFrame failed with %d", (int)statusCode);
            error = @"H264: VTCompressionSessionEncodeFrame failed";
            
            // End the session
            VTCompressionSessionInvalidate(vEncodingSession);
            CFRelease(vEncodingSession);
            vEncodingSession = NULL;
            error = NULL;
            return;
        }
        CFRelease(sampleBuffer);
        OSStatus result = VTCompressionSessionCompleteFrames(vEncodingSession, kCMTimeIndefinite);
        if (result != noErr) {
            NSLog(@"H264: VTCompressionSessionCompleteFrames failed with %d", (int)result);
            error = @"H264: VTCompressionSessionCompleteFrames failed";
            
            // End the session
            VTCompressionSessionInvalidate(vEncodingSession);
            CFRelease(vEncodingSession);
            vEncodingSession = NULL;
            error = NULL;
            return;
        }
        //NSLog(@"H264: VTCompressionSessionEncodeFrame Success");
    });
    
    
}

- (void)stopEncoding
{
    AudioConverterDispose(aEncodingSession);
    aEncodingSession = nil;
    
    // Mark the completion
    VTCompressionSessionCompleteFrames(vEncodingSession, kCMTimeInvalid);
    
    // End the session
    VTCompressionSessionInvalidate(vEncodingSession);
    CFRelease(vEncodingSession);
    vEncodingSession = NULL;
    error = NULL;
    self.isActive = 0;
    [self.delegate inmemEncodeStop];
    
}

@end
