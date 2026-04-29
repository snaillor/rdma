# RDMA Core - 项目开发指南

## 项目概览

这是一个支持单 QP 的 RoCEv2 RDMA Write-Only 协议处理核心，适用于 FPGA 向 PC 进行 10G 以太网单向数据传输。

### 核心特性
- 单 QP（Queue Pair）模式
- 512bit 内部数据通路
- RDMA Write-Only 发送模式（FPGA -> PC）
- 完整 ACK/NAK 处理与超时重传机制
- AXI4-Lite 软件配置接口
- 4 组 AXI4 Master DMA 接口

## 技术栈

- Verilog'2001
- AXI4-Lite / AXI4 / AXI-Stream 接口协议

## 目录结构

```
/workspace/projects/10g_rdma/
├── hdl/
│   ├── rdma_core.v              # 顶层模块
│   ├── rdma_macros.vh           # 宏定义
│   ├── qp_mgr/                   # QP 管理模块
│   │   ├── qp_mgr_top.v          # QP 管理顶层
│   │   ├── qp_mgr_cache.v        # WQE 缓存
│   │   ├── qp_mgr_retransmit.v   # 重传控制
│   │   └── rdma_config_reg.v     # 配置寄存器
│   ├── resp_handler/             # 响应处理模块
│   │   ├── resp_handler_top.v    # 响应处理顶层
│   │   ├── resp_handler_fsm.v    # 响应状态机
│   │   └── resp_handler_timer.v  # 重传定时器
│   ├── rx_pkt_handler/           # RX 包处理模块
│   │   ├── rx_pkt_handler.v      # RX 包处理顶层
│   │   ├── rx_rsp_hdr_val.v      # 响应包头解析
│   │   ├── rocev2_icrc32_512b.v  # ICRC 计算
│   │   └── cmac_rx_intf.v        # CMAC 接口适配
│   ├── wqe_proc/                 # WQE 处理模块
│   │   ├── wqe_proc_top.v        # WQE 处理顶层
│   │   ├── wqe_proc_hdr_gen.v    # 包头生成
│   │   ├── wqe_proc_dma.v        # DMA 读取
│   │   └── wqe_proc_buf_mgr.v    # 缓冲区管理
│   └── common/                   # 公共模块
│       ├── rdma_axi_master.v     # AXI Master
│       ├── rdma_axi_slave.v      # AXI Slave
│       └── rdma_q_mgr_queue.v    # 队列管理
├── docs/
│   └── fpga_to_pc_write/         # FPGA->PC 单向传输文档
└── AGENTS.md                     # 本文件
```

## 文件清单（34 个 Verilog 文件）

### 顶层（1 个）
| 文件 | 描述 |
|------|------|
| `rdma_core.v` | 顶层模块，集成所有子系统 |

### QP 管理（4 个）
| 文件 | 描述 |
|------|------|
| `qp_mgr_top.v` | QP 管理顶层 |
| `rdma_config_reg.v` | 配置/状态寄存器（AXI-Lite） |
| `qp_mgr_cache.v` | WQE 缓存管理 |
| `qp_mgr_retransmit.v` | 重传控制逻辑 |

### 响应处理（3 个）
| 文件 | 描述 |
|------|------|
| `resp_handler_top.v` | 响应处理顶层 |
| `resp_handler_fsm.v` | ACK/NAK 处理状态机 |
| `resp_handler_timer.v` | 重传定时器 |

### RX 包处理（12 个）
| 文件 | 描述 |
|------|------|
| `rx_pkt_handler.v` | RX 包处理顶层（仅 ACK/NAK 解析） |
| `rx_rsp_hdr_val.v` | 响应包头解析 |
| `cmac_rx_intf.v` | CMAC 接口适配 |
| `rocev2_icrc32_512b.v` | ICRC32 计算 |
| `icrc_rocev2_512b_rx.v` | RX CRC 计算 |
| `icrc_rocev2_512b_tx.v` | TX CRC 计算 |
| `crc32_*.v` (4 个) | CRC 基础模块 |
| `rx_pkt_intr_ctrl.v` | 中断控制 |
| `reg_fifo_sync.v` | 同步 FIFO |
| `reg_pipe.v` | 寄存器流水线 |

### WQE 处理（7 个）
| 文件 | 描述 |
|------|------|
| `wqe_proc_top.v` | WQE 处理顶层 |
| `wqe_proc_hdr_gen.v` | 包头生成（仅 RDMA Write） |
| `wqe_proc_dma.v` | DMA 读取 |
| `wqe_proc_buf_mgr.v` | 缓冲区管理 |
| `wqe_proc_ack_buf.v` | ACK 缓冲 |
| `wqe_proc_dre.v` | 数据重对齐 |
| `wqe_proc_crc_wrap.v` | CRC 封装 |

### 公共模块（7 个）
| 文件 | 描述 |
|------|------|
| `rdma_axi_master.v` | AXI4 Master 接口 |
| `rdma_axi_slave.v` | AXI4 Slave 接口 |
| `rdma_blk_allocator.v` | 块分配器 |
| `rdma_blk_allocator_init_fifo.v` | 块分配器初始化 FIFO |
| `rdma_q_mgr_queue.v` | 队列管理 |
| `rdma_q_mgr_init_top.v` | 队列初始化顶层 |
| `rdma_macros.vh` | 全局宏定义 |

## 已裁剪功能

以下功能在 Write-Only 精简过程中已删除：
- RDMA Read 请求处理
- SEND 请求处理
- RX 请求包 DDR 写入路径
- Read Response DDR 写入路径
- QP 轮询仲裁器（单 QP 直通）
- 多 QP 支持（C_NUM_QP = 1）

## 开发规范

### 信号命名
- 时钟信号：`core_clk`
- 复位信号：`core_rst`
- 输入前缀：`i_`
- 输出前缀：`o_`

### 模块实例化
- 使用 `module_name #(...) instance_name (...)` 格式
- 参数传递使用 named mapping
