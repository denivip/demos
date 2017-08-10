//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

// http://bento4.sourceforge.net/docs/html/index.html
// https://github.com/axiomatic-systems/Bento4/blob/master/Source/C%2B%2B/Apps/Mp42Hls/Mp42Hls.cpp
// https://github.com/axiomatic-systems/Bento4/blob/master/Source/C%2B%2B/Apps/Mp42Ts/Mp42Ts.cpp


#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "Ap4.h"
#include "muxers.h"
struct SampleOrder {
    SampleOrder(AP4_UI32 decode_order, AP4_UI32 display_order) :
    m_DecodeOrder(decode_order),
    m_DisplayOrder(display_order) {}
    AP4_UI32 m_DecodeOrder;
    AP4_UI32 m_DisplayOrder;
};

static void
SortSamples(SampleOrder* array, unsigned int n)
{
    if (n < 2) {
        return;
    }
    SampleOrder pivot = array[n / 2];
    SampleOrder* left  = array;
    SampleOrder* right = array + n - 1;
    while (left <= right) {
        if (left->m_DisplayOrder < pivot.m_DisplayOrder) {
            ++left;
            continue;
        }
        if (right->m_DisplayOrder > pivot.m_DisplayOrder) {
            --right;
            continue;
        }
        SampleOrder temp = *left;
        *left++ = *right;
        *right-- = temp;
    }
    SortSamples(array, (unsigned int)(right - array + 1));
    SortSamples(left, (unsigned int)(array + n - left));
}

/*----------------------------------------------------------------------
 |   AddAacTrack
 +---------------------------------------------------------------------*/
static AP4_Track*
AddAacTrack(AP4_Movie*            movie,
            const AP4_UI08* buffer, AP4_Size size,
            //SampleFileStorage&    sample_storage)
            AP4_MemoryByteStream& sample_storage)
{
    AP4_Result result;
    AP4_ByteStream* input = new AP4_MemoryByteStream(buffer, size);
    
    // create a sample table
    AP4_SyntheticSampleTable* sample_table = new AP4_SyntheticSampleTable();
    
    // create an ADTS parser
    AP4_AdtsParser parser;
    bool           initialized = false;
    unsigned int   sample_description_index = 0;
    
    // read from the input, feed, and get AAC frames
    AP4_UI32     sample_rate = 0;
    AP4_Cardinal sample_count = 0;
    bool eos = false;
    for(;;) {
        // try to get a frame
        AP4_AacFrame frame;
        result = parser.FindFrame(frame);
        if (AP4_SUCCEEDED(result)) {
                //printf("AAC frame [%06d]: size = %d, %d kHz, %d ch\n",
                //       sample_count,
                //       frame.m_Info.m_FrameLength,
                //       (int)frame.m_Info.m_SamplingFrequency,
                //       frame.m_Info.m_ChannelConfiguration);

            if (!initialized) {
                initialized = true;
                
                // create a sample description for our samples
                AP4_DataBuffer dsi;
                unsigned char aac_dsi[2];
                
                unsigned int object_type = 2; // AAC LC by default
                aac_dsi[0] = (object_type<<3) | (frame.m_Info.m_SamplingFrequencyIndex>>1);
                aac_dsi[1] = ((frame.m_Info.m_SamplingFrequencyIndex&1)<<7) | (frame.m_Info.m_ChannelConfiguration<<3);
                
                dsi.SetData(aac_dsi, 2);
                AP4_MpegAudioSampleDescription* sample_description =
                new AP4_MpegAudioSampleDescription(
                                                   AP4_OTI_MPEG4_AUDIO,   // object type
                                                   (AP4_UI32)frame.m_Info.m_SamplingFrequency,
                                                   16,                    // sample size
                                                   frame.m_Info.m_ChannelConfiguration,
                                                   &dsi,                  // decoder info
                                                   6144,                  // buffer size
                                                   128000,                // max bitrate
                                                   128000);               // average bitrate
                sample_description_index = sample_table->GetSampleDescriptionCount();
                sample_table->AddSampleDescription(sample_description);
                sample_rate = (AP4_UI32)frame.m_Info.m_SamplingFrequency;
            }
            
            // read and store the sample data
            AP4_Position position = 0;
            sample_storage.Tell(position);
            AP4_DataBuffer sample_data(frame.m_Info.m_FrameLength);
            sample_data.SetDataSize(frame.m_Info.m_FrameLength);
            frame.m_Source->ReadBytes(sample_data.UseData(), frame.m_Info.m_FrameLength);
            sample_storage.Write(sample_data.GetData(), frame.m_Info.m_FrameLength);
            
            // add the sample to the table
            sample_table->AddSample(sample_storage, position, frame.m_Info.m_FrameLength, 1024, sample_description_index, 0, 0, true);
            sample_count++;
        } else {
            if (eos) break;
        }
        
        // read some data and feed the parser
        AP4_UI08 input_buffer[4096];
        AP4_Size to_read = parser.GetBytesFree();
        if (to_read) {
            AP4_Size bytes_read = 0;
            if (to_read > sizeof(input_buffer)) to_read = sizeof(input_buffer);
            result = input->ReadPartial(input_buffer, to_read, bytes_read);
            if (AP4_SUCCEEDED(result)) {
                AP4_Size to_feed = bytes_read;
                result = parser.Feed(input_buffer, &to_feed);
                if (AP4_FAILED(result)) {
                    fprintf(stderr, "ERROR: parser.Feed() failed (%d)\n", result);
                    return NULL;
                }
            } else {
                if (result == AP4_ERROR_EOS) {
                    eos = true;
                    parser.Feed(NULL, NULL, AP4_BITSTREAM_FLAG_EOS);
                }
            }
        }
    }
    
    // create an audio track
    AP4_Track* track = new AP4_Track(AP4_Track::TYPE_AUDIO,
                                     sample_table,
                                     1,                 // track id
                                     sample_rate,       // movie time scale
                                     sample_count*1024, // track duration
                                     sample_rate,       // media time scale
                                     sample_count*1024, // media duration
                                     "en",             // language
                                     0, 0);             // width, height
    
    if(movie != NULL){
        movie->AddTrack(track);
    }
    // cleanup
    input->Release();
    return track;
}

