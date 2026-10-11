#pragma once
#include "TouchMath.h"
#include <stdint.h>
#include <string.h>
typedef enum {CPTouchNone,CPTouchMove,CPTouchLook,CPTouchButton,CPTouchEdit,CPTouchIgnored} CPTouchRole;
typedef struct {
    uintptr_t identifier;
    CPTouchRole role;
    int control;
    double originX,originY,lastX,lastY;
} CPTouchContact;
typedef struct {CPTouchContact contacts[10];uintptr_t move,look;} CPTouchRouter;
static inline CPTouchContact *CPTouchFind(CPTouchRouter *r,uintptr_t identifier) {
    for(unsigned i=0;i<10;i++)if(r->contacts[i].identifier==identifier && identifier)return &r->contacts[i];return NULL;
}
static inline CPTouchContact *CPTouchBegin(CPTouchRouter *r,uintptr_t identifier,CPTouchRole role,int control,double x,double y) {
    if(!identifier || CPTouchFind(r,identifier))return NULL;
    if((role==CPTouchMove && r->move) || (role==CPTouchLook && r->look))role=CPTouchIgnored;
    for(unsigned i=0;i<10;i++)if(!r->contacts[i].identifier) {
        CPTouchContact *c=&r->contacts[i];*c=(CPTouchContact){identifier,role,control,x,y,x,y};
        if(role==CPTouchMove)r->move=identifier;if(role==CPTouchLook)r->look=identifier;return c;
    }return NULL;
}
static inline void CPTouchEnd(CPTouchRouter *r,uintptr_t identifier) {
    CPTouchContact *c=CPTouchFind(r,identifier);if(!c)return;
    if(r->move==identifier)r->move=0;if(r->look==identifier)r->look=0;memset(c,0,sizeof(*c));
}
static inline CPTouchAxis CPTouchMovement(CPTouchContact *c,double x,double y,double radius) {
    return CPTouchNormalize(x-c->originX,y-c->originY,radius);
}
typedef struct {double x,y;} CPTouchDelta;
static inline CPTouchDelta CPTouchRelativeLook(CPTouchContact *c,double x,double y,double sensitivity,int invertY) {
    if(!isfinite(x) || !isfinite(y) || !isfinite(sensitivity))return (CPTouchDelta){0,0};
    CPTouchDelta delta={(x-c->lastX)*sensitivity,(y-c->lastY)*sensitivity*(invertY?-1:1)};
    c->lastX=x;c->lastY=y;return delta;
}
