namespace ConnecTOWin.Protocol;

public sealed class SessionMachine
{
    public HashSet<Guid> TrustedDeviceIds { get; set; }

    public PairingCode Code { get; set; }

    public Phase Current { get; set; } = Phase.Waiting.Instance;

    public SessionMachine(IEnumerable<Guid> trustedDeviceIds, PairingCode code)
    {
        TrustedDeviceIds = trustedDeviceIds.ToHashSet();
        Code = code;
    }

    public abstract record Phase
    {
        public sealed record Waiting : Phase
        {
            public static readonly Waiting Instance = new();
        }

        public sealed record Paired(Guid DeviceId, Guid Session) : Phase;
    }

    public abstract record Effect
    {
        public sealed record Reply(WireMessage Message) : Effect;

        public sealed record Input(WireMessage Message) : Effect;

        public sealed record Drop : Effect
        {
            public static readonly Drop Instance = new();
        }
    }

    public Effect Handle(WireMessage message, DateTime now, Func<Guid>? newSessionId = null)
    {
        newSessionId ??= Guid.NewGuid;
        switch (message)
        {
            case WireMessage.Hello hello:
                if (hello.ProtocolVersion != ProtocolVersion.Current)
                {
                    return new Effect.Reply(new WireMessage.Rejected(RejectReason.UnsupportedVersion));
                }

                if (!TrustedDeviceIds.Contains(hello.DeviceId))
                {
                    return new Effect.Reply(new WireMessage.NeedCode());
                }

                return Pair(hello.DeviceId, newSessionId());
            case WireMessage.Pair pair:
                switch (Code.Matches(pair.Code, now))
                {
                    case PairingCode.Match.Expired:
                        return new Effect.Reply(new WireMessage.Rejected(RejectReason.ExpiredCode));
                    case PairingCode.Match.Mismatch:
                        return new Effect.Reply(new WireMessage.Rejected(RejectReason.BadCode));
                    default:
                        TrustedDeviceIds.Add(pair.DeviceId);
                        return Pair(pair.DeviceId, newSessionId());
                }
            case WireMessage.Pointer
                or WireMessage.Button
                or WireMessage.Scroll
                or WireMessage.Key
                or WireMessage.Text
                or WireMessage.Media
                or WireMessage.Cursor
                or WireMessage.Quality
                or WireMessage.Screen
                or WireMessage.Audio
                or WireMessage.Role:
                if (Current is not Phase.Paired)
                {
                    return new Effect.Reply(new WireMessage.Rejected(RejectReason.NotPaired));
                }

                return new Effect.Input(message);
            case WireMessage.Ping:
                return new Effect.Reply(new WireMessage.Pong());
            default:
                return Effect.Drop.Instance;
        }
    }

    private Effect Pair(Guid deviceId, Guid session)
    {
        Current = new Phase.Paired(deviceId, session);
        return new Effect.Reply(new WireMessage.Paired(session));
    }
}
