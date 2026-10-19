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

    std::string cmd = "cmd notification post -S bigtext -t '运存防线' RAMGuard '" + std::string(content) + "' >/dev/null 2>&1";
    std::system(cmd.c_str());
    is_posted_ = true;
}

void NotificationManager::hide() {
    std::string cmd = "cmd notification list 2>/dev/null | awk '/RAMGuard/ {print $1}' | "
                      "while read k; do [ -n \"$k\" ] && cmd notification snooze --for 315360000000 \"$k\" >/dev/null 2>&1; done";
    std::system(cmd.c_str());
    is_posted_ = false;
}
