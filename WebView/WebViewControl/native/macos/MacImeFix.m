// WebViewControl Mac IME Fix
// Prevents CEF's global NSEvent monitors from intercepting IME composition
// events that should go to Avalonia controls (like TextBox), which causes
// UI deadlocks during Chinese input on macOS ARM64.
//
// The `__attribute__((constructor))` ensures this runs on dylib load,
// before CEF initializes its own event monitors.

#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

// Return nil to prevent CEF from installing any event monitor.
// This is safe because CefGlue.Avalonia handles keyboard event
// forwarding through Avalonia's input system, not through NSEvent monitors.
static id swizzled_addMonitor(id self, SEL _cmd, NSEventMask mask, id handler) {
#pragma unused(self, _cmd, mask, handler)
    return nil;
}

static void installSwizzle(Class cls, SEL sel) {
    Method method = class_getClassMethod(cls, sel);
    if (!method) return;
    method_setImplementation(method, (IMP)swizzled_addMonitor);
}

__attribute__((constructor))
static void macImeFixInit(void) {
    @autoreleasepool {
        Class nseventClass = NSClassFromString(@"NSEvent");
        if (!nseventClass) return;
        
        installSwizzle(nseventClass,
                       @selector(addLocalMonitorForEventsMatchingMask:handler:));
        installSwizzle(nseventClass,
                       @selector(addGlobalMonitorForEventsMatchingMask:handler:));
        
        NSLog(@"[WebViewControl] Disabled NSEvent monitors to prevent IME deadlock");
    }
}
