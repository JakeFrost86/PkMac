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
        if (pk.Species == 0) throw new EngineException("Lo slot è vuoto.");
        var before = new LegalityAnalysis(pk).Valid;
        PKM result;
        try { result = s.Sav.Legalize(pk); }
        catch (MissingMethodException) { throw new EngineException("Auto Legality non è compatibile con questa versione del core. Aggiorna il pacchetto motore dalle impostazioni."); }
        result.Heal();
        var after = new LegalityAnalysis(result).Valid;
        if (after)
            s.Set(r, result, settings: default(EntityImportSettings), label: "Legalizza");
        return new { before, after, applied = after, detail = Describe.Detail(s, r, s.Get(r)) };
    }

    public static object LegalizeBox(Session s, int box)
    {
        s.Snapshot("Legalizza box");
        var fixedCount = s.Sav.LegalizeBox(box);
        s.Dirty = true;
        return new { fixedCount };
    }

    public static object ImportShowdown(Session s, string text, int box, int slot)
    {
        var sav = s.Sav;
        text = text.Trim();
        // Pokepaste / Pastebin links are resolved by ALM's TeamPasteInfo.
        if (text.StartsWith("http", StringComparison.OrdinalIgnoreCase) && !text.Contains('\n'))
        {
            var paste = new TeamPasteInfo(text);
            if (!paste.Valid)
                throw new EngineException("Impossibile leggere il link (supportati: pokepast.es, pastebin).");
            text = paste.Sets;
        }
        IEnumerable<ShowdownSet> sets;
        if (ShowdownUtil.IsTeamBackup(text))
            sets = ShowdownTeamSet.GetTeams(text).SelectMany(t => t.Team);
        else
            sets = ShowdownParsing.GetShowdownSets(text);
        var list = sets.Where(z => z.Species != 0).ToList();
        if (list.Count == 0)
            throw new EngineException("Nessun set Showdown valido trovato nel testo.");

        var results = new List<object>();
        int index = box * sav.BoxSlotCount + slot;
        s.Snapshot(list.Count == 1 ? "Importa set" : $"Importa {list.Count} set");
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
            var regen = new RegenTemplate(set, sav.Generation);
            var res = sav.GetLegalFromSet(regen);
            var pk = res.Created;
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
        var sav = s.Sav;
        var template = sav.BlankPKM;
        template.Species = species;
        template.Form = form;
        template.CurrentLevel = 50;
        template.Language = sav.Language > 0 ? sav.Language : (int)LanguageID.English;
        if (shiny) template.SetShiny();
        var set = new ShowdownSet(template);
        var regen = new RegenTemplate(set, sav.Generation);
        var res = sav.GetLegalFromSet(regen);
        var pk = res.Created;
        pk.ResetPartyStats();
        if (pk.Species != species)
            throw new EngineException("Auto Legality non ha trovato un incontro legale per questa specie in questo gioco.");
        s.Set(r, pk, settings: default(EntityImportSettings), label: "Nuovo Pokémon");
        return new { status = Status(res.Status), legal = new LegalityAnalysis(pk).Valid, detail = Describe.Detail(s, r, s.Get(r)) };
    }

    public static object LivingDex(Session s, int startBox, bool shiny, bool forms)
    {
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
            generated = sav.GenerateLivingDex(sav.Personal, cfg).OrderBy(p => p.Species).ThenBy(p => p.Form).ToList();
        }
        finally { cts.Cancel(); }

        s.Snapshot("Pokédex vivente");
        int placed = 0, index = startBox * sav.BoxSlotCount;
        foreach (var pk in generated)
        {
            while (index < sav.SlotCount && (sav.GetBoxSlotAtIndex(index).Species != 0 || sav.IsBoxSlotOverwriteProtected(index)))
                index++;
            if (index >= sav.SlotCount) break;
            sav.SetBoxSlotAtIndex(pk, index, EntityImportSettings.None);
            placed++;
            index++;
        }
        s.Dirty = true;
        return new { generated = generated.Count, placed, skipped = generated.Count - placed };
    }
}
