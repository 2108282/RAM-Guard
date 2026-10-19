#pragma once
#include <string>
#include <vector>
#include <unordered_set>
#include <unordered_map>
#include <mutex>
#include <chrono>

struct AppTask {
    int user_id = 0;
    std::string package_name;

    bool operator==(const AppTask& other) const {
        return user_id == other.user_id && package_name == other.package_name;
    }
};

enum class ProtectionType {
    Killable = 0,
    Empty,
    CurrentForeground,
    RecentForeground,
    Whitelist,
    CoreSystem,
    SystemApp,
    BlacklistSystemApp // 属于系统应用但在黑名单中，允许清理
};

class ProcessManager {
public:
    static ProcessManager& instance();

    void init();
    void reloadLists();

    // 更新当前前台应用 (带用户空间)
    void updateForeground(int user_id, const std::string& pkg);
    AppTask getCurrentForeground() const;

    // 解析当前任务栈 (带多用户空间)
    bool getRunningTaskPackages(std::vector<AppTask>& out_tasks, AppTask& out_foreground);

    // 检查应用保护状态 (支持多用户精确匹配与全局匹配)
    ProtectionType checkProtection(int user_id, const std::string& pkg, std::string& out_reason);

    // 终止指定用户空间的应用 (am force-stop --user <user_id> <pkg>)
    bool forceStopApp(int user_id, const std::string& pkg);

    static std::string execCommand(const std::string& cmd);
    static bool execCommandQuiet(const std::string& cmd);

private:
    ProcessManager();

    void loadCoreProtectedPackages();
    void loadDefaultIme();
    void loadSystemPackages();
    void loadPackageFile(const std::string& filepath,
                         std::unordered_set<std::string>& global_set,
                         std::unordered_map<int, std::unordered_set<std::string>>& user_map);

    std::unordered_set<std::string> core_system_packages_;
    std::unordered_set<std::string> system_packages_;

    // 全局黑白名单 (无前缀，作用于所有用户)
    std::unordered_set<std::string> global_whitelist_;
    std::unordered_set<std::string> global_blacklist_;

    // 区分特定多用户空间的黑白名单: map<user_id, set<package>>
    std::unordered_map<int, std::unordered_set<std::string>> user_whitelist_;
    std::unordered_map<int, std::unordered_set<std::string>> user_blacklist_;

    AppTask current_foreground_;
    AppTask last_foreground_;
    std::chrono::steady_clock::time_point last_switch_time_;

    mutable std::mutex mutex_;
};
