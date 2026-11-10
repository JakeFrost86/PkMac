using PKHeX.Core;

namespace PkMac.Engine;

/// <summary>Turns PKHeX objects into plain data the app can render.</summary>
public static class Describe
{
    // Display order used by the app: HP, Atk, Def, SpA, SpD, Spe.
    public static readonly string[] StatKeys = ["hp", "atk", "def", "spa", "spd", "spe"];

    public static object Slot(Session s, SlotRef r, PKM pk, bool withLegality = true)
    {
        if (pk.Species == 0)
            return new { @ref = r.ToJson(), empty = true, locked = s.IsLocked(r) };

        bool? legal = null;
        if (withLegality)
        {
            try { legal = new LegalityAnalysis(pk).Valid; }
            catch { legal = null; }
        }

        return new
        {
            @ref = r.ToJson(),
            empty = false,
            locked = s.IsLocked(r),
            species = pk.Species,
            form = pk.Form,
            formKey = FormKey(s, pk.Species, pk.Form, pk.Context),
            formArg = pk is IFormArgument fa ? (int)fa.FormArgument : 0,
            speciesName = Name(s.Strings.Species, pk.Species),
            nickname = pk.IsEgg ? s.Strings.EggName : pk.Nickname,
            isNicknamed = pk.IsNicknamed,
            level = pk.CurrentLevel,
            shiny = pk.IsShiny,
            gender = pk.Gender,
            isEgg = pk.IsEgg,
            alpha = pk is IAlphaReadOnly { IsAlpha: true },
            gmax = pk is IGigantamaxReadOnly { CanGigantamax: true },
            heldItem = pk.HeldItem,
            heldItemName = pk.HeldItem > 0 ? Name(s.Strings.Item, pk.HeldItem) : null,
            heldItemKey = pk.HeldItem > 0 ? AssetKey(Name(s.English.Item, pk.HeldItem)) : null,
            types = Types(s, pk.PersonalInfo),
            ball = pk.Ball,
            ballKey = AssetKey(Name(s.English.balllist, pk.Ball)),
            legal,
        };
    }

    public static object Detail(Session s, SlotRef r, PKM pk)
    {
        var sav = s.Sav;
        var pi = pk.PersonalInfo;
        var la = new LegalityAnalysis(pk);
        var report = SafeReport(la, s.Language, verbose: false);
        var verbose = SafeReport(la, s.Language, verbose: true);

        var moves = new[] { pk.Move1, pk.Move2, pk.Move3, pk.Move4 }
            .Select((m, i) => new
            {
                id = (int)m,
                name = m == 0 ? null : Name(s.Strings.Move, m),
                type = m == 0 ? null : TypeKey(s, MoveInfo.GetType(m, pk.Context)),
                pp = i switch { 0 => pk.Move1_PP, 1 => pk.Move2_PP, 2 => pk.Move3_PP, _ => pk.Move4_PP },
                ppUps = i switch { 0 => pk.Move1_PPUps, 1 => pk.Move2_PPUps, 2 => pk.Move3_PPUps, _ => pk.Move4_PPUps },
            }).ToArray();

        var abilities = new List<object>();
        for (int i = 0; i < pi.AbilityCount; i++)
        {
            var a = pi.GetAbilityAtIndex(i);
            if (a <= 0) continue;
            abilities.Add(new { index = i, id = a, name = Name(s.Strings.Ability, a), hidden = i == 2 });
        }

        var nature = (int)pk.Nature;
        var statNature = (int)pk.StatAlignment;
        var (up, down) = NatureEffect(statNature);

        string? tera = null;
        int? teraIndex = null;
        if (pk is ITeraType t)
        {
            teraIndex = (int)t.TeraTypeOriginal;
            tera = TypeKey(s, (byte)t.TeraType);
        }

        string location = "";
        try { location = pk.GetLocationString(false); } catch { }

