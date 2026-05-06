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

        [MethodImpl(MethodImplOptions.NoInlining)]
        public static void Initialize(GlobalSettings settings) {
            if (CefRuntimeLoader.IsLoaded) {
                return;
            }

            if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX)) {
                // Load macOS IME fix dylib before CEF initializes.
                // This swizzles +[NSEvent addLocalMonitorForEventsMatchingMask:handler:]
                // to prevent CEF's global keyboard event monitor from intercepting
                // IME composition events and deadlocking the UI thread.
                LoadMacImeFix();
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
            
            CefRuntimeLoader.Initialize(settings: cefSettings, flags: settings.CommandLineSwitches.ToArray(), customSchemes: customSchemes);

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

        private static void LoadMacImeFix() {
            var dylibName = "libMacImeFix.dylib";

            // Search in output directory first, then in system paths
            var basePath = AppDomain.CurrentDomain.BaseDirectory;
            var dylibPath = Path.Combine(basePath, dylibName);

            if (!File.Exists(dylibPath)) {
                // Try the publish directory
                dylibPath = Path.Combine(basePath, dylibName);
            }

            if (File.Exists(dylibPath)) {
                var handle = dlopen(dylibPath, 1); // RTLD_LAZY = 1
                if (handle != IntPtr.Zero) {
                    return; // __attribute__((constructor)) already ran
                }
            }

            // Fallback: load from the Avalonia project's output or package cache
            // The dylib might be in a different location depending on runtime
            var searchPaths = new[] {
                Path.Combine(basePath, "runtimes", "osx-arm64", "native", dylibName),
                Path.Combine(basePath, "runtimes", "osx", "native", dylibName),
                dylibName, // dlopen will search standard paths
            };

            foreach (var path in searchPaths) {
                if (File.Exists(path)) {
                    dlopen(path, 1);
                    return;
                }
            }
        }

        [DllImport("libSystem.dylib")]
        private static extern IntPtr dlopen(string path, int mode);

    }
}
