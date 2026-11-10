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

    /// <summary>The game's own Pokédex structure (Zukan), when the save has one.</summary>
    private static object? Zukan(SaveFile sav) =>
        sav.GetType().GetProperty("Zukan")?.GetValue(sav) ?? sav.GetType().GetProperty("Dex")?.GetValue(sav);

    private static bool Invoke(object o, string name, params object[] args)
    {
        var types = args.Select(a => a.GetType()).ToArray();
        var m = o.GetType().GetMethods().FirstOrDefault(x => x.Name == name && x.GetParameters().Length >= args.Length &&
                    x.GetParameters().Take(args.Length).Select(p => p.ParameterType).SequenceEqual(types) &&
                    x.GetParameters().Skip(args.Length).All(p => p.HasDefaultValue));
        if (m is null) return false;
        var full = args.Concat(m.GetParameters().Skip(args.Length).Select(p => p.DefaultValue!)).ToArray();
        m.Invoke(o, full);
        return true;
    }

    private static LanguageID Lang(SaveFile sav) => Enum.IsDefined(typeof(LanguageID), (byte)sav.Language) && sav.Language > 0 ? (LanguageID)sav.Language : LanguageID.English;

    /// <summary>Legends Arceus: research-based Pokédex (seen = entry updated, caught = obtained).</summary>
    private static void LA(SAV8LA la, ushort sp, bool? seen, bool? caught)
    {
        var dex = la.PokedexSave;
        var forms = la.Personal[sp].FormCount;
        if (seen == true || caught == true) dex.SetPokeHasBeenUpdated(sp);
        if (caught is { } c)
            for (byte f = 0; f < forms; f++) dex.SetPokeObtainFlags(sp, f, (byte)(c ? 1 : 0));
        if (seen == false)
            for (byte f = 0; f < forms; f++) dex.SetPokeObtainFlags(sp, f, 0);
    }

    private static void Bulk(SaveFile sav, string action)
    {
        if (sav is SAV8LA la)
        {
            for (ushort sp = 1; sp <= sav.MaxSpeciesID; sp++)
                if (sav.Personal.IsSpeciesInGame(sp))
                    LA(la, sp, action != "clear" ? true : false, action == "caughtAll" ? true : action == "clear" ? false : null);
            return;
        }
        var z = Zukan(sav);
        switch (z)
        {
            case Zukan5 z5:
                if (action == "clear") { z5.CaughtNone(); z5.SeenNone(); }
                else { z5.SeenAll(false); if (action == "caughtAll") z5.CaughtAll(Lang(sav), false); }
                return;
            case Zukan6 z6:
                if (action == "clear") { z6.CaughtNone(); z6.SeenNone(); }
                else { z6.SeenAll(false); if (action == "caughtAll") z6.CaughtAll(Lang(sav), false); }
                return;
            case not null:
                bool ok = action switch
                {
                    "clear" => Invoke(z, "CaughtNone") & Invoke(z, "SeenNone"),
                    "seenAll" => Invoke(z, "SeenAll", false),
                    "caughtAll" => Invoke(z, "CompleteDex", false) || Invoke(z, "CaughtAll", false),
                    _ => false,
                };
                if (ok) return;
                break;
        }
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

    private static void One(SaveFile sav, ushort sp, bool? seen, bool? caught)
    {
        if (sav is SAV8LA la) { LA(la, sp, seen, caught); return; }
        var z = Zukan(sav);
        switch (z)
        {
            case Zukan5 z5:
                if (caught == true) z5.GiveAll(sp, true, false, Lang(sav), false);
                else if (seen == true) z5.SetSeen(sp, (byte)0, false);
                if (caught == false) z5.SetCaught(sp, false);
                if (seen == false) { z5.SetCaught(sp, false); z5.ClearSeen(sp); }
                return;
            case Zukan6 z6:
                if (caught == true) z6.GiveAll(sp, true, false, Lang(sav), false);
                else if (seen == true) z6.SetSeen(sp, (byte)0, false);
                if (caught == false) z6.SetCaught(sp, false);
                if (seen == false) { z6.SetCaught(sp, false); z6.SetSeen(sp, (byte)0, false, false); }
                return;
            case not null:
                if (caught == true) { if (Invoke(z, "SetDexEntryAll", sp, false)) return; }
                if (seen == false) { if (Invoke(z, "ClearDexEntryAll", sp)) return; }
                if (caught == false && Invoke(z, "SetCaught", sp, false)) return;
                if (seen == true && (Invoke(z, "SetSeen", sp, true) || Invoke(z, "SetDexEntryAll", sp, false))) return;
                break;
        }
        if (seen is { } se) sav.SetSeen(sp, se);
        if (caught is { } c) { if (c) sav.SetSeen(sp, true); sav.SetCaught(sp, c); }
    }

    /// <summary>{ changes: [{ species, seen, caught }] } or { action: seenAll|caughtAll|clear }.</summary>
    public static object Set(Session s, Params p)
    {
        var sav = s.Sav;
        if (!sav.HasPokeDex)
            throw new EngineException(Tr.T($"Questo gioco non ha un Pokédex modificabile."));
        s.Snapshot(Tr.T($"Pokédex"));
        if (p.OptStr("action") is { } action)
            Bulk(sav, action);
        if (p.Raw["changes"] is System.Text.Json.Nodes.JsonArray list)
        {
            foreach (var n in list)
            {
                if (n is not System.Text.Json.Nodes.JsonObject o) continue;
                var c = new Params(o);
                var sp = (ushort)c.Int("species", 0);
                if (sp == 0 || sp > sav.MaxSpeciesID) continue;
                bool? seen = c.Has("seen") ? c.Bool("seen") : null;
                bool? caught = c.Has("caught") ? c.Bool("caught") : null;
                One(sav, sp, seen, caught);
            }
        }
        s.Dirty = true;
        return Get(s);
    }
}
