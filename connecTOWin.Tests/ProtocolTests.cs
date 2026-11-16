using System.Collections.Immutable;
using System.Net.Sockets;
using System.Text;
using ConnecTOWin;
using ConnecTOWin.Protocol;
using Xunit;

namespace ConnecTOWin.Tests;

public class ProtocolTests
{
    private static readonly DateTime Now = DateTime.UnixEpoch.AddSeconds(1_700_000_000);
    private static readonly Guid Device = Guid.Parse("11111111-1111-1111-1111-111111111111");
    private static readonly Guid Session = Guid.Parse("22222222-2222-2222-2222-222222222222");

    [Fact]
    public void FrozenHelloDecodes()
    {
        var json = """{"type":"hello","deviceID":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","deviceName":"iPad de Greg","protocolVersion":1}""";
        var message = WireJson.Decode(Encoding.UTF8.GetBytes(json));
        Assert.Equal(
            new WireMessage.Hello(Guid.Parse("E621E1F8-C36C-495A-93FC-0C247A3E6E5F"), "iPad de Greg", 1),
            message);
    }

    [Fact]
    public void MessagesRoundTripThroughAFrame()
    {
        WireMessage[] messages =
        [
            new WireMessage.Pointer(1.5, -2),
            new WireMessage.Media(MediaAction.PlayPause),
            new WireMessage.Key(8, ButtonPhase.Down, KeyModifiers.Command),
            new WireMessage.Text("áéí"),
            new WireMessage.Rejected(RejectReason.BadCode),
            new WireMessage.Cursor(0.25, 0.75),
            new WireMessage.Quality(1920),
            new WireMessage.Screen(2),
            new WireMessage.Audio(true),
            new WireMessage.Role(LinkMode.Extend),
            new WireMessage.Role(LinkMode.Control),
            new WireMessage.Displays([new SharedDisplay(1, "Studio", 1920, 1080)], 1),
        ];
        foreach (var message in messages)
        {
            var decoder = new FrameDecoder();
            var encoded = FrameCodec.Encode(message);
            var decoded = decoder.Append(encoded);
            Assert.Equal(encoded, FrameCodec.Encode(decoded[0]));
        }
    }

    [Fact]
    public void FramesCanArriveInPieces()
    {
        var first = new WireMessage.Pointer(1.5, -2);
        var second = new WireMessage.Media(MediaAction.PlayPause);
        var blob = FrameCodec.Encode(first).Concat(FrameCodec.Encode(second)).ToArray();
        var decoder = new FrameDecoder();
        Assert.Empty(decoder.Append(blob.AsSpan(0, 3)));
        Assert.Equal([first, second], decoder.Append(blob.AsSpan(3)));
    }

    [Fact]
    public void OversizedFrameIsRejected()
    {
        var decoder = new FrameDecoder();
        Assert.Throws<FrameException>(() => decoder.Append(new byte[] { 0x00, 0x00, 0x40, 0x00 }));
    }

    [Fact]
    public void VideoPacketsRoundTrip()
    {
        VideoPacket[] packets =
        [
            new VideoPacket.Format([ImmutableArray.Create<byte>(0, 1, 2), ImmutableArray.Create<byte>(9)], 1280, 720),
            new VideoPacket.Sample(true, ImmutableArray.Create<byte>(4, 5, 6, 7)),
            new VideoPacket.AudioFormat(48_000, 2),
            new VideoPacket.Audio(ImmutableArray.Create<byte>(1, 2, 3, 4)),
        ];
        foreach (var packet in packets)
        {
            var decoder = new VideoPacketDecoder();
            var encoded = VideoPacketCodec.Encode(packet);
            var decoded = decoder.Append(encoded);
            Assert.Equal(encoded, VideoPacketCodec.Encode(decoded[0]));
        }
    }

