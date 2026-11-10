using PKHeX.Core;

namespace PkMac.Engine.Features;

/// <summary>
/// Event flags / work values (story progress, hidden items, trainers, legendary encounters...) for Gen 1-7, LGPE and BDSP.
/// Gen 8 SW/SH, PLA, SV and Z-A keep everything in SCBlocks and are edited through <see cref="Blocks"/>.
/// </summary>
public static class Events
{
    /// <summary>Uniform access to the different flag/work containers.</summary>
    private sealed class Store
    {
        public required string Game;
        public required int FlagCount;
        public required Func<int, bool> GetFlag;
        public required Action<int, bool> SetFlag;
        public int WorkCount;
        public Func<int, int> GetWork = _ => 0;
        public Action<int, int> SetWork = (_, _) => { };
        public int WorkMax = ushort.MaxValue;
        public int SystemCount;
        public Func<int, bool> GetSystem = _ => false;
        public Action<int, bool> SetSystem = (_, _) => { };
        public Action Commit = () => { };
    }

    private static string Suffix(GameVersion v) => v switch
    {
        GameVersion.X or GameVersion.Y => "xy",
        GameVersion.OR or GameVersion.AS => "oras",
        GameVersion.SN or GameVersion.MN => "sm",
        GameVersion.US or GameVersion.UM => "usum",
        GameVersion.D or GameVersion.P => "dp",
        GameVersion.Pt => "pt",
        GameVersion.HG or GameVersion.SS => "hgss",
        GameVersion.B or GameVersion.W => "bw",
        GameVersion.B2 or GameVersion.W2 => "b2w2",
        GameVersion.R or GameVersion.S => "rs",
        GameVersion.E => "e",
        GameVersion.FR or GameVersion.LG => "frlg",
        GameVersion.C => "c",
        GameVersion.GD or GameVersion.SI => "gs",
        GameVersion.RD or GameVersion.GN or GameVersion.BU or GameVersion.YW => "rby",
        GameVersion.GP or GameVersion.GE => "gg",
        GameVersion.BD or GameVersion.SP => "bdsp",
        _ => "",
    };

    private static Store? Open(SaveFile sav)
    {
        var game = Suffix(sav.Version);
        switch (sav)
        {
            case SAV7b b:
            {
                var w = b.EventWork;
                return new Store
                {
                    Game = game, FlagCount = w.CountFlag, GetFlag = w.GetFlag, SetFlag = (i, v) => w.SetFlag(i, v),
                    WorkCount = w.CountWork, GetWork = w.GetWork, SetWork = w.SetWork, WorkMax = int.MaxValue,
                };
            }
            case SAV8BS bs:
            {
                var w = bs.FlagWork;
                return new Store
                {
                    Game = game, FlagCount = w.CountFlag, GetFlag = w.GetFlag, SetFlag = w.SetFlag,
                    WorkCount = w.CountWork, GetWork = w.GetWork, SetWork = w.SetWork, WorkMax = int.MaxValue,
                    SystemCount = w.CountSystem, GetSystem = w.GetSystemFlag, SetSystem = w.SetSystemFlag,
                };
            }
            case IEventFlagProvider37 provider:
            {
                var w = provider.EventWork;
                return new Store
                {
                    Game = game, FlagCount = w.EventFlagCount, GetFlag = w.GetEventFlag, SetFlag = w.SetEventFlag,
                    WorkCount = w.EventWorkCount, GetWork = i => w.GetWork(i), SetWork = (i, v) => w.SetWork(i, (ushort)v),
                    Commit = () => { if (w is EventWork7 sm) sm.UpdateQrConstants(); },
                };
            }
            case IEventFlag37 w:
                return new Store
                {
                    Game = game, FlagCount = w.EventFlagCount, GetFlag = w.GetEventFlag, SetFlag = w.SetEventFlag,
                    WorkCount = w.EventWorkCount, GetWork = i => w.GetWork(i), SetWork = (i, v) => w.SetWork(i, (ushort)v),
                };
            case IEventFlagArray f when sav is IEventWorkArray<byte> wb:
                return new Store
                {
                    Game = game, FlagCount = f.EventFlagCount, GetFlag = f.GetEventFlag, SetFlag = f.SetEventFlag,
                    WorkCount = wb.EventWorkCount, GetWork = i => wb.GetWork(i), SetWork = (i, v) => wb.SetWork(i, (byte)v), WorkMax = 255,
                };
            case IEventFlagArray f:
                return new Store { Game = game, FlagCount = f.EventFlagCount, GetFlag = f.GetEventFlag, SetFlag = f.SetEventFlag };
        }
        return null;
    }

