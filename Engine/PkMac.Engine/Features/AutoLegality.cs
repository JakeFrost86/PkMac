using PKHeX.Core;
using PKHeX.Core.AutoMod;
using PKHeX.Core.Enhancements;

namespace PkMac.Engine.Features;

/// <summary>
/// Auto Legality Mod (santacrab2/PKHeX-Plugins, originally architdate &amp; kwsch) without its WinForms UI.
/// </summary>
public static class AutoLegality
{
    public static object Configure(Params p)
    {
        // PkMac validates ALM against the loaded core with its own self-test, so ALM's
        // network-based version gate is disabled (it would otherwise block hot core updates).
        APILegality.EnableDevMode = true;
        APILegality.LatestAllowedVersion = "99.0.0.0";
        APILegality.UseTrainerData = p.Bool("useTrainerData", true);
        APILegality.SetAllLegalRibbons = p.Bool("setAllLegalRibbons", false);
        APILegality.SetMatchingBalls = p.Bool("setMatchingBalls", true);
        APILegality.UseMarkings = p.Bool("useMarkings", true);
        APILegality.UseCompetitiveMarkings = p.Bool("useCompetitiveMarkings", false);
        APILegality.ForceLevel100for50 = p.Bool("forceLevel100for50", true);
        APILegality.Timeout = Math.Clamp(p.Int("timeout", 15), 5, 120);
        Legalizer.EnableEasterEggs = p.Bool("easterEggs", false);
        return true;
    }

    /// <summary>
    /// Makes ALM use the trainer of the save being edited (OT, IDs, gender, language, 3DS region) for every
    /// game version instead of its own "ALM" fallback trainer.
    /// </summary>
    public static void UseSaveTrainer(SaveFile sav)
    {
        TrainerSettings.Clear();
        var lang = sav.Language > 0 ? sav.Language : (int)LanguageID.English;
        byte cr = 1, rg = 7, co = 49;
        if (sav is IRegionOriginReadOnly geo) { cr = geo.ConsoleRegion; rg = geo.Region; co = geo.Country; }
        foreach (var v in GameUtil.GameVersions)
        {
            if (v == GameVersion.Any) continue;
            try
            {
                var t = new SimpleTrainerInfo(v) { OT = sav.OT, TID16 = sav.TID16, SID16 = sav.SID16, Gender = sav.Gender, Language = lang };
                if (t.Context is EntityContext.Gen6 or EntityContext.Gen7)
                    t = t with { ConsoleRegion = cr, Region = rg, Country = co };
                TrainerSettings.Register(t);
            }
            catch { /* versions without a context */ }
        }
        TrainerSettings.DefaultOT = sav.OT;
        TrainerSettings.DefaultTID16 = sav.TID16;
        TrainerSettings.DefaultSID16 = sav.SID16;
    }

    /// <summary>Generated Pokémon speak the language of the save they are created in (when that stays legal).</summary>
    public static PKM ApplySaveLanguage(PKM pk, SaveFile sav)
    {
        if (sav.Language <= 0 || pk.Language == sav.Language || pk.Format <= 2)
            return pk;
        var copy = pk.Clone();
        bool nick = copy.IsNicknamed;
        copy.Language = sav.Language;
        if (!nick) copy.ClearNickname();
        copy.RefreshChecksum();
        return new LegalityAnalysis(copy).Valid || !new LegalityAnalysis(pk).Valid ? copy : pk;
    }

    public static string EventsFolder => Path.Combine(SaveIO.AppSupport, "mgdb");

    /// <summary>Loads the Project Pokémon event gallery (if downloaded) so ALM can generate event Pokémon.</summary>
    public static void LoadEvents()
    {
        if (Directory.Exists(EventsFolder))
        {
            try { EncounterEvent.RefreshMGDB(EventsFolder); }
            catch (Exception ex) { Program.Log($"mgdb: {ex.Message}"); }
        }
    }

    public static object DownloadEvents()
    {
        var cwd = Environment.CurrentDirectory;
        Directory.CreateDirectory(SaveIO.AppSupport);
        try
        {
            Environment.CurrentDirectory = SaveIO.AppSupport; // the downloader uses a relative temp.zip
            if (Directory.Exists(EventsFolder))
                Directory.Delete(EventsFolder, true);
            EventsGallery.DownloadMGDBFromGitHub(EventsFolder, entire: false);
        }
        finally { Environment.CurrentDirectory = cwd; }
        LoadEvents();
        var count = Directory.Exists(EventsFolder) ? Directory.EnumerateFiles(EventsFolder, "*", SearchOption.AllDirectories).Count() : 0;
        return new { files = count, path = EventsFolder };
    }