/*----------------------------------------------------------------------
 |   AddH264Track
 +---------------------------------------------------------------------*/
static AP4_Track*
AddH264Track(AP4_Movie*            movie,
             const AP4_UI08* buffer, AP4_Size size,
             AP4_Array<AP4_UI32>&  brands,
             //SampleFileStorage&    sample_storage
             AP4_MemoryByteStream& sample_storage)
{
    AP4_Result result;
    AP4_ByteStream* input = new AP4_MemoryByteStream(buffer, size);
    
    // see if the frame rate is specified
    unsigned int video_frame_rate = AP4_MUX_DEFAULT_VIDEO_FRAME_RATE*1000;

    // create a sample table
    AP4_SyntheticSampleTable* sample_table = new AP4_SyntheticSampleTable();
    
    // allocate an array to keep track of sample order
    AP4_Array<SampleOrder> sample_orders;
    
    // parse the input
    AP4_AvcFrameParser parser;
    for (;;) {
        bool eos;
        unsigned char input_buffer[4096];
        AP4_Size bytes_in_buffer = 0;
        result = input->ReadPartial(input_buffer, sizeof(input_buffer), bytes_in_buffer);
        if (AP4_SUCCEEDED(result)) {
            eos = false;
        } else if (result == AP4_ERROR_EOS) {
            eos = true;
        } else {
            fprintf(stderr, "ERROR: failed to read from input file\n");
            break;
        }
        AP4_Size offset = 0;
        bool     found_access_unit = false;
        do {
            AP4_AvcFrameParser::AccessUnitInfo access_unit_info;
            
            found_access_unit = false;
            AP4_Size bytes_consumed = 0;
            result = parser.Feed(&input_buffer[offset],
                                 bytes_in_buffer,
                                 bytes_consumed,
                                 access_unit_info,
                                 eos);
            if (AP4_FAILED(result)) {
                fprintf(stderr, "ERROR: Feed() failed (%d)\n", result);
                break;
            }
            if (access_unit_info.nal_units.ItemCount()) {
                // we got one access unit
                found_access_unit = true;
                //printf("H264 Access Unit, %d NAL units, decode_order=%d, display_order=%d\n",
                //           access_unit_info.nal_units.ItemCount(),
                //           access_unit_info.decode_order,
                //           access_unit_info.display_order);
                
                // compute the total size of the sample data
                unsigned int sample_data_size = 0;
                for (unsigned int i=0; i<access_unit_info.nal_units.ItemCount(); i++) {
                    sample_data_size += 4+access_unit_info.nal_units[i]->GetDataSize();
                }
                
                // store the sample data
                AP4_Position position = 0;
                sample_storage.Tell(position);
                for (unsigned int i=0; i<access_unit_info.nal_units.ItemCount(); i++) {
                    sample_storage.WriteUI32(access_unit_info.nal_units[i]->GetDataSize());
                    sample_storage.Write(access_unit_info.nal_units[i]->GetData(), access_unit_info.nal_units[i]->GetDataSize());
                }
                
                // add the sample to the track
                sample_table->AddSample(sample_storage, position, sample_data_size, 1000, 0, 0, 0, access_unit_info.is_idr);
                
                // remember the sample order
                sample_orders.Append(SampleOrder(access_unit_info.decode_order, access_unit_info.display_order));
                
                // free the memory buffers
                access_unit_info.Reset();
            }
            
            offset += bytes_consumed;
            bytes_in_buffer -= bytes_consumed;
        } while (bytes_in_buffer || found_access_unit);
        if (eos) break;
    }
    
    // adjust the sample CTS/DTS offsets based on the sample orders
    if (sample_orders.ItemCount() > 1) {
        unsigned int start = 0;
        for (unsigned int i=1; i<=sample_orders.ItemCount(); i++) {
            if (i == sample_orders.ItemCount() || sample_orders[i].m_DisplayOrder == 0) {
                // we got to the end of the GOP, sort it by display order
                SortSamples(&sample_orders[start], i-start);
                start = i;
            }
        }
    }
    unsigned int max_delta = 0;
    for (unsigned int i=0; i<sample_orders.ItemCount(); i++) {
        if (sample_orders[i].m_DecodeOrder > i) {
            unsigned int delta =sample_orders[i].m_DecodeOrder-i;
            if (delta > max_delta) {
                max_delta = delta;
            }
        }
    }
    for (unsigned int i=0; i<sample_orders.ItemCount(); i++) {
        sample_table->UseSample(sample_orders[i].m_DecodeOrder).SetCts(1000ULL*(AP4_UI64)(i+max_delta));
    }
    
    // check the video parameters
    AP4_AvcSequenceParameterSet* sps = NULL;
    for (unsigned int i=0; i<=AP4_AVC_SPS_MAX_ID; i++) {
        if (parser.GetSequenceParameterSets()[i]) {
            sps = parser.GetSequenceParameterSets()[i];
            break;
        }
    }
    if (sps == NULL) {
        fprintf(stderr, "ERROR: no sequence parameter set found in video\n");
        input->Release();
        return NULL;
    }
    unsigned int video_width = 0;
    unsigned int video_height = 0;
    sps->GetInfo(video_width, video_height);
    
    // collect the SPS and PPS into arrays
    AP4_Array<AP4_DataBuffer> sps_array;
    for (unsigned int i=0; i<=AP4_AVC_SPS_MAX_ID; i++) {
        if (parser.GetSequenceParameterSets()[i]) {
            sps_array.Append(parser.GetSequenceParameterSets()[i]->raw_bytes);
        }
    }
    AP4_Array<AP4_DataBuffer> pps_array;
    for (unsigned int i=0; i<=AP4_AVC_PPS_MAX_ID; i++) {
        if (parser.GetPictureParameterSets()[i]) {
            pps_array.Append(parser.GetPictureParameterSets()[i]->raw_bytes);
        }
    }
    
    // setup the video the sample descripton
    AP4_AvcSampleDescription* sample_description =
    new AP4_AvcSampleDescription(AP4_SAMPLE_FORMAT_AVC1,
                                 video_width,
                                 video_height,
                                 24,
                                 "h264",
                                 sps->profile_idc,
                                 sps->level_idc,
                                 sps->constraint_set0_flag<<7 |
                                 sps->constraint_set1_flag<<6 |
                                 sps->constraint_set2_flag<<5 |
                                 sps->constraint_set3_flag<<4,
                                 4,
                                 sps_array,
                                 pps_array);
    sample_table->AddSampleDescription(sample_description);
    
    AP4_UI32 movie_timescale      = AP4_MUX_TIMESCALE;
    AP4_UI32 media_timescale      = video_frame_rate;
    AP4_UI64 video_track_duration = AP4_ConvertTime(1000*sample_table->GetSampleCount(), media_timescale, movie_timescale);
    AP4_UI64 video_media_duration = 1000*sample_table->GetSampleCount();
    
    // create a video track
    AP4_Track* track = new AP4_Track(AP4_Track::TYPE_VIDEO,
                                     sample_table,
                                     2,                    // auto-select track id
                                     movie_timescale,      // movie time scale
                                     video_track_duration, // track duration
                                     video_frame_rate,     // media time scale
                                     video_media_duration, // media duration
                                     "en",                // language
                                     video_width<<16,      // width
                                     video_height<<16      // height
                                     );
    
    // update the brands list
    brands.Append(AP4_FILE_BRAND_AVC1);
    if(movie != NULL){
        movie->AddTrack(track);
    }
    // cleanup
    input->Release();
    return track;
}


