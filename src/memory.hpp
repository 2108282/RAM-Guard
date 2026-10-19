#pragma once
#include <string>

struct MemorySnapshot {
    long mem_total_kb = 0;
    long mem_available_kb = 0;
    long swap_total_kb = 0;
    long swap_free_kb = 0;

    int availPercent() const {
        if (mem_total_kb <= 0) return 0;
        return static_cast<int>((mem_available_kb * 100) / mem_total_kb);
    }

    int swapFreePercent() const {
        if (swap_total_kb <= 0) return -1;
        return static_cast<int>((swap_free_kb * 100) / swap_total_kb);
    }

    bool hasSwap() const {
        return swap_total_kb > 0;
    }
};

class MemoryReader {
public:
    static bool read(MemorySnapshot& snapshot);
    static std::string formatSize(long kb);
};
