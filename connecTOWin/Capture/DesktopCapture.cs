using System.Runtime.InteropServices;
using ConnecTOWin.Protocol;
using Vortice.Direct3D;
using Vortice.Direct3D11;
using Vortice.DXGI;
using MapFlags = Vortice.Direct3D11.MapFlags;

namespace ConnecTOWin;

public sealed class DesktopCapture : IScreenSource
{
    private readonly object gate = new();
    private Thread? thread;
    private volatile bool running;
    private H264Encoder? encoder;
    private IDXGIOutputDuplication? duplication;
    private ID3D11Device? device;
    private ID3D11DeviceContext? context;
    private EndpointVolume? volume;
    private AudioLoopback? audio;

    public bool Probe()
    {
        if (!OperatingSystem.IsWindows())
        {
            return false;
        }

        try
        {
            using var created = CreateDevice(out var immediate);
            immediate.Dispose();
            return created != null;
        }
        catch (Exception)
        {
            return false;
        }
    }

    public CaptureStartResult Start(
        int longSide,
        uint? displayId,
        bool captureAudio,
        Action<byte[]> onPacket,
        Action onFailure)
    {
        Stop();
        var monitors = MonitorCatalog.Read();
        if (monitors.Count == 0)
        {
            throw new InvalidOperationException("No hay pantallas.");
        }

        var shared = monitors.Select(monitor => monitor.AsShared()).ToArray();
        var main = monitors.FirstOrDefault(monitor => monitor.Primary).Id;
        if (main == 0 && monitors.All(monitor => !monitor.Primary))
        {
            main = monitors[0].Id;
        }

        var chosen = DisplayList.ResolvedId(displayId, shared, main) ?? monitors[0].Id;
        var monitor = monitors.First(item => item.Id == chosen);
        var (width, height) = CaptureMath.OutputSize(monitor.Width, monitor.Height, longSide);
        device = CreateDevice(out context!);
        duplication = OpenDuplication(device, monitor.DeviceName);
        encoder = new H264Encoder(width, height, CaptureMath.BitRate(width, height));
        running = true;
        var localEncoder = encoder;
        var localDuplication = duplication;
        var localDevice = device;
        var localContext = context;
        thread = new Thread(() => Loop(localDevice, localContext, localDuplication, localEncoder, monitor, width, height, onPacket, onFailure))
        {
            IsBackground = true,
            Name = "connecTO.capture",
        };
        thread.Start();

        var audioStarted = false;
        if (captureAudio)
        {
            audio = AudioLoopback.TryStart(packet =>
            {
                try
                {
                    onPacket(VideoPacketCodec.Encode(packet));
                }
                catch (VideoPacketException)
                {
                }
            });
            audioStarted = audio != null;
        }

        return new CaptureStartResult(
            new DisplayFrame(monitor.X, monitor.Y, monitor.Width, monitor.Height),
            monitor.Id,
            audioStarted,
            DisplayList.Ordered(shared, main));
    }

    public void Stop()
    {
        running = false;
        var worker = thread;
        thread = null;
        worker?.Join(TimeSpan.FromSeconds(2));
        lock (gate)
        {
            audio?.Dispose();
            audio = null;
            encoder?.Dispose();
            encoder = null;
            duplication?.Dispose();
            duplication = null;
            context?.Dispose();
            context = null;
            device?.Dispose();
            device = null;
        }
    }

    public bool TrySilence(out bool previousMuted)
    {
        previousMuted = false;
        if (!OperatingSystem.IsWindows())
        {
            return false;
        }

        try
        {
            volume ??= EndpointVolume.OpenDefault();
            if (volume == null)
            {
                return false;
            }

            previousMuted = volume.Muted;
            volume.Muted = true;
            return true;
        }
        catch (Exception)
        {
            return false;
        }
    }

    public void RestoreSilence(bool previousMuted)
    {
        try
        {
            if (volume != null)
            {
                volume.Muted = previousMuted;
            }
        }
        catch (Exception)
        {
        }
    }

    private void Loop(
        ID3D11Device device,
        ID3D11DeviceContext context,
        IDXGIOutputDuplication duplication,
        H264Encoder encoder,
        MonitorInfo monitor,
        int width,
        int height,
        Action<byte[]> onPacket,
        Action onFailure)
    {
        var next = DateTime.UtcNow;
        try
        {
            while (running)
            {
                var wait = next - DateTime.UtcNow;
                if (wait > TimeSpan.Zero)
                {
                    Thread.Sleep(wait);
                }

                next = DateTime.UtcNow.AddSeconds(1.0 / 30);
                if (!TryFrame(device, context, duplication, out var bgra, out var sourceWidth, out var sourceHeight, out var pitch))
                {
                    continue;
                }

                var nv12 = Nv12Convert.FromBgra(bgra, sourceWidth, sourceHeight, pitch, width, height);
                foreach (var packet in encoder.Encode(nv12))
                {
                    if (!running)
                    {
                        return;
                    }

                    try
                    {
                        onPacket(VideoPacketCodec.Encode(packet));
                    }
                    catch (VideoPacketException)
                    {
                    }
                }
            }
        }
        catch (Exception)
        {
            if (running)
            {
                onFailure();
            }
        }
    }

