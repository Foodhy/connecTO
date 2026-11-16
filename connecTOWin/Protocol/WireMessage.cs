using System.Collections.Immutable;
using System.Text.Json;

namespace ConnecTOWin.Protocol;

public static class ProtocolVersion
{
    public const int Current = 1;
}

public enum RejectReason
{
    BadCode,
    ExpiredCode,
    UnsupportedVersion,
    NotPaired,
}

public enum MouseButton
{
    Left,
    Right,
}

public enum ButtonPhase
{
    Down,
    Up,
}

[Flags]
public enum KeyModifiers
{
    None = 0,
    Command = 1 << 0,
    Option = 1 << 1,
    Shift = 1 << 2,
    Control = 1 << 3,
}

public enum MediaAction
{
    VolumeUp,
    VolumeDown,
    Mute,
    PlayPause,
    Next,
    Previous,
}

public enum LinkMode
{
    Control,
    Extend,
}

public static class SpecialKey
{
    public const ushort Return = 36;
    public const ushort Tab = 48;
    public const ushort Space = 49;
    public const ushort Delete = 51;
    public const ushort Escape = 53;
    public const ushort Left = 123;
    public const ushort Right = 124;
    public const ushort Down = 125;
    public const ushort Up = 126;
}

public abstract record WireMessage
{
    public sealed record Hello(Guid DeviceId, string DeviceName, int ProtocolVersion) : WireMessage;

    public sealed record Pair(string Code, Guid DeviceId, string DeviceName) : WireMessage;

    public sealed record Paired(Guid Session) : WireMessage;

    public sealed record NeedCode : WireMessage;

    public sealed record Rejected(RejectReason Reason) : WireMessage;

    public sealed record Pointer(double Dx, double Dy) : WireMessage;

    public sealed record Button(MouseButton Which, ButtonPhase Phase) : WireMessage;

    public sealed record Scroll(double Dx, double Dy) : WireMessage;

    public sealed record Key(ushort KeyCode, ButtonPhase Phase, KeyModifiers Modifiers) : WireMessage;

    public sealed record Text(string Value) : WireMessage;

    public sealed record Media(MediaAction Action) : WireMessage;

    public sealed record Cursor(double X, double Y) : WireMessage;

    public sealed record Quality(int LongSide) : WireMessage;

    public sealed record VideoHello(Guid DeviceId) : WireMessage;

    public sealed record ScreenUnavailable : WireMessage;

    public sealed record Displays(ImmutableArray<SharedDisplay> Items, uint Active) : WireMessage;

    public sealed record Screen(uint DisplayId) : WireMessage;

    public sealed record Audio(bool Enabled) : WireMessage;

    public sealed record Role(LinkMode Mode) : WireMessage;

    public sealed record Ping : WireMessage;

    public sealed record Pong : WireMessage;
}

