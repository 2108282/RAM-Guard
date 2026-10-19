#pragma once
#include <string>
#include <sys/stat.h>

struct ModuleConfig {
    // 内存阈值
    int start_mem_percent = 10;
    int target_mem_percent = 16;
    int emergency_mem_percent = 4;

    // Swap / Zram 压力阈值
    int swap_free_start_percent = 40;
    int swap_free_emergency_percent = 15;

    // 前台切换后的临时监控
    int monitor_delay_sec = 15;
    int monitor_interval_sec = 15;
    int monitor_duration_sec = 180;

    // 清理行为
    int clean_delay_after_switch_ms = 2000;
    int max_clean_count = 2;
    int emergency_max_clean_count = 3;
    int clean_interval_ms = 400;
    int clean_cooldown_sec = 30;

    // 日志
    bool enable_log = true;
    int log_max_size_kb = 512;

    // 状态栏常驻通知
    bool enable_status_notification = false;
};

class ConfigManager {
public:
    static ConfigManager& instance();

    bool init(const std::string& mod_dir);
    bool checkAndReload();
    const ModuleConfig& get() const { return config_; }

    const std::string& getModDir() const { return mod_dir_; }
    const std::string& getConfigPath() const { return config_path_; }
    const std::string& getLogPath() const { return log_path_; }
    const std::string& getWhiteListPath() const { return whitelist_path_; }
    const std::string& getBlackListPath() const { return blacklist_path_; }

private:
    ConfigManager() = default;
    void ensureDefaultConfigFile();
    bool loadFromFile(const std::string& path);
    static bool parseBool(const std::string& val, bool def);
    static int parseInt(const std::string& val, int def);
    static std::string trim(const std::string& s);

    std::string mod_dir_;
    std::string config_path_;
    std::string log_path_;
    std::string whitelist_path_;
    std::string blacklist_path_;
    time_t last_mtime_ = 0;
    ModuleConfig config_;
};
