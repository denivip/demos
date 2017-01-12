//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

#import "MainViewController.h"
#import "Defaults.h"
#import "CacheFileManager.h"
#import "AppDelegate.h"
#import "UIGriddableView.h"
#import "NSTimer+Blocks.h"
#import "RTSPServer.h"
#import "SmoothLineView.h"

__weak static PBJVision *weakvision;
__weak static MainViewController *weakroot;

@interface MainViewController ()
@property (strong, nonatomic) PBJVision *vision;

@property (weak, nonatomic) IBOutlet UIView *previewView;
@property (weak, nonatomic) IBOutlet UIButton *toggleStreaming;
@property (weak, nonatomic) IBOutlet UIView *uisubsRoot;
@property (strong, nonatomic) NSMutableArray* loglines;
@property (assign) double tapStartTs;
@property (assign) double lastActionTs;
@property (assign) int isRecording;
@property (assign) int viewInitalized;
@property (assign) float zoomingLevel;
@property (assign) NSUInteger lastHandledVideoSeconds;
@property (assign) Float64 prevFlushedChunkTs;
//@property (weak, nonatomic) IBOutlet SmoothLineView *fingerPainter;
//@property (weak, nonatomic) IBOutlet NSLayoutConstraint *cs_fingerPainterW;
//@property (weak, nonatomic) IBOutlet NSLayoutConstraint *cs_fingerPainterH;
//@property (assign) CGSize fingerPainterBufDims;
//@property (assign) CVImageBufferRef fingerPainterBuf;
//@property (assign) double audioPts2send;
@property (strong, nonatomic) RTSPServerConfig* rtspConfig;
@property (strong, nonatomic) RTSPServer* rtsp;
@end

static int ddLogLevel = LOG_LEVEL_VERBOSE;
const CGFloat pinchZoomScaleFactor = 2.0;
const CGFloat zoomBgZazor = 20.0;
static int needStartCapture = 0;
@implementation MainViewController
+(PBJVision *)getPBJVision {
    return weakvision;
}

+(void)addLogLine:(NSString*)msg {
    dispatch_async(dispatch_get_main_queue(),^{
        [weakroot setStatusLog:msg replace:NO];
    });
}

- (void)viewDidLoad {
     weakroot = self;
    [super viewDidLoad];
    [UIApplication sharedApplication].statusBarStyle = UIStatusBarStyleLightContent;

    self.loglines = @[].mutableCopy;
    UIView* pv = [[UIView alloc] initWithFrame:CGRectZero];
    pv.backgroundColor = [UIColor blackColor];
    AVCaptureVideoPreviewLayer *_previewLayer = [[PBJVision sharedInstance] previewLayer];
    _previewLayer.frame = self.previewView.bounds;
    _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [pv.layer addSublayer:_previewLayer];
    [self.previewView addSubview:pv];
    self.uisubsRoot.userInteractionEnabled = YES;
    
    UIPinchGestureRecognizer* pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@checkselector(self, handlePinchToZoomRecognizer:)];
    [self.uisubsRoot addGestureRecognizer:pinchRecognizer];
   
    [self.toggleStreaming setAction:kUIButtonBlockTouchUpInside withBlock:^{
        [self switchRecordingState:1-self.isRecording];
    }];
    
    [NSTimer scheduledTimerWithTimeInterval:1.0 block:^{
        if(needStartCapture > 0){
            if(self.vision.isPaused){
                [self.vision resumeVideoCapture];
            }else if(!self.vision.isRecording || needStartCapture > 1){
                [self.vision startVideoCapture];
            }
            needStartCapture = 0;
        }
    } repeats:YES];

    //self.fingerPainter.fadePerSec = 0.5;//2.5;
    //self.fingerPainter.userInteractionEnabled = YES;
    //self.fingerPainter.lineColor = [UIColor redColor];
    //[NSTimer scheduledTimerWithTimeInterval:1.0f/30.0f block:^{
    //    [self updateFrameBlendingBuffers];
    //} repeats:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@checkselector(self, serverNotfNetworkMsg:)
                                                 name:kNotfMessage
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@checkselector(self, willEnterForeground:)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@checkselector(self, willEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
}