    public static object EventsStatus()
    {
        var exists = Directory.Exists(EventsFolder);
        return new
        {
            installed = exists,
            files = exists ? Directory.EnumerateFiles(EventsFolder, "*", SearchOption.AllDirectories).Count() : 0,
            date = exists ? Directory.GetLastWriteTime(EventsFolder).ToString("o") : null,
        };
    }

    private static string Status(LegalizationResult r) => r switch
    {
        LegalizationResult.Regenerated => "ok",
        LegalizationResult.Timeout => "timeout",
        LegalizationResult.VersionMismatch => "mismatch",
        _ => "failed",
    };

    public static object Legalize(Session s, SlotRef r)
    {
        var pk = s.Get(r);
        if (pk.Species == 0) throw new EngineException(Tr.T($"Lo slot è vuoto."));
        var before = new LegalityAnalysis(pk).Valid;
        var (result, after, _) = Pipeline(s, pk.Clone());
        if (after && !before)
            s.Set(r, result, settings: default(EntityImportSettings), label: Tr.T($"Legalizza"));
        return new { before, after, applied = after && !before, detail = Describe.Detail(s, r, s.Get(r)) };
    }

    /// <summary>
    /// The legalization steps, least invasive first:
    /// 1) PKHeX's suggestions (moves, relearn moves, met data);
    /// 2) Sword/Shield overworld: PID/IVs/size rebuilt from the seed of its own EC;
    /// 3) Auto Legality Mod regeneration;
    /// 4) rebuild from a legal encounter of the same species/form, keeping what it can.
    /// </summary>
    private static (PKM pk, bool legal, string method) Pipeline(Session s, PKM pk)
    {
        UseSaveTrainer(s.Sav);
        if (new LegalityAnalysis(pk).Valid)
            return (pk, true, "none");

        var suggested = Encounters.ApplySuggestions(pk.Clone());
        if (new LegalityAnalysis(suggested).Valid)
            return (suggested, true, "suggestions");

        if (Encounters.RestoreFromSeed(suggested.Clone()) is { } seeded)
        {
            if (new LegalityAnalysis(seeded).Valid)
                return (seeded, true, "seed");
            suggested = seeded;
        }

        PKM alm;
        try { using (new EnglishScope()) alm = s.Sav.Legalize(pk.Clone()); }
        catch (MissingMethodException) { throw new EngineException(Tr.T($"Auto Legality non è compatibile con questa versione del core. Aggiorna il pacchetto motore dalle impostazioni.")); }
        alm.Heal();
        if (new LegalityAnalysis(alm).Valid)
            return (alm, true, "alm");

        if (Encounters.CreateLegal(s.Sav, pk.Species, pk.Form, pk.IsShiny, keep: pk) is { } rebuilt)
            return (rebuilt, true, "rebuild");

        return (suggested, false, "none");
    }

    /// <summary>Gives the Pokémon to the save's trainer: OT name, gender, IDs, language.</summary>
    private static void MakeMine(PKM pk, SaveFile sav)
    {
        pk.OriginalTrainerName = sav.OT;
        pk.OriginalTrainerGender = sav.Gender;
        if (pk.Format <= 2) pk.TID16 = sav.TID16;
        else pk.ID32 = sav.ID32;
        if (pk.Format >= 3 && sav.Language > 0 && pk.Language != sav.Language)
        {
            bool nick = pk.IsNicknamed;
            pk.Language = sav.Language;
            if (!nick) pk.ClearNickname();
        }
        if (pk.Format >= 6)
        {
            pk.CurrentHandler = 0;
            if (pk.HandlingTrainerName == sav.OT)
            {
                pk.HandlingTrainerName = "";
                pk.HandlingTrainerGender = 0;
            }
        }
        pk.RefreshChecksum();
    }

    private static string Key(SlotRef r) => $"{r.Party}-{r.Box}-{r.Slot}";

