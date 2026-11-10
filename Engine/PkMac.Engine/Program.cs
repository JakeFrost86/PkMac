using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using PKHeX.Core;

namespace PkMac.Engine;

/// <summary>
/// PkMac engine: a headless process that hosts PKHeX.Core and the integrated plugins.
/// The macOS app talks to it with one JSON object per line on stdin/stdout.
///   request : {"id":1,"method":"open","params":{...}}
///   response: {"id":1,"result":...}  or  {"id":1,"error":"message"}
///   event   : {"event":"progress","data":{...}}   (unsolicited)
/// Anything written to stderr is a log line.
/// </summary>
public static class Program
{
    public static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull,
        WriteIndented = false,
    };

    private static readonly object WriteLock = new();
    private static Stream _stdout = Stream.Null;

    public static async Task<int> Main(string[] args)
    {
        Console.OutputEncoding = Encoding.UTF8;
        Console.InputEncoding = Encoding.UTF8;
        Init();

        if (args.Contains("--version"))
        {
            Console.WriteLine(JsonSerializer.Serialize(Versions.Get(), Json));
            return 0;
        }

        if (args.Length > 0 && args[0] == "--featuretest")
            return FeatureTest.Run(args.Skip(1).FirstOrDefault());
        if (args.Length > 0 && args[0] == "--selftest")
            return SelfTest.Run(args.Skip(1).FirstOrDefault());

        _stdout = Console.OpenStandardOutput();
        var dispatcher = new Dispatcher();
        using var reader = new StreamReader(Console.OpenStandardInput(), Encoding.UTF8);
        Log($"PkMac engine {Versions.Engine} · PKHeX.Core {Versions.Core}");

        string? line;
        while ((line = await reader.ReadLineAsync().ConfigureAwait(false)) != null)
        {
            if (string.IsNullOrWhiteSpace(line))
                continue;
            JsonNode? id = null;
            try
            {
                var req = JsonNode.Parse(line)!.AsObject();
                id = req["id"]?.DeepClone();
                var method = req["method"]?.GetValue<string>() ?? throw new EngineException(Tr.T($"Richiesta senza metodo."));
                var p = req["params"] as JsonObject ?? new JsonObject();
                if (method == "quit")
                {
                    Send(new JsonObject { ["id"] = id, ["result"] = true });
                    break;
                }
                // Long operations run off the reader thread so the UI can keep asking for progress.
                var capturedId = id;
                _ = Task.Run(() => Handle(dispatcher, capturedId, method, p));
            }
            catch (Exception ex)
            {
                SendError(id, ex);
            }
        }
        return 0;
    }

    private static bool _initialized;

    /// <summary>One-time engine settings, shared by the macOS process and the iOS library.</summary>
    public static void Init()
    {
        if (_initialized) return;
        _initialized = true;
        // The HOME tracker is written only by Pokémon HOME: when it's missing we warn, we never invent one.
        ParseSettings.Settings.HOMETransfer.HOMETransferTrackerNotPresent = Severity.Fishy;
    }

    /// <summary>Result → JSON. In the ahead-of-time (iOS) build, without run-time generated serializers.</summary>
    public static JsonNode? ToNode(object? result)
    {
#if PKMAC_NATIVE
        return JsonOut.ToNode(result);
#else
        return result as JsonNode ?? JsonSerializer.SerializeToNode(result, Json);
#endif
    }

    private static void Handle(Dispatcher dispatcher, JsonNode? id, string method, JsonObject p)
        => Send(Respond(dispatcher, id, method, p));

    private static JsonObject Respond(Dispatcher dispatcher, JsonNode? id, string method, JsonObject p)
    {
        try
        {
            var result = dispatcher.Invoke(method, new Params(p));
            return new JsonObject { ["id"] = id, ["result"] = ToNode(result) };
        }
        catch (Exception ex)
        {
            return ErrorObject(id, ex);
        }
    }

    private static void SendError(JsonNode? id, Exception ex) => Send(ErrorObject(id, ex));

    private static JsonObject ErrorObject(JsonNode? id, Exception ex)
    {
        var inner = ex is TargetInvocationException { InnerException: { } ie } ? ie : ex;
        Log($"error: {inner}");
        var message = inner is EngineException ? inner.Message : $"{inner.GetType().Name}: {inner.Message}";
        return new JsonObject { ["id"] = id?.DeepClone(), ["error"] = message };
    }

    // ---------- in-process mode (iOS): no stdin/stdout, the app calls Call() and receives events ----------

    /// <summary>When set, events go here (one JSON object per call) instead of stdout.</summary>
    public static Action<string>? EventSink { get; set; }

    private static Dispatcher? _library;
    private static readonly object LibraryLock = new();

    /// <summary>Runs one request line ({"id","method","params"}) and returns the response line.</summary>
    public static string Call(string line)
    {
        Init();
        lock (LibraryLock) _library ??= new Dispatcher();
        JsonNode? id = null;
        try
        {
            var req = JsonNode.Parse(line)!.AsObject();
            id = req["id"]?.DeepClone();
            var method = req["method"]?.GetValue<string>() ?? throw new EngineException(Tr.T($"Richiesta senza metodo."));
            var p = req["params"] as JsonObject ?? new JsonObject();
            return Respond(_library, id, method, p).ToJsonString(Json);
        }
        catch (Exception ex)
        {
            return ErrorObject(id, ex).ToJsonString(Json);
        }
    }

    public static void Event(string name, object data)
    {
        var obj = new JsonObject { ["event"] = name, ["data"] = ToNode(data) };
        if (EventSink is { } sink) sink(obj.ToJsonString(Json));
        else Send(obj);
    }

    private static void Send(JsonObject obj)
    {
        var bytes = Encoding.UTF8.GetBytes(obj.ToJsonString(Json) + "\n");
        lock (WriteLock)
        {
            _stdout.Write(bytes);
            _stdout.Flush();
        }
    }

    public static void Log(string message) => Console.Error.WriteLine($"[engine] {message}");
}

/// <summary>An error whose message is meant for the user, already localized.</summary>
public sealed class EngineException(string message) : Exception(message);

public static class Versions
{
    public static string Engine => typeof(Program).Assembly.GetName().Version?.ToString(3) ?? "0.0.0";
    public static string Core => Short(typeof(SaveFile).Assembly);
    public static string Alm => Short(typeof(PKHeX.Core.AutoMod.Legalizer).Assembly);

    private static string Short(Assembly a)
    {
        var v = a.GetName().Version;
        return v is null ? "?" : $"{v.Major}.{v.Minor:00}.{v.Build:00}";
    }

    public static object Get() => new { engine = Engine, core = Core, alm = Alm };
}
