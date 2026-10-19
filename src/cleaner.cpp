#include "cleaner.hpp"
#include "process_manager.hpp"
#include "logger.hpp"
#include "notification.hpp"
#include <thread>
#include <algorithm>

CleanerEngine& CleanerEngine::instance() {
    static CleanerEngine inst;
    return inst;
}

bool CleanerEngine::checkAndClean(bool is_fast_switch) {
    auto& cfg_mgr = ConfigManager::instance();
    cfg_mgr.checkAndReload();
    const auto& cfg = cfg_mgr.get();

    // 检查普通模式冷却时间
    auto now = std::chrono::steady_clock::now();
    if (!is_fast_switch && last_clean_time_.time_since_epoch().count() > 0) {
        auto elapsed_sec = std::chrono::duration_cast<std::chrono::seconds>(now - last_clean_time_).count();
        if (elapsed_sec < cfg.clean_cooldown_sec) {
            return false;
        }
    }

    MemorySnapshot snap_before;
    if (!MemoryReader::read(snap_before)) {
        return false;
    }

    int avail = snap_before.availPercent();
    int swap_free = snap_before.swapFreePercent();

    // 内存压力判定：物理内存不足 或 Swap/ZRAM 不足
    bool mem_pressure = (avail < cfg.start_mem_percent);
    bool swap_pressure = (snap_before.hasSwap() && swap_free < cfg.swap_free_start_percent);

    if (!mem_pressure && !swap_pressure) {
        return false; // 无内存压力
    }

    // 模式判定
    CleanMode mode = CleanMode::Normal;
    std::string mode_str = "普通";
    int max_clean = cfg.max_clean_count;

    if (avail < cfg.emergency_mem_percent || (snap_before.hasSwap() && swap_free < cfg.swap_free_emergency_percent)) {
        mode = CleanMode::Emergency;
        mode_str = "紧急";
        max_clean = cfg.emergency_max_clean_count;
    } else if (is_fast_switch) {
        mode = CleanMode::Light;
        mode_str = "轻清理";
        max_clean = 1;
    }

    std::string swap_str = snap_before.hasSwap() ? (std::to_string(swap_free) + "%") : "无";
    if (is_fast_switch) {
        Logger::instance().info("快速切换内存压力：可用内存=" + std::to_string(avail) + "%，模式=" + mode_str);
    } else {
        Logger::instance().info("内存压力：可用内存=" + std::to_string(avail) + "%，Swap/ZRAM剩余=" + swap_str + "，模式=" + mode_str);
    }

    // 获取运行应用列表（带用户空间标识）
    std::vector<AppTask> tasks;
    AppTask foreground;
    if (!ProcessManager::instance().getRunningTaskPackages(tasks, foreground)) {
        return false;
    }

    // 由任务栈底（最早打开的应用）向上逆序遍历
    int cleaned_count = 0;
    std::vector<std::string> remaining_predict;

    for (int i = static_cast<int>(tasks.size()) - 1; i >= 0; --i) {
        const AppTask& task = tasks[i];
        std::string app_label = "[u" + std::to_string(task.user_id) + "] " + task.package_name;

        std::string reason;
        ProtectionType prot = ProcessManager::instance().checkProtection(task.user_id, task.package_name, reason);

        if (prot != ProtectionType::Killable && prot != ProtectionType::BlacklistSystemApp) {
            Logger::instance().skip(reason + "：" + app_label);
            continue;
        }

        // 达到本次上限则记录到“下次预计清理”
        if (cleaned_count >= max_clean) {
            remaining_predict.push_back(app_label);
            continue;
        }

        // 针对特定多用户空间执行查杀 (am force-stop --user <user_id> <pkg>)
        ProcessManager::instance().forceStopApp(task.user_id, task.package_name);
        if (prot == ProtectionType::BlacklistSystemApp) {
            Logger::instance().clean((mode == CleanMode::Light ? "轻清理黑名单：" : "已清理黑名单：") + app_label);
        } else {
            Logger::instance().clean((mode == CleanMode::Light ? "轻清理：" : "已清理：") + app_label);
        }
        cleaned_count++;

        // 清理间歇等待
        if (cfg.clean_interval_ms > 0) {
            std::this_thread::sleep_for(std::chrono::milliseconds(cfg.clean_interval_ms));
        }

        // 动态检查是否已经达到物理内存目标阈值
        MemorySnapshot snap_cur;
        if (MemoryReader::read(snap_cur) && snap_cur.availPercent() >= cfg.target_mem_percent) {
            break;
        }
    }

    if (cleaned_count == 0) {
        Logger::instance().info("未清理：没有符合条件的后台应用");
        return false;
    }

    // 清理后评估与记录：同时计算物理内存释放量与 ZRAM 释放量
    MemorySnapshot snap_after;
    MemoryReader::read(snap_after);
    long freed_kb = snap_after.mem_available_kb - snap_before.mem_available_kb;
    if (freed_kb < 0) freed_kb = 0;

    long zram_freed_kb = snap_after.swap_free_kb - snap_before.swap_free_kb;
    if (zram_freed_kb < 0) zram_freed_kb = 0;

    total_freed_kb_ += freed_kb;
    total_zram_freed_kb_ += zram_freed_kb;
    total_clean_count_ += cleaned_count;

    std::string freed_str = MemoryReader::formatSize(freed_kb);
    std::string zram_freed_str = MemoryReader::formatSize(zram_freed_kb);

    std::string finish_tag = (mode == CleanMode::Light ? "轻清理完成：" : "清理完成：");
    std::string finish_msg = finish_tag + "可用内存 " + std::to_string(avail) + "% → " +
                             std::to_string(snap_after.availPercent()) + "% (释放约 " + freed_str + ")";
    if (snap_before.hasSwap()) {
        finish_msg += "，ZRAM " + std::to_string(swap_free) + "% → " +
                      std::to_string(snap_after.swapFreePercent()) + "% (回收约 " + zram_freed_str + ")";
    }
    finish_msg += "，清理数量=" + std::to_string(cleaned_count);
    Logger::instance().info(finish_msg);

    // 输出下次预计清理
    if (!remaining_predict.empty()) {
        std::string pred_list;
        for (size_t k = 0; k < remaining_predict.size() && k < 5; ++k) {
            if (!pred_list.empty()) pred_list += ", ";
            pred_list += remaining_predict[k];
        }
        Logger::instance().info("下次预计清理：" + pred_list);
    }

    NotificationManager::instance().update(total_clean_count_, freed_kb, total_freed_kb_);
    last_clean_time_ = std::chrono::steady_clock::now();
    return true;
}
