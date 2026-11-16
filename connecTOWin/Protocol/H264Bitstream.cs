namespace ConnecTOWin.Protocol;

public static class H264Bitstream
{
    public static List<byte[]> SplitAnnexB(ReadOnlySpan<byte> data)
    {
        var markers = new List<(int Code, int Payload)>();
        for (var index = 0; index + 3 < data.Length; index++)
        {
            if (index + 4 < data.Length
                && data[index] == 0
                && data[index + 1] == 0
                && data[index + 2] == 0
                && data[index + 3] == 1)
            {
                markers.Add((index, index + 4));
                index += 3;
                continue;
            }

            if (data[index] == 0 && data[index + 1] == 0 && data[index + 2] == 1)
            {
                markers.Add((index, index + 3));
                index += 2;
            }
        }

        var units = new List<byte[]>();
        for (var i = 0; i < markers.Count; i++)
        {
            var start = markers[i].Payload;
            var end = i + 1 < markers.Count ? markers[i + 1].Code : data.Length;
            if (start < end)
            {
                units.Add(data.Slice(start, end - start).ToArray());
            }
        }

        return units;
    }

    public static byte[] LengthPrefixed(IReadOnlyList<byte[]> units)
    {
        var size = 0;
        foreach (var unit in units)
        {
            size += 4 + unit.Length;
        }

        var data = new byte[size];
        var index = 0;
        foreach (var unit in units)
        {
            BigEndian.WriteUInt32(data, index, (uint)unit.Length);
            index += 4;
            unit.CopyTo(data.AsSpan(index));
            index += unit.Length;
        }

        return data;
    }

    public static int NalType(ReadOnlySpan<byte> unit) => unit.Length == 0 ? 0 : unit[0] & 0x1F;

    public static bool IsKeyframe(IReadOnlyList<byte[]> units)
    {
        foreach (var unit in units)
        {
            if (NalType(unit) == 5)
            {
                return true;
            }
        }

        return false;
    }
}
