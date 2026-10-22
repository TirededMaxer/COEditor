/* The separately installed protocol-2 reader is deliberately retained on app
 * updates. Sevoflurane never hosts it or supplies its code-signing identity. */
#import <AppKit/AppKit.h>
#import <IOKit/hid/IOHIDManager.h>
#import <IOKit/hid/IOHIDKeys.h>
#import <IOKit/hidsystem/IOHIDLib.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include "wheel_bridge.h"
#include "wheel_activation.h"
#include <launch.h>
#include <errno.h>
#include "../../tests/wheel_raw.h"
static IOHIDManagerRef manager;
static NSMutableSet *devices;
static struct cx_wheel_bridge *bridge;
static NSString *directory;
static NSString *lastStatus;
static uint64_t reports, lastCheck;
static IOReturn openError;
static NSMutableDictionary<NSNumber *,NSNumber *> *clients;
static NSString *allowedWine;
static BOOL testNoHID;
static uint64_t lastClient, authUntil, lastPrune;
static int requestFD;
static void requests(CFFileDescriptorRef descriptor,CFOptionFlags flags,void *context);
static BOOL acceptedClient(int pid,uint64_t birth) {
    if (!birth || cx_wheel_process_birth(pid)!=birth) return NO;
    if (testNoHID) return YES;
    char path[PROC_PIDPATHINFO_MAXSIZE];
    if (proc_pidpath(pid,path,sizeof(path))<=0) return NO;
    return allowedWine && [[@(path) stringByResolvingSymlinksInPath] isEqualToString:allowedWine];
}
static void status(void) {
    unsigned state = __atomic_load_n(&bridge->state, __ATOMIC_ACQUIRE);
    NSDictionary *data = @{ @"protocol": @2, @"pid": @(getpid()),
        @"state": clients.count ? (testNoHID ? @"test" : @[@"permission-required", @"ready", @"no-device", @"open-error"][state]) : (authUntil ? @"setup":@"idle"),
        @"clients": @(clients.count), @"devices": @(bridge->devices), @"reports": @(reports), @"openError": @(openError),
        @"updated": @([[NSDate date] timeIntervalSince1970]) };
    NSData *json = [NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingSortedKeys error:nil];
    [json writeToFile:[directory stringByAppendingPathComponent:@"status.json"] atomically:YES];
    NSString *summary = [NSString stringWithFormat:@"%@ devices=%u error=%x", data[@"state"], bridge->devices, openError];
    if (![summary isEqualToString:lastStatus]) { NSLog(@"[COEditorWheel] %@", summary); lastStatus = summary; }
}
static bool wheelElement(IOHIDElementRef e) {
    int x,y;
    return macdrv_hid_wheel_delta(IOHIDElementGetUsagePage(e), IOHIDElementGetUsage(e), IOHIDElementIsRelative(e), 0, &x,&y);
}
static void matched(void *c, IOReturn result, void *sender, IOHIDDeviceRef device) {
    if (result || !devices) return;
    CFArrayRef elements = IOHIDDeviceCopyMatchingElements(device, NULL, 0);
    if (!elements) return;
    for (CFIndex i=0;i<CFArrayGetCount(elements);i++) if (wheelElement((IOHIDElementRef)CFArrayGetValueAtIndex(elements,i))) {
        [devices addObject:(__bridge id)device]; break;
    }
    CFRelease(elements);
}
static void removed(void *c, IOReturn result, void *sender, IOHIDDeviceRef device) { [devices removeObject:(__bridge id)device]; }
static void value(void *c, IOReturn result, void *sender, IOHIDValueRef v) {
    if (result || !cx_wheel_live(bridge,cx_wheel_now())) return;
    IOHIDElementRef e=IOHIDValueGetElement(v);
    if (![devices containsObject:(__bridge id)IOHIDElementGetDevice(e)]) return;
    int x,y;
    if (!macdrv_hid_wheel_delta(IOHIDElementGetUsagePage(e),IOHIDElementGetUsage(e),IOHIDElementIsRelative(e),IOHIDValueGetIntegerValue(v),&x,&y) || (!x && !y)) return;
    pid_t pid=NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
    if (clients[@(pid)] && acceptedClient(pid,[clients[@(pid)] unsignedLongLongValue])) { cx_wheel_publish(bridge,pid,x,y,cx_wheel_now()); reports++; }
}
static void stop(void) {
    if (!manager) return;
    IOHIDManagerUnscheduleFromRunLoop(manager,CFRunLoopGetMain(),kCFRunLoopCommonModes);
    IOHIDManagerClose(manager,0); CFRelease(manager); manager=NULL; [devices removeAllObjects];
}
static void requests(CFFileDescriptorRef descriptor,CFOptionFlags flags,void *context) {
    unsigned char bytes[sizeof(struct cx_wheel_request)+1];
    ssize_t n;
    while ((n=recv(requestFD,bytes,sizeof(bytes),MSG_DONTWAIT))>=0) {
        if (n!=sizeof(struct cx_wheel_request)) continue;
        struct cx_wheel_request r;memcpy(&r,bytes,sizeof(r));
        if(r.magic!=CX_WHEEL_REQUEST_MAGIC || r.version!=2 || r.reserved)continue;
        if(r.command==CX_WHEEL_AUTHORIZE) {
            NSString *marker=[directory stringByAppendingPathComponent:@"request-access"];
            if([NSFileManager.defaultManager fileExistsAtPath:marker]) {
                [NSFileManager.defaultManager removeItemAtPath:marker error:nil];
                authUntil=cx_wheel_now()+UINT64_C(120000000000);
                if(!testNoHID) IOHIDRequestAccess(kIOHIDRequestTypeListenEvent);
            }
        } else if(r.command==CX_WHEEL_ATTACH && acceptedClient(r.pid,r.birth)) {
            clients[@(r.pid)]=@(r.birth);lastClient=cx_wheel_now();
        } else if(r.command==CX_WHEEL_DETACH && [clients[@(r.pid)] unsignedLongLongValue]==r.birth) {
            [clients removeObjectForKey:@(r.pid)];lastClient=cx_wheel_now();
        }
    }
    if(descriptor)CFFileDescriptorEnableCallBacks(descriptor,kCFFileDescriptorReadCallBack);
}
static void tick(CFRunLoopTimerRef timer, void *context) {
    uint64_t now=cx_wheel_now();
    if(now-lastPrune>=UINT64_C(250000000)) {
        lastPrune=now;
        for(NSNumber *pid in clients.allKeys)if(!acceptedClient(pid.intValue,[clients[pid] unsignedLongLongValue])) {
            [clients removeObjectForKey:pid];lastClient=now;
        }
    }
    if(authUntil && (now>=authUntil || (!testNoHID && IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)==kIOHIDAccessTypeGranted)))authUntil=0;
    if(!clients.count && !authUntil && now-lastClient>=UINT64_C(1000000000)) {
        /* A queued request remains on launchd's socket and wakes the next reader. */
        __atomic_store_n(&bridge->heartbeat_ns,0,__ATOMIC_RELEASE);
        stop();status();CFRunLoopStop(CFRunLoopGetMain());return;
    }
    if (now-lastCheck >= UINT64_C(1000000000)) {
        lastCheck=now;
        if(testNoHID || !clients.count) {
            stop();bridge->devices=0;__atomic_store_n(&bridge->state,CX_WHEEL_NO_DEVICE,__ATOMIC_RELEASE);
        } else if (IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted) {
            stop(); bridge->devices=0; __atomic_store_n(&bridge->state,CX_WHEEL_DENIED,__ATOMIC_RELEASE);
        } else if (!manager) {
            manager=IOHIDManagerCreate(kCFAllocatorDefault,0);
            /* Vendor-primary USB receivers can still contain relative wheel elements. */
            IOHIDManagerSetDeviceMatching(manager,NULL);
            IOHIDManagerSetInputValueMatchingMultiple(manager,(__bridge CFArrayRef)@[
                @{@kIOHIDElementUsagePageKey:@1,@kIOHIDElementUsageKey:@0x38},
                @{@kIOHIDElementUsagePageKey:@0x0c,@kIOHIDElementUsageKey:@0x238}]);
            IOHIDManagerRegisterDeviceMatchingCallback(manager,matched,NULL);
            IOHIDManagerRegisterDeviceRemovalCallback(manager,removed,NULL);
            IOHIDManagerRegisterInputValueCallback(manager,value,NULL);
            IOHIDManagerScheduleWithRunLoop(manager,CFRunLoopGetMain(),kCFRunLoopCommonModes);
            openError=IOHIDManagerOpen(manager,0);
            if (openError) { stop(); __atomic_store_n(&bridge->state,CX_WHEEL_ERROR,__ATOMIC_RELEASE); }
        }
        status();
    }
    if (manager) {
        bridge->devices=(uint32_t)devices.count;
        __atomic_store_n(&bridge->state,bridge->devices ? CX_WHEEL_READY:CX_WHEEL_NO_DEVICE,__ATOMIC_RELEASE);
    }
    __atomic_store_n(&bridge->heartbeat_ns,now,__ATOMIC_RELEASE);
}
int main(int argc,const char **argv) { @autoreleasepool {
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    testNoHID=getenv("COEDITOR_WHEEL_TEST_NO_HID") && !strcmp(getenv("COEDITOR_WHEEL_TEST_NO_HID"),"1");
    int *fds=NULL;size_t count=0;
    if(launch_activate_socket("WheelRequests",&fds,&count) || count!=1) {free(fds);return 4;}
    requestFD=fds[0];free(fds);fcntl(requestFD,F_SETFL,fcntl(requestFD,F_GETFL)|O_NONBLOCK);
    directory=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/CrossOver/CustomRuntimes/.tuner-support/Wheel"];
    if(testNoHID && getenv("COEDITOR_WHEEL_TEST_DIRECTORY"))directory=@(getenv("COEDITOR_WHEEL_TEST_DIRECTORY"));
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    chmod(directory.fileSystemRepresentation,0700);
    NSString *support=[directory stringByDeletingLastPathComponent];
    NSData *manifest=[NSData dataWithContentsOfFile:[support stringByAppendingPathComponent:@"manifest.json"]];
    NSDictionary *info=manifest ? [NSJSONSerialization JSONObjectWithData:manifest options:0 error:nil]:nil;
    NSString *runtime=info[@"runtime"];
    if(runtime && [runtime.lastPathComponent isEqualToString:runtime])
        allowedWine=[[[support stringByDeletingLastPathComponent] stringByAppendingPathComponent:
            [runtime stringByAppendingPathComponent:@"lib/wine/x86_64-unix/wine"]] stringByResolvingSymlinksInPath];
    NSString *path=[directory stringByAppendingPathComponent:@"wheel-v1.bin"];
    int fd=open(path.fileSystemRepresentation,O_RDWR|O_CREAT|O_NOFOLLOW,0600);
    if(fd<0 || flock(fd,LOCK_EX|LOCK_NB) || ftruncate(fd,sizeof(*bridge))) return 2;
    fchmod(fd,0600);
    bridge=mmap(NULL,sizeof(*bridge),PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
    if(bridge==MAP_FAILED)return 3;
    memset(bridge,0,sizeof(*bridge));bridge->version=1;bridge->pid=getpid();
    __atomic_store_n(&bridge->magic,CX_WHEEL_MAGIC,__ATOMIC_RELEASE);
    devices=[NSMutableSet new];clients=[NSMutableDictionary new];lastClient=cx_wheel_now();
    CFFileDescriptorRef descriptor=CFFileDescriptorCreate(NULL,requestFD,false,requests,NULL);
    CFRunLoopSourceRef source=CFFileDescriptorCreateRunLoopSource(NULL,descriptor,0);
    CFRunLoopAddSource(CFRunLoopGetMain(),source,kCFRunLoopCommonModes);
    CFFileDescriptorEnableCallBacks(descriptor,kCFFileDescriptorReadCallBack);
    requests(NULL,0,NULL);
    CFRunLoopTimerRef timer=CFRunLoopTimerCreate(NULL,CFAbsoluteTimeGetCurrent(),0.02,0,0,tick,NULL);
    CFRunLoopAddTimer(CFRunLoopGetMain(),timer,kCFRunLoopCommonModes);
    CFRunLoopRun();stop();CFFileDescriptorInvalidate(descriptor);CFRelease(source);CFRelease(descriptor);
    CFRelease(timer);close(requestFD);return 0;
}}
