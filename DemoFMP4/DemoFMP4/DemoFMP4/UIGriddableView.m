//  Copyright (c) 2017 DENIVIP Group. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "UIGriddableView.h"

@interface UIGriddableView () {
    BOOL grid;
    UIColor* borderColor;
}
@end

@implementation UIGriddableView

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
    }
    return self;
}

- (void)showBorder:(UIColor*)color {
    if(color != nil){
        self.layer.borderColor = color.CGColor;
        self.layer.borderWidth = 1.0f;
        return;
    }
    self.layer.borderColor = [UIColor clearColor].CGColor;
    self.layer.borderWidth = 0.0f;
}

- (void)showGrid:(BOOL)onoff {
    grid = onoff;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    if(grid){
        CGContextRef context = UIGraphicsGetCurrentContext();
        CGContextSetStrokeColorWithColor(context, [UIColor whiteColor].CGColor);
        CGContextSetLineWidth(context, 1.0f);
        
        CGContextMoveToPoint(context, 0.0f, rect.size.height*0.33);
        CGContextAddLineToPoint(context, rect.size.width, rect.size.height*0.33);
        
        CGContextMoveToPoint(context, 0.0f, rect.size.height*0.66);
        CGContextAddLineToPoint(context, rect.size.width, rect.size.height*0.66);
        
        CGContextMoveToPoint(context, rect.size.width*0.33, 0.0);
        CGContextAddLineToPoint(context, rect.size.width*0.33, rect.size.height);

        CGContextMoveToPoint(context, rect.size.width*0.66, 0.0);
        CGContextAddLineToPoint(context, rect.size.width*0.66, rect.size.height);
        
        CGContextStrokePath(context);
    }
}

@end
