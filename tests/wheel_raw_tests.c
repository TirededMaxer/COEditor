#include <stdio.h>
#include "wheel_raw.h"
static int failures, checks;
#define CHECK(c, s) do { checks++; if(!(c)) failures++; printf("%s %s\n",(c)?"PASS":"FAIL",s); } while(0)
int main(void)
{
 int x,y;
 CHECK(macdrv_hid_wheel_delta(1,0x38,true,1,&x,&y)&&x==0&&y==120,"one vertical hardware detent produces 120 Windows units");
 CHECK(macdrv_hid_wheel_delta(1,0x38,true,-1,&x,&y)&&y==-120,"reverse physical detent preserves direction");
 CHECK(macdrv_hid_wheel_delta(1,0x38,true,4,&x,&y)&&y==480,"coalesced four-detent report keeps all four");
 CHECK(macdrv_hid_wheel_delta(0x0c,0x238,true,2,&x,&y)&&x==240&&y==0,"horizontal wheel maps to Windows positive-right units");
 CHECK(!macdrv_hid_wheel_delta(1,0x30,true,20,&x,&y),"pointer X movement is excluded");
 CHECK(!macdrv_hid_wheel_delta(1,0x31,true,20,&x,&y),"pointer Y movement is excluded");
 CHECK(!macdrv_hid_wheel_delta(7,4,true,1,&x,&y),"keyboard input is excluded");
 CHECK(!macdrv_hid_wheel_delta(1,0x38,false,1,&x,&y),"absolute controls are excluded");
 CHECK(macdrv_hid_wheel_delta(1,0x38,true,0,&x,&y)&&x==0&&y==0,"idle report cannot generate a wheel step");
 CHECK(!macdrv_hid_wheel_delta(1,0x38,true,INT64_MAX,&x,&y),"invalid oversized reports cannot overflow");
 printf("RESULT checks=%d failures=%d\n",checks,failures);return failures?1:0;
}
