using PKHeX.Core;

namespace PkMac.Engine.Features;

public static class TrainerInfo
{
    private static (uint tidMax, uint sidMax, bool hasSid) Limits(SaveFile sav) => sav.TrainerIDDisplayFormat switch
    {
        TrainerIDFormat.SixDigit => (999_999, 4294, true),
        TrainerIDFormat.SixteenBitSingle => (65535, 0, false),
        _ => (65535, 65535, true),
    };

    public static object Get(Session s)
    {
        var sav = s.Sav;
        var (tidMax, sidMax, hasSid) = Limits(sav);
        var langs = s.Sources.Languages.Where(l => l.Value > 0).Select(l => new { v = l.Value, t = l.Text }).ToArray();
        return new
        {
            ot = sav.OT,
            maxOtLength = sav.MaxStringLengthTrainer,
            gender = sav.Gender,
            hasGender = sav.Generation >= 3 || sav.Version == GameVersion.C,
            tid = sav.DisplayTID,
            sid = sav.DisplaySID,
            tidMax,
            sidMax,
            hasSid,
            idFormat = sav.TrainerIDDisplayFormat == TrainerIDFormat.SixDigit ? "6" : "5",
            money = sav.Money,
            maxMoney = sav.MaxMoney,
            hours = sav.PlayedHours,
            minutes = sav.PlayedMinutes,
            seconds = sav.PlayedSeconds,
            maxHours = sav.Generation <= 3 ? 255 : 999,
            language = sav.Language,
            languages = sav.Language >= 0 ? langs : [],
            game = GameInfo.GetVersionName(sav.Version),
            versionKey = sav.Version.ToString(),
            generation = sav.Generation,
            seenCount = sav.HasPokeDex ? sav.SeenCount : 0,
            caughtCount = sav.HasPokeDex ? sav.CaughtCount : 0,
            badges = Badges(sav),
            stamps = Stamps(sav),
        };
    }

    /// <summary>
    /// Badge bitfield (bit i = badge i in game order) plus the PokeAPI sprite id of each badge
    /// (sprites/badges/N.png; Kanto 1-8, Johto 9-16, Hoenn 17-24, Sinnoh 25-32, Unova 33-42, Kalos 43-50, Paldea 70-77).
    /// </summary>
    private static object? Badges(SaveFile sav)
    {
        var v = ReadBadges(sav);
        if (v is null) return null;
        var sprites = BadgeSprites(sav);
        return new
        {
            value = v.Value,
            count = sprites?.Length ?? 8,
            sprites,
            // Scarlet/Violet: the badges are the story's "gym cleared" flags: shown, changed only from game events.
            readOnly = sav is SAV9SV,
            layout = sav is SAV8SWSH ? "galar" : null,
        };
    }

    // Let's Go: "gym leader defeated" system flags s0012-s0019 (Brock … Giovanni).
    private const int LgpeBadgeFlag = 12;
    // BDSP: system flags 124-131 (Coal … Beacon), the ones PKHeX counts as badges.
    private const int BdspBadgeFlag = 124;
    // Scarlet/Violet: FSYS_YMAP_SCENARIO_GYM_CLEAR_* in gym order (Bug, Grass, Electric, Water, Normal, Ghost, Psychic, Ice).
    private static readonly uint[] SvGymClear = [0x8485AC3A, 0x26216312, 0x815F4601, 0x16452421, 0x9457390D, 0x1C5C88A5, 0xD0249A05, 0x0A9299BC];

    private static int ReadFlags(Func<int, bool> get, int count)
    {
        int v = 0;
        for (int i = 0; i < count; i++)
            if (get(i)) v |= 1 << i;
        return v;
    }

    private static int SvBadges(SAV9SV sv) => ReadFlags(i =>
    {
        var b = sv.AllBlocks.FirstOrDefault(x => x.Key == SvGymClear[i]);
        return b is not null && b.Type == SCTypeCode.Bool2;
    }, 8);

    // ---------- Sun/Moon, Ultra Sun/Ultra Moon: trainer card stamps ----------