    [Fact]
    public void VideoCanArriveInPieces()
    {
        var first = new VideoPacket.Format([ImmutableArray.Create<byte>(1)], 16, 16);
        var second = new VideoPacket.Sample(false, ImmutableArray.Create<byte>(8, 8));
        var blob = VideoPacketCodec.Encode(first).Concat(VideoPacketCodec.Encode(second)).ToArray();
        var decoder = new VideoPacketDecoder();
        Assert.Empty(decoder.Append(blob.AsSpan(0, 3)));
        var decoded = decoder.Append(blob.AsSpan(3));
        Assert.Equal(VideoPacketCodec.Encode(first), VideoPacketCodec.Encode(decoded[0]));
        Assert.Equal(VideoPacketCodec.Encode(second), VideoPacketCodec.Encode(decoded[1]));
    }

    [Fact]
    public void OversizedVideoHeaderIsRejected()
    {
        var decoder = new VideoPacketDecoder();
        Assert.Throws<VideoPacketException>(() => decoder.Append(new byte[] { 0x00, 0x20, 0x00, 0x00 }));
    }

    [Fact]
    public void AnnexBBecomesLengthPrefixedSlices()
    {
        byte[] annex =
        [
            0, 0, 0, 1, 0x67, 1,
            0, 0, 0, 1, 0x68, 2,
            0, 0, 1, 0x65, 3,
        ];
        var units = H264Bitstream.SplitAnnexB(annex);
        Assert.Equal(3, units.Count);
        Assert.Equal(7, H264Bitstream.NalType(units[0]));
        Assert.True(H264Bitstream.IsKeyframe(units));
        Assert.Equal(new byte[] { 0, 0, 0, 2, 0x65, 3 }, H264Bitstream.LengthPrefixed([units[2]]));
    }

    [Theory]
    [InlineData("000000", PairingCode.Match.Mismatch)]
    [InlineData("482193", PairingCode.Match.Match)]
    [InlineData("482 193", PairingCode.Match.Match)]
    public void PairingCodeMatchesDigits(string entry, PairingCode.Match expected)
    {
        var code = PairingCode.Make("482193", Now);
        Assert.Equal(expected, code.Matches(entry, Now));
    }

    [Fact]
    public void ExpiredCodeDoesNotMatch()
    {
        var code = PairingCode.Make("482193", Now, TimeSpan.FromSeconds(10));
        Assert.Equal(PairingCode.Match.Expired, code.Matches("482193", Now.AddSeconds(10)));
    }

    [Fact]
    public void WrongCodeIsRejected()
    {
        var machine = Machine("482193");
        var effect = machine.Handle(Pair("000000"), Now, () => Session);
        Assert.Equal(new SessionMachine.Effect.Reply(new WireMessage.Rejected(RejectReason.BadCode)), effect);
        Assert.Equal(SessionMachine.Phase.Waiting.Instance, machine.Current);
        Assert.Empty(machine.TrustedDeviceIds);
    }

    [Fact]
    public void ExpiredCodeIsRejected()
    {
        var machine = Machine("482193", TimeSpan.FromSeconds(10));
        var effect = machine.Handle(Pair("482193"), Now.AddSeconds(10), () => Session);
        Assert.Equal(new SessionMachine.Effect.Reply(new WireMessage.Rejected(RejectReason.ExpiredCode)), effect);
        Assert.Empty(machine.TrustedDeviceIds);
    }

    [Fact]
    public void MatchingCodePairsAndTrustsTheDevice()
    {
        var machine = Machine("482193");
        var effect = machine.Handle(Pair("482 193"), Now, () => Session);
        Assert.Equal(new SessionMachine.Effect.Reply(new WireMessage.Paired(Session)), effect);
        Assert.Contains(Device, machine.TrustedDeviceIds);
        Assert.Equal(new SessionMachine.Phase.Paired(Device, Session), machine.Current);
    }

    [Fact]
    public void TrustedDeviceSkipsTheCode()
    {
        var machine = new SessionMachine([Device], PairingCode.Make("000000", Now));
        var effect = machine.Handle(new WireMessage.Hello(Device, "iPad", ProtocolVersion.Current), Now, () => Session);
        Assert.Equal(new SessionMachine.Effect.Reply(new WireMessage.Paired(Session)), effect);
    }