public static class WireJson
{
    public static byte[] Encode(WireMessage message)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            Write(writer, message);
        }

        return stream.ToArray();
    }

    public static WireMessage Decode(ReadOnlySpan<byte> json)
    {
        using var document = JsonDocument.Parse(json.ToArray());
        var root = document.RootElement;
        var type = root.GetProperty("type").GetString() ?? "";
        return type switch
        {
            "hello" => new WireMessage.Hello(ReadGuid(root, "deviceID"), ReadString(root, "deviceName"), root.GetProperty("protocolVersion").GetInt32()),
            "pair" => new WireMessage.Pair(ReadString(root, "code"), ReadGuid(root, "deviceID"), ReadString(root, "deviceName")),
            "paired" => new WireMessage.Paired(ReadGuid(root, "session")),
            "needCode" => new WireMessage.NeedCode(),
            "rejected" => new WireMessage.Rejected(ParseReject(ReadString(root, "reason"))),
            "pointer" => new WireMessage.Pointer(root.GetProperty("dx").GetDouble(), root.GetProperty("dy").GetDouble()),
            "button" => new WireMessage.Button(ParseButton(ReadString(root, "button")), ParsePhase(ReadString(root, "phase"))),
            "scroll" => new WireMessage.Scroll(root.GetProperty("dx").GetDouble(), root.GetProperty("dy").GetDouble()),
            "key" => new WireMessage.Key((ushort)root.GetProperty("keyCode").GetInt32(), ParsePhase(ReadString(root, "phase")), (KeyModifiers)root.GetProperty("modifiers").GetInt32()),
            "text" => new WireMessage.Text(ReadString(root, "text")),
            "media" => new WireMessage.Media(ParseMedia(ReadString(root, "action"))),
            "cursor" => new WireMessage.Cursor(root.GetProperty("x").GetDouble(), root.GetProperty("y").GetDouble()),
            "quality" => new WireMessage.Quality(root.GetProperty("longSide").GetInt32()),
            "videoHello" => new WireMessage.VideoHello(ReadGuid(root, "deviceID")),
            "screenUnavailable" => new WireMessage.ScreenUnavailable(),
            "displays" => new WireMessage.Displays(ReadDisplays(root.GetProperty("displays")), root.GetProperty("active").GetUInt32()),
            "screen" => new WireMessage.Screen(root.GetProperty("displayID").GetUInt32()),
            "audio" => new WireMessage.Audio(root.GetProperty("enabled").GetBoolean()),
            "role" => new WireMessage.Role(ParseMode(ReadString(root, "mode"))),
            "ping" => new WireMessage.Ping(),
            "pong" => new WireMessage.Pong(),
            _ => throw new JsonException($"Tipo de mensaje desconocido: {type}"),
        };
    }

    private static void Write(Utf8JsonWriter writer, WireMessage message)
    {
        writer.WriteStartObject();
        switch (message)
        {
            case WireMessage.Hello hello:
                writer.WriteString("type", "hello");
                writer.WriteString("deviceID", GuidText(hello.DeviceId));
                writer.WriteString("deviceName", hello.DeviceName);
                writer.WriteNumber("protocolVersion", hello.ProtocolVersion);
                break;
            case WireMessage.Pair pair:
                writer.WriteString("type", "pair");
                writer.WriteString("code", pair.Code);
                writer.WriteString("deviceID", GuidText(pair.DeviceId));
                writer.WriteString("deviceName", pair.DeviceName);
                break;
            case WireMessage.Paired paired:
                writer.WriteString("type", "paired");
                writer.WriteString("session", GuidText(paired.Session));
                break;
            case WireMessage.NeedCode:
                writer.WriteString("type", "needCode");
                break;
            case WireMessage.Rejected rejected:
                writer.WriteString("type", "rejected");
                writer.WriteString("reason", RejectText(rejected.Reason));
                break;
            case WireMessage.Pointer pointer:
                writer.WriteString("type", "pointer");
                writer.WriteNumber("dx", pointer.Dx);
                writer.WriteNumber("dy", pointer.Dy);
                break;
            case WireMessage.Button button:
                writer.WriteString("type", "button");
                writer.WriteString("button", button.Which == MouseButton.Left ? "left" : "right");
                writer.WriteString("phase", button.Phase == ButtonPhase.Down ? "down" : "up");
                break;
            case WireMessage.Scroll scroll:
                writer.WriteString("type", "scroll");
                writer.WriteNumber("dx", scroll.Dx);
                writer.WriteNumber("dy", scroll.Dy);
                break;
            case WireMessage.Key key:
                writer.WriteString("type", "key");
                writer.WriteNumber("keyCode", key.KeyCode);
                writer.WriteString("phase", key.Phase == ButtonPhase.Down ? "down" : "up");
                writer.WriteNumber("modifiers", (int)key.Modifiers);
                break;
            case WireMessage.Text text:
                writer.WriteString("type", "text");
                writer.WriteString("text", text.Value);
                break;
            case WireMessage.Media media:
                writer.WriteString("type", "media");
                writer.WriteString("action", MediaText(media.Action));
                break;
            case WireMessage.Cursor cursor:
                writer.WriteString("type", "cursor");
                writer.WriteNumber("x", cursor.X);
                writer.WriteNumber("y", cursor.Y);
                break;
            case WireMessage.Quality quality:
                writer.WriteString("type", "quality");
                writer.WriteNumber("longSide", quality.LongSide);
                break;
            case WireMessage.VideoHello videoHello:
                writer.WriteString("type", "videoHello");
                writer.WriteString("deviceID", GuidText(videoHello.DeviceId));
                break;
            case WireMessage.ScreenUnavailable:
                writer.WriteString("type", "screenUnavailable");
                break;
            case WireMessage.Displays displays:
                writer.WriteString("type", "displays");
                writer.WritePropertyName("displays");
                writer.WriteStartArray();
                foreach (var item in displays.Items)
                {
                    writer.WriteStartObject();
                    writer.WriteNumber("id", item.Id);
                    writer.WriteString("name", item.Name);
                    writer.WriteNumber("width", item.Width);
                    writer.WriteNumber("height", item.Height);
                    writer.WriteEndObject();
                }

                writer.WriteEndArray();
                writer.WriteNumber("active", displays.Active);
                break;
            case WireMessage.Screen screen:
                writer.WriteString("type", "screen");
                writer.WriteNumber("displayID", screen.DisplayId);
                break;
            case WireMessage.Audio audio:
                writer.WriteString("type", "audio");
                writer.WriteBoolean("enabled", audio.Enabled);
                break;
            case WireMessage.Role role:
                writer.WriteString("type", "role");
                writer.WriteString("mode", role.Mode == LinkMode.Extend ? "extend" : "control");
                break;
            case WireMessage.Ping:
                writer.WriteString("type", "ping");
                break;
            case WireMessage.Pong:
                writer.WriteString("type", "pong");
                break;
        }

        writer.WriteEndObject();
    }

    private static string GuidText(Guid id) => id.ToString("D").ToUpperInvariant();

    private static Guid ReadGuid(JsonElement root, string name)
    {
        var raw = ReadString(root, name);
        if (!Guid.TryParse(raw, out var id))
        {
            throw new JsonException("UUID inválido");
        }

        return id;
    }

    private static string ReadString(JsonElement root, string name) => root.GetProperty(name).GetString() ?? "";

    private static ImmutableArray<SharedDisplay> ReadDisplays(JsonElement array)
    {
        var builder = ImmutableArray.CreateBuilder<SharedDisplay>();
        foreach (var item in array.EnumerateArray())
        {
            builder.Add(new SharedDisplay(
                item.GetProperty("id").GetUInt32(),
                item.GetProperty("name").GetString() ?? "",
                item.GetProperty("width").GetInt32(),
                item.GetProperty("height").GetInt32()));
        }

        return builder.ToImmutable();
    }

    private static RejectReason ParseReject(string value) => value switch
    {
        "badCode" => RejectReason.BadCode,
        "expiredCode" => RejectReason.ExpiredCode,
        "unsupportedVersion" => RejectReason.UnsupportedVersion,
        "notPaired" => RejectReason.NotPaired,
        _ => throw new JsonException(value),
    };

    private static string RejectText(RejectReason reason) => reason switch
    {
        RejectReason.BadCode => "badCode",
        RejectReason.ExpiredCode => "expiredCode",
        RejectReason.UnsupportedVersion => "unsupportedVersion",
        RejectReason.NotPaired => "notPaired",
        _ => throw new ArgumentOutOfRangeException(nameof(reason)),
    };

    private static MouseButton ParseButton(string value) => value switch
    {
        "left" => MouseButton.Left,
        "right" => MouseButton.Right,
        _ => throw new JsonException(value),
    };

    private static ButtonPhase ParsePhase(string value) => value switch
    {
        "down" => ButtonPhase.Down,
        "up" => ButtonPhase.Up,
        _ => throw new JsonException(value),
    };

    private static MediaAction ParseMedia(string value) => value switch
    {
        "volumeUp" => MediaAction.VolumeUp,
        "volumeDown" => MediaAction.VolumeDown,
        "mute" => MediaAction.Mute,
        "playPause" => MediaAction.PlayPause,
        "next" => MediaAction.Next,
        "previous" => MediaAction.Previous,
        _ => throw new JsonException(value),
    };

    private static string MediaText(MediaAction action) => action switch
    {
        MediaAction.VolumeUp => "volumeUp",
        MediaAction.VolumeDown => "volumeDown",
        MediaAction.Mute => "mute",
        MediaAction.PlayPause => "playPause",
        MediaAction.Next => "next",
        MediaAction.Previous => "previous",
        _ => throw new ArgumentOutOfRangeException(nameof(action)),
    };

    private static LinkMode ParseMode(string value) => value switch
    {
        "control" => LinkMode.Control,
        "extend" => LinkMode.Extend,
        _ => throw new JsonException(value),
    };
}
