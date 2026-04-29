# PC 端软件设计方案

## 1. 方案概述

本文档描述 PC 端接收 FPGA RDMA Write 数据的软件实现方案。

**核心决策：DPDK 用户态收包 + 极简 RoCEv2 协议解析**

- FPGA 侧保持现有 RoCEv2 协议栈不变（ETH/IP/UDP/BTH/RETH/ICRC）
- PC 侧使用 DPDK 直接从 10G 网卡 DMA 接收原始报文
- 软件解析 BTH/RETH 头部，按远端地址写入内存
- 帧完成后通过包计数器或帧尾标记通知处理线程

## 2. 方案选型分析

### 2.1 为什么不用 Soft-RoCE

| 问题 | 说明 |
|------|------|
| 性能瓶颈 | 内核模块做协议解析，100MB 大帧 × 10fps 时 CPU 占用高，实测难以跑满 9Gbps |
| 配置复杂 | 需加载内核模块、创建 rxe 设备、配置 IB 子系统，调试困难 |
| 无硬件卸载 | 普通 10G 网卡无 RDMA 卸载能力，Soft-RoCE 纯软件模拟，不如 DPDK 直接收包高效 |

### 2.2 为什么不用 UDP Socket

| 问题 | 说明 |
|------|------|
| 无可靠性 | UDP 无 ACK/重传机制，交换机拥塞时丢包不可恢复 |
| 单帧代价高 | 100MB 帧由约 25600 个包组成，丢任意一包整帧图像报废 |
| 内核拷贝开销 | `socket()` 收包需经过内核协议栈，`memcpy` 次数多，性能 < 3Gbps |
| 不兼容未来升级 | 若后续更换 RDMA 网卡，UDP 方案需全部重写 |

### 2.3 为什么选 DPDK + RoCEv2 解析

| 优势 | 说明 |
|------|------|
| 性能足够 | 用户态零拷贝收包，单核可处理 1000万+ pps，9Gbps 场景仅需 ~270k pps |
| 可靠性保留 | FPGA 侧 ACK/NAK/超时重传机制完整保留，交换机丢包自动恢复 |
| 实现可控 | 只需解析 BTH/RETH 头部，代码量约 200 行 |
| 未来兼容 | 后续更换 RDMA 网卡时，FPGA 侧协议不变，PC 侧可平滑迁移到 libibverbs |

## 3. 网络拓扑与带宽分析

### 3.1 拓扑结构

```
  FPGA_1 (10G) ──┐
  FPGA_2 (10G) ──┼──► 交换机 ──► PC (10G 网卡)
  FPGA_3 (10G) ──┤
  FPGA_4 (10G) ──┘
```

- 多 FPGA 共享交换机出端口带宽
- 交换机缓存满时必然丢包，RoCEv2 重传机制是刚需

### 3.2 带宽计算

| 参数 | 数值 |
|------|------|
| 线速率 | 9 Gbps = 1.125 GB/s |
| 单帧大小 | 100 MB |
| 理论最大帧率 | 1.125 / 0.1 = **11.25 fps** |
| 设计帧率 | **10 fps** |
| 实际数据率 | 100 MB × 10 = **1.0 GB/s** |
| 线路占用率 | 1.0 / 1.125 = **~89%** |

### 3.3 包级参数

| 参数 | 数值 |
|------|------|
| Payload 大小 | 4096 B |
| 协议头开销 | ETH(14) + IP(20) + UDP(8) + BTH(12) + RETH(16) + ICRC(4) = **74 B** |
| 线路上每包大小 | 4096 + 74 = **4170 B** |
| 每帧包数 | 100 MB / 4096 = **25600 包** |
| 每秒包数 | 25600 × 10 = **256,000 pps** |

**结论**：256k pps 远低于 DPDK 单核处理能力上限（10M+ pps），性能余量充足。

## 4. CPU 占用预估

绑定一个独立 CPU 核运行 DPDK 收包线程：

| 环节 | 占用估算 | 说明 |
|------|---------|------|
| DPDK 轮询收包 | ~5% | `rte_eth_rx_burst` 批量收 128 包/次，每秒轮询 ~2000 次 |
| 解析 RoCEv2 头部 | ~1% | `ntohs` / `be64toh` / `ntohl` 操作，开销极小 |
| `memcpy` 搬数据 | ~10-15% | 1.0 GB/s 内存拷贝，现代 CPU 单核 memcpy 带宽 5-10 GB/s |
| 帧完成检测 | ~0.1% | 包计数器判断 |
| 通知处理线程 | ~2% | `rte_ring_enqueue` 或条件变量 |
| **总计** | **~18-23%** | 单核轻松处理，大量余量 |

