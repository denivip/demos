//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <sys/stat.h>

#import "GCDWebServerFileChunkedResponse.h"
#import "GCDWebServerPrivate.h"
#import "HLSServer.h"

#define CHF_INFINITE_LOADING -1
@interface GCDWebServerFileChunkedResponse () {
@private
    NSString* _path;
    CBCircularData* _cbdata;
    NSData* _header;
    NSUInteger _header_size;
    BOOL _header_sent;
    
    NSInteger _offset;
    NSInteger _size;
    NSInteger _range_offset;
    NSInteger _range_length;
    NSInteger _offset_atstart;
}
@end

@implementation GCDWebServerFileChunkedResponse

+ (instancetype)responseWithCircularBuffer:(CBCircularData*)cbdata
                                   fromPos:(NSUInteger)offset
                                withHeader:(NSData*)header
                                 byteRange:(NSRange)range {
    return [[[self class] alloc] initWithCircularBuffer:cbdata
                                                fromPos:offset
                                             withHeader:header
                                              byteRange:range];
}

- (instancetype)initWithCircularBuffer:(CBCircularData*)cbdata
                               fromPos:(NSUInteger)offset
                            withHeader:(NSData*)header
                             byteRange:(NSRange)range {
    if ((self = [super init])) {
        _path = nil;
        _cbdata = cbdata;
        _offset = offset?offset:[cbdata lowOffset];
        _offset_atstart = _offset;
        _size = NSUIntegerMax;
        _header = header;
        _header_size = [header length];
        _range_offset = CHF_INFINITE_LOADING;
        BOOL hasByteRange = GCDWebServerIsValidByteRange(range);
        if (hasByteRange && range.location != NSNotFound) {
            _range_offset = range.location;
            _range_length = range.length;
        }
        self.contentType = GCDWebServerGetMimeTypeForExtension([_path pathExtension]);
        [self setStatusCode:kGCDWebServerHTTPStatusCode_PartialContent];
        self.contentLength = _size;
        self.lastModifiedDate = [cbdata getLastModified];
        self.eTag = [NSString stringWithFormat:@"%f_sec", [self.lastModifiedDate timeIntervalSince1970]];
        NSLog(@"GCDWebServerFileChunkedResponse: range %li %li", (long)_range_offset, (unsigned long)range.length);
    }
    return self;
}

- (BOOL)open:(NSError**)error {
    if(_cbdata){
        return YES;
    }
    return YES;
}

- (void)asyncReadDataWithCompletion:(GCDWebServerBodyReaderCompletionBlock)block {
    NSError* error = nil;
    if(_cbdata == nil && _header == nil){
        block([NSData data], error);
        return;
    }
    
    if(_header != nil && ((_range_offset == CHF_INFINITE_LOADING && !_header_sent) || (_range_offset != CHF_INFINITE_LOADING && _range_offset < _header_size))){
        if(_header_sent){
            block([NSData data], error);
            return;
        }
        _header_sent = YES;
        NSData* data_out = _header;
        if(_range_offset != CHF_INFINITE_LOADING){
            const Byte *bytes = data_out.bytes;
            bytes += _range_offset;
            NSUInteger len = _header_size - _range_offset;
            data_out = [NSData dataWithBytes:bytes length:len];
        }
        if(_range_length > 0){
            const Byte *bytes = data_out.bytes;
            data_out = [NSData dataWithBytes:bytes length:_range_length];
        }
        if(_range_length < 0){
            // and switching to infinite streaming
            _range_offset = CHF_INFINITE_LOADING;
        }
        NSLog(@"GCDWebServerFileChunkedResponse: readHeader +%zd", [data_out length]);
        //[HLSServer bumpNetworkStatsBytesIn:0 bytesOut:[data_out length]];
        block(data_out, error);
        return;
    }
    if(_range_offset != CHF_INFINITE_LOADING && _range_offset >= _header_size){
        _offset += _range_offset-_header_size;
        _range_offset = CHF_INFINITE_LOADING;
        _header_sent = YES;
    }
    NSData* data = [self readData:&error];
    if(data == nil || (_range_offset == CHF_INFINITE_LOADING && data.length == 0)){
        // data not ready. trying later!
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kChunkedFileWait4DataDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            //NSLog(@"asyncReadDataWithCompletion: waiting for more data to arrive");
            [self asyncReadDataWithCompletion:block];
        });
        return;
    }
    [HLSServer bumpNetworkStatsBytesIn:0 bytesOut:[data length]];
    block(data, error);
}

- (NSData*)readData:(NSError**)error {
    size_t length = MIN((NSUInteger)kChunkedFileReadBufferSize, _size);
    NSUInteger actual_offset = _offset;
    if(_range_offset != CHF_INFINITE_LOADING && _range_offset >= _header_size){
        actual_offset += _range_offset-_header_size;
    }
    
    if(_cbdata){
        NSData* data = [_cbdata readData:actual_offset length:length];
        if(data == nil){
            if (error) {
                *error = GCDWebServerMakePosixError(errno);
            }
            return nil;
        }
        ssize_t result = [data length];
        if(_range_offset == CHF_INFINITE_LOADING){
            _offset += result;
        }
        [HLSServer bumpLastNetworkActivity];
        if(result > 0){
            NSLog(@"GCDWebServerFileChunkedResponse: readData at %li (%li) +%zd", (long)(actual_offset-_offset_atstart+_header_size), (long)actual_offset, result);
        }
        return data;
    }
    return nil;
}

- (void)close {
    _cbdata = nil;
    _header = nil;
}

- (NSString*)description {
    NSMutableString* description = [NSMutableString stringWithString:[super description]];
    [description appendFormat:@"\n\n{ %@ %@}", _path, _cbdata];
    return description;
}

@end

