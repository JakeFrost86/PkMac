namespace PluginPile.Sorting;

/// <summary>
/// Drop-in replacement for PluginPile's WinForms ApplicationSettings class.
/// PkMac sets these values per request from its own preferences.
/// </summary>
public sealed class PluginSettings
{
    public static PluginSettings Default { get; } = new();

    public bool ShowIndividualPokédexes { get; set; }
    public int SortBeginBox { get; set; } = 1;
    public int SortEndBox { get; set; } = -1;
    public bool CheckForms { get; set; } = true;
    public SortOptions[] AdditionalSortOptions { get; set; } = [];

    public enum SortOptions
    {
        LevelAsc,
        LevelDesc,
        MetDateAsc,
        ShinyAsc,
        ShinyDesc,
        GenderAsc,
        GenderDesc,
    }
}
