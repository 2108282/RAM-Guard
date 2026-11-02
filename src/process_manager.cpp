#include "process_manager.hpp"
#include "config.hpp"
#include "logger.hpp"
#include <fstream>
#include <sstream>
#include <array>
#include <regex>
#include <cstdlib>
#include <unistd.h>
#include <sys/stat.h>

ProcessManager& ProcessManager::instance() {
    static ProcessManager inst;
    return inst;
}

ProcessManager::ProcessManager() {
    start_time_ = std::chrono::steady_clock::now();
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

        if (item.find('.') != std::string::npos) {
            global_set.insert(item);
        }
    }
}

void ProcessManager::loadSystemPackages() {
    // 1. 优先从本地落盘缓存快速恢复，确保开机第 0 秒即有系统清单
    if (!sys_cache_path_.empty()) {
        std::ifstream cache_in(sys_cache_path_);
        if (cache_in.is_open()) {
            std::string line;
            while (std::getline(cache_in, line)) {
                while (!line.empty() && (line.back() == '\r' || line.back() == '\n' || line.back() == ' ')) {
                    line.pop_back();
                }
                if (!line.empty()) {
                    system_packages_.insert(line);
                }
            }
            cache_in.close();
            if (system_packages_.size() > 50) {
                Logger::instance().info("已从本地缓存恢复系统应用清单 (" + std::to_string(system_packages_.size()) + " 项)");
                return;
            }
        }
    }

    // 2. 尝试从系统 Package Manager 加载
    checkAndReloadSystemPackages(true);
}

bool ProcessManager::checkAndReloadSystemPackages(bool force) {
    auto now = std::chrono::steady_clock::now();
    auto elapsed_sec = std::chrono::duration_cast<std::chrono::seconds>(now - start_time_).count();

    // 开机 5 分钟 (300 秒) 自动触发一次全量重新扫描，此时系统服务已完全就绪
    if (!did_5min_rescan_ && elapsed_sec >= 300) {
        did_5min_rescan_ = true;
        force = true;
        Logger::instance().info("触发开机 5 分钟定时重新扫描系统应用清单...");
    }

    if (!force && system_packages_.size() > 50) {
        return false;
    }

    std::string out = execCommand("cmd package list packages -s 2>/dev/null || pm list packages -s 2>/dev/null");
    if (out.empty() || out.find("package:") == std::string::npos) {
        return false;
    }

    std::unordered_set<std::string> new_sys;
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
            new_sys.insert(line);
        }
    }

    if (new_sys.size() > 50) {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            system_packages_ = std::move(new_sys);
        }
        Logger::instance().info("系统应用清单已更新，共 " + std::to_string(system_packages_.size()) + " 个系统包");

        // 同步持久化到本地缓存文件
        if (!sys_cache_path_.empty()) {
            std::ofstream cache_out(sys_cache_path_);
            if (cache_out.is_open()) {
                for (const auto& pkg : system_packages_) {
                    cache_out << pkg << "\n";
                }
                cache_out.close();
            }
        }
        return true;
    }
    return false;
}

bool ProcessManager::isThirdPartyApp(int pid, const std::string& pkg) {
    if (pid <= 0) return true; // 无法获取 PID 时默认宽松

    // 核心物理法则：读取 /proc/<pid>/maps 中实际加载的主 APK
    // 凡是不在 /data/app/ 的，100% 属于系统/芯片底层服务 (如 /system, /system_ext, /vendor, /product, /apex)
    std::string maps_path = "/proc/" + std::to_string(pid) + "/maps";
    std::ifstream maps_in(maps_path);
    if (!maps_in.is_open()) return true;

    std::string line;
    bool has_data_app = false;
    bool has_system_partition = false;

    while (std::getline(maps_in, line)) {
        if (line.find(".apk") != std::string::npos) {
            if (line.find("/data/app/") != std::string::npos) {
                has_data_app = true;
                break; // 只要有 /data/app/ 的 APK 映射，即为用户第三方应用
            }
            if (line.find("/system/") != std::string::npos ||
                line.find("/system_ext/") != std::string::npos ||
                line.find("/vendor/") != std::string::npos ||
                line.find("/product/") != std::string::npos ||
                line.find("/apex/") != std::string::npos ||
                line.find("/odm/") != std::string::npos) {
                has_system_partition = true;
            }
        }
    }
    maps_in.close();

    if (!has_data_app && has_system_partition) {
        return false; // 物理路径完全位于系统分区，非第三方用户应用！
    }

    return true;
}

