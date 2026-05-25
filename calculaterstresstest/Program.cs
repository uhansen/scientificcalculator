using System.Collections.Concurrent;
using System.Diagnostics;

// ---------------------------------------------------------------------------
// CLI argument parsing
// ---------------------------------------------------------------------------
string url         = GetArg("--url",         "http://localhost:3000");
int    concurrency = int.Parse(GetArg("--concurrency", "10"));
int    durationSec = int.Parse(GetArg("--duration",    "30"));
int    rampSec     = int.Parse(GetArg("--ramp",        "5"));

string GetArg(string name, string def)
{
    int i = Array.IndexOf(args, name);
    return i >= 0 && i + 1 < args.Length ? args[i + 1] : def;
}

// ---------------------------------------------------------------------------
// Expressions to cycle through — covers all calculator operations
// ---------------------------------------------------------------------------
string[] expressions =
[
    "add(2,3)",       "subtract(10,4)", "multiply(6,7)",  "divide(9,3)",
    "add(100,200)",   "multiply(3,3)",  "subtract(50,8)", "divide(100,4)",
    "sin(30)",        "cos(60)",        "tan(45)",        "arctan(1)",
    "sin(90)",        "cos(0)",         "tan(0)",         "arctan(0)",
    "mod(10,3)",      "div(10,3)",      "mod(7,2)",       "div(15,4)",
    "e()",            "ln(2.71828)",    "ln(1)",          "ln(10)",
    "sum(1,2,3,4,5)", "avg(1,2,3,4,5)","sum(10,20,30)",  "avg(2,4,6,8)",
];

// ---------------------------------------------------------------------------
// Shared state (lock-free counters)
// ---------------------------------------------------------------------------
long totalRequests = 0;
long totalSuccess  = 0;
long totalErrors   = 0;
var  latencies     = new ConcurrentBag<double>();   // milliseconds

var cts = new CancellationTokenSource();
var sw  = Stopwatch.StartNew();

// ---------------------------------------------------------------------------
// Print header
// ---------------------------------------------------------------------------
Console.WriteLine();
Console.WriteLine("╔══════════════════════════════════════════════════════════╗");
Console.WriteLine("║          calculaterstresstest — HTTP load test           ║");
Console.WriteLine("╠══════════════════════════════════════════════════════════╣");
Console.WriteLine($"║  URL          : {url,-42}║");
Console.WriteLine($"║  Concurrency  : {concurrency,-42}║");
Console.WriteLine($"║  Duration     : {durationSec}s (ramp {rampSec}s){new string(' ', 29 - $"{durationSec}s (ramp {rampSec}s)".Length)}║");
Console.WriteLine("╚══════════════════════════════════════════════════════════╝");
Console.WriteLine();

// ---------------------------------------------------------------------------
// Worker factory — each worker loops until cancellation
// ---------------------------------------------------------------------------
async Task Worker(int id, CancellationToken ct)
{
    // Stagger ramp-up: worker i starts after (i / concurrency * rampSec) seconds
    int rampDelayMs = (int)((double)id / concurrency * rampSec * 1000);
    try { await Task.Delay(rampDelayMs, ct); } catch (OperationCanceledException) { return; }

    using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
    int exprIndex  = id % expressions.Length;

    while (!ct.IsCancellationRequested)
    {
        string expr = expressions[exprIndex % expressions.Length];
        exprIndex++;

        var reqSw = Stopwatch.StartNew();
        try
        {
            var resp = await http.GetAsync($"{url}/?expr={Uri.EscapeDataString(expr)}", ct)
                                 .ConfigureAwait(false);
            reqSw.Stop();
            if (resp.IsSuccessStatusCode)
                Interlocked.Increment(ref totalSuccess);
            else
                Interlocked.Increment(ref totalErrors);
        }
        catch (OperationCanceledException) { break; }
        catch
        {
            reqSw.Stop();
            Interlocked.Increment(ref totalErrors);
        }

        latencies.Add(reqSw.Elapsed.TotalMilliseconds);
        Interlocked.Increment(ref totalRequests);
    }
}

