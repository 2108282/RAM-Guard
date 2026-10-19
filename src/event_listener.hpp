#pragma once
#include <string>
#include <atomic>
#include <thread>
#include <vector>

class EventListener {
public:
    static EventListener& instance();

    void start();
    void stop();

private:
    EventListener();
    ~EventListener();

    void runLogLoop();
    void runMonitorLoop();
    void triggerSwitchEvent(int user_id, const std::string& pkg);

    void listenViaLogcat();

    std::atomic<bool> running_{false};
    std::thread log_thread_;
    std::thread monitor_thread_;

    std::atomic<bool> switch_triggered_{false};
    std::chrono::steady_clock::time_point last_switch_time_;
};
