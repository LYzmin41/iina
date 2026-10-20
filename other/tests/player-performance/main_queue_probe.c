// Matched instrumentation for disposable benchmark app copies only.
// Measures main-queue scheduling delay, not end-to-end click or display latency.
#include <dispatch/dispatch.h>
#include <mach/mach_time.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static dispatch_queue_t writer;
static dispatch_source_t ticker;
static FILE *trace;
static atomic_bool pending;
static uint64_t requested;
static double scale;

static double seconds(uint64_t value) { return value * scale; }

__attribute__((constructor)) static void install_probe(void) {
    const char *path = getenv("LYINA_PERF_TRACE");
    if (!path || !(trace = fopen(path, "w"))) return;
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    scale = (double)timebase.numer / timebase.denom / 1e9;
    setvbuf(trace, NULL, _IOLBF, 0);
    fprintf(trace, "monotonic_s,latency_ms,pending_ms\n");
    writer = dispatch_queue_create("org.lyina.benchmark.probe", DISPATCH_QUEUE_SERIAL);
    ticker = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, writer);
    dispatch_source_set_timer(ticker, DISPATCH_TIME_NOW, 50000000, 5000000);
    dispatch_source_set_event_handler(ticker, ^{
        uint64_t now = mach_absolute_time();
        if (atomic_load(&pending)) {
            // Keep a bounded outstanding request even during a permanent stall.
            fprintf(trace, "%.9f,,%.6f\n", seconds(now), seconds(now - requested) * 1000);
            return;
        }
        requested = now;
        atomic_store(&pending, true);
        dispatch_async(dispatch_get_main_queue(), ^{
            uint64_t completed = mach_absolute_time();
            dispatch_async(writer, ^{
                fprintf(trace, "%.9f,%.6f,0\n", seconds(completed), seconds(completed - requested) * 1000);
                atomic_store(&pending, false);
            });
        });
    });
    dispatch_resume(ticker);
}
