//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

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
AddAacTrack(AP4_Movie&            movie,
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
    
    // cleanup
    input->Release();
    
    movie.AddTrack(track);
    return track;
}

/*----------------------------------------------------------------------
 |   AddH264Track
 +---------------------------------------------------------------------*/
static AP4_Track*
AddH264Track(AP4_Movie&            movie,
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
    
    // cleanup
    input->Release();
    
    movie.AddTrack(track);
    return track;
}

int avMuxH264AacMP4(const AP4_UI08* vbuff, int64_t vbuff_len,
                 const AP4_UI08* abuff, int64_t abuff_len,
                 void** moof_outbuff, int64_t* moof_outbuff_len) {
    
    // create the movie object to hold the tracks
    AP4_Movie* input_movie = new AP4_Movie();
    
    // setup the brands
    AP4_Array<AP4_UI32> brands;
    brands.Append(AP4_FILE_BRAND_ISOM);
    brands.Append(AP4_FILE_BRAND_MP42);
    
// create a temp file to store the sample data
//SampleFileStorage* sample_storage = NULL;
//AP4_Result result = SampleFileStorage::Create(output_filename, sample_storage);
//if (AP4_FAILED(result)) {
//    fprintf(stderr, "ERROR: failed to create temporary sample data storage (%d)\n", result);
//    return 1;
//}
    AP4_MemoryByteStream* sample_storage = new AP4_MemoryByteStream();
    
    AP4_Track* vtrack = NULL;
    AP4_Track* atrack = NULL;
    // add all the tracks
    if(vbuff_len > 0){
        vtrack = AddH264Track(*input_movie, vbuff, (AP4_Size)vbuff_len, brands, *sample_storage);
    }
    if(abuff_len > 0){
        atrack = AddAacTrack(*input_movie, abuff, (AP4_Size)abuff_len, *sample_storage);
    }
    printf("avMuxH264AacMP4: preparing TS, video_track: %fs, audio_track: %fs\n", vtrack?vtrack->GetDurationMs()/1000.0f:0.0f, atrack?atrack->GetDurationMs()/1000.0f:0.0f);
    AP4_ByteStream* output = NULL;
    output = new AP4_MemoryByteStream();
    // create a multimedia file
    AP4_File file(input_movie);
    // set the file type
    file.SetFileType(AP4_FILE_BRAND_MP42, 1, &brands[0], brands.ItemCount());
    // write the file to the output
    AP4_FileWriter::Write(file, *output);
    
    AP4_LargeSize size;
    output->GetSize(size);
    output->Seek(0);
    *moof_outbuff = malloc((size_t)size);
    output->Read(*moof_outbuff, (AP4_Size)size);
    *moof_outbuff_len = size;

    // cleanup
    sample_storage->Release();
    output->Release();
    return 0;
}
