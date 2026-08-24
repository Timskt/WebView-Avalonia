using System;
using System.IO;
using System.Runtime.InteropServices;
using Avalonia;
using Avalonia.ReactiveUI;
using WebViewControl;

namespace SampleWebView.Avalonia {

    class Program {
        [STAThread]
        static int Main(string[] args) {
            try {
                PortableRuntime.Initialize();
                return AppBuilder.Configure<App>()
                                 .UsePlatformDetect()
                                 .UseReactiveUI()
                                 .StartWithClassicDesktopLifetime(args);
            } catch (Exception exception) {
                PortableRuntime.ReportStartupFailure(exception);
                return 1;
            }
        }
    }

    internal static class PortableRuntime {
        private const string ProductDirectory = "9n1m-WebView-Avalonia";

        internal static void Initialize() {
            var baseDirectory = Path.GetFullPath(AppContext.BaseDirectory);
            Directory.SetCurrentDirectory(baseDirectory);

            if (OperatingSystem.IsWindows()) {
                ValidateWindowsRuntime(baseDirectory);
            }

            var stateDirectory = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                ProductDirectory);
            var logDirectory = Path.Combine(stateDirectory, "logs");
            Directory.CreateDirectory(logDirectory);

            WebView.Settings.LogFile = Path.Combine(logDirectory, "ceflog.txt");
            WebView.Settings.CachePath = Path.Combine(stateDirectory, "cache");
            WebView.Settings.PersistCache = true;

            File.WriteAllText(
                Path.Combine(logDirectory, "startup-info.txt"),
                $"BaseDirectory={baseDirectory}{Environment.NewLine}" +
                $"CurrentDirectory={Environment.CurrentDirectory}{Environment.NewLine}" +
                $"OS={RuntimeInformation.OSDescription}{Environment.NewLine}" +
                $"Architecture={RuntimeInformation.ProcessArchitecture}{Environment.NewLine}");
        }

        internal static void ReportStartupFailure(Exception exception) {
            var message = "SampleWebView.Avalonia failed to start." + Environment.NewLine + Environment.NewLine + exception;
            var errorPath = Path.Combine(AppContext.BaseDirectory, "portable-startup-error.log");

            try {
                File.WriteAllText(errorPath, message);
            } catch {
                errorPath = Path.Combine(Path.GetTempPath(), "SampleWebView.Avalonia-startup-error.log");
                File.WriteAllText(errorPath, message);
            }

            if (OperatingSystem.IsWindows()) {
                MessageBox(IntPtr.Zero, message + Environment.NewLine + Environment.NewLine + "Log: " + errorPath,
                    "SampleWebView startup error", 0x10);
            } else {
                Console.Error.WriteLine(message);
                Console.Error.WriteLine("Log: " + errorPath);
            }
        }

        private static void ValidateWindowsRuntime(string baseDirectory) {
            var requiredFiles = new[] {
                "libcef.dll",
                "icudtl.dat",
                "resources.pak",
                "v8_context_snapshot.bin",
                Path.Combine("CefGlueBrowserProcess", "9n1m.webview.exe")
            };
            var missingFiles = Array.FindAll(requiredFiles,
                relativePath => !File.Exists(Path.Combine(baseDirectory, relativePath)));
            var localesDirectory = Path.Combine(baseDirectory, "locales");

            if (missingFiles.Length > 0 || !Directory.Exists(localesDirectory) ||
                Directory.GetFiles(localesDirectory, "*.pak").Length == 0) {
                throw new FileNotFoundException(
                    "The portable Demo is incomplete. Extract the complete archive before running it." +
                    Environment.NewLine + "Base directory: " + baseDirectory +
                    Environment.NewLine + "Missing files: " +
                    (missingFiles.Length == 0 ? "none" : string.Join(", ", missingFiles)) +
                    Environment.NewLine + "Locales directory: " + localesDirectory);
            }
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int MessageBox(IntPtr window, string text, string caption, uint type);
    }
}
