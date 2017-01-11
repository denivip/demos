//  The MIT License (MIT)
//
//  Copyright (c) 2013 Levi Nunnink
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of
//  this software and associated documentation files (the "Software"), to deal in
//  the Software without restriction, including without limitation the rights to
//  use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
//  the Software, and to permit persons to whom the Software is furnished to do so,
//  subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
//  FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
//  COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
//  IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
//  CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

//
//  Created by Levi Nunnink (@a_band) http://culturezoo.com
//  Copyright (C) Droplr Inc. All Rights Reserved
//

#import "SmoothLineView.h"
#import <QuartzCore/QuartzCore.h>

#define DEFAULT_COLOR               [UIColor redColor]
#define DEFAULT_WIDTH               15.0f
#define DEFAULT_BACKGROUND_COLOR    [UIColor clearColor]

static const CGFloat kPointMinDistance = 5.0f;
static const CGFloat kPointMinDistanceSquared = kPointMinDistance * kPointMinDistance;
static const CGFloat kFaderResolution = 0.05;
@interface SmoothLineView ()
@property (nonatomic,assign) CGPoint currentPoint;
@property (nonatomic,assign) CGPoint previousPoint;
@property (nonatomic,assign) CGPoint previousPreviousPoint;
@property (nonatomic,strong) NSMutableArray* paths;//[UIBezierPath bezierPathWithCGPath:path])
@property (nonatomic,strong) NSTimer* fader;
#pragma mark Private Helper function
CGPoint midPoint(CGPoint p1, CGPoint p2);
@end

@implementation SmoothLineView
//{
//@private
//    CGMutablePathRef _path;
//}

#pragma mark UIView lifecycle methods

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    
    if (self) {
        [self initInts];
    }
    
    return self;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    
    if (self) {
        [self initInts];
    }
    
    return self;
}

- (void)initInts {
    // NOTE: do not change the backgroundColor here, so it can be set in IB.
    //_path = CGPathCreateMutable();
    self.clearsContextBeforeDrawing = YES;
    self.paths = [[NSMutableArray alloc] initWithCapacity:10];
    _lineWidth = DEFAULT_WIDTH;
    _lineColor = DEFAULT_COLOR;
    _empty = YES;
    self.fader = [NSTimer scheduledTimerWithTimeInterval:kFaderResolution target:self selector:@selector(fadePath) userInfo:nil repeats:YES];
}

- (void)dealloc {
    //CGPathRelease(_path);
    [self.fader invalidate];
    self.fader = nil;
}

- (void)drawRect:(CGRect)rect {
    // clear rect
    [self.backgroundColor set];
    UIRectFill(rect);
    if([self.paths count] == 0){
        self.empty = YES;
        return;
    }
    // get the graphics context and draw the path
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    //NSArray* sss=@[[UIColor greenColor],[UIColor blueColor],[UIColor whiteColor]];
    //CGContextSetFillColorWithColor(context, ((UIColor*)[sss objectAtIndex:((int)CACurrentMediaTime()%3)]).CGColor);
    //CGContextFillRect(context, self.bounds);
    ////CGContextClearRect(context, CGRectMake(0, 0, width, height));
    //while([self.paths count]>10){
    //    [self.paths removeObjectAtIndex:0];
    //}
    //CGFloat maxpaths = [self.paths count];
    //CGFloat curpath = 0;
    for(NSArray* pair in self.paths){
        UIBezierPath* p = [pair objectAtIndex:0];
        CGFloat p_alpha = [[pair objectAtIndex:1] floatValue];
        UIColor* c = self.lineColor;//[self.lineColor colorWithAlphaComponent:[p_alpha floatValue]];
        CGContextAddPath(context, p.CGPath);//_path
        CGContextSetLineCap(context, kCGLineCapRound);
        CGContextSetLineWidth(context, self.lineWidth*p_alpha);
        CGContextSetStrokeColorWithColor(context, c.CGColor);
        CGContextStrokePath(context);
        //curpath++;
    }
    self.empty = NO;
}

-(void)fadePath {
    BOOL needUpd = NO;
    if(self.fadePerSec > 0){
        for(NSInteger i = [self.paths count]-1; i>=0; i--){
            NSMutableArray* pair = [self.paths objectAtIndex:i];
            float alpha = [[pair objectAtIndex:1] floatValue];
            alpha -= self.fadePerSec*kFaderResolution;
            if(alpha < 0.1){
                needUpd = YES;
                [self.paths removeObjectAtIndex:i];
                continue;
            }
            [pair setObject:@(alpha) atIndexedSubscript:1];
            needUpd = YES;
        }
    }
    if(needUpd){
        [self setNeedsDisplay];
    }
}

#pragma mark private Helper function

CGPoint midPoint(CGPoint p1, CGPoint p2) {
    return CGPointMake((p1.x + p2.x) * 0.5, (p1.y + p2.y) * 0.5);
}

#pragma mark Touch event handlers

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    
    // initializes our point records to current location
    self.previousPoint = [touch previousLocationInView:self];
    self.previousPreviousPoint = [touch previousLocationInView:self];
    self.currentPoint = [touch locationInView:self];
    
    // call touchesMoved:withEvent:, to possibly draw on zero movement
    [self touchesMoved:touches withEvent:event];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    
    CGPoint point = [touch locationInView:self];
    
    // if the finger has moved less than the min dist ...
    CGFloat dx = point.x - self.currentPoint.x;
    CGFloat dy = point.y - self.currentPoint.y;
    
    if ((dx * dx + dy * dy) < kPointMinDistanceSquared) {
        // ... then ignore this movement
        return;
    }
    
    // update points: previousPrevious -> mid1 -> previous -> mid2 -> current
    self.previousPreviousPoint = self.previousPoint;
    self.previousPoint = [touch previousLocationInView:self];
    self.currentPoint = [touch locationInView:self];
    
    CGPoint mid1 = midPoint(self.previousPoint, self.previousPreviousPoint);
    CGPoint mid2 = midPoint(self.currentPoint, self.previousPoint);
    
    // to represent the finger movement, create a new path segment,
    // a quadratic bezier path from mid1 to mid2, using previous as a control point
    CGMutablePathRef subpath = CGPathCreateMutable();
    CGPathMoveToPoint(subpath, NULL, mid1.x, mid1.y);
    CGPathAddQuadCurveToPoint(subpath, NULL,
                              self.previousPoint.x, self.previousPoint.y,
                              mid2.x, mid2.y);
    
    // append the quad curve to the accumulated path so far.
    //CGPathAddPath(_path, NULL, subpath);
    [self.paths addObject:@[[UIBezierPath bezierPathWithCGPath:subpath],@(1.0)].mutableCopy];
    CGPathRelease(subpath);
    
    // compute the rect containing the new segment plus padding for drawn line
    //CGRect bounds = CGPathGetBoundingBox(subpath);
    //CGRect drawBox = CGRectInset(bounds, -2.0 * self.lineWidth, -2.0 * self.lineWidth);
    //[self setNeedsDisplayInRect:drawBox];
    [self setNeedsDisplay];
}

#pragma mark interface

-(void)clear {
    //CGMutablePathRef oldPath = _path;
    //CFRelease(oldPath);
    //_path = CGPathCreateMutable();
    [self.paths removeAllObjects];
    [self setNeedsDisplay];
}

@end

