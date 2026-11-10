using PKHeX.Core;

namespace PkMac.Engine.Features;

/// <summary>Box / party reading and the Pokémon editor.</summary>
public static class Storage
{
    public static object Box(Session s, int box)
    {
        var sav = s.Sav;
        if (!sav.HasBox || (uint)box >= sav.BoxCount)
            throw new EngineException("Box non valido.");
        var slots = new object[sav.BoxSlotCount];
        Parallel.For(0, sav.BoxSlotCount, i =>
        {
            var r = new SlotRef(false, box, i);
            slots[i] = Describe.Slot(s, r, sav.GetBoxSlotAtIndex(box, i));
        });
        return new { box, name = s.BoxName(box), slots };
    }

    public static object BoxList(Session s)
    {
        var sav = s.Sav;
        if (!sav.HasBox) return Array.Empty<object>();
        return Enumerable.Range(0, sav.BoxCount).Select(b =>
        {
            int count = 0, shiny = 0;
            for (int i = 0; i < sav.BoxSlotCount; i++)
            {
                var pk = sav.GetBoxSlotAtIndex(b, i);
                if (pk.Species == 0) continue;
                count++;
                if (pk.IsShiny) shiny++;
            }
            return new { box = b, name = s.BoxName(b), count, shiny };
        }).ToArray();
    }

    public static object Party(Session s)
    {
        var sav = s.Sav;
        if (!sav.HasParty) return Array.Empty<object>();
        return Enumerable.Range(0, 6).Select(i => Describe.Slot(s, new SlotRef(true, -1, i), sav.GetPartySlotAtIndex(i))).ToArray();
    }

    public static object Pokemon(Session s, SlotRef r)
    {
        var pk = s.Get(r);
        if (pk.Species == 0)
            return new { summary = Describe.Slot(s, r, pk), empty = true };
        return Describe.Detail(s, r, pk);
    }

    public static object Update(Session s, SlotRef r, Params c)
    {
        var pk = s.Get(r).Clone();
        if (pk.Species == 0 && !c.Has("species"))
            throw new EngineException("Lo slot è vuoto.");

        if (c.Has("species"))
        {
            var sp = (ushort)c.Int("species");
            if (sp == 0 || sp > s.Sav.MaxSpeciesID)
                throw new EngineException("Specie non disponibile in questo gioco.");
            bool wasDefault = !pk.IsNicknamed;
            pk.Species = sp;
            pk.Form = (byte)c.Int("form", 0);
            if (wasDefault)
                pk.ClearNickname();
            pk.RefreshAbility(pk.AbilityNumber >> 1);
        }
        else if (c.Has("form"))
        {
            pk.Form = (byte)c.Int("form");
            pk.RefreshAbility(pk.AbilityNumber >> 1);
        }

