using System.Collections.Immutable;

namespace ConnecTOWin.Protocol;

public sealed class VideoPacketException : Exception
{
    public VideoPacketException(string message) : base(message)
    {
    }
}

public abstract record VideoPacket
{
    public sealed record Format(ImmutableArray<ImmutableArray<byte>> ParameterSets, int Width, int Height) : VideoPacket;

    public sealed record Sample(bool IsKeyframe, ImmutableArray<byte> Data) : VideoPacket;

    public sealed record AudioFormat(int SampleRate, int Channels) : VideoPacket;

    public sealed record Audio(ImmutableArray<byte> Data) : VideoPacket;
}

public static class VideoPacketCodec
{
    public const int MaxFrameBytes = 2_000_000;

    public static byte[] Encode(VideoPacket packet)
    {
        var payload = Payload(packet);
        if (payload.Count > MaxFrameBytes)
        {
            throw new VideoPacketException("tooLarge");
        }

        var frame = new byte[4 + payload.Count];
        BigEndian.WriteUInt32(frame, 0, (uint)payload.Count);
        payload.CopyTo(frame, 4);
        return frame;
    }

    public static VideoPacket Decode(ReadOnlySpan<byte> payload)
    {
        if (payload.Length == 0)
        {
            throw new VideoPacketException("malformed");
        }

        switch (payload[0])
        {
            case 1:
                if (payload.Length < 7)
                {
                    throw new VideoPacketException("malformed");
                }

                var width = BigEndian.ReadUInt16(payload, 1);
                var height = BigEndian.ReadUInt16(payload, 3);
                var count = BigEndian.ReadUInt16(payload, 5);
                var index = 7;
                var sets = ImmutableArray.CreateBuilder<ImmutableArray<byte>>(count);
                for (var i = 0; i < count; i++)
                {
                    if (index + 4 > payload.Length)
                    {
                        throw new VideoPacketException("malformed");
                    }

                    var size = BigEndian.ReadUInt32(payload, index);
                    index += 4;
                    if (size < 0 || index + size > payload.Length)
                    {
                        throw new VideoPacketException("malformed");
                    }

                    sets.Add(ImmutableArray.Create(payload.Slice(index, size).ToArray()));
                    index += size;
                }

                return new VideoPacket.Format(sets.ToImmutable(), width, height);
            case 2:
                if (payload.Length < 2)
                {
                    throw new VideoPacketException("malformed");
                }

                return new VideoPacket.Sample(payload[1] == 1, ImmutableArray.Create(payload[2..].ToArray()));
            case 3:
                if (payload.Length != 7)
                {
                    throw new VideoPacketException("malformed");
                }

                return new VideoPacket.AudioFormat(BigEndian.ReadUInt32(payload, 1), BigEndian.ReadUInt16(payload, 5));
            case 4:
                if (payload.Length < 2)
                {
                    throw new VideoPacketException("malformed");
                }

                return new VideoPacket.Audio(ImmutableArray.Create(payload[1..].ToArray()));
            default:
                throw new VideoPacketException("malformed");
        }
    }

    private static List<byte> Payload(VideoPacket packet)
    {
        var data = new List<byte>();
        switch (packet)
        {
            case VideoPacket.Format format:
                if (format.Width is < 0 or > ushort.MaxValue || format.Height is < 0 or > ushort.MaxValue)
                {
                    throw new VideoPacketException("malformed");
                }

                if (format.ParameterSets.Length > ushort.MaxValue)
                {
                    throw new VideoPacketException("malformed");
                }

                data.Add(1);
                BigEndian.WriteUInt16(data, (ushort)format.Width);
                BigEndian.WriteUInt16(data, (ushort)format.Height);
                BigEndian.WriteUInt16(data, (ushort)format.ParameterSets.Length);
                foreach (var set in format.ParameterSets)
                {
                    BigEndian.WriteUInt32(data, (uint)set.Length);
                    data.AddRange(set);
                }

                break;
            case VideoPacket.Sample sample:
                data.Add(2);
                data.Add(sample.IsKeyframe ? (byte)1 : (byte)0);
                data.AddRange(sample.Data);
                break;
            case VideoPacket.AudioFormat audioFormat:
                if (audioFormat.SampleRate < 0 || audioFormat.Channels is < 0 or > ushort.MaxValue)
                {
                    throw new VideoPacketException("malformed");
                }

                data.Add(3);
                BigEndian.WriteUInt32(data, (uint)audioFormat.SampleRate);
                BigEndian.WriteUInt16(data, (ushort)audioFormat.Channels);
                break;
            case VideoPacket.Audio audio:
                if (audio.Data.IsEmpty)
                {
                    throw new VideoPacketException("malformed");
                }

                data.Add(4);
                data.AddRange(audio.Data);
                break;
        }

        return data;
    }
}

public sealed class VideoPacketDecoder
{
    private readonly List<byte> buffer = [];

    public IReadOnlyList<VideoPacket> Append(ReadOnlySpan<byte> chunk)
    {
        foreach (var value in chunk)
        {
            buffer.Add(value);
        }

        var packets = new List<VideoPacket>();
        while (buffer.Count >= 4)
        {
            var length = (buffer[0] << 24) | (buffer[1] << 16) | (buffer[2] << 8) | buffer[3];
            if (length <= 0 || length > VideoPacketCodec.MaxFrameBytes)
            {
                buffer.Clear();
                throw new VideoPacketException("tooLarge");
            }

            if (buffer.Count < 4 + length)
            {
                break;
            }

            var payload = buffer.GetRange(4, length).ToArray();
            buffer.RemoveRange(0, 4 + length);
            packets.Add(VideoPacketCodec.Decode(payload));
        }

        return packets;
    }
}
