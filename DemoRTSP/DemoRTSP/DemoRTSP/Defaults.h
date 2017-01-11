//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

#ifndef DemoRTSP_Defaults_h
#define DemoRTSP_Defaults_h
#import <UIKit/UIDevice.h>
#import <MobileCoreServices/UTCoreTypes.h>

// raw chunk format. ts (video/mp2t) not supported out of the box
// iPad2 ios8: public.mpeg-4, public.3gpp, com.apple.coreaudio-format, com.apple.quicktime-movie, com.apple.m4a-audio, com.apple.m4v-video,
// org.3gpp.adaptive-multi-rate-audio, public.aiff-audio, com.microsoft.waveform-audio, public.aifc-audio
#define RAW_CHUNK_CONTAINER kUTTypeMPEG4
#define CAPTURE_ASPECT PBJOutputFormatStandard
#define CACHE_RAWCHUNKS_PATH @"rawchunks"
#define STREAM_TITLE @"test-stream"
#endif