        if (c.Has("nickname"))
        {
            var nick = c.Str("nickname").Trim();
            if (nick.Length == 0 || nick == s.Strings.Species[pk.Species])
                pk.ClearNickname();
            else
            {
                if (nick.Length > pk.MaxStringLengthNickname)
                    throw new EngineException($"Soprannome troppo lungo (massimo {pk.MaxStringLengthNickname} caratteri).");
                pk.SetNickname(nick);
            }
        }
        if (c.Has("level"))
            pk.CurrentLevel = (byte)Math.Clamp(c.Int("level"), 1, 100);
        if (c.Has("nature"))
            pk.SetNature((Nature)c.Int("nature"));
        if (c.Has("statNature"))
            pk.StatAlignment = (Nature)c.Int("statNature");
        if (c.Has("abilityIndex"))
            pk.SetAbilityIndex(c.Int("abilityIndex"));
        if (c.Has("heldItem"))
            pk.ApplyHeldItem(c.Int("heldItem"), pk.Context);
        if (c.IntArray("moves") is { Length: 4 } moves)
        {
            pk.SetMoves(moves.Select(m => (ushort)m).ToArray());
            pk.HealPP();
        }
        if (c.IntArray("ivs") is { Length: 6 } ivs)
        {
            pk.IV_HP = ivs[0]; pk.IV_ATK = ivs[1]; pk.IV_DEF = ivs[2];
            pk.IV_SPA = ivs[3]; pk.IV_SPD = ivs[4]; pk.IV_SPE = ivs[5];
        }
        if (c.IntArray("evs") is { Length: 6 } evs)
        {
            var max = pk.MaxEV;
            evs = evs.Select(v => Math.Clamp(v, 0, max)).ToArray();
            if (pk.Format >= 3 && evs.Sum() > 510)
                throw new EngineException("La somma degli EV non può superare 510.");
            pk.EV_HP = evs[0]; pk.EV_ATK = evs[1]; pk.EV_DEF = evs[2];
            pk.EV_SPA = evs[3]; pk.EV_SPD = evs[4]; pk.EV_SPE = evs[5];
        }
        if (c.Has("shiny"))
            pk.SetIsShiny(c.Bool("shiny"));
        if (c.Has("gender"))
            pk.SetGender((byte)c.Int("gender"));
        if (c.Has("ball"))
            pk.Ball = (byte)c.Int("ball");
        if (c.Has("ot"))
            pk.OriginalTrainerName = c.Str("ot");
        if (c.Has("friendship"))
            pk.CurrentFriendship = (byte)Math.Clamp(c.Int("friendship"), 0, 255);
        if (c.Has("teraType") && pk is ITeraType tera)
            tera.SetTeraType((MoveType)c.Int("teraType"));
        if (c.Has("pokerus"))
            pk.IsPokerusInfected = c.Bool("pokerus");

        pk.ResetPartyStats();
        pk.RefreshChecksum();
        s.Set(r, pk, label: "Modifica Pokémon");
        return Describe.Detail(s, r, s.Get(r));
    }

    public static object Delete(Session s, SlotRef r)
    {
        s.Clear(r);
        return true;
    }

    public static object Move(Session s, SlotRef from, SlotRef to, bool copy)
    {
        var a = s.Get(from);
        var b = s.Get(to);
        if (a.Species == 0)
            return false;
        if (copy)
        {
            s.Set(to, a.Clone(), label: "Copia");
            return true;
        }
        if (from == to) return true;
        if (from.Party && b.Species == 0)
        {
            // Moving the last party member out is not allowed by the games.
            if (s.Sav.PartyCount <= 1)
                throw new EngineException("La squadra deve contenere almeno un Pokémon.");
        }
        s.Set(to, a.Clone(), label: "Sposta");
        if (b.Species == 0)
            s.Clear(from, recordUndo: true);
        else
            s.Set(from, b.Clone(), label: "Sposta");
        return true;
    }

    public static object RenameBox(Session s, int box, string name)
    {
        if (s.Sav is not IBoxDetailName n)
            throw new EngineException("Questo gioco non permette di rinominare i box.");
        n.SetBoxName(box, name);
        s.Dirty = true;
        return s.BoxName(box);
    }

    public static object Search(Session s, string query)
    {
        var sav = s.Sav;
        var q = query.Trim();
        var results = new List<object>();
        if (q.Length == 0 || !sav.HasBox) return results;
        bool shinyOnly = q.Equals("shiny", StringComparison.OrdinalIgnoreCase) || q.Equals("cromatico", StringComparison.OrdinalIgnoreCase);
        bool illegalOnly = q.Equals("illegale", StringComparison.OrdinalIgnoreCase) || q.Equals("illegal", StringComparison.OrdinalIgnoreCase);
        for (int b = 0; b < sav.BoxCount; b++)
        for (int i = 0; i < sav.BoxSlotCount; i++)
        {
            var pk = sav.GetBoxSlotAtIndex(b, i);
            if (pk.Species == 0) continue;
            bool match;
            if (shinyOnly) match = pk.IsShiny;
            else if (illegalOnly) match = !new LegalityAnalysis(pk).Valid;
            else
            {
                var name = Describe.Name(s.Strings.Species, pk.Species);
                match = name.Contains(q, StringComparison.OrdinalIgnoreCase)
                        || pk.Nickname.Contains(q, StringComparison.OrdinalIgnoreCase)
                        || pk.OriginalTrainerName.Equals(q, StringComparison.OrdinalIgnoreCase);
            }
            if (match)
                results.Add(Describe.Slot(s, new SlotRef(false, b, i), pk, withLegality: false));
            if (results.Count >= 300) return results;
        }
        return results;
    }