    private static object? Stamps(SaveFile sav) => sav is SAV7 s7
        ? new { value = (int)s7.Misc.Stamps, names = Enum.GetValues<Stamp7>().Select(StampName).ToArray() }
        : null;

    private static string StampName(Stamp7 s) => s switch
    {
        Stamp7.OfficialPokemonTrainer => Tr.T($"Allenatore di Pokémon ufficiale"),
        Stamp7.MelemeleTrialCompletion => Tr.T($"Prove di Mele Mele completate"),
        Stamp7.AkalaTrialCompletion => Tr.T($"Prove di Akala completate"),
        Stamp7.UlaulaTrialCompletion => Tr.T($"Prove di Ula Ula completate"),
        Stamp7.PoniTrialCompletion => Tr.T($"Prove di Poni completate"),
        Stamp7.IslandChallengeCompletion => Tr.T($"Giro delle isole completato"),
        Stamp7.MelemelePokedexCompletion => Tr.T($"Pokédex di Mele Mele completo"),
        Stamp7.AkalaPokedexCompletion => Tr.T($"Pokédex di Akala completo"),
        Stamp7.UlaulaPokedexCompletion => Tr.T($"Pokédex di Ula Ula completo"),
        Stamp7.PoniPokedexCompletion => Tr.T($"Pokédex di Poni completo"),
        Stamp7.AlolaPokedexCompletion => Tr.T($"Pokédex di Alola completo"),
        Stamp7.ConsecutiveSingleBattleWins50 => Tr.T($"50 vittorie di fila in lotte singole"),
        Stamp7.ConsecutiveDoubleBattleWins50 => Tr.T($"50 vittorie di fila in lotte doppie"),
        Stamp7.ConsecutiveMultiBattleWins50 => Tr.T($"50 vittorie di fila in lotte multiple"),
        Stamp7.PokeFinderPro => Tr.T($"Esperto del Pokévisore"),
        _ => s.ToString(),
    };

    private static readonly int[] Kanto = [1, 2, 3, 4, 5, 6, 7, 8];
    private static readonly int[] Johto = [9, 10, 11, 12, 13, 14, 15, 16];
    private static readonly int[] Hoenn = [17, 18, 19, 20, 21, 22, 23, 24];
    private static readonly int[] Sinnoh = [25, 26, 27, 28, 29, 30, 31, 32];
    private static readonly int[] Unova1 = [33, 34, 35, 36, 37, 38, 39, 40];
    private static readonly int[] Unova2 = [34, 41, 35, 36, 37, 38, 40, 42];
    private static readonly int[] Kalos = [43, 44, 45, 46, 47, 48, 49, 50];

    /// <summary>Null when PokeAPI has no sprites for that region (e.g. Galar): the view falls back to generic icons.</summary>
    private static int?[]? BadgeSprites(SaveFile sav) => sav switch
    {
        SAV1 => Box(Kanto),
        SAV2 => Box([.. Johto, .. Kanto]),
        SAV3FRLG => Box(Kanto),
        SAV3 => Box(Hoenn),
        SAV4HGSS => Box([.. Johto, .. Kanto]),
        SAV4 => Box(Sinnoh),
        SAV5B2W2 => Box(Unova2),
        SAV5 => Box(Unova1),
        SAV6XY => Box(Kalos),
        SAV6AO => Box(Hoenn),
        SAV8SWSH => new int?[8],
        SAV7b => Box(Kanto),
        SAV8BS => Box(Sinnoh),
        SAV9SV => Box([70, 71, 72, 73, 74, 75, 76, 77]),
        _ => null,
    };

    private static int?[] Box(int[] ids) => ids.Select(i => (int?)i).ToArray();

