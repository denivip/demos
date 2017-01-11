//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

#import <Foundation/Foundation.h>

#define RTPSTREAM_TYPE_VIDEO 96
#define RTPSTREAM_TYPE_AUDIO 97

@interface RTSPMessage : NSObject
+ (RTSPMessage*) createWithData:(CFDataRef) data;

- (NSString*) valueForOption:(NSString*) option;
- (NSString*) createResponse:(int) code text:(NSString*) desc;
@property (strong) NSString* command_full;
@property NSString* command;
@property int sequence;

@end
