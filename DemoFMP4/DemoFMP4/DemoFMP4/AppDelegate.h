//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>
#import "Defaults.h"
#import "HLSServer.h"

#define kNotfMessage         @"kNotfMessage"
#define kGDCNetwrokError     @"GCDWriteError"

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;
@property (readonly, strong, nonatomic) NSManagedObjectContext *managedObjectContext;
@property (readonly, strong, nonatomic) NSManagedObjectModel *managedObjectModel;
@property (readonly, strong, nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;

- (void)saveContext;
- (NSURL *)applicationDocumentsDirectory;

@end

