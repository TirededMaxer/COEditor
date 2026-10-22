/* The separately installed protocol-1 reader is deliberately retained on app
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
#include "../../tests/wheel_raw.h"
static IOHIDManagerRef manager;
static NSMutableSet *devices;
static struct cx_wheel_bridge *bridge;
static NSString *directory;
static NSString *lastStatus;
static uint64_t reports, lastCheck;
static IOReturn openError;
static void status(void) {
    unsigned state = __atomic_load_n(&bridge->state, __ATOMIC_ACQUIRE);
    NSDictionary *data = @{ @"protocol": @1, @"pid": @(getpid()),
        @"state": @[@"permission-required", @"ready", @"no-device", @"open-error"][state],
        @"devices": @(bridge->devices), @"reports": @(reports), @"openError": @(openError),
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
    if (pid > 0) { cx_wheel_publish(bridge,pid,x,y,cx_wheel_now()); reports++; }
}
static void stop(void) {
    if (!manager) return;
    IOHIDManagerUnscheduleFromRunLoop(manager,CFRunLoopGetMain(),kCFRunLoopCommonModes);
    IOHIDManagerClose(manager,0); CFRelease(manager); manager=NULL; [devices removeAllObjects];
}
static void tick(CFRunLoopTimerRef timer, void *context) {
    uint64_t now=cx_wheel_now();
    if (now-lastCheck >= UINT64_C(1000000000)) {
        lastCheck=now;
        NSString *request=[directory stringByAppendingPathComponent:@"request-access"];
        if ([NSFileManager.defaultManager fileExistsAtPath:request]) {
            [NSFileManager.defaultManager removeItemAtPath:request error:nil];
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent);
        }
        if (IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted) {
            stop(); bridge->devices=0; __atomic_store_n(&bridge->state,CX_WHEEL_DENIED,__ATOMIC_RELEASE);
        } else if (!manager) {
            manager=IOHIDManagerCreate(kCFAllocatorDefault,0);
            /* Match all HID devices, then accept only actual relative wheel elements.
             * Some USB receivers advertise a vendor-defined primary collection. */
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
    directory=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/CrossOver/CustomRuntimes/.tuner-support/Wheel"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    chmod(directory.fileSystemRepresentation,0700);
    NSString *path=[directory stringByAppendingPathComponent:@"wheel-v1.bin"];
    int fd=open(path.fileSystemRepresentation,O_RDWR|O_CREAT|O_NOFOLLOW,0600);
    if(fd<0 || flock(fd,LOCK_EX|LOCK_NB) || ftruncate(fd,sizeof(*bridge))) return 2;
    bridge=mmap(NULL,sizeof(*bridge),PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
    if(bridge==MAP_FAILED)return 3;
    memset(bridge,0,sizeof(*bridge));bridge->version=1;bridge->pid=getpid();
    __atomic_store_n(&bridge->magic,CX_WHEEL_MAGIC,__ATOMIC_RELEASE);
    devices=[NSMutableSet new];
    CFRunLoopTimerRef timer=CFRunLoopTimerCreate(NULL,CFAbsoluteTimeGetCurrent(),0.02,0,0,tick,NULL);
    CFRunLoopAddTimer(CFRunLoopGetMain(),timer,kCFRunLoopCommonModes);
    CFRunLoopRun(); stop(); return 0;
}}
