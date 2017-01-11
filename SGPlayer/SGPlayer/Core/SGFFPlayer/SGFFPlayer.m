//
//  SGFFPlayer.m
//  SGMediaKit
//
//  Created by Single on 03/01/2017.
//  Copyright © 2017 single. All rights reserved.
//

#import "SGFFPlayer.h"
#import "SGFFDecoder.h"
#import "KxAudioManager.h"
#import "SGNotification.h"

@interface SGFFPlayer () <SGFFDecoderDelegate, KxAudioManagerDelegate>

@property (nonatomic, strong) SGFFDecoder * decoder;
@property (nonatomic, strong) NSTimer * decodeTimer;

@property (nonatomic, strong) NSMutableArray * videoFrames;
@property (nonatomic, strong) NSMutableArray * audioFrames;

@property (nonatomic, strong) NSData * currentAudioFrameSamples;
@property (nonatomic, assign) NSUInteger currentAudioFramePosition;

@property (nonatomic, assign) SGPlayerState state;
@property (nonatomic, assign) NSTimeInterval progress;
@property (nonatomic, assign) NSTimeInterval bufferDuration;

@property (nonatomic, assign) BOOL prepareToPlay;
@property (nonatomic, assign) BOOL seeking;
@property (nonatomic, assign) BOOL playing;

@property (nonatomic, assign) NSTimeInterval lastPostProgressTime;
@property (nonatomic, assign) NSTimeInterval lastPostPlayableTime;

@end

@implementation SGFFPlayer

@synthesize view = _view;

+ (instancetype)player
{
    return [[self alloc] init];
}

- (instancetype)init
{
    if (self = [super init]) {
        
        self.videoFrames = [NSMutableArray array];
        self.audioFrames = [NSMutableArray array];
        self.playableBufferInterval = 2.f;
        
        [[KxAudioManager audioManager] activateAudioSession];
        [self setupDecodeTimer];
    }
    return self;
}

- (void)replaceVideoWithURL:(NSURL *)contentURL
{
    [self replaceVideoWithURL:contentURL videoType:SGVideoTypeNormal];
}

- (void)replaceVideoWithURL:(NSURL *)contentURL videoType:(SGVideoType)videoType
{
    [self clean];
    self.contentURL = contentURL;
    self.videoType = videoType;
    [self setupDecoder];
}

- (void)play
{
    self.playing = YES;
    [KxAudioManager audioManager].delegate = self;
    [KxAudioManager audioManager].delegateQueue = dispatch_get_main_queue();
    [[KxAudioManager audioManager] play];
    
    switch (self.state) {
        case SGPlayerStateNone:
        case SGPlayerStateSuspend:
        case SGPlayerStateFailed:
        case SGPlayerStateFinished:
        {
            self.state = SGPlayerStateBuffering;
        }
            break;
        case SGPlayerStateReadyToPlay:
        case SGPlayerStatePlaying:
        case SGPlayerStateBuffering:
            break;
    }
}

- (void)pause
{
    self.playing = NO;
    [[KxAudioManager audioManager] pause];
    
    switch (self.state) {
        case SGPlayerStateNone:
        case SGPlayerStateSuspend:
            break;
        case SGPlayerStateFailed:
        case SGPlayerStateReadyToPlay:
        case SGPlayerStateFinished:
        case SGPlayerStatePlaying:
        case SGPlayerStateBuffering:
        {
            self.state = SGPlayerStateSuspend;
        }
            break;
    }
}

- (void)stop
{
    [self clean];
}

- (void)seekToTime:(NSTimeInterval)time
{
    [self seekToTime:time completeHandler:nil];
}

- (void)seekToTime:(NSTimeInterval)time completeHandler:(void (^)(BOOL finished))completeHandler
{
    if (!self.decoder.seekEnable) {
        if (completeHandler) {
            completeHandler(NO);
        }
        return;
    }
    
    self.seeking = YES;
    [self cleanFrames];
    __weak typeof(self) weakSelf = self;
    [self.decoder seekToTime:time completeHandler:^(BOOL finished) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.seeking = NO;
        if (finished) {
            self.progress = time;
        }
        if (strongSelf.prepareToPlay) {
            [strongSelf resumeDecodeTimer];
        }
        if (completeHandler) {
            completeHandler(finished);
        }
    }];
}

- (void)setVolume:(CGFloat)volume
{
    NSLog(@"SGFFPlayer %s", __func__);
}

- (void)setViewTapBlock:(void (^)())block
{
    NSLog(@"SGFFPlayer %s", __func__);
}

- (UIImage *)snapshot
{
    NSLog(@"SGFFPlayer %s", __func__);
    return nil;
}

- (void)setState:(SGPlayerState)state
{
    @synchronized (self) {
        if (_state != state) {
            SGPlayerState temp = _state;
            _state = state;
            [SGNotification postPlayer:self.abstractPlayer statePrevious:temp current:_state];
        }
    }
}

