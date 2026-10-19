#pragma once
#include <string>
#include <mutex>

class NotificationManager {
public:
    static NotificationManager& instance();

    void update(int clean_count, long last_freed_kb, long total_freed_kb);
    void hide();

private:
    NotificationManager() = default;

    std::mutex mutex_;
    bool is_posted_ = false;
};
