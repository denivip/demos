//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

// http://www.w3.org/2013/12/byte-stream-format-registry/isobmff-byte-stream-format.html
// https://wikileaks.org/sony/docs/05/docs/DECE/TWG/2014/CFFMediaFormat-1.2_140605.txt
// http://stackoverflow.com/questions/19974430/how-to-create-mfra-box-for-ismv-file-if-it-is-not-present

// Data and examples
// http://10.0.1.27:7000/index.mp4
// http://www.mediacollege.com/video/format/mpeg4/videofilename.mp4
// http://p.demo.flowplayer.netdna-cdn.com/vod/demo.flowplayer/bbb-800.mp4
// ffprobe -probesize 500000 -loglevel error -show_format -show_streams http://10.0.1.27:7000/index.mp4

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "Ap4.h"
#include "tsmuxer.h"
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

static AP4_UI32 moofs_sequence_number = 1;// global!!! important (seq->unique)
static AP4_UI64 moofs_duration = 0;
int avMuxH264Aac(const AP4_UI08* vbuff, int64_t vbuff_len,
                 const AP4_UI08* abuff, int64_t abuff_len,
                 void** moov_outbuff, int64_t* moov_outbuff_len,
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
    
//     ----- simple mp4
//    // open the output
//    AP4_ByteStream* output = NULL;
//    //result = AP4_FileByteStream::Create(output_filename, AP4_FileByteStream::STREAM_MODE_WRITE, output);
//    //if (AP4_FAILED(result)) {
//        //fprintf(stderr, "ERROR: cannot open output '%s' (%d)\n", output_filename, result);
//        //delete sample_storage;
//    //    return 1;
//    //}
//    output = new AP4_MemoryByteStream();
//    
//    // create a multimedia file
//    AP4_File file(movie);
//    
//    // set the file type
//    file.SetFileType(AP4_FILE_BRAND_MP42, 1, &brands[0], brands.ItemCount());
//    
//    // write the file to the output
//    AP4_FileWriter::Write(file, *output);
//
//    AP4_LargeSize size;
//    output->GetSize(size);
//    output->Seek(0);
//    *outbuff = malloc((size_t)size);
//    output->Read(*outbuff, (AP4_Size)size);
//    *outbuff_len = size;
//    
//    // cleanup
//    sample_storage->Release();
//    output->Release();
    
    AP4_Movie* output_movie = new AP4_Movie(AP4_MUX_TIMESCALE);
    
    AP4_Result result;
    AP4_ByteStream* moov_output = NULL;
    moov_output = new AP4_MemoryByteStream();
    
    AP4_ByteStream* moof_output = NULL;
    moof_output = new AP4_MemoryByteStream();
    
    AP4_Track* tracks[2];
    tracks[0] = vtrack;
    tracks[1] = atrack;
    
    AP4_MoovAtom* moov = output_movie->GetMoovAtom();
    AP4_ContainerAtom* mvex = new AP4_ContainerAtom(AP4_ATOM_TYPE_MVEX);
    AP4_MehdAtom*      mehd = new AP4_MehdAtom(0);
    mvex->AddChild(mehd);
    
    for(int i=0;i<2;i++){
        AP4_Track* track = tracks[i];
        
        // create a sample table (with no samples) to hold the sample description
        AP4_SyntheticSampleTable* sample_table = new AP4_SyntheticSampleTable();
        for (unsigned int j=0; j<track->GetSampleDescriptionCount(); j++) {
            AP4_SampleDescription* sample_description = track->GetSampleDescription(j);
            sample_table->AddSampleDescription(sample_description, false);
        }
        
        // create the track
        AP4_UI64 duration = 0;//AP4_ConvertTime(track->GetDuration(),input_movie->GetTimeScale(),AP4_MUX_TIMESCALE);
        AP4_Track* output_track = new AP4_Track(sample_table,
                                                track->GetId(),
                                                AP4_MUX_TIMESCALE,
                                                duration,
                                                track->GetMediaTimeScale(),
                                                duration,
                                                track);
        output_movie->AddTrack(output_track);
        AP4_TrexAtom* trex = new AP4_TrexAtom(track->GetId(),
                                              1,
                                              0,
                                              0,
                                              0);
        mvex->AddChild(trex);
    }
    
    // add the mvex container to the moov container
    // real duration: Unknown (infinite)
    //mehd->SetDuration(movie->GetDuration());
    //mehd->SetDuration(0xffffffff);
    mehd->SetDuration(0);
    moov->AddChild(mvex);
    
    AP4_FtypAtom* ftyp = NULL;
    ftyp = new AP4_FtypAtom(AP4_FTYP_BRAND_MP42, 1, &brands[0], brands.ItemCount());
    ftyp->Write(*moov_output);
    delete ftyp;
    moov->Write(*moov_output);
    
    // create moof payload
    for(int i=0;i<2;i++){
        AP4_Track* track = tracks[i];
        
        // setup the moof structure
        AP4_ContainerAtom* moof = new AP4_ContainerAtom(AP4_ATOM_TYPE_MOOF);
        AP4_MfhdAtom* mfhd = new AP4_MfhdAtom(moofs_sequence_number++);
        moof->AddChild(mfhd);
        
        unsigned int sample_desc_index = 0;//cursor->m_Sample.GetDescriptionIndex();
        unsigned int tfhd_flags = AP4_TFHD_FLAG_DEFAULT_BASE_IS_MOOF;
        if (sample_desc_index > 0) {
            tfhd_flags |= AP4_TFHD_FLAG_SAMPLE_DESCRIPTION_INDEX_PRESENT;
        }
        if(track == vtrack){
            tfhd_flags |= AP4_TFHD_FLAG_DEFAULT_SAMPLE_FLAGS_PRESENT;
        }
        AP4_ContainerAtom* traf = new AP4_ContainerAtom(AP4_ATOM_TYPE_TRAF);
        AP4_TfhdAtom* tfhd = new AP4_TfhdAtom(tfhd_flags,
                                              track->GetId(),
                                              0,
                                              sample_desc_index+1,
                                              0,
                                              0,
                                              0);
        if (tfhd_flags & AP4_TFHD_FLAG_DEFAULT_SAMPLE_FLAGS_PRESENT) {
            tfhd->SetDefaultSampleFlags(0x1010000); // sample_is_non_sync_sample=1, sample_depends_on=1 (not I frame)
        }
        traf->AddChild(tfhd);
    
        AP4_TfdtAtom* tfdt = new AP4_TfdtAtom(1, moofs_duration);
        traf->AddChild(tfdt);
        
        AP4_UI32 trun_flags = AP4_TRUN_FLAG_DATA_OFFSET_PRESENT | AP4_TRUN_FLAG_SAMPLE_DURATION_PRESENT | AP4_TRUN_FLAG_SAMPLE_SIZE_PRESENT;
        AP4_UI32 first_sample_flags = 0;
        if(track == vtrack){
            trun_flags |= AP4_TRUN_FLAG_FIRST_SAMPLE_FLAGS_PRESENT;
            first_sample_flags = 0x2000000; // sample_depends_on=2 (I frame)
        }
        AP4_TrunAtom* trun = new AP4_TrunAtom(trun_flags, 0, first_sample_flags);
        traf->AddChild(trun);
        moof->AddChild(traf);
    
        AP4_Array<AP4_Sample> m_SampleIndexes;
        unsigned int sample_count = 0;
        AP4_Array<AP4_TrunAtom::Entry> trun_entries;
        AP4_UI32 m_MdatSize = AP4_ATOM_HEADER_SIZE;
        AP4_UI32 m_Duration = 0;

        for(int j=0;j<track->GetSampleCount();j++){
            AP4_Sample* m_Sample;
            
            m_SampleIndexes.SetItemCount(sample_count+1);
            track->GetSample(j,m_SampleIndexes[sample_count]);
            m_Sample = &m_SampleIndexes[sample_count];
            
            if (m_Sample->GetCtsDelta()) {
                trun->SetFlags(trun->GetFlags() | AP4_TRUN_FLAG_SAMPLE_COMPOSITION_TIME_OFFSET_PRESENT);
            }
            // add one sample
            trun_entries.SetItemCount(sample_count+1);
            AP4_TrunAtom::Entry& trun_entry           = trun_entries[sample_count];
            trun_entry.sample_duration                = m_Sample->GetDuration();
            trun_entry.sample_size                    = m_Sample->GetSize();
            trun_entry.sample_composition_time_offset = m_Sample->GetCtsDelta();
            
            m_MdatSize += trun_entry.sample_size;
            m_Duration += trun_entry.sample_duration;
            sample_count++;
        }
        trun->SetEntries(trun_entries);
        trun->SetDataOffset((AP4_UI32)moof->GetSize()+AP4_ATOM_HEADER_SIZE);
        if(track == vtrack){
            moofs_duration += m_Duration;
        }
        moof->Write(*moof_output);
        moof_output->WriteUI32(m_MdatSize);
        moof_output->WriteUI32(AP4_ATOM_TYPE_MDAT);
        AP4_DataBuffer sample_data;
        AP4_Sample     sample;
        for (unsigned int i=0; i<m_SampleIndexes.ItemCount(); i++) {
            AP4_Sample& sample = m_SampleIndexes[i];
            result = sample.ReadData(sample_data);
            if (AP4_FAILED(result)) {
                fprintf(stderr, "ERROR: failed to read sample data for sample %d (%d)\n", i, result);
                continue;
            }
            result = moof_output->Write(sample_data.GetData(), sample_data.GetDataSize());
            if (AP4_FAILED(result)) {
                fprintf(stderr, "ERROR: failed to write sample data (%d)\n", result);
                continue;
            }
        }
        
        //AP4_ContainerAtom mfra(AP4_ATOM_TYPE_MFRA);
        //AP4_MfroAtom* mfro = new AP4_MfroAtom((AP4_UI32)mfra.GetSize()+16);
        //mfra.AddChild(mfro);
        //mfra.Write(*moof_output);
        
        for (unsigned int i=0; i<m_SampleIndexes.ItemCount(); i++) {
            AP4_Sample& sample = m_SampleIndexes[i];
            sample.Reset();
        }
        m_SampleIndexes.Clear();
    }
    
    AP4_LargeSize size;
    moov_output->GetSize(size);
    moov_output->Seek(0);
    *moov_outbuff = malloc((size_t)size);
    moov_output->Read(*moov_outbuff, (AP4_Size)size);
    *moov_outbuff_len = size;
    
    moof_output->GetSize(size);
    moof_output->Seek(0);
    *moof_outbuff = malloc((size_t)size);
    moof_output->Read(*moof_outbuff, (AP4_Size)size);
    *moof_outbuff_len = size;
    
    moov_output->Release();
    moof_output->Release();
    return 0;
}
