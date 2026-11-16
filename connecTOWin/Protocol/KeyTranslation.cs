namespace ConnecTOWin.Protocol;

public readonly record struct KeyStroke(ushort VirtualKey, bool Down, bool Win, bool Control, bool Alt, bool Shift);

public static class KeyTranslation
{
    public const ushort VkControl = 0x11;
    public const ushort VkMenu = 0x12;
    public const ushort VkShift = 0x10;
    public const ushort VkLWin = 0x5B;
    public const ushort VkTab = 0x09;
    public const ushort VkLeft = 0x25;
    public const ushort VkUp = 0x26;
    public const ushort VkRight = 0x27;
    public const ushort VkDown = 0x28;
    public const ushort VkVolumeMute = 0xAD;
    public const ushort VkVolumeDown = 0xAE;
    public const ushort VkVolumeUp = 0xAF;
    public const ushort VkMediaNext = 0xB0;
    public const ushort VkMediaPrev = 0xB1;
    public const ushort VkMediaPlayPause = 0xB3;

    private static readonly IReadOnlyDictionary<ushort, ushort> MacToVirtual = BuildMap();

    public static IReadOnlyList<KeyStroke> ForKey(ushort macCode, bool down, KeyModifiers modifiers)
    {
        if (modifiers == KeyModifiers.Control && IsDesktopArrow(macCode))
        {
            return down ? DesktopChord(macCode) : [];
        }

        if (!MacToVirtual.TryGetValue(macCode, out var virtualKey))
        {
            return [];
        }

        var control = modifiers.HasFlag(KeyModifiers.Command) || modifiers.HasFlag(KeyModifiers.Control);
        var alt = modifiers.HasFlag(KeyModifiers.Option);
        var shift = modifiers.HasFlag(KeyModifiers.Shift);
        if (down)
        {
            return [new KeyStroke(virtualKey, true, false, control, alt, shift)];
        }

        return [new KeyStroke(virtualKey, false, false, control, alt, shift)];
    }

    public static IReadOnlyList<KeyStroke> ForMedia(MediaAction action)
    {
        var key = action switch
        {
            MediaAction.VolumeUp => VkVolumeUp,
            MediaAction.VolumeDown => VkVolumeDown,
            MediaAction.Mute => VkVolumeMute,
            MediaAction.PlayPause => VkMediaPlayPause,
            MediaAction.Next => VkMediaNext,
            MediaAction.Previous => VkMediaPrev,
            _ => (ushort)0,
        };
        if (key == 0)
        {
            return [];
        }

        return [new KeyStroke(key, true, false, false, false, false), new KeyStroke(key, false, false, false, false, false)];
    }

    public static bool TryVirtualKey(ushort macCode, out ushort virtualKey) => MacToVirtual.TryGetValue(macCode, out virtualKey);

    private static bool IsDesktopArrow(ushort code)
    {
        return code is SpecialKey.Left or SpecialKey.Right or SpecialKey.Up or SpecialKey.Down;
    }

    private static KeyStroke[] DesktopChord(ushort arrow)
    {
        if (arrow is SpecialKey.Up or SpecialKey.Down)
        {
            return
            [
                new KeyStroke(VkLWin, true, true, false, false, false),
                new KeyStroke(VkTab, true, true, false, false, false),
                new KeyStroke(VkTab, false, true, false, false, false),
                new KeyStroke(VkLWin, false, false, false, false, false),
            ];
        }

        var key = arrow == SpecialKey.Left ? VkLeft : VkRight;
        return
        [
            new KeyStroke(VkLWin, true, true, true, false, false),
            new KeyStroke(VkControl, true, true, true, false, false),
            new KeyStroke(key, true, true, true, false, false),
            new KeyStroke(key, false, true, true, false, false),
            new KeyStroke(VkControl, false, true, false, false, false),
            new KeyStroke(VkLWin, false, false, false, false, false),
        ];
    }

