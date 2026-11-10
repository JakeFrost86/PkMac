using System.Runtime.InteropServices;

namespace PkMac.Engine;

/// <summary>
/// C entry points of the iOS engine library. Requests and responses are the same UTF-8 JSON lines the
/// macOS engine reads from stdin and writes to stdout.
/// </summary>
public static unsafe class NativeExports
{
    private static delegate* unmanaged<byte*, void> _events;

    /// <summary>Runs one request synchronously; the returned string must be released with pkmac_free.</summary>
    [UnmanagedCallersOnly(EntryPoint = "pkmac_call")]
    public static byte* Call(byte* request)
    {
        string response;
        try
        {
            var line = Marshal.PtrToStringUTF8((nint)request) ?? "{}";
            response = Program.Call(line);
        }
        catch (Exception e)
        {
            response = $"{{\"error\":{System.Text.Json.JsonSerializer.Serialize(e.Message, EngineJson.Default.String)}}}";
        }
        return (byte*)Marshal.StringToCoTaskMemUTF8(response);
    }

    [UnmanagedCallersOnly(EntryPoint = "pkmac_free")]
    public static void Free(byte* pointer)
    {
        if (pointer != null)
            Marshal.FreeCoTaskMem((nint)pointer);
    }

    /// <summary>Registers the function that receives events (progress…); the string is valid only during the call.</summary>
    [UnmanagedCallersOnly(EntryPoint = "pkmac_set_event_callback")]
    public static void SetEventCallback(delegate* unmanaged<byte*, void> callback)
    {
        _events = callback;
        Program.EventSink = callback == null ? null : json =>
        {
            var p = Marshal.StringToCoTaskMemUTF8(json);
            try { _events((byte*)p); }
            finally { Marshal.FreeCoTaskMem(p); }
        };
    }
}

[System.Text.Json.Serialization.JsonSerializable(typeof(string))]
internal sealed partial class EngineJson : System.Text.Json.Serialization.JsonSerializerContext;
