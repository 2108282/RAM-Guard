#include "memory.hpp"
#include "logger.hpp"
#include <cstdio>
#include <cstring>
#include <cmath>

bool MemoryReader::read(MemorySnapshot& snapshot) {
    FILE* fp = std::fopen("/proc/meminfo", "r");
    if (!fp) {
        Logger::instance().error("读取 /proc/meminfo 失败");
        return false;
    }

    char line[256];
    snapshot = MemorySnapshot{}; // 重置
    int found_count = 0;

    while (std::fgets(line, sizeof(line), fp)) {
        long val = 0;
        if (std::sscanf(line, "MemTotal: %ld kB", &val) == 1) {
            snapshot.mem_total_kb = val;
            found_count++;
        } else if (std::sscanf(line, "MemAvailable: %ld kB", &val) == 1) {
            snapshot.mem_available_kb = val;
            found_count++;
        } else if (std::sscanf(line, "SwapTotal: %ld kB", &val) == 1) {
            snapshot.swap_total_kb = val;
            found_count++;
        } else if (std::sscanf(line, "SwapFree: %ld kB", &val) == 1) {
            snapshot.swap_free_kb = val;
            found_count++;
        }
        if (found_count >= 4) break;
    }
    std::fclose(fp);

    return (snapshot.mem_total_kb > 0);
}

std::string MemoryReader::formatSize(long kb) {
    long mb = kb / 1024;
    if (mb <= 0) {
        return "0MB";
    }
    if (mb < 1024) {
        return std::to_string(mb) + "MB";
    }

    double gb = static_cast<double>(mb) / 1024.0;
    char buf[32];
    // 如果接近整GB则展示1位小数，比如 1.1GB
    std::snprintf(buf, sizeof(buf), "%.1fGB", gb);
    return std::string(buf);
}
