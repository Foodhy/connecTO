using System.Runtime.InteropServices;

namespace ConnecTOWin;

public readonly record struct MonitorInfo(
    uint Id,
    string Name,
    string DeviceName,
    int X,
    int Y,
    int Width,
    int Height,
    bool Primary)
{
    public Protocol.SharedDisplay AsShared() => new(Id, Name, Width, Height);
}

public static class MonitorCatalog
{
    public static IReadOnlyList<MonitorInfo> Read()
    {
        if (!OperatingSystem.IsWindows())
        {
            return [];
        }

        var found = new List<MonitorInfo>();
        MonitorEnum callback = (IntPtr monitor, IntPtr hdc, ref NativeRect rect, IntPtr data) =>
        {
            var info = new MonitorInfoEx { Size = Marshal.SizeOf<MonitorInfoEx>() };
            if (!GetMonitorInfo(monitor, ref info))
            {
                return true;
            }

            var device = (info.DeviceName ?? "").TrimEnd('\0');
            var id = Number(device);
            var primary = (info.Flags & 1) != 0;
            var width = info.Monitor.Right - info.Monitor.Left;
            var height = info.Monitor.Bottom - info.Monitor.Top;
            var name = primary ? "Pantalla" : $"Pantalla {id}";
            found.Add(new MonitorInfo(id, name, device, info.Monitor.Left, info.Monitor.Top, width, height, primary));
            return true;
        };
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, callback, IntPtr.Zero);
        GC.KeepAlive(callback);
        return found;
    }

    private static uint Number(string device)
    {
        var digits = new string(device.Where(char.IsDigit).ToArray());
        return uint.TryParse(digits, out var number) && number != 0 ? number : 1;
    }

    private delegate bool MonitorEnum(IntPtr monitor, IntPtr hdc, ref NativeRect rect, IntPtr data);

    [DllImport("user32.dll")]
    private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonitorEnum callback, IntPtr data);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfoEx info);

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct MonitorInfoEx
    {
        public int Size;
        public NativeRect Monitor;
        public NativeRect Work;
        public int Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string DeviceName;
    }
}