    /// <summary>Numbers for the save overview (dashboard).</summary>
    public static object Overview(Session s)
    {
        var sav = s.Sav;
        int total = 0, shiny = 0, illegal = 0, eggs = 0;
        var species = new HashSet<ushort>();
        var types = new Dictionary<string, int>();
        var levels = new int[10];
        void Count(PKM pk)
        {
            if (pk.Species == 0) return;
            total++;
            if (pk.IsShiny) shiny++;
            if (pk.IsEgg) { eggs++; return; }
            species.Add(pk.Species);
            foreach (var t in Describe.Types(s, pk.PersonalInfo))
                types[t] = types.GetValueOrDefault(t) + 1;
            levels[Math.Clamp((pk.CurrentLevel - 1) / 10, 0, 9)]++;
            if (!new LegalityAnalysis(pk).Valid) illegal++;
        }
        if (sav.HasBox)
            for (int i = 0; i < sav.SlotCount; i++) Count(sav.GetBoxSlotAtIndex(i));
        if (sav.HasParty)
            for (int i = 0; i < sav.PartyCount; i++) Count(sav.GetPartySlotAtIndex(i));
        return new
        {
            total,
            shiny,
            illegal,
            eggs,
            uniqueSpecies = species.Count,
            maxSpecies = sav.MaxSpeciesID,
            capacity = sav.HasBox ? sav.SlotCount : 0,
            types = types.OrderByDescending(kv => kv.Value).Select(kv => new { type = kv.Key, count = kv.Value }).ToArray(),
            levels,
        };
    }

    public static object UndoRedo(Session s, bool undo)
    {
        var e = undo ? s.Undo() : s.Redo();
        return new { applied = e?.Label, whole = e?.Whole is not null || e?.Ref is null, @ref = e?.Ref?.ToJson(), undo = s.UndoLabel, redo = s.RedoLabel };
    }

    // ---------- files ----------

    public static byte[] Bytes(PKM pk)
    {
        var buf = new byte[pk.SIZE_PARTY];
        pk.WriteDecryptedDataParty(buf);
        return buf;
    }

    public static object ExportPk(Session s, SlotRef r, string dir)
    {
        var pk = s.Get(r);
        if (pk.Species == 0) throw new EngineException("Lo slot è vuoto.");
        Directory.CreateDirectory(dir);
        var path = UniquePath(dir, pk.FileName);
        File.WriteAllBytes(path, Bytes(pk));
        return path;
    }

    public static object ExportBox(Session s, int box, string dir)
    {
        var sav = s.Sav;
        Directory.CreateDirectory(dir);
        var paths = new List<string>();
        for (int i = 0; i < sav.BoxSlotCount; i++)
        {
            var pk = sav.GetBoxSlotAtIndex(box, i);
            if (pk.Species == 0) continue;
            var path = UniquePath(dir, pk.FileName);
            File.WriteAllBytes(path, Bytes(pk));
            paths.Add(path);
        }
        return paths;
    }

    public static string UniquePath(string dir, string fileName)
    {
        var clean = string.Concat(fileName.Select(ch => Path.GetInvalidFileNameChars().Contains(ch) || ch == ':' ? '_' : ch));
        var path = Path.Combine(dir, clean);
        var stem = Path.GetFileNameWithoutExtension(clean);
        var ext = Path.GetExtension(clean);
        for (int n = 2; File.Exists(path); n++)
            path = Path.Combine(dir, $"{stem} ({n}){ext}");
        return path;
    }

    public static object ImportPk(Session s, string path, SlotRef r)
    {
        var data = File.ReadAllBytes(path);
        if (!FileUtil.TryGetPKM(data, out var pk, Path.GetExtension(path), s.Sav))
            throw new EngineException("Il file non contiene un Pokémon leggibile.");
        s.Set(r, pk, settings: default(EntityImportSettings), label: "Importa");
        return Describe.Detail(s, r, s.Get(r));
    }

