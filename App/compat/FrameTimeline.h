#pragma once
#include <stdbool.h>
#include <math.h>

#define CP_FRAME_WINDOW 600
typedef struct {
    double milliseconds[CP_FRAME_WINDOW],last;
    unsigned count,cursor,nonmonotonic,resets;
    bool active;
} CPFrameTimeline;

// Caller supplies synchronization. Only an actual foreground transition resets
// the window: a long foreground interval is a hitch and must remain measurable.
static inline void CPFrameSetActive(CPFrameTimeline *frames,bool active) {
    if(frames->active==active)return;
    frames->active=active;frames->last=0;frames->count=0;frames->cursor=0;frames->resets++;
}
static inline void CPFrameAdd(CPFrameTimeline *frames,double time) {
    if(!frames->active || !isfinite(time) || time<=0)return;
    if(frames->last>0) {
        if(time<=frames->last){frames->nonmonotonic++;return;}
        frames->milliseconds[frames->cursor]=(time-frames->last)*1000;
        frames->cursor=(frames->cursor+1)%CP_FRAME_WINDOW;
        if(frames->count<CP_FRAME_WINDOW)frames->count++;
    }
    frames->last=time;
}