**优化后（中断自适应模式）**：
- 满负载时：~20%
- 半负载时：~10%
- 空闲时：~1-2%

## 5. DPDK 程序结构

### 5.1 主循环

```c
#define PKT_BURST_SIZE 128
#define PAYLAOD_OFFSET 70   // ETH(14) + IP(20) + UDP(8) + BTH(12) + RETH(16)
#define PKT_MAGIC 0xDEADBEEF

uint32_t pkt_cnt = 0;
uint32_t frame_seq = 0;

while (1) {
    struct rte_mbuf *mbufs[PKT_BURST_SIZE];
    uint16_t nb_rx = rte_eth_rx_burst(port_id, 0, mbufs, PKT_BURST_SIZE);

    for (int i = 0; i < nb_rx; i++) {
        uint8_t *pkt = rte_pktmbuf_mtod(mbufs[i], uint8_t*);

        // 快速过滤：只处理 UDP dst port = 4791 (RoCEv2)
        uint16_t udp_dst = ntohs(*(uint16_t*)(pkt + 36));
        if (udp_dst != 4791) {
            rte_pktmbuf_free(mbufs[i]);
            continue;
        }

        // 解析 BTH (12 bytes)
        uint32_t bth0 = ntohl(*(uint32_t*)(pkt + 42));
        uint8_t  opcode = (bth0 >> 24) & 0xFF;
        uint32_t psn    = bth0 & 0xFFFFFF;
        uint32_t dest_qpn = ntohl(*(uint32_t*)(pkt + 46)) & 0xFFFFFF;

        // 解析 RETH (16 bytes)
        uint64_t remote_va = be64toh(*(uint64_t*)(pkt + 54));
        uint32_t rkey  = ntohl(*(uint32_t*)(pkt + 62));
        uint32_t dlen  = ntohl(*(uint32_t*)(pkt + 66));

        // 提取 Payload
        uint8_t *payload = pkt + PAYLAOD_OFFSET;
        uint32_t payload_len = rte_pktmbuf_data_len(mbufs[i]) - PAYLAOD_OFFSET;

        // 按远端地址写入帧缓冲区
        uint64_t offset = remote_va - frame_base_addr;
        memcpy(frame_buffer + offset, payload, payload_len);

        // 帧完成检测：包计数
        if (++pkt_cnt == PACKETS_PER_FRAME) {
            // 整帧 100MB 到齐，通知处理线程
            rte_ring_enqueue(frame_ready_ring, (void*)(uintptr_t)frame_seq);
            pkt_cnt = 0;
            frame_seq++;
        }

        rte_pktmbuf_free(mbufs[i]);
    }
}
```

### 5.2 帧完成检测方式

支持两种检测机制，二选一或双保险：

**方式 A：包计数器（推荐）**
```c
#define PACKETS_PER_FRAME 25600  // 100MB / 4096B

if (++pkt_cnt == PACKETS_PER_FRAME) {
    frame_complete();
    pkt_cnt = 0;
}
```

**方式 B：帧尾标记（Payload 头部 Magic）**
```c
// FPGA 最后一个包的 Payload 前 4B = 0xDEADBEEF
if (*(uint32_t*)payload == PKT_MAGIC) {
    frame_complete();
}
```

**建议**：同时启用两种方式，包计数器为主，帧尾标记为辅校验。

### 5.3 多 FPGA 支持

```c
// 按 Destination QPN 区分不同 FPGA
#define NUM_FPGA 4

struct fpga_session {
    uint8_t  *frame_buf;
    uint32_t  pkt_cnt;
    uint32_t  frame_seq;
} fpga[NUM_FPGA];

// QPN 到 FPGA 索引映射（初始化时建立）
int qpn_to_fpga(uint32_t qpn) {
    return qpn - BASE_QPN;  // 假设 QPN 连续分配
}

// 主循环中按 QPN 分发
int idx = qpn_to_fpga(dest_qpn);
struct fpga_session *s = &fpga[idx];
memcpy(s->frame_buf + offset, payload, payload_len);

if (++s->pkt_cnt == PACKETS_PER_FRAME) {
    rte_ring_enqueue(fpga_ready_ring[idx], (void*)(uintptr_t)s->frame_seq);
    s->pkt_cnt = 0;
    s->frame_seq++;
}
```

## 6. 关键配置

### 6.1 DPDK 初始化要点

