// qp_mgr_top.v
// 文件名          : qp_mgr_top.v
// 版本            : v1.0
// 描述            : QP 管理顶层模块，集成 QP 配置寄存器、WQE 缓存、重传控制
//                   单 QP 模式下仲裁逻辑已简化为直通
// Verilog 标准    : Verilog'2001

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
`timescale 1ps/1ps

(* DowngradeIPIdentifiedWarnings="yes" *)
module qp_mgr_top
#(
    parameter   C_S_AXI_LITE_ADDR_WIDTH = 14,
    parameter   C_S_AXI_LITE_DATA_WIDTH = 32,
    parameter   C_M_AXI_ADDR_WIDTH      = 32,
    parameter   C_NUM_QP                = 256,
    parameter   C_QP_INDX_WIDTH         = 8,
    parameter   STB_WIDTH               = 4,
    parameter   C_SQPI_DB_HNDSHK_EN     = 0,
    parameter   RESP_WIDTH              = 2,
    parameter   C_EN_DEBUG_REGS         = 1
)
(
  input  wire                                       s_axi_lite_aclk,
  input  wire                                       s_axi_lite_aresetn,

  input  wire  [C_S_AXI_LITE_ADDR_WIDTH-1:0]        s_axi_lite_awaddr,
  output wire                                       s_axi_lite_awready,
  input  wire                                       s_axi_lite_awvalid,

  input  wire  [C_S_AXI_LITE_ADDR_WIDTH-1:0]        s_axi_lite_araddr,
  output wire                                       s_axi_lite_arready,
  input  wire                                       s_axi_lite_arvalid,

  input  wire  [C_S_AXI_LITE_DATA_WIDTH-1:0]        s_axi_lite_wdata,
  input  wire  [STB_WIDTH-1:0]                      s_axi_lite_wstrb,
  output wire                                       s_axi_lite_wready,
  input  wire                                       s_axi_lite_wvalid,

  output wire  [C_S_AXI_LITE_DATA_WIDTH-1:0]        s_axi_lite_rdata,
  output wire  [RESP_WIDTH-1:0]                     s_axi_lite_rresp,
  input  wire                                       s_axi_lite_rready,
  output wire                                       s_axi_lite_rvalid,

  output wire  [RESP_WIDTH-1:0]                     s_axi_lite_bresp,
  input  wire                                       s_axi_lite_bready,
  output wire                                       s_axi_lite_bvalid,

  input  wire					    core_clk,
  input  wire					    core_rstn,	    // Active low core reset

  output wire  [511:0]                              o_wqe,
  input  wire                                       i_wqe_pop,
  output wire                                       o_wqe_empty,
  output wire                                       o_halt,
  output wire [C_QP_INDX_WIDTH -1 :0]               o_halted_qpid,
  input  wire                                       i_wqe_halted,

  // Interrupt signals coming from Header validation module
  input  wire                                       i_pkt_valdn_err_intr,
  input  wire                                       i_mad_pkt_rcvd_intr,
  input  wire                                       i_bypass_pkt_rcvd_intr,
  input  wire                                       i_rnr_nack_gen_intr,
  input  wire                                       i_ill_opc_in_sq_intr,

  output wire                                       o_intr_clr_pkt_valdn_err,
  output wire                                       o_intr_clr_wqe_cmpl,
  output wire                                       o_intr_clr_mad_pkt_rcvd,
  output wire                                       o_intr_clr_bypass_pkt_rcvd,
  output wire                                       o_intr_clr_rnr_nak_gen,
  output wire                                       o_intr_clr_ill_opc_in_sq,
  output wire                                       o_intr_clr_qp_pkt_rcvd,
  output wire					    o_intr_clr_fatal_err,

  output wire                                       o_intr_en_pkt_valdn_err,
  output wire                                       o_intr_en_wqe_cmpl,
  output wire                                       o_intr_en_mad_pkt_rcvd,
  output wire                                       o_intr_en_bypass_pkt_rcvd,
  output wire                                       o_intr_en_rnr_nak_gen,
  output wire                                       o_intr_en_ill_opc_in_sq,
  output wire                                       o_intr_en_fatal_err,
  output wire                                       o_intr_en_qp_pkt_rcvd,

  input  wire  [C_NUM_QP -1 :0]                     i_rq_full,  // Rcv Q full for QPn
  input  wire  [C_NUM_QP -1 :0]                     i_osq_full, // Outstanding Q full for QPn
  input  wire  [C_NUM_QP -1 :0]                     i_cq_full,  // completion Q full for QPn
  input  wire  [C_NUM_QP -1 :0]                     i_rq_empty, // Rcv Q empty for QPn
  input  wire  [C_NUM_QP -1 :0]                     i_osq_empty,// Outstanding Q empty for QPn
  input  wire  [C_NUM_QP -1 :0]                     i_qp_retried,// QP retried for QPn

  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_stat_msn_idx,    // Index for reading/writing MSN
  input  wire  [23:0]                               i_qp_stat_msn, // Expected MSN for Qp incoming messages
  output wire  [23:0]                               o_qp_stat_msn, // Expected MSN for Qp incoming messages write data from hdr validation
  input  wire                                       i_qp_stat_msn_req,
  input  wire                                       i_qp_stat_msn_wrn,
  output wire                                       o_qp_stat_msn_valid,

  output wire [31:0]                                o_rx_pkt_hndl_dbg_ctrl,

  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_stat_ssn_idx,
  input  wire  [23:0]                               i_qp_stat_ssn,
  output wire  [23:0]                               o_qp_stat_ssn,
  input  wire                                       i_qp_stat_ssn_req,
  input  wire                                       i_qp_stat_ssn_wrn,
  output wire                                       o_qp_stat_ssn_valid,

  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_timeout_idx,    // Index for reading/writing MSN
  output wire  [31:0]                               o_qp_timeout, // Expected MSN for Qp incoming messages write data from hdr validation

  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_rq_pi_db_idx,    // Index for reading/writing RQ PI DB
  input  wire  [15:0]                               i_qp_rq_pi_db,
  output wire  [15:0]                               o_qp_rq_pi_db,
  input  wire                                       i_qp_rq_pi_db_req,
  input  wire                                       i_qp_rq_pi_db_wrn,
  output wire                                       o_qp_rq_pi_db_valid,

  // Retried SQ PSN for Rx packet handler
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_stat_ret_sq_psn_idx,    // Index for reading/writing RQ PI DB
  output wire  [23:0]                               o_qp_stat_ret_sq_psn,
  input  wire                                       i_qp_stat_ret_sq_psn_req,
  output wire                                       o_qp_stat_ret_sq_psn_valid,

  input  wire  [9:0]                               i_qp_stat_nak,
  input  wire                                       i_qp_stat_nak_wen,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_stat_nak_idx,
  output wire                                       o_qp_stat_nak_valid,
  input  wire                                       i_qp_stat_nak_rdreq,
  output wire  [9:0]                               o_qp_stat_nak,

  input  wire  [31:0]                               i_wqe_proc_sts,
  input  wire  [31:0]                               i_rx_pkt_vld_sts,

  //Configuration outputs going to other modules (generic)
  output wire                                       o_rdma_en,
  output wire                                       o_rdma_adv_conf_errbuf_overwr_en,
  output wire [3:0]				    o_rdma_adv_base_cnt,
  output wire [1:0]                                 o_tx_ack_gen,
  output wire                                       o_err_buf_en,
  output wire [1:0]                                 o_flow_credits,
  output wire [15:0]                                o_rdma_udp_src_port,
  output wire                                       o_depkt_bypass_en,               // RDMA interface bypass feature enable
  output wire [C_QP_INDX_WIDTH-1:0]                 o_num_qp_en,                      // Number of QPs enabled
  output wire [47:0]                                o_mac_rdma_addr,                 // Ethernet MAC destination (own) address from RDMA registers
  output wire [31:0]                                o_ipv4_rdma_addr,                // IPv4 destination (own) address from RDMA registers
  output wire [127:0]                               o_ipv6_rdma_addr,                // IPv6 destination (own) address form RDMA registers
  output wire [31:0]                                o_data_buf_ba,
  output wire [15:0]                                o_data_buf_sz_num_bufs,
  output wire [15:0]                                o_data_buf_sz_buf_sz,

  input  wire                                       i_qp_sq_ba_req,
  output wire                                       o_qp_sq_ba_valid,
  output wire [31:0]                                o_qp_sq_ba,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_sq_ba_idx,   // Index for reading Qp SQ BA

  output wire [9:0]                                 o_connect_io_qp_rq_pi_db_wptr,
  input  wire                                       i_connect_io_qp_rq_pi_db_rdy,  // Ready indicates can accept another
  output wire [15:0]                                o_rq_pi_db_hw_hndshk,
  output wire                                       o_hw_hndshk_disable_to_0,

  output wire [31:0]                                o_bypass_buf_ba,
  output wire [15:0]                                o_bypass_buf_sz_num_bufs,
  output wire [15:0]                                o_bypass_buf_sz_buf_sz,
  input  wire [15:0]                                i_bypass_buf_wrptr,

  output wire [31:0]                                o_rq_err_pkt_buf_ba,
  output wire [15:0]                                o_rq_err_pkt_buf_sz_num_bufs,
  output wire [15:0]                                o_rq_err_pkt_buf_sz_buf_sz,
  output wire [31:0]                                o_resp_err_pkt_buf_ba,
  output wire [15:0]                                o_resp_err_pkt_buf_sz_num_bufs,
  output wire [15:0]                                o_resp_err_pkt_buf_sz_buf_sz,

  input  wire  [15:0]                               i_inc_rresp_pkt_cnt,
  input  wire  [15:0]                               i_inc_send_pkt_cnt,
  input  wire  [15:0]                               i_inc_ack_pkt_cnt,
  input  wire  [15:0]                               i_inc_mad_pkt_cnt,
  input  wire  [15:0]                               i_inc_inv_pkt_cnt,
  input  wire  [15:0]                               i_inc_dup_pkt_cnt,
  input  wire  [31:0]                               i_inc_all_dropped_cnt,
  input  wire  [15:0]                               i_inc_nack_cnt,

  input  wire  [15:0]                               i_out_rdwr_pkt_cnt,
  input  wire  [15:0]                               i_out_send_pkt_cnt,
  input  wire  [15:0]                               i_out_mad_pkt_cnt,
  input  wire  [15:0]                               i_out_ack_pkt_cnt,
  input  wire  [15:0]                               i_out_nack_cnt,
  input  wire  [31:0]                               i_resp_hndler_sts,
  input  wire  [31:0]                               i_stat_retry_cnt,
  input  wire  [31:0]                               i_min_ipg_stat,
  input  wire  [31:0]                               i_ipg_0_4_cnt,
  input  wire  [31:0]                               i_ipg_5_9_cnt,
  input  wire  [31:0]                               i_ipg_10_14_cnt,
  input  wire  [31:0]                               i_ipg_15_19_cnt,

  output wire [31:0]                                o_tx_hdr_buf_ba,
  output wire [15:0]                                o_tx_hdr_buf_sz_num_hdrs,
  output wire [15:0]                                o_tx_hdr_buf_sz_buf_sz,
  output wire [31:0]                                o_tx_sgl_buf_ba,
  output wire [15:0]                                o_tx_sgl_buf_sz_num_sgls,
  output wire [15:0]                                o_tx_sgl_buf_sz_buf_sz,
  output wire                                       o_rdma_conf_ipver,

  //Configuration outputs going to other modules (PER QP)
  input  wire                                       i_qp_conf_req_resp_hndl,
  input  wire                                       i_qp_conf_req_wqe_proc,
  input  wire                                       i_qp_conf_req_rx_pkt,
  output wire                                       o_qp_conf_valid_resp_hndl,
  output wire                                       o_qp_conf_valid_wqe_proc,
  output wire                                       o_qp_conf_valid_rx_pkt,
  output wire  [31:0]                               o_qp_conf,        // QP configuration
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_conf_idx,    // Index for reading Qp configuration

  output wire  [31:0]                               o_qp_conf_replica,        // QP configuration REPLICA
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_conf_replica_idx,    // Index for reading Qp configuration REPLICA
  input  wire                                       i_qp_conf_replica_req,
  output wire                                       o_qp_conf_replica_valid,

  input  wire                                       i_qp_adv_conf_req,
  output wire                                       o_qp_adv_conf_valid,
  output wire  [31:0]                               o_qp_adv_conf,        // QP advance configuration
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_adv_conf_idx,    // Index for reading Qp configuration

  input  wire                                       i_qp_rq_ba_req,
  output wire                                       o_qp_rq_ba_valid,
  output wire  [23:0]                               o_qp_rq_ba,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_rq_ba_idx,   // Index for reading Qp RQ Buffer BA

  input  wire                                       i_qp_cq_ba_req,
  output wire                                       o_qp_cq_ba_valid,
  output wire  [31:0]                               o_qp_cq_ba,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_cq_ba_idx,   // Index for reading Qp CQ BA

  input  wire                                       i_qp_rq_wrptrdb_add_req,
  output wire                                       o_qp_rq_wrptrdb_add_valid,
  output wire  [31:0]                               o_qp_rq_wrptrdb_add,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_rq_wrptrdb_add_idx,   // Index for reading Qp SQ BA

  input  wire                                       i_qp_sq_cmpldb_add_req,
  output wire                                       o_qp_sq_cmpldb_add_valid,
  output wire  [31:0]                               o_qp_sq_cmpldb_add,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_sq_cmpldb_add_idx,   // Index for reading SQ Completion DB address

  input wire  [15:0]                                i_qp_sq_pidb_hndshk,
  input wire  [31:0]                                i_qp_sq_pidb_wr_addr_hndshk,
  input wire                                        i_qp_sq_pidb_wr_valid_hndshk,
  output wire                                       o_qp_sq_pidb_wr_rdy,
  input wire  [15:0]                                i_qp_rq_cidb_hndshk,
  input wire  [31:0]                                i_qp_rq_cidb_wr_addr_hndshk,
  input wire                                        i_qp_rq_cidb_wr_valid_hndshk,
  output wire                                       o_qp_rq_cidb_wr_rdy,

  input  wire                                       i_qp_cq_hdptr_req,
  output wire                                       o_qp_cq_hdptr_valid,
  output wire  [15:0]                               o_qp_cq_hdptr,
  input  wire  [15:0]                               i_qp_cq_hdptr,
  input  wire                                       i_qp_cq_hdptr_wrn,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_cq_hdptr_idx,   // Index for reading CQ head pointer

  input  wire                                       i_qp_rq_cidb_req,
  output wire                                       o_qp_rq_cidb_valid,
  output wire  [31:0]                               o_qp_rq_cidb,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_rq_cidb_idx,   // Index for reading RQ CI DB

  // Response PSN status register. Read/write interface to RX pkt handler
  input  wire  [23:0]                               i_qp_stat_resp_psn,
  input  wire                                       i_qp_stat_resp_psn_wen,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_stat_resp_psn_idx,
  output wire                                       o_qp_stat_resp_psn_valid,
  input  wire                                       i_qp_stat_resp_psn_rdreq,
  output wire  [23:0]                               o_qp_stat_resp_psn,

  input  wire  [23:0]                               i_qp_stat_rq_buf_ca,
  input  wire                                       i_qp_stat_rq_buf_ca_wen,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_stat_rq_buf_ca_idx,
  output wire                                       o_qp_stat_rq_buf_ca_valid,
  input  wire                                       i_qp_stat_rq_buf_ca_rdreq,
  output wire  [23:0]                               o_qp_stat_rq_buf_ca,

  input  wire                                       i_qp_rq_depth_req,
  output wire                                       o_qp_rq_depth_valid,
  output wire  [15:0]                               o_qp_rq_depth,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_rq_depth_idx,

  // The CQ depth is equal to SQ depth. This information is shared by QP cache
  // manager and resp handler. Priority is for cache manager

  input  wire                                       i_qp_cq_depth_req,
  output wire                                       o_qp_cq_depth_valid,
  output wire  [15:0]                               o_qp_cq_depth,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_cq_depth_idx,

  input  wire                                       i_qp_sq_psn_req,
  input  wire                                       i_qp_sq_psn_wqe_req,
  output wire                                       o_qp_sq_psn_valid,
  output wire                                       o_qp_sq_psn_wqe_valid,
  output wire  [23:0]                               o_qp_sq_psn,
  input  wire                                       i_qp_sq_psn_wrn,
  input  wire  [23:0]                               i_qp_sq_psn,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_sq_psn_idx,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_sq_psn_wqe_idx,

  output wire  [31:0]                               o_qp_last_rq,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_last_rq_idx,
  input wire   [31:0]                               i_qp_last_rq,
  input  wire                                       i_qp_last_rq_req,
  input  wire                                       i_qp_last_rq_wrn,
  output wire                                       o_qp_last_rq_valid,

  input  wire                                       i_qp_dest_qpid_req_wqe_proc,
  input  wire                                       i_qp_dest_qpid_req_rx_pkt,
  output wire                                       o_qp_dest_qpid_valid_wqe_proc,
  output wire                                       o_qp_dest_qpid_valid_rx_pkt,
  output wire  [23:0]                               o_qp_dest_qpid,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_dest_qpid_idx,

  output wire  [31:0]                               o_timeoutreg,

  output wire  [C_NUM_QP -1:0]                      o_qp_disable_pulse,

  output wire  [31:0]                               o_out_errsts_q_ba,
  output wire  [15:0]                               o_out_errsts_q_sz,
  input  wire  [15:0]                               i_out_errsts_q_wrptr,

  output wire  [31:0]                               o_in_errsts_q_ba,
  output wire  [15:0]                               o_in_errsts_q_sz,
  input  wire  [15:0]                               i_in_errsts_q_wrptr,

  input  wire                                       i_qp_mac_remote_addrl_req,
  input  wire                                       i_qp_mac_remote_addrl_wqe_req,
  output wire                                       o_qp_mac_remote_addrl_valid,
  output wire                                       o_qp_mac_remote_addrl_wqe_valid,
  output wire  [31:0]                               o_qp_mac_remote_addrl,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_mac_remote_addrl_idx,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_mac_remote_addrl_wqe_idx,   // Index for reading Q depth

  input  wire                                       i_qp_mac_remote_addrl_replica_req,
  output wire  [31:0]                               o_qp_mac_remote_addrl_replica,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_mac_remote_addrl_replica_idx,   // Index for reading Q depth
  output wire                                       o_qp_mac_remote_addrl_replica_valid,

  input  wire                                       i_qp_mac_remote_addrm_req,
  input  wire                                       i_qp_mac_remote_addrm_wqe_req,
  output wire                                       o_qp_mac_remote_addrm_valid,
  output wire                                       o_qp_mac_remote_addrm_wqe_valid,
  output wire  [31:0]                               o_qp_mac_remote_addrm,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_mac_remote_addrm_idx,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_mac_remote_addrm_wqe_idx,   // Index for reading Q depth

  output wire  [31:0]                               o_qp_mac_remote_addrm_replica,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_mac_remote_addrm_replica_idx,   // Index for reading Q depth
  input  wire                                       i_qp_mac_remote_addrm_replica_req,
  output wire                                       o_qp_mac_remote_addrm_replica_valid,

  input  wire                                       i_qp_ip_remote_addr1_req,
  output wire                                       o_qp_ip_remote_addr1_valid,
  input  wire                                       i_qp_ip_remote_addr1_wqe_req,
  output wire                                       o_qp_ip_remote_addr1_wqe_valid,
  output wire  [31:0]                               o_qp_ip_remote_addr1,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_ip_remote_addr1_idx,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_ip_remote_addr1_wqe_idx,   // Index for reading Q depth

  output wire  [31:0]                               o_qp_ip_remote_addr1_replica,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_ip_remote_addr1_replica_idx,   // Index for reading Q depth
  input  wire                                       i_qp_ip_remote_addr1_replica_req,
  output wire                                       o_qp_ip_remote_addr1_replica_valid,

  // HW Doorbell WQE template outputs (from rdma_config_reg)
  output wire [31:0]                                o_hw_wqe_remote_addr_lo,
  output wire [31:0]                                o_hw_wqe_remote_addr_hi,
  output wire [31:0]                                o_hw_wqe_rkey,
  output wire [31:0]                                o_hw_wqe_local_addr,
  output wire [7:0]                                 o_hw_wqe_opcode,
  output wire [15:0]                                o_hw_wqe_wrid,
  output wire                                       o_wqe_fifo_full,

  //Performacne debug counter i/f
  output wire  [15:0]				    o_global_dbg_cnt_value,
  output wire  					    o_global_dbg_cnt_clr,
  output wire					    o_global_dbg_cnt_en,
  input  wire  [15:0]				    i_wqe_fsm_idle_cnt,
  input  wire  [15:0]				    i_hdr_backpressure_cnt,
  input  wire  [15:0]				    i_retry_tx_backpressure_cnt,
  input  wire  [15:0]				    i_wqe_proc_rd_wqe_cnt      ,
  input  wire  [15:0]				    i_wqe_proc_rd_q_info_cnt   ,
  input  wire  [15:0]				    i_wqe_proc_wait0_cnt       ,
  input  wire  [15:0]				    i_wqe_proc_ip_chksum_cnt   ,
  input  wire  [15:0]				    i_wqe_proc_hdr_gen_cnt     ,
  input  wire  [15:0]				    i_wqe_proc_hdr_sto_cnt     ,

  input  wire  [31:0]                               i_last_in_pkt_info,
  input  wire  [31:0]                               i_last_out_pkt_info,

  // In terface to response handler for retransmission logic
  input  wire [C_QP_INDX_WIDTH -1 :0]               i_retransmit_qpid,        // QP id for this retransmission is required
  input  wire                                       i_retransmit_reqd,        // Retransmission is required
  output wire                                       o_retransmit_accepted,        // Ack from QP manager that the retransmission is initiated
  input  wire [C_NUM_QP -1:0]                       i_osq_almost_full,
  input  wire [23:0]                                i_psn_to_retry,
  input  wire [23:0]                                i_ssn_to_retry,

  input  wire [C_NUM_QP -1:0]                       i_qp_rnr_nacked,
  input  wire [C_NUM_QP -1:0]                       i_qp_pkt_rcvd_intr,
(* mark_debug = "true" *)  input  wire [C_NUM_QP-1:0]                        i_qp_fatal_err,               // QPs those are stalled due to fatal error

  output wire [C_NUM_QP -1:0]                       o_qp_clr_fatal_err,
  input  wire [C_NUM_QP -1:0]                       i_qp_wq_cmpl_intr,
  output wire [C_NUM_QP -1:0]                       o_rq_intr_sts_clr,
  output wire [C_NUM_QP -1:0]                       o_cq_intr_sts_clr,

// AXI Master signals
  output wire   [0:0]                               m_axi_awid,
  output wire   [31:0]                              m_axi_awaddr,
  output wire   [7:0]                               m_axi_awlen,
  output wire   [2:0]                               m_axi_awsize,
  output wire   [1:0]                               m_axi_awburst,
  output wire   [3:0]                               m_axi_awcache,
  output wire   [2:0]                               m_axi_awprot,
  output wire                                       m_axi_awvalid,
  input  wire                                       m_axi_awready,
  output wire   [511:0]                             m_axi_wdata,
  output wire   [512/8-1:0]                         m_axi_wstrb,
  output wire                                       m_axi_wlast,
  output wire                                       m_axi_wvalid,
  input  wire                                       m_axi_wready,
  output wire                                       m_axi_awlock,
  input  wire   [0 :0]                              m_axi_bid,
  input  wire   [1:0]                               m_axi_bresp,
  input  wire                                       m_axi_bvalid,
  output wire                                       m_axi_bready,
  output wire   [0:0]                               m_axi_arid,
  output wire   [31:0]                              m_axi_araddr,
  output wire   [7:0]                               m_axi_arlen,
  output wire   [2:0]                               m_axi_arsize,
  output wire   [1:0]                               m_axi_arburst,
  output wire   [3:0]                               m_axi_arcache,
  output wire   [2:0]                               m_axi_arprot,
  output wire                                       m_axi_arvalid,
  input  wire                                       m_axi_arready,
  input  wire   [0:0]                               m_axi_rid,
  input  wire   [511:0]                             m_axi_rdata,
  input  wire   [1:0]                               m_axi_rresp,
  input  wire                                       m_axi_rlast,
  input  wire                                       m_axi_rvalid,
  output wire                                       m_axi_rready,
  output wire                                       m_axi_arlock

  );

  `include "rdma_macros.vh"

  localparam WQE_SIZE = 14'd512;        // WQE entry size is 64 Bytes -> 512bits
  localparam WQE_SIZE_IN_BYTES = WQE_SIZE/8;
  localparam WQE_FIFO_DEPTH = 3'd4;     // DO NOT INCREASE BEYOND 4. See *below. Depth of FIFO that interfaces with WQE processor
  localparam WQE_FIFO_IDX_WIDTH = 2;

  //* The SEND WQE FIFO feeds to the WQE processor. It is a cache to allow
  //back to back processing of WQEs. Since this is a FIFO, if one entry cannot
  //be processed by WQE module because the outstanding FIFO for that QP is
  //the arbiter module is fed with osq_almost_full information so that the
  //when there is enough space for all WQEs in the FIFO to be absorbed.
  //Since the OSQ is currently set to a depth of 8, if the WQE FIFO depth
  //is set to more than 4, the OSQ might be severly under utilized for
  //cases where only a single QP is connected

