namespace ConnecTOWin.Protocol;

public sealed class FrameException : Exception
{
    public FrameException(string message) : base(message)
    {
    }
}

public static class FrameCodec
{
    public const int MaxFrameBytes = 8_192;

    public static byte[] Encode(WireMessage message)
    {
        var payload = WireJson.Encode(message);
        if (payload.Length > MaxFrameBytes)
        {
            throw new FrameException("tooLarge");
        }

        var frame = new byte[4 + payload.Length];
        BigEndian.WriteUInt32(frame, 0, (uint)payload.Length);
        payload.CopyTo(frame, 4);
        return frame;
    }
}

public sealed class FrameDecoder
{
    private readonly List<byte> buffer = [];

    public IReadOnlyList<WireMessage> Append(ReadOnlySpan<byte> chunk)
    {
        foreach (var value in chunk)
        {
            buffer.Add(value);
        }

        var messages = new List<WireMessage>();
        while (buffer.Count >= 4)
        {
            var length = ReadUInt32(buffer, 0);
            if (length == 0 || length > FrameCodec.MaxFrameBytes)
            {
                buffer.Clear();
                throw new FrameException("tooLarge");
            }

            if (buffer.Count < 4 + length)
            {
                break;
            }

            var payload = buffer.GetRange(4, (int)length).ToArray();
            buffer.RemoveRange(0, 4 + (int)length);
            messages.Add(WireJson.Decode(payload));
        }

        return messages;
    }

    private static int ReadUInt32(List<byte> data, int index)
    {
        return (data[index] << 24) | (data[index + 1] << 16) | (data[index + 2] << 8) | data[index + 3];
    }
}

internal static class BigEndian
{
    public static void WriteUInt32(byte[] data, int index, uint value)
    {
        data[index] = (byte)(value >> 24);
        data[index + 1] = (byte)(value >> 16);
        data[index + 2] = (byte)(value >> 8);
        data[index + 3] = (byte)value;
    }

    public static void WriteUInt32(List<byte> data, uint value)
    {
        data.Add((byte)(value >> 24));
        data.Add((byte)(value >> 16));
        data.Add((byte)(value >> 8));
        data.Add((byte)value);
    }

    public static void WriteUInt16(List<byte> data, ushort value)
    {
        data.Add((byte)(value >> 8));
        data.Add((byte)value);
    }

    public static int ReadUInt32(ReadOnlySpan<byte> data, int index)
    {
        return (data[index] << 24) | (data[index + 1] << 16) | (data[index + 2] << 8) | data[index + 3];
    }

    public static int ReadUInt16(ReadOnlySpan<byte> data, int index)
    {
        return (data[index] << 8) | data[index + 1];
    }
}