/*----------------------------------------------------------------------
 |   SampleReader
 +---------------------------------------------------------------------*/
class SampleReader
{
public:
    virtual ~SampleReader() {}
    virtual AP4_Result ReadSample(AP4_Sample& sample, AP4_DataBuffer& sample_data) = 0;
};

/*----------------------------------------------------------------------
 |   TrackSampleReader
 +---------------------------------------------------------------------*/
class TrackSampleReader : public SampleReader
{
public:
    TrackSampleReader(AP4_Track& track) : m_Track(track), m_SampleIndex(0) {}
    AP4_Result ReadSample(AP4_Sample& sample, AP4_DataBuffer& sample_data);
    
private:
    AP4_Track&  m_Track;
    AP4_Ordinal m_SampleIndex;
};

/*----------------------------------------------------------------------
 |   TrackSampleReader
 +---------------------------------------------------------------------*/
AP4_Result
TrackSampleReader::ReadSample(AP4_Sample& sample, AP4_DataBuffer& sample_data)
{
    if (m_SampleIndex >= m_Track.GetSampleCount()) return AP4_ERROR_EOS;
    return m_Track.ReadSample(m_SampleIndex++, sample, sample_data);
}

/*----------------------------------------------------------------------
 |   ReadSample
 +---------------------------------------------------------------------*/
