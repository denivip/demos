#ifndef mstreamer_CBCircularData_h
#define mstreamer_CBCircularData_h
@interface CBCircularData : NSObject

- (instancetype)initWithDepth:(NSUInteger)maxBytes;
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
