using Avalonia;
using Avalonia.Controls;
using Avalonia.Threading;

namespace ConnecTOWin;

public partial class App : Application
{
    private WindowsHost? host;
    private TrayIcon? tray;
    private WindowIcon? waitingIcon;
    private WindowIcon? linkedIcon;

    public override void OnFrameworkInitializationCompleted()
    {
        host = new WindowsHost();
        var window = new StatusWindow(host);
        waitingIcon = TrayImages.Load(false);
        linkedIcon = TrayImages.Load(true);
        tray = new TrayIcon
        {
            Icon = waitingIcon,
            ToolTipText = "connecTO",
            IsVisible = true,
        };
        tray.Clicked += (_, _) => window.Toggle();
        host.Changed += () => Dispatcher.UIThread.Post(Refresh);
        var icons = new TrayIcons { tray };
        TrayIcon.SetIcons(this, icons);
        base.OnFrameworkInitializationCompleted();
    }

    private void Refresh()
    {
        if (host == null || tray == null)
        {
            return;
        }

        tray.Icon = host.IsLinked ? linkedIcon : waitingIcon;
    }
}
