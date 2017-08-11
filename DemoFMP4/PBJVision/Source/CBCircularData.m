//
//  CBCircularData.m
//  DemoFMP4
//
//  Created by IPv6 on 14/07/15.
//  Copyright (c) 2015 DENIVIP Group. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBCircularData.h"

@interface CBCircularData()
@property (strong) NSMutableArray* buffers;
@property (assign) NSUInteger baseOffset;
@property (assign) NSUInteger maxTotalSize;
@property (assign) NSUInteger curTotalSize;
@end

@implementation CBCircularData

- (instancetype)initWithDepth:(NSUInteger)maxBytes {
    if (self = [super init]) {
        self.maxTotalSize = maxBytes;
        [self removeAllUpTo:-1];
    }
    return self;
}

- (NSDate*)getLastModified {
    return self.lastWriteTs;
}

- (void)removeAllUpTo:(NSInteger)lastIdx {
    @synchronized(self.buffers) {
        if(self.buffers == nil){
            self.buffers = [[NSMutableArray alloc] initWithCapacity:100];
        }else{
            if(lastIdx < 0){
                [self.buffers removeAllObjects];
            }else{
                [self.buffers removeObjectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, lastIdx)]];
            }
        }
        self.firstWriteTs = nil;
        self.curTotalSize = 0;
        self.baseOffset = 0;
    }
}

- (NSUInteger)size {
    return self.curTotalSize;
}

- (NSUInteger)sizeCap {
    return self.maxTotalSize;
}

- (NSUInteger)lowOffset {
    return self.baseOffset;
}

- (NSArray*)dataBuffers {
    return self.buffers;
}

- (NSUInteger)writeData:(NSData*)dt {
    NSUInteger buffOffset = self.baseOffset;
    @synchronized(self.buffers) {
        self.lastWriteTs = [NSDate date];
        if(self.firstWriteTs == nil){
            self.firstWriteTs = [NSDate date];
        }
        [self.buffers addObject:dt];
        buffOffset = self.baseOffset+self.curTotalSize;
        self.curTotalSize += [dt length];
        while ([self.buffers count] > 0 && self.curTotalSize > self.maxTotalSize) {
            // removing chunks at the beginning
            NSData* fis = [self.buffers objectAtIndex:0];
            [self.buffers removeObjectAtIndex:0];
            self.curTotalSize -= [fis length];
            self.baseOffset += [fis length];
        }
    }
    return buffOffset;
}

- (NSData*)readCurrentDataUpTo:(NSInteger)lastIdx andReset:(BOOL)andReset {
    if([self size] == 0){
        return [[NSData alloc] init];
    }
    NSMutableData* md = [[NSMutableData alloc] initWithCapacity:[self size]];
    @synchronized(self.buffers) {
        NSInteger maxBlocks2consume = lastIdx;
        for(NSData* block in self.buffers){
            [md appendData:block];
            if(maxBlocks2consume>0){
                maxBlocks2consume--;
                if(maxBlocks2consume == 0){
                    // stop!
                    break;
                }
            }
        }
        if(andReset){
            [self removeAllUpTo:lastIdx];
        }
    }
    return md;
}

- (NSData*)readData:(NSUInteger)offset length:(NSInteger)len {
    NSMutableData* md = [[NSMutableData alloc] initWithCapacity:len];
    if(offset < self.baseOffset){
        return md;
    }
    @synchronized(self.buffers) {
        NSUInteger pos = self.baseOffset;
        for(NSData* block in self.buffers){
            NSUInteger block_len = [block length];
            if(offset >= pos && offset < pos + block_len){
                NSInteger initoffset = offset - pos;
                NSInteger blockend_len = block_len - initoffset;
                if(blockend_len < 0 || initoffset < 0){
                    return nil;
                }
                [md appendBytes:block.bytes + initoffset length:blockend_len];
                len -= blockend_len;
                offset += blockend_len;
                if(len <= 0){
                    [md setLength:md.length - (-len)];
                    break;
                }
            }
            pos += block_len;
        }
    }
    return md;
}

@end
