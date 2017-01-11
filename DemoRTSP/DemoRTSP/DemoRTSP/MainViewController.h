//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "PBJVision.h"
#import "UIButton+Blocks.h"

@interface MainViewController : UIViewController <PBJVisionDelegate>

+(PBJVision *)getPBJVision;
+(void)addLogLine:(NSString*)msg;
@end

