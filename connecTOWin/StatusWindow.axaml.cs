using Avalonia.Controls;
using Avalonia.Interactivity;
using ConnecTOWin.Protocol;

namespace ConnecTOWin;

public partial class StatusWindow : Window
{
    private readonly WindowsHost host;
    private bool quitting;

    public StatusWindow(WindowsHost host)
    {
        this.host = host;
        InitializeComponent();
        host.Changed += () => Avalonia.Threading.Dispatcher.UIThread.Post(Refresh);
        Deactivated += (_, _) =>
        {
            if (!quitting)
            {
                Hide();
            }
        };
        Refresh();
    }

    public void Toggle()
    {
        if (IsVisible)
        {
            Hide();
            return;
        }

        Refresh();
        Show();
        Activate();
        PositionNearClock();
    }

    protected override void OnClosing(WindowClosingEventArgs e)
    {
        if (!quitting)
        {
            e.Cancel = true;
            Hide();
        }

        base.OnClosing(e);
    }

    private void Refresh()
    {
        var seconds = Math.Max(0, (int)(host.Code.ExpiresAt - host.Now).TotalSeconds);
        CodeText.Text = PairingCode.Grouped(host.Code.Digits);
        ExpiresText.Text = $"Vence en {seconds / 60}:{seconds % 60:00}";
        LinkText.Text = host.LinkLabel;
        CaptureText.Text = host.CaptureReady
            ? "Captura de pantalla activa"
            : "Falta captura de pantalla. Sin eso el iPad no ve el escritorio.";
        InputText.Text = host.InputReady
            ? "Cursor y teclado activos"
            : "Falta el cursor. Sin eso el PC ignora el mando.";
        ExtendText.IsVisible = host.ExtendRequested;
        FirewallButton.IsVisible = !host.FirewallReady;
    }

    private void PositionNearClock()
    {
        var screen = Screens.Primary;
        if (screen == null)
        {
            return;
        }

        var area = screen.WorkingArea;
        var width = (int)(Bounds.Width * screen.Scaling);
        var height = (int)(Bounds.Height * screen.Scaling);
        Position = new Avalonia.PixelPoint(area.Right - width - 12, area.Bottom - height - 12);
    }

    private void NewCode(object? sender, RoutedEventArgs e) => host.RegenerateCode();

    private void Forget(object? sender, RoutedEventArgs e) => host.Forget();

    private void OpenFirewall(object? sender, RoutedEventArgs e) => host.OpenFirewall();

    private void Quit(object? sender, RoutedEventArgs e)
    {
        quitting = true;
        host.Dispose();
        if (Avalonia.Application.Current?.ApplicationLifetime is Avalonia.Controls.ApplicationLifetimes.IClassicDesktopStyleApplicationLifetime desktop)
        {
            desktop.Shutdown();
        }

        Close();
    }
}
