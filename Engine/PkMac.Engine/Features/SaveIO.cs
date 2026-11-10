using System.Security.Cryptography;
using System.Text;
using PKHeX.Core;
using PKHeX.Core.Injection;

namespace PkMac.Engine.Features;

/// <summary>
/// Opening and writing save files. Every write goes through a checksum-verified pipeline:
///   1. build the final binary (PKHeX recomputes checksums)
///   2. re-parse it from memory and require valid checksums + identical storage contents
///   3. back up the file currently on disk
///   4. write atomically (temp file + replace)
///   5. read the file back and compare it byte-for-byte
/// If any step fails nothing on disk is touched (or the backup is restored).
/// </summary>
public static class SaveIO
{
    public static string AppSupport => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Library", "Application Support", "PkMac");

    public static string BackupRoot => Path.Combine(AppSupport, "Backups");

    public static object Open(Session s, string path, string? entry = null)
    {
        if (!File.Exists(path))
            throw new EngineException("Il file non esiste.");

        if (path.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))
        {
            if (!AzuriiZip.IsAzuriiZip(path))
                throw new EngineException("Questo zip non è un salvataggio o un backup di Azurii.");
            if (entry is null)
            {
                var (kind, saves, _) = AzuriiZip.Inspect(path);
                if (kind == "backup" && saves.Count > 1)
                    return new
                    {
                        needsChoice = true,
                        path,
                        saves = saves.Select(c => new { entry = c.Entry, titleId = c.TitleId, game = c.Game, size = c.Size }).ToArray(),
                    };
            }
            var (zsav, container) = AzuriiZip.Load(path, entry);
            s.Load(zsav, path, container);
            PKHeX.Core.AutoMod.TrainerSettings.Register(zsav);
            try { Backup(path, "apertura", oncePerDay: true); } catch (Exception ex) { Program.Log($"backup failed: {ex.Message}"); }
            return Info(s);
        }

        var len = new FileInfo(path).Length;
        if (len > 64 * 1024 * 1024)
            throw new EngineException("Il file è troppo grande per essere un salvataggio.");
        if (!SaveUtil.TryGetSaveFile(path, out var sav))
            throw new EngineException("Questo file non è un salvataggio Pokémon riconosciuto da PKHeX.");

