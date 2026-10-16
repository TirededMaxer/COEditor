#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <unistd.h>
static id (*vendor_init)(id,SEL,NSString*);
static NSString *runtime_root(void) { return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/CrossOver/CustomRuntimes/Steam-Optimized-26.3"]; }
static NSString *log_path(void) { return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/CrossOver/Bottles/Steam/drive_c/ProgramData/CrossOverSteamUI/host-shim.log"]; }
static void note(const char *message)
{
    FILE *file=fopen([log_path() fileSystemRepresentation],"a");if(file){fprintf(file,"pid=%d %s\n",getpid(),message);fclose(file);}
}
static id steam_loader_init(id self,SEL selector,NSString *root)
{
    note("native WineLoader using existing patched runtime");
    return vendor_init(self,selector,runtime_root());
}
__attribute__((constructor)) static void install_host_hook(void)
{
    Class cls=objc_getClass("WineLoader");SEL selector=sel_registerName("initWithCrossOverRoot:");
    Method method=cls?class_getInstanceMethod(cls,selector):NULL;
    if(!method){note("WineLoader method unavailable; preserving vendor behavior");return;}
    vendor_init=(void*)method_getImplementation(method);
    method_setImplementation(method,(IMP)steam_loader_init);
    note("Steam launcher loader hook installed");
}