- (void)dealloc {
//    @synchronized(self.fingerPainter){
//        if(self.fingerPainterBuf != nil){
//            CVPixelBufferRelease(self.fingerPainterBuf);
//            self.fingerPainterBuf = nil;
//        }
//    };
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    if(self.vision == nil){
        self.vision = [PBJVision sharedInstance];
        self.vision.delegate = self;
        self.vision.cameraMode = PBJCameraModeVideo;
        self.vision.focusMode = PBJFocusModeContinuousAutoFocus;
        self.vision.outputFormat = CAPTURE_ASPECT;
        self.vision.captureContainerFormat = (NSString*)RAW_CHUNK_CONTAINER;
        self.vision.inmemEncoding = PBJInmemEncodingExclusive;
        [self.vision setCaptureSessionPreset:AVCaptureSessionPresetLow];
        self.vision.additionalCompressionProperties = @{
                                                        AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel,
                                                        AVVideoAllowFrameReorderingKey: @NO,
                                                        };
        [self.vision setThumbnailEnabled:NO];
        weakvision = self.vision;
        
        NSString* rawcpath = [CacheFileManager cachePathForKey:CACHE_RAWCHUNKS_PATH];
        [[CacheFileManager sharedManager] deleteFilesAtPath:rawcpath];
        [[CacheFileManager sharedManager] createDirectoryAtPath:rawcpath];
        [self.vision setCaptureDirectory:rawcpath];
        [self configureWithInterfaceOrientation: [UIApplication sharedApplication].statusBarOrientation];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.vision muteAudio:NO];
            [self.vision muteVideo:self.isRecording>0?NO:YES];
            needStartCapture = 1;
        });
    }
    [self updateView];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.viewInitalized++;
    NSString* version = [[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleShortVersionString"];
    NSString* startInfo = [NSString stringWithFormat:@"%@ v%@", NSLocalizedString(@"Starting app", nil), version];
    [self setStatusLog:startInfo replace:NO];
    
    self.isRecording = 0;
    [self updateView];
    [self.vision startPreview];
}

- (void)viewDidLayoutSubviews {
    AVCaptureVideoPreviewLayer *_previewLayer = [[PBJVision sharedInstance] previewLayer];
    _previewLayer.frame = self.previewView.bounds;
}

- (BOOL)prefersStatusBarHidden {
    return NO;
}

-(void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration{
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
    
    [self configureWithInterfaceOrientation:toInterfaceOrientation];
}

-(void)willEnterForeground:(NSNotification*)notification {
    [self.vision unfreezePreview];
    needStartCapture = 1;
}

-(void)willEnterBackground:(NSNotification*)notification {
    [self.vision freezePreview];
    [self.vision pauseVideoCapture];
}

-(void)configureWithInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation{
    switch (interfaceOrientation) {
        case UIInterfaceOrientationLandscapeLeft:
            [self.vision setCameraOrientation:PBJCameraOrientationLandscapeLeft];
            break;
        case UIInterfaceOrientationLandscapeRight:
            [self.vision setCameraOrientation:PBJCameraOrientationLandscapeRight];
            break;
        case UIInterfaceOrientationPortrait:
            [self.vision setCameraOrientation:PBJCameraOrientationPortrait];
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            [self.vision setCameraOrientation:PBJCameraOrientationPortraitUpsideDown];
            break;
            
        default:
            break;
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void)handlePinchToZoomRecognizer:(UIPinchGestureRecognizer*)pinchRecognizer {
    if (pinchRecognizer.state == UIGestureRecognizerStateChanged) {
        self.zoomingLevel = pinchRecognizer.scale - 1.0;
        [self zoomingSet2Device];
    }
}

- (void)zoomingSet2Device {
    if(self.zoomingLevel < 0.0){
        self.zoomingLevel = 0.0;
    }
    if(self.zoomingLevel > 1.0){
        self.zoomingLevel = 1.0;
    }
    
    float videoZoomFactor = 1.0 + self.zoomingLevel * pinchZoomScaleFactor;
    [self.vision setZoomFactor:videoZoomFactor];
    [self updateView];
}

- (void)switchRecordingState:(int)newState {
    self.lastActionTs = CACurrentMediaTime();
    self.isRecording = newState;
    [self updateView];
    [self setStatusLog:self.isRecording>0?@"Streaming started":@"Streaming paused" replace:NO];
    [self.vision muteAudio:NO];
    [self.vision muteVideo:self.isRecording>0?NO:YES];
}

- (void)updateView {
    UIImage* recbt = [UIImage imageNamed:self.isRecording>0?@"btn_rec_red":@"btn_rec_white"];
    [self.toggleStreaming setImage:recbt forState:UIControlStateNormal];
}

- (void)setStatusLog:(NSString*)msg replace:(BOOL)replaceOld {
    DDLogInfo(@"StatusLog: %@", msg);
    NSString* preMsg = msg;//self.logLabel.text;
    if([preMsg length]>0 && replaceOld == NO && self.viewInitalized>0){
        UILabel* lline = [[UILabel alloc] initWithFrame:CGRectMake(10,10,self.previewView.frame.size.width,22)];
        lline.text = preMsg;
        lline.textColor = [UIColor whiteColor];
        [self.loglines addObject:lline];
        [self.uisubsRoot addSubview:lline];
        int idx = 1;
        for(UILabel* pl in self.loglines){
            CGRect f = pl.frame;
            f.origin.y = 22*idx;//f.size.height;
            pl.frame = f;
            idx++;
        }
        while([self.loglines count]>15){
            UILabel* pl = [self.loglines firstObject];
            [self.loglines removeObject:pl];
            [pl removeFromSuperview];
        }
    }
}

- (void)serverNotfNetworkMsg:(NSNotification*)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary* userInfo = [notification userInfo];
        if([userInfo objectForKey:@"message"] != nil){
            [self setStatusLog:[userInfo objectForKey:@"message"] replace:NO];
        }
    });
}

