#include "process_manager.hpp"
#include "config.hpp"
#include "logger.hpp"
#include <fstream>
#include <sstream>
#include <array>
#include <regex>
#include <cstdlib>

ProcessManager& ProcessManager::instance() {
    static ProcessManager inst;
    return inst;
}

ProcessManager::ProcessManager() {
    loadCoreProtectedPackages();
}

void ProcessManager::loadCoreProtectedPackages() {
    const std::vector<std::string> hardcoded = {
        "android",
        "com.android.systemui",
        "com.android.phone",
        "com.android.settings",
        "com.android.bluetooth",
        "com.android.shell",
        "com.android.packageinstaller",
        "com.google.android.packageinstaller",
        "com.android.permissioncontroller",
        "com.google.android.permissioncontroller",
        "com.android.providers.downloads",
        "com.android.providers.media",
        "com.android.providers.settings",
        "com.android.providers.telephony",
        "com.android.providers.contacts",
        "com.android.launcher",
        "com.android.launcher3",
        "com.google.android.apps.nexuslauncher",
        "com.miui.home",
        "com.huawei.android.launcher",
        "com.oppo.launcher",
        "com.vivo.launcher",
        "com.realme.launcher",
        "com.sec.android.app.launcher",
        "net.oneplus.launcher",
        "com.android.inputmethod.latin",
        "com.google.android.inputmethod.latin",
        "com.sohu.inputmethod.sogou",
        "com.baidu.input",
        "com.iflytek.inputmethod",
        "com.topjohnwu.magisk",
        "io.github.huskydg.magisk",
        "me.weishu.kernelsu",
        "com.dergoogler.mmrl"
    };

    for (const auto& pkg : hardcoded) {
        core_system_packages_.insert(pkg);
    }
}

void ProcessManager::loadDefaultIme() {
    std::string ime_out = execCommand("settings get secure default_input_method 2>/dev/null");
    size_t slash = ime_out.find('/');
    if (slash != std::string::npos) {
        std::string pkg = ime_out.substr(0, slash);
        while (!pkg.empty() && (pkg.back() == '\r' || pkg.back() == '\n' || pkg.back() == ' ')) {
            pkg.pop_back();
        }
        if (!pkg.empty()) {
            core_system_packages_.insert(pkg);
        }
    }
}

void ProcessManager::loadPackageFile(const std::string& filepath,
                                     std::unordered_set<std::string>& global_set,
                                     std::unordered_map<int, std::unordered_set<std::string>>& user_map) {
    global_set.clear();
    user_map.clear();
    std::ifstream in(filepath);
    if (!in.is_open()) return;

    std::string line;
    while (std::getline(in, line)) {
        size_t cpos = line.find_first_of("#;");
        if (cpos != std::string::npos) {
            line = line.substr(0, cpos);
        }
        size_t start = line.find_first_not_of(" \t\r\n");
        if (start == std::string::npos) continue;
        size_t end = line.find_last_not_of(" \t\r\n");
        std::string item = line.substr(start, end - start + 1);

        // 解析多用户语法: "12:com.foo.bar", "u12:com.foo.bar", "com.foo.bar:12"
        size_t colon_pos = item.find(':');
        if (colon_pos != std::string::npos) {
            std::string p1 = item.substr(0, colon_pos);
            std::string p2 = item.substr(colon_pos + 1);
            int uid = -1;
            std::string pkg;

            if (!p1.empty() && (isdigit(p1[0]) || (p1[0] == 'u' && p1.size() > 1 && isdigit(p1[1])))) {
                size_t dstart = (p1[0] == 'u') ? 1 : 0;
                try {
                    uid = std::stoi(p1.substr(dstart));
                    pkg = p2;
                } catch (...) {}
            } else if (!p2.empty() && isdigit(p2[0])) {
                try {
                    uid = std::stoi(p2);
                    pkg = p1;
                } catch (...) {}
            }

            if (uid >= 0 && pkg.find('.') != std::string::npos) {
                user_map[uid].insert(pkg);
                continue;
            }
        }

        // 无前缀全局配置（对所有用户生效）
        if (item.find('.') != std::string::npos) {
            global_set.insert(item);
        }
    }
}

void ProcessManager::loadSystemPackages() {
    system_packages_.clear();
    std::string out = execCommand("cmd package list packages -s 2>/dev/null || pm list packages -s 2>/dev/null");
    std::istringstream iss(out);
    std::string line;
    while (std::getline(iss, line)) {
        if (line.rfind("package:", 0) == 0) {
            line = line.substr(8);
        }
        while (!line.empty() && (line.back() == '\r' || line.back() == '\n' || line.back() == ' ')) {
            line.pop_back();
        }
        if (!line.empty()) {
            system_packages_.insert(line);
        }
    }
}

