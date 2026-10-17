#include <assert.h>
#include <stdio.h>
#include "cx_frame_control.h"
int main(void)
{
    struct cx_frame_clock clock = {0};
    assert(cx_frame_deadline(&clock, 10, 120) == 10);
    clock.last_start = 10;
    assert(fabs(cx_frame_deadline(&clock, 10.001, 120) - (10 + 1.0/120)) < 1e-9);
    assert(cx_frame_deadline(&clock, 11, 120) == 11); /* no catch-up burst */
    assert(cx_frame_deadline(&clock, 10.001, 0) == 10.001);
    for (int i=0; i<400; ++i) cx_frame_record(&clock, 20 + i/120.0);
    struct cx_frame_summary s=cx_frame_summarize(&clock);
    assert(s.count==399 && fabs(s.fps-120)<1e-6 && fabs(s.p99_ms-1000.0/120)<1e-6);
    cx_frame_record(&clock, NAN); cx_frame_record(&clock, 0);
    assert(clock.count==400);
    /* Callback delivery may be out of order or duplicate the same display time. */
    cx_frame_record(&clock,20+398.0/120);s=cx_frame_summarize(&clock);assert(s.count==399);
    cx_frame_record(&clock,40);cx_frame_record(&clock,40.05);
    s=cx_frame_summarize(&clock);assert(s.count==1 && fabs(s.fps-20)<1e-6);
    for(int i=2;i<700;++i)cx_frame_record(&clock,40+i*.05);
    s=cx_frame_summarize(&clock);assert(s.count==511 && fabs(s.fps-20)<1e-6);
    puts("PASS: frame cap deadline, no catch-up bursts, actual presentation intervals, callback ordering, pause reset and bounded samples");
}
