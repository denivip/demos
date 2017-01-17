//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HLSServer.h"
#import "GCDWebServerDataResponse.h"
#import "GCDWebServerFileResponse.h"
#import "PSTAlertController.h"
#import "CacheFileManager.h"
#import "AppDelegate.h"
#import "FFReencoder.h"
#import "GCDWebServerFileStreamResponse.h"
#import "GCDWebServerHTTPStatusCodes.h"
#import "GCDWebServerFileChunkedResponse.h"
#import "CBCircularData.h"
#import "MainViewController.h"

#ifdef CONFIGURATION_Debug
static int ddLogLevel = LOG_LEVEL_VERBOSE;
#else
static int ddLogLevel = LOG_LEVEL_WARN;
#endif

@interface HLSServer ()
@property (strong, nonatomic) NSString *chunksNamePrefix;
@property (assign, nonatomic) NSInteger lastChunkId;
@property (assign, nonatomic) NSInteger mediaSequenceId;
@property (strong, nonatomic) NSMutableArray* readyChunks;
@property (strong, nonatomic) NSDateFormatter* m3uDateFormatter;
@property (strong, nonatomic) NSHashTable* liveEncodedTsRequests;
@end

@implementation HLSServer
+(instancetype)sharedInstance {
    // singleton initialization
    static dispatch_once_t pred = 0;
    __strong static HLSServer* shared = nil;
    dispatch_once(&pred, ^{
        shared = [[HLSServer alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    if (self = [super init]) {
        self.chunksNamePrefix = [[NSUUID new] UUIDString];
        self.readyChunks = @[].mutableCopy;
        self.m3uDateFormatter = [NSDateFormatter new];
        [self.m3uDateFormatter setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
        [self.m3uDateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];
        self.liveEncodedTsRequests = [NSHashTable hashTableWithOptions:NSHashTableWeakMemory];
        [self resetLiveEncodedBuffers];
    }
    return self;
}

-(void)bootstrapServer {
    // Create server
    //NSFileManager* fileManager = [NSFileManager defaultManager];
    self.webServer = [[GCDWebServer alloc] init];
    self.webServer.delegate = self;
    [GCDWebServer setLogLevel: 0];//3 - kGCDWebServerLoggingLevel_Error

    // Add a handler to respond to GET requests on any URL
    {
        //@weakify(self);
        [self.webServer addDefaultHandlerForMethod:@"GET"
                               requestClass:[GCDWebServerRequest class]
                               processBlock:^(GCDWebServerRequest* request) {
                                   //@strongify(self);
                                   NSString* reply = @"HELLO";
                                   NSData* replyData = [NSData dataWithBytes:[reply UTF8String] length:[reply lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
                                   GCDWebServerDataResponse* response = [GCDWebServerDataResponse responseWithData:replyData contentType:@"text/html"];
                                   return response;
                               }];
    }
    {
        @weakify(self);
        [self.webServer addHandlerForMethod:@"GET"
                                  pathRegex:[NSString stringWithFormat:@"index.%@",FMP4_EXTENSION]
                               requestClass:[GCDWebServerRequest class]
                               processBlock:^(GCDWebServerRequest* request) {
                                   @strongify(self);
                                   
//#warning DEBUG: sending out full mp4 file
//                                   if(true){
//                                       NSMutableData* test = [NSMutableData dataWithData:self.liveEncodedTsHeader];
//                                       [test appendData:[self.liveEncodedTsBuffer readData:self.liveEncodedTsBuffer.lowOffset length:self.liveEncodedTsBuffer.size]];
//                                       GCDWebServerDataResponse* tempResponse = [GCDWebServerDataResponse responseWithData:test contentType:@"application/octet-stream"];
//                                       return (GCDWebServerResponse*)tempResponse;
//                                   }
                                   
                                   self.stat_bytesIn = 0;
                                   self.stat_bytesOut = 0;
                                   [[NSNotificationCenter defaultCenter] postNotificationName:kNotfMessage object:self
                                                                                     userInfo:@{@"message":@"Incoming request detected"}];
                                   //[HLSServer bumpNetworkStatsBytesIn:[self.liveEncodedTsHeader length] bytesOut:0];
                                   GCDWebServerFileChunkedResponse* response = [GCDWebServerFileChunkedResponse responseWithCircularBuffer:self.liveEncodedTsBuffer
                                                                                                                                   fromPos:self.liveEncodedTsBufferOffset
                                                                                                                                withHeader:self.liveEncodedTsHeader
                                                                                                                                 byteRange:request.byteRange];
                                   
                                   [self.liveEncodedTsRequests addObject:response];
                                   [response setValue:@"bytes" forAdditionalHeader:@"Accept-Ranges"];
                                   response.contentType = FMP4_MIME;
                                   DDLogVerbose(@"HLSServer: mp4 request=%@", request.path);
                                   return (GCDWebServerResponse*)response;
                               }];
    }
    
    NSMutableDictionary* options = [NSMutableDictionary dictionary];
    [options setObject:[NSNumber numberWithInteger:SERVER_WWWPORT] forKey:GCDWebServerOption_Port];
    [options setValue:@(10.0) forKey:GCDWebServerOption_ConnectedStateCoalescingInterval];

    if(![self.webServer startWithOptions:options error:NULL]){
        [[NSNotificationCenter defaultCenter] postNotificationName:kNotfMessage object:self
                                                          userInfo:@{@"message":[NSString stringWithFormat:@"Can not open port %i",SERVER_WWWPORT]}];
    }else{
        //DDLogVerbose(@"HLSServer: started. URL=%@, options=%@", self.webServer.serverURL, options);
        [[NSNotificationCenter defaultCenter] postNotificationName:kNotfMessage object:self
                                                          userInfo:@{
                                                                     @"message":[NSString stringWithFormat:@"%@ %@index.mp4",NSLocalizedString(@"URL:", nil), self.webServer.serverURL]
                                                                     }];
    }
}

- (void)webServerDidStart:(GCDWebServer*)server {
}

- (void)webServerDidStop:(GCDWebServer*)server {
    if(self.webServer.serverURL != nil){
        // Possible on app background->foreground movements
        return;
    }
}

-(double)lastNetworkActivity {
    return self.lastNwa;
}

+(void)bumpLastNetworkActivity {
    [HLSServer sharedInstance].lastNwa = CACurrentMediaTime();
}

+(void)bumpNetworkStatsBytesIn:(NSInteger)bi bytesOut:(NSInteger)bo {
    [HLSServer sharedInstance].stat_bytesIn += bi;
    [HLSServer sharedInstance].stat_bytesOut += bo;
}

-(void)resetLiveEncodedBuffers {
    self.liveEncodedTsHeader = nil;
    self.liveEncodedTsBuffer = [[CBCircularData alloc] initWithDepth:5*1000000];
    self.liveEncodedTsBufferOffset = 0;
    NSArray* pendingResp = [self.liveEncodedTsRequests allObjects];
    for(GCDWebServerFileChunkedResponse* response in pendingResp){
        [response close];
    }
    
}

- (void)webServerConnectionDidFinished:(GCDWebServer*)server withRequest:(GCDWebServerRequest*)request withStatusCode:(NSInteger)statusCode {
    if(statusCode != kGCDWebServerHTTPStatusCode_OK){
        [[NSNotificationCenter defaultCenter] postNotificationName:kGDCNetwrokError object:self];
    }
}

@end
