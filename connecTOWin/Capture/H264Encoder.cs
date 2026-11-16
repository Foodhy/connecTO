using System.Collections.Immutable;
using System.Runtime.InteropServices;
using ConnecTOWin.Protocol;
using Vortice;
using Vortice.MediaFoundation;

namespace ConnecTOWin;

public sealed class H264Encoder : IDisposable
{
    private static bool started;
    private readonly IMFTransform transform;
    private readonly int width;
    private readonly int height;
    private readonly bool providesSamples;
    private readonly int outputSize;
    private bool formatSent;
    private int frameCount;
    private byte[]? parameterSets;

    public H264Encoder(int width, int height, int bitRate)
    {
        this.width = width;
        this.height = height;
        EnsureStarted();
        transform = OpenTransform();
        var nv12 = VideoFormatGuids.FromFourCC(new FourCC("NV12"));
        var h264 = VideoFormatGuids.FromFourCC(new FourCC("H264"));
        using var output = MediaFactory.MFCreateMediaType();
        output.Set(MediaTypeAttributeKeys.MajorType, MediaTypeGuids.Video);
        output.Set(MediaTypeAttributeKeys.Subtype, h264);
        output.Set(MediaTypeAttributeKeys.AvgBitrate, (uint)bitRate);
        output.Set(MediaTypeAttributeKeys.FrameSize, Pack(width, height));
        output.Set(MediaTypeAttributeKeys.FrameRate, Pack(30, 1));
        output.Set(MediaTypeAttributeKeys.InterlaceMode, (uint)VideoInterlaceMode.Progressive);
        output.Set(MediaTypeAttributeKeys.Mpeg2Profile, 77u);
        output.Set(MediaTypeAttributeKeys.MaxKeyframeSpacing, 60u);
        output.Set(MediaTypeAttributeKeys.AllSamplesIndependent, 1u);
        transform.SetOutputType(0, output, 0);
        using var input = MediaFactory.MFCreateMediaType();
        input.Set(MediaTypeAttributeKeys.MajorType, MediaTypeGuids.Video);
        input.Set(MediaTypeAttributeKeys.Subtype, nv12);
        input.Set(MediaTypeAttributeKeys.FrameSize, Pack(width, height));
        input.Set(MediaTypeAttributeKeys.FrameRate, Pack(30, 1));
        input.Set(MediaTypeAttributeKeys.InterlaceMode, (uint)VideoInterlaceMode.Progressive);
        transform.SetInputType(0, input, 0);
        try
        {
            parameterSets = output.GetBlob(MediaTypeAttributeKeys.MpegSequenceHeader);
        }
        catch (Exception)
        {
            parameterSets = null;
        }

        var info = transform.GetOutputStreamInfo(0);
        providesSamples = ((uint)info.Flags & (uint)OutputStreamInfoFlags.OutputStreamProvidesSamples) != 0;
        outputSize = Math.Max((int)info.Size, width * height);
        transform.ProcessMessage(TMessageType.MessageNotifyBeginStreaming, UIntPtr.Zero);
        transform.ProcessMessage(TMessageType.MessageNotifyStartOfStream, UIntPtr.Zero);
    }

    public IReadOnlyList<VideoPacket> Encode(byte[] nv12)
    {
        frameCount++;
        using var sample = MediaFactory.MFCreateSample();
        using var buffer = MediaFactory.MFCreateMemoryBuffer(nv12.Length);
        buffer.Lock(out var pointer, out _, out _);
        Marshal.Copy(nv12, 0, pointer, nv12.Length);
        buffer.Unlock();
        buffer.CurrentLength = nv12.Length;
        sample.AddBuffer(buffer);
        var tick = 10_000_000L / 30;
        sample.SampleTime = frameCount * tick;
        sample.SampleDuration = tick;
        transform.ProcessInput(0, sample, 0);

        var packets = new List<VideoPacket>();
        while (true)
        {
            IMFSample? provided = providesSamples ? null : CreateOutputSample();
            var data = new OutputDataBuffer { Sample = provided };
            var result = transform.ProcessOutput(ProcessOutputFlags.None, 1, ref data, out _);
            if (result == ResultCode.TransformNeedMoreInput)
            {
                provided?.Dispose();
                break;
            }

            if (result.Failure || data.Sample == null)
            {
                provided?.Dispose();
                data.Sample?.Dispose();
                break;
            }

            try
            {
                using var contiguous = data.Sample.ConvertToContiguousBuffer();
                contiguous.Lock(out var encodedPointer, out _, out var current);
                var encoded = new byte[Math.Max(current, 0)];
                if (encoded.Length > 0)
                {
                    Marshal.Copy(encodedPointer, encoded, 0, encoded.Length);
                }

                contiguous.Unlock();
                Collect(encoded, packets);
            }
            finally
            {
                data.Sample.Dispose();
            }
        }

        return packets;
    }

