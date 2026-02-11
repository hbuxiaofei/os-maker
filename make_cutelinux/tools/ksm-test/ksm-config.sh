#!/bin/sh

# 重要前置条件（必须满足，否则程序无效）
# - 内核必须开启 CONFIG_KSM=y（大多数发行版的虚拟化/服务器内核都默认开启）
# - 以 root 权限执行以下命令启用 ksmd（如果尚未启用）：
#
# ```bash
# echo 1 > /sys/kernel/mm/ksm/run
# echo 500 > /sys/kernel/mm/ksm/pages_to_scan    # 建议调大一点
# echo 50 > /sys/kernel/mm/ksm/sleep_millisecs   # 加快扫描
# ```
#
#  观察合并效果（在另一个终端反复执行）：
#
#  ```bash
#  watch -n 1 "cat /sys/kernel/mm/ksm/pages_shared /sys/kernel/mm/ksm/pages_sharing"
#  ```
#
#  当 pages_sharing 明显大于 pages_shared 时，说明合并正在生效。

# 每十秒执行一次, 同步当前所有文件到远程 (rsync端口号默认 873)
# watch -n 10 rsync -av ./ rsync://127.0.0.1/share

echo 1 > /sys/kernel/mm/ksm/run

watch -n 1 "cat /sys/kernel/mm/ksm/pages_shared /sys/kernel/mm/ksm/pages_sharing"

exit 0
