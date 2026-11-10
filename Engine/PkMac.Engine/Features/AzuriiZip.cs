using System.IO.Compression;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using PKHeX.Core;

namespace PkMac.Engine.Features;

/// <summary>
/// Reads and rewrites, without unpacking them on disk, the zip files made by Azurii:
///  • per-game saves (export, save slots, iCloud copies, "prima di PKHeX" backups):
///      azurii_save.json (or azahar_save.json) + save/main | save/sav.dat [+ save.metadata, extdata/…]
///  • full backups: azurii_backup.json + Azurii/sdmc/Nintendo 3DS/…/title/{hi}/{lo}/data/00000001/main
/// Only the edited save entry and the manifest change; every other entry is copied byte for byte
/// so Azurii can import the zip again.
/// </summary>
public static partial class AzuriiZip
{
    public const string SaveManifest = "azurii_save.json";
    public const string LegacySaveManifest = "azahar_save.json";
    public const string BackupManifest = "azurii_backup.json";

    public sealed record Candidate(string Entry, string TitleId, string Game, long Size);

    public sealed class Container
    {
        public required string ZipPath { get; init; }
        public required string Kind { get; init; }          // "save" | "backup"
        public required string Entry { get; init; }          // zip entry of the edited save
        public string? TitleId { get; init; }
        public string? Title { get; init; }
        public string ManifestName { get; init; } = SaveManifest;

        public object Describe() => new
        {
            kind = Kind,
            entry = Entry,
            titleId = TitleId,
            title = Title,
            zipName = Path.GetFileName(ZipPath),
        };
    }

    // Azurii/sdmc/Nintendo 3DS/<id0>/<id1>/title/<hi>/<lo>/data/00000001/main
    [GeneratedRegex(@"title/([0-9a-fA-F]{8})/([0-9a-fA-F]{8})/data/[0-9a-fA-F]{8}/(main|sav\.dat)$")]
    private static partial Regex TitleSaveRegex();

    public static bool IsAzuriiZip(string path)
    {
        if (!path.EndsWith(".zip", StringComparison.OrdinalIgnoreCase)) return false;
        try
        {
            using var zip = ZipFile.OpenRead(path);
            return zip.GetEntry(SaveManifest) is not null || zip.GetEntry(LegacySaveManifest) is not null || zip.GetEntry(BackupManifest) is not null;
        }
        catch { return false; }
    }

    private static readonly Dictionary<string, string> KnownTitles = new(StringComparer.OrdinalIgnoreCase)
    {
        ["0004000000055D00"] = "Pokémon X", ["0004000000055E00"] = "Pokémon Y",
        ["000400000011C400"] = "Pokémon Rubino Omega", ["000400000011C500"] = "Pokémon Zaffiro Alpha",
        ["0004000000164800"] = "Pokémon Sole", ["0004000000175E00"] = "Pokémon Luna",
        ["00040000001B5000"] = "Pokémon Ultrasole", ["00040000001B5100"] = "Pokémon Ultraluna",
    };

    /// <summary>Lists the saves PKHeX can open inside an Azurii zip.</summary>
    public static (string kind, List<Candidate> saves, JsonObject? manifest) Inspect(string path)
    {
        using var zip = ZipFile.OpenRead(path);
        var saveManifest = zip.GetEntry(SaveManifest) ?? zip.GetEntry(LegacySaveManifest);
        var list = new List<Candidate>();
        if (saveManifest is not null)
        {
            var manifest = ReadJson(saveManifest);
            var titleId = manifest?["titleId"]?.GetValue<string>() ?? "";
            var title = manifest?["title"]?.GetValue<string>() ?? "";
            foreach (var name in new[] { "save/main", "save/sav.dat" })
            {
                if (zip.GetEntry(name) is { } e)
                {
                    list.Add(new Candidate(e.FullName, titleId, title, e.Length));
                    break;
                }
            }
            if (list.Count == 0)
            {
                // Same rule as Azurii: otherwise the largest file of the save folder.
                var biggest = zip.Entries.Where(e => e.FullName.StartsWith("save/") && !e.FullName.EndsWith('/'))
                    .OrderByDescending(e => e.Length).FirstOrDefault();
                if (biggest is not null) list.Add(new Candidate(biggest.FullName, titleId, title, biggest.Length));
            }
            return ("save", list, manifest);
        }

        if (zip.GetEntry(BackupManifest) is { } bm)
        {
            foreach (var e in zip.Entries)
            {
                var m = TitleSaveRegex().Match(e.FullName);
                if (!m.Success || e.Length is < 0x2000 or > 8 * 1024 * 1024) continue;
                var titleId = (m.Groups[1].Value + m.Groups[2].Value).ToUpperInvariant();
                var game = KnownTitles.GetValueOrDefault(titleId) ?? "";
                // Keep only what PKHeX recognizes as a Pokémon save.
                try
                {
                    var data = ReadAll(e);
                    if (!SaveUtil.TryGetSaveFile((Memory<byte>)data, out var sav)) continue;
                    if (game.Length == 0) game = "Pokémon " + GameInfo.GetVersionName(sav.Version);
                }
                catch { continue; }
                list.Add(new Candidate(e.FullName, titleId, game, e.Length));
            }
            return ("backup", list, ReadJson(bm));
        }
        throw new EngineException("Questo zip non è un salvataggio o un backup di Azurii.");
    }