static AP4_Result
ReadSample(SampleReader&   reader,
           AP4_Track&      track,
           AP4_Sample&     sample,
           AP4_DataBuffer& sample_data,
           double&         ts,
           bool&           eos)
{
    AP4_Result result = reader.ReadSample(sample, sample_data);
    if (AP4_FAILED(result)) {
        if (result == AP4_ERROR_EOS) {
            eos = true;
        } else {
            return result;
        }
    }
    ts = (double)sample.GetDts()/(double)track.GetMediaTimeScale();
    
    return AP4_SUCCESS;
}

/*----------------------------------------------------------------------
 |   WriteSamples
 +---------------------------------------------------------------------*/
static AP4_Result
WriteSamples(AP4_ByteStream*                  output,
             AP4_Mpeg2TsWriter&               writer,
             AP4_Track*                       audio_track,
             SampleReader*                    audio_reader,
             AP4_Mpeg2TsWriter::SampleStream* audio_stream,
             AP4_Track*                       video_track,
             SampleReader*                    video_reader,
             AP4_Mpeg2TsWriter::SampleStream* video_stream)
{
    AP4_Sample        audio_sample;
    AP4_DataBuffer    audio_sample_data;
    unsigned int      audio_sample_count = 0;
    double            audio_ts = 0.0;
    bool              audio_eos = false;
    AP4_Sample        video_sample;
    AP4_DataBuffer    video_sample_data;
    unsigned int      video_sample_count = 0;
    double            video_ts = 0.0;
    bool              video_eos = false;
    AP4_Result        result = AP4_SUCCESS;
    AP4_Array<double> segment_durations;
    
    // prime the samples
    if (audio_reader) {
        result = ReadSample(*audio_reader, *audio_track, audio_sample, audio_sample_data, audio_ts, audio_eos);
        if (AP4_FAILED(result)) return result;
    }
    if (video_reader) {
        result = ReadSample(*video_reader, *video_track, video_sample, video_sample_data, video_ts, video_eos);
        if (AP4_FAILED(result)) return result;
    }
    bool isPATsWritten = false;
    for (;;) {
        bool sync_sample = false;
        AP4_Track* chosen_track= NULL;
        if (audio_track && !audio_eos) {
            chosen_track = audio_track;
            if (video_track == NULL) sync_sample = true;
        }
        if (video_track && !video_eos) {
            if (audio_track) {
                if (video_ts <= audio_ts) {
                    chosen_track = video_track;
                }
            } else {
                chosen_track = video_track;
            }
            if (chosen_track == video_track && video_sample.IsSync()) {
                sync_sample = true;
            }
        }
        if (chosen_track == NULL) break;
        
        // check if we need to start a new segment
//        if (Options.segment_duration && sync_sample) {
//            if (video_track) {
//                segment_duration = video_ts - last_ts;
//            } else {
//                segment_duration = audio_ts - last_ts;
//            }
//            if (segment_duration >= (double)Options.segment_duration - (double)segment_duration_threshold/1000.0) {
//                if (video_track) {
//                    last_ts = video_ts;
//                } else {
//                    last_ts = audio_ts;
//                }
//                if (output) {
//                    segment_durations.Append(segment_duration);
//                    if (Options.verbose) {
//                        printf("Segment %d, duration=%.2f, %d audio samples, %d video samples\n",
//                               segment_number,
//                               segment_duration,
//                               audio_sample_count,
//                               video_sample_count);
//                    }
//                    output->Release();
//                    output = NULL;
//                    ++segment_number;
//                    audio_sample_count = 0;
//                    video_sample_count = 0;
//                }
//            }
//        }
        if(!isPATsWritten){
            writer.WritePAT(*output);
            writer.WritePMT(*output);
        }
        
        // write the samples out and advance to the next sample
        if (chosen_track == audio_track) {
            result = audio_stream->WriteSample(audio_sample,
                                               audio_sample_data,
                                               audio_track->GetSampleDescription(audio_sample.GetDescriptionIndex()),
                                               video_track==NULL,
                                               *output);
            if (AP4_FAILED(result)) return result;
            
            result = ReadSample(*audio_reader, *audio_track, audio_sample, audio_sample_data, audio_ts, audio_eos);
            if (AP4_FAILED(result)) return result;
            ++audio_sample_count;
        } else if (chosen_track == video_track) {
            result = video_stream->WriteSample(video_sample,
                                               video_sample_data,
                                               video_track->GetSampleDescription(video_sample.GetDescriptionIndex()),
                                               true,
                                               *output);
            if (AP4_FAILED(result)) return result;
            
            result = ReadSample(*video_reader, *video_track, video_sample, video_sample_data, video_ts, video_eos);
            if (AP4_FAILED(result)) return result;
            ++video_sample_count;
        } else {
            break;
        }
    }

    return result;
}