void ProcessManager::init() {
    std::lock_guard<std::mutex> lock(mutex_);
    sys_cache_path_ = ConfigManager::instance().getModDir() + "/system_packages.cache";
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
        current_foreground_ = {user_id, pkg, 0};
        last_switch_time_ = std::chrono::steady_clock::now();
    }
}

AppTask ProcessManager::getCurrentForeground() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return current_foreground_;
}

bool ProcessManager::getRunningTaskPackages(std::vector<AppTask>& out_tasks, AppTask& out_foreground) {
    out_tasks.clear();
    out_foreground = {0, "", 0};

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
                int pid = std::stoi(m[1].str());
                std::string pkg = m[2].str();
                std::string uid_str = m[3].matched ? m[3].str() : (m[4].matched ? m[4].str() : "0");
                int raw_uid = 0;
                int user_id = 0;
                try {
                    raw_uid = std::stoi(uid_str);
                    if (raw_uid >= 100000) user_id = raw_uid / 100000;
                    else user_id = 0;
                } catch (...) {
                    raw_uid = 0;
                    user_id = 0;
                }

                // 核心加固：若 raw_uid < 10000，属于 Android 特权服务用户 (如 1073 networkstack, 1027 nfc, 1001 phone)
                // 必须严格属于 user_id = 0，不可误当成多用户空间普通应用！
                if (raw_uid < 10000) {
                    user_id = 0;
                }

                if (line.find(" TOP ") != std::string::npos && out_foreground.package_name.empty()) {
                    out_foreground = {user_id, pkg, pid};
                }

                std::string key = std::to_string(user_id) + ":" + pkg;
                if (seen.insert(key).second) {
                    lru_tasks.push_back({user_id, pkg, pid});
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

    return !out_tasks.empty();
}

ProtectionType ProcessManager::checkProtection(int user_id, const std::string& pkg, int pid, std::string& out_reason) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (pkg.empty()) {
        out_reason = "空包名";
        return ProtectionType::Empty;
    }

    // 1. 核心防砖应用判定 (无论如何绝对不杀)
    if (core_system_packages_.count(pkg)) {
        out_reason = "系统核心保护";
        return ProtectionType::CoreSystem;
    }

    // 2. 当前前台与刚离开前台短暂缓冲
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

    // 3. 白名单匹配 (全局白名单 或 单空间专属白名单 0:pkg / 12:pkg)
    if (global_whitelist_.count(pkg)) {
        out_reason = "白名单(全局)";
        return ProtectionType::Whitelist;
    }
    auto it_uw = user_whitelist_.find(user_id);
    if (it_uw != user_whitelist_.end() && it_uw->second.count(pkg)) {
        out_reason = "白名单(用户" + std::to_string(user_id) + ")";
        return ProtectionType::Whitelist;
    }

    // 4. 【黑名单最高优先级接管】
    // 只要用户在黑名单中明确配置了该包名，系统应用或底层服务一律允许查杀！
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

    // 5. 系统应用与芯片底层服务免杀拦截 (UID、包名清单、物理分区三道防线)
    // 5.1 芯片厂商硬件服务包名前缀免杀
    if (pkg.rfind("vendor.", 0) == 0 ||
        pkg.rfind("com.qti.", 0) == 0 ||
        pkg.rfind("com.qualcomm.", 0) == 0 ||
        pkg.rfind("org.ifaa.", 0) == 0) {
        out_reason = "芯片底层服务保护";
        return ProtectionType::SystemApp;
    }

    // 5.2 系统应用清单免杀
    if (system_packages_.count(pkg)) {
        out_reason = "系统应用保护";
        return ProtectionType::SystemApp;
    }

    // 5.3 物理安装分区免杀：APK 路径不在 /data/app/ 的统统视为系统组件
    if (pid > 0 && !isThirdPartyApp(pid, pkg)) {
        out_reason = "系统分区保护(非/data/app)";
        return ProtectionType::SystemApp;
    }

    // 6. 剩余真正的第三方后台用户应用 -> 允许清理
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
