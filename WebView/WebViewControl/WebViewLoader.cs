using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using Xilium.CefGlue;
using Xilium.CefGlue.Common;
using Xilium.CefGlue.Common.Shared;

namespace WebViewControl {

    internal static class WebViewLoader {

        private static string[] CustomSchemes { get; } = new[] {
            ResourceUrl.LocalScheme,
            ResourceUrl.EmbeddedScheme,
            ResourceUrl.CustomScheme,
            Uri.UriSchemeHttp,
            Uri.UriSchemeHttps
        };

        private static GlobalSettings globalSettings;
        private static IntPtr macImeFixHandle;

        [MethodImpl(MethodImplOptions.NoInlining)]
        public static void Initialize(GlobalSettings settings) {
            if (CefRuntimeLoader.IsLoaded) {
                return;
            }

            if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX)) {
                // Load macOS IME fix dylib before CEF initializes.
                // Phase 1 (constructor): Swizzles NSEvent monitors and NSWindow makeFirstResponder:
                // Phase 2 (macImeFixPostInit): Neutralizes CEF's NSView NSTextInputClient methods
                macImeFixHandle = LoadMacImeFix();
            }

            globalSettings = settings;

            var cefSettings = new CefSettings {
                LogSeverity = string.IsNullOrWhiteSpace(settings.LogFile) ? CefLogSeverity.Disable : (settings.EnableErrorLogOnly ? CefLogSeverity.Error : CefLogSeverity.Verbose),
                LogFile = settings.LogFile,
                UncaughtExceptionStackSize = 100, // enable stack capture
                CachePath = settings.CachePath, // enable cache for external resources to speedup loading
                WindowlessRenderingEnabled = settings.OsrEnabled || RuntimeInformation.IsOSPlatform(OSPlatform.OSX),
                RemoteDebuggingPort = settings.GetRemoteDebuggingPort(),
                UserAgent = settings.UserAgent,
                BackgroundColor = new CefColor((uint)settings.BackgroundColor.ToArgb())
            };

            var customSchemes = CustomSchemes.Select(s => new CustomScheme() {
                SchemeName = s,
                SchemeHandlerFactory = new SchemeHandlerFactory()
            }).ToArray();

            settings.AddCommandLineSwitch("enable-experimental-web-platform-features", null);
            
            if (settings.EnableVideoAutoplay) {
                settings.AddCommandLineSwitch("autoplay-policy", "no-user-gesture-required");
            }

            if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX)) {
                // Combine with CEF's internal --disable-features=FirstPartySets
                // to also disable TextInputClient which is the OOP IME handling
                // that causes deadlocks on macOS during composition.
                settings.AddCommandLineSwitch("disable-features", "FirstPartySets,TextInputClient");
                
                // Disable GPU rendering to prevent GPU sync deadlocks during IME
                settings.AddCommandLineSwitch("disable-gpu", null);
                settings.AddCommandLineSwitch("disable-gpu-compositing", null);
            }

            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows) && 
                RuntimeInformation.ProcessArchitecture == Architecture.Arm64) {
                // On Windows ARM64, disable TextInputClient to prevent IME deadlocks
                // when switching input methods while WebView is present but not focused.
                // This fixes the issue where switching to Chinese IME causes the app to freeze.
                settings.AddCommandLineSwitch("disable-features", "TextInputClient");
            }

            if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX)) {
                // Append our feature to disable, so it combines with CEF's
                // internal --disable-features=FirstPartySets instead of overwriting.
                // We set a custom flag that our build target will handle.
                Environment.SetEnvironmentVariable("WEBVIEW_MAC_IME_FIX", "1");
            }
            
            CefRuntimeLoader.Initialize(settings: cefSettings, flags: settings.CommandLineSwitches.ToArray(), customSchemes: customSchemes);

            // Phase 2: After CEF init, neutralize CEF's NSView classes that implement
            // NSTextInputClient. Delayed to allow CEF's NSView classes to fully initialize.
            if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX) && macImeFixHandle != IntPtr.Zero) {
                System.Threading.Tasks.Task.Run(async () => {
                    await System.Threading.Tasks.Task.Delay(2000);
                    try {
                        CallMacImeFixPostInit();
                    } catch {
                        // Non-critical - best effort
                    }
                });
            }

            AppDomain.CurrentDomain.ProcessExit += delegate { Cleanup(); };
        }

        /// <summary>
        /// Release all resources and shutdown web view
        /// </summary>
        [DebuggerNonUserCode]
        public static void Cleanup() {
            CefRuntime.Shutdown(); // must shutdown cef to free cache files (so that cleanup is able to delete files)

            if (globalSettings.PersistCache) {
                return;
            }

            try {
                var dirInfo = new DirectoryInfo(globalSettings.CachePath);
                if (dirInfo.Exists) {
                    dirInfo.Delete(true);
                }
            } catch (UnauthorizedAccessException) {
                // ignore
            } catch (IOException) {
                // ignore
            }
        }

        private static IntPtr LoadMacImeFix() {
            var dylibName = "libMacImeFix.dylib";
            var basePath = AppDomain.CurrentDomain.BaseDirectory;

            // Search paths in order of preference:
            // 1. Output directory (where .NET SDK copies native runtime assets)
            // 2. Runtime-specific native directories (NuGet package resolution)
            // 3. Standard system dlopen search
            var searchPaths = new List<string>();

            // Primary: output directory
            searchPaths.Add(Path.Combine(basePath, dylibName));

            // Fallback: runtime identifier-specific native directories
            var rids = RuntimeInformation.ProcessArchitecture == Architecture.Arm64
                ? new[] { "osx-arm64", "osx" }
                : new[] { "osx-x64", "osx" };
            foreach (var rid in rids) {
                searchPaths.Add(Path.Combine(basePath, "runtimes", rid, "native", dylibName));
            }

            // Standard dlopen search (last resort)
            searchPaths.Add(dylibName);

            foreach (var path in searchPaths) {
                if (File.Exists(path)) {
                    var handle = dlopen(path, 1); // RTLD_LAZY = 1
                    if (handle != IntPtr.Zero) {
                        return handle; // __attribute__((constructor)) already ran
                    }
                }
            }

            return IntPtr.Zero;
        }

        private static void CallMacImeFixPostInit() {
            // Phase 2: Call macImeFixPostInit() to scan for and neutralize
            // CEF's NSView classes that implement NSTextInputClient.
            // This must be called AFTER CefRuntimeLoader.Initialize() because
            // CEF's ObjC classes are registered when libcef.dylib is loaded.
            var symbolPtr = dlsym(macImeFixHandle, "macImeFixPostInit");
            if (symbolPtr != IntPtr.Zero) {
                var postInit = (MacImeFixPostInitDelegate)Marshal.GetDelegateForFunctionPointer(
                    symbolPtr, typeof(MacImeFixPostInitDelegate));
                postInit();
            }
        }

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate void MacImeFixPostInitDelegate();

        [DllImport("libSystem.dylib")]
        private static extern IntPtr dlopen(string path, int mode);

        [DllImport("libSystem.dylib")]
        private static extern IntPtr dlsym(IntPtr handle, string symbol);

    }
}
