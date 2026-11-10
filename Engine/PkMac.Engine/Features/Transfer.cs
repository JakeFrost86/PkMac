using PKHeX.Core;

namespace PkMac.Engine.Features;

/// <summary>
/// Moves Pokémon between two open saves (or boxes of the same save). Cross-save transfers go through
/// PKHeX's EntityConverter, are checked against the destination game (species, form, moves, items,
/// ability, ball) and refused when the result would be incompatible or would lose its legality.
/// </summary>
public static class Transfer
{
    static Transfer()
    {
        EntityConverter.AllowIncompatibleConversion = EntityCompatibilitySetting.DisallowIncompatible;
    }

    private static string Explain(EntityConverterResult r) => r switch
    {
        EntityConverterResult.IncompatibleForm => "questa forma non esiste nel gioco di destinazione",
        EntityConverterResult.IncompatibleSpecies => "questa specie non esiste nel gioco di destinazione",
        EntityConverterResult.IncompatibleLanguageGB => "la lingua del Pokémon non è compatibile con quella del gioco Game Boy di destinazione",
        EntityConverterResult.NoTransferRoute => "nei giochi non esiste un modo per trasferirlo verso questa versione",
        _ => r.ToString(),
    };

    /// <summary>Last step reached by <see cref="Prepare"/> (diagnostics for the feature test).</summary>
    public static volatile string LastStage = "";

    /// <summary>Converts the entity for <paramref name="to"/> or explains why it can't go there.</summary>
    public static (PKM? pk, string? problem) Prepare(Session from, SlotRef r, Session to)
    {
        LastStage = "get";
        var src = from.Get(r);
        if (src.Species == 0)
            return (null, Tr.T($"Lo slot di partenza è vuoto."));
        var dest = to.Sav;

        PKM pk;
        if (src.GetType() == dest.PKMType)
        {
            pk = src.Clone();
        }
        else
        {
            // Games only move Pokémon forward (plus Gen 1↔2 and the Switch games through HOME).
            byte g1 = src.Format, g2 = dest.Generation;
            bool route = g2 >= g1 || (g1 <= 2 && g2 <= 2) || (g1 >= 8 && g2 >= 8);
            if (!route)
                return (null, Tr.T($"Non trasferibile: nei giochi non si può riportare un Pokémon dalla generazione {g1} alla {g2}."));
            LastStage = "convert";
            EntityConverterResult res = EntityConverterResult.None;
            var job = Task.Run(() => { var c = EntityConverter.ConvertToType(src, dest.PKMType, out var r0); res = r0; return c; });
            if (!job.Wait(TimeSpan.FromSeconds(10)))
                return (null, Tr.T($"Non trasferibile: la conversione non è riuscita."));
            var converted = job.Result;
            if (converted is null || res is not (EntityConverterResult.Success or EntityConverterResult.None))
                return (null, Tr.T($"Non trasferibile: {Explain(res)}."));
            pk = converted;
        }


        if (!dest.Personal.IsPresentInGame(pk.Species, pk.Form))
            return (null, Tr.T($"Non trasferibile: {Describe.Name(to.Strings.Species, pk.Species)} non è presente in {GameInfo.GetVersionName(dest.Version)}."));

        // Same treatment the game gives on arrival: handler/trade memories for the receiving trainer.
        dest.AdaptToSaveFile(pk, isParty: false);
        LastStage = "compat";
        var errata = dest.EvaluateCompatibility(pk, to.Language);
        if (errata.Count > 0)
            return (null, Tr.T($"Non compatibile con il gioco di destinazione:\n") + string.Join("\n", errata));

        // A legal Pokémon must stay legal once it lands in the other game.
        LastStage = "legal-src";
        bool wasLegal = SafeValid(src);
        LastStage = "legal-dest";
        if (wasLegal && !SafeValid(pk))
        {
            var la = new LegalityAnalysis(pk);
            var first = la.Report(to.Language).Split('\n').FirstOrDefault(l => l.Trim().Length > 0) ?? "";
            return (null, Tr.T($"Non trasferibile: in {GameInfo.GetVersionName(dest.Version)} diventerebbe non legale.\n{first}"));
        }
        LastStage = "done";
        return (pk, null);
    }

    private static bool SafeValid(PKM pk)
    {
        try { return new LegalityAnalysis(pk).Valid; } catch { return false; }
    }

    public static object Check(Session from, SlotRef r, Session to)
    {
        if (ReferenceEquals(from, to))
            return new { ok = true };
        var (pk, problem) = Prepare(from, r, to);
        return new { ok = pk is not null, problem, format = pk?.GetType().Name };
    }

    public static object Move(Session from, SlotRef fromRef, Session to, SlotRef toRef, bool copy)
    {
        if (ReferenceEquals(from, to))
            return Storage.Move(from, fromRef, toRef, copy);

        if (to.Get(toRef).Species != 0)
            throw new EngineException(Tr.T($"Lo slot di destinazione è occupato: trascina il Pokémon su uno slot vuoto."));
        var (pk, problem) = Prepare(from, fromRef, to);
        if (pk is null)
            throw new EngineException(problem ?? Tr.T($"Trasferimento non possibile."));

        // Trade/handler data is updated by PKHeX for the receiving save.
        to.Set(toRef, pk, settings: default(EntityImportSettings), label: Tr.T($"Trasferimento"));
        if (!copy)
        {
            if (fromRef.Party && from.Sav.PartyCount <= 1)
                throw new EngineException(Tr.T($"La squadra deve contenere almeno un Pokémon."));
            from.Clear(fromRef);
        }
        return new { ok = true, detail = Describe.Detail(to, toRef, to.Get(toRef)) };
    }

    /// <summary>Drops a Pokémon on a box (strip chip): first free, writable slot of that box.</summary>
    public static object MoveToBox(Session s, SlotRef from, int box, bool copy)
    {
        var sav = s.Sav;
        if ((uint)box >= sav.BoxCount)
            throw new EngineException(Tr.T($"Box non valido."));
        for (int i = 0; i < sav.BoxSlotCount; i++)
        {
            if (sav.GetBoxSlotAtIndex(box, i).Species != 0 || sav.IsBoxSlotOverwriteProtected(box, i))
                continue;
            var to = new SlotRef(false, box, i);
            Storage.Move(s, from, to, copy);
            return to.ToJson();
        }
        throw new EngineException(Tr.T($"Il box {box + 1} è pieno."));
    }
}
