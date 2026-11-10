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
        };
    }

    /// <summary>Badge bitfield for games that expose one through reflection (Gen 1-7).</summary>
    private static object? Badges(SaveFile sav)
    {
        var prop = BadgeProp(sav);
        if (prop is null || !prop.CanRead || !prop.CanWrite)
            return null;
        try
        {
            var v = Convert.ToInt32(prop.GetValue(sav));
            int count = sav is SAV2 || prop.Name == "Badges16" ? 16 : 8;
            return new { value = v, count };
        }
        catch { return null; }
    }

    private static System.Reflection.PropertyInfo? BadgeProp(SaveFile sav) =>
        sav.GetType().GetProperty("Badges16") ?? sav.GetType().GetProperty("Badges");

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
        {
            var prop = BadgeProp(sav);
            if (prop is { CanWrite: true })
                prop.SetValue(sav, Convert.ChangeType(p.Int("badges"), prop.PropertyType));
        }
        s.Dirty = true;
        return Get(s);
    }
}