    /// <summary>
    /// Works out what "Make legal" (or "Make mine", then legal) would change, without touching the save.
    /// The result waits in the session until <see cref="ApplyPending"/>.
    /// </summary>
    public static object Preview(Session s, SlotRef r, bool mine)
    {
        var original = s.Get(r);
        if (original.Species == 0) throw new EngineException(Tr.T($"Lo slot è vuoto."));
        var start = original.Clone();
        if (mine) MakeMine(start, s.Sav);
        var (result, legal, method) = Pipeline(s, start);
        var la = new LegalityAnalysis(result);
        s.Pending[Key(r)] = (original.Clone(), result, mine ? Tr.T($"Rendi mio") : Tr.T($"Legalizza"));
        var problems = legal ? [] : Describe.SafeReport(la, s.Language, verbose: false).Split('\n').Where(l => l.Trim().Length > 0).Take(8).ToArray();
        return new
        {
            before = new LegalityAnalysis(original).Valid,
            legal,
            method,
            mine,
            changes = Diff(s, original, result),
            problems,
        };
    }

    public static object ApplyPending(Session s, SlotRef r)
    {
        if (!s.Pending.TryRemove(Key(r), out var p))
            throw new EngineException(Tr.T($"Nessuna modifica in attesa per questo Pokémon."));
        var now = s.Get(r);
        if (now.Species != p.Original.Species || now.PID != p.Original.PID || now.EncryptionConstant != p.Original.EncryptionConstant)
            throw new EngineException(Tr.T($"Il Pokémon è cambiato dopo l'anteprima: ripeti l'operazione."));
        p.Result.ResetPartyStats();
        s.Set(r, p.Result, settings: default(EntityImportSettings), label: p.Label);
        return new { legal = new LegalityAnalysis(s.Get(r)).Valid, detail = Describe.Detail(s, r, s.Get(r)) };
    }

    // ---------- what changed ----------

    private static List<(string Label, string Value)> Fields(Session s, PKM pk)
    {
        string N(IReadOnlyList<string> list, int i) => Describe.Name(list, i);
        string Moves(ReadOnlySpan<ushort> m)
        {
            var parts = new List<string>();
            foreach (var x in m) if (x != 0) parts.Add(N(s.Strings.Move, x));
            return parts.Count == 0 ? "—" : string.Join(", ", parts);
        }
        Span<ushort> moves = stackalloc ushort[4];
        pk.GetMoves(moves);
        Span<ushort> relearn = stackalloc ushort[4];
        pk.GetRelearnMoves(relearn);
        string location;
        try { location = pk.GetLocationString(false); } catch { location = pk.MetLocation.ToString(); }

        var f = new List<(string, string)>
        {
            (Tr.T($"Specie"), N(s.Strings.Species, pk.Species) + (pk.Form > 0 ? $" ({pk.Form})" : "")),
            (Tr.T($"Soprannome"), pk.Nickname),
            (Tr.T($"Livello"), pk.CurrentLevel.ToString()),
            (Tr.T($"Cromatico"), pk.IsShiny ? Tr.T($"sì") : Tr.T($"no")),
            (Tr.T($"Sesso"), pk.Gender switch { 0 => "♂", 1 => "♀", _ => "—" }),
            (Tr.T($"Natura"), N(s.Strings.Natures, (int)pk.Nature)),
            (Tr.T($"Abilità"), pk.Ability > 0 ? N(s.Strings.Ability, pk.Ability) : "—"),
            (Tr.T($"Strumento"), pk.HeldItem > 0 ? N(s.Strings.Item, pk.HeldItem) : "—"),
            (Tr.T($"Ball"), N(s.Strings.balllist, pk.Ball)),
            ("PID", pk.PID.ToString("X8")),
            ("EC", pk.EncryptionConstant.ToString("X8")),
            ("IV", $"{pk.IV_HP}/{pk.IV_ATK}/{pk.IV_DEF}/{pk.IV_SPA}/{pk.IV_SPD}/{pk.IV_SPE}"),
            ("EV", $"{pk.EV_HP}/{pk.EV_ATK}/{pk.EV_DEF}/{pk.EV_SPA}/{pk.EV_SPD}/{pk.EV_SPE}"),
            (Tr.T($"Mosse"), Moves(moves)),
        };
        if (pk.Format >= 6) f.Add((Tr.T($"Mosse ricordabili"), Moves(relearn)));
        if (pk is IScaledSize sz)
        {
            f.Add((Tr.T($"Altezza"), sz.HeightScalar.ToString()));
            f.Add((Tr.T($"Peso"), sz.WeightScalar.ToString()));
        }
        if (pk is IScaledSize3 sc) f.Add((Tr.T($"Scala"), sc.Scale.ToString()));
        if (pk is ITeraType t) f.Add((Tr.T($"Teratipo"), N(s.Strings.types, (int)t.TeraTypeOriginal)));
        f.Add((Tr.T($"Luogo d'incontro"), location));
        f.Add((Tr.T($"Livello d'incontro"), pk.MetLevel.ToString()));
        if (pk.MetDate is { } md) f.Add((Tr.T($"Data d'incontro"), md.ToString("yyyy-MM-dd")));
        f.Add((Tr.T($"Gioco d'origine"), GameInfo.GetVersionName(pk.Version)));
        f.Add((Tr.T($"Allenatore originale"), $"{pk.OriginalTrainerName} {(pk.OriginalTrainerGender == 0 ? "♂" : "♀")}"));
        f.Add(("ID", pk.GetDisplayTID().ToString()));
        if (pk.Format >= 3) f.Add((Tr.T($"ID segreto"), pk.GetDisplaySID().ToString()));
        if (pk.Format >= 3) f.Add((Tr.T($"Lingua"), ((LanguageID)pk.Language).ToString()));
        if (pk.Format >= 6) f.Add((Tr.T($"Allenatore attuale"), pk.CurrentHandler == 0 ? Tr.T($"originale") : pk.HandlingTrainerName));
        if (pk is IHomeTrack h) f.Add((Tr.T($"Codice HOME"), h.Tracker.ToString("X16")));
        return f;
    }

