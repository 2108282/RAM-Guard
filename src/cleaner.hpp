#pragma once
#include "config.hpp"
#include "memory.hpp"
#include <string>
#include <vector>
#include <chrono>

enum class CleanMode {
    Normal,
    Emergency,
    Light
};

class CleanerEngine {
public:
    static CleanerEngine& instance();

    // 触发单次内存检查与清理
    bool checkAndClean(bool is_fast_switch = false);

private:
    CleanerEngine() = default;

    std::chrono::steady_clock::time_point last_clean_time_;
    long total_freed_kb_ = 0;
    long total_zram_freed_kb_ = 0;
    int total_clean_count_ = 0;
};
