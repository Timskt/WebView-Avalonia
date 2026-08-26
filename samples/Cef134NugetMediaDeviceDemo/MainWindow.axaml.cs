using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Text;
using Avalonia.Controls;
using Avalonia.Markup.Xaml;
using Avalonia.Threading;
using WebViewControl;

namespace Cef134NugetMediaDeviceDemo;

public sealed partial class MainWindow : Window
{
    private readonly LocalTestServer server = new();
    private WebView browser = null!;

    public MainWindow()
    {
        WebView.Settings.LogFile = Path.Combine(AppContext.BaseDirectory, "cef-media-device.log");
        WebView.Settings.CachePath = Path.Combine(AppContext.BaseDirectory, "cef-cache");
        WebView.Settings.EnableMediaStream = true;
        WebView.Settings.EnableGpuAcceleration = true;
        WebView.Settings.EnableHardwareVideoDecoding = true;
        WebView.Settings.EnableHardwareVideoEncoding = true;

        AvaloniaXamlLoader.Load(this);
        browser = this.FindControl<WebView>("Browser")!;
        browser.WebViewInitialized += OnWebViewInitialized;
        browser.Navigated += OnNavigated;
        server.ResultReceived += OnResultReceived;
        server.Start();
        SetStatus($"WebViewControl-Avalonia 3.134.178-codecs.11\nWaiting for CEF browser initialization...");
        Closed += (_, _) => server.Dispose();
    }

    private void OnWebViewInitialized()
    {
        browser.Address = server.Url;
        SetStatus($"Loading {server.Url}\nThe page stays open for manual device checks.");
    }

    private async void OnNavigated(string url, string frameName)
    {
        if (!string.Equals(url, server.Url, StringComparison.OrdinalIgnoreCase) ||
            !Environment.GetCommandLineArgs().Contains("--autorun", StringComparer.OrdinalIgnoreCase))
            return;

        await Task.Delay(750);
        await browser.EvaluateScript<bool>("document.getElementById('microphone').click(); true");
        await Task.Delay(2000);
        await browser.EvaluateScript<bool>("document.getElementById('camera').click(); true");
    }

    private async void OnResultReceived(string json)
    {
        try
        {
            await File.WriteAllTextAsync(Path.Combine(AppContext.BaseDirectory, "media-device-result.json"), json, Encoding.UTF8);
            await Dispatcher.UIThread.InvokeAsync(() => SetStatus($"Latest result saved to media-device-result.json\n{Summarize(json)}"));
        }
        catch (Exception exception)
        {
            await Dispatcher.UIThread.InvokeAsync(() => SetStatus($"Unable to save media device result: {exception.Message}"));
        }
    }

    private void SetStatus(string text)
    {
        var status = this.FindControl<TextBlock>("Status");
        if (status != null)
            status.Text = text;
    }

    private static string Summarize(string json)
    {
        try
        {
            using var document = System.Text.Json.JsonDocument.Parse(json);
            var devices = document.RootElement.GetProperty("devices");
            var counts = devices.EnumerateArray().GroupBy(device => device.GetProperty("kind").GetString()).Select(group => $"{group.Key}={group.Count()}");
            return $"devices: {string.Join(", ", counts)}";
        }
        catch
        {
            return "Result received.";
        }
    }
}

internal sealed class LocalTestServer : IDisposable
{
    private readonly HttpListener listener = new();
    private CancellationTokenSource? stop;

    public event Action<string>? ResultReceived;

    public string Url { get; private set; } = string.Empty;

    public void Start()
    {
        if (stop != null)
            return;

        var port = GetFreePort();
        Url = $"http://127.0.0.1:{port}/";
        listener.Prefixes.Add(Url);
        listener.Start();
        stop = new CancellationTokenSource();
        _ = ServeAsync(stop.Token);
    }

    private async Task ServeAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            HttpListenerContext context;
            try
            {
                context = await listener.GetContextAsync();
            }
            catch when (cancellationToken.IsCancellationRequested)
            {
                return;
            }
            catch
            {
                continue;
            }

            if (context.Request.HttpMethod.Equals("POST", StringComparison.OrdinalIgnoreCase) && context.Request.Url?.AbsolutePath == "/result")
            {
                using var reader = new StreamReader(context.Request.InputStream, Encoding.UTF8);
                var json = await reader.ReadToEndAsync(cancellationToken);
                context.Response.StatusCode = 204;
                context.Response.Close();
                ResultReceived?.Invoke(json);
                continue;
            }

            var bytes = ReadHtml();
            context.Response.ContentType = "text/html; charset=utf-8";
            context.Response.ContentLength64 = bytes.Length;
            await context.Response.OutputStream.WriteAsync(bytes, cancellationToken);
            context.Response.Close();
        }
    }

    public void Dispose()
    {
        stop?.Cancel();
        listener.Close();
        stop?.Dispose();
        stop = null;
    }

    private static byte[] ReadHtml()
    {
        const string resourceName = "Cef134NugetMediaDeviceDemo.Resources.media-device-test.html";
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException($"Embedded resource not found: {resourceName}");
        using var memory = new MemoryStream();
        stream.CopyTo(memory);
        return memory.ToArray();
    }

    private static int GetFreePort()
    {
        using var tcpListener = new TcpListener(IPAddress.Loopback, 0);
        tcpListener.Start();
        return ((IPEndPoint)tcpListener.LocalEndpoint).Port;
    }
}