    public static object ExportShowdown(Session s, SlotRef r)
        { using (new EnglishScope()) return ShowdownParsing.GetShowdownText(s.Get(r)); }

    public static object Heal(Session s, SlotRef r)
    {
        var pk = s.Get(r).Clone();
        pk.Heal();
        s.Set(r, pk, label: "Cura");
        return Describe.Detail(s, r, s.Get(r));
    }

    /// <summary>Max IVs (keeping Hidden-Power-free 31s) and recommended EV spread left untouched.</summary>
    public static object MaxStats(Session s, SlotRef r)
    {
        var pk = s.Get(r).Clone();
        var max = pk.MaxIV;
        pk.IV_HP = pk.IV_ATK = pk.IV_DEF = pk.IV_SPA = pk.IV_SPD = pk.IV_SPE = max;
        pk.ResetPartyStats();
        pk.RefreshChecksum();
        s.Set(r, pk, label: "IV al massimo");
        return Describe.Detail(s, r, s.Get(r));
    }

    // ---------- ribbons & marks ----------

    public static object Ribbons(Session s, SlotRef r)
    {
        var pk = s.Get(r);
        if (pk.Species == 0) throw new EngineException("Slot vuoto.");
        var la = new LegalityAnalysis(pk);
        bool ribbonsOk = !la.Results.Any(x => x.Identifier == CheckIdentifier.Ribbon && !x.Valid);
        var list = RibbonInfo.GetRibbonInfo(pk).Select(i => new
        {
            prop = i.Name,
            name = s.Strings.Ribbons.GetNameSafe(i.Name, out var n) ? n : i.Name.Replace("Ribbon", ""),
            mark = i.Name.StartsWith("RibbonMark", StringComparison.Ordinal),
            count = i.Type == RibbonValueType.Byte,
            value = i.Type == RibbonValueType.Byte ? i.RibbonCount : (i.HasRibbon ? 1 : 0),
            max = i.Type == RibbonValueType.Byte ? i.MaxCount : 1,
        }).ToArray();
        int? affix = pk is IRibbonSetAffixed a ? a.AffixedRibbon : null;
        return new { ribbons = list, affixed = affix, ribbonsValid = ribbonsOk, owned = list.Count(x => x.value > 0) };
    }

    /// <summary>{ set: [{ prop, value }] } or { action: "allValid" | "removeAll" } and optional { affixed }.</summary>
    public static object SetRibbons(Session s, SlotRef r, Params p)
    {
        var pk = s.Get(r).Clone();
        if (pk.Species == 0) throw new EngineException("Slot vuoto.");
        switch (p.OptStr("action"))
        {
            case "allValid": RibbonApplicator.SetAllValidRibbons(pk); break;
            case "removeAll": RibbonApplicator.RemoveAllValidRibbons(pk); break;
        }
        if (p.Raw["set"] is System.Text.Json.Nodes.JsonArray list)
        {
            var known = RibbonInfo.GetRibbonInfo(pk).ToDictionary(i => i.Name);
            foreach (var n in list)
            {
                if (n is not System.Text.Json.Nodes.JsonObject o) continue;
                var c = new Params(o);
                var prop = c.Str("prop");
                if (!known.TryGetValue(prop, out var info)) continue;
                var v = c.Int("value", 0);
                if (info.Type == RibbonValueType.Byte)
                    ReflectUtil.SetValue(pk, prop, (byte)Math.Clamp(v, 0, info.MaxCount));
                else
                    ReflectUtil.SetValue(pk, prop, v > 0);
            }
        }
        if (p.Has("affixed") && pk is IRibbonSetAffixed a)
            a.AffixedRibbon = (sbyte)Math.Clamp(p.Int("affixed"), -1, 127);
        pk.RefreshChecksum();
        s.Set(r, pk, label: "Fiocchi");
        return new { ribbons = Ribbons(s, r), detail = Pokemon(s, r) };
    }
}
