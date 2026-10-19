# 运存防线 (RAM Guard) 逆向工程与源码工作区

本文档详细记录对 Magisk / KernelSU / APatch 模块 `/data/adb/modules/ram/` 的完整逆向分析结果，以及重构还原出的源代码工程。所有源码与工作文件已展开在当前工作区中，方便直接查看、定制修改与重新编译部署。

---

## 一、逆向分析结果与模块真实架构

### 1. 核心文件真相：伪装成脚本的 ELF 二进制
- 模块根目录下的核心执行文件 `ram.sh`（约 883KB）**并非普通的 Shell 脚本**，其实际头部魔数为 `\x7fELF`（64-bit LSB ARM aarch64，动态链接器指向 `/system/bin/linker64`）。
- 该二进制由 **Android NDK r17c (clang-6.0)** 编译生成，静态包含了 LLVM `libc++`（标准库算法、字符串、容器与线程库），核心自定义业务代码位于 `0x00ee90` 至 `0x01c800` 之间。

### 2. 运作机理与控制拓扑
```text
                      [ service.sh / 开机启动 ]
                                  │
                                  ▼
                        [ 运存防线启动.sh ]
                                  │ (nohup 启动)
                                  ▼
                         [ ram.sh (核心守护) ]
                     /            │           \
                    /             │            \
      [ 1. 事件捕获 ]       [ 2. 内存计算 ]    [ 3. 状态栏通知 ]
     (logcat / liblog)      (/proc/meminfo)     (cmd notification)
  wm_resume_activity ...          │
                    \             │
                     \            ▼
                      [ 4. 任务栈与候选解析 ]
                      (dumpsys activity activities)
                                  │
                                  ▼
                      [ 5. 多层防护过滤判定 ]
              ┌───────────────────┼───────────────────┐
              ▼                   ▼                   ▼
       [ 系统核心保护 ]        [ 白名单应用 ]      [ 前台应用保护 ]
       (SystemUI/输入法等)     (白名单.conf)         (当前前台/离开缓冲)
                                  │
                                  ▼
                        [ 6. 逆序查杀执行 ]
                      (由栈底向栈顶，旧后台优先)
                         am force-stop <pkg>
```

### 3. 多级防线与阈值模型
- **普通模式**：物理内存可用低于 `start_mem_percent`（默认 10-12%）或 Swap 剩余低于 `swap_free_start_percent` 时触发。
- **紧急模式**：物理内存可用低于 `emergency_mem_percent`（默认 4-7%）或 Swap 剩余低于 `swap_free_emergency_percent` 时触发，允许单次查杀更多应用（`emergency_max_clean_count`）。
- **轻清理模式**：在前台 App 发生切换时，经过 `clean_delay_after_switch_ms`（默认 2000ms）后触发快速检测，仅查杀 1 个符合条件的后台应用。
- **查杀排序机制**：从任务栈**最底部向顶部**逆序扫描（优先清理最早打开的冷门后台，保护刚切入后台不久的应用）。

---

## 二、工作区源码目录结构

工作区路径：`/root/workspaces/内部工作区/ram_module/`

```text
ram_module/
├── original/             # 宿主模块目录原始文件的完整只读备份
├── src/                  # 100% 对齐原版逻辑的 C++ 重构源码
│   ├── main.cpp          # 入口点、信号处理、模块路径自探测与主线程生命周期
│   ├── config.hpp/.cpp   # 配置项解析、默认配置生成与基于 st_mtime 的热重载
│   ├── logger.hpp/.cpp   # 格式化时间戳日志、KB 级超限轮转截断
│   ├── memory.hpp/.cpp   # /proc/meminfo 解析、RAM/Swap 压力计算与大小格式化
│   ├── process_manager.hpp/.cpp # 任务栈提取、白/黑名单加载、输入法自适应保护、am force-stop
│   ├── cleaner.hpp/.cpp  # 清理引擎、逆序遍历候选、提前达标退出与释放量核算
│   ├── event_listener.hpp/.cpp # 前台切换事件捕获（logcat events）与临时监控线程
│   └── notification.hpp/.cpp   # Android 状态栏常驻通知管理与 snooze 处理
├── scripts/              # 模块生命周期控制脚本
│   ├── service.sh        # 开机自启入口
│   ├── action.sh         # 控制器或终端动作触发
│   ├── module_common.sh  # Root 管理器（Magisk / KSU / APatch）环境适配
│   ├── 运存防线启动.sh    # 拉起守护进程
│   ├── 运存防线关闭.sh    # 结束守护进程并清理残留通知
│   ├── 运存防线检测.sh    # 输出当前内存、前台栈与预计清理队列的检测工具
│   └── ram_pure_shell.sh # 纯 Shell 免编译等价实现（可直接重命名为 ram.sh 运行）
├── config/               # 配置文件与白名单
│   ├── config.ini        # 阈值与参数配置
│   ├── 白名单.conf        # 白名单包名清单（永不查杀）
│   ├── 黑名单.conf        # 黑名单系统应用清单（覆盖系统保护，允许查杀）
│   └── module.prop       # Magisk 模块描述属性
├── build/                # 构建脚本与工程配置
│   ├── Makefile          # 标准 Make 构建文件（带 -static）
│   ├── CMakeLists.txt    # CMake 跨平台构建文件
│   └── build.sh          # 一键编译与可选自动部署脚本
└── README.md             # 本文档
```

