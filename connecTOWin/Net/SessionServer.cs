using System.Collections.Immutable;
using System.Net;
using System.Net.Sockets;
using ConnecTOWin.Protocol;

namespace ConnecTOWin;

public readonly record struct DisplayFrame(int X, int Y, int Width, int Height);

public sealed record CaptureStartResult(
    DisplayFrame Frame,
    uint DisplayId,
    bool Audio,
    IReadOnlyList<SharedDisplay> Displays);

public interface IScreenSource
{
    bool Probe();

    CaptureStartResult Start(
        int longSide,
        uint? displayId,
        bool captureAudio,
        Action<byte[]> onPacket,
        Action onFailure);

    void Stop();

    bool TrySilence(out bool previousMuted);

    void RestoreSilence(bool previousMuted);
}

public interface IInputSink
{
    bool Available { get; }

    void Apply(WireMessage message, DisplayFrame frame);
}

public sealed class SessionServer : IDisposable
{
    private readonly object gate = new();
    private readonly TrustedDeviceStore store;
    private readonly IScreenSource screen;
    private readonly IInputSink input;
    private readonly Func<DateTime> clock;
    private readonly Func<Guid> newSessionId;
    private SessionMachine machine;
    private TcpListener? listener;
    private CancellationTokenSource? lifetime;
    private TcpClient? controlClient;
    private TcpClient? videoClient;
    private NetworkStream? controlStream;
    private NetworkStream? videoStream;
    private FrameDecoder controlDecoder = new();
    private FrameDecoder videoDecoder = new();
    private string? connectedName;
    private string? pendingName;
    private int preferredLongSide = 1920;
    private uint? preferredDisplay;
    private DisplayFrame displayFrame;
    private LinkMode linkMode = LinkMode.Control;
    private bool roleKnown;
    private bool videoHelloAccepted;
    private bool redirectingAudio;
    private bool? savedMute;
    private int captureGeneration;
    private bool capturing;

    public SessionServer(
        PairingCode code,
        IScreenSource screen,
        IInputSink input,
        TrustedDeviceStore? store = null,
        Func<DateTime>? clock = null,
        Func<Guid>? newSessionId = null)
    {
        this.store = store ?? new TrustedDeviceStore();
        this.screen = screen;
        this.input = input;
        this.clock = clock ?? (() => DateTime.UtcNow);
        this.newSessionId = newSessionId ?? Guid.NewGuid;
        var devices = this.store.Load();
        machine = new SessionMachine(devices.Select(device => device.Id), code);
    }

    public string LinkLabel { get; private set; } = "Esperando un iPad";

    public bool IsLinked { get; private set; }

    public bool ExtendRequested { get; private set; }

    public int Port { get; private set; }

    public event Action? Changed;

    public void Start()
    {
        if (listener != null)
        {
            return;
        }

        var bound = new TcpListener(IPAddress.Any, 0);
        bound.Start();
        listener = bound;
        Port = ((IPEndPoint)bound.LocalEndpoint).Port;
        lifetime = new CancellationTokenSource();
        var token = lifetime.Token;
        Task.Run(() => AcceptLoop(token));
    }

    public void UpdateCode(PairingCode code)
    {
        lock (gate)
        {
            machine.Code = code;
        }
    }

    public void ForgetAll()
    {
        TcpClient? control;
        lock (gate)
        {
            machine.TrustedDeviceIds.Clear();
            machine.Current = SessionMachine.Phase.Waiting.Instance;
            store.Save([]);
            connectedName = null;
            pendingName = null;
            linkMode = LinkMode.Control;
            roleKnown = false;
            ExtendRequested = false;
            control = controlClient;
            controlClient = null;
            controlStream = null;
            controlDecoder = new FrameDecoder();
            Publish();
        }

        CloseVideo();
        control?.Dispose();
        Changed?.Invoke();
    }

    public void Dispose()
    {
        lifetime?.Cancel();
        listener?.Stop();
        ForgetAll();
        screen.Stop();
    }

    private async Task AcceptLoop(CancellationToken token)
    {
        while (!token.IsCancellationRequested && listener != null)
        {
            TcpClient client;
            try
            {
                client = await listener.AcceptTcpClientAsync(token);
            }
            catch (Exception) when (token.IsCancellationRequested)
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

            var startVideo = false;
            var startControl = false;
            lock (gate)
            {
                if (controlClient == null)
                {
                    controlClient = client;
                    controlStream = client.GetStream();
                    controlDecoder = new FrameDecoder();
                    startControl = true;
                }
                else if (videoClient == null && machine.Current is SessionMachine.Phase.Paired)
                {
                    videoClient = client;
                    videoStream = client.GetStream();
                    videoDecoder = new FrameDecoder();
                    startVideo = true;
                }
                else
                {
                    client.Dispose();
                }
            }

            if (startControl)
            {
                _ = Task.Run(() => Pump(client, video: false));
            }
            else if (startVideo)
            {
                _ = Task.Run(() => Pump(client, video: true));
            }
        }
    }

