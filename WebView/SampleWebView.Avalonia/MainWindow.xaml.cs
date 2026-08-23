using System;
using System.Drawing;
using System.IO;
using Avalonia.Controls;
using Avalonia.Markup.Xaml;
using WebViewControl;

namespace SampleWebView.Avalonia {

    internal class MainWindow : Window {

        public MainWindow() {
            WebView.Settings.LogFile = Path.Combine(AppContext.BaseDirectory, "ceflog.txt");
            WebView.Settings.BackgroundColor = Color.Bisque;

            // The demo is intentionally safe to run on a developer Mac without
            // granting Chromium access to the user's Keychain. These switches
            // are passed through CefRuntimeLoader to the browser process before
            // CEF is initialized. Production applications can choose their own
            // password-store policy through WebView.Settings.
            WebView.Settings.AddCommandLineSwitch("password-store", "basic");
            WebView.Settings.AddCommandLineSwitch("use-mock-keychain", null);

            AvaloniaXamlLoader.Load(this);

            DataContext = new MainWindowViewModel(this.FindControl<WebView>("webview"));
        }
    }
}
