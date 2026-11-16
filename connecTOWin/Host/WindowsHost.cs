using System.Diagnostics;
using ConnecTOWin.Protocol;

namespace ConnecTOWin;

public sealed class WindowsHost : IDisposable
{
    private readonly SessionServer server;
    private readonly MdnsAdvertiser? advertiser;
    private readonly Timer timer;
    private bool announcedFailure;

    public WindowsHost()
    {
        var now = DateTime.UtcNow;
        Code = PairingCode.Make(PairingCode.RandomDigits(), now);
        Now = now;
        var screen = new DesktopCapture();
        var input = new SendInputSink();
        CaptureReady = screen.Probe();
        InputReady = input.Available;
        server = new SessionServer(Code, screen, input);
        server.Changed += OnServerChanged;
        try
        {
            server.Start();
            advertiser = new MdnsAdvertiser(Environment.MachineName + " PC", server.Port);
        }
        catch (Exception)
        {
            advertiser = null;
            announcedFailure = true;
        }

        FirewallReady = FirewallRule.Exists();
        timer = new Timer(_ => Tick(), null, TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(1));
        PublishLink();
    }

    public PairingCode Code { get; private set; }

    public DateTime Now { get; private set; }

    public bool CaptureReady { get; }

    public bool InputReady { get; }

    public bool FirewallReady { get; private set; }

    public string LinkLabel { get; private set; } = "Esperando un iPad";

    public bool IsLinked { get; private set; }

    public bool ExtendRequested { get; private set; }

    public bool AnnounceFailed { get; private set; }

    public event Action? Changed;

    public void RegenerateCode()
    {
        Code = PairingCode.Make(PairingCode.RandomDigits(), DateTime.UtcNow);
        Now = DateTime.UtcNow;
        server.UpdateCode(Code);
        Changed?.Invoke();
    }

    public void Forget()
    {
        server.ForgetAll();
        RegenerateCode();
    }

    public void OpenFirewall()
    {
        FirewallRule.Request();
        FirewallReady = FirewallRule.Exists();
        Changed?.Invoke();
    }

    public void Dispose()
    {
        timer.Dispose();
        advertiser?.Dispose();
        server.Dispose();
    }

    private void Tick()
    {
        Now = DateTime.UtcNow;
        if (Now >= Code.ExpiresAt)
        {
            RegenerateCode();
            return;
        }

        var firewall = FirewallRule.Exists();
        if (firewall != FirewallReady)
        {
            FirewallReady = firewall;
        }

        Changed?.Invoke();
    }

    private void OnServerChanged()
    {
        PublishLink();
        Changed?.Invoke();
    }

    private void PublishLink()
    {
        LinkLabel = announcedFailure ? "No se pudo anunciar el PC en la red." : server.LinkLabel;
        AnnounceFailed = announcedFailure;
        IsLinked = server.IsLinked;
        ExtendRequested = server.ExtendRequested;
    }
}

public static class FirewallRule
{
    public const string Name = "connecTO";

    public static bool Exists()
    {
        if (!OperatingSystem.IsWindows())
        {
            return true;
        }

        try
        {
            var output = Run("advfirewall", "firewall show rule name=connecTO");
            if (output.Contains("No rules", StringComparison.OrdinalIgnoreCase)
                || output.Contains("Ninguna regla", StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            return output.Contains("connecTO", StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception)
        {
            return false;
        }
    }

    public static void Request()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        var exe = Environment.ProcessPath;
        if (string.IsNullOrEmpty(exe))
        {
            return;
        }

        var command = $"Remove-NetFirewallRule -Name connecTO -ErrorAction SilentlyContinue; New-NetFirewallRule -DisplayName connecTO -Name connecTO -Direction Inbound -Program '{exe.Replace("'", "''")}' -Action Allow -Profile Private";
        Process.Start(new ProcessStartInfo
        {
            FileName = "powershell",
            Arguments = $"-NoProfile -Command \"Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile -Command {command}'\"",
            UseShellExecute = true,
        });
    }

    private static string Run(string program, string arguments)
    {
        using var process = Process.Start(new ProcessStartInfo
        {
            FileName = "netsh",
            Arguments = program + " " + arguments,
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        });
        if (process == null)
        {
            return "";
        }

        var output = process.StandardOutput.ReadToEnd();
        process.WaitForExit(2000);
        return output;
    }
}