    private void Pump(TcpClient client, bool video)
    {
        var buffer = new byte[video ? 65536 : 16384];
        try
        {
            var stream = client.GetStream();
            while (true)
            {
                var read = stream.Read(buffer, 0, buffer.Length);
                if (read == 0)
                {
                    break;
                }

                if (!Consume(client, buffer.AsSpan(0, read), video))
                {
                    return;
                }
            }
        }
        catch (IOException)
        {
        }
        catch (SocketException)
        {
        }

        if (video)
        {
            CloseVideo();
        }
        else
        {
            CloseLink(client);
        }

        Changed?.Invoke();
    }

    private bool Consume(TcpClient client, ReadOnlySpan<byte> chunk, bool video)
    {
        try
        {
            if (video)
            {
                List<WireMessage> messages;
                lock (gate)
                {
                    if (videoClient != client || capturing)
                    {
                        return videoClient == client;
                    }

                    messages = videoDecoder.Append(chunk).ToList();
                }

                foreach (var message in messages)
                {
                    if (!AcceptVideoHello(client, message))
                    {
                        return false;
                    }
                }

                return true;
            }

            List<WireMessage> controlMessages;
            lock (gate)
            {
                if (controlClient != client)
                {
                    return false;
                }

                controlMessages = controlDecoder.Append(chunk).ToList();
            }

            foreach (var message in controlMessages)
            {
                Handle(message);
            }

            return true;
        }
        catch (FrameException)
        {
            if (video)
            {
                CloseVideo();
            }
            else
            {
                CloseLink(client);
            }

            Changed?.Invoke();
            return false;
        }
    }

    private void Handle(WireMessage message)
    {
        Action? begin = null;
        var changed = false;
        lock (gate)
        {
            if (controlClient == null)
            {
                return;
            }

            switch (message)
            {
                case WireMessage.Hello hello:
                    pendingName = hello.DeviceName;
                    break;
                case WireMessage.Pair pair:
                    pendingName = pair.DeviceName;
                    break;
            }

            var effect = machine.Handle(message, clock(), newSessionId);
            switch (effect)
            {
                case SessionMachine.Effect.Reply reply:
                    if (reply.Message is WireMessage.Paired)
                    {
                        connectedName = pendingName;
                        Remember(message);
                    }

                    Send(reply.Message);
                    break;
                case SessionMachine.Effect.Input inputMessage:
                    changed = ApplyInput(inputMessage.Message, out begin);
                    break;
            }

            Publish();
        }

        begin?.Invoke();
        if (changed)
        {
            Changed?.Invoke();
        }
    }

    private bool ApplyInput(WireMessage message, out Action? begin)
    {
        begin = null;
        switch (message)
        {
            case WireMessage.Quality quality:
                var clamped = Math.Clamp(quality.LongSide, 960, 8192);
                var qualityChanged = clamped != preferredLongSide;
                preferredLongSide = clamped;
                if (qualityChanged && capturing)
                {
                    begin = RestartCapture;
                }

                return false;
            case WireMessage.Screen screenMessage:
                if (linkMode == LinkMode.Extend)
                {
                    return false;
                }

                if (screenMessage.DisplayId == preferredDisplay)
                {
                    return false;
                }

                preferredDisplay = screenMessage.DisplayId;
                if (capturing)
                {
                    begin = RestartCapture;
                }

                return false;
            case WireMessage.Audio audio:
                if (audio.Enabled == redirectingAudio)
                {
                    return false;
                }

                redirectingAudio = audio.Enabled;
                if (!audio.Enabled)
                {
                    RestoreMute();
                }

                if (capturing)
                {
                    begin = RestartCapture;
                }

                return false;
            case WireMessage.Role role:
                var modeChanged = role.Mode != linkMode || !roleKnown;
                linkMode = role.Mode;
                roleKnown = true;
                ExtendRequested = role.Mode == LinkMode.Extend;
                if (capturing && modeChanged)
                {
                    begin = RestartCapture;
                }
                else if (videoHelloAccepted)
                {
                    begin = BeginCapture;
                }

                return true;
            default:
                input.Apply(message, displayFrame);
                return false;
        }
    }

