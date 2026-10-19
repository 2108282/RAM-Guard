#include "config.hpp"
#include "logger.hpp"
#include "memory.hpp"
#include "process_manager.hpp"
#include "notification.hpp"
#include "cleaner.hpp"
#include "event_listener.hpp"
#include <iostream>
#include <csignal>
#include <unistd.h>
#include <climits>

static std::atomic<bool> g_running{true};

static void sigHandler(int signum) {
    g_running = false;
    EventListener::instance().stop();
}

static std::string detectModDir(int argc, char* argv[]) {
    if (argc > 1 && argv[1] != nullptr && argv[1][0] != '\0') {
        return std::string(argv[1]);
    }

    char self_path[PATH_MAX] = {0};
    ssize_t len = readlink("/proc/self/exe", self_path, sizeof(self_path) - 1);
    if (len > 0) {
        self_path[len] = '\0';
        std::string s(self_path);
        size_t last_slash = s.find_last_of('/');
        if (last_slash != std::string::npos) {
            std::string dir = s.substr(0, last_slash);
            if (!dir.empty() && dir != "/data/local/tmp") {
                return dir;
            }
        }
    }

    return "/data/adb/modules/ram";
}

int main(int argc, char* argv[]) {
    // 注册信号处理
    std::signal(SIGINT, sigHandler);
    std::signal(SIGTERM, sigHandler);
    std::signal(SIGHUP, SIG_IGN);

    std::string mod_dir = detectModDir(argc, argv);

    // 1. 加载配置
    auto& cfg_mgr = ConfigManager::instance();
    cfg_mgr.init(mod_dir);
    const auto& cfg = cfg_mgr.get();

    // 2. 初始化日志
    auto& logger = Logger::instance();
    logger.init(cfg_mgr.getLogPath(), cfg.log_max_size_kb, cfg.enable_log);
    logger.info("运存防线启动，配置加载完成");

    // 3. 初始化进程管理（加载系统核心包列表、白名单、黑名单、当前输入法）
    auto& pm = ProcessManager::instance();
    pm.init();

    // 4. 启动前台切换事件监听器
    auto& listener = EventListener::instance();
    listener.start();

    // 5. 初始化状态栏通知 (若配置启用)
    if (cfg.enable_status_notification) {
        NotificationManager::instance().update(0, 0, 0);
    }

    // 6. 启动时执行一次初始检查
    CleanerEngine::instance().checkAndClean(false);

    // 7. 主循环保持休眠等待信号
    while (g_running) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }

    logger.info("运存防线已停止");
    NotificationManager::instance().hide();
    return 0;
}