    [Fact]
    public void InputBeforePairingIsRejected()
    {
        var machine = Machine("482193");
        Assert.Equal(
            new SessionMachine.Effect.Reply(new WireMessage.Rejected(RejectReason.NotPaired)),
            machine.Handle(new WireMessage.Pointer(1, 2), Now, () => Session));
        Assert.Equal(
            new SessionMachine.Effect.Reply(new WireMessage.Rejected(RejectReason.NotPaired)),
            machine.Handle(new WireMessage.Cursor(0.2, 0.4), Now, () => Session));
        Assert.Equal(
            new SessionMachine.Effect.Reply(new WireMessage.Rejected(RejectReason.NotPaired)),
            machine.Handle(new WireMessage.Screen(7), Now, () => Session));
        Assert.Equal(
            new SessionMachine.Effect.Reply(new WireMessage.Rejected(RejectReason.NotPaired)),
            machine.Handle(new WireMessage.Role(LinkMode.Extend), Now, () => Session));
    }

    [Fact]
    public void RoleScreenAndPointerAfterPairingAreInput()
    {
        var machine = Machine("482193");
        machine.Handle(Pair("482193"), Now, () => Session);
        Assert.Equal(new SessionMachine.Effect.Input(new WireMessage.Role(LinkMode.Extend)), machine.Handle(new WireMessage.Role(LinkMode.Extend), Now, () => Session));
        Assert.Equal(new SessionMachine.Effect.Input(new WireMessage.Screen(7)), machine.Handle(new WireMessage.Screen(7), Now, () => Session));
        Assert.Equal(new SessionMachine.Effect.Input(new WireMessage.Audio(true)), machine.Handle(new WireMessage.Audio(true), Now, () => Session));
        Assert.Equal(new SessionMachine.Effect.Input(new WireMessage.Pointer(4, -1)), machine.Handle(new WireMessage.Pointer(4, -1), Now, () => Session));
    }

    [Fact]
    public void ReplacingTheCodeInvalidatesTheOldOne()
    {
        var machine = Machine("482193");
        machine.Code = PairingCode.Make("111111", Now);
        Assert.Equal(
            new SessionMachine.Effect.Reply(new WireMessage.Rejected(RejectReason.BadCode)),
            machine.Handle(Pair("482193"), Now, () => Session));
    }

    [Fact]
    public void UnsupportedVersionIsRejected()
    {
        var machine = Machine("482193");
        var effect = machine.Handle(new WireMessage.Hello(Device, "iPad", 0), Now, () => Session);
        Assert.Equal(new SessionMachine.Effect.Reply(new WireMessage.Rejected(RejectReason.UnsupportedVersion)), effect);
    }

    [Fact]
    public void CommandCIsControlC()
    {
        var strokes = KeyTranslation.ForKey(8, true, KeyModifiers.Command);
        Assert.Contains(strokes, stroke => stroke.VirtualKey == 0x43 && stroke.Down && stroke.Control && !stroke.Alt);
    }

    [Fact]
    public void ControlLeftMovesTheDesktop()
    {
        var strokes = KeyTranslation.ForKey(SpecialKey.Left, true, KeyModifiers.Control);
        Assert.Contains(strokes, stroke => stroke.VirtualKey == KeyTranslation.VkLWin && stroke.Down);
        Assert.Contains(strokes, stroke => stroke.VirtualKey == KeyTranslation.VkLeft && stroke.Down);
        Assert.Empty(KeyTranslation.ForKey(SpecialKey.Left, false, KeyModifiers.Control));
    }

    [Fact]
    public void ControlUpOpensTaskView()
    {
        var strokes = KeyTranslation.ForKey(SpecialKey.Up, true, KeyModifiers.Control);
        Assert.Contains(strokes, stroke => stroke.VirtualKey == KeyTranslation.VkTab && stroke.Down);
    }