(* mark_debug = "true" *)  wire qp_fatal_err_ored;               // QPs those are stalled due to fatal error
  wire halt;
  wire sw_override_en;
  wire [15:0] qp_cq_hdptr_from_config;
  wire [WQE_FIFO_IDX_WIDTH  :0]   num_valid_entries;
  wire [WQE_FIFO_IDX_WIDTH -1 :0] wqe_fifo_rd_ptr;
  wire [WQE_FIFO_IDX_WIDTH -1 :0] wqe_fifo_wr_ptr;
  wire wqe_full;
  wire  [C_NUM_QP -1 :0]          sq_empty;
  wire  [C_NUM_QP -1 :0]          sq_full;
  wire                            arbitrate;
  wire                            sample_arbitrated_sq;
  wire                            arbitration_done;
  wire [2:0]                      cache_fsm_status;
  wire [15:0]                     stat_wqe_cnt;
  wire [511:0] bus2ip_data;
  wire bus2ip_dvalid;
  wire [31:0] qp_sq_ba;
  wire axi_ren_valid;
  wire [C_QP_INDX_WIDTH -1 :0]       qp_sq_arbitrated_idx;
  wire [C_QP_INDX_WIDTH :0]       num_elements_enabled;
  wire [15:0]                          qp_sq_pidb;
  wire qp_curr_sqptr_req;
  wire qp_sq_depth_req;
  wire qp_sq_depth_valid;
  wire qp_sq_ba_req_int;
  wire qp_sq_ba_valid_int;
  wire [15:0] new_curr_sqptr_proc;
  wire [15:0] qp_curr_sqptr_proc;
  wire [15:0] qp_sq_depth;
  wire [C_M_AXI_ADDR_WIDTH -1:0] sq_read_addr_to_axi;
  wire [511:0] wqe_qid_inserted;
  wire qp_cq_hdptr_req_retry;
  wire qp_cq_hdptr_valid_retry;
  wire [C_QP_INDX_WIDTH -1: 0] qp_cq_hdptr_idx_retry;
  wire [15:0]                  qp_curr_sqptr_proc_retry;
  wire                         qp_curr_sqptr_proc_wen_retry;
  wire [C_QP_INDX_WIDTH -1: 0] qp_curr_sqptr_proc_idx_retry;   // Index for writing curent SQ pointer
  wire                          qp_sq_psn_req_retry;
  wire                          qp_sq_psn_wrn_retry;
  wire  [23:0]                  qp_sq_psn_retry;
  wire  [C_QP_INDX_WIDTH -1: 0] qp_sq_psn_idx_retry;   // Index for reading Q depth
  wire  [C_QP_INDX_WIDTH -1: 0] qp_stat_ssn_idx_retry;   // Index for reading/writing MSN
  wire  [23:0]                  qp_stat_ssn_retry; // Expected MSN for Qp incoming messages write data from hdr validation
  wire                          qp_stat_ssn_req_retry;
  wire                          qp_stat_ssn_wrn_retry;
  wire  [511:0]                 wqe_from_fifo;
  wire  [511:0]                 wqe_to_fifo;
  wire  [511:0]                 cached_wqe;
  wire                          wqe_fifo_push_retry;
  wire                          wqe_fifo_pop_retry;
  wire cache_halted;
  wire qp_sq_psn_retry_valid;
  wire                          qp_stat_wqe_cnt_valid;
  wire                          qp_stat_wqe_cnt_rdreq;
  wire [15:0]                   qp_stat_wqe_cnt;
  wire [15:0]                   new_qp_stat_wqe_cnt;

  wire 		dbg_bram_wen ;
  wire	[120:0]	dbg_bram_wdata;
  wire	[9:0]	dbg_bram_raddr;
  wire	[120:0] dbg_bram_rdata;
  reg	[9:0]	dbg_bram_waddr;
  reg	[7:0]	axi_rd_err_cnt_ff;
  reg axi_ren_valid_ff;
  reg [C_QP_INDX_WIDTH -1 :0] qp_sq_arbitrated_idx_ff;
  reg [C_NUM_QP -1:0] osq_almost_full_ff;
  reg wqe_empty_ff;

  wire [23:0] qp_stat_ret_sq_psn_int;
  wire [C_QP_INDX_WIDTH -1: 0] qp_stat_ret_sq_psn_idx_int;

  assign qp_fatal_err_ored = |(i_qp_fatal_err);               // QPs those are stalled due to fatal error

  assign num_elements_enabled = o_num_qp_en; //C_NUM_QP;

