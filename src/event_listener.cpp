#include "event_listener.hpp"
#include "cleaner.hpp"
#include "process_manager.hpp"
#include "config.hpp"
#include "logger.hpp"
#include <cstdio>
#include <cstring>
#include <chrono>

EventListener& EventListener::instance() {
    static EventListener inst;
    return inst;
}

EventListener::EventListener() = default;

EventListener::~EventListener() {
    stop();
}

void EventListener::start() {
    if (running_) return;
    running_ = true;

    log_thread_ = std::thread(&EventListener::runLogLoop, this);
    monitor_thread_ = std::thread(&EventListener::runMonitorLoop, this);
}

void EventListener::stop() {
    if (!running_) return;
    running_ = false;

    if (log_thread_.joinable()) log_thread_.join();
    if (monitor_thread_.joinable()) monitor_thread_.join();
}

void EventListener::triggerSwitchEvent(int user_id, const std::string& pkg) {
    if (!pkg.empty()) {
        ProcessManager::instance().updateForeground(user_id, pkg);
    }
    last_switch_time_ = std::chrono::steady_clock::now();
    switch_triggered_ = true;

    const auto& cfg = ConfigManager::instance().get();
    if (cfg.clean_delay_after_switch_ms > 0) {
        std::this_thread::sleep_for(std::chrono::milliseconds(cfg.clean_delay_after_switch_ms));
    }
    CleanerEngine::instance().checkAndClean(true);
}

void EventListener::listenViaLogcat() {
    const char* cmd = "logcat -b events -v brief -T 1 2>/dev/null";
    FILE* pipe = popen(cmd, "r");
    if (!pipe) {
        Logger::instance().error("启动 logcat events 监听失败");
        return;
    }

    char buf[512];
    while (running_ && fgets(buf, sizeof(buf), pipe)) {
        if (strstr(buf, "wm_resume_activity") ||
            strstr(buf, "am_start_activity") ||
            strstr(buf, "wm_set_resumed_activity") ||
            strstr(buf, "am_focused_activity")) {

            std::string line(buf);
            int uid = 0;
            // Android EventLog 通常形如: wm_resume_activity: [0,com.tencent.mm/.ui.LauncherUI]
            size_t bstart = line.find('[');
            if (bstart != std::string::npos) {
                size_t comma = line.find(',', bstart);
                if (comma != std::string::npos) {
                    try {
                        uid = std::stoi(line.substr(bstart + 1, comma - bstart - 1));
                    } catch (...) {
                        uid = 0;
                    }
                }
            }

            std::string pkg;
            size_t slash = line.find('/');
            if (slash != std::string::npos) {
                size_t pstart = slash;
                while (pstart > 0 && (isalnum(line[pstart - 1]) || line[pstart - 1] == '.' || line[pstart - 1] == '_')) {
                    pstart--;
                }
                pkg = line.substr(pstart, slash - pstart);
            }

            triggerSwitchEvent(uid, pkg);
        }
    }
    pclose(pipe);
}

void EventListener::runLogLoop() {
    while (running_) {
        listenViaLogcat();
        if (running_) {
            std::this_thread::sleep_for(std::chrono::seconds(2));
        }
    }
}

void EventListener::runMonitorLoop() {
    while (running_) {
        if (switch_triggered_) {
            switch_triggered_ = false;
            const auto& cfg = ConfigManager::instance().get();

            if (cfg.monitor_delay_sec > 0) {
                for (int i = 0; i < cfg.monitor_delay_sec && running_ && !switch_triggered_; ++i) {
                    std::this_thread::sleep_for(std::chrono::seconds(1));
                }
            }

            auto start_time = std::chrono::steady_clock::now();
            while (running_ && !switch_triggered_) {
                auto now = std::chrono::steady_clock::now();
                auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(now - start_time).count();
                if (elapsed >= cfg.monitor_duration_sec) {
                    break;
                }

                CleanerEngine::instance().checkAndClean(false);

                for (int i = 0; i < cfg.monitor_interval_sec && running_ && !switch_triggered_; ++i) {
                    std::this_thread::sleep_for(std::chrono::seconds(1));
                }
            }
        } else {
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
        }
    }
}