void ProcessManager::init() {
    std::lock_guard<std::mutex> lock(mutex_);
    loadDefaultIme();
    loadSystemPackages();
    reloadLists();
}

void ProcessManager::reloadLists() {
    const auto& cfg = ConfigManager::instance();
    struct stat st_w{}, st_b{};
    if (stat(cfg.getWhiteListPath().c_str(), &st_w) == 0) last_wl_mtime_ = st_w.st_mtime;
    if (stat(cfg.getBlackListPath().c_str(), &st_b) == 0) last_bl_mtime_ = st_b.st_mtime;
    loadPackageFile(cfg.getWhiteListPath(), global_whitelist_, user_whitelist_);
    loadPackageFile(cfg.getBlackListPath(), global_blacklist_, user_blacklist_);
}

bool ProcessManager::checkAndReloadLists() {
    const auto& cfg = ConfigManager::instance();
    struct stat st_w{}, st_b{};
    bool changed = false;

    if (stat(cfg.getWhiteListPath().c_str(), &st_w) == 0 && st_w.st_mtime != last_wl_mtime_) {
        last_wl_mtime_ = st_w.st_mtime;
        changed = true;
    }
    if (stat(cfg.getBlackListPath().c_str(), &st_b) == 0 && st_b.st_mtime != last_bl_mtime_) {
        last_bl_mtime_ = st_b.st_mtime;
        changed = true;
    }

    if (changed) {
        std::lock_guard<std::mutex> lock(mutex_);
        loadPackageFile(cfg.getWhiteListPath(), global_whitelist_, user_whitelist_);
        loadPackageFile(cfg.getBlackListPath(), global_blacklist_, user_blacklist_);
        Logger::instance().info("黑白名单已热重载生效");
        return true;
    }
    return false;
}

void ProcessManager::updateForeground(int user_id, const std::string& pkg) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!pkg.empty() && (pkg != current_foreground_.package_name || user_id != current_foreground_.user_id)) {
        last_foreground_ = current_foreground_;
        current_foreground_ = {user_id, pkg};
        last_switch_time_ = std::chrono::steady_clock::now();
    }
}

AppTask ProcessManager::getCurrentForeground() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return current_foreground_;
}

bool ProcessManager::getRunningTaskPackages(std::vector<AppTask>& out_tasks, AppTask& out_foreground) {
    out_tasks.clear();
    out_foreground = {0, ""};

    // 核心优化 1：优先使用 dumpsys activity lru，读取系统全部活跃、后台 Service 及 Cached 进程队列
    // 该队列已天然按 LRU 顺序由近及远排列，且完整标注了多用户标识 (u0, u12 等)
    std::string lru_out = execCommand("dumpsys activity lru 2>/dev/null");
    if (!lru_out.empty()) {
        std::istringstream iss(lru_out);
        std::string line;
        static const std::regex re_lru(R"(^\s*#\d+:.*?\s+(\d+):([A-Za-z0-9_.]+\.[A-Za-z0-9_.]+)(?::\S+)?/(?:u(\d+)[as]|\b(\d+)\b))");

        std::vector<AppTask> lru_tasks;
        std::unordered_set<std::string> seen;

        while (std::getline(iss, line)) {
            std::smatch m;
            if (std::regex_search(line, m, re_lru)) {
                std::string pkg = m[2].str();
                std::string uid_str = m[3].matched ? m[3].str() : (m[4].matched ? m[4].str() : "0");
                int uid = 0;
                try {
                    uid = std::stoi(uid_str);
                    if (uid >= 100000) uid = uid / 100000;
                    else if (uid == 1000) uid = 0;
                } catch (...) {
                    uid = 0;
                }

                if (line.find(" TOP ") != std::string::npos && out_foreground.package_name.empty()) {
                    out_foreground = {uid, pkg};
                }

                std::string key = std::to_string(uid) + ":" + pkg;
                if (seen.insert(key).second) {
                    lru_tasks.push_back({uid, pkg});
                }
            }
        }

        if (!lru_tasks.empty()) {
            out_tasks = std::move(lru_tasks);
            if (!out_foreground.package_name.empty()) {
                updateForeground(out_foreground.user_id, out_foreground.package_name);
            } else if (!out_tasks.empty()) {
                out_foreground = out_tasks.front();
                updateForeground(out_foreground.user_id, out_foreground.package_name);
            }
            return true;
        }
    }

    // 核心优化 2：降级回退到 dumpsys activity activities
    std::string dumpsys_out = execCommand("dumpsys activity activities 2>/dev/null");
    if (dumpsys_out.empty()) {
        Logger::instance().error("获取运行应用列表失败，跳过本次清理");
        return false;
    }

    std::istringstream iss(dumpsys_out);
    std::string line;

    static const std::regex re_task(R"(Task\{.*?\bU=(\d+)\b)");
    static const std::regex re_userid(R"(\buserId=(\d+)\b)");
    static const std::regex re_activity_rec(R"(ActivityRecord\{[0-9a-fA-F]+\s+u(\d+)\s+([A-Za-z0-9_.]+\.[A-Za-z0-9_.]+)/)");
    static const std::regex re_comp(R"(([A-Za-z0-9_.]+\.[A-Za-z0-9_.]+)/)");

    int current_user = 0;
    std::unordered_set<std::string> seen;

    while (std::getline(iss, line)) {
        std::smatch m;
        if (std::regex_search(line, m, re_task)) {
            current_user = std::stoi(m[1].str());
        } else if (std::regex_search(line, m, re_userid)) {
            current_user = std::stoi(m[1].str());
        }

        if (std::regex_search(line, m, re_activity_rec)) {
            int uid = std::stoi(m[1].str());
            std::string pkg = m[2].str();
            std::string key = std::to_string(uid) + ":" + pkg;
            if (seen.insert(key).second) {
                out_tasks.push_back({uid, pkg});
            }
            continue;
        }

        if (line.find("mActivityComponent") != std::string::npos ||
            line.find("realActivity") != std::string::npos ||
            line.find("topResumedActivity") != std::string::npos) {

            if (std::regex_search(line, m, re_comp)) {
                std::string pkg = m[1].str();
                std::string key = std::to_string(current_user) + ":" + pkg;
                if (seen.insert(key).second) {
                    out_tasks.push_back({current_user, pkg});
                }
            }
        }
    }

    if (!out_tasks.empty()) {
        out_foreground = out_tasks.front();
        updateForeground(out_foreground.user_id, out_foreground.package_name);
    }
    return !out_tasks.empty();
}

