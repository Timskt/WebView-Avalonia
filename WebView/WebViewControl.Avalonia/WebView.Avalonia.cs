using System;
using System.Runtime.ExceptionServices;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Data;
using Avalonia.Input;
using Avalonia.Threading;

namespace WebViewControl {

    partial class WebView : BaseControl {

        private bool IsInDesignMode => false;

        public static readonly StyledProperty<string> AddressProperty =
            AvaloniaProperty.Register<WebView, string>(nameof(Address), defaultBindingMode: BindingMode.TwoWay);

        public string Address {
            get => GetValue(AddressProperty);
            set => SetValue(AddressProperty, value);
        }

        protected override void OnPropertyChanged(AvaloniaPropertyChangedEventArgs change) {
            base.OnPropertyChanged(change);

            if (change.Property == AddressProperty) {
                InternalAddress = Address;
            }
        }

        partial void ExtraInitialize() {
            VisualChildren.Add(chromium);
            chromium[!FocusableProperty] = this[!FocusableProperty];
            chromium.AddressChanged += (o, address) => ExecuteInUI(() => Address = address);

            // Prevent CEF from intercepting IME text input when WebView is not focused.
            // On macOS, CEF's native NSView can intercept IME composition events
            // even when another control (like TextBox) has focus, causing a deadlock.
            // On Windows ARM64, using handledEventsToo: true causes deadlocks when
            // switching IME in other controls like TextBox, so we use false to only
            // handle events that haven't been handled yet.
            chromium.AddHandler(TextInputEvent, OnChromiumTextInput, handledEventsToo: false);
        }

        private void OnChromiumTextInput(object sender, TextInputEventArgs e) {
            // Only handle the event if WebView or chromium has focus.
            // If another control (like TextBox) has focus, let the event propagate
            // to avoid intercepting IME input and causing deadlocks.
            var focusedElement = TopLevel.GetTopLevel(this)?.FocusManager?.GetFocusedElement();
            if (focusedElement != this && focusedElement != chromium) {
                // Another control has focus, don't intercept the input
                return;
            }

            // CRITICAL FIX for macOS IME deadlock:
            // On macOS, we MUST NOT mark TextInputEvent as handled, even when WebView has focus.
            // The error "messaging the mach port for IMKCFRunLoopWakeUpReliable" occurs because:
            // 1. CEF's NSView implements NSTextInputClient protocol for IME support
            // 2. When e.Handled = true, it prevents the system from completing necessary
            //    IMK state synchronization and cleanup during rapid editing operations
            // 3. This causes the IMK daemon to wait indefinitely for a response that never comes,
            //    resulting in a Mach Port communication timeout and UI freeze
            // 
            // The actual text input is still correctly processed by CEF through:
            // - Lower-level keyboard events (KeyDown/KeyUp) which are not affected
            // - Direct NSTextInputClient methods called by the system on the NSView
            //
            // By letting the TextInputEvent propagate naturally, we allow:
            // - Proper IMK state management during composition
            // - Correct handling of delete/retype sequences
            // - No interference with CEF's native input handling
            //
            // On Windows, setting e.Handled = true is safe because the IME architecture
            // doesn't rely on this event for state synchronization.
#if !__MACOS__
            e.Handled = true;
#endif
        }

        protected override void OnKeyDown(KeyEventArgs e) {
            if (AllowDeveloperTools && e.Key == Key.F12) {
                ToggleDeveloperTools();
                e.Handled = true;
            }
        }

        protected override void OnGotFocus(GotFocusEventArgs e) {
            if (!e.Handled) {
                e.Handled = true;
                base.OnGotFocus(e);

                // use async call to avoid reentrancy, otherwise the webview will fight to get the focus
                Dispatcher.UIThread.Post(() => {
                    if (IsFocused) {
                        chromium.Focus();
                    }
                }, DispatcherPriority.Background);
            }
        }

        protected override void InternalDispose() => Dispose();

        private void ForwardException(ExceptionDispatchInfo exceptionInfo) {
            // TODO
        }

        private T ExecuteInUI<T>(Func<T> action) {
            if (Dispatcher.UIThread.CheckAccess()) {
                return action();
            }
            return Dispatcher.UIThread.InvokeAsync<T>(action).Result;
        }

        private void AsyncExecuteInUI(Action action) {
            if (isDisposing) {
                return;
            }
            // use async call to avoid dead-locks, otherwise if the source action tries to to evaluate js it would block
            Dispatcher.UIThread.InvokeAsync(
                () => {
                    if (!isDisposing) {
                        ExecuteWithAsyncErrorHandling(action);
                    }
                },
                DispatcherPriority.Normal);
        }

        internal void InitializeBrowser(int initialWidth, int initialHeight) {
            chromium.CreateBrowser(initialWidth, initialHeight);
        }

        /// <summary>
        /// Called when the webview is requesting focus. Return false to allow the
        /// focus to be set or true to cancel setting the focus.
        /// <paramref name="isSystemEvent">True if is a system focus event, or false if is a navigation</paramref>
        /// </summary>
        protected virtual bool OnSetFocus(bool isSystemEvent) {
            // VisualRoot can be null when webview is not yet added to the Visual tree
            var focusedElement = TopLevel.GetTopLevel(this)?.FocusManager.GetFocusedElement();
            return !(focusedElement == chromium || focusedElement == this);
        }
    }
}