    private static object[] Diff(Session s, PKM a, PKM b)
    {
        var fa = Fields(s, a); var fb = Fields(s, b);
        var map = fb.ToDictionary(x => x.Label, x => x.Value);
        return fa.Where(x => map.TryGetValue(x.Label, out var v) && v != x.Value)
                 .Select(x => (object)new { field = x.Label, from = x.Value, to = map[x.Label] })
                 .ToArray();
    }

    public static object LegalizeBox(Session s, int box)
    {
        UseSaveTrainer(s.Sav);
        s.Snapshot(Tr.T($"Legalizza box"));
        int fixedCount;
        using (new EnglishScope()) fixedCount = s.Sav.LegalizeBox(box);
        s.Dirty = true;
        return new { fixedCount };
    }

    public static object ImportShowdown(Session s, string text, int box, int slot)
    {
        UseSaveTrainer(s.Sav);
        var sav = s.Sav;
        text = text.Trim();
        // Pokepaste / Pastebin links are resolved by ALM's TeamPasteInfo.
        if (text.StartsWith("http", StringComparison.OrdinalIgnoreCase) && !text.Contains('\n'))
        {
            var paste = new TeamPasteInfo(text);
            if (!paste.Valid)
                throw new EngineException(Tr.T($"Impossibile leggere il link (supportati: pokepast.es, pastebin)."));
            text = paste.Sets;
        }
        List<ShowdownSet> list;
        using (new EnglishScope())
        {
            IEnumerable<ShowdownSet> sets = ShowdownUtil.IsTeamBackup(text)
                ? ShowdownTeamSet.GetTeams(text).SelectMany(t => t.Team)
                : ShowdownParsing.GetShowdownSets(text);
            list = sets.Where(z => z.Species != 0).ToList();
        }
        if (list.Count == 0)
            throw new EngineException(Tr.T($"Nessun set Showdown valido trovato nel testo."));