- (void)setProgress:(NSTimeInterval)progress
{
    @synchronized (self) {
        if (_progress != progress) {
            NSTimeInterval previous = _progress;
            _progress = progress;
            NSTimeInterval duration = self.duration;
            if (_progress == 0 || _progress == duration) {
                [SGNotification postPlayer:self.abstractPlayer progressPercent:@(_progress/duration) current:@(_progress) total:@(duration)];
            } else {
                NSTimeInterval currentTime = [NSDate date].timeIntervalSince1970;
                if (currentTime - self.lastPostProgressTime >= 1) {
                    self.lastPostProgressTime = currentTime;
                    [SGNotification postPlayer:self.abstractPlayer progressPercent:@(_progress/duration) current:@(_progress) total:@(duration)];
                }
            }
        }
    }
}

- (void)setBufferDuration:(NSTimeInterval)bufferDuration
{
    @synchronized (self) {
        if (_bufferDuration != bufferDuration) {
            if (bufferDuration < 0) {
                bufferDuration = 0;
            }
            _bufferDuration = bufferDuration;
            
            if (!self.decoder.endOfFile) {
                NSTimeInterval playableTtime = self.playableTime;
                NSTimeInterval duration = self.duration;
                if (playableTtime > duration) {
                    playableTtime = duration;
                }
                if (_bufferDuration == 0 || playableTtime == duration) {
                    [SGNotification postPlayer:self.abstractPlayer playablePercent:@(playableTtime/duration) current:@(playableTtime) total:@(duration)];
                } else {
                    NSTimeInterval currentTime = [NSDate date].timeIntervalSince1970;
                    if (currentTime - self.lastPostPlayableTime >= 1) {
                        self.lastPostPlayableTime = currentTime;
                        [SGNotification postPlayer:self.abstractPlayer playablePercent:@(playableTtime/duration) current:@(playableTtime) total:@(duration)];
                    }
                }
            }
        }
    }
}

- (void)setContentURL:(NSURL *)contentURL
{
    _contentURL = [contentURL copy];
}

- (void)setVideoType:(SGVideoType)videoType
{
    switch (videoType) {
        case SGVideoTypeNormal:
        case SGVideoTypeVR:
            _videoType = videoType;
            break;
        default:
            _videoType = SGVideoTypeNormal;
            break;
    }
}

- (NSTimeInterval)playableTime
{
    if (self.decoder.endOfFile) {
        return self.duration;
    }
    return self.progress + self.bufferDuration;
}

- (NSTimeInterval)duration
{
    return self.decoder.duration;
}

#pragma mark - frames

- (void)addFrames:(NSArray <SGFFFrame *> *)frames
{
    for (SGFFFrame * frame in frames) {
        switch (frame.type) {
            case SGFFFrameTypeVideo:
            {
                @synchronized (self.videoFrames) {
                    [self.videoFrames addObject:frame];
                }
            }
                break;
            case SGFFFrameTypeAudio:
            {
                @synchronized (self.audioFrames) {
                    [self.audioFrames addObject:frame];
                    self.bufferDuration += frame.duration;
                }
            }
                break;
            default:
                break;
        }
    }
    
    if (self.playing) {
        if (self.audioFrames.count <= 0) {
            self.state = SGPlayerStateBuffering;
        } else {
            self.state = SGPlayerStatePlaying;
        }
    }
//    NSLog(@"\nvideo frame count : %ld\naudio frame count : %ld", self.videoFrames.count, self.audioFrames.count);
}

#pragma mark - clean

- (void)clean
{
    [self cleanPlayer];
    [self cleanFrames];
    [self cleanDecoder];
}

- (void)cleanPlayer
{
    self.contentURL = nil;
    self.videoType = nil;
    self.seeking = NO;
    self.playing = NO;
    self.prepareToPlay = NO;
    self.state = SGPlayerStateNone;
    self.progress = 0;
    self.lastPostProgressTime = 0;
    self.lastPostPlayableTime = 0;
}

- (void)cleanFrames
{
    @synchronized (self.videoFrames) {
        [self.videoFrames removeAllObjects];
    }
    
    @synchronized (self.audioFrames) {
        [self.audioFrames removeAllObjects];
    }
    
    @synchronized (self) {
        self.currentAudioFrameSamples = nil;
        self.currentAudioFramePosition = 0;
        self.bufferDuration = 0;
    }
}

- (void)cleanDecoder
{
    if (self.decoder) {
        [self.decoder closeFile];
        self.decoder = nil;
    }
    [self pauseDecodeTimer];
}

#pragma mark - decode frames

- (void)setupDecoder
{
    [self cleanDecoder];
    self.decoder = [SGFFDecoder decoderWithContentURL:self.contentURL delegate:self delegateQueue:dispatch_get_main_queue()];
}

