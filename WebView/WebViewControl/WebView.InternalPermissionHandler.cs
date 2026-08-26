using Xilium.CefGlue;

namespace WebViewControl {

    partial class WebView {

        private sealed class InternalPermissionHandler : CefPermissionHandler {

            private readonly GlobalSettings settings;

            public InternalPermissionHandler(GlobalSettings settings) {
                this.settings = settings;
            }

            protected override bool OnRequestMediaAccessPermission(
                CefBrowser browser,
                CefFrame frame,
                string requestingOrigin,
                CefMediaAccessPermissionTypes requestedPermissions,
                CefMediaAccessCallback callback) {
                using (callback) {
                    var allowedPermissions = CefMediaAccessPermissionTypes.None;

                    if (settings.EnableMediaStream) {
                        allowedPermissions |= CefMediaAccessPermissionTypes.DeviceAudioCapture;
                        allowedPermissions |= CefMediaAccessPermissionTypes.DeviceVideoCapture;
                    }

                    if (settings.EnableDesktopCapture) {
                        allowedPermissions |= CefMediaAccessPermissionTypes.DesktopAudioCapture;
                        allowedPermissions |= CefMediaAccessPermissionTypes.DesktopVideoCapture;
                    }

                    if ((requestedPermissions & ~allowedPermissions) != 0) {
                        callback.Cancel();
                        return true;
                    }

                    callback.Continue(requestedPermissions);
                    return true;
                }
            }
        }
    }
}
