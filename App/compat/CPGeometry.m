#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// macOS Foundation geometry uses the same double-precision ABI as CoreGraphics.
const CGRect NSZeroRect = {{0, 0}, {0, 0}};
const CGPoint NSZeroPoint = {0, 0};
const CGSize NSZeroSize = {0, 0};
BOOL NSEqualSizes(CGSize a, CGSize b) { return CGSizeEqualToSize(a, b); }
BOOL NSEqualRects(CGRect a, CGRect b) { return CGRectEqualToRect(a, b); }
BOOL NSEqualPoints(CGPoint a, CGPoint b) { return CGPointEqualToPoint(a, b); }
BOOL NSPointInRect(CGPoint point, CGRect rect) { return CGRectContainsPoint(rect, point); }
BOOL NSMouseInRect(CGPoint p, CGRect r, BOOL flipped) {
    return p.x >= CGRectGetMinX(r) && p.x < CGRectGetMaxX(r) &&
        (flipped ? p.y >= CGRectGetMinY(r) && p.y < CGRectGetMaxY(r)
                 : p.y > CGRectGetMinY(r) && p.y <= CGRectGetMaxY(r));
}