    private static string TypeName(NamedEventType t) => t switch
    {
        NamedEventType.HiddenItem => "Strumenti nascosti",
        NamedEventType.TrainerToggle => "Allenatori",
        NamedEventType.StoryProgress => "Trama",
        NamedEventType.FlyToggle => "Volo",
        NamedEventType.Misc => "Varie",
        NamedEventType.Statistic => "Statistiche",
        NamedEventType.Achievement => "Traguardi",
        NamedEventType.UsefulFeature => "Funzioni utili",
        NamedEventType.EventEncounter => "Incontri speciali",
        NamedEventType.GiftAvailable => "Regali",
        NamedEventType.Rebattle => "Rivincite",
        _ => "Altro",
    };

    private static (IReadOnlyList<NamedEventValue> flags, IReadOnlyList<NamedEventWork> work, IReadOnlyList<NamedEventValue> system) Labels(Store st)
    {
        if (st.Game.Length == 0)
            return ([], [], []);
        try
        {
            if (st.SystemCount > 0)
            {
                var l = new EventLabelCollectionSystem(st.Game, st.FlagCount - 1, st.SystemCount - 1, st.WorkCount - 1);
                return (l.Flag, l.Work, l.System);
            }
            var c = new EventLabelCollection(st.Game, st.FlagCount - 1, Math.Max(0, st.WorkCount - 1));
            return (c.Flag, c.Work, []);
        }
        catch
        {
            return ([], [], []);
        }
    }

    public static object Get(Session s)
    {
        var sav = s.Sav;
        var st = Open(sav);
        if (st is null)
        {
            bool blocks = sav is ISCBlockArray;
            return new
            {
                supported = false,
                useBlocks = blocks,
                message = blocks
                    ? "In questo gioco eventi, contatori e progressi sono salvati come blocchi: usa la sezione “Blocchi di gioco”."
                    : "Questo gioco non ha eventi modificabili.",
            };
        }

        var (flagLabels, workLabels, systemLabels) = Labels(st);
        var flags = Enumerable.Range(0, st.FlagCount).Select(st.GetFlag).ToArray();
        var work = Enumerable.Range(0, st.WorkCount).Select(st.GetWork).ToArray();
        var system = Enumerable.Range(0, st.SystemCount).Select(st.GetSystem).ToArray();

        return new
        {
            supported = true,
            game = GameInfo.GetVersionName(sav.Version),
            flagCount = st.FlagCount,
            workCount = st.WorkCount,
            systemCount = st.SystemCount,
            workMax = st.WorkMax,
            flags,
            work,
            system,
            namedFlags = flagLabels.Where(l => l.Index < st.FlagCount)
                .Select(l => new { i = l.Index, name = l.Name, category = TypeName(l.Type) }).ToArray(),
            namedSystem = systemLabels.Where(l => l.Index < st.SystemCount)
                .Select(l => new { i = l.Index, name = l.Name, category = TypeName(l.Type) }).ToArray(),
            namedWork = workLabels.Where(l => l.Index < st.WorkCount).Select(l => new
            {
                i = l.Index,
                name = l.Name,
                category = TypeName(l.Type),
                options = l.PredefinedValues.Where(v => !v.IsCustom).Select(v => new { v = (int)v.Value, t = v.Name }).ToArray(),
            }).ToArray(),
        };
    }

    /// <summary>{ flags: [[i, bool]], system: [[i, bool]], work: [[i, value]] }.</summary>
    public static object Set(Session s, Params p)
    {
        var sav = s.Sav;
        var st = Open(sav) ?? throw new EngineException("Questo gioco non ha eventi modificabili qui.");
        s.Snapshot("Eventi di gioco");
        foreach (var (key, count, apply) in new (string, int, Action<int, System.Text.Json.Nodes.JsonNode>)[]
        {
            ("flags", st.FlagCount, (i, n) => st.SetFlag(i, n.ToJsonString() == "true")),
            ("system", st.SystemCount, (i, n) => st.SetSystem(i, n.ToJsonString() == "true")),
            ("work", st.WorkCount, (i, n) => st.SetWork(i, (int)Math.Clamp(long.Parse(n.ToJsonString().Trim('"'), System.Globalization.CultureInfo.InvariantCulture), st.WorkMax == int.MaxValue ? int.MinValue : 0, st.WorkMax))),
        })
        {
            if (p.Raw[key] is not System.Text.Json.Nodes.JsonArray list) continue;
            foreach (var entry in list)
            {
                if (entry is not System.Text.Json.Nodes.JsonArray pair || pair.Count < 2) continue;
                var i = int.Parse(pair[0]!.ToJsonString());
                if ((uint)i >= count) continue;
                apply(i, pair[1]!);
            }
        }
        st.Commit();
        s.Dirty = true;
        return Get(s);
    }
}
