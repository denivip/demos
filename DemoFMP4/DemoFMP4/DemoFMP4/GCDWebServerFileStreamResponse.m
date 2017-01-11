//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

#import <sys/stat.h>
#import <Foundation/Foundation.h>
#import "GCDWebServerFileStreamResponse.h"
#import "GCDWebServerPrivate.h"
#import "HLSServer.h"
@interface GCDWebServerFileStreamResponse () {
@private
    NSString* _path;
    NSUInteger _offset;
    NSUInteger _size;
    int _file;
}
@end

@implementation GCDWebServerFileStreamResponse

- (void)asyncReadDataWithCompletion:(GCDWebServerBodyReaderCompletionBlock)block {
    NSError* error = nil;
    NSData* data = [self readData:&error];
    //dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kStreamDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    block(data, error);
    //});
}

+ (instancetype)responseWithFile:(NSString*)path {
    return [[[self class] alloc] initWithFile:path];
}

+ (instancetype)responseWithFile:(NSString*)path isAttachment:(BOOL)attachment {
    return [[[self class] alloc] initWithFile:path isAttachment:attachment];
}

+ (instancetype)responseWithFile:(NSString*)path byteRange:(NSRange)range {
    return [[[self class] alloc] initWithFile:path byteRange:range];
}

+ (instancetype)responseWithFile:(NSString*)path byteRange:(NSRange)range isAttachment:(BOOL)attachment {
    return [[[self class] alloc] initWithFile:path byteRange:range isAttachment:attachment];
}

- (instancetype)initWithFile:(NSString*)path {
    return [self initWithFile:path byteRange:NSMakeRange(NSUIntegerMax, 0) isAttachment:NO];
}

- (instancetype)initWithFile:(NSString*)path isAttachment:(BOOL)attachment {
    return [self initWithFile:path byteRange:NSMakeRange(NSUIntegerMax, 0) isAttachment:attachment];
}

- (instancetype)initWithFile:(NSString*)path byteRange:(NSRange)range {
    return [self initWithFile:path byteRange:range isAttachment:NO];
}

static inline NSDate* _NSDateFromTimeSpec(const struct timespec* t) {
    return [NSDate dateWithTimeIntervalSince1970:((NSTimeInterval)t->tv_sec + (NSTimeInterval)t->tv_nsec / 1000000000.0)];
}

- (instancetype)initWithFile:(NSString*)path byteRange:(NSRange)range isAttachment:(BOOL)attachment {
    struct stat info;
    if (lstat([path fileSystemRepresentation], &info) || !(info.st_mode & S_IFREG)) {
        GWS_DNOT_REACHED();
        return nil;
    }
#ifndef __LP64__
    if (info.st_size >= (off_t)4294967295) {  // In 32 bit mode, we can't handle files greater than 4 GiBs (don't use "NSUIntegerMax" here to avoid potential unsigned to signed conversion issues)
        GWS_DNOT_REACHED();
        return nil;
    }
#endif
    NSUInteger fileSize = (NSUInteger)info.st_size;
    
    BOOL hasByteRange = GCDWebServerIsValidByteRange(range);
    if (hasByteRange) {
        if (range.location != NSUIntegerMax) {
            range.location = MIN(range.location, fileSize);
            range.length = MIN(range.length, fileSize - range.location);
        } else {
            range.length = MIN(range.length, fileSize);
            range.location = fileSize - range.length;
        }
        if (range.length == 0) {
            return nil;  // TODO: Return 416 status code and "Content-Range: bytes */{file length}" header
        }
    } else {
        range.location = 0;
        range.length = fileSize;
    }
    
    if ((self = [super init])) {
        _path = [path copy];
        _offset = range.location;
        _size = range.length;
        if (hasByteRange) {
            [self setStatusCode:kGCDWebServerHTTPStatusCode_PartialContent];
            [self setValue:[NSString stringWithFormat:@"bytes %lu-%lu/%lu", (unsigned long)_offset, (unsigned long)(_offset + _size - 1), (unsigned long)fileSize] forAdditionalHeader:@"Content-Range"];
            GWS_LOG_DEBUG(@"Using content bytes range [%lu-%lu] for file \"%@\"", (unsigned long)_offset, (unsigned long)(_offset + _size - 1), path);
        }
        
        if (attachment) {
            NSString* fileName = [path lastPathComponent];
            NSData* data = [[fileName stringByReplacingOccurrencesOfString:@"\"" withString:@""] dataUsingEncoding:NSISOLatin1StringEncoding allowLossyConversion:YES];
            NSString* lossyFileName = data ? [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] : nil;
            if (lossyFileName) {
                NSString* value = [NSString stringWithFormat:@"attachment; filename=\"%@\"; filename*=UTF-8''%@", lossyFileName, GCDWebServerEscapeURLString(fileName)];
                [self setValue:value forAdditionalHeader:@"Content-Disposition"];
            } else {
                GWS_DNOT_REACHED();
            }
        }
        
        self.contentType = GCDWebServerGetMimeTypeForExtension([_path pathExtension]);
        self.contentLength = _size;
        self.lastModifiedDate = _NSDateFromTimeSpec(&info.st_mtimespec);
        self.eTag = [NSString stringWithFormat:@"%llu/%li/%li", info.st_ino, info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec];
    }
    return self;
}

- (BOOL)open:(NSError**)error {
    _file = open([_path fileSystemRepresentation], O_NOFOLLOW | O_RDONLY);
    if (_file <= 0) {
        if (error) {
            *error = GCDWebServerMakePosixError(errno);
        }
        return NO;
    }
    if (lseek(_file, _offset, SEEK_SET) != (off_t)_offset) {
        if (error) {
            *error = GCDWebServerMakePosixError(errno);
        }
        close(_file);
        return NO;
    }
    return YES;
}

- (NSData*)readData:(NSError**)error {
    size_t length = MIN((NSUInteger)kStreamFileReadBufferSize, _size);
    NSMutableData* data = [[NSMutableData alloc] initWithLength:length];
    ssize_t result = read(_file, data.mutableBytes, length);
    if (result < 0) {
        if (error) {
            *error = GCDWebServerMakePosixError(errno);
        }
        return nil;
    }
    if (result > 0) {
        [data setLength:result];
        _size -= result;
    }
    [HLSServer bumpLastNetworkActivity];
    return data;
}

- (void)close {
    close(_file);
}

- (NSString*)description {
    NSMutableString* description = [NSMutableString stringWithString:[super description]];
    [description appendFormat:@"\n\n{%@}", _path];
    return description;
}

@end
