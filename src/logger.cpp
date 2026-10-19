#include "logger.hpp"
#include <fstream>
#include <chrono>
#include <ctime>
#include <iomanip>
#include <sys/stat.h>

Logger& Logger::instance() {
    static Logger inst;
    return inst;
}

void Logger::init(const std::string& log_path, int max_size_kb, bool enable) {
    std::lock_guard<std::mutex> lock(mutex_);
    log_path_ = log_path;
    max_size_kb_ = max_size_kb;
    enabled_ = enable;
}

void Logger::updateSettings(int max_size_kb, bool enable) {
    std::lock_guard<std::mutex> lock(mutex_);
    max_size_kb_ = max_size_kb;
    enabled_ = enable;
}

std::string Logger::currentTimestamp() {
    auto now = std::chrono::system_clock::now();
    std::time_t tt = std::chrono::system_clock::to_time_t(now);
    std::tm tm_buf{};
    localtime_r(&tt, &tm_buf);

    char buf[64];
    std::strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", &tm_buf);
    return std::string(buf);
}

void Logger::checkRotation() {
    if (log_path_.empty()) return;
    struct stat st{};
    if (stat(log_path_.c_str(), &st) == 0) {
        if (st.st_size > static_cast<off_t>(max_size_kb_) * 1024) {
            // 清理旧日志并写入提示
            std::ofstream out(log_path_, std::ios::trunc);
            if (out.is_open()) {
                out << "[" << currentTimestamp() << "] [INFO] 日志过大，已清理旧日志\n";
            }
        }
    }
}

void Logger::log(const std::string& tag, const std::string& msg) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!enabled_ || log_path_.empty()) return;

    checkRotation();

    std::ofstream out(log_path_, std::ios::app);
    if (out.is_open()) {
        out << "[" << currentTimestamp() << "] [" << tag << "] " << msg << "\n";
    }
}

void Logger::info(const std::string& msg) {
    log("INFO", msg);
}

void Logger::clean(const std::string& msg) {
    log("CLEAN", msg);
}

void Logger::error(const std::string& msg) {
    log("ERROR", msg);
}

void Logger::skip(const std::string& msg) {
    log("跳过", msg);
}
