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

    /// <summary>Converts the entity for <paramref name="to"/> or explains why it can't go there.</summary>
    public static (PKM? pk, string? problem) Prepare(Session from, SlotRef r, Session to)
    {
        var src = from.Get(r);
        if (src.Species == 0)
            return (null, "Lo slot di partenza è vuoto.");
        var dest = to.Sav;

        PKM pk;
        if (src.GetType() == dest.PKMType)
        {
            pk = src.Clone();
        }
        else
        {
            var converted = EntityConverter.ConvertToType(src, dest.PKMType, out var res);
            if (converted is null || res is not (EntityConverterResult.Success or EntityConverterResult.None))
                return (null, $"Non trasferibile: {Explain(res)}.");
            pk = converted;
        }

        if (!dest.Personal.IsPresentInGame(pk.Species, pk.Form))
            return (null, $"Non trasferibile: {Describe.Name(to.Strings.Species, pk.Species)} non è presente in {GameInfo.GetVersionName(dest.Version)}.");

        var errata = dest.EvaluateCompatibility(pk, to.Language);
        if (errata.Count > 0)
            return (null, "Non compatibile con il gioco di destinazione:\n" + string.Join("\n", errata));

        // A legal Pokémon must stay legal once it lands in the other game.
        bool wasLegal = SafeValid(src);
        if (wasLegal && !SafeValid(pk))
        {
            var la = new LegalityAnalysis(pk);
            var first = la.Report(to.Language).Split('\n').FirstOrDefault(l => l.Trim().Length > 0) ?? "";
            return (null, $"Non trasferibile: in {GameInfo.GetVersionName(dest.Version)} diventerebbe non legale.\n{first}");
        }
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
            throw new EngineException("Lo slot di destinazione è occupato: trascina il Pokémon su uno slot vuoto.");
        var (pk, problem) = Prepare(from, fromRef, to);
        if (pk is null)
            throw new EngineException(problem ?? "Trasferimento non possibile.");

        // Trade/handler data is updated by PKHeX for the receiving save.
        to.Set(toRef, pk, settings: default(EntityImportSettings), label: "Trasferimento");
        if (!copy)
        {
            if (fromRef.Party && from.Sav.PartyCount <= 1)
                throw new EngineException("La squadra deve contenere almeno un Pokémon.");
            from.Clear(fromRef);
        }
        return new { ok = true, detail = Describe.Detail(to, toRef, to.Get(toRef)) };
    }

    /// <summary>Drops a Pokémon on a box (strip chip): first free, writable slot of that box.</summary>
    public static object MoveToBox(Session s, SlotRef from, int box, bool copy)
    {
        var sav = s.Sav;
        if ((uint)box >= sav.BoxCount)
            throw new EngineException("Box non valido.");
        for (int i = 0; i < sav.BoxSlotCount; i++)
        {
            if (sav.GetBoxSlotAtIndex(box, i).Species != 0 || sav.IsBoxSlotOverwriteProtected(box, i))
                continue;
            var to = new SlotRef(false, box, i);
            Storage.Move(s, from, to, copy);
            return to.ToJson();
        }
        throw new EngineException($"Il box {box + 1} è pieno.");
    }
}
