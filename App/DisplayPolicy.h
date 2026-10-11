#import <UIKit/UIKit.h>
#include <math.h>

// Keep vertical output resolution while matching the actual landscape screen.
static inline CGSize CPFullScreenRenderSize(CGSize screen, CGFloat height) {
    CGFloat wide=MAX(screen.width,screen.height),shortSide=MIN(screen.width,screen.height);
    if(shortSide<=0)return CGSizeZero;
    return CGSizeMake(2*round(wide/shortSide*height/2),height);
}
BOOL CPApplyDisplayPolicy(UIWindow *window, NSError **error);
void CPSetHDRBootstrap(UIWindow *window);
