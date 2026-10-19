#include "config.hpp"
#include "logger.hpp"
#include <fstream>
#include <sstream>
#include <algorithm>
#include <cctype>

ConfigManager& ConfigManager::instance() {
    static ConfigManager inst;
    return inst;
}

std::string ConfigManager::trim(const std::string& s) {
    size_t start = 0;
    while (start < s.size() && std::isspace(static_cast<unsigned char>(s[start]))) {
        start++;
    }
    size_t end = s.size();
    while (end > start && std::isspace(static_cast<unsigned char>(s[end - 1]))) {
        end--;
    }
    return s.substr(start, end - start);
}

bool ConfigManager::parseBool(const std::string& val, bool def) {
    std::string s = trim(val);
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return std::tolower(c); });
    if (s == "1" || s == "true" || s == "yes" || s == "on") {
        return true;
    }
    if (s == "0" || s == "false" || s == "no" || s == "off") {
        return false;
    }
    return def;
}

int ConfigManager::parseInt(const std::string& val, int def) {
    std::string s = trim(val);
    if (s.empty()) return def;
    try {
        return std::stoi(s);
    } catch (...) {
        return def;
    }
}

void ConfigManager::ensureDefaultConfigFile() {
    struct stat st{};
    if (stat(config_path_.c_str(), &st) == 0) {
        return; // 文件已存在
    }

    std::ofstream out(config_path_);
    if (!out.is_open()) return;

    out << "# ==========================================\n"
        << "# 运存防线 RAM Guard 配置文件\n"
        << "# 修改后无需重启手机，模块会自动重载配置\n"
        << "# 以 # 或 ; 开头的行为注释\n"
        << "# ==========================================\n\n"
        << "# ========== 内存阈值 ==========\n"
        << "start_mem_percent=10\n"
        << "target_mem_percent=16\n"
        << "emergency_mem_percent=4\n\n"
        << "# ========== Swap / Zram 压力 ==========\n"
        << "swap_free_start_percent=40\n"
        << "swap_free_emergency_percent=15\n\n"
        << "# ========== 前台切换后的临时监控 ==========\n"
        << "monitor_delay_sec=15\n"
        << "monitor_interval_sec=15\n"
        << "monitor_duration_sec=180\n\n"
        << "# ========== 清理行为 ==========\n"
        << "clean_delay_after_switch_ms=2000\n"
        << "max_clean_count=2\n"
        << "emergency_max_clean_count=3\n"
        << "clean_interval_ms=400\n"
        << "clean_cooldown_sec=30\n\n"
        << "# ========== 日志 ==========\n"
        << "enable_log=true\n"
        << "log_max_size_kb=512\n\n"
        << "# ========== 状态栏通知 ==========\n"
        << "# 是否在状态栏显示运行状态通知\n"
        << "# 显示：清理应用个数、上次释放内存、累计释放内存\n"
        << "enable_status_notification=false\n";
    out.close();
}

bool ConfigManager::loadFromFile(const std::string& path) {
    std::ifstream in(path);
    if (!in.is_open()) return false;

    ModuleConfig cfg = config_; // 保留已有设置或默认值
    std::string line;
    while (std::getline(in, line)) {
        // 去除行内注释
        size_t comment_pos = line.find_first_of("#;");
        if (comment_pos != std::string::npos) {
            line = line.substr(0, comment_pos);
        }
        line = trim(line);
        if (line.empty()) continue;

        size_t eq_pos = line.find('=');
        if (eq_pos == std::string::npos) continue;

        std::string key = trim(line.substr(0, eq_pos));
        std::string val = trim(line.substr(eq_pos + 1));

        if (key == "start_mem_percent" || key == "avail_mem_percent") {
            cfg.start_mem_percent = parseInt(val, cfg.start_mem_percent);
        } else if (key == "target_mem_percent") {
            cfg.target_mem_percent = parseInt(val, cfg.target_mem_percent);
        } else if (key == "emergency_mem_percent") {
            cfg.emergency_mem_percent = parseInt(val, cfg.emergency_mem_percent);
        } else if (key == "swap_free_start_percent") {
            cfg.swap_free_start_percent = parseInt(val, cfg.swap_free_start_percent);
        } else if (key == "swap_free_emergency_percent") {
            cfg.swap_free_emergency_percent = parseInt(val, cfg.swap_free_emergency_percent);
        } else if (key == "monitor_delay_sec") {
            cfg.monitor_delay_sec = parseInt(val, cfg.monitor_delay_sec);
        } else if (key == "monitor_interval_sec") {
            cfg.monitor_interval_sec = parseInt(val, cfg.monitor_interval_sec);
        } else if (key == "monitor_duration_sec") {
            cfg.monitor_duration_sec = parseInt(val, cfg.monitor_duration_sec);
        } else if (key == "clean_delay_after_switch_ms") {
            cfg.clean_delay_after_switch_ms = parseInt(val, cfg.clean_delay_after_switch_ms);
        } else if (key == "max_clean_count") {
            cfg.max_clean_count = parseInt(val, cfg.max_clean_count);
        } else if (key == "emergency_max_clean_count") {
            cfg.emergency_max_clean_count = parseInt(val, cfg.emergency_max_clean_count);
        } else if (key == "clean_interval_ms") {
            cfg.clean_interval_ms = parseInt(val, cfg.clean_interval_ms);
        } else if (key == "clean_cooldown_sec") {
            cfg.clean_cooldown_sec = parseInt(val, cfg.clean_cooldown_sec);
        } else if (key == "enable_log") {
            cfg.enable_log = parseBool(val, cfg.enable_log);
        } else if (key == "log_max_size_kb") {
            cfg.log_max_size_kb = parseInt(val, cfg.log_max_size_kb);
        } else if (key == "enable_status_notification") {
            cfg.enable_status_notification = parseBool(val, cfg.enable_status_notification);
        }
    }

    config_ = cfg;
    return true;
}

bool ConfigManager::init(const std::string& mod_dir) {
    mod_dir_ = mod_dir;
    config_path_ = mod_dir + "/config.ini";
    log_path_ = mod_dir + "/ram.log";
    whitelist_path_ = mod_dir + "/白名单.conf";
    blacklist_path_ = mod_dir + "/黑名单.conf";

    ensureDefaultConfigFile();

    struct stat st{};
    if (stat(config_path_.c_str(), &st) == 0) {
        last_mtime_ = st.st_mtime;
        loadFromFile(config_path_);
    }
    return true;
}

bool ConfigManager::checkAndReload() {
    struct stat st{};
    if (stat(config_path_.c_str(), &st) == 0) {
        if (st.st_mtime != last_mtime_) {
            last_mtime_ = st.st_mtime;
            if (loadFromFile(config_path_)) {
                Logger::instance().info("配置已重载");
                return true;
            }
        }
    }
    return false;
}
