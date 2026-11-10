using PKHeX.Core;

namespace PkMac.Engine.Features;

public static class TrainerInfo
{
    public static object Get(Session s)
    {
        var sav = s.Sav;
        return new
        {
            ot = sav.OT,
            maxOtLength = sav.MaxStringLengthTrainer,
            gender = sav.Gender,
            tid = sav.DisplayTID,
            sid = sav.DisplaySID,
            money = sav.Money,
            maxMoney = sav.MaxMoney,
            hours = sav.PlayedHours,
            minutes = sav.PlayedMinutes,
            seconds = sav.PlayedSeconds,
            language = sav.Language,
            game = GameInfo.GetVersionName(sav.Version),
        };
    }

    public static object Set(Session s, Params p)
    {
        var sav = s.Sav;
        if (p.OptStr("ot") is { } ot)
        {
            ot = ot.Trim();
            if (ot.Length == 0 || ot.Length > sav.MaxStringLengthTrainer)
                throw new EngineException($"Nome allenatore non valido (1–{sav.MaxStringLengthTrainer} caratteri).");
            sav.OT = ot;
        }
        if (p.Has("money"))
            sav.Money = (uint)Math.Clamp(p.Int("money"), 0, sav.MaxMoney);
        if (p.Has("hours"))
        {
            sav.PlayedHours = Math.Clamp(p.Int("hours"), 0, 999);
            sav.PlayedMinutes = Math.Clamp(p.Int("minutes", sav.PlayedMinutes), 0, 59);
        }
        s.Dirty = true;
        return Get(s);
    }
}
