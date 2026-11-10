using PKHeX.Core;

namespace PkMac.Engine.Features;

/// <summary>Seen / caught Pokédex flags.</summary>
public static class Pokedex
{
    public static object Get(Session s)
    {
        var sav = s.Sav;
        if (!sav.HasPokeDex)
            return new { supported = false, entries = Array.Empty<object>() };
        var pt = sav.Personal;
        var entries = new List<object>();
        for (ushort sp = 1; sp <= sav.MaxSpeciesID; sp++)
        {
            if (!pt.IsSpeciesInGame(sp))
                continue;
            var pi = pt.GetFormEntry(sp, 0);
            entries.Add(new
            {
                species = sp,
                name = Describe.Name(s.Strings.Species, sp),
                seen = sav.GetSeen(sp),
                caught = sav.GetCaught(sp),
                types = Describe.Types(s, pi),
                formKey = Describe.FormKey(s, sp, 0, sav.Context),
            });
        }
        return new { supported = true, seen = sav.SeenCount, caught = sav.CaughtCount, total = entries.Count, entries };
    }

    /// <summary>{ changes: [{ species, seen, caught }] } or { action: seenAll|caughtAll|clear }.</summary>
    public static object Set(Session s, Params p)
    {
        var sav = s.Sav;
        if (!sav.HasPokeDex)
            throw new EngineException("Questo gioco non ha un Pokédex modificabile.");
        s.Snapshot("Pokédex");
        if (p.OptStr("action") is { } action)
        {
            var pt = sav.Personal;
            for (ushort sp = 1; sp <= sav.MaxSpeciesID; sp++)
            {
                if (!pt.IsSpeciesInGame(sp)) continue;
                switch (action)
                {
                    case "seenAll": sav.SetSeen(sp, true); break;
                    case "caughtAll": sav.SetSeen(sp, true); sav.SetCaught(sp, true); break;
                    case "clear": sav.SetCaught(sp, false); sav.SetSeen(sp, false); break;
                }
            }
        }
        if (p.Raw["changes"] is System.Text.Json.Nodes.JsonArray list)
        {
            foreach (var n in list)
            {
                if (n is not System.Text.Json.Nodes.JsonObject o) continue;
                var c = new Params(o);
                var sp = (ushort)c.Int("species", 0);
                if (sp == 0 || sp > sav.MaxSpeciesID) continue;
                if (c.Has("seen")) sav.SetSeen(sp, c.Bool("seen"));
                if (c.Has("caught"))
                {
                    var caught = c.Bool("caught");
                    if (caught) sav.SetSeen(sp, true);
                    sav.SetCaught(sp, caught);
                }
            }
        }
        s.Dirty = true;
        return Get(s);
    }
}
