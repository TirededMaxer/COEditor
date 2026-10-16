#import <AppKit/AppKit.h>
#include <stdio.h>
#include <math.h>
#include "mouse_fraction.h"
static int failures;
#define CHECK(c,s) do {printf("%s %s\n",(c)?"PASS":"FAIL",s);if(!(c))failures++;} while(0)
int main(void){@autoreleasepool {
 double remainder=0,total=0;long output=0;
 for(int i=0;i<10000;i++){double d=(i%13-6)*0.071;total+=d;output+=macdrv_take_fraction(&remainder,d);}
 CHECK(fabs(total-output-remainder)<1e-9,"fractional motion conserved across 10000 reports with direction changes");
 CHECK(fabs(remainder)<1,"remaining subpixel motion stays below one output unit");
 remainder=0;output=0;for(int i=0;i<1000;i++)output+=macdrv_take_fraction(&remainder,0.0625);
 CHECK(output==62&&fabs(remainder-0.5)<1e-12,"small smooth-scroll increments accumulate instead of disappearing");
 double rx=0,ry=0;int x=0,y=0;for(int i=0;i<80;i++){x+=macdrv_take_fraction(&rx,0.125);y+=macdrv_take_fraction(&ry,-0.25);}
 CHECK(x==10&&y==-20,"diagonal axes preserve independent signs and totals");
 CGEventRef cg=CGEventCreateMouseEvent(NULL,kCGEventMouseMoved,CGPointMake(200,200),kCGMouseButtonLeft);
 CGEventSetDoubleValueField(cg,kCGMouseEventDeltaX,3);CGEventSetDoubleValueField(cg,kCGMouseEventDeltaY,-6);
 CGEventSetDoubleValueField(cg,kCGEventUnacceleratedPointerMovementX,8);CGEventSetDoubleValueField(cg,kCGEventUnacceleratedPointerMovementY,-9);
 NSEvent *event=[NSEvent eventWithCGEvent:cg];
 printf("native delta %.6f %.6f; raw %.6f %.6f\n",event.deltaX,event.deltaY,CGEventGetDoubleValueField(cg,kCGEventUnacceleratedPointerMovementX),CGEventGetDoubleValueField(cg,kCGEventUnacceleratedPointerMovementY));
 CHECK(fabs(event.deltaX-3)<1e-9&&fabs(event.deltaY+6)<1e-9,"AppKit conversion uses processed mouse deltas rather than raw fields");CFRelease(cg);
 cg=CGEventCreateScrollWheelEvent(NULL,kCGScrollEventUnitPixel,1,1);

 event=[NSEvent eventWithCGEvent:cg];
 CHECK(event.hasPreciseScrollingDeltas,"pixel scrolling retains precise-scroll classification");
 CHECK(fabs(event.scrollingDeltaY-1)<1e-9,"native pixel-scroll value survives AppKit conversion");CFRelease(cg);
 printf("RESULT failures=%d\n",failures);return failures?1:0;
}}