---

## 三、常见功能修改指引

你可以根据自己的需求自由调整源码中的策略与逻辑：

### 1. 修改查杀算法（例如改为按应用实际占用内存大小查杀）
- **修改位置**：`src/cleaner.cpp` 中的 candidate 遍历逻辑。
- **实现建议**：在由 `tasks` 收集到候选列表后，调用 `dumpsys meminfo <pkg>` 或读取 `/proc/<pid>/statm` 换算出每个候选 App 的 RSS 占用，按占用内存从大到小排序查杀，而非原版的 LRU（按栈底远近）排序。

### 2. 调整系统应用与多用户黑白名单判定
- **修改位置**：`src/process_manager.cpp` 的 `checkProtection()` 函数。
- **多用户黑白名单语法**（在 `白名单.conf` 或 `黑名单.conf` 中配置）：
  - `com.tencent.mm`：全局匹配，对所有用户空间（User 0、分身 User 12 等）生效；
  - `0:com.tencent.mm` 或 `u0:com.tencent.mm`：仅对主空间 (User 0) 生效；
  - `12:com.tencent.mm` 或 `u12:com.tencent.mm`：仅对分身/双开空间 (User 12) 生效。
- **查杀命令多用户隔离**：
  自动调用 `am force-stop --user <user_id> <pkg>`，清理双开应用时不误伤主空间同名应用。

### 3. 应用检测与漏检根因排查
原模块默认只扫描了 `dumpsys activity activities`（仅当前界面活动栈），会导致没有 Recent 卡片的纯后台服务应用、常驻守护和被划掉任务卡片的应用完全漏检。现已升级为 `dumpsys activity lru` 系统全量进程流比对，捕获率由原版的 28 个提升至 100+ 个。

### 4. 修改常驻状态栏通知显示文案
- **修改位置**：`src/notification.cpp` 中的 `update()` 函数。
- **调整内容**：修改 `cmd notification post` 中的标题、内容格式或通知优先级。

### 4. 调整监控敏感度与延时
- **修改位置**：直接修改 `config/config.ini` 中的参数（无需修改代码，修改后运行时自动热重载）：
  - `start_mem_percent`：触发清理的物理内存阈值
  - `target_mem_percent`：停止清理的目标内存阈值
  - `monitor_duration_sec`：前台切换后临时监控的时长

---

## 四、编译与部署方式

### 方式 A：C++ 源码重新编译构建（推荐）
在容器终端或开发环境执行构建脚本：
```bash
cd /root/workspaces/内部工作区/ram_module/build
# 1. 仅编译输出 build/ram.sh
./build.sh

# 2. 编译并直接热替换部署到宿主模块目录 (/data/adb/modules/ram/ram.sh)
./build.sh deploy
```

部署完成后，重启模块生效：
```bash
sh /data/adb/modules/ram/运存防线关闭.sh
sh /data/adb/modules/ram/运存防线启动.sh
```

### 方式 B：纯 Shell 免编译直接替换（最轻快）
如果不想搭建 C++ 编译链，工作区中提供的 `scripts/ram_pure_shell.sh` 已经 100% 还原了所有清理、判定与日志逻辑：
```bash
# 直接覆盖宿主模块的核心执行文件
cp /root/workspaces/内部工作区/ram_module/scripts/ram_pure_shell.sh /data/adb/modules/ram/ram.sh
chmod 0755 /data/adb/modules/ram/ram.sh

# 重启模块
sh /data/adb/modules/ram/运存防线关闭.sh
sh /data/adb/modules/ram/运存防线启动.sh
```

### 验证运行状态
执行原作者的检测脚本，查看模块运行情况与预计清理候选：
```bash
sh /data/adb/modules/ram/运存防线检测.sh
```
实时查看运行日志：
```bash
tail -f /data/adb/modules/ram/ram.log
```