ProtectionType ProcessManager::checkProtection(int user_id, const std::string& pkg, std::string& out_reason) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (pkg.empty()) {
        out_reason = "空包名";
        return ProtectionType::Empty;
    }

    if (current_foreground_.package_name == pkg && current_foreground_.user_id == user_id) {
        out_reason = "当前前台";
        return ProtectionType::CurrentForeground;
    }

    if (last_foreground_.package_name == pkg && last_foreground_.user_id == user_id) {
        auto elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - last_switch_time_).count();
        if (elapsed_ms < 5000) {
            out_reason = "刚离开前台";
            return ProtectionType::RecentForeground;
        }
    }

    // 白名单匹配: 全局白名单 或 用户专属白名单
    if (global_whitelist_.count(pkg)) {
        out_reason = "白名单(全局)";
        return ProtectionType::Whitelist;
    }
    auto it_uw = user_whitelist_.find(user_id);
    if (it_uw != user_whitelist_.end() && it_uw->second.count(pkg)) {
        out_reason = "白名单(用户" + std::to_string(user_id) + ")";
        return ProtectionType::Whitelist;
    }

    if (core_system_packages_.count(pkg)) {
        out_reason = "系统核心保护";
        return ProtectionType::CoreSystem;
    }

    if (system_packages_.count(pkg)) {
        bool in_blacklist = (global_blacklist_.count(pkg) > 0);
        if (!in_blacklist) {
            auto it_ub = user_blacklist_.find(user_id);
            if (it_ub != user_blacklist_.end() && it_ub->second.count(pkg)) {
                in_blacklist = true;
            }
        }

        if (in_blacklist) {
            out_reason = "黑名单系统应用";
            return ProtectionType::BlacklistSystemApp;
        }
        out_reason = "系统应用保护";
        return ProtectionType::SystemApp;
    }

    out_reason.clear();
    return ProtectionType::Killable;
}

bool ProcessManager::forceStopApp(int user_id, const std::string& pkg) {
    if (pkg.empty()) return false;
    std::string cmd = "am force-stop --user " + std::to_string(user_id) + " " + pkg + " >/dev/null 2>&1";
    int ret = std::system(cmd.c_str());
    if (ret != 0) {
        std::string su_cmd = "su 2000 -c \"am force-stop --user " + std::to_string(user_id) + " '" + pkg + "'\" >/dev/null 2>&1";
        std::system(su_cmd.c_str());
    }
    return true;
}

std::string ProcessManager::execCommand(const std::string& cmd) {
    std::array<char, 256> buffer;
    std::string result;
    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) return result;
    while (fgets(buffer.data(), buffer.size(), pipe) != nullptr) {
        result += buffer.data();
    }
    pclose(pipe);
    return result;
}

bool ProcessManager::execCommandQuiet(const std::string& cmd) {
    int ret = std::system(cmd.c_str());
    return (ret == 0);
}
