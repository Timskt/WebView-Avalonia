using System;
using System.ComponentModel;
using System.Text.Json;
using System.Threading.Tasks;
using Avalonia.Threading;
using System.Reactive;
using ReactiveUI;
using WebViewControl;

namespace SampleWebView.Avalonia {
    class MainWindowViewModel : ReactiveObject {

        private string address;
        private string currentAddress;
        private string codecStatus = "打开 html5test.com 后点击“Check H.264/HEVC”；该检查是浏览器能力预检，不替代真实视频播放验证。";

        public MainWindowViewModel(WebView webview) {
            Address = CurrentAddress = new ResourceUrl(typeof(MainWindowViewModel).Assembly, "Resources", "media-device-test.html").ToString();

            webview.Navigated += (_, _) => _ = CheckCodecsAsync(webview);

            NavigateCommand = ReactiveCommand.Create(() => {
                CurrentAddress = Address;
            });

            CheckCodecsCommand = ReactiveCommand.CreateFromTask(() => CheckCodecsAsync(webview));

            MediaTestCommand = ReactiveCommand.Create(() => {
                CurrentAddress = new ResourceUrl(typeof(MainWindowViewModel).Assembly, "Resources", "media-device-test.html").ToString();
            });

            ShowDevToolsCommand = ReactiveCommand.Create(() => {
                webview.ShowDeveloperTools();
            });

            CutCommand = ReactiveCommand.Create(() => {
                webview.EditCommands.Cut();
            });

            CopyCommand = ReactiveCommand.Create(() => {
                webview.EditCommands.Copy();
            });

            PasteCommand = ReactiveCommand.Create(() => {
                webview.EditCommands.Paste();
            });

            UndoCommand = ReactiveCommand.Create(() => {
                webview.EditCommands.Undo();
            });

            RedoCommand = ReactiveCommand.Create(() => {
                webview.EditCommands.Redo();
            });

            SelectAllCommand = ReactiveCommand.Create(() => {
                webview.EditCommands.SelectAll();
            });

            DeleteCommand = ReactiveCommand.Create(() => {
                webview.EditCommands.Delete();
            });
            
            BackCommand = ReactiveCommand.Create(() => {
                webview.GoBack();
            });
            
            ForwardCommand = ReactiveCommand.Create(() => {
                webview.GoForward();
            });

            PropertyChanged += OnPropertyChanged;
        }

        private void OnPropertyChanged(object sender, PropertyChangedEventArgs e) {
            if (e.PropertyName == nameof(CurrentAddress)) {
                Address = CurrentAddress;
            }
        }

        public string Address {
            get => address;
            set => this.RaiseAndSetIfChanged(ref address, value);
        }

        public string CodecStatus {
            get => codecStatus;
            private set => this.RaiseAndSetIfChanged(ref codecStatus, value);
        }

        private async Task CheckCodecsAsync(WebView webview) {
            try {
                var json = await webview.EvaluateScript<string>("(() => JSON.stringify({h264: document.createElement('video').canPlayType('video/mp4; codecs=\"avc1.42E01E\"'), hevc: document.createElement('video').canPlayType('video/mp4; codecs=\"hvc1.1.6.L93.B0\"'), url: location.href}))()", timeout: TimeSpan.FromSeconds(10));
                if (string.IsNullOrWhiteSpace(json)) return;
                var result = JsonSerializer.Deserialize<CodecResult>(json);
                if (result is null) return;
                await Dispatcher.UIThread.InvokeAsync(() => CodecStatus = $"Codec preflight: H.264={Format(result.h264)}, H.265/HEVC={Format(result.hevc)}\nURL: {result.url}");
            } catch (Exception ex) {
                await Dispatcher.UIThread.InvokeAsync(() => CodecStatus = $"Codec preflight failed: {ex.Message}");
            }
        }

        private static string Format(string value) => string.IsNullOrEmpty(value) ? "unsupported" : value;

        private sealed class CodecResult {
            public string h264 { get; set; }
            public string hevc { get; set; }
            public string url { get; set; }
        }

        public string CurrentAddress {
            get => currentAddress;
            set => this.RaiseAndSetIfChanged(ref currentAddress, value);
        }

        public ReactiveCommand<Unit, Unit> NavigateCommand { get; }

        public ReactiveCommand<Unit, Unit> CheckCodecsCommand { get; }

        public ReactiveCommand<Unit, Unit> MediaTestCommand { get; }

        public ReactiveCommand<Unit, Unit> ShowDevToolsCommand { get; }

        public ReactiveCommand<Unit, Unit> CutCommand { get; }

        public ReactiveCommand<Unit, Unit> CopyCommand { get; }

        public ReactiveCommand<Unit, Unit> PasteCommand { get; }

        public ReactiveCommand<Unit, Unit> UndoCommand { get; }

        public ReactiveCommand<Unit, Unit> RedoCommand { get; }

        public ReactiveCommand<Unit, Unit> SelectAllCommand { get; }

        public ReactiveCommand<Unit, Unit> DeleteCommand { get; }

        public ReactiveCommand<Unit, Unit> BackCommand { get; }
        
        public ReactiveCommand<Unit, Unit> ForwardCommand { get; }
    }
}
