/* Exercise the production feedback controller with real Metal drawables.
 * Run on an unlocked macOS desktop; this briefly opens a rendering window. */
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#include <unistd.h>
#include <assert.h>
#include <stdatomic.h>
#include "cx_frame_control.m.h"
static atomic_bool finished;
static int failure;
int main(void) {
    @autoreleasepool {
        char directory[]="/private/tmp/coeditor-metal-probe-XXXXXX";
        assert(mkdtemp(directory));setenv("WINEPREFIX",directory,1);
        [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,420,220) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        [window setTitle:@"COEditor 呈现验证"];[window center];
        CAMetalLayer *layer=[CAMetalLayer layer];layer.device=MTLCreateSystemDefaultDevice();
        assert(layer.device);layer.pixelFormat=MTLPixelFormatBGRA8Unorm;layer.drawableSize=CGSizeMake(420,220);
        layer.displaySyncEnabled=YES;layer.maximumDrawableCount=3;
        window.contentView.wantsLayer=YES;window.contentView.layer=layer;
        [window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
            @autoreleasepool {
                id<MTLCommandQueue> queue=[layer.device newCommandQueue];
                NSMutableArray *controls=[NSMutableArray array];
                for (int phase=0;phase<3;++phase) {
                    cx_frame_fps=phase==0 ? 60:120;cx_frame_stats=1;cx_frame_pacing=phase;
                    CXFrameControl *control=[[CXFrameControl alloc] init];
                    [controls addObject:control];
                    double start=CACurrentMediaTime();unsigned frames=0;
                    while(CACurrentMediaTime()-start<3) {
                        @autoreleasepool {
                            [control waitForFrame];
                            id<CAMetalDrawable> drawable=[layer nextDrawable];
                            if(!drawable){failure=1;break;}
                            [control track:drawable size:layer.drawableSize];
                            MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];
                            pass.colorAttachments[0].texture=drawable.texture;
                            pass.colorAttachments[0].loadAction=MTLLoadActionClear;
                            pass.colorAttachments[0].storeAction=MTLStoreActionStore;
                            pass.colorAttachments[0].clearColor=MTLClearColorMake(.1+phase*.1,.2,.35,1);
                            id<MTLCommandBuffer> buffer=[queue commandBuffer];
                            id<MTLRenderCommandEncoder> encoder=[buffer renderCommandEncoderWithDescriptor:pass];[encoder endEncoding];
                            [buffer presentDrawable:drawable];[buffer commit];++frames;
                        }
                    }
                    double seconds=CACurrentMediaTime()-start;
                    printf("phase=%d cap=%d render_rate=%.2f frames=%u\n",phase,cx_frame_fps,frames/seconds,frames);
                    if(frames<20 || frames/seconds>cx_frame_fps*1.05)failure=1;
                    [control release];
                    usleep(150000);
                }
                /* Missing presentation callback must fail open within 100 ms. */
                cx_frame_fps=0;cx_frame_pacing=2;
                CXFrameControl *control=[[CXFrameControl alloc] init];
                id<CAMetalDrawable> abandoned=[layer nextDrawable];
                [control track:abandoned size:layer.drawableSize];
                double start=CACurrentMediaTime();[control waitForFrame];
                double waited=CACurrentMediaTime()-start;
                printf("abandoned drawable wait=%.3f seconds\n",waited);
                if(waited>.25)failure=1;
                [control release];
                atomic_store(&finished,true);
            }
        });
        double deadline=CACurrentMediaTime()+20;
        while(!atomic_load(&finished) && CACurrentMediaTime()<deadline)
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        [window orderOut:nil];
        if(!atomic_load(&finished))return 2;
        NSString *dir=[[NSString stringWithUTF8String:directory] stringByAppendingPathComponent:@"drive_c/.cx-frame-stats"];
        unsigned valid=0;
        for(NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL]){
            NSData *data=[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:file]];
            NSDictionary *s=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            if([s[@"samples"] intValue]>20 && [s[@"mean_ms"] doubleValue]>0){
                ++valid;printf("presented cap=%d mode=%d fps=%.2f p99=%.2fms\n",[s[@"limit_fps"] intValue],[s[@"pacing"] intValue],[s[@"fps"] doubleValue],[s[@"p99_ms"] doubleValue]);
            }
        }
        printf("snapshots=%u result=%s\n",valid,valid>=3 && !failure ? "PASS":"FAIL");
        return valid>=3 && !failure ? 0:1;
    }
}