        s.Load(sav, path);
        PKHeX.Core.AutoMod.TrainerSettings.Register(sav);
        // Safety net: snapshot of the untouched file the first time it is opened each day.
        try { Backup(path, "apertura", oncePerDay: true); } catch (Exception ex) { Program.Log($"backup failed: {ex.Message}"); }
        return Info(s);
    }

    public static object Info(Session s)
    {
        var sav = s.Sav;
        var boxNames = sav.HasBox ? Enumerable.Range(0, sav.BoxCount).Select(s.BoxName).ToArray() : [];
        return new
        {
            path = s.Path,
            fileName = s.Path is null ? null : Path.GetFileName(s.Path),
            container = s.Container?.Describe(),
            game = GameInfo.GetVersionName(sav.Version),
            version = (int)sav.Version,
            versionKey = sav.Version.ToString(),
            generation = sav.Generation,
            context = sav.Context.ToString(),
            ot = sav.OT,
            gender = sav.Gender,
            tid = sav.DisplayTID,
            sid = sav.DisplaySID,
            playTime = $"{sav.PlayedHours}:{sav.PlayedMinutes:00}",
            money = sav.Money,
            hasBox = sav.HasBox,
            hasParty = sav.HasParty,
            boxCount = sav.HasBox ? sav.BoxCount : 0,
            boxSlotCount = sav.HasBox ? sav.BoxSlotCount : 0,
            partyCount = sav.HasParty ? sav.PartyCount : 0,
            boxNames,
            canRenameBoxes = sav is IBoxDetailName,
            checksumValid = sav.ChecksumsValid,
            checksumInfo = sav.ChecksumsValid ? "" : sav.ChecksumInfo,
            dirty = s.Dirty,
            undo = s.UndoLabel,
            redo = s.RedoLabel,
            liveHex = SafeBool(() => RamOffsets.IsLiveHeXSupported(sav)),
            liveHexSwitch = SafeBool(() => RamOffsets.IsSwitchTitle(sav)),
            homeCompatible = sav.Generation >= 8 || sav is SAV7b,
        };
    }

    private static bool SafeBool(Func<bool> f) { try { return f(); } catch { return false; } }

    public static object Checksum(Session s)
    {
        var sav = s.Sav;
        var data = sav.Write().ToArray();
        var ok = SaveUtil.TryGetSaveFile((Memory<byte>)data.ToArray(), out var check, s.Container is null ? s.Path : null);
        return new
        {
            loaded = sav.ChecksumsValid,
            loadedInfo = sav.ChecksumsValid ? "" : sav.ChecksumInfo,
            export = ok && check!.ChecksumsValid,
            exportInfo = ok ? (check!.ChecksumsValid ? "" : check.ChecksumInfo) : "Il file generato non è leggibile.",
        };
    }

    public static object Save(Session s, string? target, bool backup)
    {
        var sav = s.Sav;
        var path = target ?? s.Path ?? throw new EngineException("Nessun percorso di destinazione.");
        var steps = new List<string>();

        // 1. Build final binary.
        byte[] data = sav.Write().ToArray();
        steps.Add($"File generato ({data.Length:N0} byte), checksum ricalcolati");

        // 2. Re-parse and verify.
        if (!SaveUtil.TryGetSaveFile((Memory<byte>)data.ToArray(), out var check, s.Container is null ? path : null))
            throw new EngineException("Verifica fallita: il file generato non viene riconosciuto come salvataggio. Nulla è stato scritto.");
        if (!check.ChecksumsValid)
            throw new EngineException($"Verifica fallita: checksum non validi nel file generato.\n{check.ChecksumInfo}\nNulla è stato scritto.");
        steps.Add("Checksum verificati sul file rigenerato");

        var mismatch = CompareStorage(sav, check);
        if (mismatch is not null)
            throw new EngineException($"Verifica fallita: {mismatch}. Nulla è stato scritto.");
        steps.Add("Contenuto di box e squadra identico");

        // Inside an Azurii zip: rewrite the zip with the new save and an updated manifest.
        if (s.Container is { } zc && (target is null || target.EndsWith(".zip", StringComparison.OrdinalIgnoreCase)))
            return SaveIntoZip(s, zc, path, data, steps, backup);

        // 3. Backup what is on disk now.
        string? backupPath = null;
        if (backup && File.Exists(path))
        {
            backupPath = Backup(path, "prima-del-salvataggio", oncePerDay: false);
            steps.Add("Backup del file precedente creato");
        }

        // 4. Atomic write.
        var dir = Path.GetDirectoryName(Path.GetFullPath(path))!;
        var tmp = Path.Combine(dir, $".{Path.GetFileName(path)}.pkmac-{Guid.NewGuid():N}.tmp");
        File.WriteAllBytes(tmp, data);
        try
        {
            if (File.Exists(path))
                File.Replace(tmp, path, null);
            else
                File.Move(tmp, path);
        }
        catch
        {
            if (File.Exists(tmp)) File.Delete(tmp);
            throw;
        }

        // 5. Read back.
        var written = File.ReadAllBytes(path);
        if (!written.AsSpan().SequenceEqual(data))
        {
            if (backupPath is not null)
                File.Copy(backupPath, path, overwrite: true);
            throw new EngineException("Il file scritto non corrisponde a quello verificato: è stato ripristinato il backup.");
        }
        steps.Add("Rilettura dal disco identica, byte per byte");

        s.Dirty = false;
        return new { path, backup = backupPath, steps, sha256 = Convert.ToHexString(SHA256.HashData(data))[..16] };
    }

    private static object SaveIntoZip(Session s, AzuriiZip.Container c, string path, byte[] data, List<string> steps, bool backup)
    {
        string? backupPath = null;
        if (backup && File.Exists(path))
        {
            backupPath = Backup(path, "prima-del-salvataggio", oncePerDay: false);
            steps.Add("Backup dello zip di Azurii creato");
        }
        var dir = Path.GetDirectoryName(Path.GetFullPath(path))!;
        var tmp = Path.Combine(dir, $".{Path.GetFileName(path)}.pkmac-{Guid.NewGuid():N}.tmp");
        try
        {
            AzuriiZip.Write(c, data, tmp);
            var problem = AzuriiZip.Verify(c, tmp, data);
            if (problem is not null)
                throw new EngineException($"Verifica dello zip fallita: {problem}. Nulla è stato scritto.");
            steps.Add("Zip di Azurii ricostruito: solo il salvataggio e le informazioni sono cambiati");
            if (File.Exists(path)) File.Replace(tmp, path, null);
            else File.Move(tmp, path);
        }
        finally
        {
            if (File.Exists(tmp)) File.Delete(tmp);
        }

        var target = path == c.ZipPath ? c : new AzuriiZip.Container { ZipPath = path, Kind = c.Kind, Entry = c.Entry, TitleId = c.TitleId, Title = c.Title, ManifestName = c.ManifestName };
        var (reloaded, _) = AzuriiZip.Load(path, c.Entry);
        var reData = reloaded.Write().ToArray();
        if (!reloaded.ChecksumsValid)
        {
            if (backupPath is not null) File.Copy(backupPath, path, overwrite: true);
            throw new EngineException("Il salvataggio riletto dallo zip non è valido: è stato ripristinato il backup.");
        }
        steps.Add("Salvataggio riletto dallo zip con checksum validi");
        steps.Add(c.Kind == "backup"
            ? "Pronto da ripristinare in Azurii (Impostazioni › Backup)"
            : "Pronto da reimportare in Azurii (Salvataggi › Importa)");
        s.Load(s.Sav, path, target);
        s.Dirty = false;
        _ = reData;
        return new { path, backup = backupPath, steps, sha256 = Convert.ToHexString(SHA256.HashData(data))[..16] };
    }

    private static string? CompareStorage(SaveFile a, SaveFile b)
    {
        if (a.HasBox != b.HasBox || (a.HasBox && a.BoxCount != b.BoxCount))
            return "numero di box diverso";
        if (a.HasBox)
        {
            for (int i = 0; i < a.BoxCount * a.BoxSlotCount; i++)
            {
                var x = a.GetBoxSlotAtIndex(i);
                var y = b.GetBoxSlotAtIndex(i);
                if (x.Species != y.Species || x.PID != y.PID || x.EncryptionConstant != y.EncryptionConstant)
                    return $"differenza nel box {i / a.BoxSlotCount + 1}, slot {i % a.BoxSlotCount + 1}";
                if (x.Species != 0 && !y.ChecksumValid)
                    return $"checksum del Pokémon non valido nel box {i / a.BoxSlotCount + 1}, slot {i % a.BoxSlotCount + 1}";
            }
        }
        if (a.HasParty)
        {
            if (a.PartyCount != b.PartyCount)
                return "numero di Pokémon in squadra diverso";
            for (int i = 0; i < a.PartyCount; i++)
            {
                var x = a.GetPartySlotAtIndex(i);
                var y = b.GetPartySlotAtIndex(i);
                if (x.Species != y.Species || x.PID != y.PID)
                    return $"differenza in squadra, slot {i + 1}";
            }
        }
        return null;
    }

    // ---------- backups ----------

    public static string BackupFolderFor(string savePath)
    {
        var full = Path.GetFullPath(savePath);
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(full)))[..8];
        var name = string.Concat(Path.GetFileName(full).Select(c => Path.GetInvalidFileNameChars().Contains(c) ? '_' : c));
        return Path.Combine(BackupRoot, $"{name}-{hash}");
    }

    public static string Backup(string savePath, string reason, bool oncePerDay)
    {
        var folder = BackupFolderFor(savePath);
        Directory.CreateDirectory(folder);
        var stamp = DateTime.Now;
        if (oncePerDay && Directory.EnumerateFiles(folder, $"{stamp:yyyyMMdd}-*-{reason}.bak").Any())
            return "";
        var dest = Path.Combine(folder, $"{stamp:yyyyMMdd-HHmmss}-{reason}.bak");
        File.Copy(savePath, dest, overwrite: true);
        // Keep the 40 most recent.
        foreach (var old in Directory.GetFiles(folder, "*.bak").OrderByDescending(f => f).Skip(40))
            File.Delete(old);
        return dest;
    }

    public static object Backups(Session s, string? path)
    {
        var p = path ?? s.Path;
        if (p is null) return Array.Empty<object>();
        var folder = BackupFolderFor(p);
        if (!Directory.Exists(folder)) return Array.Empty<object>();
        return Directory.GetFiles(folder, "*.bak").OrderByDescending(f => f).Select(f =>
        {
            var fi = new FileInfo(f);
            var parts = Path.GetFileNameWithoutExtension(f).Split('-', 3);
            return new { path = f, date = fi.LastWriteTime.ToString("o"), size = fi.Length, reason = parts.Length == 3 ? parts[2].Replace('-', ' ') : "" };
        }).ToArray();
    }

    public static object RestoreBackup(Session s, string backup)
    {
        var target = s.Path ?? throw new EngineException("Nessun salvataggio aperto.");
        if (!File.Exists(backup))
            throw new EngineException("Backup non trovato.");
        if (s.Container is null && !SaveUtil.TryGetSaveFile(backup, out _))
            throw new EngineException("Il backup non è un salvataggio valido.");
        var entry = s.Container?.Entry;
        Backup(target, "prima-del-ripristino", oncePerDay: false);
        File.Copy(backup, target, overwrite: true);
        return Open(s, target, entry);
    }
}
