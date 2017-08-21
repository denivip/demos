//
//  BebopVideoView.h
//  Arbieye-test2
//
//  Created by morishi on 2016/12/10.
//  Copyright © 2016年 morishi. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface H264VideoView : UIView

- (long)findNextNALUOffsetIn:(uint8_t *)frame withSize:(long)frameSize startAt:(long)offset;
- (long)feedViewWithH264:(uint8_t *)frame withSize:(long)frameSize;
- (BOOL)waitingForMoreH264;
- (void)resetFeed;
@end


