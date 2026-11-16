using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;

namespace ConnecTOWin;

public sealed class MdnsAdvertiser : IDisposable
{
    private readonly UdpClient socket;
    private readonly byte[] announcement;
    private readonly CancellationTokenSource lifetime = new();
    private readonly string instanceLabel;

    public MdnsAdvertiser(string instanceName, int port)
    {
        instanceLabel = Sanitize(instanceName);
        var host = Sanitize(Environment.MachineName);
        if (string.IsNullOrEmpty(host))
        {
            host = "connecto";
        }

        announcement = Build(instanceLabel, host, port, Addresses());
        socket = new UdpClient(AddressFamily.InterNetwork);
        socket.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
        try
        {
            socket.Client.Bind(new IPEndPoint(IPAddress.Any, 5353));
            socket.JoinMulticastGroup(IPAddress.Parse("224.0.0.251"));
        }
        catch (SocketException)
        {
            socket.Client.Bind(new IPEndPoint(IPAddress.Any, 0));
        }

        socket.Client.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.MulticastTimeToLive, 255);
        var token = lifetime.Token;
        Task.Run(() => Announce(token));
        Task.Run(() => Listen(token));
    }

    public void Dispose()
    {
        lifetime.Cancel();
        socket.Dispose();
    }

    private async Task Announce(CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            Send();
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(8), token);
            }
            catch (OperationCanceledException)
            {
                return;
            }
        }
    }

    private async Task Listen(CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            try
            {
                var result = await socket.ReceiveAsync(token);
                if (IsQueryForUs(result.Buffer))
                {
                    Send();
                }
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (ObjectDisposedException)
            {
                return;
            }
            catch (SocketException)
            {
                return;
            }
        }
    }

    private void Send()
    {
        try
        {
            socket.Send(announcement, announcement.Length, new IPEndPoint(IPAddress.Parse("224.0.0.251"), 5353));
        }
        catch (SocketException)
        {
        }
        catch (ObjectDisposedException)
        {
        }
    }

    private bool IsQueryForUs(byte[] packet)
    {
        if (packet.Length < 12 || (packet[2] & 0x80) != 0)
        {
            return false;
        }

        var needle = Encoding.ASCII.GetBytes("_connecto");
        for (var index = 0; index + needle.Length <= packet.Length; index++)
        {
            if (packet.AsSpan(index, needle.Length).SequenceEqual(needle))
            {
                return true;
            }
        }

        return false;
    }

    private static byte[] Build(string instance, string host, int port, IReadOnlyList<IPAddress> addresses)
    {
        var writer = new DnsWriter();
        var answers = 2 + addresses.Count;
        writer.Header(0, 0x8400, 0, (ushort)answers, 0, 1);
        writer.Record("_connecto._tcp.local", 12, 1, 120, () => writer.Name($"{instance}._connecto._tcp.local"));
        writer.Record($"{instance}._connecto._tcp.local", 33, 0x8001, 120, () =>
        {
            writer.U16(0);
            writer.U16(0);
            writer.U16((ushort)port);
            writer.Name($"{host}.local");
        });
        foreach (var address in addresses)
        {
            var bytes = address.GetAddressBytes();
            writer.Record($"{host}.local", 1, 0x8001, 120, () => writer.Bytes(bytes));
        }

        writer.Record($"{instance}._connecto._tcp.local", 16, 0x8001, 120, () =>
        {
            var text = Encoding.ASCII.GetBytes("plat=win");
            writer.Byte((byte)text.Length);
            writer.Bytes(text);
        });
        return writer.ToArray();
    }

    private static List<IPAddress> Addresses()
    {
        var found = new List<IPAddress>();
        foreach (var adapter in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (adapter.OperationalStatus != OperationalStatus.Up || adapter.NetworkInterfaceType == NetworkInterfaceType.Loopback)
            {
                continue;
            }

            foreach (var address in adapter.GetIPProperties().UnicastAddresses)
            {
                if (address.Address.AddressFamily == AddressFamily.InterNetwork && !IPAddress.IsLoopback(address.Address))
                {
                    found.Add(address.Address);
                }
            }
        }

        return found.Count == 0 ? [IPAddress.Parse("127.0.0.1")] : found;
    }

    private static string Sanitize(string value)
    {
        var cleaned = new string(value.Select(character => character is '.' or '_' ? '-' : character).ToArray()).Trim();
        if (cleaned.Length > 40)
        {
            cleaned = cleaned[..40];
        }

        return string.IsNullOrWhiteSpace(cleaned) ? "connecTO" : cleaned;
    }

    private sealed class DnsWriter
    {
        private readonly List<byte> data = [];
        private readonly Dictionary<string, int> names = [];

        public void Header(ushort id, ushort flags, ushort questions, ushort answers, ushort authorities, ushort additional)
        {
            U16(id);
            U16(flags);
            U16(questions);
            U16(answers);
            U16(authorities);
            U16(additional);
        }

        public int Name(string dotted)
        {
            if (names.TryGetValue(dotted, out var existing))
            {
                data.Add((byte)(0xC0 | (existing >> 8)));
                data.Add((byte)existing);
                return existing;
            }

            var offset = data.Count;
            names[dotted] = offset;
            var labels = dotted.Split('.', StringSplitOptions.RemoveEmptyEntries);
            for (var index = 0; index < labels.Length; index++)
            {
                var suffix = string.Join('.', labels.Skip(index));
                if (index > 0 && names.TryGetValue(suffix, out var pointer))
                {
                    data.Add((byte)(0xC0 | (pointer >> 8)));
                    data.Add((byte)pointer);
                    return offset;
                }

                names[suffix] = data.Count;
                var bytes = Encoding.UTF8.GetBytes(labels[index]);
                data.Add((byte)bytes.Length);
                data.AddRange(bytes);
            }

            data.Add(0);
            return offset;
        }

        public void Record(string dotted, ushort type, ushort klass, uint ttl, Action writeData)
        {
            Name(dotted);
            U16(type);
            U16(klass);
            U32(ttl);
            var lengthAt = data.Count;
            U16(0);
            var start = data.Count;
            writeData();
            var length = (ushort)(data.Count - start);
            data[lengthAt] = (byte)(length >> 8);
            data[lengthAt + 1] = (byte)length;
        }

        public void U16(ushort value)
        {
            data.Add((byte)(value >> 8));
            data.Add((byte)value);
        }

        public void U32(uint value)
        {
            data.Add((byte)(value >> 24));
            data.Add((byte)(value >> 16));
            data.Add((byte)(value >> 8));
            data.Add((byte)value);
        }

        public void Byte(byte value) => data.Add(value);

        public void Bytes(byte[] value) => data.AddRange(value);

        public byte[] ToArray() => data.ToArray();
    }
}
