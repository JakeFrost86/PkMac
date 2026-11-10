using PKHeX.Core;

namespace PkMac.Engine;

/// <summary>ALM parses and builds sets with the current GameInfo strings: it is written for English.</summary>
public sealed class EnglishScope : IDisposable
{
    private readonly string _lang = GameInfo.CurrentLanguage;
    private readonly GameStrings _strings = GameInfo.Strings;
    public EnglishScope() { GameInfo.CurrentLanguage = "en"; GameInfo.Strings = GameInfo.GetStrings("en"); }
    public void Dispose() { GameInfo.CurrentLanguage = _lang; GameInfo.Strings = _strings; }
}