- (void)setupDecodeTimer
{
    __weak typeof(self) weakSelf = self;
    self.decodeTimer = [NSTimer scheduledTimerWithTimeInterval:0.01 repeats:YES block:^(NSTimer * _Nonnull timer) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf decodeTimerHandler];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.decodeTimer forMode:NSRunLoopCommonModes];
    [self pauseDecodeTimer];
}

- (void)pauseDecodeTimer
{
    self.decodeTimer.fireDate = [NSDate distantFuture];
}

- (void)resumeDecodeTimer
{
    if (self.decodeTimer.fireDate.timeIntervalSince1970 > [NSDate date].timeIntervalSince1970) {
        self.decodeTimer.fireDate = [NSDate distantPast];
    }
}

- (void)decodeTimerHandler
{
    if (self.seeking) return;
    if (!self.decoder.endOfFile && !self.decoder.decoding) {
        [self.decoder decodeFrames];
    }
}

#pragma mark - SGFFDecoderDelegate

- (void)decoderWillOpenInputStream:(SGFFDecoder *)decoder
{
    self.state = SGPlayerStateBuffering;
}

- (void)decoderDidPrepareToDecodeFrames:(SGFFDecoder *)decoder
{
    self.prepareToPlay = YES;
    [self resumeDecodeTimer];
    self.state = SGPlayerStateReadyToPlay;
}

- (void)decoder:(SGFFDecoder *)decoder didDecodeFrames:(NSArray<SGFFFrame *> *)frames
{
    if (self.seeking) return;
    if (frames.count > 0) {
        [self addFrames:frames];
    }
}

- (void)decoderDidEndOfFile:(SGFFDecoder *)decoder
{
    NSLog(@"end of file %d", decoder.endOfFile);
    NSTimeInterval duration = decoder.duration;
    [SGNotification postPlayer:self.abstractPlayer playablePercent:@(1) current:@(duration) total:@(duration)];
    [self pauseDecodeTimer];
}

- (void)decoder:(SGFFDecoder *)decoder didError:(NSError *)error
{
    NSLog(@"SGFFPlayer %s, \nerror : %@", __func__, error);
}

#pragma mark - audio

- (void)audioManager:(KxAudioManager *)audioManager outputData:(float *)data numberOfFrames:(UInt32)numFrames numberOfChannels:(UInt32)numChannels
{
    if (!self.playing) return;
    
    [self audioCallbackFillData:data numFrames:numFrames numChannels:numChannels];
}

- (void)audioCallbackFillData:(float *)outData numFrames:(UInt32) numFrames numChannels:(UInt32)numChannels
{
    if (self.decoder.endOfFile) {
        if (self.audioFrames.count <= 0) {
            self.progress = self.duration;
            self.state = SGPlayerStateFinished;
            return;
        }
    } else {
        if (self.bufferDuration < self.playableBufferInterval ) {
            memset(outData, 0, numFrames * numChannels * sizeof(float));
            return;
        }
    }
    
    while (numFrames > 0) {
        if (!self.currentAudioFrameSamples) {
            @synchronized (self.audioFrames) {
                if (self.audioFrames.count > 0) {
                    SGFFAudioFrame * frame = self.audioFrames[0];
                    [self.audioFrames removeObjectAtIndex:0];
                    self.progress = frame.position;
                    self.bufferDuration -= frame.duration;
                    
                    self.currentAudioFramePosition = 0;
                    self.currentAudioFrameSamples = frame.samples;
                }
            }
        }
        if (self.currentAudioFrameSamples) {
            const void *bytes = (Byte *)self.currentAudioFrameSamples.bytes + self.currentAudioFramePosition;
            const NSUInteger bytesLeft = (self.currentAudioFrameSamples.length - self.currentAudioFramePosition);
            const NSUInteger frameSizeOf = numChannels * sizeof(float);
            const NSUInteger bytesToCopy = MIN(numFrames * frameSizeOf, bytesLeft);
            const NSUInteger framesToCopy = bytesToCopy / frameSizeOf;
            
            memcpy(outData, bytes, bytesToCopy);
            numFrames -= framesToCopy;
            outData += framesToCopy * numChannels;
            
            if (bytesToCopy < bytesLeft) {
                self.currentAudioFramePosition += bytesToCopy;
            } else {
                self.currentAudioFrameSamples = nil;
            }
        } else {
            memset(outData, 0, numFrames * numChannels * sizeof(float));
            break;
        }
    }
}

- (void)errorHandler:(NSError *)error
{
    self.state = SGPlayerStateFailed;
    [SGNotification postPlayer:self.abstractPlayer error:error];
}

- (void)dealloc
{
    [self cleanDecoder];
    NSLog(@"SGFFPlayer release");
}

@end
