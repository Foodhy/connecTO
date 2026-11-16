namespace ConnecTOWin.Protocol;

public sealed record SharedDisplay(uint Id, string Name, int Width, int Height);

public static class DisplayList
{
    public static IReadOnlyList<SharedDisplay> Ordered(IReadOnlyList<SharedDisplay> displays, uint mainId)
    {
        return displays
            .Select((display, index) => (display, index))
            .OrderBy(item => item.display.Id == mainId ? 0 : 1)
            .ThenBy(item => item.display.Name, StringComparer.CurrentCulture)
            .ThenBy(item => item.index)
            .Select(item => item.display)
            .ToArray();
    }

    public static uint? ResolvedId(uint? preferred, IReadOnlyList<SharedDisplay> displays, uint mainId)
    {
        if (preferred is uint wanted && displays.Any(display => display.Id == wanted))
        {
            return wanted;
        }

        if (displays.Any(display => display.Id == mainId))
        {
            return mainId;
        }

        return displays.Count > 0 ? displays[0].Id : null;
    }
}
