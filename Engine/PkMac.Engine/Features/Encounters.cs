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
    /// <summary>
    /// Sword/Shield overworld encounters: EC, PID, IVs, height and weight all come from one 32-bit seed,
    /// which can be recovered from the EC. Rebuilds PID/IVs/size from that seed so the Pokémon returns to
    /// exactly what the game generated (same EC). Null when it doesn't apply or doesn't make it legal.
    /// </summary>
    public static PKM? RestoreFromSeed(PKM pk)
    {
        if (pk is not PK8 || pk is not IScaledSize size) return null;
        var la = new LegalityAnalysis(pk);
        if (la.EncounterMatch is not IOverworldCorrelation8 z || z.GetRequirement(pk) != OverworldCorrelation8Requirement.MustHave)
            return null;
        if (z.IsOverworldCorrelationCorrect(pk)) return null;

        var seed = Overworld8RNG.GetOriginalSeed(pk);
        if (seed == uint.MaxValue) return null;
        foreach (var flawless in new[] { 0, 2, 3 })
        {
            var c = pk.Clone();
            var xoro = new Xoroshiro128Plus(seed);
            var ec = (uint)xoro.NextInt(uint.MaxValue);
            if (ec != c.EncryptionConstant) return null;
            var pid = (uint)xoro.NextInt(uint.MaxValue);
            // The game forces the shiny state of the encounter (same rules PKHeX checks).
            bool rngShiny = ShinyXor(c.ID32, pid) < 16;
            if (c.IsShiny && !rngShiny)
                pid = (((uint)c.TID16 ^ c.SID16 ^ (pid & 0xFFFF)) << 16) | (pid & 0xFFFF);
            else if (!c.IsShiny && rngShiny)
                pid ^= 0x1000_0000;
            c.PID = pid;

            Span<int> ivs = [-1, -1, -1, -1, -1, -1];
            for (int i = 0; i < flawless; i++)
            {
                int index;
                do { index = (int)xoro.NextInt(6); } while (ivs[index] != -1);
                ivs[index] = 31;
            }
            for (int i = 0; i < 6; i++)
                if (ivs[i] == -1) ivs[i] = (int)xoro.NextInt(32);
            c.IV_HP = ivs[0]; c.IV_ATK = ivs[1]; c.IV_DEF = ivs[2]; c.IV_SPA = ivs[3]; c.IV_SPD = ivs[4]; c.IV_SPE = ivs[5];
            var cs = (IScaledSize)c;
            cs.HeightScalar = (byte)(xoro.NextInt(0x81) + xoro.NextInt(0x80));
            cs.WeightScalar = (byte)(xoro.NextInt(0x81) + xoro.NextInt(0x80));
            c.ResetPartyStats();
            c.RefreshChecksum();
            if (new LegalityAnalysis(c).Valid || z.IsOverworldCorrelationCorrect(c))
                return c;
        }
        return null;
    }

    private static uint ShinyXor(uint id32, uint pid) => (pid >> 16) ^ (pid & 0xFFFF) ^ (id32 >> 16) ^ (id32 & 0xFFFF);

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