        var results = new List<object>();
        int index = box * sav.BoxSlotCount + slot;
        s.Snapshot(list.Count == 1 ? Tr.T($"Importa set") : Tr.T($"Importa {list.Count} set"));
        foreach (var set in list)
        {
            // next empty, writable slot
            while (index < sav.SlotCount && (sav.GetBoxSlotAtIndex(index).Species != 0 || sav.IsBoxSlotOverwriteProtected(index)))
                index++;
            if (index >= sav.SlotCount)
            {
                results.Add(new { name = Describe.Name(s.Strings.Species, set.Species), status = "nospace" });
                continue;
            }
            if (set.InvalidLines.Count > 0)
            {
                results.Add(new { name = Describe.Name(s.Strings.Species, set.Species), status = "invalid", lines = set.InvalidLines.Select(l => l.ToString()).ToArray() });
                continue;
            }
            APILegality.AsyncLegalizationResult res;
            using (new EnglishScope()) res = sav.GetLegalFromSet(new RegenTemplate(set, sav.Generation));
            var pk = ApplySaveLanguage(res.Created, sav);
            pk.ResetPartyStats();
            pk.SetBoxForm();
            var legal = new LegalityAnalysis(pk).Valid;
            var r = new SlotRef(false, index / sav.BoxSlotCount, index % sav.BoxSlotCount);
            s.Set(r, pk, settings: default(EntityImportSettings), recordUndo: false);
            results.Add(new { name = Describe.Name(s.Strings.Species, pk.Species), status = Status(res.Status), legal, @ref = r.ToJson() });
            index++;
        }
        return results;
    }

    public static object Create(Session s, SlotRef r, ushort species, byte form, bool shiny)
    {
        UseSaveTrainer(s.Sav);
        var sav = s.Sav;
        PKM? pk = null;
        string status;
        using (new EnglishScope())
        {
            var en = GameInfo.Strings;
            var name = en.Species[species];
            if (form > 0)
            {
                var f = ShowdownParsing.GetShowdownFormName(species, ShowdownParsing.GetStringFromForm(form, en, species, sav.Context));
                if (f.Length > 0) name += "-" + f;
            }
            var text = name + "\n" + (shiny ? "Shiny: Yes\n" : "");
            var set = new ShowdownSet(text);
            var regen = new RegenTemplate(set, sav.Generation);
            var res = sav.GetLegalFromSet(regen);
            status = Status(res.Status);
            if (res.Created.Species == species && new LegalityAnalysis(res.Created).Valid)
                pk = res.Created;
        }
        // Fallback: PKHeX's own encounter generator (what its Encounter Database does).
        pk ??= Encounters.CreateLegal(sav, species, form, shiny);
        if (pk is null)
            throw new EngineException(Tr.T($"Nessun incontro legale trovato per questa specie/forma in questo gioco."));
        pk = ApplySaveLanguage(pk, sav);
        pk.ResetPartyStats();
        s.Set(r, pk, settings: default(EntityImportSettings), label: Tr.T($"Nuovo Pokémon"));
        return new { status, legal = new LegalityAnalysis(s.Get(r)).Valid, detail = Describe.Detail(s, r, s.Get(r)) };
    }

    public static object LivingDex(Session s, int startBox, bool shiny, bool forms)
    {
        UseSaveTrainer(s.Sav);
        var sav = s.Sav;
        var cfg = ModLogic.Config with { SetShiny = shiny, IncludeForms = forms, TransferVersion = sav.Version };
        ModLogic.TrackingCount = 0;
        using var cts = new CancellationTokenSource();
        var reporter = Task.Run(async () =>
        {
            while (!cts.IsCancellationRequested)
            {
                Program.Event("progress", new { task = "livingDex", done = ModLogic.TrackingCount, total = (int)sav.MaxSpeciesID });
                try { await Task.Delay(500, cts.Token); } catch { }
            }
        });

        List<PKM> generated;
        try
        {
            using (new EnglishScope())
                generated = sav.GenerateLivingDex(sav.Personal, cfg).OrderBy(p => p.Species).ThenBy(p => p.Form).ToList();
        }
        finally { cts.Cancel(); }

        s.Snapshot(Tr.T($"Pokédex vivente"));
        int placed = 0, index = startBox * sav.BoxSlotCount;
        foreach (var pk in generated)
        {
            while (index < sav.SlotCount && (sav.GetBoxSlotAtIndex(index).Species != 0 || sav.IsBoxSlotOverwriteProtected(index)))
                index++;
            if (index >= sav.SlotCount) break;
            sav.SetBoxSlotAtIndex(ApplySaveLanguage(pk, sav), index, EntityImportSettings.None);
            placed++;
            index++;
        }
        s.Dirty = true;
        return new { generated = generated.Count, placed, skipped = generated.Count - placed };
    }
}