int avMuxH264AacTS(const AP4_UI08* vbuff, int64_t vbuff_len,
                 const AP4_UI08* abuff, int64_t abuff_len,
                 void** moov_outbuff, int64_t* moov_outbuff_len,
                 void** moof_outbuff, int64_t* moof_outbuff_len) {
    
    int Options_pmt_pid                    = 0x100;
    int Options_audio_pid                  = 0x101;
    int Options_video_pid                  = 0x102;
    AP4_Result result = AP4_SUCCESS;
    // create the movie object to hold the tracks
    //AP4_Movie* input_movie = new AP4_Movie();
    
    // setup the brands
    AP4_Array<AP4_UI32> brands;
    brands.Append(AP4_FILE_BRAND_ISOM);
    brands.Append(AP4_FILE_BRAND_MP42);

    AP4_MemoryByteStream* sample_storage = new AP4_MemoryByteStream();
    AP4_Track* video_track = NULL;
    AP4_Track* audio_track = NULL;
    if(vbuff_len > 0){
        video_track = AddH264Track(NULL/*input_movie*/, vbuff, (AP4_Size)vbuff_len, brands, *sample_storage);
    }
    if(abuff_len > 0){
        audio_track = AddAacTrack(NULL/*input_movie*/, abuff, (AP4_Size)abuff_len, *sample_storage);
    }
    printf("avMuxH264AacTS: preparing TS, video_track: %fs, audio_track: %fs\n", video_track?video_track->GetDurationMs()/1000.0f:0.0f, audio_track?audio_track->GetDurationMs()/1000.0f:0.0f);
    // open the output
    AP4_ByteStream* output = NULL;
    output = new AP4_MemoryByteStream();
    AP4_Mpeg2TsWriter writer(Options_pmt_pid);
    AP4_Mpeg2TsWriter::SampleStream* audio_stream = NULL;
    AP4_Mpeg2TsWriter::SampleStream* video_stream = NULL;
    AP4_SampleDescription* sample_description;
    SampleReader*     audio_reader  = NULL;
    SampleReader*     video_reader  = NULL;
    if (audio_track) {
        audio_reader = new TrackSampleReader(*audio_track);
    }
    if (video_track) {
        video_reader = new TrackSampleReader(*video_track);
    }
    
    // add the audio stream
    if (audio_track) {
        sample_description = audio_track->GetSampleDescription(0);
        if (sample_description == NULL) {
            printf("ERROR: unable to parse audio sample description\n");
            goto end;
        }
        
        unsigned int stream_type = 0;
        unsigned int stream_id   = 0;
        if (sample_description->GetFormat() == AP4_SAMPLE_FORMAT_MP4A) {
            stream_type = AP4_MPEG2_STREAM_TYPE_ISO_IEC_13818_7;
            stream_id   = AP4_MPEG2_TS_DEFAULT_STREAM_ID_AUDIO;
        } else if (sample_description->GetFormat() == AP4_SAMPLE_FORMAT_AC_3 ||
                   sample_description->GetFormat() == AP4_SAMPLE_FORMAT_EC_3) {
            stream_type = AP4_MPEG2_STREAM_TYPE_ATSC_AC3;
            stream_id   = AP4_MPEG2_TS_STREAM_ID_PRIVATE_STREAM_1;
        } else {
            printf("ERROR: audio codec not supported\n");
            return 1;
        }
        
        result = writer.SetAudioStream(audio_track->GetMediaTimeScale(),
                                       stream_type,
                                       stream_id,
                                       audio_stream,
                                       Options_audio_pid);
        if (AP4_FAILED(result)) {
            printf("could not create audio stream (%d)\n", result);
            goto end;
        }
    }
    
    // add the video stream
    if (video_track) {
        sample_description = video_track->GetSampleDescription(0);
        if (sample_description == NULL) {
            printf("ERROR: unable to parse video sample description\n");
            goto end;
        }
        
        // decide on the stream type
        unsigned int stream_type = 0;
        unsigned int stream_id   = AP4_MPEG2_TS_DEFAULT_STREAM_ID_VIDEO;
        if (sample_description->GetFormat() == AP4_SAMPLE_FORMAT_AVC1 ||
            sample_description->GetFormat() == AP4_SAMPLE_FORMAT_AVC2 ||
            sample_description->GetFormat() == AP4_SAMPLE_FORMAT_AVC3 ||
            sample_description->GetFormat() == AP4_SAMPLE_FORMAT_AVC4) {
            stream_type = AP4_MPEG2_STREAM_TYPE_AVC;
        } else if (sample_description->GetFormat() == AP4_SAMPLE_FORMAT_HEV1 ||
                   sample_description->GetFormat() == AP4_SAMPLE_FORMAT_HVC1) {
            stream_type = AP4_MPEG2_STREAM_TYPE_HEVC;
        } else {
            printf("ERROR: video codec not supported\n");
            return 1;
        }
        result = writer.SetVideoStream(video_track->GetMediaTimeScale(),
                                       stream_type,
                                       stream_id,
                                       video_stream,
                                       Options_video_pid);
        if (AP4_FAILED(result)) {
            printf("could not create video stream (%d)\n", result);
            goto end;
        }
    }
    result = WriteSamples(output, writer,
                          audio_track, audio_reader, audio_stream,
                          video_track, video_reader, video_stream);
    
   
    AP4_LargeSize size;
    output->GetSize(size);
    output->Seek(0);
    *moof_outbuff = malloc((size_t)size);
    output->Read(*moof_outbuff, (AP4_Size)size);
    *moof_outbuff_len = size;
    
end:
    *moov_outbuff = NULL;
    *moov_outbuff_len = 0;

    // cleanup
    sample_storage->Release();
    output->Release();
    
    return result;
}
