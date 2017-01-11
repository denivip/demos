//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CacheFileManager.h"

static int ddLogLevel = LOG_LEVEL_VERBOSE;

@implementation CacheFileManager

+ (instancetype)sharedManager
{
    // singleton initialization
    
    static dispatch_once_t pred = 0;
    __strong static id obj = nil;
    dispatch_once(&pred, ^{
        obj = [[self alloc] init];
    });
    return obj;
}

- (instancetype)init
{
    if (self = [super init]) {
        [self deleteFilesAtPath:[CacheFileManager cachesDirectory]];
    }
    return self;
}

+ (NSString *)cachesDirectory {
    return [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
}

+ (NSString *)cachePathForKey:(NSString*)key {
    NSString *cachesPath = [CacheFileManager cachesDirectory];
    NSString *cacheKeyPath = [cachesPath stringByAppendingPathComponent:key];
    if([[CacheFileManager sharedManager] createDirectoryAtPath:cacheKeyPath]){
        return cacheKeyPath;
    }
    return nil;
}

- (void)deleteFilesAtPath:(NSString *)path
{
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:path];
    NSString *file;
    while ((file = [enumerator nextObject])) {
        NSString *filePath = [path stringByAppendingPathComponent:file];
        NSError *removeError;
        if (![[NSFileManager defaultManager] removeItemAtPath:filePath
                                                        error:&removeError]) {
            DDLogVerbose(@"%s failed to remove: %@", __PRETTY_FUNCTION__, filePath);
        }else{
            DDLogVerbose(@"%s removed: %@", __PRETTY_FUNCTION__, filePath);
        }
    }
}

- (long)cleanupCachesAtPath:(NSString*)path maxAge:(NSTimeInterval)maxAge maxTotalSize:(NSUInteger)maxTotalSize
{
    NSURL *cacheURL = [NSURL fileURLWithPath:path];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *resourceKeys = @[ NSURLContentModificationDateKey, NSURLTotalFileAllocatedSizeKey ];
    NSDirectoryEnumerator *fileEnumerator = [fileManager enumeratorAtURL:cacheURL includingPropertiesForKeys:resourceKeys options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:NULL];
    
    NSDate *expirationDate = [NSDate dateWithTimeIntervalSinceNow:-maxAge];
    NSMutableDictionary *cacheFiles = [NSMutableDictionary dictionary];
    long long currentCacheSize = 0;
    int deletedFiles = 0;
    NSMutableArray *URLsToDelete = [NSMutableArray array];
    for (NSURL *fileURL in fileEnumerator) {
        NSDictionary *resourceValues = [fileURL resourceValuesForKeys:resourceKeys error:NULL];
        
        // Remove files that are older than the expiration date;
        NSDate *modificationDate = resourceValues[NSURLContentModificationDateKey];
        if ([[modificationDate laterDate:expirationDate] isEqualToDate:expirationDate]) {
            [URLsToDelete addObject:fileURL];
            continue;
        }
        
        // Store a reference to this file and account for its total size.
        NSNumber *totalAllocatedSize = resourceValues[NSURLTotalFileAllocatedSizeKey];
        currentCacheSize += [totalAllocatedSize longLongValue];
        [cacheFiles setObject:resourceValues forKey:fileURL];
    }
    
    for (NSURL *fileURL in URLsToDelete) {
        deletedFiles++;
        [fileManager removeItemAtURL:fileURL error:NULL];
    }
    
    if (maxTotalSize > 0 && currentCacheSize > maxTotalSize) {
        NSArray *sortedFiles = [cacheFiles keysSortedByValueWithOptions:0 usingComparator:^NSComparisonResult(NSDictionary *obj1, NSDictionary *obj2) {
            return [(NSDate *)obj1[NSURLContentModificationDateKey] compare:obj2[NSURLContentModificationDateKey]];
        }];
        
        // Delete files until we fall below our desired cache size.
        for (NSURL *fileURL in sortedFiles) {
            if ([fileManager removeItemAtURL:fileURL error:NULL]) {
                deletedFiles++;
                NSDictionary *resourceValues = cacheFiles[fileURL];
                NSNumber *totalAllocatedSize = resourceValues[NSURLTotalFileAllocatedSizeKey];
                currentCacheSize -= [totalAllocatedSize longLongValue];
                if (currentCacheSize < maxTotalSize) {
                    break;
                }
            }
        }
    }
    return deletedFiles;
}

- (unsigned long long)directorySize:(NSString *)folderPath
{
    NSArray *filesArray = [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:folderPath error:nil];
    NSEnumerator *filesEnumerator = [filesArray objectEnumerator];
    NSString *fileName;
    unsigned long long int fileSize = 0;
    
    while (fileName = [filesEnumerator nextObject]) {
        NSDictionary *fileDictionary = [[NSFileManager defaultManager] attributesOfItemAtPath:[folderPath stringByAppendingPathComponent:fileName] error:nil];
        fileSize += [fileDictionary fileSize];
    }
    
    return fileSize;
}

- (NSDictionary *)directorySizes:(NSString *)path
{
    NSMutableDictionary *sizes = [NSMutableDictionary dictionary];
    
    NSArray *subpaths = [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:path error:NULL];
    [subpaths enumerateObjectsUsingBlock:^(NSString *subpath, NSUInteger idx, BOOL *stop) {
        NSString *fullpath = [path stringByAppendingPathComponent:subpath];
        BOOL isDirectory;
        if ([[NSFileManager defaultManager] fileExistsAtPath:fullpath isDirectory:&isDirectory]) {
            if (isDirectory) {
                sizes[subpath] = @([self directorySize:fullpath]);
            }
        }
    }];
    
    return sizes;
}

- (BOOL)createDirectoryAtPath:(NSString *)path {
    @synchronized(self) {
        if (![self fileExistsAtPath:path isDirectory:NULL]) {
            NSError *createError;
            if (![self createDirectoryAtPath:path
                 withIntermediateDirectories:YES
                                  attributes:nil
                                       error:&createError]) {
                return NO;
            }
        }
    }
    
    return YES;
}

@end