    [Fact]
    public void OptionIsAlt()
    {
        var strokes = KeyTranslation.ForKey(0, true, KeyModifiers.Option);
        Assert.Contains(strokes, stroke => stroke.VirtualKey == 0x41 && stroke.Alt);
    }

    [Fact]
    public void PointerGainGrowsWithDistance()
    {
        var slow = PointerGain.CursorDelta(3, 4);
        Assert.Equal(3.75, slow.Dx, 3);
        Assert.Equal(5, slow.Dy, 3);
    }

    [Fact]
    public void BitRateMatchesTheMacCurve()
    {
        Assert.Equal(5_000_000, CaptureMath.BitRate(1280, 720));
        Assert.Equal(2_000_000, CaptureMath.BitRate(100, 100));
    }

    [Fact]
    public async Task PairedIPadReceivesTheDisplayList()
    {
        var store = new TrustedDeviceStore(Path.Combine(Path.GetTempPath(), $"connecto-{Guid.NewGuid():N}.json"));
        var screen = new FakeScreen();
        using var server = new SessionServer(
            PairingCode.Make("482193", Now),
            screen,
            new FakeInput(),
            store,
            () => Now,
            () => Session);
        server.Start();
        using var control = new TcpClient();
        await control.ConnectAsync("127.0.0.1", server.Port);
        var stream = control.GetStream();
        await stream.WriteAsync(FrameCodec.Encode(new WireMessage.Hello(Device, "iPad", ProtocolVersion.Current)));
        var needCode = await ReadFrame(stream);
        Assert.IsType<WireMessage.NeedCode>(needCode);
        await stream.WriteAsync(FrameCodec.Encode(Pair("482193")));
        var paired = await ReadFrame(stream);
        Assert.Equal(new WireMessage.Paired(Session), paired);
        await stream.WriteAsync(FrameCodec.Encode(new WireMessage.Role(LinkMode.Control)));
        using var video = new TcpClient();
        await video.ConnectAsync("127.0.0.1", server.Port);
        await video.GetStream().WriteAsync(FrameCodec.Encode(new WireMessage.VideoHello(Device)));
        var displays = await ReadFrame(stream);
        var list = Assert.IsType<WireMessage.Displays>(displays);
        Assert.Equal(1u, list.Active);
        Assert.Equal(1, screen.Starts);
    }

    private static SessionMachine Machine(string digits, TimeSpan? lifetime = null)
        => new([], PairingCode.Make(digits, Now, lifetime));

    private static WireMessage Pair(string code) => new WireMessage.Pair(code, Device, "iPad");

    private static async Task<WireMessage> ReadFrame(NetworkStream stream)
    {
        var decoder = new FrameDecoder();
        var buffer = new byte[4096];
        var deadline = DateTime.UtcNow.AddSeconds(3);
        while (DateTime.UtcNow < deadline)
        {
            var read = await stream.ReadAsync(buffer);
            if (read == 0)
            {
                break;
            }

            var messages = decoder.Append(buffer.AsSpan(0, read));
            if (messages.Count > 0)
            {
                return messages[0];
            }
        }

        throw new TimeoutException("El PC no contestó.");
    }

    private sealed class FakeScreen : IScreenSource
    {
        public int Starts { get; private set; }

        public bool Probe() => true;

        public CaptureStartResult Start(int longSide, uint? displayId, bool captureAudio, Action<byte[]> onPacket, Action onFailure)
        {
            Starts++;
            onPacket(VideoPacketCodec.Encode(new VideoPacket.Sample(true, ImmutableArray.Create<byte>(9))));
            return new CaptureStartResult(
                new DisplayFrame(0, 0, 100, 100),
                1,
                false,
                [new SharedDisplay(1, "Pantalla", 100, 100)]);
        }

        public void Stop()
        {
        }

        public bool TrySilence(out bool previousMuted)
        {
            previousMuted = false;
            return false;
        }

        public void RestoreSilence(bool previousMuted)
        {
        }
    }

    private sealed class FakeInput : IInputSink
    {
        public bool Available => true;

        public void Apply(WireMessage message, DisplayFrame frame)
        {
        }
    }
}
