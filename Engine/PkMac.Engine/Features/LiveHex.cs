using PKHeX.Core;
using PKHeX.Core.Injection;

namespace PkMac.Engine.Features;

/// <summary>
/// LiveHeX (santacrab2/PKHeX-Plugins): read/write the boxes of a running game over the network.
/// Switch: sys-botbase (Wi-Fi, port 6000). 3DS: NTR (port 8000).
/// Connection/validation logic ported from LiveHexUI.Connect_Switch / Connect_NTR.
/// </summary>
public sealed class LiveHex(Session s)
{
    private PokeSysBotMini? _bot;
    private string _game = "";
    private string _gameVersion = "";

    public bool Connected => _bot?.Connected == true;

    public object Status() => new
    {
        connected = Connected,
        game = _game,
        gameVersion = _gameVersion,
        version = _bot?.Version.ToString(),
    };

    public object Connect(string ip, int port)
    {
        var sav = s.Sav;
        if (!RamOffsets.IsLiveHeXSupported(sav))
            throw new EngineException("LiveHeX non supporta questo gioco.");
        Disconnect();

        var com = RamOffsets.GetCommunicator(sav, InjectorCommunicationType.SocketNetwork);
        com.IP = ip;
        com.Port = port;
        try { com.Connect(); }
        catch (Exception ex) { throw new EngineException($"Connessione a {ip}:{port} non riuscita: {ex.Message}"); }

        var versions = RamOffsets.GetValidVersions(sav);
        try
        {
            if (com is ICommunicatorNX nx)
                ConnectSwitch(sav, nx, versions);
            else
                ConnectNtr(sav, com, versions);
        }
        catch
        {
            try { com.Disconnect(); } catch { }
            _bot = null;
            throw;
        }
        return Status();
    }

    private void ConnectSwitch(SaveFile sav, ICommunicatorNX nx, LiveHeXVersion[] versions)
    {
        var botbaseVer = nx.GetBotbaseVersion();
        var version = Version.TryParse(botbaseVer, out var v) ? v : null;
        if (version is null || version < InjectionBase.BotbaseVersion)
            throw new EngineException($"sys-botbase non compatibile: serve la versione {InjectionBase.BotbaseVersion} o successiva (trovata {botbaseVer.Trim()}).");

        var titleID = nx.GetTitleID();
        _game = nx.GetGameInfo("name").Trim();
        _gameVersion = nx.GetGameInfo("version").Trim();

        if (!InjectionBase.SaveCompatibleWithTitle(sav, titleID))
            throw new EngineException($"Gioco in esecuzione: {_game} ({_gameVersion}).\nSalvataggio aperto: Pokémon {GameInfo.GetVersionName(sav.Version)}.\nApri in PkMac un salvataggio dello stesso gioco.");

        var lv = InjectionBase.GetVersionFromTitle(titleID, _gameVersion);
        if (lv == LiveHeXVersion.Unknown)
            throw new EngineException($"Versione {_gameVersion} di {_game} non supportata (supportate: da {versions[^1]} a {versions[0]}).");

        _bot = new PokeSysBotMini(lv, nx);
        var data = _bot.ReadSlot(0, 0).ToArray();
        if (lv >= LiveHeXVersion.ZA_v101 && lv <= LiveHeXVersion.ZA_v202)
            data = data[..344];
        if (!LooksValid(sav, data))
            throw new EngineException("I dati letti non sono validi: la RAM potrebbe essere spostata. Riavvia il gioco e riprova.");
    }

    private void ConnectNtr(SaveFile sav, ICommunicator com, LiveHeXVersion[] versions)
    {
        foreach (var version in versions)
        {
            var bot = new PokeSysBotMini(version, com);
            var data = bot.ReadSlot(0, 0).ToArray();
            if (LooksValid(sav, data))
            {
                _bot = bot;
                _game = GameInfo.GetVersionName(sav.Version);
                _gameVersion = version.ToString();
                return;
            }
        }
        throw new EngineException($"Nessuna versione compatibile trovata via NTR per Pokémon {GameInfo.GetVersionName(sav.Version)}.");
    }

    private static bool LooksValid(SaveFile sav, byte[] data)
    {
        if (data.Length < sav.SIZE_STORED)
        {
            var padded = new byte[sav.SIZE_BOXSLOT];
            data.CopyTo(padded, 0);
            data = padded;
        }
        var pkm = sav.GetDecryptedPKM(data);
        return pkm.Species <= pkm.MaxSpeciesID && pkm.ChecksumValid &&
               pkm is { Species: 0, EncryptionConstant: 0 } or { Species: not 0, Language: not (int)LanguageID.None and not (int)LanguageID.UNUSED_6 };
    }

    public object Disconnect()
    {
        try { if (_bot?.Connected == true) _bot.com.Disconnect(); } catch { }
        _bot = null;
        return true;
    }

    private PokeSysBotMini Bot => _bot is { Connected: true } b ? b : throw new EngineException("LiveHeX non è connesso.");

    public object ReadBox(int box)
    {
        var sav = s.Sav;
        var bot = Bot;
        var len = sav.BoxSlotCount * (RamOffsets.GetSlotSize(bot.Version) + RamOffsets.GetGapSize(bot.Version));
        var data = bot.ReadBox(box, len);
        if (data.Length == 0)
            throw new EngineException("Il gioco non ha restituito dati per questo box.");
        s.Snapshot($"LiveHeX: leggi box {box + 1}");
        sav.SetBoxBinary(data, box);
        s.Dirty = true;
        return Storage.Box(s, box);
    }

    public object WriteBox(int box)
    {
        var bot = Bot;
        var data = s.Sav.GetBoxBinary(box);
        bot.SendBox(data, box);
        return true;
    }
}
