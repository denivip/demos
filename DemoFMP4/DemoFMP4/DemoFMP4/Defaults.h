//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//
//

#ifndef DemoFMP4_Defaults_h
#define DemoFMP4_Defaults_h
#import <UIKit/UIDevice.h>
#import <MobileCoreServices/UTCoreTypes.h>

// raw chunk format. ts (video/mp2t) not supported out of the box
// iPad2 ios8: public.mpeg-4, public.3gpp, com.apple.coreaudio-format, com.apple.quicktime-movie, com.apple.m4a-audio, com.apple.m4v-video,
// org.3gpp.adaptive-multi-rate-audio, public.aiff-audio, com.microsoft.waveform-audio, public.aifc-audio
#define RAW_CHUNK_CONTAINER kUTTypeMPEG4
#define CAPTURE_ASPECT PBJOutputFormatStandard
#define kChunkedFileMinChunkLenSec 5.0
static int CHUNK_DURATION_SEC = 3;
static NSString* CACHE_RAWCHUNKS_PATH = @"rawchunks";

// Links
// https://mobisoftinfotech.com/resources/mguide/h264-encode-decode-using-videotoolbox/
// http://bento4.sourceforge.net/docs/html/index.html

// http://www.w3.org/2013/12/byte-stream-format-registry/isobmff-byte-stream-format.html
// https://wikileaks.org/sony/docs/05/docs/DECE/TWG/2014/CFFMediaFormat-1.2_140605.txt
// http://stackoverflow.com/questions/19974430/how-to-create-mfra-box-for-ismv-file-if-it-is-not-present

// Data and examples
// http://10.0.1.27:7000/index.mp4
// http://www.mediacollege.com/video/format/mpeg4/videofilename.mp4
// http://p.demo.flowplayer.netdna-cdn.com/vod/demo.flowplayer/bbb-800.mp4
// ffprobe -probesize 500000 -loglevel error -show_format -show_streams http://10.0.1.27:7000/index.mp4

// Replay
// https://stackoverflow.com/questions/29525000/how-to-use-videotoolbox-to-decompress-h-264-video-stream
// https://stackoverflow.com/questions/33245023/image-buffer-display-order-with-vtdecompressionsession
#endif