        return new
        {
            summary = Slot(s, r, pk, withLegality: false),
            format = pk.Format,
            generation = pk.Generation,
            pid = pk.PID.ToString("X8"),
            encryptionConstant = pk.EncryptionConstant.ToString("X8"),
            nature,
            natureName = Name(s.Strings.Natures, nature),
            statNature,
            natureUp = up,
            natureDown = down,
            hasNatures = pk.Format >= 3,
            ability = pk.Ability,
            abilityName = pk.Ability > 0 ? Name(s.Strings.Ability, pk.Ability) : null,
            abilityNumber = pk.AbilityNumber,
            abilities,
            moves,
            ivs = new[] { pk.IV_HP, pk.IV_ATK, pk.IV_DEF, pk.IV_SPA, pk.IV_SPD, pk.IV_SPE },
            evs = new[] { pk.EV_HP, pk.EV_ATK, pk.EV_DEF, pk.EV_SPA, pk.EV_SPD, pk.EV_SPE },
            stats = Stats(pk),
            baseStats = new[] { pi.HP, pi.ATK, pi.DEF, pi.SPA, pi.SPD, pi.SPE },
            maxIV = pk.MaxIV,
            maxEV = pk.MaxEV,
            evTotalMax = pk.Format >= 6 ? 510 : pk.Format >= 3 ? 510 : 65535 * 6,
            ot = pk.OriginalTrainerName,
            otGender = pk.OriginalTrainerGender,
            tid = pk.GetDisplayTID(),
            sid = pk.GetDisplaySID(),
            ballName = Name(s.Strings.balllist, pk.Ball),
            metLocation = location,
            metLevel = pk.MetLevel,
            version = (int)pk.Version,
            versionName = GameInfo.GetVersionName(pk.Version),
            language = pk.Language,
            origin = Origin(s, pk),
            friendship = pk.CurrentFriendship,
            exp = pk.EXP,
            teraType = tera,
            teraTypeIndex = teraIndex,
            pokerus = pk.IsPokerusInfected,
            height = pk is IScaledSize hs ? (int?)hs.HeightScalar : null,
            weight = pk is IScaledSize ws ? (int?)ws.WeightScalar : null,
            scale = pk is IScaledSize3 ss ? (int?)ss.Scale : null,
            legality = new
            {
                valid = la.Valid,
                report,
                verbose,
                problems = la.Results.Where(z => !z.Valid).Select(z => z.Identifier.ToString()).Distinct().ToArray(),
            },
            showdown = SafeShowdown(pk),
            fileName = SafeFileName(pk),
            canEdit = !s.IsLocked(r),
            genderRatio = pi.Gender,
        };
    }

    public static int[] Stats(PKM pk)
    {
        if (!pk.PartyStatsPresent)
        {
            var clone = pk.Clone();
            clone.ResetPartyStats();
            pk = clone;
        }
        return [pk.Stat_HPMax, pk.Stat_ATK, pk.Stat_DEF, pk.Stat_SPA, pk.Stat_SPD, pk.Stat_SPE];
    }

    /// <summary>Index (display order) of the boosted and lowered stat; -1 when neutral.</summary>
    public static (int up, int down) NatureEffect(int nature)
    {
        if (nature is < 0 or >= 25) return (-1, -1);
        int up = nature / 5, down = nature % 5;
        if (up == down) return (-1, -1);
        // PKHeX nature order: Atk, Def, Spe, SpA, SpD  ->  display: Atk=1 Def=2 SpA=3 SpD=4 Spe=5
        int[] map = [1, 2, 5, 3, 4];
        return (map[up], map[down]);
    }

    public static string[] Types(Session s, IPersonalType pi)
    {
        var t1 = TypeKey(s, pi.Type1);
        var t2 = TypeKey(s, pi.Type2);
        return t1 == t2 ? [t1] : [t1, t2];
    }

    /// <summary>English, lowercase type name: used by the app as a stable color key.</summary>
    public static string TypeKey(Session s, byte type)
        => type < s.English.types.Length ? s.English.types[type].ToLowerInvariant() : "normal";

    /// <summary>English form name, normalized for PokeAPI sprite lookup ("" for the base form).</summary>
    /// <summary>
    /// English form name used to pick the sprite. Also for form 0 when the species has several forms
    /// (Vivillon's form 0 is Icy Snow, not the Meadow pattern of the base sprite).
    /// </summary>
    public static string FormKey(Session s, ushort species, byte form, EntityContext context)
    {
        try
        {
            var forms = FormConverter.GetFormList(species, s.English.types, s.English.forms, GameInfo.GenderSymbolASCII, context);
            if (form == 0 && forms.Length <= 1)
                return "";
            if (form < forms.Length)
                return forms[form].ToLowerInvariant();
        }
        catch { }
        return form == 0 ? "" : form.ToString();
    }

    public static string[] FormNames(Session s, ushort species, EntityContext context)
    {
        try { return FormConverter.GetFormList(species, s.Strings.types, s.Strings.forms, GameInfo.GenderSymbolUnicode, context); }
        catch { return []; }
    }

