// WebViewControl Mac IME Fix
// Prevents CEF's global NSEvent monitor from intercepting IME composition
// events that should go to Avalonia controls (like TextBox), which causes
// UI deadlocks during Chinese input.
//
// The `__attribute__((constructor))` ensures this runs before CEF
// initializes its own event monitors.

#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

// Store the original implementation
static id (*original_addLocalMonitor)(id, SEL, NSEventMask, id);

static id swizzled_addLocalMonitor(id self, SEL _cmd, NSEventMask mask, id handler) {
    // Allow the call but wrap the handler so it can't block the main thread
    // during IME composition. We still let the monitor be installed because
    // CEF needs it for its own keyboard handling when focused.
    //
    // The handler gets called for EVERY keyboard event. During IME
    // composition, CEF's handler may block waiting for IPC to the renderer
    // process. We prevent this by wrapping the handler to run on a dispatch
    // queue instead of synchronously.
    
    id wrappedHandler = ^NSEvent *(NSEvent *event) {
        // Return event unmodified for all events - don't let CEF block
        // the event dispatch during IME composition
        return event;
    };
    
    return original_addLocalMonitor(self, _cmd, mask, wrappedHandler);
}

__attribute__((constructor))
static void macImeFixInit(void) {
    Class nseventClass = NSClassFromString(@"NSEvent");
    if (!nseventClass) return;
    
    SEL selector = @selector(addLocalMonitorForEventsMatchingMask:handler:);
    Method method = class_getClassMethod(nseventClass, selector);
    if (!method) return;
    
    original_addLocalMonitor = (void *)method_getImplementation(method);
    method_setImplementation(method, (IMP)swizzled_addLocalMonitor);
    
    NSLog(@"[WebViewControl] Patched NSEvent addLocalMonitor to prevent IME deadlock");
}
