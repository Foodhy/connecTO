namespace ConnecTOWin.Protocol;

public readonly record struct PairingCode(string Digits, DateTime ExpiresAt)
{
    public const int Length = 6;
    public static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(3);

    public enum Match
    {
        Match,
        Mismatch,
        Expired,
    }

    public Match Matches(string entry, DateTime now)
    {
        if (now >= ExpiresAt)
        {
            return Match.Expired;
        }

        var digits = string.Concat(entry.Where(char.IsDigit));
        if (digits.Length == Length && digits == Digits)
        {
            return Match.Match;
        }

        return Match.Mismatch;
    }

    public static string Grouped(string digits)
    {
        if (digits.Length != Length)
        {
            return digits;
        }

        return digits[..3] + " " + digits[3..];
    }

    public static string RandomDigits()
    {
        return Random.Shared.Next(0, 1_000_000).ToString("D6");
    }

    public static PairingCode Make(string digits, DateTime now, TimeSpan? lifetime = null)
    {
        return new PairingCode(digits, now + (lifetime ?? Lifetime));
    }
}
