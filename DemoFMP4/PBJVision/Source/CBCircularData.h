//
//  CBCircularData.h
//  DemoFMP4
//
//  Created by IPv6 on 14/07/15.
//  Copyright (c) 2015 DENIVIP Group. All rights reserved.
//

#ifndef DemoFMP4_CBCircularData_h
#define DemoFMP4_CBCircularData_h
@interface CBCircularData : NSObject
@property (strong) NSDate* firstWriteTs;
@property (strong) NSDate* lastWriteTs;
@property (assign) NSInteger flags;
- (instancetype)initWithDepth:(NSUInteger)maxBytes;
- (NSData*)readCurrentData:(BOOL)andReset;
- (NSData*)readData:(NSUInteger)offset length:(NSInteger)len;
- (NSUInteger)writeData:(NSData*)dt;
- (void)removeAll;
- (NSDate*)getLastModified;
- (NSUInteger)size;
- (NSUInteger)sizeCap;
- (NSUInteger)lowOffset;
- (NSArray*)dataBuffers;
@end
#endif
