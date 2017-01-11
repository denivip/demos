//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

#import "MainViewController.h"
#import "Defaults.h"
#import "HLSServer.h"
#import "CacheFileManager.h"
#import "AppDelegate.h"
#import "UIGriddableView.h"
#import "NSTimer+Blocks.h"
#import "FFReencoder.h"

__weak static PBJVision *weakvision;

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
@end

static int ddLogLevel = LOG_LEVEL_VERBOSE;
const CGFloat pinchZoomScaleFactor = 2.0;
const CGFloat zoomBgZazor = 20.0;
static int needStartCapture = 0;
@implementation MainViewController
+(PBJVision *)getPBJVision {
    return weakvision;
}

- (void)viewDidLoad {
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
        //double ts = CACurrentMediaTime();
        if(needStartCapture > 0){
            if(self.vision.isPaused){
                [self.vision resumeVideoCapture];
            }else if(!self.vision.isRecording || needStartCapture > 1){
                [self.vision startVideoCapture];
            }
            needStartCapture = 0;
        }
    } repeats:YES];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@checkselector(self, serverNotfNetworkFail:)
                                                 name:kGDCNetwrokError
                                               object:nil];
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
        [self.vision setCaptureSessionPreset: AVCaptureSessionPresetLow];
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
    //if(![self.vision isRecording]){
    //    if([self.vision isPaused]){
    //        [self.vision resumeVideoCapture];
    //    }else{
    //        [self.vision startVideoCapture];
    //    }
    //}
    //else{
    //    [self.vision endVideoCapture];
    //}
}

- (void)updateView {
    
    UIImage* recbt = [UIImage imageNamed:self.isRecording>0?@"btn_rec_red":@"btn_rec_white"];
    [self.toggleStreaming setImage:recbt forState:UIControlStateNormal];
}

- (void)vision:(PBJVision *)vision didCaptureSampleHandled:(CMSampleBufferRef)sampleBuffer {
    double capturedVideoSeconds = self.vision.capturedVideoSeconds;

    if(true){
        if(capturedVideoSeconds >= self.lastHandledVideoSeconds){
            self.lastHandledVideoSeconds = capturedVideoSeconds+CHUNK_DURATION_SEC;
            //DDLogVerbose(@"Captured seconds so far: %f", capturedVideoSeconds);
        }
        return;
    }
    if(capturedVideoSeconds >= CHUNK_DURATION_SEC && self.vision.flushPending == 0){
//        NSString* actualPreset = ???;
//        if(![self.vision.captureSessionPreset isEqualToString:actualPreset]){
//            [self.vision setCaptureSessionPreset:actualPreset];
//        }
        [self.vision flushVideoCapture:NO];
    }
}

- (void)vision:(PBJVision *)vision capturedVideo:(NSDictionary *)videoDict error:(NSError *)error {
    return;
}

- (NSString *)vision:(PBJVision *)vision willStartVideoCaptureToFile:(NSString *)fileName {
    return fileName;
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

- (void)serverNotfNetworkFail:(NSNotification*)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setStatusLog:NSLocalizedString(@"Socket operation failed: can`t send data", nil) replace:NO];
    });
}


- (void)serverNotfNetworkMsg:(NSNotification*)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary* userInfo = [notification userInfo];
        if([userInfo objectForKey:@"message"] != nil){
            [self setStatusLog:[userInfo objectForKey:@"message"] replace:NO];
        }
    });
}

- (BOOL)vision:(PBJVision *)vision canFlushInmemVideo:(CBCircularData *)video andAudio:(CBCircularData *)audio {
    CFTimeInterval ts = CACurrentMediaTime();
    if(self.prevFlushedChunkTs < 1.0){
        self.prevFlushedChunkTs = ts;
    }
//    NSString* actualPreset = ???;
//    if(![self.vision.captureSessionPreset isEqualToString:actualPreset]){
//        [self.vision cancelVideoCapture];
//        [[HLSServer sharedInstance] resetLiveEncodedBuffers];
//        [self.vision setCaptureSessionPreset:actualPreset];
//        [self.vision startVideoCapture];
//        self.prevFlushedChunkTs = ts;
//        return YES;
//    }
    if([video size] > 0 && ts - self.prevFlushedChunkTs > kChunkedFileMinChunkLenSec)
    {
        self.prevFlushedChunkTs = ts;
        [FFReencoder muxVideoBuffer:video audioBuffer:audio completion:^(NSData* moov_dat, NSData* moof_dat){
            HLSServer* srv = [HLSServer sharedInstance];
            srv.liveEncodedTsHeader = moov_dat;
            [HLSServer bumpNetworkStatsBytesIn:[moof_dat length] bytesOut:0];
            NSUInteger recentChunkOffset = [srv.liveEncodedTsBuffer writeData:moof_dat];
            srv.liveEncodedTsBufferOffset = recentChunkOffset;
        }];
        return YES;
    }
    return NO;
}

@end
