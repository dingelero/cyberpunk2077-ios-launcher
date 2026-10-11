#import <UIKit/UIKit.h>
#import <GameController/GameController.h>
void CPAttachTouchControls(UIWindow *window);
NSDictionary *CPTouchControlsReport(void);
BOOL CPIsTouchController(GCController *controller);
GCController *CPTouchNativeController(void);
NSArray<GCController *> *CPTouchGameControllers(void);
void CPTouchControlsGuestStopped(void);
void CPTouchControlsPointerCaptureChanged(void);
