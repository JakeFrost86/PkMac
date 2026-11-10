using PKHeX.Core;
using PluginPile.Sorting;
using PokeFilename.API;

namespace PkMac.Engine.Features;

/// <summary>PluginPile "Sorting" (foohyfooh): regional Pokédex ordering.</summary>
public static class Sorting
{
    public static object Options(Session s, bool areas)
        => SortingCatalog.GetOptions(s.Sav, areas).Select(o => new { id = o.Id, name = o.Name, group = o.Group }).ToArray();

    public static object Sort(Session s, Params p)
    {
        var sav = s.Sav;
        var id = p.Str("id");
        var option = SortingCatalog.GetOptions(sav, includeAreas: true).FirstOrDefault(o => o.Id == id)
                     ?? throw new EngineException("Ordinamento non disponibile per questo gioco.");
        var begin = Math.Clamp(p.Int("startBox", 0), 0, sav.BoxCount - 1);
        var end = p.Int("endBox", -1);
        if (end >= sav.BoxCount) end = -1;
        var extra = (p.Raw["extra"] as System.Text.Json.Nodes.JsonArray)?
            .Select(n => Enum.TryParse<PluginSettings.SortOptions>(n!.GetValue<string>(), true, out var e) ? e : (PluginSettings.SortOptions?)null)
            .Where(e => e.HasValue).Select(e => e!.Value).ToArray() ?? [];
        s.Snapshot($"Ordina: {option.Name}");
        var moved = SortingCatalog.Apply(sav, option, begin, end, p.Bool("checkForms", true), extra);
        s.Dirty = true;
        return new { moved };
    }
}

/// <summary>PluginPile "Special Pokémon Finder" (foohyfooh), re-implemented headless.</summary>
public static class SpecialFinder
{
    public static object Find(Session s)
    {
        var sav = s.Sav;
        var found = new List<object>();
        int dunsparce = 0, tandemaus = 0, wurmple = 0;

        void Check(PKM pk, SlotRef r)
        {
            switch ((Species)pk.Species)
            {
                case Species.Dunsparce when sav.Generation >= 6:
                    dunsparce++;
                    if (pk.EncryptionConstant % 100 == 0)
                        found.Add(new { kind = "dunsparce3", label = "Dunsparce a tre segmenti", hint = "Evolve in Dudunsparce Forma Trimetrica", pokemon = Describe.Slot(s, r, pk, false) });
                    break;
                case Species.Tandemaus when sav.Generation >= 6:
                    tandemaus++;
                    if (pk.EncryptionConstant % 100 == 0)
                        found.Add(new { kind = "family3", label = "Tandemaus famiglia da tre", hint = "Evolve in Maushold Famiglia da Tre", pokemon = Describe.Slot(s, r, pk, false) });
                    break;
                case Species.Wurmple:
                    wurmple++;
                    var evo = WurmpleUtil.GetWurmpleEvoVal(pk.EncryptionConstant);
                    found.Add(new
                    {
                        kind = evo == WurmpleEvolution.Silcoon ? "beautifly" : "dustox",
                        label = evo == WurmpleEvolution.Silcoon ? "Wurmple → Beautifly" : "Wurmple → Dustox",
                        hint = evo == WurmpleEvolution.Silcoon ? "Diventerà Silcoon, poi Beautifly" : "Diventerà Cascoon, poi Dustox",
                        pokemon = Describe.Slot(s, r, pk, false),
                    });
                    break;
            }
        }

        if (sav.HasParty)
            for (int i = 0; i < sav.PartyCount; i++)
                Check(sav.GetPartySlotAtIndex(i), new SlotRef(true, -1, i));
        if (sav.HasBox)
            for (int b = 0; b < sav.BoxCount; b++)
            for (int i = 0; i < sav.BoxSlotCount; i++)
            {
                var pk = sav.GetBoxSlotAtIndex(b, i);
                if (pk.Species != 0) Check(pk, new SlotRef(false, b, i));
            }

        return new { found, totals = new { dunsparce, tandemaus, wurmple } };
    }
}

/// <summary>PokeFilename (architdate): configurable names for exported .pk files.</summary>
public static class FileNaming
{
    private static readonly EntityNamerSettings Settings = new();

    public static object Options() => new
    {
        current = Settings.Namer.ToString(),
        regular = Settings.CustomPatternRegular,
        gameboy = Settings.CustomPatternGameBoy,
        namers = Enum.GetNames<EntityNamers>(),
        keywords = new[] { "{Species}", "{Nickname}", "{FormName}", "{CurrentLevel}", "{Nature}", "{ShinyType}", "{ItemName}", "{OriginalTrainerName}", "{TID16}", "{PID}", "{EncryptionConstant}", "{Legality}", "{Alpha}", "{Gigantamax}", "{LanguageTag}" },
    };

    public static object Set(Params p)
    {
        if (p.OptStr("namer") is { } n && Enum.TryParse<EntityNamers>(n, true, out var namer))
            Settings.Namer = namer;
        if (p.OptStr("regular") is { } r && r.Length > 0)
            Settings.CustomPatternRegular = r;
        if (p.OptStr("gameboy") is { } g && g.Length > 0)
            Settings.CustomPatternGameBoy = g;
        EntityFileNamer.Namer = Settings.Create();
        return Options();
    }

    public static object RenameFolder(string dir)
    {
        if (!Directory.Exists(dir))
            throw new EngineException("Cartella non trovata.");
        var before = Directory.GetFiles(dir).Length;
        BulkRename.RenameFolder(dir, EntityFileNamer.Namer, deep: false);
        return new { files = before };
    }
}
