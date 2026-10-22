/* Native lifecycle fixture, never reads input. Run only against an isolated
 * launchd test job with COEDITOR_WHEEL_TEST_NO_HID=1. */
#include <time.h>
#include "../Sources/WheelBridge/wheel_activation.h"
int main(int argc,char **argv) {
    int seconds=argc>1 ? atoi(argv[1]):3;
    uint64_t birth=cx_wheel_process_birth(getpid());
    if(!birth){perror("proc_pidinfo");return 2;}
    if(argc>2)birth++;
    if(cx_wheel_send_request(CX_WHEEL_ATTACH,getpid(),birth)){perror("wheel attach");return 3;}
    sleep(seconds);
    cx_wheel_send_request(CX_WHEEL_DETACH,getpid(),birth);
    return 0;
}
