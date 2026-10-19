#pragma once
#include <string>
#include <mutex>

class Logger {
public:
    static Logger& instance();

    void init(const std::string& log_path, int max_size_kb, bool enable);
    void updateSettings(int max_size_kb, bool enable);

    void info(const std::string& msg);
    void clean(const std::string& msg);
    void error(const std::string& msg);
    void skip(const std::string& msg);

    void log(const std::string& tag, const std::string& msg);

private:
    Logger() = default;
    void checkRotation();
    static std::string currentTimestamp();

    std::string log_path_;
    int max_size_kb_ = 512;
    bool enabled_ = true;
    std::mutex mutex_;
};