rdma_config_reg
#(
    .C_S_AXI_LITE_ADDR_WIDTH    (C_S_AXI_LITE_ADDR_WIDTH),
    .C_S_AXI_LITE_DATA_WIDTH    (C_S_AXI_LITE_DATA_WIDTH),
    .C_NUM_QP                   (C_NUM_QP               ),
    .C_QP_INDX_WIDTH            (C_QP_INDX_WIDTH        ),
    .STB_WIDTH                  (STB_WIDTH              ),
    .RESP_WIDTH                 (RESP_WIDTH             ),
    .C_EN_DEBUG_REGS            (C_EN_DEBUG_REGS        )
) inst_rdma_config_reg
(
  .s_axi_lite_aclk              (s_axi_lite_aclk   ),
  .s_axi_lite_aresetn           (s_axi_lite_aresetn),

  .s_axi_lite_awaddr            (s_axi_lite_awaddr ),
  .s_axi_lite_awready           (s_axi_lite_awready),
  .s_axi_lite_awvalid           (s_axi_lite_awvalid),

  .s_axi_lite_araddr            (s_axi_lite_araddr ),
  .s_axi_lite_arready           (s_axi_lite_arready),
  .s_axi_lite_arvalid           (s_axi_lite_arvalid),

  .s_axi_lite_wdata             (s_axi_lite_wdata ),
  .s_axi_lite_wstrb             (s_axi_lite_wstrb ),
  .s_axi_lite_wready            (s_axi_lite_wready),
  .s_axi_lite_wvalid            (s_axi_lite_wvalid),

  .s_axi_lite_rdata             (s_axi_lite_rdata ),
  .s_axi_lite_rresp             (s_axi_lite_rresp ),
  .s_axi_lite_rready            (s_axi_lite_rready),
  .s_axi_lite_rvalid            (s_axi_lite_rvalid),

  .s_axi_lite_bresp             (s_axi_lite_bresp ),
  .s_axi_lite_bready            (s_axi_lite_bready),
  .s_axi_lite_bvalid            (s_axi_lite_bvalid),

  .i_status_upd_needed          (status_upd_needed),
  .i_status_upd_indx            (qp_sq_arbitrated_idx_ff),

  .i_pkt_valdn_err_intr         (i_pkt_valdn_err_intr      ),
  .i_mad_pkt_rcvd_intr          (i_mad_pkt_rcvd_intr       ),
  .i_bypass_pkt_rcvd_intr       (i_bypass_pkt_rcvd_intr    ),
  .i_rnr_nack_gen_intr          (i_rnr_nack_gen_intr        ),
  .i_ill_opc_in_sq_intr         (i_ill_opc_in_sq_intr      ),
  .i_qp_pkt_rcvd_intr           (i_qp_pkt_rcvd_intr       ),

  .o_intr_clr_pkt_valdn_err     (o_intr_clr_pkt_valdn_err  ),
  .o_intr_clr_wqe_cmpl           (o_intr_clr_wqe_cmpl       ),
  .o_intr_clr_mad_pkt_rcvd      (o_intr_clr_mad_pkt_rcvd   ),
  .o_intr_clr_bypass_pkt_rcvd   (o_intr_clr_bypass_pkt_rcvd),
  .o_intr_clr_rnr_nak_gen       (o_intr_clr_rnr_nak_gen    ),
  .o_intr_clr_ill_opc_in_sq     (o_intr_clr_ill_opc_in_sq     ),
  .o_intr_clr_qp_pkt_rcvd       (o_intr_clr_qp_pkt_rcvd       ),
  .o_intr_clr_fatal_err		(o_intr_clr_fatal_err),

  .o_intr_en_pkt_valdn_err      (o_intr_en_pkt_valdn_err     ),
  .o_intr_en_wqe_cmpl           (o_intr_en_wqe_cmpl          ),
  .o_intr_en_mad_pkt_rcvd       (o_intr_en_mad_pkt_rcvd      ),
  .o_intr_en_bypass_pkt_rcvd    (o_intr_en_bypass_pkt_rcvd   ),
  .o_intr_en_rnr_nak_gen        (o_intr_en_rnr_nak_gen       ),
  .o_intr_en_ill_opc_in_sq      (o_intr_en_ill_opc_in_sq     ),
  .o_intr_en_fatal_err          (o_intr_en_fatal_err         ),
  .o_intr_en_qp_pkt_rcvd        (o_intr_en_qp_pkt_rcvd       ),

  .i_qp_wq_cmpl_intr            (i_qp_wq_cmpl_intr),
  .o_rq_intr_sts_clr            (o_rq_intr_sts_clr),
  .o_cq_intr_sts_clr            (o_cq_intr_sts_clr),

  .i_qp_fatal_err               (i_qp_fatal_err),
  .o_qp_clr_fatal_err           (o_qp_clr_fatal_err),

  .i_rq_full                    (i_rq_full  ),
  .i_osq_full                   (i_osq_full ),
  .i_osq_almost_full            (i_osq_almost_full ),
  .i_cq_full                    (i_cq_full  ),
  .i_rq_empty                   (i_rq_empty ),
  .i_osq_empty                  (i_osq_empty),
  .i_qp_retried                 (i_qp_retried),
  .i_stat_retry_cnt             (i_stat_retry_cnt),
  .i_min_ipg_stat               (i_min_ipg_stat ),
  .i_ipg_0_4_cnt                (i_ipg_0_4_cnt  ),
  .i_ipg_5_9_cnt                (i_ipg_5_9_cnt  ),
  .i_ipg_10_14_cnt              (i_ipg_10_14_cnt),
  .i_ipg_15_19_cnt              (i_ipg_15_19_cnt),

  .o_rx_pkt_hndl_dbg_ctrl       (o_rx_pkt_hndl_dbg_ctrl),

  .i_qp_stat_msn_idx            (i_qp_stat_msn_idx),
  .i_qp_stat_msn                (i_qp_stat_msn    ),
  .o_qp_stat_msn                (o_qp_stat_msn    ),
  .i_qp_stat_msn_req            (i_qp_stat_msn_req  ),
  .i_qp_stat_msn_wrn            (i_qp_stat_msn_wrn  ),
  .o_qp_stat_msn_valid          (o_qp_stat_msn_valid),

  .i_qp_stat_ssn_idx            ((qp_stat_ssn_req_retry | qp_stat_ssn_wrn_retry) ? qp_stat_ssn_idx_retry: i_qp_stat_ssn_idx),
  .i_qp_stat_ssn                (qp_stat_ssn_wrn_retry ? qp_stat_ssn_retry : i_qp_stat_ssn    ),
  .o_qp_stat_ssn                (o_qp_stat_ssn    ),
  .i_qp_stat_ssn_req            (i_qp_stat_ssn_req | qp_stat_ssn_req_retry), // can be ORed as WQE is halted
  .i_qp_stat_ssn_wrn            (i_qp_stat_ssn_wrn | qp_stat_ssn_wrn_retry ),// can be ORed as WQE is halted
  .o_qp_stat_ssn_valid          (o_qp_stat_ssn_valid),

  .i_qp_timeout_idx             (i_qp_conf_idx),//i_qp_timeout_idx),
  .o_qp_timeout                 (o_qp_timeout),

  .i_qp_rq_pi_db_idx            (i_qp_rq_pi_db_idx),
  .i_qp_rq_pi_db                (i_qp_rq_pi_db    ),
  .o_qp_rq_pi_db                (o_qp_rq_pi_db    ),
  .i_qp_rq_pi_db_req            (i_qp_rq_pi_db_req  ),
  .i_qp_rq_pi_db_wrn            (i_qp_rq_pi_db_wrn  ),
  .o_qp_rq_pi_db_valid          (o_qp_rq_pi_db_valid),

  .i_qp_stat_wqe_cnt            (new_qp_stat_wqe_cnt),
  .i_qp_stat_wqe_cnt_wen        (update_qp_stat_wqe_cnt),
  .i_qp_stat_wqe_cnt_idx        (qp_sq_arbitrated_idx_ff),
  .o_qp_stat_wqe_cnt_valid      (qp_stat_wqe_cnt_valid),
  .i_qp_stat_wqe_cnt_rdreq      (qp_stat_wqe_cnt_rdreq),
  .o_qp_stat_wqe_cnt            (qp_stat_wqe_cnt),

  .i_qp_ret_sq_psn_idx          (i_qp_stat_ret_sq_psn_req ? i_qp_stat_ret_sq_psn_idx : qp_stat_ret_sq_psn_idx_int),
  .i_qp_ret_sq_psn              (qp_stat_ret_sq_psn_int),
  .o_qp_ret_sq_psn              (o_qp_stat_ret_sq_psn),
  .i_qp_ret_sq_psn_req          (i_qp_stat_ret_sq_psn_req),
  .i_qp_ret_sq_psn_wrn          (i_qp_stat_ret_sq_psn_req ? 1'b0 : qp_stat_ret_sq_psn_wen_int),
  .o_qp_ret_sq_psn_valid        (o_qp_stat_ret_sq_psn_valid),
  .o_qp_ret_sq_psn_valid_int    (qp_stat_ret_sq_psn_valid_int),  // from QPM

  .o_rdma_en                   (o_rdma_en               ),
  .o_rdma_adv_conf_sw_override (sw_override_en           ),
  .o_rdma_adv_conf_errbuf_overwr_en (o_rdma_adv_conf_errbuf_overwr_en ),
  .o_rdma_adv_base_cnt (o_rdma_adv_base_cnt),
  .o_tx_ack_gen                 (o_tx_ack_gen             ),
  .o_err_buf_en                 (o_err_buf_en             ),
  .o_flow_credits               (o_flow_credits             ),
  .o_rdma_udp_src_port         (o_rdma_udp_src_port     ),
  .o_depkt_bypass_en            (o_depkt_bypass_en        ),
  .o_num_qp_en                  (o_num_qp_en              ),
  .o_mac_rdma_addr             (o_mac_rdma_addr           ),
  .o_ipv4_rdma_addr            (o_ipv4_rdma_addr          ),
  .o_ipv6_rdma_addr            (o_ipv6_rdma_addr          ),
  .o_bypass_buf_ba              (o_bypass_buf_ba          ),
  .o_bypass_buf_sz_num_bufs     (o_bypass_buf_sz_num_bufs ),
  .o_bypass_buf_sz_buf_sz       (o_bypass_buf_sz_buf_sz   ),
  .o_data_buf_ba                (o_data_buf_ba          ),
  .o_data_buf_sz_num_bufs       (o_data_buf_sz_num_bufs ),
  .o_data_buf_sz_buf_sz         (o_data_buf_sz_buf_sz   ),
  .o_connect_io_qp_rq_pi_db_wptr              (o_connect_io_qp_rq_pi_db_wptr        ),
  .i_connect_io_qp_rq_pi_db_rdy	(i_connect_io_qp_rq_pi_db_rdy),  // Ready indicates can accept another
  //.o_connect_io_residual_rq     (o_connect_io_residual_rq),
  .o_rq_pi_db_hw_hndshk         (o_rq_pi_db_hw_hndshk),
  .o_hw_hndshk_disable_to_0     (o_hw_hndshk_disable_to_0 ),
  .i_bypass_buf_wrptr           (i_bypass_buf_wrptr       ),
  .o_rq_err_pkt_buf_ba          (o_rq_err_pkt_buf_ba         ),
  .o_rq_err_pkt_buf_sz_num_bufs (o_rq_err_pkt_buf_sz_num_bufs),
  .o_rq_err_pkt_buf_sz_buf_sz   (o_rq_err_pkt_buf_sz_buf_sz  ),
  .o_resp_err_pkt_buf_ba          (o_resp_err_pkt_buf_ba         ),
  .o_resp_err_pkt_buf_sz_num_bufs (o_resp_err_pkt_buf_sz_num_bufs),
  .o_resp_err_pkt_buf_sz_buf_sz   (o_resp_err_pkt_buf_sz_buf_sz  ),
  .i_inc_rresp_pkt_cnt          (i_inc_rresp_pkt_cnt      ),
  .i_inc_send_pkt_cnt           (i_inc_send_pkt_cnt       ),
  .i_inc_ack_pkt_cnt            (i_inc_ack_pkt_cnt        ),
  .i_inc_mad_pkt_cnt            (i_inc_mad_pkt_cnt        ),
  .i_inc_all_dropped_cnt        (i_inc_all_dropped_cnt    ),
  .i_inc_nack_cnt               (i_inc_nack_cnt           ),

  .i_out_rdwr_pkt_cnt           (i_out_rdwr_pkt_cnt       ),
  .i_out_send_pkt_cnt           (i_out_send_pkt_cnt       ),
  .i_out_mad_pkt_cnt            (i_out_mad_pkt_cnt        ),
  .i_out_ack_pkt_cnt            (i_out_ack_pkt_cnt        ),
  .i_out_nack_cnt               (i_out_nack_cnt           ),
  .i_resp_hndler_sts            (i_resp_hndler_sts        ),

  .i_inc_inv_pkt_cnt            (i_inc_inv_pkt_cnt        ),
  .i_inc_dup_pkt_cnt            (i_inc_dup_pkt_cnt        ),
  .o_rdma_conf_ipver           (o_rdma_conf_ipver       ),
  .o_hw_wqe_remote_addr_lo    (o_hw_wqe_remote_addr_lo ),
  .o_hw_wqe_remote_addr_hi    (o_hw_wqe_remote_addr_hi ),
  .o_hw_wqe_rkey              (o_hw_wqe_rkey           ),
  .o_hw_wqe_local_addr        (o_hw_wqe_local_addr     ),
  .o_hw_wqe_opcode            (o_hw_wqe_opcode         ),
  .o_hw_wqe_wrid              (o_hw_wqe_wrid           ),

  .o_sq_full                    (sq_full),
  .o_sq_empty                   (sq_empty),

  .core_clk                     (core_clk      ),
  .core_rstn                    (core_rstn     ),	    // Active high core reset

  .i_qp_conf_req_wqe_proc       (i_qp_conf_req_wqe_proc  ),
  .i_qp_conf_req_resp_hndl      (i_qp_conf_req_resp_hndl ),
  .i_qp_conf_req_rx_pkt         (i_qp_conf_req_rx_pkt  ),
  .o_qp_conf_valid_wqe_proc     (o_qp_conf_valid_wqe_proc),
  .o_qp_conf_valid_resp_hndl    (o_qp_conf_valid_resp_hndl),
  .o_qp_conf_valid_rx_pkt       (o_qp_conf_valid_rx_pkt ),
  .o_qp_conf                    (o_qp_conf     ),        // QP configuration
  .i_qp_conf_idx                (i_qp_conf_idx ),    // Index for reading Qp configuration

  .o_qp_conf_replica            (o_qp_conf_replica      ),        // QP configuration REPLICA
  .i_qp_conf_replica_idx        (i_qp_conf_replica_idx  ),    // Index for reading Qp configuration REPLICA
  .i_qp_conf_replica_req        (i_qp_conf_replica_req  ),
  .o_qp_conf_replica_valid      (o_qp_conf_replica_valid),

  .i_qp_adv_conf_req            (i_qp_adv_conf_req  ),
  .o_qp_adv_conf_valid          (o_qp_adv_conf_valid),
  .o_qp_adv_conf                (o_qp_adv_conf     ),        // QP configuration
  .i_qp_adv_conf_idx            (i_qp_adv_conf_idx ),    // Index for reading Qp configuration

  .i_qp_rq_ba_req               (i_qp_rq_ba_req  ),
  .o_qp_rq_ba_valid             (o_qp_rq_ba_valid),
  .o_qp_rq_ba                   (o_qp_rq_ba    ),
  .i_qp_rq_ba_idx               (i_qp_rq_ba_idx),   // Index for reading Qp RQ Buffer BA

  .i_qp_sq_ba_req_int           (qp_sq_ba_req_int  ),
  .i_qp_sq_ba_req               (i_qp_sq_ba_req  ),
  .o_qp_sq_ba_valid_int         (qp_sq_ba_valid_int),
  .o_qp_sq_ba_valid             (o_qp_sq_ba_valid),
  .o_qp_sq_ba                   (qp_sq_ba    ),
  .i_qp_sq_ba_idx               (i_qp_sq_ba_req ? i_qp_sq_ba_idx : qp_sq_arbitrated_idx_ff),   // Index for reading Qp SQ BA

  .i_qp_cq_ba_req               (i_qp_cq_ba_req  ),
  .o_qp_cq_ba_valid             (o_qp_cq_ba_valid),
  .o_qp_cq_ba                   (o_qp_cq_ba    ),
  .i_qp_cq_ba_idx               (i_qp_cq_ba_idx),   // Index for reading Qp SQ BA

  .i_qp_rq_wrptrdb_add_req      (i_qp_rq_wrptrdb_add_req  ),
  .o_qp_rq_wrptrdb_add_valid    (o_qp_rq_wrptrdb_add_valid),
  .o_qp_rq_wrptrdb_add          (o_qp_rq_wrptrdb_add),
  .i_qp_rq_wrptrdb_add_idx      (i_qp_rq_wrptrdb_add_idx),   // Index for reading Qp SQ BA

  .i_qp_sq_cmpldb_add_req       (i_qp_sq_cmpldb_add_req  ),
  .o_qp_sq_cmpldb_add_valid     (o_qp_sq_cmpldb_add_valid),
  .o_qp_sq_cmpldb_add           (o_qp_sq_cmpldb_add),
  .i_qp_sq_cmpldb_add_idx       (i_qp_sq_cmpldb_add_idx),   // Index for reading SQ Completion DB address

  .i_qp_cq_hdptr_req            (i_qp_cq_hdptr_req), // ORing as resp_handler halted
  .i_qp_cq_hdptr_retry_req      (qp_cq_hdptr_req_retry), // ORing as resp_handler halted
  .o_qp_cq_hdptr_valid          (o_qp_cq_hdptr_valid),
  .o_qp_cq_hdptr_valid_retry    (qp_cq_hdptr_valid_retry),
  .o_qp_cq_hdptr                (qp_cq_hdptr_from_config ),
  .i_qp_cq_hdptr                (i_qp_cq_hdptr    ),
  .i_qp_cq_hdptr_wrn            (i_qp_cq_hdptr_wrn),
  .i_qp_cq_hdptr_idx            (qp_cq_hdptr_req_retry ? qp_cq_hdptr_idx_retry : i_qp_cq_hdptr_idx),   // Index for reading CQ head pointer

  .i_qp_rq_cidb_req             (i_qp_rq_cidb_req  ),
  .o_qp_rq_cidb_valid           (o_qp_rq_cidb_valid),
  .o_qp_rq_cidb                 (o_qp_rq_cidb     ),
  .i_qp_rq_cidb_idx             (i_qp_rq_cidb_idx ),   // Index for reading RQ CI DB

  .o_qp_sq_pidb                 (qp_sq_pidb     ),
  .i_qp_sq_pidb_idx             (qp_sq_arbitrated_idx_ff),   // Index for reading SQ PI DB
  .i_qp_sq_pidb_req             (qp_sq_pidb_req   ),
  .o_qp_sq_pidb_valid           (qp_sq_pidb_valid ),

  .i_qp_sq_pidb_hndshk          (i_qp_sq_pidb_hndshk ),
  .i_qp_sq_pidb_wr_addr_hndshk  (i_qp_sq_pidb_wr_addr_hndshk),
  .i_qp_sq_pidb_wr_valid_hndshk (i_qp_sq_pidb_wr_valid_hndshk ),
  .o_qp_sq_pidb_wr_rdy          (o_qp_sq_pidb_wr_rdy),

//  .i_qp_sq_pidb_hndshk          ('b0),
//  .i_qp_sq_pidb_idx_hndshk      ('b0),
//  .i_qp_sq_pidb_wr_valid_hndshk ('b0),
//  .o_qp_sq_pidb_wr_rdy          (o_qp_sq_pidb_wr_rdy),

  .i_qp_rq_cidb_hndshk          (i_qp_rq_cidb_hndshk         ),
  .i_qp_rq_cidb_wr_addr_hndshk  (i_qp_rq_cidb_wr_addr_hndshk ),
  .i_qp_rq_cidb_wr_valid_hndshk (i_qp_rq_cidb_wr_valid_hndshk),
  .o_qp_rq_cidb_wr_rdy          (o_qp_rq_cidb_wr_rdy         ),

  .i_qp_rq_depth_req            (i_qp_rq_depth_req  ),
  .o_qp_rq_depth_valid          (o_qp_rq_depth_valid),
  .o_qp_rq_depth                (o_qp_rq_depth     ),
  .i_qp_rq_depth_idx            (i_qp_rq_depth_idx ),

  .i_qp_sq_depth_req            (qp_sq_depth_req  ),
  .o_qp_sq_depth_valid          (qp_sq_depth_valid),
  .o_qp_sq_depth                (qp_sq_depth     ),
  .i_qp_sq_depth_idx            (qp_sq_arbitrated_idx_ff),

  .i_qp_cq_depth_req            (i_qp_cq_depth_req  ),
  .o_qp_cq_depth_valid          (o_qp_cq_depth_valid),
  .o_qp_cq_depth_rdy            (o_qp_cq_depth_rdy  ),
  .o_qp_cq_depth                (o_qp_cq_depth      ),
  .i_qp_cq_depth_idx            (i_qp_cq_depth_idx  ),

  .i_qp_sq_psn_req              (i_qp_sq_psn_req), // highest priority from RX pkt handler
  .i_qp_sq_psn_wqe_req          (i_qp_sq_psn_wqe_req), // can be ORed as WQE is halted
  .i_qp_sq_psn_retry_req        (qp_sq_psn_req_retry ), // can be ORed as WQE is halted
  .o_qp_sq_psn_valid            (o_qp_sq_psn_valid),
  .o_qp_sq_psn_wqe_valid        (o_qp_sq_psn_wqe_valid),
  .o_qp_sq_psn_retry_valid      (qp_sq_psn_retry_valid),
  .o_qp_sq_psn                  (o_qp_sq_psn       ),
  .i_qp_sq_psn                  (qp_sq_psn_wrn_retry ? qp_sq_psn_retry : i_qp_sq_psn),
  .i_qp_sq_psn_wrn              (i_qp_sq_psn_wrn   ), // can be ORed as WQE is halted
  .i_qp_sq_psn_retry_wrn        (qp_sq_psn_wrn_retry  ), // can be ORed as WQE is halted
  .i_qp_sq_psn_idx              (i_qp_sq_psn_idx        ),   // Index for reading PSN
  .i_qp_sq_psn_wqe_idx          (i_qp_sq_psn_wqe_idx    ),   // Index for reading PSN
  .i_qp_sq_psn_retry_idx        (qp_sq_psn_idx_retry    ),   // Index for reading PSN

  .o_qp_last_rq                 (o_qp_last_rq       ),
  .i_qp_last_rq_idx             (i_qp_last_rq_idx   ),
  .i_qp_last_rq                 (i_qp_last_rq    ),
  .i_qp_last_rq_req             (i_qp_last_rq_req),
  .i_qp_last_rq_wrn             (i_qp_last_rq_wrn),
  .o_qp_last_rq_valid           (o_qp_last_rq_valid),

  //.i_qp_rnr_nck_tval_curr_retry_req (i_qp_rnr_nck_tval_curr_retry_req),
  //.i_qp_rnr_nck_tval_curr_retry_wrn (i_qp_rnr_nck_tval_curr_retry_wrn),
  //.i_qp_rnr_nck_tval_curr_retry     (i_qp_rnr_nck_tval_curr_retry    ),

  .i_qp_dest_qpid_req_wqe_proc  (i_qp_dest_qpid_req_wqe_proc),
  .i_qp_dest_qpid_req_rx_pkt    (i_qp_dest_qpid_req_rx_pkt),
  .o_qp_dest_qpid_valid_wqe_proc(o_qp_dest_qpid_valid_wqe_proc),
  .o_qp_dest_qpid_valid_rx_pkt  (o_qp_dest_qpid_valid_rx_pkt),
  .o_qp_dest_qpid               (o_qp_dest_qpid    ),
  .i_qp_dest_qpid_idx           (i_qp_dest_qpid_idx),   // Index for reading Q depth

  .o_tx_hdr_buf_ba              (o_tx_hdr_buf_ba         ),
  .o_tx_hdr_buf_sz_num_hdrs     (o_tx_hdr_buf_sz_num_hdrs),
  .o_tx_hdr_buf_sz_buf_sz       (o_tx_hdr_buf_sz_buf_sz  ),
  .o_tx_sgl_buf_ba              (o_tx_sgl_buf_ba         ),
  .o_tx_sgl_buf_sz_num_sgls     (o_tx_sgl_buf_sz_num_sgls),
  .o_tx_sgl_buf_sz_buf_sz       (o_tx_sgl_buf_sz_buf_sz  ),

  .o_timeoutreg                 (o_timeoutreg      ),
  .o_qp_disable_pulse           (o_qp_disable_pulse),

  .o_out_errsts_q_ba            (o_out_errsts_q_ba   ),
  .o_out_errsts_q_sz            (o_out_errsts_q_sz   ),
  .i_out_errsts_q_wrptr         (i_out_errsts_q_wrptr),

  .o_in_errsts_q_ba             (o_in_errsts_q_ba    ),
  .o_in_errsts_q_sz             (o_in_errsts_q_sz    ),
  .i_in_errsts_q_wrptr          (i_in_errsts_q_wrptr ),

  .i_qp_mac_remote_addrl_req      (i_qp_mac_remote_addrl_req  ),
  .o_qp_mac_remote_addrl_valid    (o_qp_mac_remote_addrl_valid),
  .i_qp_mac_remote_addrl_wqe_req  (i_qp_mac_remote_addrl_wqe_req  ),
  .o_qp_mac_remote_addrl_wqe_valid(o_qp_mac_remote_addrl_wqe_valid),
  .o_qp_mac_remote_addrl          (o_qp_mac_remote_addrl),
  .i_qp_mac_remote_addrl_idx      (i_qp_mac_remote_addrl_idx),   // Index for reading Q depth
  .i_qp_mac_remote_addrl_wqe_idx      (i_qp_mac_remote_addrl_wqe_idx),   // Index for reading Q depth

  .o_qp_mac_remote_addrl_replica        (o_qp_mac_remote_addrl_replica      ),
  .i_qp_mac_remote_addrl_replica_idx    (i_qp_mac_remote_addrl_replica_idx  ),   // Index for reading Q depth
  .i_qp_mac_remote_addrl_replica_req    (i_qp_mac_remote_addrl_replica_req  ),
  .o_qp_mac_remote_addrl_replica_valid  (o_qp_mac_remote_addrl_replica_valid),

  .i_qp_mac_remote_addrm_req            (i_qp_mac_remote_addrm_req  ),
  .o_qp_mac_remote_addrm_valid          (o_qp_mac_remote_addrm_valid),
  .i_qp_mac_remote_addrm_wqe_req        (i_qp_mac_remote_addrm_wqe_req  ),
  .o_qp_mac_remote_addrm_wqe_valid      (o_qp_mac_remote_addrm_wqe_valid),
  .o_qp_mac_remote_addrm                (o_qp_mac_remote_addrm    ),
  .i_qp_mac_remote_addrm_idx            (i_qp_mac_remote_addrm_idx),   // Index for reading Q depth
  .i_qp_mac_remote_addrm_wqe_idx        (i_qp_mac_remote_addrm_wqe_idx),   // Index for reading Q depth

  .o_qp_mac_remote_addrm_replica        (o_qp_mac_remote_addrm_replica      ),
  .i_qp_mac_remote_addrm_replica_idx    (i_qp_mac_remote_addrm_replica_idx  ),   // Index for reading Q depth
  .i_qp_mac_remote_addrm_replica_req    (i_qp_mac_remote_addrm_replica_req  ),
  .o_qp_mac_remote_addrm_replica_valid  (o_qp_mac_remote_addrm_replica_valid),

  .i_qp_ip_remote_addr1_req             (i_qp_ip_remote_addr1_req  ),
  .o_qp_ip_remote_addr1_valid           (o_qp_ip_remote_addr1_valid),
  .i_qp_ip_remote_addr1_wqe_req         (i_qp_ip_remote_addr1_wqe_req  ),
  .o_qp_ip_remote_addr1_wqe_valid       (o_qp_ip_remote_addr1_wqe_valid),
  .o_qp_ip_remote_addr1                 (o_qp_ip_remote_addr1     ),
  .i_qp_ip_remote_addr1_idx             (i_qp_ip_remote_addr1_idx ),   // Index for reading Q depth
  .i_qp_ip_remote_addr1_wqe_idx         (i_qp_ip_remote_addr1_wqe_idx ),   // Index for reading Q depth

  .o_qp_ip_remote_addr1_replica         (o_qp_ip_remote_addr1_replica      ),
  .i_qp_ip_remote_addr1_replica_idx     (i_qp_ip_remote_addr1_replica_idx  ),   // Index for reading Q depth
  .i_qp_ip_remote_addr1_replica_req     (i_qp_ip_remote_addr1_replica_req  ),
  .o_qp_ip_remote_addr1_replica_valid   (o_qp_ip_remote_addr1_replica_valid),


  .i_qp_curr_sqptr_proc         (qp_curr_sqptr_proc_wen_retry ? qp_curr_sqptr_proc_retry : new_curr_sqptr_proc    ),
  .i_qp_curr_sqptr_rdreq        (qp_curr_sqptr_req),
  .i_qp_curr_sqptr_proc_wen     (update_curr_sqptr | qp_curr_sqptr_proc_wen_retry), // Canbe ORed since QP cache is halted
  .i_qp_curr_sqptr_proc_idx     (qp_curr_sqptr_proc_wen_retry ? qp_curr_sqptr_proc_idx_retry : qp_sq_arbitrated_idx_ff),
  .o_qp_curr_sqptr_proc_valid   (qp_curr_sqptr_proc_valid),
  .o_qp_curr_sqptr_proc         (qp_curr_sqptr_proc    ),

  .i_qp_stat_resp_psn           (i_qp_stat_resp_psn      ),
  .i_qp_stat_resp_psn_wen       (i_qp_stat_resp_psn_wen  ),
  .i_qp_stat_resp_psn_idx       (i_qp_stat_resp_psn_idx  ),
  .o_qp_stat_resp_psn_valid     (o_qp_stat_resp_psn_valid),
  .i_qp_stat_resp_psn_rdreq     (i_qp_stat_resp_psn_rdreq),
  .o_qp_stat_resp_psn           (o_qp_stat_resp_psn      ),

  .i_qp_stat_rq_buf_ca          (i_qp_stat_rq_buf_ca      ),
  .i_qp_stat_rq_buf_ca_wen      (i_qp_stat_rq_buf_ca_wen  ),
  .i_qp_stat_rq_buf_ca_idx      (i_qp_stat_rq_buf_ca_idx  ),
  .o_qp_stat_rq_buf_ca_valid    (o_qp_stat_rq_buf_ca_valid),
  .i_qp_stat_rq_buf_ca_rdreq    (i_qp_stat_rq_buf_ca_rdreq),
  .o_qp_stat_rq_buf_ca          (o_qp_stat_rq_buf_ca      ),

  .i_qp_stat_nak                (i_qp_stat_nak      ),
  .i_qp_stat_nak_wen            (i_qp_stat_nak_wen  ),
  .i_qp_stat_nak_idx            (i_qp_stat_nak_idx  ),
  .o_qp_stat_nak_valid          (o_qp_stat_nak_valid),
  .i_qp_stat_nak_rdreq          (i_qp_stat_nak_rdreq),
  .o_qp_stat_nak                (o_qp_stat_nak      ),

   .i_qp_stat_retry_cnt		(3'h0)				,
   .i_qp_stat_retry_cnt_wen	(1'b0)				,
   .i_qp_stat_retry_cnt_idx	({C_QP_INDX_WIDTH{1'b0}})	,
   .o_qp_stat_retry_cnt_valid	()				,
   .i_qp_stat_retry_cnt_rdreq	(1'b0)				,
   .o_qp_stat_retry_cnt		()				,

  .o_global_dbg_cnt_value	(o_global_dbg_cnt_value     ),
  .o_global_dbg_cnt_clr		(o_global_dbg_cnt_clr	    ),
  .o_global_dbg_cnt_en		(o_global_dbg_cnt_en	    ),
  .i_wqe_fsm_idle_cnt		(i_wqe_fsm_idle_cnt	    ),
  .i_wqe_proc_rd_wqe_cnt    (i_wqe_proc_rd_wqe_cnt    )  ,
  .i_wqe_proc_rd_q_info_cnt (i_wqe_proc_rd_q_info_cnt )  ,
  .i_wqe_proc_wait0_cnt     (i_wqe_proc_wait0_cnt     )  ,
  .i_wqe_proc_ip_chksum_cnt (i_wqe_proc_ip_chksum_cnt )  ,
  .i_wqe_proc_hdr_gen_cnt   (i_wqe_proc_hdr_gen_cnt   )  ,
  .i_wqe_proc_hdr_sto_cnt   (i_wqe_proc_hdr_sto_cnt   )  ,
  .i_hdr_backpressure_cnt	(i_hdr_backpressure_cnt     ),
  .i_retry_tx_backpressure_cnt	(i_retry_tx_backpressure_cnt),

  .i_dbg_bram_rdata		(dbg_bram_rdata),
  .o_dbg_bram_raddr		(dbg_bram_raddr),

  .i_axi_rd_err_cnt		(axi_rd_err_cnt_ff),

  .i_last_in_pkt_info           (i_last_in_pkt_info),
  .i_last_out_pkt_info          (i_last_out_pkt_info),

  .i_wqe_proc_sts               (i_wqe_proc_sts),
  .i_qp_mgr_sts                 ({stat_wqe_cnt ,8'b0 ,1'b0, cache_fsm_status, 2'b0, wqe_empty, wqe_full}),
  .i_rx_pkt_vld_sts             (i_rx_pkt_vld_sts)

  );

  assign o_qp_cq_hdptr = qp_cq_hdptr_from_config;
  assign o_qp_sq_ba = qp_sq_ba;

  // Single QP: no arbitration needed
  // Use sample_arbitrated_sq (active in GET_ARBITRATED_SQ state) instead of
  // arbitrate (active in ARBITRATE_SQ state) to avoid deadlock:
  // GET_ARBITRATED_SQ waits for arbitration_done, but arbitrate is only set
  // in ARBITRATE_SQ, creating a circular dependency.
  assign arbitration_done   = sample_arbitrated_sq & ~(|sq_empty) & ~(|i_osq_almost_full) & ~(|i_qp_rnr_nacked);
  assign qp_sq_arbitrated_idx = {C_QP_INDX_WIDTH{1'b0}};

`MSFF_R(osq_almost_full_ff, i_osq_almost_full, core_clk, ~core_rstn)

qp_mgr_cache
#(
    .C_NUM_QP               (C_NUM_QP),
    .C_M_AXI_ADDR_WIDTH     (C_M_AXI_ADDR_WIDTH),
    .C_QP_INDX_WIDTH        (C_QP_INDX_WIDTH)
) inst_qp_mgr_cache
(
    .core_clk               (core_clk),
    .core_rstn              (core_rstn),

    .o_fsm_status           (cache_fsm_status),
    .o_stat_num_wqe_cnt     (stat_wqe_cnt),

    .i_sq_empty             (sq_empty),
    .i_osq_almost_full      (osq_almost_full_ff),
    .i_qp_sq_arbitrated_idx (qp_sq_arbitrated_idx_ff),
    .i_wqe_fifo_full        (wqe_full),
    .i_arbitration_done     (arbitration_done),
    .o_arbitrate            (arbitrate),
    .o_sample_arbitrated_sq (sample_arbitrated_sq),

    .o_status_upd_needed    (status_upd_needed),

    .o_qp_sq_ba_req         (qp_sq_ba_req_int),
    .i_qp_sq_ba_valid       (qp_sq_ba_valid_int),
    .i_qp_sq_ba             (qp_sq_ba),

    .o_qp_sq_depth_req      (qp_sq_depth_req),
    .i_qp_sq_depth_valid    (qp_sq_depth_valid),
    .i_qp_sq_depth          (qp_sq_depth),

    .o_qp_sq_pidb_req       (qp_sq_pidb_req),
    .i_qp_sq_pidb_valid     (qp_sq_pidb_valid),
    .i_qp_sq_pidb           (qp_sq_pidb),

    .o_qp_curr_sqptr_rdreq  (qp_curr_sqptr_req),
    .i_qp_curr_sqptr_valid  (qp_curr_sqptr_proc_valid),
    .i_qp_curr_sqptr_proc   (qp_curr_sqptr_proc),
    .o_qp_curr_sqptr        (new_curr_sqptr_proc),
    .o_update_curr_sqptr    (update_curr_sqptr),

    .i_sw_override_en       (sw_override_en),
    .i_rdma_en		    (o_rdma_en),

    .i_halt                 (halt),
    .o_halted               (cache_halted),
    .i_qp_stat_wqe_cnt_valid(qp_stat_wqe_cnt_valid),
    .o_qp_stat_wqe_cnt_rdreq(qp_stat_wqe_cnt_rdreq),
    .i_qp_stat_wqe_cnt      (qp_stat_wqe_cnt),
    .o_update_qp_stat_wqe_cnt(update_qp_stat_wqe_cnt),
    .o_qp_stat_wqe_cnt      (new_qp_stat_wqe_cnt),

    .o_axi_ren_valid        (axi_ren_valid),
    .o_axi_read_addr        (sq_read_addr_to_axi),
    .i_wqe_dataread         (bus2ip_dvalid)

);

assign o_halt = halt;

// Since the sq_ba and sq_depth is flopped (to have better timing), the ren is
// also being flopped so have consistent timing
`MSFF_R(axi_ren_valid_ff, axi_ren_valid, core_clk, ~core_rstn)

// SEND WQE FIFO

    rdma_q_mgr_queue
    #(
    .C_Q_DEPTH(WQE_FIFO_DEPTH),	    // Number of entries in each queue
    .C_ENTRY_SIZE(WQE_SIZE),    // Size of each entry in Bytes. SQ size is 64B
    .C_PTR_WIDTH(WQE_FIFO_IDX_WIDTH)	    // Pointer size reqd for accessing the Q depth
    ) inst_q
    (
    .core_clk			    (core_clk),					// Clock
    .core_rst			    (~core_rstn),					// Active high core reset

    // Queue pointers
    .o_rd_addr			    (),		// Read address stacked on one bus
    .o_wr_addr			    (),		// Write address stacked on one bus
    .o_rd_ptr                       (wqe_fifo_rd_ptr),                // read pointer
    .o_wr_ptr		            (wqe_fifo_wr_ptr),	        // write pointer
    .o_num_valid_entries	    (num_valid_entries),  // Number of valid entries stacked
    .o_num_free_entries		    (),	// Number of free entries stacked
    .o_q_empty			    (wqe_empty),
    .o_q_full			    (wqe_full),
    .o_q_almost_full                (),    // Q is full -1

    // Configuration
    .i_base_addr		    (32'b0),	// Base address of queues
    .i_q_depth                      (WQE_FIFO_DEPTH),
    .i_init                         (1'b0),

    .i_q_push			    (bus2ip_dvalid | wqe_fifo_push_retry),				// Push enable for a queue
    .i_push_num_entries		    ({{(WQE_FIFO_IDX_WIDTH){1'b0}}, 1'b1}),			// Number of entries to be pushed

    .i_q_pop			    (i_wqe_pop | wqe_fifo_pop_retry),				// Pop enable for a queue
    .i_pop_num_entries		    ({{(WQE_FIFO_IDX_WIDTH){1'b0}}, 1'b1})				// Number of entries to be popped
    );

assign o_wqe_empty = wqe_empty | wqe_empty_ff; // extending the WQE empty assertion for one more cycle until BRAm data is stable
assign o_wqe_fifo_full = wqe_full;
`MSFF_R(wqe_empty_ff, wqe_empty, core_clk, ~core_rstn)

 // Actual FIFO implemented in BRAM

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (WQE_SIZE*WQE_FIFO_DEPTH),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("common_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (WQE_SIZE),              //positive integer
  .READ_DATA_WIDTH_A  (WQE_SIZE),              //positive integer
  .BYTE_WRITE_WIDTH_A (WQE_SIZE),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (WQE_FIFO_IDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (WQE_SIZE),              //positive integer
  .READ_DATA_WIDTH_B  (WQE_SIZE),              //positive integer
  .BYTE_WRITE_WIDTH_B (WQE_SIZE),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (WQE_FIFO_IDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_wqe_fifo (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (core_clk),
  .rsta           (~core_rstn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (bus2ip_dvalid | wqe_fifo_push_retry),
  .addra          (wqe_fifo_wr_ptr),
  .dina           (wqe_fifo_push_retry ? wqe_to_fifo : wqe_qid_inserted),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (~wqe_empty),
  .regceb         (1'b1),
  .web            (1'b0),
  .addrb          (wqe_fifo_rd_ptr),
  .dinb           ({WQE_SIZE{1'b0}}),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (cached_wqe),
  .sbiterrb       (),
  .dbiterrb       ()

);

 assign o_wqe = cached_wqe;
     // Inserting QPID in the 28th byte
 assign wqe_qid_inserted =  {bus2ip_data[511 : 144], {(8 - C_QP_INDX_WIDTH){1'b0}} , qp_sq_arbitrated_idx_ff, bus2ip_data[135: 0]};
`MSFF_R(qp_sq_arbitrated_idx_ff, ((arbitration_done & sample_arbitrated_sq) ? qp_sq_arbitrated_idx : qp_sq_arbitrated_idx_ff), core_clk, ~core_rstn)

// Retransmission module

`ifdef SIMULATION
// Debug: monitor WQE data written to FIFO
always @(posedge core_clk) begin
    if(bus2ip_dvalid && !wqe_fifo_push_retry) begin
        $display("[%0t] WQE_FIFO_WR: bus2ip[31:0]=%h [63:32]=%h [95:64]=%h [127:96]=%h [159:128]=%h [191:160]=%h [223:192]=%h [255:224]=%h",
                 $time, bus2ip_data[31:0], bus2ip_data[63:32], bus2ip_data[95:64],
                 bus2ip_data[127:96], bus2ip_data[159:128], bus2ip_data[191:160],
                 bus2ip_data[223:192], bus2ip_data[255:224]);
    end
end
`endif

qp_mgr_retransmit
#(
    .C_NUM_QP                (C_NUM_QP),
    .C_WQE_FIFO_IDX_WIDTH    (WQE_FIFO_IDX_WIDTH),
    .C_QP_INDX_WIDTH         (C_QP_INDX_WIDTH)
) inst_retransmit
(
  .core_clk                 (core_clk),
  .core_rstn                (core_rstn),

  // Configuration details
  .i_retransmit_reqd        (i_retransmit_reqd),
  .i_retransmit_qpid        (i_retransmit_qpid),        // QP id for this retransmission is required
  .o_retransmit_accepted    (o_retransmit_accepted),
  .i_psn_to_retry           (i_psn_to_retry   ),
  .i_ssn_to_retry           (i_ssn_to_retry   ),

  .i_num_valid_entries      (num_valid_entries),

  .o_qp_cq_hdptr_req        (qp_cq_hdptr_req_retry),
  .i_qp_cq_hdptr_valid      (qp_cq_hdptr_valid_retry),
  .i_qp_cq_hdptr            (qp_cq_hdptr_from_config),
  .o_qp_cq_hdptr_idx        (qp_cq_hdptr_idx_retry),

  // configuration that is updated
  .o_qp_curr_sqptr_proc     (qp_curr_sqptr_proc_retry    ),
  .o_qp_curr_sqptr_proc_wen (qp_curr_sqptr_proc_wen_retry),
  .o_qp_curr_sqptr_proc_idx (qp_curr_sqptr_proc_idx_retry),   // Index for writing curent SQ pointer

  .o_qp_stat_ret_sq_psn     (qp_stat_ret_sq_psn_int    ),
  .o_qp_stat_ret_sq_psn_wen (qp_stat_ret_sq_psn_wen_int),
  .o_qp_stat_ret_sq_psn_idx (qp_stat_ret_sq_psn_idx_int),
  .i_qp_stat_ret_sq_psn_valid(qp_stat_ret_sq_psn_valid_int),

  .o_qp_sq_psn_req          (qp_sq_psn_req_retry  ),
  .i_qp_sq_psn_valid        (qp_sq_psn_retry_valid),
  .i_qp_sq_psn              (o_qp_sq_psn          ),
  .o_qp_sq_psn_wrn          (qp_sq_psn_wrn_retry  ),
  .o_qp_sq_psn              (qp_sq_psn_retry      ),
  .o_qp_sq_psn_idx          (qp_sq_psn_idx_retry  ),   // Index for reading Q depth

  .o_qp_stat_ssn_idx        (qp_stat_ssn_idx_retry  ),    // Index for reading/writing MSN
  .o_qp_stat_ssn            (qp_stat_ssn_retry      ), // Expected MSN for Qp incoming messages
  .i_qp_stat_ssn            (o_qp_stat_ssn          ), // Expected MSN for Qp incoming messages write data from hdr validation
  .o_qp_stat_ssn_req        (qp_stat_ssn_req_retry  ),
  .o_qp_stat_ssn_wrn        (qp_stat_ssn_wrn_retry  ),
  .i_qp_stat_ssn_valid      (o_qp_stat_ssn_valid),

  .i_wqe                    (wqe_from_fifo),
  .o_wqe                    (wqe_to_fifo),
  .o_wqe_fifo_push          (wqe_fifo_push_retry),
  .o_wqe_fifo_pop           (wqe_fifo_pop_retry),

  .o_halt                   (halt),
  .o_halted_qpid            (o_halted_qpid),
  .i_halted                 (i_wqe_halted & cache_halted)

);

assign wqe_from_fifo = cached_wqe;

// AXI master to fetch the WQE from SEND Q in DDR
rdma_axi_master
#(
.C_M_AXI_ADDR_WIDTH(C_M_AXI_ADDR_WIDTH),
.C_M_AXI_DATA_WIDTH(512),
.C_M_AXI_THREAD_ID_WIDTH(1),
.IP2BUS_LEN_WIDTH(14)
) inst_axi_master
(
// AXI System signals
.m_axi_aclk                     (core_clk),
.m_axi_aresetn                  (core_rstn),
// AXI Master signals
.m_axi_awid                     (m_axi_awid   ),
.m_axi_awaddr                   (m_axi_awaddr ),
.m_axi_awlen                    (m_axi_awlen  ),
.m_axi_awsize                   (m_axi_awsize ),
.m_axi_awburst                  (m_axi_awburst),
.m_axi_awcache                  (m_axi_awcache),
.m_axi_awprot                   (m_axi_awprot ),
.m_axi_awvalid                  (m_axi_awvalid),
.m_axi_awready                  (m_axi_awready),
.m_axi_wdata                    (m_axi_wdata  ),
.m_axi_wstrb                    (m_axi_wstrb  ),
.m_axi_wlast                    (m_axi_wlast  ),
.m_axi_wvalid                   (m_axi_wvalid ),
.m_axi_wready                   (m_axi_wready ),
.m_axi_awlock                   (m_axi_awlock ),
.m_axi_bid                      (m_axi_bid    ),
.m_axi_bresp                    (m_axi_bresp  ),
.m_axi_bvalid                   (m_axi_bvalid ),
.m_axi_bready                   (m_axi_bready ),
.m_axi_arid                     (m_axi_arid   ),
.m_axi_araddr                   (m_axi_araddr ),
.m_axi_arlen                    (m_axi_arlen  ),
.m_axi_arsize                   (m_axi_arsize ),
.m_axi_arburst                  (m_axi_arburst),
.m_axi_arcache                  (m_axi_arcache),
.m_axi_arprot                   (m_axi_arprot ),
.m_axi_arvalid                  (m_axi_arvalid),
.m_axi_arready                  (m_axi_arready),
.m_axi_rid                      (m_axi_rid    ),
.m_axi_rdata                    (m_axi_rdata  ),
.m_axi_rresp                    (m_axi_rresp  ),
.m_axi_rlast                    (m_axi_rlast  ),
.m_axi_rvalid                   (m_axi_rvalid ),
.m_axi_rready                   (m_axi_rready ),
.m_axi_arlock                   (m_axi_arlock ),

.bus2ip_byte_en                 (),
.bus2ip_data                    (bus2ip_data),
.bus2ip_dvalid                  (bus2ip_dvalid),
.ip2bus_data                    (512'b0),
.bus2ip_data_rdy                (),
.axi_m_en                       (axi_ren_valid_ff),
.wr_rdn                         (1'b0),             //1 = write; 0 = read
.ip2bus_addr                    (sq_read_addr_to_axi),
.ip2bus_len                     (WQE_SIZE_IN_BYTES),         //length in bytes

.axi_master_done                (axi_master_done),
.axi_master_busy                (axi_master_busy),
.axi_master_bvalid              (axi_master_bvalid),
.axi_master_error               (axi_master_error_nc)

    );

//----------------Debug Registers---------------------------//
generate
if(C_EN_DEBUG_REGS == 1) begin

assign dbg_bram_wen		= i_wqe_pop;
assign dbg_bram_wdata[63:0]	= cached_wqe[223:160]; 	//REMOTE OFFSET - 64 bits
assign dbg_bram_wdata[95:64]	= cached_wqe[255:224];  //REMOTE TAG - 32 bits
assign dbg_bram_wdata[103:96]	= cached_wqe[143:136];  //QP ID - 8 bits
assign dbg_bram_wdata[119:104]	= cached_wqe[15:0];     //WR ID - 16 bits
assign dbg_bram_wdata[120]	= cached_wqe[16];	//RETRY - 1 bit

`MSFF_R(dbg_bram_waddr, (i_wqe_pop ? dbg_bram_waddr + 1 : dbg_bram_waddr), core_clk, ~core_rstn)

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (121*1024),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("common_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (121),              //positive integer
  .READ_DATA_WIDTH_A  (121),              //positive integer
  .BYTE_WRITE_WIDTH_A (121),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (10),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (121),              //positive integer
  .READ_DATA_WIDTH_B  (121),              //positive integer
  .BYTE_WRITE_WIDTH_B (121),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (10),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_dbg_info (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (core_clk),
  .rsta           (~core_rstn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (dbg_bram_wen),
  .addra          (dbg_bram_waddr),
  .dina           (dbg_bram_wdata),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (s_axi_lite_aclk),
  .rstb           (~s_axi_lite_aresetn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (1'b0),
  .addrb          (dbg_bram_raddr),
  .dinb           ({121{1'b0}}),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (dbg_bram_rdata),
  .sbiterrb       (),
  .dbiterrb       ()

);

end
else begin

assign dbg_bram_rdata = {121{1'b0}};

end
endgenerate

//--------End of debug registers logic---------------//
`MSFF_R(axi_rd_err_cnt_ff, ((axi_master_error_nc & axi_master_done) ? ((axi_rd_err_cnt_ff == 8'hFF) ? axi_rd_err_cnt_ff : axi_rd_err_cnt_ff + 1 ): axi_rd_err_cnt_ff ), core_clk, ~core_rstn)

  endmodule

