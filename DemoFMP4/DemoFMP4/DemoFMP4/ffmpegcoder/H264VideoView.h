//
//  BebopVideoView.h
//  Arbieye-test2
//
//  Created by morishi on 2016/12/10.
//  Copyright © 2016年 morishi. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface H264VideoView : UIView

- (BOOL)configureDecoder:(id)codec;
- (BOOL)displayFrame:(id)frame;
- (int)throwCurrentStatus;


@end


