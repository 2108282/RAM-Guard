#include "notification.hpp"
#include "config.hpp"
#include "memory.hpp"
#include <cstdio>
#include <cstdlib>

NotificationManager& NotificationManager::instance() {
    static NotificationManager inst;
    return inst;
}

void NotificationManager::update(int clean_count, long last_freed_kb, long total_freed_kb) {
    std::lock_guard<std::mutex> lock(mutex_);
    const auto& cfg = ConfigManager::instance().get();

    if (!cfg.enable_status_notification) {
        if (is_posted_) {
            hide();
        }
        return;
    }

    std::string last_str = MemoryReader::formatSize(last_freed_kb);
    std::string total_str = MemoryReader::formatSize(total_freed_kb);

    char content[256];
    std::snprintf(content, sizeof(content), "清理 %d 个 ｜ 上次 %s ｜ 累计 %s",
                  clean_count, last_str.c_str(), total_str.c_str());

    // 唤醒可能处于休眠中的历史通知通道 (与原版逻辑 100% 对齐)
    std::string unsnooze_cmd = "cmd notification list 2>/dev/null | awk '/RAMGuard/ {print $1}' | "
                               "while read k; do [ -n \"$k\" ] && cmd notification unsnooze \"$k\" >/dev/null 2>&1; done";
    std::system(unsnooze_cmd.c_str());

    // 发布常驻状态栏通知
    std::string post_cmd = "su 2000 -c \"cmd notification post -t '运存防线' RAMGuard '" + std::string(content) + "'\" >/dev/null 2>&1 || "
                           "cmd notification post -t '运存防线' RAMGuard '" + std::string(content) + "' >/dev/null 2>&1";
    std::system(post_cmd.c_str());
    is_posted_ = true;
}

void NotificationManager::hide() {
    // 模块停止时休眠通知，避免留下僵尸卡片
    std::string cmd = "su 2000 -c \"cmd notification list 2>/dev/null | awk '/RAMGuard/ {print \\$1}' | "
                      "while read k; do [ -n \\\"\\$k\\\" ] && cmd notification snooze --for 315360000000 \\\"\\$k\\\" >/dev/null 2>&1; done\" >/dev/null 2>&1 || "
                      "cmd notification list 2>/dev/null | awk '/RAMGuard/ {print $1}' | while read k; do [ -n \"$k\" ] && cmd notification snooze --for 315360000000 \"$k\" >/dev/null 2>&1; done";
    std::system(cmd.c_str());
    is_posted_ = false;
}
