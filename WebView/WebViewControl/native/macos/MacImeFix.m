// WebViewControl Mac IME Fix
// Prevents CEF's NSView from interfering with IME composition on macOS,
// which causes UI deadlocks during Chinese/Japanese input when using
// CEF WebView alongside other Avalonia text controls (like TextBox).
//
// All swizzles are performed in macImeFixPostInit() (called from C# after
// CefRuntimeLoader.Initialize) rather than in the dylib constructor, because
// swizzling NSEvent monitors before CEF init causes a __NSGenericDeallocHandler
// crash in CEF's ObjC runtime initialization.
//
// In OSR mode on macOS, CEF's RenderWidgetHostViewCocoa implements
// NSTextInputClient but does NOT need to be firstResponder because keyboard
// input is forwarded through Avalonia's event system via CefKeyEvent messages.

#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

static id swizzled_addMonitor(id self, SEL _cmd, NSEventMask mask, id handler) {
#pragma unused(self, _cmd, mask, handler)
    return nil;
}

static BOOL swizzled_acceptsFirstResponder_noop(id self, SEL _cmd) {
#pragma unused(self, _cmd)
    return NO;
}

static BOOL swizzled_hasMarkedText_noop(id self, SEL _cmd) {
#pragma unused(self, _cmd)
    return NO;
}

static void swizzled_insertText_noop(id self, SEL _cmd, id text, NSRange replacementRange) {
#pragma unused(self, _cmd, text, replacementRange)
}

static void swizzled_setMarkedText_noop(id self, SEL _cmd, id string, NSRange selectedRange, NSRange replacementRange) {
#pragma unused(self, _cmd, string, selectedRange, replacementRange)
}

static void swizzled_unmarkText_noop(id self, SEL _cmd) {
#pragma unused(self, _cmd)
}

static NSArray *swizzled_validAttributesForMarkedText_noop(id self, SEL _cmd) {
#pragma unused(self, _cmd)
    return @[];
}

static NSAttributedString *swizzled_attributedSubstringForProposedRange_noop(id self, SEL _cmd, NSRange range, NSRangePointer actualRange) {
#pragma unused(self, _cmd, range)
    if (actualRange) *actualRange = NSMakeRange(NSNotFound, 0);
    return nil;
}

static NSRect swizzled_firstRectForCharacterRange_noop(id self, SEL _cmd, NSRange range, NSRangePointer actualRange) {
#pragma unused(self, _cmd, range)
    if (actualRange) *actualRange = NSMakeRange(NSNotFound, 0);
    return NSZeroRect;
}

static NSUInteger swizzled_characterIndexForPoint_noop(id self, SEL _cmd, NSPoint point) {
#pragma unused(self, _cmd, point)
    return NSNotFound;
}

static void swizzled_doCommandBySelector_noop(id self, SEL _cmd, SEL selector) {
#pragma unused(self, _cmd, selector)
}

static void installSwizzle(Class cls, SEL sel, IMP newImpl) {
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) return;
    if (class_getMethodImplementation(cls, sel) == newImpl) return;
    method_setImplementation(method, newImpl);
}

__attribute__((constructor))
static void macImeFixInit(void) {
    @autoreleasepool {
        NSLog(@"[WebViewControl] macImeFixInit: loaded");
    }
}

__attribute__((visibility("default")))
void macImeFixPostInit(void) {
    @autoreleasepool {
        NSLog(@"[WebViewControl] macImeFixPostInit: applying IME fixes...");

        // Phase 1: Disable CEF's NSEvent keyboard monitors to prevent
        // them from intercepting IME composition events.
        // Must be done AFTER CEF init to avoid __NSGenericDeallocHandler crash.
        Class nseventClass = NSClassFromString(@"NSEvent");
        if (nseventClass) {
            installSwizzle(nseventClass, @selector(addLocalMonitorForEventsMatchingMask:handler:), (IMP)swizzled_addMonitor);
            installSwizzle(nseventClass, @selector(addGlobalMonitorForEventsMatchingMask:handler:), (IMP)swizzled_addMonitor);
            NSLog(@"[WebViewControl] Swizzled NSEvent monitors");
        }

        // Phase 2: Neutralize CEF's RenderWidgetHostViewCocoa which implements
        // NSTextInputClient. In OSR mode this view doesn't need to handle IME,
        // but it can still become firstResponder and intercept IME events,
        // causing deadlocks when a TextBox is also present.
        Class rwhvcClass = objc_lookUpClass("RenderWidgetHostViewCocoa");
        if (rwhvcClass) {
            NSLog(@"[WebViewControl] Neutralizing RenderWidgetHostViewCocoa NSTextInputClient");

            installSwizzle(rwhvcClass, @selector(acceptsFirstResponder), (IMP)swizzled_acceptsFirstResponder_noop);
            installSwizzle(rwhvcClass, @selector(hasMarkedText), (IMP)swizzled_hasMarkedText_noop);
            installSwizzle(rwhvcClass, @selector(insertText:replacementRange:), (IMP)swizzled_insertText_noop);
            installSwizzle(rwhvcClass, @selector(setMarkedText:selectedRange:replacementRange:), (IMP)swizzled_setMarkedText_noop);
            installSwizzle(rwhvcClass, @selector(unmarkText), (IMP)swizzled_unmarkText_noop);
            installSwizzle(rwhvcClass, @selector(validAttributesForMarkedText), (IMP)swizzled_validAttributesForMarkedText_noop);
            installSwizzle(rwhvcClass, @selector(attributedSubstringForProposedRange:actualRange:), (IMP)swizzled_attributedSubstringForProposedRange_noop);
            installSwizzle(rwhvcClass, @selector(firstRectForCharacterRange:actualRange:), (IMP)swizzled_firstRectForCharacterRange_noop);
            installSwizzle(rwhvcClass, @selector(characterIndexForPoint:), (IMP)swizzled_characterIndexForPoint_noop);
            installSwizzle(rwhvcClass, @selector(doCommandBySelector:), (IMP)swizzled_doCommandBySelector_noop);
        } else {
            NSLog(@"[WebViewControl] RenderWidgetHostViewCocoa not found");
        }

        NSLog(@"[WebViewControl] macImeFixPostInit complete");
    }
}
