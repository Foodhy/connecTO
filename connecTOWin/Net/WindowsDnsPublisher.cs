using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;

namespace ConnecTOWin;

sealed class WindowsDnsPublisher : IDisposable
{
    private readonly RegisterComplete callback;
    private readonly IntPtr request;
    private readonly IntPtr instance;
    private bool registered;

    private WindowsDnsPublisher(IntPtr instance, IntPtr request, RegisterComplete callback)
    {
        this.instance = instance;
        this.request = request;
        this.callback = callback;
        registered = true;
    }

    public static bool TryStart(string instanceLabel, int port, out WindowsDnsPublisher? publisher)
    {
        publisher = null;
        if (!OperatingSystem.IsWindows() || port is < 1 or > ushort.MaxValue)
        {
            return false;
        }

        var address = FirstAddress();
        if (address == null)
        {
            return false;
        }

        var ip = Marshal.AllocHGlobal(4);
        var key = Marshal.StringToHGlobalUni("plat");
        var value = Marshal.StringToHGlobalUni("win");
        var keys = Marshal.AllocHGlobal(IntPtr.Size);
        var values = Marshal.AllocHGlobal(IntPtr.Size);
        IntPtr created = IntPtr.Zero;
        IntPtr request = IntPtr.Zero;
        RegisterComplete? complete = null;
        try
        {
            Marshal.WriteInt32(ip, BitConverter.ToInt32(address.GetAddressBytes(), 0));
            Marshal.WriteIntPtr(keys, key);
            Marshal.WriteIntPtr(values, value);
            created = DnsServiceConstructInstance(
                $"{instanceLabel}._connecto._tcp.local",
                $"{instanceLabel}.local",
                ip,
                IntPtr.Zero,
                (ushort)port,
                0,
                0,
                1,
                keys,
                values);
            if (created == IntPtr.Zero)
            {
                return false;
            }

            var done = new ManualResetEventSlim(false);
            var status = 1u;
            complete = (code, _, _) =>
            {
                status = code;
                done.Set();
            };
            request = Marshal.AllocHGlobal(Marshal.SizeOf<DNS_SERVICE_REGISTER_REQUEST>());
            var registration = new DNS_SERVICE_REGISTER_REQUEST
            {
                Version = 1,
                pServiceInstance = created,
                pRegisterCompletionCallback = Marshal.GetFunctionPointerForDelegate(complete),
            };
            Marshal.StructureToPtr(registration, request, false);
            var started = DnsServiceRegister(request, IntPtr.Zero);
            if (started != 0 && started != 997)
            {
                return false;
            }

            done.Wait(TimeSpan.FromSeconds(2));
            if (!done.IsSet || status != 0)
            {
                DnsServiceDeRegister(request, IntPtr.Zero);
                return false;
            }

            publisher = new WindowsDnsPublisher(created, request, complete);
            created = IntPtr.Zero;
            request = IntPtr.Zero;
            return true;
        }
        catch (Exception)
        {
            return false;
        }
        finally
        {
            if (created != IntPtr.Zero)
            {
                DnsServiceFreeInstance(created);
            }

            if (request != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(request);
            }

            Marshal.FreeHGlobal(values);
            Marshal.FreeHGlobal(keys);
            Marshal.FreeHGlobal(value);
            Marshal.FreeHGlobal(key);
            Marshal.FreeHGlobal(ip);
            GC.KeepAlive(complete);
        }
    }

    public void Dispose()
    {
        if (!registered)
        {
            return;
        }

        registered = false;
        try
        {
            DnsServiceDeRegister(request, IntPtr.Zero);
            DnsServiceFreeInstance(instance);
        }
        catch (Exception)
        {
        }

        Marshal.FreeHGlobal(request);
        GC.KeepAlive(callback);
    }

    private static IPAddress? FirstAddress()
    {
        foreach (var adapter in System.Net.NetworkInformation.NetworkInterface.GetAllNetworkInterfaces())
        {
            if (adapter.OperationalStatus != System.Net.NetworkInformation.OperationalStatus.Up
                || adapter.NetworkInterfaceType == System.Net.NetworkInformation.NetworkInterfaceType.Loopback)
            {
                continue;
            }

            foreach (var unicast in adapter.GetIPProperties().UnicastAddresses)
            {
                if (unicast.Address.AddressFamily == AddressFamily.InterNetwork && !IPAddress.IsLoopback(unicast.Address))
                {
                    return unicast.Address;
                }
            }
        }

        return null;
    }

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate void RegisterComplete(uint status, IntPtr context, IntPtr instance);

    [StructLayout(LayoutKind.Sequential)]
    private struct DNS_SERVICE_REGISTER_REQUEST
    {
        public uint Version;
        public uint InterfaceIndex;
        public IntPtr pServiceInstance;
        public IntPtr pRegisterCompletionCallback;
        public IntPtr pQueryContext;
        public IntPtr hCredentials;
        public int unicastEnabled;
    }

    [DllImport("dnsapi.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr DnsServiceConstructInstance(
        string serviceName,
        string hostName,
        IntPtr ip4,
        IntPtr ip6,
        ushort port,
        ushort priority,
        ushort weight,
        uint propertyCount,
        IntPtr keys,
        IntPtr values);

    [DllImport("dnsapi.dll")]
    private static extern void DnsServiceFreeInstance(IntPtr instance);

    [DllImport("dnsapi.dll")]
    private static extern uint DnsServiceRegister(IntPtr request, IntPtr cancel);

    [DllImport("dnsapi.dll")]
    private static extern uint DnsServiceDeRegister(IntPtr request, IntPtr cancel);
}
