//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

#ifndef DemoFMP4_GCDWebServerFileChunkedResponse_h
#define DemoFMP4_GCDWebServerFileChunkedResponse_h
#import "Defaults.h"
#import "GCDWebServer.h"
#import "GCDWebServerFileResponse.h"
#import "CBCircularData.h"

@interface GCDWebServerFileChunkedResponse: GCDWebServerFileResponse
+ (instancetype)responseWithCircularBuffer:(CBCircularData*)cbdata
                                   fromPos:(NSUInteger)offset
                                withHeader:(NSData*)header
                                 byteRange:(NSRange)range;
@end

#endif
