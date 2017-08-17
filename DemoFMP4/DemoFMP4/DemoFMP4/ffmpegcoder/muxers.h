//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

#ifndef DemoFMP4_tsmuxer_h
#define DemoFMP4_tsmuxer_h
#include <float.h>
#include <stdlib.h>

#define AP4_MUX_DEFAULT_VIDEO_FRAME_RATE 24
#define AP4_MUX_TIMESCALE 1000

#ifdef __cplusplus
extern "C" {
#endif

int avMuxH264AacMP4(const unsigned char* vbuff, int64_t vbuff_len,
                 const unsigned char* abuff, int64_t abuff_len,
                 void** moof_outbuff, int64_t* moof_outbuff_len);

int avMuxH264AacTS(const unsigned char* vbuff, int64_t vbuff_len,
                 const unsigned char* abuff, int64_t abuff_len,
                 void** moof_outbuff, int64_t* moof_outbuff_len);
int avDemuxTS(const char* ts_filepath, void** videobuf, int64_t* videobuf_len, void** audiobuf, int64_t* audiobuf_len);
#ifdef __cplusplus
}
#endif
#endif
