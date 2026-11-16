using System.Collections.Immutable;
using System.Runtime.InteropServices;
using ConnecTOWin.Protocol;

namespace ConnecTOWin;

public sealed class AudioLoopback : IDisposable
{
    private readonly IAudioClient client;
    private readonly IAudioCaptureClient capture;
    private readonly int sampleRate;
    private readonly int channels;
    private readonly bool floating;
    private readonly int bits;
    private volatile bool running;
    private Thread? thread;

    private AudioLoopback(IAudioClient client, IAudioCaptureClient capture, int sampleRate, int channels, bool floating, int bits)
    {
        this.client = client;
        this.capture = capture;
        this.sampleRate = sampleRate;
        this.channels = channels;
        this.floating = floating;
        this.bits = bits;
    }

    public static AudioLoopback? TryStart(Action<VideoPacket> onPacket)
    {
        if (!OperatingSystem.IsWindows())
        {
            return null;
        }

        try
        {
            var loopback = Open();
            loopback.running = true;
            loopback.client.Start();
            loopback.thread = new Thread(() => loopback.Pump(onPacket))
            {
                IsBackground = true,
                Name = "connecTO.audio",
            };
            loopback.thread.Start();
            return loopback;
        }
        catch (Exception)
        {
            return null;
        }
    }

    public void Dispose()
    {
        running = false;
        try
        {
            client.Stop();
        }
        catch (Exception)
        {
        }

        thread?.Join(TimeSpan.FromSeconds(1));
        Marshal.ReleaseComObject(capture);
        Marshal.ReleaseComObject(client);
    }

    private void Pump(Action<VideoPacket> onPacket)
    {
        var announced = false;
        while (running)
        {
            capture.GetNextPacketSize(out var frames);
            if (frames == 0)
            {
                Thread.Sleep(10);
                continue;
            }

            var status = capture.GetBuffer(out var data, out frames, out var flags, out _, out _);
            if (status != 0 || frames == 0 || (flags & 2) != 0)
            {
                capture.ReleaseBuffer(frames);
                continue;
            }

            var bytes = frames * channels * (bits / 8);
            var raw = new byte[bytes];
            Marshal.Copy(data, raw, 0, raw.Length);
            capture.ReleaseBuffer(frames);
            var pcm = ToInt16(raw);
            if (pcm.Length == 0)
            {
                continue;
            }

            if (!announced)
            {
                onPacket(new VideoPacket.AudioFormat(sampleRate, channels));
                announced = true;
            }

            onPacket(new VideoPacket.Audio(pcm.ToImmutableArray()));
        }
    }

    private byte[] ToInt16(byte[] raw)
    {
        if (!floating && bits == 16)
        {
            return raw;
        }

        if (!floating || bits != 32)
        {
            return [];
        }

        var samples = raw.Length / 4;
        var pcm = new byte[samples * 2];
        for (var index = 0; index < samples; index++)
        {
            var value = BitConverter.ToSingle(raw, index * 4);
            var scaled = (short)Math.Clamp(value * 32767f, short.MinValue, short.MaxValue);
            pcm[index * 2] = (byte)scaled;
            pcm[(index * 2) + 1] = (byte)(scaled >> 8);
        }

        return pcm;
    }

    private static AudioLoopback Open()
    {
        var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorCom();
        enumerator.GetDefaultAudioEndpoint(0, 1, out var device);
        var clientId = new Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2");
        device.Activate(ref clientId, 23, IntPtr.Zero, out var clientPointer);
        var client = (IAudioClient)Marshal.GetObjectForIUnknown(clientPointer);
        Marshal.Release(clientPointer);
        var formatPointer = IntPtr.Zero;
        try
        {
            client.GetMixFormat(out formatPointer);
            var format = Marshal.PtrToStructure<WaveFormat>(formatPointer);
            var floating = format.Tag == 3;
            var bits = format.Bits;
            if (format.Tag == 0xFFFE)
            {
                var sub = Marshal.PtrToStructure<Guid>(IntPtr.Add(formatPointer, 24));
                floating = sub == new Guid("00000003-0000-0010-8000-00aa00389b71");
            }

            client.Initialize(0, 0x00020000, 1_000_0000, 0, formatPointer, IntPtr.Zero);
            var captureId = new Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317");
            client.GetService(ref captureId, out var capturePointer);
            var capture = (IAudioCaptureClient)Marshal.GetObjectForIUnknown(capturePointer);
            Marshal.Release(capturePointer);
            return new AudioLoopback(client, capture, (int)format.Rate, format.Channels, floating, bits == 0 ? 32 : bits);
        }
        finally
        {
            if (formatPointer != IntPtr.Zero)
            {
                Marshal.FreeCoTaskMem(formatPointer);
            }

            Marshal.ReleaseComObject(device);
            Marshal.ReleaseComObject(enumerator);
        }
    }

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    private struct WaveFormat
    {
        public ushort Tag;
        public ushort Channels;
        public uint Rate;
        public uint Average;
        public ushort Align;
        public ushort Bits;
        public ushort Extra;
    }
}

