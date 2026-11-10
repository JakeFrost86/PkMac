using System.Text.Json;
using System.Text.Json.Nodes;
using PKHeX.Core;
using PkMac.Engine.Features;

namespace PkMac.Engine;

/// <summary>
/// Headless test of every editor on blank saves of all supported games (and an optional real save):
/// bag, events, Pokédex, gifts, blocks, inspector, trainer, ribbons and cross-save transfers.
/// Every save must still write with valid checksums afterwards.
/// Usage: PkMacEngine --featuretest [save]
/// </summary>
public static class FeatureTest
{
    private static readonly JsonSerializerOptions J = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    private static JsonNode ToNode(object o) => JsonSerializer.SerializeToNode(o, o.GetType(), J)!;

    public static int Run(string? savePath)
    {
        var results = new List<string>();
        int failures = 0;
        void T(string game, string name, Func<string?> f)
        {
            try { var d = f(); results.Add($"  ✅ {game,-6} {name,-10} {d}"); }
            catch (Exception e) { failures++; results.Add($"  ❌ {game,-6} {name,-10} {e.GetType().Name}: {e.Message.Split('\n')[0]}"); }
        }

        var versions = new[]
        {
            GameVersion.RD, GameVersion.C, GameVersion.E, GameVersion.FR, GameVersion.Pt, GameVersion.HG, GameVersion.B2,
            GameVersion.OR, GameVersion.US, GameVersion.GP, GameVersion.SW, GameVersion.BD, GameVersion.PLA, GameVersion.SL, GameVersion.ZA,
        };

        var sessions = new List<(string name, Session s)>();
        foreach (var v in versions)
        {
            SaveFile sav;
            try { sav = BlankSaveFile.Get(v); }
            catch (Exception e) { results.Add($"  ⚪️ {v,-6} blank non disponibile: {e.Message}"); continue; }
            var s = new Session();
            s.SetLanguage("it");
            s.Load(sav, $"/tmp/{v}.sav");
            sessions.Add((v.ToString(), s));
        }
        if (savePath is not null && File.Exists(savePath) && SaveUtil.TryGetSaveFile(savePath, out var real))
        {
            var s = new Session();
            s.SetLanguage("it");
            s.Load(real, savePath);
            sessions.Add(("real", s));
        }

        foreach (var (g, s) in sessions)
        {
            var sav = s.Sav;
            T(g, "trainer", () =>
            {
                var t = ToNode(TrainerInfo.Get(s));
                var p = new Params(new JsonObject { ["ot"] = "Test", ["hours"] = 12, ["minutes"] = 34, ["seconds"] = 56, ["money"] = 1234, ["tid"] = 12345 });
                TrainerInfo.Set(s, p);
                if (sav.OT != "Test" || sav.PlayedHours != 12 || sav.DisplayTID != 12345) throw new Exception("valori non applicati");
                return $"fmt {t["idFormat"]} badges {(t["badges"] is null ? "-" : t["badges"]!["count"]!.ToString())}";
            });
            T(g, "bag", () =>
            {
                var b = ToNode(Bag.Get(s));
                var pouches = b["pouches"]!.AsArray();
                if (pouches.Count == 0) return "nessuna borsa";
                Bag.Action(s, 0, "giveAll", -1);
                var after = ToNode(Bag.Get(s))["pouches"]![0]!["items"]!.AsArray();
                var set = new JsonObject { ["pouches"] = new JsonArray(new JsonObject { ["index"] = 0, ["items"] = new JsonArray(after.Take(3).Select(i => (JsonNode)new JsonObject { ["id"] = i!["id"]!.GetValue<int>(), ["count"] = 1 }).ToArray()) }) };
                Bag.Set(s, new Params(set));
                var final = ToNode(Bag.Get(s))["pouches"]![0]!["items"]!.AsArray().Count;
                var key = after.FirstOrDefault()?["key"]?.ToString();
                return $"{pouches.Count} tasche, giveAll {after.Count} → set {final} ({key})";
            });
            T(g, "events", () =>
            {
                var e = ToNode(Events.Get(s));
                if (e["supported"]!.GetValue<bool>() == false) return e["useBlocks"]?.GetValue<bool>() == true ? "via blocchi" : "n/d";
                var named = e["namedFlags"]!.AsArray().Count;
                Events.Set(s, new Params(new JsonObject { ["flags"] = new JsonArray(new JsonArray(1, true)), ["work"] = new JsonArray(new JsonArray(0, 1)) }));
                var again = ToNode(Events.Get(s));
                if (!again["flags"]![1]!.GetValue<bool>()) throw new Exception("flag non scritto");
                return $"{e["flagCount"]} flag ({named} con nome), {e["workCount"]} valori, {e["systemCount"]} sistema";
            });
            T(g, "dex", () =>
            {
                var d = ToNode(Pokedex.Get(s));
                if (!d["supported"]!.GetValue<bool>()) return "n/d";
                var r = ToNode(Pokedex.Set(s, new Params(new JsonObject { ["action"] = "caughtAll" })));
                return $"{r["caught"]}/{r["total"]} catturati";
            });
            T(g, "gifts", () =>
            {
                var a = ToNode(Gifts.Album(s));
                var db = ToNode(Gifts.Database(s, null, 5000));
                var items = db["items"]!.AsArray();
                string extra = "";
                var album = items.FirstOrDefault(i => i!["canAlbum"]?.GetValue<bool>() == true);
                if (album is not null)
                {
                    var res = ToNode(Gifts.PutInAlbum(s, album["id"]!.GetValue<int>(), -1));
                    var filled = res["cards"]!.AsArray().Count(c => c!["card"]!["empty"]!.GetValue<bool>() == false);
                    if (filled == 0) throw new Exception("carta non inserita");
                    Gifts.Delete(s, 0);
                    extra += $" album ok ({album["type"]})";
                }
                var mon = items.FirstOrDefault(i => i!["canReceive"]?.GetValue<bool>() == true);
                if (mon is not null && sav.HasBox)
                {
                    Gifts.Receive(s, mon["id"]!.GetValue<int>(), new SlotRef(false, 0, 5));
                    var pk = sav.GetBoxSlotAtIndex(0, 5);
                    extra += $" ricevuto {GameInfo.Strings.Species[pk.Species]} legale={new LegalityAnalysis(pk).Valid}";
                }
                return $"album {(a["supported"]!.GetValue<bool>() ? a["capacity"] : "-")}, db {db["total"]}" + extra;
            });
            T(g, "blocks", () =>
            {
                var b = ToNode(Blocks.List(s, null, true));
                if (!b["supported"]!.GetValue<bool>()) return "n/d";
                var list = b["blocks"]!.AsArray();
                var named = list.Count(x => x!["named"]!.GetValue<bool>());
                var obj = list.FirstOrDefault(x => x!["hasObject"]!.GetValue<bool>());
                if (obj is not null) Inspector.Inspect(s, new Params(new JsonObject { ["target"] = "block", ["key"] = obj["key"]!.ToString() }));
                var boolBlock = list.FirstOrDefault(x => x!["type"]!.ToString() == "Bool");
                if (boolBlock is not null) Blocks.Set(s, boolBlock["key"]!.ToString(), JsonValue.Create(true));
                return $"{list.Count} blocchi ({named} con nome)";
            });
            T(g, "inspect", () =>
            {
                var i = ToNode(Inspector.Inspect(s, new Params(new JsonObject { ["target"] = "save" })));
                var props = i["props"]!.AsArray();
                var child = props.FirstOrDefault(p => p!["kind"]!.ToString() == "object");
                int sub = 0;
                if (child is not null)
                    sub = ToNode(Inspector.Inspect(s, new Params(new JsonObject { ["target"] = "save", ["path"] = new JsonArray(child["name"]!.ToString()) })))["props"]!.AsArray().Count;
                return $"{props.Count} campi, sezione {child?["name"]} {sub}";
            });
            if (sav.HasBox)
            {
                T(g, "ribbons", () =>
                {
                    var pk = sav.BlankPKM;
                    pk.Species = (ushort)Species.Pikachu; pk.CurrentLevel = 10; pk.Language = 2;
                    pk.RefreshChecksum();
                    sav.SetBoxSlotAtIndex(pk, 0, 0, EntityImportSettings.None);
                    var r = ToNode(Storage.Ribbons(s, new SlotRef(false, 0, 0)));
                    var list = r["ribbons"]!.AsArray();
                    if (list.Count == 0) return "nessun fiocco";
                    var first = list[0]!["prop"]!.ToString();
                    Storage.SetRibbons(s, new SlotRef(false, 0, 0), new Params(new JsonObject { ["set"] = new JsonArray(new JsonObject { ["prop"] = first, ["value"] = 1 }) }));
                    var pkm = Inspector.Inspect(s, new Params(new JsonObject { ["target"] = "pkm", ["ref"] = new JsonObject { ["kind"] = "box", ["box"] = 0, ["slot"] = 0 } }));
                    return $"{list.Count} fiocchi ({list[0]!["name"]})";
                });
            }
            T(g, "write", () =>
            {
                var data = sav.Write().ToArray();
                if (!sav.ChecksumsValid) throw new Exception("checksum: " + sav.ChecksumInfo);
                if (!SaveUtil.TryGetSaveFile((Memory<byte>)data, out var re)) throw new Exception("non riletto");
                if (re.OT != sav.OT) throw new Exception("OT diverso dopo rilettura");
                return $"{data.Length} byte, checksum ok";
            });
        }

        // Cross-save transfers.
        Session? Find(string n) => sessions.FirstOrDefault(x => x.name == n).s;
        foreach (var (a, b, species) in new[] { ("SW", "SL", Species.Pikachu), ("E", "Pt", Species.Pikachu), ("SL", "FR", Species.Pikachu), ("RD", "C", Species.Pikachu), ("SW", "BD", Species.Zacian), ("US", "SW", Species.Pikachu) })
        {
            var from = Find(a); var to = Find(b);
            if (from is null || to is null) continue;
            T($"{a}→{b}", "transfer", () =>
            {
                var probe = EntityBlank.GetBlank(from.Sav);
                probe.Species = (ushort)species;
                var enc = EncounterMovesetGenerator.GenerateEncounters(probe, from.Sav, ReadOnlyMemory<ushort>.Empty, from.Sav.Version).FirstOrDefault();
                PKM pk;
                if (enc is not null) pk = enc.ConvertToPKM(from.Sav);
                else
                {
                    var blank = from.Sav.BlankPKM;
                    blank.Species = (ushort)species; blank.CurrentLevel = 50; blank.Language = 2; blank.RefreshChecksum();
                    pk = blank;
                }
                from.Sav.SetBoxSlotAtIndex(pk, 0, 10, EntityImportSettings.None);
                var check = ToNode(Transfer.Check(from, new SlotRef(false, 0, 10), to));
                if (check["ok"]!.GetValue<bool>())
                {
                    Transfer.Move(from, new SlotRef(false, 0, 10), to, new SlotRef(false, 0, 11), copy: true);
                    var landed = to.Sav.GetBoxSlotAtIndex(0, 11);
                    return $"ok → {landed.GetType().Name} legale={new LegalityAnalysis(landed).Valid}";
                }
                return "rifiutato: " + check["problem"]!.ToString().Split('\n')[0];
            });
        }

        foreach (var r in results) Console.WriteLine(r);
        Console.WriteLine(failures == 0 ? "FEATURETEST OK" : $"FEATURETEST: {failures} errori");
        return failures == 0 ? 0 : 1;
    }
}
