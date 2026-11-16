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

    public bool Probe() => OperatingSystem.IsWindows();

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
        ComApartment.Ensure();
        TryDuplicate(monitor.DeviceName, out device, out context, out duplication);
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
        ID3D11Device? device,
        ID3D11DeviceContext? context,
        IDXGIOutputDuplication? duplication,
        H264Encoder encoder,
        MonitorInfo monitor,
        int width,
        int height,
        Action<byte[]> onPacket,
        Action onFailure)
    {
        var next = DateTime.UtcNow;
        var started = DateTime.UtcNow;
        var sent = false;
        var duplicate = duplication;
        byte[]? held = null;
        var heldAt = DateTime.UtcNow;
        var flushed = true;
        try
        {
            ComApartment.Ensure();
            while (running)
            {
                var wait = next - DateTime.UtcNow;
                if (wait > TimeSpan.Zero)
                {
                    Thread.Sleep(wait);
                }

                next = DateTime.UtcNow.AddSeconds(1.0 / 30);
                byte[]? bgra = null;
                var sourceWidth = 0;
                var sourceHeight = 0;
                var pitch = 0;
                var lost = false;
                if (duplicate != null
                    && device != null
                    && context != null
                    && TryFrame(device, context, duplicate, out var captured, out sourceWidth, out sourceHeight, out pitch, out lost))
                {
                    bgra = captured;
                }
                else if (lost)
                {
                    duplicate = null;
                }

                if (bgra == null && (duplicate == null || (!sent && DateTime.UtcNow - started > TimeSpan.FromMilliseconds(200))))
                {
                    bgra = GrabScreen(monitor.X, monitor.Y, monitor.Width, monitor.Height);
                    sourceWidth = monitor.Width;
                    sourceHeight = monitor.Height;
                    pitch = monitor.Width * 4;
                }

                if (bgra != null)
                {
                    sent = true;
                    held = Nv12Convert.FromBgra(bgra, sourceWidth, sourceHeight, pitch, width, height);
                    heldAt = DateTime.UtcNow;
                    flushed = false;
                    Publish(encoder.Encode(held));
                }
                else if (!flushed && held != null && DateTime.UtcNow - heldAt > TimeSpan.FromMilliseconds(30))
                {
                    flushed = true;
                    Publish(encoder.Encode(held));
                }
            }

            void Publish(IReadOnlyList<VideoPacket> packets)
            {
                foreach (var packet in packets)
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
        out int pitch,
        out bool lost)
    {
        bgra = [];
        width = 0;
        height = 0;
        pitch = 0;
        lost = false;
        IDXGIResource? resource = null;
        var acquired = false;
        try
        {
            var result = duplication.AcquireNextFrame(16, out _, out resource);
            lost = result == Vortice.DXGI.ResultCode.AccessLost;
            acquired = result.Success && resource != null;
            if (!acquired || resource == null)
            {
                return false;
            }

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

            return bgra.Length > 0;
        }
        catch (Exception)
        {
            lost = true;
            return false;
        }
        finally
        {
            if (acquired)
            {
                resource?.Dispose();
                duplication.ReleaseFrame();
            }
        }
    }

    private static void TryDuplicate(
        string deviceName,
        out ID3D11Device? device,
        out ID3D11DeviceContext? context,
        out IDXGIOutputDuplication? duplication)
    {
        device = null;
        context = null;
        duplication = null;
        try
        {
            using var factory = DXGI.CreateDXGIFactory1<IDXGIFactory1>();
            uint adapterIndex = 0;
            while (true)
            {
                var adapterResult = factory.EnumAdapters1(adapterIndex, out var adapter);
                if (adapterResult.Failure || adapter == null)
                {
                    break;
                }

                using (adapter)
                {
                    if (TryOutput(adapter, deviceName, out device, out context, out duplication))
                    {
                        return;
                    }
                }

                adapterIndex++;
            }
        }
        catch (Exception)
        {
            device?.Dispose();
            context?.Dispose();
            duplication?.Dispose();
            device = null;
            context = null;
            duplication = null;
        }
    }

    private static bool TryOutput(
        IDXGIAdapter1 adapter,
        string deviceName,
        out ID3D11Device? device,
        out ID3D11DeviceContext? context,
        out IDXGIOutputDuplication? duplication)
    {
        device = null;
        context = null;
        duplication = null;
        IDXGIOutput? matched = null;
        IDXGIOutput? first = null;
        uint index = 0;
        while (true)
        {
            var result = adapter.EnumOutputs(index, out var output);
            if (result.Failure || output == null)
            {
                break;
            }

            first ??= output;
            if (string.Equals(output.Description.DeviceName, deviceName, StringComparison.OrdinalIgnoreCase))
            {
                matched = output;
                break;
            }

            if (!ReferenceEquals(first, output))
            {
                output.Dispose();
            }

            index++;
        }

        var chosen = matched ?? first;
        if (chosen == null)
        {
            return false;
        }

        try
        {
            device = CreateDevice(adapter.NativePointer, out context!);
            using var output1 = chosen.QueryInterface<IDXGIOutput1>();
            duplication = output1.DuplicateOutput(device);
            if (duplication != null)
            {
                return true;
            }

            device.Dispose();
            context?.Dispose();
            device = null;
            context = null;
            return false;
        }
        catch (Exception)
        {
            device?.Dispose();
            context?.Dispose();
            duplication?.Dispose();
            device = null;
            context = null;
            duplication = null;
            return false;
        }
        finally
        {
            chosen.Dispose();
            if (first != null && !ReferenceEquals(first, chosen))
            {
                first.Dispose();
            }
        }
    }

    private static ID3D11Device CreateDevice(IntPtr adapter, out ID3D11DeviceContext context)
    {
        var levels = new[] { FeatureLevel.Level_11_0, FeatureLevel.Level_10_0 };
        D3D11.D3D11CreateDevice(
            adapter,
            adapter == IntPtr.Zero ? DriverType.Hardware : DriverType.Unknown,
            DeviceCreationFlags.BgraSupport,
            levels,
            out var device,
            out _,
            out context).CheckError();
        return device ?? throw new InvalidOperationException("Sin dispositivo de vídeo.");
    }

    private static byte[]? GrabScreen(int x, int y, int width, int height)
    {
        if (!OperatingSystem.IsWindows() || width <= 0 || height <= 0)
        {
            return null;
        }

        var screen = GetDC(IntPtr.Zero);
        if (screen == IntPtr.Zero)
        {
            return null;
        }

        var memory = CreateCompatibleDC(screen);
        var bitmap = CreateCompatibleBitmap(screen, width, height);
        var previous = SelectObject(memory, bitmap);
        var copied = BitBlt(memory, 0, 0, width, height, screen, x, y, 0x00CC0020);
        byte[]? pixels = null;
        if (copied)
        {
            var info = new BitmapInfo
            {
                Size = Marshal.SizeOf<BitmapInfo>(),
                Width = width,
                Height = -height,
                Planes = 1,
                BitCount = 32,
            };
            pixels = new byte[width * height * 4];
            var pin = GCHandle.Alloc(pixels, GCHandleType.Pinned);
            try
            {
                if (GetDIBits(memory, bitmap, 0, (uint)height, pin.AddrOfPinnedObject(), ref info, 0) == 0)
                {
                    pixels = null;
                }
            }
            finally
            {
                pin.Free();
            }
        }

        SelectObject(memory, previous);
        DeleteObject(bitmap);
        DeleteDC(memory);
        ReleaseDC(IntPtr.Zero, screen);
        return pixels;
    }

    [DllImport("user32.dll")]
    private static extern IntPtr GetDC(IntPtr window);

    [DllImport("user32.dll")]
    private static extern int ReleaseDC(IntPtr window, IntPtr dc);

    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateCompatibleDC(IntPtr dc);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteDC(IntPtr dc);

    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateCompatibleBitmap(IntPtr dc, int width, int height);

    [DllImport("gdi32.dll")]
    private static extern IntPtr SelectObject(IntPtr dc, IntPtr obj);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteObject(IntPtr obj);

    [DllImport("gdi32.dll")]
    private static extern bool BitBlt(IntPtr dest, int x, int y, int width, int height, IntPtr source, int sourceX, int sourceY, int op);

    [DllImport("gdi32.dll")]
    private static extern int GetDIBits(IntPtr dc, IntPtr bitmap, uint start, uint lines, IntPtr bits, ref BitmapInfo info, uint usage);

    [StructLayout(LayoutKind.Sequential)]
    private struct BitmapInfo
    {
        public int Size;
        public int Width;
        public int Height;
        public short Planes;
        public short BitCount;
        public int Compression;
        public int SizeImage;
        public int XPelsPerMeter;
        public int YPelsPerMeter;
        public int ClrUsed;
        public int ClrImportant;
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
