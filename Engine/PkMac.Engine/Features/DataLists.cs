using PKHeX.Core;

namespace PkMac.Engine.Features;

/// <summary>Localized pick lists filtered for the loaded game (species, moves, items...).</summary>
public static class DataLists
{
    public static object All(Session s)
    {
        var src = GameInfo.FilteredSources;
        object Map(IEnumerable<ComboItem> items) => items.Where(i => i.Value >= 0).Select(i => new { v = i.Value, t = i.Text }).ToArray();
        var ctx = s.Sav.Context;
        return new
        {
            language = s.Language,
            species = Map(src.Species),
            moves = src.Moves.Where(m => m.Value >= 0).Select(m => new
            {
                v = m.Value,
                t = m.Text,
                type = m.Value == 0 ? null : Describe.TypeKey(s, MoveInfo.GetType((ushort)m.Value, ctx)),
            }).ToArray(),
            items = Map(src.Items),
            natures = Map(src.Natures),
            balls = src.Balls.Where(b => b.Value > 0).Select(b => new { v = b.Value, t = b.Text, key = Describe.AssetKey(Describe.Name(s.English.balllist, b.Value)) }).ToArray(),
            languages = Map(src.Languages),
            types = s.Strings.types.Select((t, i) => new { v = i, t, key = i < s.English.types.Length ? s.English.types[i].ToLowerInvariant() : "" }).ToArray(),
        };
    }

    public static object Species(Session s, ushort species, byte form)
    {
        var sav = s.Sav;
        var pt = sav.Personal;
        if (!pt.IsPresentInGame(species, form) && form != 0)
            form = 0;
        var pi = pt.GetFormEntry(species, form);
        var abilities = new List<object>();
        for (int i = 0; i < pi.AbilityCount; i++)
        {
            var a = pi.GetAbilityAtIndex(i);
            if (a > 0) abilities.Add(new { index = i, id = a, name = Describe.Name(s.Strings.Ability, a), hidden = i == 2 });
        }
        return new
        {
            species,
            form,
            name = Describe.Name(s.Strings.Species, species),
            forms = Describe.FormNames(s, species, sav.Context),
            types = Describe.Types(s, pi),
            baseStats = new[] { pi.HP, pi.ATK, pi.DEF, pi.SPA, pi.SPD, pi.SPE },
            abilities,
            genderRatio = pi.Gender,
            inGame = pt.IsSpeciesInGame(species),
        };
    }
}