    /// <summary>Gen 2 and HGSS: Johto in bits 0-7, Kanto in bits 8-15.</summary>
    private static int? ReadBadges(SaveFile sav)
    {
        try
        {
            return sav switch
            {
                SAV1 s1 => s1.Badges,
                SAV2 s2 => s2.Badges,
                SAV3 s3 => s3.Badges,
                SAV4HGSS hg => hg.Badges | (hg.Badges16 << 8),
                SAV4 s4 => s4.Badges,
                SAV5 s5 => s5.Misc.Badges,
                SAV6 s6 => s6.Badges,
                SAV8SWSH sw => sw.Badges,
                SAV7b gg => ReadFlags(i => gg.EventWork.GetFlag(EventVarType.System, LgpeBadgeFlag + i), 8),
                SAV8BS bs => ReadFlags(i => bs.FlagWork.GetSystemFlag(BdspBadgeFlag + i), 8),
                SAV9SV sv => SvBadges(sv),
                _ => null,
            };
        }
        catch { return null; }
    }

    private static void WriteBadges(SaveFile sav, int v)
    {
        switch (sav)
        {
            case SAV1 s1: s1.Badges = v & 0xFF; break;
            case SAV2 s2: s2.Badges = v & 0xFFFF; break;
            case SAV3 s3: s3.Badges = v & 0xFF; break;
            case SAV4HGSS hg: hg.Badges = (byte)(v & 0xFF); hg.Badges16 = (v >> 8) & 0xFF; break;
            case SAV4 s4: s4.Badges = (byte)(v & 0xFF); break;
            case SAV5 s5: s5.Misc.Badges = v & 0xFF; break;
            case SAV6 s6: s6.Badges = v & 0xFF; break;
            case SAV8SWSH sw: sw.Badges = v & 0xFF; break;
            case SAV7b gg:
                for (int i = 0; i < 8; i++) gg.EventWork.SetFlag(EventVarType.System, LgpeBadgeFlag + i, (v & (1 << i)) != 0);
                break;
            case SAV8BS bs:
                for (int i = 0; i < 8; i++) bs.FlagWork.SetSystemFlag(BdspBadgeFlag + i, (v & (1 << i)) != 0);
                break;
            // SAV9SV: read only (story flags).
        }
    }

    public static object Set(Session s, Params p)
    {
        var sav = s.Sav;
        var (tidMax, sidMax, hasSid) = Limits(sav);
        if (p.OptStr("ot") is { } ot)
        {
            ot = ot.Trim();
            if (ot.Length == 0 || ot.Length > sav.MaxStringLengthTrainer)
                throw new EngineException(Tr.T($"Nome allenatore non valido (1–{sav.MaxStringLengthTrainer} caratteri)."));
            sav.OT = ot;
        }
        if (p.Has("gender"))
            sav.Gender = (byte)Math.Clamp(p.Int("gender"), 0, 1);
        if (p.Has("tid"))
        {
            var tid = p.Int("tid");
            if (tid < 0 || tid > tidMax) throw new EngineException(Tr.T($"ID allenatore non valido (0–{tidMax})."));
            sav.DisplayTID = (uint)tid;
        }
        if (p.Has("sid") && hasSid)
        {
            var sid = p.Int("sid");
            if (sid < 0 || sid > sidMax) throw new EngineException(Tr.T($"ID segreto non valido (0–{sidMax})."));
            sav.DisplaySID = (uint)sid;
        }
        if (p.Has("money"))
            sav.Money = (uint)Math.Clamp(p.Int("money"), 0, sav.MaxMoney);
        if (p.Has("hours"))
        {
            var max = sav.Generation <= 3 ? 255 : 999;
            sav.PlayedHours = Math.Clamp(p.Int("hours"), 0, max);
            sav.PlayedMinutes = Math.Clamp(p.Int("minutes", sav.PlayedMinutes), 0, 59);
            sav.PlayedSeconds = Math.Clamp(p.Int("seconds", sav.PlayedSeconds), 0, 59);
        }
        if (p.Has("language") && sav.Language >= 0)
            sav.Language = p.Int("language");
        if (p.Has("badges"))
            WriteBadges(sav, p.Int("badges"));
        if (p.Has("stamps") && sav is SAV7 s7)
            s7.Misc.Stamps = (uint)p.Int("stamps") & 0x7FFF;
        s.Dirty = true;
        return Get(s);
    }
}
