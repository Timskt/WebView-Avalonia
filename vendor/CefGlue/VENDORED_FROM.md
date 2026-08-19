# Vendored CefGlue source

This directory vendors OutSystems/CefGlue branch `5249` at commit:

```text
393f0fb4f218e1a0f15e79055eb86ab4193a79a2
```

It is intentionally kept on the CEF 106 API surface for the parent project's
Windows 7 compatibility requirement. Local changes add Avalonia 11 support,
Linux runtime packaging, six-RID subprocess publishing, and rename only the
browser subprocess assembly/executable to `9n1m.webview`. The C# namespaces
remain `Xilium.CefGlue.BrowserProcess` for source compatibility.