    private static Dictionary<ushort, ushort> BuildMap()
    {
        var hidToMac = new Dictionary<int, ushort>
        {
            [4] = 0, [5] = 11, [6] = 8, [7] = 2, [8] = 14, [9] = 3, [10] = 5, [11] = 4, [12] = 34, [13] = 38,
            [14] = 40, [15] = 37, [16] = 46, [17] = 45, [18] = 31, [19] = 35, [20] = 12, [21] = 15, [22] = 1, [23] = 17,
            [24] = 32, [25] = 9, [26] = 13, [27] = 7, [28] = 16, [29] = 6,
            [30] = 18, [31] = 19, [32] = 20, [33] = 21, [34] = 23, [35] = 22, [36] = 26, [37] = 28, [38] = 25, [39] = 29,
            [40] = 36, [41] = 53, [42] = 51, [43] = 48, [44] = 49, [45] = 27, [46] = 24, [47] = 33, [48] = 30, [49] = 42,
            [51] = 41, [52] = 39, [53] = 50, [54] = 43, [55] = 47, [56] = 44, [57] = 57,
            [58] = 122, [59] = 120, [60] = 99, [61] = 118, [62] = 96, [63] = 97, [64] = 98, [65] = 100, [66] = 101, [67] = 109, [68] = 103, [69] = 111,
            [74] = 115, [75] = 116, [76] = 117, [77] = 119, [78] = 121,
            [79] = 124, [80] = 123, [81] = 125, [82] = 126,
            [83] = 71, [84] = 75, [85] = 67, [86] = 78, [87] = 69, [88] = 76,
            [89] = 83, [90] = 84, [91] = 85, [92] = 86, [93] = 87, [94] = 88, [95] = 89, [96] = 91, [97] = 92, [98] = 82, [99] = 65,
            [100] = 10,
        };

        var hidToVirtual = new Dictionary<int, ushort>();
        for (var hid = 4; hid <= 29; hid++)
        {
            hidToVirtual[hid] = (ushort)(0x41 + (hid - 4));
        }

        ushort[] digits = [0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30];
        for (var i = 0; i < digits.Length; i++)
        {
            hidToVirtual[30 + i] = digits[i];
        }

        hidToVirtual[40] = 0x0D;
        hidToVirtual[41] = 0x1B;
        hidToVirtual[42] = 0x08;
        hidToVirtual[43] = 0x09;
        hidToVirtual[44] = 0x20;
        hidToVirtual[45] = 0xBD;
        hidToVirtual[46] = 0xBB;
        hidToVirtual[47] = 0xDB;
        hidToVirtual[48] = 0xDD;
        hidToVirtual[49] = 0xDC;
        hidToVirtual[51] = 0xBA;
        hidToVirtual[52] = 0xDE;
        hidToVirtual[53] = 0xC0;
        hidToVirtual[54] = 0xBC;
        hidToVirtual[55] = 0xBE;
        hidToVirtual[56] = 0xBF;
        hidToVirtual[57] = 0x14;
        for (var f = 0; f < 12; f++)
        {
            hidToVirtual[58 + f] = (ushort)(0x70 + f);
        }

        hidToVirtual[74] = 0x24;
        hidToVirtual[75] = 0x21;
        hidToVirtual[76] = 0x2E;
        hidToVirtual[77] = 0x23;
        hidToVirtual[78] = 0x22;
        hidToVirtual[79] = VkRight;
        hidToVirtual[80] = VkLeft;
        hidToVirtual[81] = VkDown;
        hidToVirtual[82] = VkUp;
        hidToVirtual[83] = 0x90;
        hidToVirtual[84] = 0x6F;
        hidToVirtual[85] = 0x6A;
        hidToVirtual[86] = 0x6D;
        hidToVirtual[87] = 0x6B;
        hidToVirtual[88] = 0x0D;
        for (var n = 0; n < 9; n++)
        {
            hidToVirtual[89 + n] = (ushort)(0x61 + n);
        }

        hidToVirtual[98] = 0x60;
        hidToVirtual[99] = 0x6E;
        hidToVirtual[100] = 0xE2;

        var map = new Dictionary<ushort, ushort>();
        foreach (var (hid, mac) in hidToMac)
        {
            if (hidToVirtual.TryGetValue(hid, out var virtualKey))
            {
                map[mac] = virtualKey;
            }
        }

        return map;
    }
}
