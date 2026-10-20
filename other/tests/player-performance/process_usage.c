// Read-only process accounting; 100% CPU corresponds to one fully occupied core.
#include <libproc.h>
#include <sys/resource.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    pid_t pid = (pid_t)atoi(argv[1]);
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    double scale = (double)tb.numer / tb.denom / 1e9;
    setvbuf(stdout, NULL, _IOLBF, 0);
    puts("monotonic_s,user_ns,system_ns,resident_bytes,footprint_bytes,pageins,idle_wakeups,interrupt_wakeups,read_bytes,write_bytes");
    struct rusage_info_v4 usage;
    while (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&usage) == 0) {
        printf("%.9f,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu\n",
               mach_absolute_time() * scale,
               (unsigned long long)(usage.ri_user_time * scale * 1e9),
               (unsigned long long)(usage.ri_system_time * scale * 1e9),
               usage.ri_resident_size, usage.ri_phys_footprint, usage.ri_pageins,
               usage.ri_pkg_idle_wkups, usage.ri_interrupt_wkups,
               usage.ri_diskio_bytesread, usage.ri_diskio_byteswritten);
        usleep(250000);
    }
    return 0;
}
