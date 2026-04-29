# PC 端 RoCEv2 接收程序

## 1. 概述

PC 端使用 **Raw Socket** 直接接收 RoCEv2 数据包（UDP 目的端口 4791），解析 BTH/RETH 头部，将 Payload 数据写入预分配的内存区域，然后构造并发送 ACK 包。

## 2. 通信流程

```
FPGA (Initiator)                          PC (Target)
     │                                        │
     │  RDMA_WRITE_FIRST (PSN=100)            │
     │  ├─ BTH: Opcode=0x06                   │
     │  ├─ RETH: VA=0x7F00..., R_Key=0x12..  │
     │  └─ Payload: 4KB data                  │
     ├───────────────────────────────────────►│
     │                                        │
     │  RDMA_WRITE_LAST (PSN=101)             │
     │  ├─ BTH: Opcode=0x08                   │
     │  └─ Payload: 2KB data                  │
     ├───────────────────────────────────────►│
     │                                        │
     │         ACK (PSN=101)                  │
     │         ├─ BTH: Opcode=0x11            │
     │         └─ AETH: Syndrome=0x20, MSN=1  │
     │◄───────────────────────────────────────┤
     │                                        │
     │  数据已确认，FPGA 可发送下一 WQE        │
```

## 3. 程序架构

```
main()
  │
  ├── init_raw_socket()      // 创建 Raw Socket
  ├── init_memory_region()   // 分配接收内存 (1GB)
  ├── tcp_handshake()        // TCP 建链 (获取 FPGA 参数)
  │
  ├── pthread_create()
  │   └── rx_thread()        // 接收线程
  │       └── process_rocev2_packet()
  │           ├── parse_eth_ip_udp()
  │           ├── parse_bth()
  │           ├── parse_reth()        // 如果是 Write
  │           ├── validate_icrc()     // 校验 ICRC
  │           ├── write_to_memory()   // 写入内存
  │           └── send_ack()          // 发送 ACK
  │
  └── stats_thread()         // 统计线程
      └── 每秒打印吞吐量
```

## 4. 关键设计要点

### 4.1 PSN 管理

| 场景 | 处理 |
|------|------|
| PSN == expected_psn | 正常接收，expected_psn++ |
| PSN < expected_psn | 重复包，丢弃但发送 ACK |
| PSN > expected_psn | 乱序包，发送 NAK (Seq Error) |

### 4.2 内存写入

- 使用 `mmap` 分配大页内存 (1GB)
- RETH.VA 指定写入地址
- 检查 R_Key 和地址范围有效性
- 多线程访问需要加锁或使用无锁队列

### 4.3 ACK 发送策略

| 条件 | 动作 |
|------|------|
| 收到 Write Last / Write Only | 立即发送 ACK |
| 收到 Write First / Middle | 累积等待 (延迟 ACK) |
| ICRC 校验失败 | 发送 NAK |
| PSN 乱序 | 发送 NAK |

### 4.4 性能优化

1. **忙轮询**: `SO_BUSY_POLL` 或使用 `PACKET_RX_RING`
2. **大页内存**: `mmap` + `MAP_HUGETLB`
3. **零拷贝**: `PACKET_MMAP` (环形缓冲)
4. **批量处理**: 一次处理多个包再发送 ACK

## 5. 源码文件

完整源码见 `../../sw/pc_receiver/` 目录：

| 文件 | 说明 |
|------|------|
| `rocev2_receiver.c` | 主程序 |
| `rocev2_protocol.h` | RoCEv2 协议头定义 |
| `Makefile` | 编译脚本 |

## 6. 编译运行

```bash
# 编译
cd sw/pc_receiver
make

# 运行 (需要 root 权限)
sudo ./rocev2_receiver -i eth0 -p 9876

# 参数说明
# -i: 网卡接口名
# -p: TCP 建链端口
# -m: 内存区域大小 (默认 1GB)
```

## 7. 与 FPGA 对接验证

1. **ARP 检查**
   ```bash
   # FPGA 侧需要能解析 PC 的 MAC
   # PC 侧查看 ARP 表
   arp -a | grep 192.168.1.10
   ```

2. **抓包验证**
   ```bash
   # 使用 tcpdump 抓 RoCEv2 包
   sudo tcpdump -i eth0 udp port 4791 -w rocev2.pcap
   
   # 用 Wireshark 分析
   # 注意: Wireshark 可能需要手动设置 RoCEv2 解析
   ```

3. **吞吐量测试**
   ```bash
   # PC 侧运行接收程序
   sudo ./rocev2_receiver -i eth0
   
   # FPGA 侧开始发送
   # 观察输出统计
   ```
