//
//  FFOutputStream.m
//  LiveStreamer
//
//  Created by Christopher Ballinger on 10/1/13.
//  Copyright (c) 2013 OpenWatch, Inc. All rights reserved.
//

#import "FFOutputStream.h"
#import "FFOutputFile.h"

@interface FFOutputStream ()

@property (nonatomic, strong) NSMutableSet *bitstreamFilters;

@end

@implementation FFOutputStream
@synthesize lastMuxDTS, frameNumber;

- (id) initWithOutputFile:(FFOutputFile*)outputFile outputCodec:(NSString*)outputCodec {
    if (self = [super initWithFile:outputFile]) {
        self.lastMuxDTS = AV_NOPTS_VALUE;
        self.frameNumber = 0;
        
        const char* requestedCodec = [outputCodec UTF8String];
        AVCodec *codec = avcodec_find_encoder_by_name(requestedCodec);
        if (!codec)
        {
            if ([outputCodec isEqualToString:@"h264"])
            {
                codec = avcodec_find_encoder(AV_CODEC_ID_H264);

            }
            /*
            NSLog(@"codec not found: %@, searching for it.", outputCodec);
            
            codec = av_codec_next(codec);
            BOOL found = NO;
            while(codec && !found)
            {
                NSString *string = [NSString stringWithCString:codec->name encoding:NSASCIIStringEncoding];
                if ([string isEqualToString:outputCodec])
                {
                    found = YES;
                    NSLog(@"Found codec %@ while iterating", outputCodec);
                }
                else
                {
                    codec = av_codec_next(codec);
                }
            }
            if (!found)
            {
                codec = NULL;
                NSLog(@"Couldn't find %@", outputCodec);
            }*/
        }
        
        self.stream = avformat_new_stream(outputFile.formatContext, codec);
        [outputFile addOutputStream:self];
    }
    return self;
}

- (void) setupVideoContextWithWidth:(int)width height:(int)height {
    AVCodecContext *c = self.stream->codec;
    
    AVCodec *codec = avcodec_find_encoder(c->codec_id);
    if (!codec) {
        NSLog(@"Can not find encoder!");
    }
    
    
    avcodec_get_context_defaults3(c, NULL);
    c->codec_id = AV_CODEC_ID_H264;//CODEC_ID_H264;
    c->codec_type = AVMEDIA_TYPE_VIDEO;
    c->width    = width;
    c->height   = height;
    c->bit_rate = 2000000;
    c->profile = FF_PROFILE_H264_BASELINE;
    c->time_base.den = 90000;
    c->time_base.num = 1;
    c->pix_fmt       = PIX_FMT_YUV420P;
    if (self.parentFile.formatContext->oformat->flags & AVFMT_GLOBALHEADER)
        c->flags |= CODEC_FLAG_GLOBAL_HEADER;
}

void make_dsi( unsigned int sampling_frequency_index, unsigned int channel_configuration, unsigned   char* dsi )
{
    unsigned int object_type = 2;
    dsi[0] = (object_type<<3) | (sampling_frequency_index>>1);
    dsi[1] = ((sampling_frequency_index&1)<<7) | (channel_configuration<<3);
}
int get_sr_index(unsigned int sampling_frequency)
{
    switch (sampling_frequency) {
        case 96000: return 0;
        case 88200: return 1;
        case 64000: return 2;
        case 48000: return 3;
        case 44100: return 4;
        case 32000: return 5;
        case 24000: return 6;
        case 22050: return 7;
        case 16000: return 8;
        case 12000: return 9;
        case 11025: return 10;
        case 8000:  return 11;
        case 7350:  return 12;
        default:    return 0;
    }
}

- (void) setupAudioContextWithSampleRate:(int)sampleRate {
    AVCodecContext *codecContext = self.stream->codec;
    int codecID = CODEC_ID_AAC;
    AVCodec *codec = avcodec_find_encoder(codecID);
    if (!codec) {
        NSLog(@"audio codec not found: %d", codecID);
    }
    /* find the audio encoder */
    avcodec_get_context_defaults3(codecContext, codec);
    codecContext->codec_id = codecID;
    codecContext->codec_type = AVMEDIA_TYPE_AUDIO;
    
    //st->id = 1;
    codecContext->strict_std_compliance = FF_COMPLIANCE_UNOFFICIAL; // for native aac support
    /* put sample parameters */
    //codecContext->sample_fmt  = AV_SAMPLE_FMT_FLT;
    codecContext->sample_fmt  = AV_SAMPLE_FMT_S16;
    codecContext->time_base.den = 90000;
    codecContext->time_base.num = 1;
    codecContext->channel_layout = AV_CH_LAYOUT_MONO;
    codecContext->profile = FF_PROFILE_AAC_LOW;
    codecContext->bit_rate = 64 * 1000;
    //c->bit_rate    = bit_rate;
    codecContext->sample_rate = sampleRate;
    codecContext->channels    = 1;
//    char dsi[2];
//    make_dsi( (unsigned int)get_sr_index( (unsigned int)sampleRate ), (unsigned int)1, dsi );
//    codecContext->extradata = (uint8_t*)dsi;
//    codecContext->extradata_size = 2;

    //NSLog(@"addAudioStream sample_rate %d index %d", codecContext->sample_rate, self.stream->index);
    //LOGI("add_audio_stream parameters: sample_fmt: %d bit_rate: %d sample_rate: %d", codec_audio_sample_fmt, bit_rate, audio_sample_rate);
    // some formats want stream headers to be separate
//    if (self.parentFile.formatContext->oformat->flags & AVFMT_GLOBALHEADER)
//        codecContext->flags |= CODEC_FLAG_GLOBAL_HEADER;
}

- (void) addBitstreamFilter:(FFBitstreamFilter *)bitstreamFilter {
    if (_bitstreamFilters == nil)
    {
        _bitstreamFilters = [NSMutableSet new];
    }
    [_bitstreamFilters addObject:bitstreamFilter];
}

- (void) removeBitstreamFilter:(FFBitstreamFilter *)bitstreamFilter {
    if (_bitstreamFilters == nil)
    {
        _bitstreamFilters = [NSMutableSet new];
    }
    [_bitstreamFilters removeObject:bitstreamFilter];
}

- (NSSet *)bitstreamFilters
{
    if (_bitstreamFilters == nil)
    {
        _bitstreamFilters = [NSMutableSet new];
    }
    return _bitstreamFilters;
}

@end
