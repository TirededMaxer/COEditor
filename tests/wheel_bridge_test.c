#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include "../Sources/WheelBridge/wheel_bridge.h"
#define CHECK(c) do {if(!(c)){fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#c);return 1;}}while(0)
int main(void) {
    struct cx_wheel_bridge b={0}; struct cx_wheel_event e; uint64_t c=0,now=UINT64_C(5000000000);
    CHECK(sizeof(e)==32 && sizeof(b)==8232);
    CHECK(!cx_wheel_live(&b,now));
    b.magic=CX_WHEEL_MAGIC;b.version=1;b.state=CX_WHEEL_READY;b.devices=1;b.heartbeat_ns=now;
    CHECK(cx_wheel_live(&b,now));
    b.state=CX_WHEEL_DENIED;CHECK(!cx_wheel_live(&b,now));
    b.state=CX_WHEEL_ERROR;CHECK(!cx_wheel_live(&b,now));
    b.state=CX_WHEEL_READY;b.devices=0;CHECK(!cx_wheel_live(&b,now));
    b.devices=1;CHECK(!cx_wheel_live(&b,now+CX_WHEEL_LEASE_NS));
    CHECK(!cx_wheel_live(&b,now-1));
    cx_wheel_publish(&b,10,0,120,now);cx_wheel_publish(&b,11,0,-120,now);
    CHECK(cx_wheel_next(&b,&c,10,now,&e) && e.y==120);
    CHECK(!cx_wheel_next(&b,&c,10,now,&e)); /* one delivery, no duplicate */
    c=b.sequence;cx_wheel_publish(&b,10,0,-120,now); /* focus resumed cursor */
    CHECK(cx_wheel_next(&b,&c,10,now,&e) && e.y==-120);
    c=0;CHECK(!cx_wheel_next(&b,&c,10,now+CX_WHEEL_LEASE_NS,&e)); /* no replay after wake */
    CHECK(!cx_wheel_claimed(0,now,now)); /* open device alone cannot suppress native */
    CHECK(cx_wheel_claimed(now,now-100,now+100)); /* native first, physical arrived during deferral */
    CHECK(cx_wheel_claimed(now,now+100,now+200)); /* smoothing tail */
    CHECK(!cx_wheel_claimed(now,now+CX_WHEEL_TAIL_NS,now+CX_WHEEL_TAIL_NS));
    c=0;for(int i=0;i<300;i++)cx_wheel_publish(&b,10,i,120,now);
    int n=0;while(cx_wheel_next(&b,&c,10,now,&e))n++;CHECK(n==CX_WHEEL_CAPACITY);
    memset(&b,0,sizeof(b));cx_wheel_publish(&b,10,0,120,now);
    CHECK(!cx_wheel_next(&b,&c,10,now,&e)); /* new epoch starts from new cursor */
    c=0;CHECK(cx_wheel_next(&b,&c,10,now,&e));
    puts("PASS: wire layout, permissions, heartbeat expiry, unplug, PID routing, single delivery, focus, stale events, native claims, overflow and restart");return 0;
}
