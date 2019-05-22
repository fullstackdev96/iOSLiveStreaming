//
//  KFH264Encoder.h
//  Kickflip
//
//  Created by Christopher Ballinger on 2/11/14.
//  Copyright (c) 2014 Kickflip. All rights reserved.
//


#import "KFVideoEncoder.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@interface FFmpegVideoEncoder : KFVideoEncoder <KFSampleBufferEncoder>

- (void)encodeAudioData:(NSData* )data presentationTimestamp:(CMTime) scaledTime;
- (void)onTick;
- (void)startTimer;
- (void)finishTimer;

@property (strong, nonatomic) NSString *sUrl;

@end