- (void)vision:(PBJVision *)vision didCaptureSampleHandled:(CMSampleBufferRef)sampleBuffer {
    //    CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
    //    CMMediaType sampleMediaType = CMFormatDescriptionGetMediaType(format);
    //    if(sampleMediaType == kCMMediaType_Video){
    //         self.lastPts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
    //    }
}

+ (UIImage *)imageWithImage:(UIImage *)image scaledToSize:(CGSize)newSize {
    //UIGraphicsBeginImageContext(newSize);
    // In next line, pass 0.0 to use the current device's pixel scaling factor (and thus account for Retina resolution).
    // Pass 1.0 to force exact pixel size.
    UIGraphicsBeginImageContextWithOptions(newSize, NO, 0.0);
    [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newImage;
}

+ (CVPixelBufferRef)pixelBufferFromCGImage:(CGImageRef)image
{
    CGSize frameSize = CGSizeMake(CGImageGetWidth(image), CGImageGetHeight(image));
    NSDictionary *options = @{
                              (__bridge NSString *)kCVPixelBufferCGImageCompatibilityKey: @(YES),
                              (__bridge NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @(YES)
                              };
    CVPixelBufferRef pixelBuffer;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, frameSize.width,
                                          frameSize.height,  kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef) options,
                                          &pixelBuffer);
    if (status != kCVReturnSuccess) {
        return NULL;
    }
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *data = CVPixelBufferGetBaseAddress(pixelBuffer);
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(data, frameSize.width, frameSize.height,
                                                 8, CVPixelBufferGetBytesPerRow(pixelBuffer), rgbColorSpace,
                                                 (CGBitmapInfo) kCGImageAlphaNoneSkipLast);
    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(image),
                                           CGImageGetHeight(image)), image);
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    return pixelBuffer;
}

- (void)updateFrameBlendingBuffers {
//    @autoreleasepool {
//        if(self.fingerPainterBufDims.width < 1){
//            // Not now
//            return;
//        }
//        if(self.fingerPainter.empty){
//            if(self.fingerPainterBuf != nil){
//                @synchronized(self.fingerPainter){
//                    if(self.fingerPainterBuf != nil){
//                        CVPixelBufferRelease(self.fingerPainterBuf);
//                        self.fingerPainterBuf = nil;
//                    }
//                }
//            }
//            return;
//        }
//        UIGraphicsBeginImageContext(self.fingerPainterBufDims);//self.fingerPainter.bounds.size
//        [self.fingerPainter.layer renderInContext:UIGraphicsGetCurrentContext()];
//        UIImage *screenshot = UIGraphicsGetImageFromCurrentImageContext();
//        //screenshot = [MainViewController imageWithImage:screenshot scaledToSize:self.fingerPainterBufDims];
//        CVImageBufferRef fpb = [MainViewController pixelBufferFromCGImage:screenshot.CGImage];
//        UIGraphicsEndImageContext();
//        @synchronized(self.fingerPainter){
//            if(self.fingerPainterBuf != nil){
//                CVPixelBufferRelease(self.fingerPainterBuf);
//                self.fingerPainterBuf = nil;
//            }
//            self.fingerPainterBuf = fpb;
//        }
//    }
}

