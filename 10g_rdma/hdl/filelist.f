// RDMA Core RTL Filelist for VCS
// Usage: vcs -f filelist.f -full64 -debug_access+all +v2k -sverilog
// All paths relative to hdl/ (where rdma_core.v resides)

// Header include path
+incdir+common

// ---- XPM Behavioral Models ----
// xpm_stubs.v: Vivado synthesis stub (空壳，仅声明端口)
// xpm_stubs_logic.v: iverilog/VCS simulation (行为级RTL，FIFO/BRAM指针初始化)
// For iverilog simulation: use xpm_stubs_logic.v (see sim/run_sim.sh)
// For Vivado synthesis: use XPM library (xpm_stubs.v is fallback)
common/xpm_stubs.v

// ---- Common Modules ----
common/blk_mem_gen_wrapper.v
common/rdma_axi_master.v
common/rdma_blk_allocator.v
common/rdma_blk_allocator_init_fifo.v
common/rdma_q_mgr_init_top.v
common/rdma_q_mgr_queue.v

// ---- QP Manager ----
qp_mgr/rdma_config_reg.v
qp_mgr/qp_mgr_top.v
qp_mgr/qp_mgr_cache.v
qp_mgr/qp_mgr_retransmit.v

// ---- WQE Processor ----
wqe_proc/wqe_proc_top.v
wqe_proc/wqe_proc_hdr_gen.v
wqe_proc/wqe_proc_dma.v
wqe_proc/wqe_proc_dre.v
wqe_proc/wqe_proc_buf_mgr.v
wqe_proc/wqe_proc_ack_buf.v
wqe_proc/wqe_proc_crc_wrap.v

// ---- Response Handler ----
resp_handler/resp_handler_top.v
resp_handler/resp_handler_fsm.v
resp_handler/resp_handler_timer.v

// ---- RX Packet Handler ----
rx_pkt_handler/rx_pkt_handler.v
rx_pkt_handler/rx_rsp_hdr_val.v
rx_pkt_handler/cmac_rx_intf.v
rx_pkt_handler/rx_pkt_intr_ctrl.v
rx_pkt_handler/rocev2_icrc32_512b.v
rx_pkt_handler/icrc_rocev2_512b_rx.v
rx_pkt_handler/icrc_rocev2_512b_tx.v
rx_pkt_handler/crc32_0_data_in.v
rx_pkt_handler/crc32_32b.v
rx_pkt_handler/crc32_8b.v
rx_pkt_handler/crc32_zero_extnd.v
rx_pkt_handler/reg_fifo_sync.v
rx_pkt_handler/reg_pipe.v

// ---- Top Level ----
rdma_core.v