    /// <summary>"Poké Ball" -> "poke-ball": the naming used by PokeAPI item sprites.</summary>
    public static string AssetKey(string english)
    {
        var norm = english.Normalize(System.Text.NormalizationForm.FormD);
        var sb = new System.Text.StringBuilder();
        foreach (var ch in norm)
        {
            if (System.Globalization.CharUnicodeInfo.GetUnicodeCategory(ch) == System.Globalization.UnicodeCategory.NonSpacingMark) continue;
            if (char.IsLetterOrDigit(ch)) sb.Append(char.ToLowerInvariant(ch));
            else if (ch is ' ' or '-' or '_') { if (sb.Length > 0 && sb[^1] != '-') sb.Append('-'); }
        }
        return sb.ToString().Trim('-');
    }

    /// <summary>Raw origin data for the editable "Origine" tab.</summary>
    public static object Origin(Session s, PKM pk)
    {
        static string? D(DateOnly? d) => d?.ToString("yyyy-MM-dd");
        var gen = pk.Format;
        return new
        {
            ball = (int)pk.Ball,
            version = (int)pk.Version,
            metLocation = (int)pk.MetLocation,
            metLevel = (int)pk.MetLevel,
            metDate = gen >= 4 ? D(pk.MetDate) : null,
            eggLocation = gen >= 4 ? (int)pk.EggLocation : 0,
            eggDate = gen >= 4 ? D(pk.EggMetDate) : null,
            wasEgg = pk.WasEgg,
            isEgg = pk.IsEgg,
            fateful = pk.FatefulEncounter,
            hasFateful = gen >= 3,
            hasDates = gen >= 4,
            hasEgg = gen >= 4,
            hasVersion = gen >= 3,
            hasMet = gen >= 2,
            otGender = (int)pk.OriginalTrainerGender,
            hasOtGender = gen >= 2,
            tid = pk.GetDisplayTID(),
            sid = pk.GetDisplaySID(),
            hasSid = gen >= 3,
            tidMax = pk.TrainerIDDisplayFormat == TrainerIDFormat.SixDigit ? 999_999 : 65535,
            sidMax = pk.TrainerIDDisplayFormat == TrainerIDFormat.SixDigit ? 4294 : 65535,
            language = pk.Language,
            hasHandler = gen >= 6,
            htName = gen >= 6 ? pk.HandlingTrainerName : "",
            htGender = gen >= 6 ? (int)pk.HandlingTrainerGender : 0,
            currentHandler = gen >= 6 ? (int)pk.CurrentHandler : 0,
            pid = pk.PID.ToString("X8"),
            ec = pk.EncryptionConstant.ToString("X8"),
            hasEc = gen >= 6,
            maxOt = pk.MaxStringLengthTrainer,
            // HOME tracker: written only by Pokémon HOME (Switch formats). Never generated here.
            hasHomeTracker = pk is IHomeTrack,
            homeTracker = pk is IHomeTrack ht ? ht.Tracker.ToString("X16") : null,
            homeTrackerMissing = pk is IHomeTrack { HasTracker: false } && HomeTrackerExpected(pk),
        };
    }

    /// <summary>Games and met locations for the origin editor.</summary>
    /// <summary>True when PKHeX's legality check says this Pokémon must have come through HOME.</summary>
    private static bool HomeTrackerExpected(PKM pk)
    {
        try { return new LegalityAnalysis(pk).Results.Any(r => r.Result == LegalityCheckResultCode.TransferTrackerMissing); }
        catch { return false; }
    }

    public static object OriginLists(Session s, int version, bool egg)
    {
        var sav = s.Sav;
        var v = (GameVersion)version;
        IReadOnlyList<ComboItem> locs;
        try { locs = GameInfo.GetLocationList(v == GameVersion.Any ? sav.Version : v, sav.Context, egg); }
        catch { locs = []; }
        return new
        {
            games = s.Sources.Games.Where(g => g.Value > 0).Select(g => new { v = g.Value, t = g.Text }).ToArray(),
            locations = locs.Select(l => new { v = l.Value, t = l.Text }).ToArray(),
        };
    }

    public static string Name(IReadOnlyList<string> list, int index)
        => (uint)index < (uint)list.Count ? list[index] : $"#{index}";

    public static string SafeReport(LegalityAnalysis la, string lang, bool verbose)
    {
        try { return la.Report(lang, verbose); }
        catch
        {
            try { return la.Report(verbose); } catch (Exception ex) { return ex.Message; }
        }
    }

    private static string SafeShowdown(PKM pk)
    {
        try { using (new EnglishScope()) return ShowdownParsing.GetShowdownText(pk); } catch { return ""; }
    }

    private static string SafeFileName(PKM pk)
    {
        try { return pk.FileName; } catch { return $"{pk.Species}.{pk.Extension}"; }
    }
}
