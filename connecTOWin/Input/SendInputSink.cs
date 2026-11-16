using System.Runtime.InteropServices;
using ConnecTOWin.Protocol;

namespace ConnecTOWin;

public sealed class SendInputSink : IInputSink
{
    private double fractionX;
    private double fractionY;

    public bool Available => OperatingSystem.IsWindows();

    public void Apply(WireMessage message, DisplayFrame frame)
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        switch (message)
        {
            case WireMessage.Pointer pointer:
                Move(pointer.Dx, pointer.Dy);
                break;
            case WireMessage.Cursor cursor:
                MoveAbsolute(cursor.X, cursor.Y, frame);
                break;
            case WireMessage.Button button:
                Click(button.Which, button.Phase);
                break;
            case WireMessage.Scroll scroll:
                Wheel(scroll.Dx, scroll.Dy);
                break;
            case WireMessage.Key key:
                TypeKey(key.KeyCode, key.Phase == ButtonPhase.Down, key.Modifiers);
                break;
            case WireMessage.Text text:
                TypeText(text.Value);
                break;
            case WireMessage.Media media:
                Tap(KeyTranslation.ForMedia(media.Action));
                break;
        }
    }

    private void Move(double dx, double dy)
    {
        var scaled = PointerGain.CursorDelta(dx, dy);
        fractionX += scaled.Dx;
        fractionY += scaled.Dy;
        var stepX = (int)Math.Round(fractionX);
        var stepY = (int)Math.Round(fractionY);
        fractionX -= stepX;
        fractionY -= stepY;
        if (stepX == 0 && stepY == 0)
        {
            return;
        }

        Send(Mouse(stepX, stepY, MouseMove, 0));
    }

    private static void MoveAbsolute(double x, double y, DisplayFrame frame)
    {
        if (frame.Width <= 0 || frame.Height <= 0)
        {
            return;
        }

        var pixelX = frame.X + (int)Math.Round(x * frame.Width);
        var pixelY = frame.Y + (int)Math.Round(y * frame.Height);
        var originX = GetSystemMetrics(VirtualX);
        var originY = GetSystemMetrics(VirtualY);
        var width = Math.Max(GetSystemMetrics(VirtualWidth) - 1, 1);
        var height = Math.Max(GetSystemMetrics(VirtualHeight) - 1, 1);
        var absoluteX = (int)Math.Round((pixelX - originX) * 65535.0 / width);
        var absoluteY = (int)Math.Round((pixelY - originY) * 65535.0 / height);
        Send(Mouse(absoluteX, absoluteY, MouseMove | MouseAbsolute | MouseVirtualDesk, 0));
    }

    private void Click(MouseButton button, ButtonPhase phase)
    {
        var down = phase == ButtonPhase.Down;
        var flag = button == MouseButton.Left
            ? (down ? MouseLeftDown : MouseLeftUp)
            : (down ? MouseRightDown : MouseRightUp);
        Send(Mouse(0, 0, flag, 0));
    }

    private static void Wheel(double dx, double dy)
    {
        var vertical = Clamp(-dy);
        var horizontal = Clamp(-dx);
        if (vertical != 0)
        {
            Send(Mouse(0, 0, MouseWheel, vertical));
        }

        if (horizontal != 0)
        {
            Send(Mouse(0, 0, MouseHorizontal, horizontal));
        }
    }

    private static void TypeKey(ushort macCode, bool down, KeyModifiers modifiers)
    {
        var strokes = KeyTranslation.ForKey(macCode, down, modifiers);
        if (strokes.Count == 1 && strokes[0].VirtualKey is not (KeyTranslation.VkLWin or KeyTranslation.VkControl or KeyTranslation.VkMenu or KeyTranslation.VkShift))
        {
            var stroke = strokes[0];
            var batch = new List<Input>();
            if (stroke.Down)
            {
                if (stroke.Control) batch.Add(Key(KeyTranslation.VkControl, false));
                if (stroke.Alt) batch.Add(Key(KeyTranslation.VkMenu, false));
                if (stroke.Shift) batch.Add(Key(KeyTranslation.VkShift, false));
                batch.Add(Key(stroke.VirtualKey, false));
            }
            else
            {
                batch.Add(Key(stroke.VirtualKey, true));
                if (stroke.Shift) batch.Add(Key(KeyTranslation.VkShift, true));
                if (stroke.Alt) batch.Add(Key(KeyTranslation.VkMenu, true));
                if (stroke.Control) batch.Add(Key(KeyTranslation.VkControl, true));
            }

            Send(batch);
            return;
        }

        Tap(strokes);
    }

    private static void Tap(IReadOnlyList<KeyStroke> strokes)
    {
        if (strokes.Count == 0)
        {
            return;
        }

        var batch = new List<Input>(strokes.Count);
        foreach (var stroke in strokes)
        {
            batch.Add(Key(stroke.VirtualKey, !stroke.Down));
        }

        Send(batch);
    }

    private static void TypeText(string text)
    {
        var batch = new List<Input>();
        foreach (var unit in text)
        {
            batch.Add(Unicode(unit, false));
            batch.Add(Unicode(unit, true));
        }

        Send(batch);
    }

    private static int Clamp(double value) => (int)Math.Clamp(Math.Round(value), -2000, 2000);

    private const uint MouseMove = 0x0001;
    private const uint MouseLeftDown = 0x0002;
    private const uint MouseLeftUp = 0x0004;
    private const uint MouseRightDown = 0x0008;
    private const uint MouseRightUp = 0x0010;
    private const uint MouseWheel = 0x0800;
    private const uint MouseHorizontal = 0x1000;
    private const uint MouseAbsolute = 0x8000;
    private const uint MouseVirtualDesk = 0x4000;
    private const uint KeyUp = 0x0002;
    private const uint KeyUnicode = 0x0004;
    private const int VirtualX = 76;
    private const int VirtualY = 77;
    private const int VirtualWidth = 78;
    private const int VirtualHeight = 79;

    private static Input Mouse(int x, int y, uint flags, int data) => new()
    {
        Type = 0,
        Mouse = new MouseInput { X = x, Y = y, Data = data, Flags = flags },
    };

    private static Input Key(ushort virtualKey, bool up) => new()
    {
        Type = 1,
        Key = new KeyInput { VirtualKey = virtualKey, Flags = up ? KeyUp : 0 },
    };

    private static Input Unicode(char unit, bool up) => new()
    {
        Type = 1,
        Key = new KeyInput { Scan = unit, Flags = KeyUnicode | (up ? KeyUp : 0) },
    };

    private static void Send(Input input) => Send([input]);

    private static void Send(List<Input> inputs)
    {
        if (inputs.Count == 0)
        {
            return;
        }

        var array = inputs.ToArray();
        SendInput((uint)array.Length, array, Marshal.SizeOf<Input>());
    }

    [DllImport("user32.dll")]
    private static extern uint SendInput(uint count, Input[] inputs, int size);

    [DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int index);

    [StructLayout(LayoutKind.Sequential)]
    private struct Input
    {
        public uint Type;
        public InputUnion Union;

        public MouseInput Mouse
        {
            get => Union.Mouse;
            set => Union.Mouse = value;
        }

        public KeyInput Key
        {
            get => Union.Key;
            set => Union.Key = value;
        }
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)]
        public MouseInput Mouse;

        [FieldOffset(0)]
        public KeyInput Key;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MouseInput
    {
        public int X;
        public int Y;
        public int Data;
        public uint Flags;
        public uint Time;
        public nint Extra;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KeyInput
    {
        public ushort VirtualKey;
        public ushort Scan;
        public uint Flags;
        public uint Time;
        public nint Extra;
    }
}