```c
// 1. Hugepage 内存
rte_eal_init(argc, argv);

// 2. 网卡初始化
struct rte_eth_conf port_conf = {
    .rxmode = {
        .max_rx_pkt_len = RTE_ETHER_MAX_LEN,
        .offloads = DEV_RX_OFFLOAD_CRC_STRIP,
    },
    .txmode = {
        .offloads = 0,  // PC 端不需要发包
    },
};
rte_eth_dev_configure(port_id, 1, 0, &port_conf);  // 1 RXQ, 0 TXQ

// 3. RX 队列（ mbuf 池用 2MB hugepage）
struct rte_mempool *mbuf_pool = rte_pktmbuf_pool_create(
    "MBUF_POOL", 8192, 0, 0, RTE_MBUF_DEFAULT_BUF_SIZE, rte_socket_id()
);
rte_eth_rx_queue_setup(port_id, 0, 1024, rte_eth_dev_socket_id(port_id), NULL, mbuf_pool);

// 4. 启动网卡
rte_eth_dev_start(port_id);

// 5. 绑定收包核（隔离一个独立核）
rte_thread_set_affinity(lcore_id);
```

### 6.2 帧缓冲区分配

```c
// 每 FPGA 分配 2 个帧缓冲区（ping-pong 双缓冲）
#define FRAME_SIZE (100 * 1024 * 1024)

uint8_t *frame_buf[NUM_FPGA][2];
for (int i = 0; i < NUM_FPGA; i++) {
    for (int j = 0; j < 2; j++) {
        frame_buf[i][j] = rte_malloc("frame", FRAME_SIZE, 4096);
    }
}
```

## 7. 性能优化

### 7.1 批量收包（已做）
- `rx_burst` 一次收 128 个包，减少轮询次数

### 7.2 Hugepage 内存
- 使用 2MB hugepage 做帧缓冲区，减少 TLB miss

### 7.3 中断自适应模式（可选）

低帧率场景下降低 CPU 空转：

```c
// 先尝试收包，没收到则阻塞等中断
nb_rx = rte_eth_rx_burst(port_id, 0, mbufs, PKT_BURST_SIZE);
if (nb_rx == 0) {
    rte_eth_dev_rx_intr_enable(port_id, 0);
    epoll_wait(epfd, events, 1, -1);  // 阻塞等中断
    rte_eth_dev_rx_intr_disable(port_id, 0);
}
```

### 7.4 交换机 QoS 建议

在交换机上为每个 FPGA 端口配置 Rate Limit：

```
FPGA_1 port: max 2.5 Gbps
FPGA_2 port: max 2.5 Gbps
FPGA_3 port: max 2.5 Gbps
FPGA_4 port: max 2.5 Gbps
```

总带宽 = 10 Gbps = PC 网卡出端口不拥塞，RoCEv2 重传机制极少触发。

## 8. 可靠性保障

### 8.1 FPGA 侧（已完成）

| 机制 | 作用 |
|------|------|
| PSN 24bit | 包序号追踪，检测丢包/乱序 |
| ACK/NAK 解析 | `rx_pkt_handler` + `resp_handler_fsm` 处理响应 |
| 超时重传 | `resp_handler_timer` 定时检测，超时自动重发 |
| ICRC32 | `rocev2_icrc32_512b` 数据完整性校验 |

### 8.2 PC 侧

| 机制 | 实现 |
|------|------|
| 包计数检测 | 每帧 25600 包，收齐才通知处理 |
| 帧尾标记校验 | Payload 头部 Magic 值二次确认 |
| 帧序号递增 | 处理线程检测帧号连续性，发现跳变可告警 |

## 9. 与 FPGA 侧接口

PC 侧不需要改动 FPGA 任何代码，FPGA 继续通过以下接口工作：

```
FPGA rdma_core
   │
   ├─ AXI-Lite：PC 通过 TCP 建链后下发 QP 配置（IP/MAC/PSN/R_Key）
   ├─ AXI-Stream：wqe_proc_top_m_axis_* → 10G MAC → 网线
   └─ AXI-Stream：rx_pkt_hndler_s_axis_* ← 10G MAC ← ACK/NAK
```

FPGA 的 WQE 触发方式（二选一）：
- **方式 A**：PC 每帧写 `SQ_PI_REG`（Doorbell）触发
- **方式 B**：FPGA 内部定时/帧同步信号自动触发（固定地址 ping-pong）

## 10. 总结

| 项目 | 结论 |
|------|------|
| **方案** | DPDK 用户态收包 + 软件解析 RoCEv2 |
| **性能** | 10fps × 100MB = 1GB/s，占 9Gbps 线路 ~89%，CPU 单核 ~20% |
| **可靠性** | FPGA 侧 ACK/重传/ICRC 完整保留，交换机拥塞自动恢复 |
| **复杂度** | PC 端 ~200 行 C 代码，FPGA 侧零改动 |
| **扩展性** | 支持多 FPGA，后续换 RDMA 网卡可平滑迁移 |
| **关键限制** | 9Gbps 线路下 100MB 帧最大 ~11fps，10fps 是安全设计点 |
