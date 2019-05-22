//
//  KFH264Encoder.m
//  Kickflip
//
//  Created by Christopher Ballinger on 2/11/14.
//  Copyright (c) 2014 Kickflip. All rights reserved.
//

#import "avcodec.h"
#import "libavformat/avformat.h"
#import "libavcodec/avcodec.h"
#import "libavutil/opt.h"
#import "librtmp/log.h"


#import "FFmpegVideoEncoder.h"
#import "AVEncoder.h"
#import "KFFrame.h"



    
@interface FFmpegVideoEncoder()

@end

#define FrameRate 30

@implementation FFmpegVideoEncoder{
    AVFormatContext                *pFormatCtx;
    AVStream                       *pVideo_st, *pAudio_st;

    AVCodecContext                 *pCodecCtx;
    AVCodec                        *pCodec;
    AVPacket                        packet;
    AVPacket                       *pAudioPacket;
    AVFrame                        *pFrame;
    int                             pictureSize;
    int                             frameCounter;
    int                             frameWidth;
    int                             frameHeight;
    AVBitStreamFilterContext       *aacbsfc;
    NSLock                         *pLock;
    NSLock                         *pLockBuf;
    NSTimer                        *timer;
    
    NSThread                       *pThread;
    UInt8                          *pY;
    UInt8                          *pUV;
    size_t                          width;
    size_t                          height;
    size_t                          pYBytes;
    size_t                          pUVBytes;
    
    UInt8                           *pYUV420P;
}

- (void)dealloc
{
}

- (instancetype)initWithBitrate:(int)bitrate width:(int)width height:(int)height directory:(NSString*)directory url:(NSString*)url
{
    self.sUrl = url;
    pYUV420P = (UInt8 *)malloc(640 * 480 * 3 / 2); // buffer to store YUV with layout YYYYYYYYUUVV

    if (self = [super initWithBitrate:bitrate])
    {
        av_register_all();
        avcodec_register_all();
        avformat_network_init();
        
        frameWidth = width;
        frameHeight = height;

        int ret = avformat_alloc_output_context2(&pFormatCtx, NULL, "flv", NULL);
        
        pCodec = avcodec_find_encoder(AV_CODEC_ID_H264);

        
        pVideo_st = avformat_new_stream(pFormatCtx, pCodec);
        if (pVideo_st == NULL) {
        }
        
        pCodecCtx = pVideo_st->codec;

//        pCodecCtx = avcodec_alloc_context3(pCodec);
        pCodecCtx->codec_id = AV_CODEC_ID_H264;
        pCodecCtx->codec_type = AVMEDIA_TYPE_VIDEO;
        pCodecCtx->pix_fmt = PIX_FMT_YUV420P;
        pCodecCtx->width = width;
        pCodecCtx->height = height;
        pCodecCtx->time_base.num = 1;
        pCodecCtx->time_base.den = FrameRate;
        pCodecCtx->bit_rate = bitrate;
        pCodecCtx->gop_size = 10;
        pCodecCtx->qmin = 10;
        pCodecCtx->qmax = 51;
        pCodecCtx->profile = FF_PROFILE_H264_MAIN;
        pVideo_st->time_base.num = 1;
        pVideo_st->time_base.den = FrameRate;
        
        AVDictionary *param = NULL;
        if(pCodecCtx->codec_id == AV_CODEC_ID_H264) {
            av_dict_set(&param, "preset", "superfast", 0);
            av_dict_set(&param, "tune", "zerolatency", 0);
       }
        
        pCodec = avcodec_find_encoder(pCodecCtx->codec_id);
        if (!pCodec) {
            NSLog(@"Can not find encoder!");
        }
        
        if (avcodec_open2(pCodecCtx, pCodec, &param) < 0) {
            NSLog(@"Failed to open encoder!");
        }
        
        AVCodec *AudioCodec = avcodec_find_encoder_by_name("aac");
        
        pAudio_st = avformat_new_stream(pFormatCtx, AudioCodec);
        pAudio_st->time_base.den = 90000;
        pAudio_st->time_base.num = 1;
        pAudio_st->codec->bit_rate = 64 * 1024;
        
        
        AVCodecContext *codecContext = pAudio_st->codec;
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
        codecContext->bit_rate = 96000;
        //c->bit_rate    = bit_rate;
        codecContext->sample_rate = 44100;
        codecContext->channels    = 1;
        if (pFormatCtx->oformat->flags & AVFMT_GLOBALHEADER)
            codecContext->flags |= CODEC_FLAG_GLOBAL_HEADER;

        
        pFrame = av_frame_alloc();
        pFrame->width = frameWidth;
        pFrame->height = frameHeight;
        pFrame->format = PIX_FMT_YUV420P;
        
        avpicture_fill((AVPicture *)pFrame, NULL, pCodecCtx->pix_fmt, pCodecCtx->width, pCodecCtx->height);
        
        pictureSize = avpicture_get_size(pCodecCtx->pix_fmt, pCodecCtx->width, pCodecCtx->height);
        av_new_packet(&packet, pictureSize);
        
        //Open output URL,set before avformat_write_header() for muxing
        if (avio_open(&pFormatCtx->pb, [self.sUrl UTF8String], AVIO_FLAG_READ_WRITE) < 0) {
        }
        pAudioPacket = av_malloc(sizeof(AVPacket));

        //Write File Header
        avformat_write_header(pFormatCtx, NULL);
        
        aacbsfc =  av_bitstream_filter_init("aac_adtstoasc");
        pLock = [[NSLock alloc] init];
        pLockBuf = [[NSLock alloc] init];

//
    }
    return self;
}