    private static bool TryFrame(
        ID3D11Device device,
        ID3D11DeviceContext context,
        IDXGIOutputDuplication duplication,
        out byte[] bgra,
        out int width,
        out int height,
        out int pitch)
    {
        bgra = [];
        width = 0;
        height = 0;
        pitch = 0;
        var result = duplication.AcquireNextFrame(16, out _, out var resource);
        if (result == Vortice.DXGI.ResultCode.WaitTimeout || result.Failure || resource == null)
        {
            return false;
        }

        try
        {
            using var texture = resource.QueryInterface<ID3D11Texture2D>();
            var description = texture.Description;
            description.Usage = ResourceUsage.Staging;
            description.BindFlags = BindFlags.None;
            description.CPUAccessFlags = CpuAccessFlags.Read;
            description.MiscFlags = ResourceOptionFlags.None;
            using var staging = device.CreateTexture2D(description);
            context.CopyResource(staging, texture);
            var mapped = context.Map(staging, 0, MapMode.Read, MapFlags.None);
            try
            {
                width = (int)description.Width;
                height = (int)description.Height;
                pitch = (int)mapped.RowPitch;
                var size = pitch * height;
                bgra = new byte[size];
                Marshal.Copy(mapped.DataPointer, bgra, 0, size);
            }
            finally
            {
                context.Unmap(staging, 0);
            }
        }
        finally
        {
            resource.Dispose();
            duplication.ReleaseFrame();
        }

        return bgra.Length > 0;
    }

    private static IDXGIOutputDuplication OpenDuplication(ID3D11Device device, string deviceName)
    {
        using var dxgi = device.QueryInterface<IDXGIDevice>();
        dxgi.GetAdapter(out var adapter).CheckError();
        using (adapter)
        {
            uint index = 0;
            while (true)
            {
                var result = adapter.EnumOutputs(index, out var output);
                if (result.Failure || output == null)
                {
                    break;
                }

                using (output)
                {
                    var description = output.Description;
                    if (string.Equals(description.DeviceName, deviceName, StringComparison.OrdinalIgnoreCase))
                    {
                        using var output1 = output.QueryInterface<IDXGIOutput1>();
                        return output1.DuplicateOutput(device);
                    }
                }

                index++;
            }
        }

        throw new InvalidOperationException("No se pudo duplicar la pantalla.");
    }

    private static ID3D11Device CreateDevice(out ID3D11DeviceContext context)
    {
        var levels = new[] { FeatureLevel.Level_11_0, FeatureLevel.Level_10_0 };
        D3D11.D3D11CreateDevice(
            IntPtr.Zero,
            DriverType.Hardware,
            DeviceCreationFlags.BgraSupport,
            levels,
            out var device,
            out _,
            out context).CheckError();
        return device ?? throw new InvalidOperationException("Sin dispositivo de vídeo.");
    }
}

public static class Nv12Convert
{
    public static byte[] FromBgra(byte[] bgra, int sourceWidth, int sourceHeight, int pitch, int width, int height)
    {
        var nv12 = new byte[(width * height * 3) / 2];
        for (var y = 0; y < height; y++)
        {
            var sourceY = sourceHeight <= 1 ? 0 : y * (sourceHeight - 1) / Math.Max(height - 1, 1);
            for (var x = 0; x < width; x++)
            {
                var sourceX = sourceWidth <= 1 ? 0 : x * (sourceWidth - 1) / Math.Max(width - 1, 1);
                var pixel = (sourceY * pitch) + (sourceX * 4);
                if (pixel + 2 >= bgra.Length)
                {
                    continue;
                }

                var b = bgra[pixel];
                var g = bgra[pixel + 1];
                var r = bgra[pixel + 2];
                nv12[(y * width) + x] = ClampByte(16 + ((66 * r) + (129 * g) + (25 * b)) / 256);
                if ((y & 1) == 0 && (x & 1) == 0)
                {
                    var chroma = (width * height) + ((y / 2) * width) + (x & ~1);
                    nv12[chroma] = ClampByte(128 + ((-38 * r) + (-74 * g) + (112 * b)) / 256);
                    nv12[chroma + 1] = ClampByte(128 + ((112 * r) + (-94 * g) + (-18 * b)) / 256);
                }
            }
        }

        return nv12;
    }

    private static byte ClampByte(int value) => (byte)Math.Clamp(value, 0, 255);
}
