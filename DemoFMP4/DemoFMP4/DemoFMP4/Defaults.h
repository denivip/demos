//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//
//

#ifndef DemoFMP4_Defaults_h
#define DemoFMP4_Defaults_h
#import <UIKit/UIDevice.h>
#import <MobileCoreServices/UTCoreTypes.h>

// Bonjour https://developer.apple.com/library/ios/documentation/Networking/Conceptual/NSNetServiceProgGuide/Articles/PublishingServices.html
// airplay - https://developer.apple.com/library/ios/documentation/NetworkingInternet/Conceptual/StreamingMediaGuide/UsingHTTPLiveStreaming/UsingHTTPLiveStreaming.html#//apple_ref/doc/uid/TP40008332-CH102-SW1
// m3u - https://developer.apple.com/library/ios/documentation/NetworkingInternet/Conceptual/StreamingMediaGuide/HTTPStreamingArchitecture/HTTPStreamingArchitecture.html#//apple_ref/doc/uid/TP40008332-CH101-SW2
// m3u - https://developer.apple.com/library/ios/technotes/tn2288/_index.html
// m3u switching, etc - https://developer.apple.com/library/ios/technotes/tn2224/_index.html
// interesting - https://code.google.com/p/upnpx/
// m3u tags - http://www.gpac-licensing.com/2014/12/08/apple-hls-technical-depth/

// http://blog.denivip.ru/index.php/2013/10/how-to-live-stream-video-as-you-shoot-it-in-ios/?lang=en
// http://blog.denivip.ru/index.php/2012/09/http-live-streaming-%D0%BB%D1%83%D1%87%D1%88%D0%B8%D0%B5-%D1%80%D0%B5%D1%86%D0%B5%D0%BF%D1%82%D1%8B/#more-3465
// mime: http://help.encoding.com/knowledge-base/article/correct-mime-types-for-serving-video-files/
// faq: https://developer.apple.com/library/ios/documentation/NetworkingInternet/Conceptual/StreamingMediaGuide/FrequentlyAskedQuestions/FrequentlyAskedQuestions.html



static int CHUNK_DURATION_SEC = 3;
static int CHUNKS_CACHE_MAX = 100;
static int CHUNKS_CACHE_CHECK = 10;
static int SERVER_WWWPORT = 7000;

static NSString* SERVER_BONJOURNAME = @"live stream";
static NSString* CACHE_RAWCHUNKS_PATH = @"rawchunks";

static NSString* FMP4_MIME = @"video/mp4";//@"video/ismv";
static NSString* FMP4_EXTENSION = @"mp4";//@"ismv";

// raw chunk format. ts (video/mp2t) not supported out of the box
// iPad2 ios8: public.mpeg-4, public.3gpp, com.apple.coreaudio-format, com.apple.quicktime-movie, com.apple.m4a-audio, com.apple.m4v-video,
// org.3gpp.adaptive-multi-rate-audio, public.aiff-audio, com.microsoft.waveform-audio, public.aifc-audio
#define RAW_CHUNK_CONTAINER kUTTypeMPEG4
#define CAPTURE_ASPECT PBJOutputFormatStandard

// streaming limits
#define kStreamFileReadBufferSize (128 * 1024)
#define kChunkedFileReadBufferSize (200 * 1024)
#define kChunkedFileWait4DataDelay 0.1
#define kChunkedFileMinChunkLenSec 2.0

// FFmpeg-IOS = http://sourceforge.net/projects/ffmpeg-ios/?source=typ_redirect
// FFmpeg-IOS = $(FFMPEG_PATH)/include/ FFMPEG_PATH=$(PROJECT_DIR)/../FFmpeg-IOS
// 900sec FFmpeg.build = $(FFMPEG_PATH)/include/$(CURRENT_ARCH) FFMPEG_PATH=$(PROJECT_DIR)/../FFmpeg.build
// mDNSResponder source http://www.opensource.apple.com/source/mDNSResponder/mDNSResponder-333.10/
// http://stackoverflow.com/questions/28716995/ios-mdns-service-with-non-standard-type
#endif
