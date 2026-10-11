#include "../compat/FrameTimeline.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    CPFrameTimeline frames={0};CPFrameSetActive(&frames,true);
    CPFrameAdd(&frames,10);CPFrameAdd(&frames,10.033333);CPFrameAdd(&frames,12.033333);
    assert(frames.count==2 && fabs(frames.milliseconds[1]-2000)<.01);
    CPFrameAdd(&frames,11);assert(frames.count==2 && frames.nonmonotonic==1 && frames.last==12.033333);
    CPFrameSetActive(&frames,false);CPFrameAdd(&frames,30);assert(frames.count==0 && frames.last==0);
    CPFrameSetActive(&frames,true);CPFrameAdd(&frames,100);CPFrameAdd(&frames,100.033333);
    assert(frames.count==1 && fabs(frames.milliseconds[0]-33.333)<.01);
    CPFrameSetActive(&frames,true);assert(frames.count==1);
    for(unsigned i=1;i<=650;i++)CPFrameAdd(&frames,100.033333+i*.033333);
    assert(frames.count==600);
    double sum=0;for(unsigned i=0;i<600;i++)sum+=frames.milliseconds[i];
    assert(fabs(sum-19999.8)<.01);
    CPFrameAdd(&frames,NAN);CPFrameAdd(&frames,INFINITY);CPFrameAdd(&frames,0);
    assert(frames.count==600);
    puts("PASS: long foreground hitches, out-of-order callbacks, real background reset, repeated activation, ring wrap and invalid timestamps");
}
