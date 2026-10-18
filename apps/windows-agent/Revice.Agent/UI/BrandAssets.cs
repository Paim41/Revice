using System.Reflection;

namespace Revice.Agent.UI;

internal static class BrandAssets
{
    public static Icon LoadIcon()
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("Revice.Icon.ico")!;
        using var icon = new Icon(stream);
        return (Icon)icon.Clone();
    }

    public static Image LoadHeader()
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("Revice.Header.png")!;
        using var image = Image.FromStream(stream);
        return new Bitmap(image);
    }
}
