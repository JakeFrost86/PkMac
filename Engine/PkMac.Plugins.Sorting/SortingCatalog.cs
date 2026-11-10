using PKHeX.Core;

namespace PluginPile.Sorting;

/// <summary>
/// One sorting option offered for the loaded save.
/// </summary>
public sealed record SortOption(string Id, string Name, string Group, Func<PKM, IComparable>[]? Functions);

/// <summary>
/// PkMac facade over PluginPile's regional Pokédex tables: mirrors the menu logic of the
/// original SortingPlugin (credit: foohyfooh) and exposes it without WinForms.
/// </summary>
public static class SortingCatalog
{
    public static IReadOnlyList<SortOption> GetOptions(SaveFile sav, bool includeAreas)
    {
        var list = new List<SortOption>();
        void Add(string id, string name, Func<PKM, IComparable>[] f, string group = "Regionali") => list.Add(new(id, name, group, f));

        byte gen = sav.Generation;
        var version = sav.Version;
        bool isLetsGo = version is GameVersion.GP or GameVersion.GE;
        bool isBDSP = version is GameVersion.BD or GameVersion.SP;
        bool isScVi = version is GameVersion.SL or GameVersion.VL;
        bool isPLA = version == GameVersion.PLA;
        bool isSwSh = version is GameVersion.SW or GameVersion.SH;

        if (isLetsGo)
        {
            Add("gen7kanto", "Kanto (Let's Go)", Gen7Kanto.GetSortFunctions());
        }
        else
        {
            if (gen >= 1) Add("gen1kanto", "Kanto", Gen1Kanto.GetSortFunctions());
            if (gen >= 2) Add("gen2johto", "Johto", Gen2Johto.GetSortFunctions());
            if (gen >= 3)
            {
                Add("gen3hoenn", "Hoenn", Gen3Hoenn.GetSortFunctions());
                Add("gen3kanto", "Kanto (RFVF)", Gen3Kanto.GetSortFunctions());
            }
            if (gen >= 4)
            {
                Add("gen4dp", "Sinnoh (Diamante/Perla)", Gen4Sinnoh.GetDPSortFunctions());
                Add("gen4pt", "Sinnoh (Platino)", Gen4Sinnoh.GetPtSortFunctions());
                Add("gen4johto", "Johto (HGSS)", Gen4Johto.GetSortFunctions());
            }
            if (gen >= 5 && !isBDSP)
            {
                Add("gen5bw", "Unima (Nero/Bianco)", Gen5Unova.GetBWSortFunctions());
                Add("gen5b2w2", "Unima (Nero 2/Bianco 2)", Gen5Unova.GetB2W2SortFunctions());
            }
            if (gen >= 6 && !isBDSP)
            {
                if (includeAreas)
                {
                    Add("gen6central", "Kalos Centrale", Gen6Kalos.GetCentralDexSortFunctions(), "Aree");
                    Add("gen6coastal", "Kalos Costiera", Gen6Kalos.GetCostalDexSortFunctions(), "Aree");
                    Add("gen6mountain", "Kalos Montana", Gen6Kalos.GetMountainDexSortFunctions(), "Aree");
                }
                Add("gen6kalos", "Kalos", Gen6Kalos.GetSortFunctions());
                Add("gen6hoenn", "Hoenn (ROZA)", Gen6Hoenn.GetSortFunctions());
            }
            if (gen >= 7 && !isBDSP && !isPLA)
            {
                if (includeAreas)
                {
                    Add("sm1", "Mele Mele (SL)", Gen7Alola.GetSMMelemeleSortFunctions(), "Aree");
                    Add("sm2", "Akala (SL)", Gen7Alola.GetSMAkalaSortFunctions(), "Aree");
                    Add("sm3", "Ula Ula (SL)", Gen7Alola.GetSMUlaulaSortFunctions(), "Aree");
                    Add("sm4", "Poni (SL)", Gen7Alola.GetSMPoniSortFunctions(), "Aree");
                }
                Add("gen7sm", "Alola (Sole/Luna)", Gen7Alola.GetSMSortFunctions());
                if (includeAreas)
                {
                    Add("usum1", "Mele Mele (USUL)", Gen7Alola.GetUSUMMelemeleSortFunctions(), "Aree");
                    Add("usum2", "Akala (USUL)", Gen7Alola.GetUSUMAkalaSortFunctions(), "Aree");
                    Add("usum3", "Ula Ula (USUL)", Gen7Alola.GetUSUMUlaulaSortFunctions(), "Aree");
                    Add("usum4", "Poni (USUL)", Gen7Alola.GetUSUMPoniSortFunctions(), "Aree");
                }
                Add("gen7usum", "Alola (Ultrasole/Ultraluna)", Gen7Alola.GetUSUMSortFunctions());
            }
            if (gen >= 8)
            {
                if (!isBDSP && !isPLA)
                {
                    if (!isScVi) Add("gen7kanto", "Kanto (Let's Go)", Gen7Kanto.GetSortFunctions());
                    if (includeAreas)
                    {
                        Add("galar", "Galar", Gen8Galar.GetGalarDexSortFunctions(), "Aree");
                        Add("ioa", "Isola dell'Armatura", Gen8Galar.GetIoADexSortFunctions(), "Aree");
                        Add("ct", "Landa Corona", Gen8Galar.GetCTDexSortFunction(), "Aree");
                    }
                    Add("gen8galar", "Galar (completo)", Gen8Galar.GetFullGalarDexSortFunctions());
                }
                if (!isSwSh)
                {
                    Add("gen8sinnoh", "Sinnoh (DSLS)", Gen8Sinnoh.GetSortFunctions());
                    if (!isBDSP)
                    {
                        if (includeAreas)
                        {
                            Add("hisui1", "Landa Ossidiana", Gen8Hisui.GetObsidianFieldlandsSortFunctions(), "Aree");
                            Add("hisui2", "Palude Cremisi", Gen8Hisui.GetCrimsonMirelandsSortFunctions(), "Aree");
                            Add("hisui3", "Costa Cobalto", Gen8Hisui.GetCobaltCoastlandsSortFunctions(), "Aree");
                            Add("hisui4", "Altopiano Corona", Gen8Hisui.GetCoronetHighlandsSortFunctions(), "Aree");
                            Add("hisui5", "Monti Biancocielo", Gen8Hisui.GetAlabasterIcelandsSortFunctions(), "Aree");
                        }
                        Add("gen8hisui", "Hisui", Gen8Hisui.GetSortFunctions());
                    }
                }
            }
            if (gen >= 9)
            {
                if (includeAreas)
                {
                    Add("paldea", "Paldea", Gen9Paldea.GetPaldeaSortFunctions(), "Aree");
                    Add("kitakami", "Nordivia", Gen9Paldea.GetKitakamiSortFunctions(), "Aree");
                    Add("blueberry", "Accademia Mirtilla", Gen9Paldea.GetBlueberryAcademySortFunctions(), "Aree");
                }
                Add("gen9paldea", "Paldea (completo)", Gen9Paldea.GetSortFunctions());
                if (!isScVi)
                {
                    if (includeAreas)
                    {
                        Add("lumiose", "Luminopoli", Gen9Kalos.GetLumioseDexSortFunctions(), "Aree");
                        Add("hyperspace", "Luminopoli Iperspazio", Gen9Kalos.GetHyperspaceDexSortFunctions(), "Aree");
                    }
                    Add("gen9kalos", "Kalos (Z-A)", Gen9Kalos.GetSortFunctions());
                }
            }
            if (gen != 1)
            {
                list.Add(new("national", "Nazionale", "Nazionale", null));
                if (gen >= 7 && !isBDSP)
                    Add("nationalforms", "Nazionale + forme regionali", GenNational.GetNationalDexWithRegionalFormsSortFunctions(), "Nazionale");
            }
        }
        return list;
    }

    /// <summary>Applies a sort option to the boxes [begin, end] (0-based; end -1 = last box).</summary>
    public static int Apply(SaveFile sav, SortOption option, int begin, int end, bool checkForms, PluginSettings.SortOptions[] extra)
    {
        PluginSettings.Default.CheckForms = checkForms;
        PluginSettings.Default.AdditionalSortOptions = extra;
        // The sort functions read settings when generated, so regenerate for this call.
        var fresh = GetOptions(sav, includeAreas: true).FirstOrDefault(o => o.Id == option.Id) ?? option;
        if (fresh.Functions is { } f)
            return sav.SortBoxes(begin, end, (pkms, _) => pkms.OrderByCustom(f));
        return sav.SortBoxes(begin, end);
    }
}