- (void)setBitrate:(int)bitrate
{
    [super setBitrate:bitrate];

}

- (void) encodeAudioData:(NSData* )data presentationTimestamp:(CMTime) pts
{
    if (data.length == 0) {
        return;
    }
    av_init_packet(pAudioPacket);
    uint64_t originalPTS = pts.value;
    // This lets the muxer know about H264 keyframes

    
    pAudioPacket->data = (uint8_t*)data.bytes;
    pAudioPacket->size = (int)data.length;
    pAudioPacket->stream_index = 1;
    
    
    av_bitstream_filter_filter(aacbsfc, pFormatCtx->streams[1]->codec, NULL, &pAudioPacket->data, &pAudioPacket->size, pAudioPacket->data, pAudioPacket->size, 0);
    AVRational audioTimeBase;
    
    audioTimeBase.num = 1;
    audioTimeBase.den = 1000000000;
    uint64_t scaledPTS = av_rescale_q(originalPTS, audioTimeBase, pFormatCtx->streams[1]->time_base);
    
    pAudioPacket->pts = scaledPTS;
    pAudioPacket->dts = scaledPTS;

    [pLock lock];
    int ret = av_interleaved_write_frame(pFormatCtx, pAudioPacket);
    if (ret != 0) {
        NSLog(@"av_interleaved_write_frame failed Audio");
    }
    [pLock unlock];
    return ;
}

- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);

    pY = (UInt8 *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    pUV = (UInt8 *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
    width = CVPixelBufferGetWidth(pixelBuffer);
    height = CVPixelBufferGetHeight(pixelBuffer);
    pYBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
    pUVBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
//    pYUV420P = (UInt8 *)malloc(width * height * 3 / 2);
    
    [pLockBuf lock];
    /* convert NV12 data to YUV420*/
    UInt8 *pU = pYUV420P + (width * height);
    UInt8 *pV = pU + (width * height / 4);
    for(int i = 0; i < height; i++) {
        memcpy(pYUV420P + i * width, pY + i * pYBytes, width);
    }

    for(int j = 0; j < height / 2; j++) {
        for(int i = 0; i < width / 2; i++) {
            *(pU++) = pUV[i<<1];
            *(pV++) = pUV[(i<<1) + 1];
        }
        pUV += pUVBytes;
    }
    [pLockBuf unlock];

//    [self onThread];
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
}



- (void)startTimer
{
    timer = [NSTimer scheduledTimerWithTimeInterval: 0.033333
                                             target: self
                                           selector: @selector(onTick)
                                           userInfo: nil
                                            repeats: YES];
}

- (void)finishTimer
{
    [timer invalidate];
    [pThread cancel];
    free(pYUV420P);
}

- (void)onTick
{
    pThread = [[NSThread alloc] initWithTarget:self
                                               selector:@selector(onThread)
                                                 object:@"Thread"];
    [pThread start];
}

- (void)onThread
{
    [pLockBuf lock];

    //Read raw YUV data
    pFrame->data[0] = pYUV420P;                                // Y
    pFrame->data[1] = pFrame->data[0] + width * height;        // U
    pFrame->data[2] = pFrame->data[1] + (width * height) / 4;  // V
    // PTS
    pFrame->pts = frameCounter;

    // Encode
    int got_picture = 0;

    if (!pCodecCtx) {
        return;
    }
    int ret = avcodec_encode_video2(pCodecCtx, &packet, pFrame, &got_picture);
    if(ret < 0) {
        NSLog(@"Failed to encode!");
    }
    frameCounter++;

    [pLockBuf unlock];

    packet.pts =av_rescale_q(packet.pts, pCodecCtx->time_base, pVideo_st->time_base);
    packet.dts =av_rescale_q(packet.dts, pCodecCtx->time_base, pVideo_st->time_base);
    
    NSLog(@"Video PTS=%llu", packet.pts);

    if (got_picture == 1) {

        packet.stream_index = pVideo_st->index;
        [pLock lock];
        ret = av_interleaved_write_frame(pFormatCtx, &packet);
        if (ret != 0) {
        }
        [pLock unlock];
        av_free_packet(&packet);
    }

}

@end