    public static (SaveFile sav, Container container) Load(string path, string? entry)
    {
        var (kind, saves, manifest) = Inspect(path);
        if (saves.Count == 0)
            throw new EngineException(kind == "backup" ? "Nel backup non c'è nessun salvataggio Pokémon." : "Lo zip non contiene dati di salvataggio.");
        var pick = entry is null ? saves[0] : saves.FirstOrDefault(s => s.Entry == entry) ?? throw new EngineException("Salvataggio non trovato nello zip.");

        using var zip = ZipFile.OpenRead(path);
        var data = ReadAll(zip.GetEntry(pick.Entry)!);
        if (!SaveUtil.TryGetSaveFile((Memory<byte>)data, out var sav))
            throw new EngineException("Il salvataggio contenuto nello zip non è un gioco Pokémon riconosciuto.");
        var container = new Container
        {
            ZipPath = path,
            Kind = kind,
            Entry = pick.Entry,
            TitleId = pick.TitleId,
            Title = pick.Game.Length > 0 ? pick.Game : manifest?["title"]?.GetValue<string>(),
            ManifestName = kind == "backup" ? BackupManifest : (zip.GetEntry(SaveManifest) is not null ? SaveManifest : LegacySaveManifest),
        };
        return (sav, container);
    }

    /// <summary>
    /// Writes a new zip at <paramref name="dest"/>: same entries in the same order, the save entry
    /// replaced with <paramref name="saveData"/>, and the manifest updated so Azurii sees the
    /// edit (dates, editor); everything else is copied unchanged.
    /// </summary>
    public static void Write(Container c, byte[] saveData, string dest)
    {
        var now = DateTimeOffset.Now;
        var iso = now.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'");
        using var src = ZipFile.OpenRead(c.ZipPath);
        using (var fs = new FileStream(dest, FileMode.Create, FileAccess.ReadWrite))
        using (var dst = new ZipArchive(fs, ZipArchiveMode.Create))
        {
            foreach (var e in src.Entries)
            {
                if (e.FullName == c.Entry)
                {
                    var ne = dst.CreateEntry(e.FullName, CompressionLevel.Optimal);
                    ne.LastWriteTime = now;
                    using var w = ne.Open();
                    w.Write(saveData);
                }
                else if (e.FullName == c.ManifestName)
                {
                    var manifest = ReadJson(e) ?? new JsonObject();
                    UpdateManifest(manifest, c, iso);
                    var ne = dst.CreateEntry(e.FullName, CompressionLevel.Optimal);
                    ne.LastWriteTime = now;
                    using var w = ne.Open();
                    w.Write(JsonSerializer.SerializeToUtf8Bytes(manifest, new JsonSerializerOptions { WriteIndented = true }));
                }
                else
                {
                    bool stored = e.CompressedLength == e.Length && e.Length > 0;
                    var ne = dst.CreateEntry(e.FullName, stored ? CompressionLevel.NoCompression : CompressionLevel.Optimal);
                    ne.LastWriteTime = e.LastWriteTime;
                    if (e.FullName.EndsWith('/') && e.Length == 0)
                        continue; // directory entry
                    using var r = e.Open();
                    using var w = ne.Open();
                    r.CopyTo(w);
                }
            }
        }
    }

    private static void UpdateManifest(JsonObject m, Container c, string iso)
    {
        m["editedWith"] = $"PkMac {Versions.Engine} · PKHeX.Core {Versions.Core}";
        m["modified"] = iso;
        if (c.Kind == "save")
        {
            // Azurii shows "created" as the date of a slot and uses "saveDate" to sync iCloud:
            // both move forward so the edited copy is seen as the newest one.
            if (m["created"] is not null && m["originalCreated"] is null)
                m["originalCreated"] = m["created"]!.DeepClone();
            m["created"] = iso;
            if (m["saveDate"] is not null)
                m["saveDate"] = iso;
        }
        else
        {
            var edited = m["editedSaves"] as JsonArray ?? new JsonArray();
            if (!edited.Any(n => n?.GetValue<string>() == c.Entry))
                edited.Add(c.Entry);
            m["editedSaves"] = edited;
        }
    }

    /// <summary>Re-reads the written zip and checks the save entry and that nothing went missing.</summary>
    public static string? Verify(Container c, string written, byte[] expected)
    {
        using var a = ZipFile.OpenRead(c.ZipPath);
        using var b = ZipFile.OpenRead(written);
        var names = a.Entries.Select(e => e.FullName).Where(n => !n.EndsWith('/')).ToHashSet();
        var namesB = b.Entries.Select(e => e.FullName).ToHashSet();
        var missing = names.Where(n => !namesB.Contains(n)).ToList();
        if (missing.Count > 0)
            return $"mancano {missing.Count} file nello zip riscritto (es. {missing[0]})";
        var entry = b.GetEntry(c.Entry);
        if (entry is null) return "il salvataggio non è nello zip riscritto";
        if (!ReadAll(entry).AsSpan().SequenceEqual(expected)) return "il salvataggio nello zip non coincide con quello verificato";
        foreach (var e in a.Entries)
        {
            if (e.FullName == c.Entry || e.FullName == c.ManifestName || e.FullName.EndsWith('/')) continue;
            if (b.GetEntry(e.FullName) is not { } other || other.Length != e.Length || other.Crc32 != e.Crc32)
                return $"il file {e.FullName} è cambiato";
        }
        return null;
    }

    private static byte[] ReadAll(ZipArchiveEntry e)
    {
        using var s = e.Open();
        using var ms = new MemoryStream((int)Math.Max(0, Math.Min(e.Length, int.MaxValue)));
        s.CopyTo(ms);
        return ms.ToArray();
    }

    private static JsonObject? ReadJson(ZipArchiveEntry e)
    {
        try { return JsonNode.Parse(ReadAll(e)) as JsonObject; } catch { return null; }
    }
}