// ---------------------------------------------------------------------------
// Live progress printer (every second)
// ---------------------------------------------------------------------------
long prevRequests = 0;
var progressTimer = new System.Timers.Timer(1000);
progressTimer.Elapsed += (_, _) =>
{
    long cur  = Interlocked.Read(ref totalRequests);
    long rps  = cur - prevRequests;
    prevRequests = cur;
    int  elapsed = (int)sw.Elapsed.TotalSeconds;
    int  left    = Math.Max(0, durationSec - elapsed);
    long err     = Interlocked.Read(ref totalErrors);
    Console.Write($"\r  [{elapsed,3}s / {durationSec}s]  {rps,5} req/s  total: {cur,7}  errors: {err,5}  remaining: {left,3}s  ");
};
progressTimer.Start();

// ---------------------------------------------------------------------------
// Launch workers and stop after duration
// ---------------------------------------------------------------------------
cts.CancelAfter(TimeSpan.FromSeconds(durationSec));
var workerTasks = Enumerable.Range(0, concurrency)
                            .Select(i => Worker(i, cts.Token))
                            .ToArray();

await Task.WhenAll(workerTasks);
progressTimer.Stop();
sw.Stop();

Console.WriteLine();
Console.WriteLine();

// ---------------------------------------------------------------------------
// Compute statistics
// ---------------------------------------------------------------------------
var sorted   = latencies.OrderBy(x => x).ToArray();
long success = Interlocked.Read(ref totalSuccess);
long errors  = Interlocked.Read(ref totalErrors);
long total   = Interlocked.Read(ref totalRequests);
double actualSec = sw.Elapsed.TotalSeconds;

double Percentile(double[] arr, double p)
{
    if (arr.Length == 0) return 0;
    int idx = (int)Math.Ceiling(p / 100.0 * arr.Length) - 1;
    return arr[Math.Clamp(idx, 0, arr.Length - 1)];
}

double avg = sorted.Length > 0 ? sorted.Average() : 0;
double p50 = Percentile(sorted, 50);
double p95 = Percentile(sorted, 95);
double p99 = Percentile(sorted, 99);
double rps = total / actualSec;

// ---------------------------------------------------------------------------
// Print summary
// ---------------------------------------------------------------------------
Console.WriteLine("╔══════════════════════════════════════════════════════════╗");
Console.WriteLine("║                     Test Summary                         ║");
Console.WriteLine("╠══════════════════════════════════════════════════════════╣");
Console.WriteLine($"║  Duration     : {actualSec:F1}s{new string(' ', 42 - $"{actualSec:F1}s".Length)}║");
Console.WriteLine($"║  Concurrency  : {concurrency,-42}║");
Console.WriteLine($"║  Total req    : {total,-42}║");
Console.WriteLine($"║  Success      : {success,-42}║");
Console.WriteLine($"║  Errors       : {errors,-42}║");
Console.WriteLine($"║  Throughput   : {rps:F1} req/s{new string(' ', 37 - $"{rps:F1} req/s".Length)}║");
Console.WriteLine("╠══════════════════════════════════════════════════════════╣");
Console.WriteLine($"║  Latency avg  : {avg:F1} ms{new string(' ', 38 - $"{avg:F1} ms".Length)}║");
Console.WriteLine($"║  Latency p50  : {p50:F1} ms{new string(' ', 38 - $"{p50:F1} ms".Length)}║");
Console.WriteLine($"║  Latency p95  : {p95:F1} ms{new string(' ', 38 - $"{p95:F1} ms".Length)}║");
Console.WriteLine($"║  Latency p99  : {p99:F1} ms{new string(' ', 38 - $"{p99:F1} ms".Length)}║");
Console.WriteLine("╚══════════════════════════════════════════════════════════╝");
Console.WriteLine();

return errors > 0 && success == 0 ? 1 : 0;
