# Portable Windows Demo

The Windows Demo is published as a self-contained, directory-independent ZIP.
It includes the application, .NET runtime, CEF runtime, resources, locales and
the `CefGlueBrowserProcess/9n1m.webview.exe` subprocess.

After extracting the complete ZIP, run:

```powershell
.\Run-SampleDemo.ps1
```

or double-click `Run-SampleDemo.cmd`.

The launcher changes the working directory to the extracted application
directory. The application also resolves CEF resources, locales and the browser
subprocess from `AppContext.BaseDirectory`, so it can be started from another
working directory, a shortcut or `Start-Process`.

CEF logs are written to:

```text
%LOCALAPPDATA%\9n1m-WebView-Avalonia\logs\ceflog.txt
```

If required files are missing, startup displays an error and writes
`portable-startup-error.log`. Do not copy only `SampleWebView.Avalonia.exe`;
the complete extracted directory is the deployable product.

Build the portable archive as part of the normal physical build, or create it
from an existing published Demo directory:

```powershell
python .\scripts\create-portable-windows-demo.py `
  --source .\dist\cef-134\win-x64\demo `
  --output .\dist\SampleWebView-Avalonia-portable-win-x64.zip `
  --line 134 `
  --rid win-x64
```

CEF 134 targets Windows 10/11 x64. The Windows 7 compatibility build uses CEF
106 and .NET 6 instead.