- (CVImageBufferRef)vision:(PBJVision *)vision onBeforeEncodingVideoFrame:(CVImageBufferRef)imageBuffer frameSize:(CGSize)dims {
//    if(self.fingerPainterBufDims.width < 1){
//        self.fingerPainterBufDims = dims;
//        dispatch_async(dispatch_get_main_queue(), ^{
//            self.cs_fingerPainterW.constant = self.fingerPainterBufDims.width;
//            self.cs_fingerPainterH.constant = self.fingerPainterBufDims.height;
//        });
//    }
//    if(self.fingerPainterBuf != nil){
//        @synchronized(self.fingerPainter){
//            if(self.fingerPainterBuf != nil){
//                imageBuffer = self.fingerPainterBuf;
//            }
//        };
//    }
    CVPixelBufferRetain(imageBuffer);
    return imageBuffer;
}

- (void)vision:(PBJVision *)vision onAfterEncodingVideoFrame:(CVImageBufferRef)imageBuffer {
    CVPixelBufferRelease(imageBuffer);
}

- (BOOL)vision:(PBJVision *)vision onVideoFrameEncodedWithPts:(double)pts withSps:(NSData*)sps withPps:(NSData*)pps circularBuffer:(CBCircularData *)video {
    CFTimeInterval ts = CACurrentMediaTime();
    if(self.prevFlushedChunkTs < 1.0){
        self.prevFlushedChunkTs = ts;
    }
//    NSString* actualPreset = CAPTURE_QUALITY;
//    if(![self.vision.captureSessionPreset isEqualToString:actualPreset]){
//        [self.rtsp shutdownServer];
//        self.rtsp = nil;
//        
//        [self.vision cancelVideoCapture];
//        [self.vision setCaptureSessionPreset:actualPreset];
//        [self.vision startVideoCapture];
//        self.prevFlushedChunkTs = ts;
//        return YES;
//    }
    if(sps != nil && pps != nil)
    {
        if(self.rtsp == nil){
            self.rtspConfig = [[RTSPServerConfig alloc] init];
            self.rtspConfig.spsNal = sps;
            self.rtspConfig.ppsNal = pps;
            self.rtspConfig.audioSettings = [self.vision audioEncodingSettings];
            [self restartRtsp];
            return YES;
        }
        if(self.rtspConfig.spsNal != sps){
            // most recent should be used for SDP
            self.rtspConfig.spsNal = sps;
            self.rtspConfig.ppsNal = pps;
        }
    }
    if([video.dataBuffers count] > 0 && sps != nil && pps != nil)
    {
        self.prevFlushedChunkTs = ts;
        //self.audioPts2send = pts;
        //NSLog(@"Sending video with pts=%f, buffers: %i", pts, (int)[video.dataBuffers count]);
        [self.rtsp onVideoData:video.dataBuffers time:pts];
        return YES;
    }
    return NO;
}

- (BOOL)vision:(PBJVision *)vision onAudioFrameEncodedWithPts:(double)pts circularBuffer:(CBCircularData *)audio {
    if([audio.dataBuffers count]>0 && self.rtsp != nil){//self.audioPts2send > 0
        //NSLog(@"Sending audio with pts=%f", pts);
        [self.rtsp onAudioData:audio.dataBuffers time:0];
        //self.audioPts2send = 0;
        return YES;
    }
    return NO;
}

- (void)restartRtsp {
    [self.rtsp shutdownServer];
    self.rtsp = [RTSPServer setupListener:self.rtspConfig];
    if(self.rtsp != nil){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSString* ipaddr = [RTSPServer getIPAddress];
            NSString* url = [NSString stringWithFormat:@"Device is online, url: rtsp://%@/", ipaddr];
            [self setStatusLog:url replace:NO];
        });
    }else{
        [self setStatusLog:@"Failed to go online" replace:NO];
    }
}

@end
