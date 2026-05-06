// WebViewControl Mac IME Fix
// Prevents CEF's global NSEvent monitor from intercepting IME composition
// events that should go to Avalonia controls (like TextBox), which causes
// UI deadlocks during Chinese input on macOS ARM64.
//
// The `__attribute__((constructor))` ensures this runs before CEF
// initializes its own event monitors.

#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

static id (*original_addLocalMonitor)(id, SEL, NSEventMask, id);
static id (*original_addGlobalMonitor)(id, SEL, NSEventMask, id);

// Return nil to prevent CEF from installing any event monitor.
// This is safe because CEF only uses the monitor to forward keyboard
// events to the renderer, and CefGlue.Avalonia handles keyboard
// forwarding through Avalonia's input system instead.
static id swizzled_addMonitor(id self, SEL _cmd, NSEventMask mask, id handler) {
    // Don't call original - return nil to effectively disable the monitor.
    // CEF will think the monitor was "installed" but no events will be
    // intercepted, allowing the Avalonia TextBox to handle IME normally.
    return nil;
}

static void swizzleMethod(Class cls, SEL sel, IMP newImp, IMP* origImp) {
    Method method = class_getClassMethod(cls, sel);
    if (!method) return;
    *origImp = method_getImplementation(method);
    method_setImplementation(method, newImp);
}

__attribute__((constructor))
static void macImeFixInit(void) {
    Class nseventClass = NSClassFromString(@"NSEvent");
    if (!nseventClass) return;
    
    // Swizzle both local and global event monitors
    swizzleMethod(nseventClass,
                  @selector(addLocalMonitorForEventsMatchingMask:handler:),
                  (IMP)swizzled_addMonitor,
                  &original_addLocalMonitor);
    
    swizzleMethod(nseventClass,
                  @selector(addGlobalMonitorForEventsMatchingMask:handler:),
                  (IMP)swizzled_addMonitor,
                  &original_addGlobalMonitor);
    
    NSLog(@"[WebViewControl] Disabled NSEvent monitors to prevent IME deadlock");
}