    public void Dispose()
    {
        transform.Dispose();
    }

    private void Collect(byte[] encoded, List<VideoPacket> packets)
    {
        if (encoded.Length == 0)
        {
            return;
        }

        var units = H264Bitstream.SplitAnnexB(encoded);
        if (units.Count == 0)
        {
            EnsureFormat(packets, parameterSets);
            packets.Add(new VideoPacket.Sample(frameCount == 1 || frameCount % 60 == 0, encoded.ToImmutableArray()));
            return;
        }

        var sets = new List<byte[]>();
        var slices = new List<byte[]>();
        foreach (var unit in units)
        {
            var kind = H264Bitstream.NalType(unit);
            if (kind is 7 or 8)
            {
                sets.Add(unit);
            }
            else if (kind is not 6 and not 9)
            {
                slices.Add(unit);
            }
        }

        if (!formatSent && sets.Count > 0)
        {
            formatSent = true;
            packets.Add(new VideoPacket.Format(sets.Select(set => set.ToImmutableArray()).ToImmutableArray(), width, height));
        }
        else
        {
            EnsureFormat(packets, parameterSets);
        }

        if (slices.Count == 0)
        {
            return;
        }

        packets.Add(new VideoPacket.Sample(H264Bitstream.IsKeyframe(slices), H264Bitstream.LengthPrefixed(slices).ToImmutableArray()));
    }

    private void EnsureFormat(List<VideoPacket> packets, byte[]? header)
    {
        if (formatSent || header == null || header.Length == 0)
        {
            return;
        }

        var units = H264Bitstream.SplitAnnexB(header);
        var sets = units.Where(unit => H264Bitstream.NalType(unit) is 7 or 8).ToArray();
        if (sets.Length == 0)
        {
            sets = [header];
        }

        formatSent = true;
        packets.Add(new VideoPacket.Format(sets.Select(set => set.ToImmutableArray()).ToImmutableArray(), width, height));
    }

    private IMFSample CreateOutputSample()
    {
        var sample = MediaFactory.MFCreateSample();
        var buffer = MediaFactory.MFCreateMemoryBuffer(outputSize);
        sample.AddBuffer(buffer);
        buffer.Dispose();
        return sample;
    }

    private static IMFTransform OpenTransform()
    {
        var nv12 = VideoFormatGuids.FromFourCC(new FourCC("NV12"));
        var h264 = VideoFormatGuids.FromFourCC(new FourCC("H264"));
        var input = new RegisterTypeInfo { GuidMajorType = MediaTypeGuids.Video, GuidSubtype = nv12 };
        var output = new RegisterTypeInfo { GuidMajorType = MediaTypeGuids.Video, GuidSubtype = h264 };
        var flags = new[]
        {
            (uint)(EnumFlag.EnumFlagSortandfilter | EnumFlag.EnumFlagHardware | EnumFlag.EnumFlagSyncmft | EnumFlag.EnumFlagLocalmft),
            (uint)(EnumFlag.EnumFlagSortandfilter | EnumFlag.EnumFlagSyncmft | EnumFlag.EnumFlagLocalmft),
        };
        foreach (var flag in flags)
        {
            MediaFactory.MFTEnumEx(TransformCategoryGuids.VideoEncoder, flag, input, output, out var array, out var count);
            try
            {
                if (count == 0 || array == IntPtr.Zero)
                {
                    continue;
                }

                var activatePointer = Marshal.ReadIntPtr(array);
                var activate = new IMFActivate(activatePointer);
                var transform = activate.ActivateObject<IMFTransform>();
                activate.Dispose();
                return transform;
            }
            finally
            {
                if (array != IntPtr.Zero)
                {
                    Marshal.FreeCoTaskMem(array);
                }
            }
        }

        throw new InvalidOperationException("No hay codificador H.264.");
    }

    private static void EnsureStarted()
    {
        if (started)
        {
            return;
        }

        MediaFactory.MFStartup(false);
        started = true;
    }

    private static ulong Pack(int high, int low) => ((ulong)(uint)high << 32) | (uint)low;
}
