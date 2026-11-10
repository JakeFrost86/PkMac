using PKHeX.Core;

namespace PkMac.Engine.Features;

/// <summary>
/// PKHeX-native legal generation and fixes: the same building blocks PKHeX uses for its Encounter
/// Database and for the "suggested" buttons (moves, relearn moves, met location).
/// </summary>
public static class Encounters
{
    /// <summary>Applies PKHeX's suggestions: current moves, relearn moves, met data, TR flags.</summary>
    public static PKM ApplySuggestions(PKM pk)
    {
        var la = new LegalityAnalysis(pk);
        if (la.Valid)
            return pk;

        // Met location/level suggested by PKHeX (only if the current ones are wrong).
        if (la.Results.Any(r => !r.Valid && r.Identifier is CheckIdentifier.Encounter or CheckIdentifier.Level))
        {
            var enc = EncounterSuggestion.GetSuggestedMetInfo(pk);
            if (enc is not null)
            {
                var level = enc.LevelMin;
                pk.MetLevel = level;
                pk.MetLocation = enc.Location;
                pk.CurrentLevel = Math.Max(EncounterSuggestion.GetLowestLevel(pk, level), Math.Max(level, pk.CurrentLevel));
            }
        }

        // Moves: PKHeX's suggested legal moveset.
        la = new LegalityAnalysis(pk);
        if (la.Results.Any(r => !r.Valid && r.Identifier is CheckIdentifier.CurrentMove) || pk.Moves.All(m => m == 0))
        {
            pk.SetMoveset();
            pk.HealPP();
        }

        // Relearn moves.
        la = new LegalityAnalysis(pk);
        if (la.Results.Any(r => !r.Valid && r.Identifier is CheckIdentifier.RelearnMove))
            pk.SetRelearnMoves(la);

        // Technical records (Gen 8+).
        if (pk is ITechRecord tr)
        {
            la = new LegalityAnalysis(pk);
            if (!la.Valid)
                tr.SetRecordFlags(pk, TechnicalRecordApplicatorOption.LegalCurrent);
        }

        pk.ResetPartyStats();
        pk.RefreshChecksum();
        return pk;
    }

    /// <summary>
    /// Creates a legal Pokémon of the given species/form for <paramref name="sav"/> from PKHeX's encounter
    /// tables. With <paramref name="keep"/>, nickname, held item and EVs are carried over when they stay legal.
    /// </summary>
    public static PKM? CreateLegal(SaveFile sav, ushort species, byte form, bool shiny, PKM? keep = null, int maxTries = 80)
    {
        var probe = EntityBlank.GetBlank(sav);
        probe.Species = species;
        probe.Form = form;
        probe.Language = sav.Language > 0 ? sav.Language : (int)LanguageID.English;
        probe.SetGender(probe.GetSaneGender());

        var criteria = shiny ? EncounterCriteria.Unrestricted with { Shiny = Shiny.Always } : EncounterCriteria.Unrestricted;
        int tries = 0;
        foreach (var enc in EncounterMovesetGenerator.GenerateEncounters(probe, sav, ReadOnlyMemory<ushort>.Empty, sav.Version))
        {
            if (++tries > maxTries)
                break;
            PKM pk;
            try { pk = enc.ConvertToPKM(sav, criteria); }
            catch { continue; }
            if (shiny && !pk.IsShiny)
                continue;

            if (pk.GetType() != sav.PKMType)
            {
                var conv = EntityConverter.ConvertToType(pk, sav.PKMType, out _);
                if (conv is null) continue;
                pk = conv;
            }

            // The encounter may be a pre-evolution: evolve it to the requested species.
            if (pk.Species != species || pk.Form != form)
            {
                bool nick = pk.IsNicknamed;
                pk.Species = species;
                pk.Form = form;
                if (!nick) pk.ClearNickname();
                pk.RefreshAbility(pk.AbilityNumber >> 1);
                pk.CurrentLevel = Math.Max(pk.CurrentLevel, (byte)50);
            }

            pk = ApplySuggestions(pk);
            if (!new LegalityAnalysis(pk).Valid)
                continue;

            if (keep is not null)
            {
                var copy = pk.Clone();
                if (keep.IsNicknamed) copy.SetNickname(keep.Nickname);
                if (keep.HeldItem > 0) copy.HeldItem = keep.HeldItem;
                copy.EV_HP = keep.EV_HP; copy.EV_ATK = keep.EV_ATK; copy.EV_DEF = keep.EV_DEF;
                copy.EV_SPA = keep.EV_SPA; copy.EV_SPD = keep.EV_SPD; copy.EV_SPE = keep.EV_SPE;
                copy.ResetPartyStats();
                copy.RefreshChecksum();
                if (new LegalityAnalysis(copy).Valid)
                    pk = copy;
            }
            return pk;
        }
        return null;
    }
}