public sealed class EndpointVolume
{
    private readonly IAudioEndpointVolume volume;

    private EndpointVolume(IAudioEndpointVolume volume)
    {
        this.volume = volume;
    }

    public bool Muted
    {
        get
        {
            volume.GetMute(out var muted);
            return muted;
        }
        set
        {
            var context = Guid.Empty;
            volume.SetMute(value, ref context);
        }
    }

    public static EndpointVolume? OpenDefault()
    {
        if (!OperatingSystem.IsWindows())
        {
            return null;
        }

        var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorCom();
        try
        {
            enumerator.GetDefaultAudioEndpoint(0, 1, out var device);
            try
            {
                var id = new Guid("5CDF2C82-841E-4546-9722-0CF74078229A");
                device.Activate(ref id, 23, IntPtr.Zero, out var volumePointer);
                var volume = (IAudioEndpointVolume)Marshal.GetObjectForIUnknown(volumePointer);
                Marshal.Release(volumePointer);
                return new EndpointVolume(volume);
            }
            finally
            {
                Marshal.ReleaseComObject(device);
            }
        }
        finally
        {
            Marshal.ReleaseComObject(enumerator);
        }
    }
}

[ComImport]
[Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
internal class MMDeviceEnumeratorCom
{
}

[ComImport]
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IMMDeviceEnumerator
{
    [PreserveSig]
    int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);

    [PreserveSig]
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
}

[ComImport]
[Guid("D666063F-1587-4E43-81F1-B948E807363F")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IMMDevice
{
    [PreserveSig]
    int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, out IntPtr instance);
}

[ComImport]
[Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IAudioClient
{
    [PreserveSig]
    int Initialize(int shareMode, uint flags, long bufferDuration, long periodicity, IntPtr format, IntPtr session);

    [PreserveSig]
    int GetBufferSize(out uint size);

    [PreserveSig]
    int GetStreamLatency(out long latency);

    [PreserveSig]
    int GetCurrentPadding(out uint padding);

    [PreserveSig]
    int IsFormatSupported(int shareMode, IntPtr format, out IntPtr closest);

    [PreserveSig]
    int GetMixFormat(out IntPtr format);

    [PreserveSig]
    int GetDevicePeriod(out long defaultPeriod, out long minimumPeriod);

    [PreserveSig]
    int Start();

    [PreserveSig]
    int Stop();

    [PreserveSig]
    int Reset();

    [PreserveSig]
    int SetEventHandle(IntPtr handle);

    [PreserveSig]
    int GetService(ref Guid iid, out IntPtr instance);
}

[ComImport]
[Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IAudioCaptureClient
{
    [PreserveSig]
    int GetBuffer(out IntPtr data, out uint frames, out uint flags, out ulong devicePosition, out ulong qpc);

    [PreserveSig]
    int ReleaseBuffer(uint frames);

    [PreserveSig]
    int GetNextPacketSize(out uint frames);
}

[ComImport]
[Guid("5CDF2C82-841E-4546-9722-0CF74078229A")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IAudioEndpointVolume
{
    [PreserveSig]
    int Register(IntPtr notify);

    [PreserveSig]
    int Unregister(IntPtr notify);

    [PreserveSig]
    int GetChannelCount(out uint count);

    [PreserveSig]
    int SetMasterVolumeLevel(float level, ref Guid context);

    [PreserveSig]
    int SetMasterVolumeLevelScalar(float level, ref Guid context);

    [PreserveSig]
    int GetMasterVolumeLevel(out float level);

    [PreserveSig]
    int GetMasterVolumeLevelScalar(out float level);

    [PreserveSig]
    int SetChannelVolumeLevel(uint channel, float level, ref Guid context);

    [PreserveSig]
    int SetChannelVolumeLevelScalar(uint channel, float level, ref Guid context);

    [PreserveSig]
    int GetChannelVolumeLevel(uint channel, out float level);

    [PreserveSig]
    int GetChannelVolumeLevelScalar(uint channel, out float level);

    [PreserveSig]
    int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid context);

    [PreserveSig]
    int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
}
