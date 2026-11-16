using System.Runtime.InteropServices;

namespace ConnecTOWin;

static class ComApartment
{
    public static void Ensure()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        CoInitializeEx(IntPtr.Zero, 0);
    }

    [DllImport("ole32.dll")]
    private static extern int CoInitializeEx(IntPtr reserved, uint model);
}
