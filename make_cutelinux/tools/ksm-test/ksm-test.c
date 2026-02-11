#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/mman.h>
#include <errno.h>
#include <string.h>
#include <stdint.h>

#define PAGE_SIZE       4096
#define BLOCK_SIZE      (PAGE_SIZE * 8)   // 每个块 8 个页面（可调大）
#define NUM_BLOCKS      200               // 申请 200 个块（200 × 32 KB = 6400 KB）

int main(void)
{
    void *base;
    size_t total_size = NUM_BLOCKS * BLOCK_SIZE;

    printf("正在申请 %zu 页匿名内存（约 %.1f MB）...\n",
            total_size / PAGE_SIZE, total_size / (1024.0 * 1024));

    // 使用 mmap 分配大块匿名私有内存
    base = mmap(NULL, total_size, PROT_READ | PROT_WRITE,
            MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (base == MAP_FAILED) {
        perror("mmap 失败");
        return 1;
    }

    // 用全A填充（最容易被 KSM 合并的内容）
    printf("用全A填充内存...\n");
    memset(base, 'A', total_size);

    // 关键步骤：标记为可被 KSM 合并
    printf("调用 madvise(MADV_MERGEABLE) ...\n");
    if (madvise(base, total_size, MADV_MERGEABLE) == -1) {
        perror("madvise MADV_MERGEABLE 失败");
        // 常见原因：内核没开 CONFIG_KSM，或者权限不足
        goto cleanup;
    }

    printf("内存已标记为可合并。现在你可以观察 /sys/kernel/mm/ksm/\n");
    printf("pages_shared 和 pages_sharing 是否开始增长。\n");
    printf("\n程序将挂起 60 秒（按 Ctrl+C 退出）...\n\n");

    // 保持进程存活，让 ksmd 有时间扫描和合并
    sleep(60);

cleanup:
    printf("清理中...\n");
    // 可选：取消合并标记（演示用）
    // madvise(base, total_size, MADV_UNMERGEABLE);

    if (munmap(base, total_size) == -1) {
        perror("munmap 失败");
    }

    return 0;
}
