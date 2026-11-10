using System.Text.Json;
using PKHeX.Core;
using PKHeX.Core.AutoMod;

namespace PkMac.Engine;

/// <summary>
/// Smoke test used by the updater before activating a new PKHeX.Core / engine pack:
/// if any check fails, the app keeps (or rolls back to) the previous version.
/// Usage: PkMacEngine --selftest [optional real save to round-trip]
/// </summary>
public static class SelfTest
{
    public static int Run(string? savePath)
    {
        var checks = new List<object>();
        bool ok = true;
        void Check(string name, Func<string?> test)
        {
            try
            {
                var detail = test();
                checks.Add(new { name, ok = true, detail });
            }
            catch (Exception ex)
            {
                ok = false;
                checks.Add(new { name, ok = false, detail = $"{ex.GetType().Name}: {ex.Message}" });
            }
        }

        Check("strings", () =>
        {
            var it = GameInfo.GetStrings("it");
            if (it.Species[25].Length == 0) throw new Exception("lista specie vuota");
            return it.Species[25];
        });

        foreach (var version in new[] { GameVersion.SL, GameVersion.SW, GameVersion.US, GameVersion.C })
        {
            Check($"checksum-{version}", () =>
            {
                var sav = BlankSaveFile.Get(version);
                var pk = sav.BlankPKM;
                pk.Species = (ushort)Species.Pikachu;
                pk.CurrentLevel = 5;
                pk.RefreshChecksum();
                if (sav.HasBox) sav.SetBoxSlotAtIndex(pk, 0, 0, EntityImportSettings.None);
                var data = sav.Write().ToArray();
                if (data.Length == 0) throw new Exception("file vuoto");
                if (!sav.ChecksumsValid) throw new Exception("checksum non validi: " + sav.ChecksumInfo);
                if (sav.HasBox && sav.GetBoxSlotAtIndex(0, 0).Species != (ushort)Species.Pikachu) throw new Exception("slot non riletto");
                return $"{data.Length} byte";
            });
        }

        Check("alm", () =>
        {
            APILegality.EnableDevMode = true;
            APILegality.Timeout = 30;
            var sav = BlankSaveFile.Get(GameVersion.SL);
            var set = new ShowdownSet("Pikachu @ Light Ball\nAbility: Static\nLevel: 50\nTera Type: Electric\n- Thunderbolt\n- Volt Tackle\n- Iron Tail\n- Quick Attack");
            var res = sav.GetLegalFromSet(new RegenTemplate(set, sav.Generation));
            var la = new LegalityAnalysis(res.Created);
            if (!la.Valid) throw new Exception($"{res.Status}: {la.Report()}");
            return res.Status.ToString();
        });

        if (savePath is not null && File.Exists(savePath))
        {
            Check("save-roundtrip", () =>
            {
                if (!SaveUtil.TryGetSaveFile(savePath, out var sav)) throw new Exception("salvataggio non riconosciuto");
                var data = sav.Write().ToArray();
                if (!SaveUtil.TryGetSaveFile((Memory<byte>)data, out var re) || !re.ChecksumsValid)
                    throw new Exception("checksum non validi dopo la riscrittura");
                return GameInfo.GetVersionName(sav.Version);
            });

            Check("azurii-zip", () =>
            {
                // Builds an Azurii-style save zip around the test save, edits it in place and checks it.
                var dir = Path.Combine(Path.GetTempPath(), "pkmac-selftest-" + Guid.NewGuid().ToString("N")[..8]);
                Directory.CreateDirectory(dir);
                try
                {
                    var zipPath = Path.Combine(dir, "Test [0004000000000000] salvataggio.zip");
                    using (var z = System.IO.Compression.ZipFile.Open(zipPath, System.IO.Compression.ZipArchiveMode.Create))
                    {
                        void Add(string name, byte[] bytes) { using var w = z.CreateEntry(name).Open(); w.Write(bytes); }
                        Add("save/sav.dat", File.ReadAllBytes(savePath));
                        Add("save.metadata", new byte[16]);
                        Add("extdata/00000000", new byte[] { 1, 2, 3 });
                        Add(Features.AzuriiZip.SaveManifest, System.Text.Encoding.UTF8.GetBytes("{\"app\":\"Azurii\",\"format\":1,\"titleId\":\"0004000000000000\",\"title\":\"Test\",\"created\":\"2026-01-01T00:00:00Z\",\"saveDate\":\"2026-01-01T00:00:00Z\"}"));
                    }
                    var (sav, c) = Features.AzuriiZip.Load(zipPath, null);
                    sav.Money = (uint)Math.Min(sav.MaxMoney, 123456);
                    var data = sav.Write().ToArray();
                    var outPath = Path.Combine(dir, "out.zip");
                    Features.AzuriiZip.Write(c, data, outPath);
                    var problem = Features.AzuriiZip.Verify(c, outPath, data);
                    if (problem is not null) throw new Exception(problem);
                    var (re, _) = Features.AzuriiZip.Load(outPath, null);
                    if (re.Money != sav.Money || !re.ChecksumsValid) throw new Exception("modifica non riletta");
                    using var check = System.IO.Compression.ZipFile.OpenRead(outPath);
                    using var mr = new StreamReader(check.GetEntry(Features.AzuriiZip.SaveManifest)!.Open());
                    var manifest = mr.ReadToEnd();
                    if (!manifest.Contains("editedWith") || manifest.Contains("2026-01-01T00:00:00Z\",\n  \"saveDate\": \"2026-01-01"))
                        throw new Exception("manifest non aggiornato");
                    return "zip riscritto e verificato";
                }
                finally { try { Directory.Delete(dir, true); } catch { } }
            });
        }

        Console.WriteLine(JsonSerializer.Serialize(new { ok, versions = Versions.Get(), checks }, Program.Json));
        return ok ? 0 : 1;
    }
}
