# Linux 内核 KSM (Kernel Samepage Merging) 代码详解

## 📚 目录
1. [KSM 简介](#1-ksm-简介)
2. [核心数据结构](#2-核心数据结构)
3. [关键函数详解](#3-关键函数详解)
4. [工作流程](#4-工作流程)
5. [代码段注释](#5-代码段注释)

---

## 1. KSM 简介

### 1.1 什么是 KSM?
KSM (Kernel Samepage Merging) 是 Linux 内核的一个内存去重特性。它会扫描内存,找出内容相同的页面并合并它们,从而节省物理内存。

### 1.2 使用场景
- **虚拟化环境**: 多个虚拟机运行相同的操作系统
- **容器**: 多个容器使用相同的基础镜像
- **重复数据**: 应用程序加载多份相同的库或数据

### 1.3 核心机制
```
普通页面 → 扫描 → 发现重复 → 合并 → KSM页面(写保护)
                                      ↓
                              写入时复制(COW)
                                      ↓
                              恢复为独立页面
```

---

## 2. 核心数据结构

### 2.1 struct mm_slot
```c
/**
 * struct mm_slot - 每个被扫描的进程内存描述符的KSM信息
 * @link: 链接到mm_slots哈希表
 * @mm_list: 链接到全局mm_slots链表
 * @rmap_list: 该进程的反向映射项链表
 * @mm: 指向进程的mm_struct
 *
 * 作用: 记录每个参与KSM的进程
 */
struct mm_slot {
    struct hlist_node link;       // 哈希表节点
    struct list_head mm_list;     // 双向链表节点
    struct rmap_item *rmap_list;  // 该进程的rmap项列表
    struct mm_struct *mm;         // 进程的内存描述符
};
```

**解释:**
- 每个调用 `madvise(MADV_MERGEABLE)` 的进程都会有一个 mm_slot
- KSM 通过 mm_slot 管理所有需要扫描的进程

### 2.2 struct rmap_item
```c
/**
 * struct rmap_item - 虚拟地址的反向映射项
 * @rmap_list: 链接到mm_slot的rmap列表
 * @anon_vma: 稳定状态时指向anon_vma
 * @mm: 所属的进程mm
 * @address: 虚拟地址 + 状态标志位
 * @oldchecksum: 页面的旧校验和
 * @node: 红黑树节点(用于不稳定树)
 * @head: 指向稳定树节点
 * @hlist: 挂在稳定节点上的链表
 *
 * 作用: 代表一个被跟踪的虚拟页面
 */
struct rmap_item {
    struct rmap_item *rmap_list;
    union {
        struct anon_vma *anon_vma;  /* 稳定时 */
        int nid;                        /* 不稳定树节点ID */
    };
    struct mm_struct *mm;           // 所属进程
    unsigned long address;          // 虚拟地址 + 标志
    unsigned int oldchecksum;       // 旧校验和
    union {
        struct rb_node node;        // 不稳定树节点
        struct {                    // 稳定树状态
            struct stable_node *head;
            struct hlist_node hlist;
        };
    };
};
```

**关键点:**
- `address` 的低位存储状态标志:
  - `STABLE_FLAG (0x200)`: 页面在稳定树中
  - `UNSTABLE_FLAG (0x100)`: 页面在不稳定树中
  - `SEQNR_MASK (0x0ff)`: 扫描序列号
- 一个 rmap_item 代表一个被 KSM 跟踪的虚拟页面

### 2.3 struct stable_node
```c
/**
 * struct stable_node - 稳定树中的节点
 * @node: 红黑树节点
 * @hlist: 使用该KSM页面的所有rmap_item链表
 * @kpfn: 该KSM页面的物理页帧号
 * @rmap_hlist_len: 共享该页面的虚拟页面数量
 * @nid: NUMA节点ID
 *
 * 作用: 代表一个已合并的KSM页面
 */
struct stable_node {
    union {
        struct rb_node node;        // 红黑树节点
        struct {                    // 迁移状态
            struct list_head *head;
            struct {
                struct hlist_node hlist_dup;
                struct list_head list;
            };
        };
    };
    struct hlist_head hlist;        // 反向映射链表头
    union {
        unsigned long kpfn;         // 页帧号
        unsigned long chain_prune_time; // 链修剪时间
    };
    int rmap_hlist_len;             // 共享计数
    int nid;                        // NUMA节点
};
```

**解释:**
- 稳定树中的每个节点代表一个实际的KSM页面
- `hlist` 链接了所有映射到该物理页面的虚拟页面
- `rmap_hlist_len` 记录有多少虚拟页面共享这个物理页面

### 2.4 struct ksm_scan
```c
/**
 * struct ksm_scan - 扫描游标
 * @mm_slot: 当前正在扫描的进程
 * @address: 当前扫描的虚拟地址
 * @rmap_list: 当前扫描的rmap项指针
 * @seqnr: 完整扫描轮次计数
 *
 * 作用: 记录KSM扫描进度
 */
struct ksm_scan {
    struct mm_slot *mm_slot;        // 当前进程
    unsigned long address;          // 当前地址
    struct rmap_item **rmap_list;   // 当前rmap项
    unsigned long seqnr;            // 扫描序列号
};
```

---

## 3. 关键函数详解

### 3.1 ksm_scan_thread() - KSM主线程
```c
/**
 * ksm_scan_thread - KSM守护线程
 *
 * 工作流程:
 * 1. 循环等待,直到需要扫描
 * 2. 调用 ksm_do_scan() 扫描一批页面
 * 3. 休眠指定时间
 * 4. 重复
 *
 * 作用: KSM的核心工作线程
 */
static int ksm_scan_thread(void *nothing)
{
    set_freezable();              // 允许被冻结
    set_user_nice(current, 5);    // 设置低优先级

    while (!kthread_should_stop()) {
        mutex_lock(&ksm_thread_mutex);
        wait_while_offlining();   // 等待内存热拔插完成

        if (ksmd_should_run())    // 检查是否应该运行
            ksm_do_scan(ksm_thread_pages_to_scan); // 扫描页面

        mutex_unlock(&ksm_thread_mutex);

        try_to_freeze();          // 尝试冻结

        if (ksmd_should_run()) {
            // 休眠指定时间
            schedule_timeout_interruptible(
                msecs_to_jiffies(ksm_thread_sleep_millisecs));
        } else {
            // 等待唤醒信号
            wait_event_freezable(ksm_thread_wait,
                ksmd_should_run() || kthread_should_stop());
        }
    }
    return 0;
}
```

### 3.2 cmp_and_merge_page() - 比较和合并页面
```c
/**
 * cmp_and_merge_page - 比较并合并页面
 * @page: 要处理的页面
 * @rmap_item: 页面的反向映射项
 *
 * 工作流程:
 * 1. 先在稳定树中查找匹配的KSM页面
 * 2. 如果找到,尝试合并到该KSM页面
 * 3. 如果没找到,在不稳定树中查找
 * 4. 如果在不稳定树中找到匹配,创建新的KSM页面
 * 5. 如果都没找到,将页面加入不稳定树等待下次扫描
 *
 * 作用: KSM合并的核心逻辑
 */
static void cmp_and_merge_page(struct page *page, struct rmap_item *rmap_item)
{
    struct page *kpage;

    // 1. 在稳定树中查找
    kpage = stable_tree_search(page);
    if (kpage) {
        // 找到匹配的KSM页面,尝试合并
        err = try_to_merge_with_ksm_page(rmap_item, page, kpage);
        if (!err) {
            // 合并成功,将rmap_item加入稳定树
            lock_page(kpage);
            stable_tree_append(rmap_item, page_stable_node(kpage), false);
            unlock_page(kpage);
        }
        put_page(kpage);
        return;
    }

    // 2. 在不稳定树中查找
    tree_rmap_item = unstable_tree_search_insert(rmap_item, page, &tree_page);
    if (tree_rmap_item) {
        // 找到匹配,创建新的KSM页面
        kpage = try_to_merge_two_pages(rmap_item, page,
                                        tree_rmap_item, tree_page);
        if (kpage) {
            // 合并成功,插入稳定树
            lock_page(kpage);
            stable_node = stable_tree_insert(kpage);
            if (stable_node) {
                stable_tree_append(tree_rmap_item, stable_node, false);
                stable_tree_append(rmap_item, stable_node, false);
            }
            unlock_page(kpage);
            put_page(kpage);
        }
        put_page(tree_page);
    }
    // 否则页面已被加入不稳定树,等待下次扫描
}
```

### 3.3 try_to_merge_one_page() - 合并单个页面
```c
/**
 * try_to_merge_one_page - 尝试将页面合并到KSM页面
 * @vma: 虚拟内存区域
 * @page: 源页面
 * @kpage: 目标KSM页面
 *
 * 工作流程:
 * 1. 检查两个页面的内容是否完全相同
 * 2. 将页表项指向KSM页面
 * 3. 设置写保护位
 * 4. 释放原页面
 *
 * 返回: 成功返回0,失败返回错误码
 */
static int try_to_merge_one_page(struct vm_area_struct *vma,
                                  struct page *page,
                                  struct page *kpage)
{
    // 1. 锁定页面
    if (!trylock_page(page))
        return -EBUSY;

    // 2. 比较页面内容
    if (memcmp_pages(page, kpage)) {
        unlock_page(page);
        return -EFAULT;
    }

    // 3. 替换页表项
    err = replace_page(vma, page, kpage, orig_pte);

    unlock_page(page);
    return err;
}
```

### 3.4 stable_tree_search() - 稳定树查找
```c
/**
 * stable_tree_search - 在稳定树中查找匹配页面
 * @page: 要查找的页面
 *
 * 工作原理:
 * 1. 计算页面所属的NUMA节点
 * 2. 在对应的稳定树中进行二叉搜索
 * 3. 使用memcmp_pages()比较页面内容
 * 4. 找到匹配则返回KSM页面
 *
 * 返回: 匹配的KSM页面或NULL
 */
static struct page *stable_tree_search(struct page *page)
{
    int nid = get_kpfn_nid(page_to_pfn(page));
    struct rb_root *root = root_stable_tree + nid;
    struct rb_node **new = &root->rb_node;

    while (*new) {
        struct stable_node *stable_node;
        struct page *tree_page;
        int ret;

        // 获取当前节点
        stable_node = rb_entry(*new, struct stable_node, node);
        tree_page = get_ksm_page(stable_node, false);

        // 比较页面内容
        ret = memcmp_pages(page, tree_page);
        put_page(tree_page);

        if (ret < 0)
            new = &(*new)->rb_left;   // 往左子树
        else if (ret > 0)
            new = &(*new)->rb_right;  // 往右子树
        else
            return tree_page;         // 找到匹配
    }

    return NULL;  // 没找到
}
```

---

## 4. 工作流程

### 4.1 初始化流程
```
ksm_init()
    │
    ├─→ ksm_slab_init()          # 创建slab缓存
    │       ├─ rmap_item_cache
    │       ├─ stable_node_cache
    │       └─ mm_slot_cache
    │
    ├─→ kthread_run(ksm_scan_thread)  # 启动ksmd线程
    │
    └─→ sysfs_create_group()     # 创建sysfs接口
            ├─ /sys/kernel/mm/ksm/run
            ├─ /sys/kernel/mm/ksm/pages_to_scan
            ├─ /sys/kernel/mm/ksm/sleep_millisecs
            └─ ...
```

### 4.2 应用程序注册流程
```
应用程序调用 madvise(addr, len, MADV_MERGEABLE)
    │
    ↓
do_madvise()
    │
    ↓
ksm_madvise()
    │
    ↓
__ksm_enter(mm)
    │
    ├─→ alloc_mm_slot()           # 分配mm_slot
    │
    ├─→ insert_to_mm_slots_hash() # 加入哈希表
    │
    ├─→ list_add_tail()           # 加入扫描列表
    │
    └─→ wake_up_interruptible()   # 唤醒ksmd线程
```

### 4.3 KSM扫描流程
```
ksmd线程循环:
    │
    ├─→ ksm_do_scan(pages_to_scan)
    │       │
    │       └─→ for (i = 0; i < pages_to_scan; i++)
    │               │
    │               ├─→ scan_get_next_rmap_item(&page)
    │               │       │
    │               │       ├─ 遍历mm_slot列表
    │               │       ├─ 遍历VMA
    │               │       ├─ follow_page()获取页面
    │               │       └─ 返回rmap_item
    │               │
    │               └─→ cmp_and_merge_page(page, rmap_item)
    │                       │
    │                       ├─ stable_tree_search()  # 稳定树查找
    │                       │
    │                       ├─ unstable_tree_search_insert()  # 不稳定树
    │                       │
    │                       └─ try_to_merge_*()  # 执行合并
    │
    └─→ schedule_timeout(sleep_millisecs)  # 休眠
```

### 4.4 页面合并详细流程
```
发现两个内容相同的页面 (pageA 和 pageB)
    │
    ↓
try_to_merge_two_pages(pageA, pageB)
    │
    ├─→ 将pageA设为写保护
    │
    ├─→ 修改pageB的页表,指向pageA
    │
    ├─→ 设置pageB的页表项为只读
    │
    ├─→ 释放pageB的物理页面
    │
    └─→ 创建stable_node,加入稳定树
            │
            └─→ pageA成为KSM页面

当有进程尝试写入KSM页面时:
    │
    ↓
page_fault_handler()
    │
    ↓
do_wp_page()  # 写保护页面错误处理
    │
    ├─→ 分配新页面 (newpage)
    │
    ├─→ 复制KSM页面内容到newpage
    │
    ├─→ 修改页表,指向newpage
    │
    └─→ 清除写保护位
```

---

## 5. 代码段注释

### 5.1 头文件和宏定义部分
```c
/* ========== 文件头注释 ========== */
/*
 * Memory merging support.
 * 内存合并支持
 *
 * This code enables dynamic sharing of identical pages found in different
 * memory areas, even if they are not shared by fork()
 * 这段代码实现了在不同内存区域中找到的相同页面的动态共享,
 * 即使这些页面不是通过 fork() 共享的
 */

/* ========== 头文件包含 ========== */
#include <linux/errno.h>      /* 错误码定义 */
#include <linux/mm.h>          /* 内存管理核心 */
#include <linux/fs.h>          /* 文件系统接口 */
#include <linux/mman.h>        /* 内存映射 */
#include <linux/sched.h>       /* 进程调度 */
#include <linux/rwsem.h>       /* 读写信号量 */
#include <linux/pagemap.h>     /* 页缓存 */
#include <linux/rmap.h>        /* 反向映射 */
#include <linux/spinlock.h>    /* 自旋锁 */
#include <linux/jhash.h>       /* 哈希函数 */
#include <linux/delay.h>       /* 延迟函数 */
#include <linux/kthread.h>     /* 内核线程 */
#include <linux/wait.h>        /* 等待队列 */
#include <linux/slab.h>        /* slab分配器 */
#include <linux/rbtree.h>      /* 红黑树 */
#include <linux/memory.h>      /* 内存管理 */
#include <linux/mmu_notifier.h>/* MMU通知 */
#include <linux/swap.h>        /* 交换 */
#include <linux/ksm.h>         /* KSM接口 */
#include <linux/hashtable.h>   /* 哈希表 */
#include <linux/freezer.h>     /* 进程冻结 */
#include <linux/oom.h>         /* OOM killer */
#include <linux/numa.h>        /* NUMA支持 */

/* ========== NUMA相关宏 ========== */
#ifdef CONFIG_NUMA
#define NUMA(x)     (x)          /* NUMA开启时,使用参数x */
#define DO_NUMA(x)  do { (x); } while (0)  /* 执行NUMA相关代码 */
#else
#define NUMA(x)     (0)          /* NUMA关闭时,返回0 */
#define DO_NUMA(x)  do { } while (0)       /* 不执行 */
#endif

/* ========== 地址标志位 ========== */
#define SEQNR_MASK  0x0ff    /* 扫描序列号掩码 (低8位) */
#define UNSTABLE_FLAG   0x100  /* 不稳定树标志 (第9位) */
#define STABLE_FLAG 0x200    /* 稳定树标志 (第10位) */

/* ========== KSM运行状态 ========== */
#define KSM_RUN_STOP    0     /* 停止KSM */
#define KSM_RUN_MERGE   1     /* 运行并合并 */
#define KSM_RUN_UNMERGE 2     /* 解除所有合并 */
#define KSM_RUN_OFFLINE 4     /* 内存热拔插中 */

/* ========== 稳定节点链标记 ========== */
#define STABLE_NODE_CHAIN -1024  /* 标记节点为链头 */

/* ========== 哈希表大小 ========== */
#define MM_SLOTS_HASH_BITS 10   /* 2^10 = 1024个桶 */

/* ========== slab缓存创建宏 ========== */
#define KSM_KMEM_CACHE(__struct, __flags) \
    kmem_cache_create("ksm_"#__struct, \
        sizeof(struct __struct), __alignof__(struct __struct), \
        (__flags), NULL)
```

### 5.2 全局变量部分
```c
/* ========== 红黑树根节点 ========== */
/*
 * 稳定树: 存储已合并的KSM页面
 * 不稳定树: 存储候选合并页面,每轮扫描后重建
 */
static struct rb_root one_stable_tree[1] = { RB_ROOT };
static struct rb_root one_unstable_tree[1] = { RB_ROOT };
static struct rb_root *root_stable_tree = one_stable_tree;
static struct rb_root *root_unstable_tree = one_unstable_tree;

/* ========== 迁移节点列表 ========== */
/*
 * 当页面被迁移到其他NUMA节点时,临时存放在这里
 */
static LIST_HEAD(migrate_nodes);

/* ========== mm_slots哈希表 ========== */
/*
 * 哈希表用于快速查找进程的mm_slot
 */
static DEFINE_HASHTABLE(mm_slots_hash, MM_SLOTS_HASH_BITS);

/* ========== mm_slots链表头 ========== */
/*
 * 所有参与KSM的进程通过这个链表串联
 */
static struct mm_slot ksm_mm_head = {
    .mm_list = LIST_HEAD_INIT(ksm_mm_head.mm_list),
};

/* ========== 扫描游标 ========== */
/*
 * 记录当前扫描到哪个进程的哪个地址
 */
static struct ksm_scan ksm_scan = {
    .mm_slot = &ksm_mm_head,
};

/* ========== slab缓存 ========== */
/*
 * 用于高效分配频繁使用的数据结构
 */
static struct kmem_cache *rmap_item_cache;    /* rmap_item缓存 */
static struct kmem_cache *stable_node_cache;  /* stable_node缓存 */
static struct kmem_cache *mm_slot_cache;      /* mm_slot缓存 */

/* ========== 统计信息 ========== */
static unsigned long ksm_pages_shared;    /* 已共享的物理页面数 */
static unsigned long ksm_pages_sharing;   /* 共享的虚拟页面数 */
static unsigned long ksm_pages_unshared;  /* 候选但未共享的页面数 */
static unsigned long ksm_rmap_items;      /* rmap_item总数 */

/* ========== 可调参数 ========== */
static unsigned int ksm_thread_pages_to_scan = 100;  /* 每批扫描页数 */
static unsigned int ksm_thread_sleep_millisecs = 20; /* 批次间休眠时间 */
static unsigned long ksm_run = KSM_RUN_STOP;  /* 运行状态 */

/* ========== 同步原语 ========== */
static DECLARE_WAIT_QUEUE_HEAD(ksm_thread_wait);  /* ksmd等待队列 */
static DEFINE_MUTEX(ksm_thread_mutex);  /* ksm线程互斥锁 */
static DEFINE_SPINLOCK(ksm_mmlist_lock); /* mm列表自旋锁 */
```

### 5.3 辅助函数部分
```c
/* ========== NUMA节点相关 ========== */
/**
 * get_kpfn_nid - 获取页帧号对应的NUMA节点
 * @kpfn: 页帧号
 *
 * 作用: 确定页面属于哪个NUMA节点
 */
static inline int get_kpfn_nid(unsigned long kpfn)
{
    return ksm_merge_across_nodes ? 0 : NUMA(pfn_to_nid(kpfn));
}

/* ========== 内存分配/释放 ========== */
/**
 * alloc_rmap_item - 分配rmap_item
 *
 * 使用slab缓存分配,比kmalloc更高效
 */
static struct rmap_item *alloc_rmap_item(void)
{
    struct rmap_item *rmap_item;

    rmap_item = kmem_cache_zalloc(rmap_item_cache,
                                  GFP_KERNEL | __GFP_NORETRY | __GFP_NOWARN);
    if (rmap_item)
        ksm_rmap_items++;  /* 更新统计 */
    return rmap_item;
}

/**
 * free_rmap_item - 释放rmap_item
 * @rmap_item: 要释放的项
 */
static inline void free_rmap_item(struct rmap_item *rmap_item)
{
    ksm_rmap_items--;  /* 更新统计 */
    rmap_item->mm = NULL;  /* 调试用,防止野指针 */
    kmem_cache_free(rmap_item_cache, rmap_item);
}

/**
 * alloc_stable_node - 分配稳定节点
 */
static struct stable_node *alloc_stable_node(void)
{
    return kmem_cache_alloc(stable_node_cache, GFP_KERNEL);
}

/**
 * free_stable_node - 释放稳定节点
 * @stable_node: 要释放的节点
 */
static inline void free_stable_node(struct stable_node *stable_node)
{
    kmem_cache_free(stable_node_cache, stable_node);
}
```

### 5.4 核心功能函数
```c
/**
 * get_ksm_page - 获取KSM页面
 * @stable_node: 稳定节点
 * @lock_it: 是否锁定页面
 *
 * 功能:
 * 1. 从stable_node获取物理页面
 * 2. 验证页面映射是否仍然有效
 * 3. 增加页面引用计数
 * 4. 可选地锁定页面
 *
 * 返回: 成功返回page,失败返回NULL
 *
 * 注意: 页面可能被迁移或解除映射,需要多次检查
 */
static struct page *get_ksm_page(struct stable_node *stable_node, bool lock_it)
{
    struct page *page;
    void *expected_mapping;
    unsigned long kpfn;

    /* 期望的映射标记: stable_node地址 | KSM标志 */
    expected_mapping = (void *)((unsigned long)stable_node |
                                PAGE_MAPPING_KSM);
again:
    /* 读取页帧号 */
    kpfn = READ_ONCE(stable_node->kpfn);
    page = pfn_to_page(kpfn);

    /* 检查映射是否匹配 */
    if (READ_ONCE(page->mapping) != expected_mapping)
        goto stale;  /* 页面已失效 */

    /* 尝试增加引用计数 */
    if (!get_page_unless_zero(page))
        goto stale;  /* 页面正在释放 */

    /* 再次检查映射(可能被并发修改) */
    if (READ_ONCE(page->mapping) != expected_mapping) {
        put_page(page);
        goto stale;
    }

    /* 如果需要锁定页面 */
    if (lock_it) {
        lock_page(page);
        /* 锁定后再次验证 */
        if (READ_ONCE(page->mapping) != expected_mapping) {
            unlock_page(page);
            put_page(page);
            goto stale;
        }
    }

    return page;

stale:
    /* 页面失效,从稳定树中移除节点 */
    remove_node_from_stable_tree(stable_node);
    return NULL;
}

/**
 * remove_rmap_item_from_tree - 从树中移除rmap_item
 * @rmap_item: 要移除的项
 *
 * 功能:
 * 1. 判断rmap_item在稳定树还是不稳定树中
 * 2. 从相应的树中移除
 * 3. 更新统计信息
 * 4. 清理相关数据结构
 */
static void remove_rmap_item_from_tree(struct rmap_item *rmap_item)
{
    if (rmap_item->address & STABLE_FLAG) {
        /* 在稳定树中 */
        struct stable_node *stable_node;
        struct page *page;

        stable_node = rmap_item->head;
        page = get_ksm_page(stable_node, true);
        if (!page)
            goto out;

        /* 从stable_node的链表中移除 */
        hlist_del(&rmap_item->hlist);
        unlock_page(page);
        put_page(page);

        /* 更新统计 */
        if (!hlist_empty(&stable_node->hlist))
            ksm_pages_sharing--;  /* 还有其他页面共享 */
        else
            ksm_pages_shared--;   /* 最后一个共享页面 */

        VM_BUG_ON(stable_node->rmap_hlist_len <= 0);
        stable_node->rmap_hlist_len--;

        /* 释放anon_vma引用 */
        put_anon_vma(rmap_item->anon_vma);
        rmap_item->address &= PAGE_MASK;  /* 清除标志位 */

    } else if (rmap_item->address & UNSTABLE_FLAG) {
        /* 在不稳定树中 */
        unsigned char age;

        /* 计算年龄(当前扫描序号 - rmap_item序号) */
        age = (unsigned char)(ksm_scan.seqnr - rmap_item->address);
        BUG_ON(age > 1);  /* 不应该超过1轮 */

        if (!age) {
            /* 是当前轮次的,从红黑树中删除 */
            rb_erase(&rmap_item->node,
                     root_unstable_tree + NUMA(rmap_item->nid));
        }

        ksm_pages_unshared--;  /* 更新统计 */
        rmap_item->address &= PAGE_MASK;  /* 清除标志位 */
    }
out:
    cond_resched();  /* 可能耗时较长,主动让出CPU */
}

/**
 * remove_trailing_rmap_items - 移除mm_slot中的尾部rmap项
 * @mm_slot: 内存槽
 * @rmap_list: rmap列表的指针的指针
 *
 * 功能: 从*rmap_list开始,删除并释放所有后续的rmap_items
 *
 * 使用场景:
 * - VMA被unmap
 * - 进程退出
 * - 扫描完一个mm
 */
static void remove_trailing_rmap_items(struct mm_slot *mm_slot,
                                        struct rmap_item **rmap_list)
{
    while (*rmap_list) {
        struct rmap_item *rmap_item = *rmap_list;
        *rmap_list = rmap_item->rmap_list;  /* 移动到下一个 */
        remove_rmap_item_from_tree(rmap_item);  /* 从树中移除 */
        free_rmap_item(rmap_item);  /* 释放内存 */
    }
}

/**
 * unmerge_ksm_pages - 解除VMA中的KSM页面合并
 * @vma: 虚拟内存区域
 * @start: 起始地址
 * @end: 结束地址
 *
 * 功能: 遍历地址范围,将所有KSM页面恢复为普通匿名页面
 *
 * 原理:
 * 1. 对每个KSM页面触发写保护错误
 * 2. COW机制会自动分配新页面
 * 3. KSM页面的引用计数减1
 */
static int unmerge_ksm_pages(struct vm_area_struct *vma,
                             unsigned long start, unsigned long end)
{
    unsigned long addr;
    int err = 0;

    /* 遍历每个页面 */
    for (addr = start; addr < end && !err; addr += PAGE_SIZE) {
        /* 检查进程是否正在退出 */
        if (ksm_test_exit(vma->vm_mm))
            break;
        /* 检查是否收到信号 */
        if (signal_pending(current))
            err = -ERESTARTSYS;
        else
            err = break_ksm(vma, addr);  /* 打破KSM页面 */
    }
    return err;
}
```

---

## 6. sysfs接口

### 6.1 可调参数
```bash
# KSM运行状态
/sys/kernel/mm/ksm/run
    0 - 停止
    1 - 运行
    2 - 解除所有合并

# 每批扫描的页面数
/sys/kernel/mm/ksm/pages_to_scan
    默认: 100

# 批次间休眠时间(毫秒)
/sys/kernel/mm/ksm/sleep_millisecs
    默认: 20
```

### 6.2 统计信息
```bash
# 已共享的物理页面数
/sys/kernel/mm/ksm/pages_shared

# 共享的虚拟页面数
/sys/kernel/mm/ksm/pages_sharing

# 候选但未共享的页面数
/sys/kernel/mm/ksm/pages_unshared

# 易变的页面数(经常变化的)
/sys/kernel/mm/ksm/pages_volatile

# 完整扫描轮次
/sys/kernel/mm/ksm/full_scans
```

---

## 7. 使用示例

### 7.1 C程序示例
```c
#include <sys/mman.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    size_t size = 1024 * 1024;  // 1MB

    // 分配匿名内存
    void *addr = mmap(NULL, size, PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (addr == MAP_FAILED) {
        perror("mmap");
        return 1;
    }

    // 填充数据
    memset(addr, 'A', size);

    // 标记为可合并
    if (madvise(addr, size, MADV_MERGEABLE) < 0) {
        perror("madvise");
        munmap(addr, size);
        return 1;
    }

    printf("内存已标记为可合并,地址: %p, 大小: %zu\n", addr, size);

    // 保持运行,让KSM有时间扫描
    getchar();

    munmap(addr, size);
    return 0;
}
```

### 7.2 启用KSM
```bash
# 启动KSM
echo 1 > /sys/kernel/mm/ksm/run

# 设置扫描参数
echo 1000 > /sys/kernel/mm/ksm/pages_to_scan
echo 10 > /sys/kernel/mm/ksm/sleep_millisecs

# 查看统计
cat /sys/kernel/mm/ksm/pages_shared
cat /sys/kernel/mm/ksm/pages_sharing
```

---

## 8. 性能考虑

### 8.1 优点
- **节省内存**: 可以显著减少内存使用
- **透明**: 对应用程序透明
- **灵活**: 可通过sysfs动态调整

### 8.2 缺点
- **CPU开销**: 扫描和比较需要CPU时间
- **页错误增加**: COW会导致额外的页错误
- **延迟增加**: 写入KSM页面时需要分配新页面

### 8.3 优化建议
```bash
# 虚拟化环境(推荐)
pages_to_scan=100-500
sleep_millisecs=20-100

# 容器环境(中等)
pages_to_scan=50-200
sleep_millisecs=50-200

# 普通服务器(保守)
pages_to_scan=20-50
sleep_millisecs=100-500
```

---

## 9. 调试技巧

### 9.1 查看KSM状态
```bash
#!/bin/bash
# ksm_status.sh - 显示KSM状态

echo "=== KSM状态 ==="
echo "运行状态: $(cat /sys/kernel/mm/ksm/run)"
echo "已共享页面: $(cat /sys/kernel/mm/ksm/pages_shared)"
echo "共享虚拟页: $(cat /sys/kernel/mm/ksm/pages_sharing)"
echo "未共享页面: $(cat /sys/kernel/mm/ksm/pages_unshared)"
echo "易变页面: $(cat /sys/kernel/mm/ksm/pages_volatile)"
echo "完整扫描: $(cat /sys/kernel/mm/ksm/full_scans)"
echo ""

# 计算节省的内存(MB)
shared=$(cat /sys/kernel/mm/ksm/pages_shared)
sharing=$(cat /sys/kernel/mm/ksm/pages_sharing)
saved=$((sharing * 4 / 1024))  # 假设页面大小4KB
echo "节省内存: ${saved} MB"
```

### 9.2 内核日志
```bash
# 查看KSM相关日志
dmesg | grep -i ksm

# 使用ftrace跟踪KSM
echo 1 > /sys/kernel/debug/tracing/events/ksm/enable
cat /sys/kernel/debug/tracing/trace
```

---

## 10. 总结

### 10.1 核心要点
1. **两棵树**: 稳定树(已合并) + 不稳定树(候选)
2. **写保护**: KSM页面是只读的,写入时COW
3. **周期扫描**: ksmd线程定期扫描可合并内存
4. **透明操作**: 应用程序无感知

### 10.2 适用场景
- ✅ 虚拟化平台(多个相似VM)
- ✅ 容器环境(共享基础镜像)
- ✅ 内存受限系统
- ❌ 内存充足且性能敏感的系统
- ❌ 写密集型应用

### 10.3 学习路径
1. 理解基本数据结构(mm_slot, rmap_item, stable_node)
2. 跟踪一次完整的扫描流程
3. 理解页面合并机制
4. 学习COW如何与KSM交互
5. 实验不同参数对性能的影响

---

## 附录: 关键函数调用链

```
应用层
    │
    └─→ madvise(MADV_MERGEABLE)
            │
            ↓
内核层
    │
    ├─→ do_madvise()
    │       └─→ ksm_madvise()
    │               └─→ __ksm_enter()
    │                       ├─ alloc_mm_slot()
    │                       ├─ insert_to_mm_slots_hash()
    │                       └─ wake_up_interruptible()
    │
    └─→ ksm_scan_thread()  [内核线程]
            │
            └─→ ksm_do_scan()
                    │
                    ├─→ scan_get_next_rmap_item()
                    │       ├─ follow_page()
                    │       └─ get_next_rmap_item()
                    │
                    └─→ cmp_and_merge_page()
                            ├─→ stable_tree_search()
                            │       └─ memcmp_pages()
                            │
                            ├─→ unstable_tree_search_insert()
                            │       └─ memcmp_pages()
                            │
                            ├─→ try_to_merge_with_ksm_page()
                            │       └─ try_to_merge_one_page()
                            │               └─ replace_page()
                            │
                            └─→ try_to_merge_two_pages()
                                    ├─ try_to_merge_one_page()
                                    └─ stable_tree_insert()
```