    private bool AcceptVideoHello(TcpClient client, WireMessage message)
    {
        Guid? paired;
        var ready = false;
        lock (gate)
        {
            if (videoClient != client)
            {
                return false;
            }

            paired = machine.Current is SessionMachine.Phase.Paired open ? open.DeviceId : null;
            if (message is not WireMessage.VideoHello hello || hello.DeviceId != paired)
            {
                ready = false;
            }
            else if (!screen.Probe())
            {
                Send(new WireMessage.ScreenUnavailable());
                ready = false;
            }
            else
            {
                videoHelloAccepted = true;
                ready = roleKnown;
            }
        }

        if (message is not WireMessage.VideoHello || paired == null || (message is WireMessage.VideoHello helloMismatch && helloMismatch.DeviceId != paired))
        {
            CloseVideo();
            Changed?.Invoke();
            return false;
        }

        if (!screen.Probe())
        {
            CloseVideo();
            Changed?.Invoke();
            return false;
        }

        if (ready)
        {
            BeginCapture();
        }

        return true;
    }

    private void RestartCapture()
    {
        lock (gate)
        {
            captureGeneration++;
            capturing = false;
        }

        screen.Stop();
        BeginCapture();
    }

    private void BeginCapture()
    {
        int generation;
        int longSide;
        uint? displayId;
        var audio = false;
        lock (gate)
        {
            if (!roleKnown || capturing)
            {
                return;
            }

            capturing = true;
            captureGeneration++;
            generation = captureGeneration;
            longSide = preferredLongSide;
            displayId = preferredDisplay;
            audio = redirectingAudio;
        }

        try
        {
            var started = screen.Start(longSide, displayId, audio, packet =>
            {
                lock (gate)
                {
                    if (generation != captureGeneration)
                    {
                        return;
                    }

                    WriteVideo(packet);
                }
            }, () =>
            {
                lock (gate)
                {
                    if (generation != captureGeneration)
                    {
                        return;
                    }

                    Send(new WireMessage.ScreenUnavailable());
                }

                CloseVideo();
                Changed?.Invoke();
            });

            lock (gate)
            {
                if (generation != captureGeneration)
                {
                    screen.Stop();
                    return;
                }

                displayFrame = started.Frame;
                preferredDisplay = started.DisplayId;
                if (redirectingAudio && started.Audio)
                {
                    Silence();
                }
                else if (redirectingAudio)
                {
                    redirectingAudio = false;
                    RestoreMute();
                    Send(new WireMessage.Audio(false));
                }

                Send(new WireMessage.Displays(started.Displays.ToImmutableArray(), started.DisplayId));
            }
        }
        catch (Exception)
        {
            lock (gate)
            {
                if (generation != captureGeneration)
                {
                    return;
                }

                Send(new WireMessage.ScreenUnavailable());
            }

            CloseVideo();
        }

        Changed?.Invoke();
    }

    private void Silence()
    {
        if (savedMute != null)
        {
            return;
        }

        if (screen.TrySilence(out var previous))
        {
            savedMute = previous;
        }
    }

    private void RestoreMute()
    {
        if (savedMute is not bool previous)
        {
            return;
        }

        screen.RestoreSilence(previous);
        savedMute = null;
    }

    private void Remember(WireMessage message)
    {
        switch (message)
        {
            case WireMessage.Pair pair:
                store.Upsert(new TrustedDevice(pair.DeviceId, pair.DeviceName, clock()));
                break;
            case WireMessage.Hello hello:
                store.Upsert(new TrustedDevice(hello.DeviceId, hello.DeviceName, clock()));
                break;
        }
    }

    private void Send(WireMessage message)
    {
        try
        {
            var bytes = FrameCodec.Encode(message);
            controlStream?.Write(bytes, 0, bytes.Length);
        }
        catch (IOException)
        {
        }
    }

    private void WriteVideo(byte[] data)
    {
        try
        {
            videoStream?.Write(data, 0, data.Length);
        }
        catch (IOException)
        {
        }
    }

    private void CloseVideo()
    {
        TcpClient? client;
        lock (gate)
        {
            capturing = false;
            captureGeneration++;
            videoHelloAccepted = false;
            displayFrame = default;
            if (redirectingAudio)
            {
                redirectingAudio = false;
                RestoreMute();
                Send(new WireMessage.Audio(false));
            }

            client = videoClient;
            videoClient = null;
            videoStream = null;
            videoDecoder = new FrameDecoder();
        }

        screen.Stop();
        client?.Dispose();
    }

    private void CloseLink(TcpClient client)
    {
        lock (gate)
        {
            if (controlClient != client)
            {
                return;
            }

            controlClient = null;
            controlStream = null;
            controlDecoder = new FrameDecoder();
            connectedName = null;
            pendingName = null;
            machine.Current = SessionMachine.Phase.Waiting.Instance;
            linkMode = LinkMode.Control;
            roleKnown = false;
            ExtendRequested = false;
            Publish();
        }

        CloseVideo();
    }

    private void Publish()
    {
        if (connectedName != null)
        {
            LinkLabel = $"{connectedName} conectado";
            IsLinked = true;
        }
        else if (pendingName != null)
        {
            LinkLabel = "Esperando el código";
            IsLinked = false;
        }
        else
        {
            LinkLabel = "Esperando un iPad";
            IsLinked = false;
        }
    }
}
