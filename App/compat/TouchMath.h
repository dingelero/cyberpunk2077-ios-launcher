#pragma once
#include <math.h>
typedef struct {float x,y;} CPTouchAxis;
static inline CPTouchAxis CPTouchNormalize(double dx,double dy,double radius) {
    if(radius<=0)return (CPTouchAxis){0,0};
    double x=dx/radius,y=-dy/radius,length=hypot(x,y),dead=0.12;
    if(length<=dead)return (CPTouchAxis){0,0};
    double scale=(fmin(1,length)-dead)/(1-dead)/length;
    return (CPTouchAxis){x*scale,y*scale};
}
static inline int CPTouchShouldHide(double now,double lastActivity,unsigned fingers) {
    return fingers==0 && now-lastActivity>=4.0;
}
