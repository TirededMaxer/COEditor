/* Socket-activated lifecycle protocol 2. Same wire layout on arm64 / x86_64.
 * launchd owns the listener while no reader process is running. */
#ifndef CX_WHEEL_ACTIVATION_H
#define CX_WHEEL_ACTIVATION_H
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>
#include <libproc.h>
#include <sys/socket.h>
#include <sys/un.h>
#define CX_WHEEL_REQUEST_MAGIC UINT64_C(0x4358575245513032)
enum { CX_WHEEL_ATTACH=1, CX_WHEEL_DETACH=2, CX_WHEEL_AUTHORIZE=3 };
struct cx_wheel_request { uint64_t magic; uint32_t version, command; int32_t pid; uint32_t reserved; uint64_t birth; };
_Static_assert(sizeof(struct cx_wheel_request)==32,"wheel activation ABI");
static inline uint64_t cx_wheel_process_birth(int pid) {
    struct proc_bsdinfo info;
    if (proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&info,sizeof(info)) != sizeof(info) || info.pbi_uid != getuid()) return 0;
    return info.pbi_start_tvsec * UINT64_C(1000000) + info.pbi_start_tvusec;
}
static inline bool cx_wheel_game_program(const char *name) {
    static const char *excluded[]={
        "steam.exe","steamwebhelper.exe","steamservice.exe","gameoverlayui.exe",
        "steamerrorreporter.exe","steamerrorreporter64.exe","explorer.exe",
        "gldriverquery.exe","gldriverquery64.exe","vulkandriverquery.exe","vulkandriverquery64.exe",
        "steamxboxutil.exe","steamxboxutil64.exe","fossilize-replay.exe","fossilize-replay64.exe",
        "x64launcher.exe","x86launcher.exe","WriteMiniDump.exe","steam_monitor.exe",
        "secure_desktop_capture.exe","drivers.exe","hardwareupdater.exe","steamsysinfo.exe",
        "wineboot.exe","winedevice.exe","services.exe","svchost.exe","conhost.exe",
        "cmd.exe","reg.exe","rundll32.exe","control.exe","msiexec.exe","wermgr.exe"
    };
    if (!name || strlen(name)<5 || strcasecmp(name+strlen(name)-4,".exe")) return false;
    for (unsigned i=0;i<sizeof(excluded)/sizeof(*excluded);i++) if (!strcasecmp(name,excluded[i])) return false;
    return true;
}
static inline int cx_wheel_send_request(uint32_t command, int pid, uint64_t birth) {
    struct sockaddr_un address={0};
    const char *home=getenv("HOME");
    if (!home) return -1;
    int n=snprintf(address.sun_path,sizeof(address.sun_path),"%s/Library/Application Support/COEditor/wheel.sock",home);
    if(n<0 || n>=(int)sizeof(address.sun_path))return -1;
    address.sun_family=AF_UNIX;address.sun_len=sizeof(address);
    int fd=socket(AF_UNIX,SOCK_DGRAM,0);if(fd<0)return -1;
    struct cx_wheel_request request={CX_WHEEL_REQUEST_MAGIC,2,command,pid,0,birth};
    ssize_t sent=sendto(fd,&request,sizeof(request),MSG_DONTWAIT,(struct sockaddr *)&address,sizeof(address));
    close(fd);return sent==sizeof(request) ? 0:-1;
}
#endif
