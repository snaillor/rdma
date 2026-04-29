// rdma_config_reg.v
// 文件名          : rdma_config_reg.v
// 版本            : v1.0
// 描述            : RDMA 配置/状态寄存器模块，通过 AXI4-Lite 接口提供软件配置
//                   包含 QP 参数、Doorbell、中断状态等寄存器，使用 BRAM 存储
// Verilog 标准    : Verilog'2001

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
`timescale 1ps/1ps

(* DowngradeIPIdentifiedWarnings="yes" *)
module rdma_config_reg
#(
    parameter   C_S_AXI_LITE_ADDR_WIDTH = 14,
    parameter   C_S_AXI_LITE_DATA_WIDTH = 32,
    parameter   C_NUM_QP                = 128,
    parameter   C_QP_INDX_WIDTH         = 7,
    parameter   STB_WIDTH               = 4,
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

  output reg   [C_S_AXI_LITE_DATA_WIDTH-1:0]        s_axi_lite_rdata,
  output wire  [RESP_WIDTH-1:0]                     s_axi_lite_rresp,
  input  wire                                       s_axi_lite_rready,
  output reg                                        s_axi_lite_rvalid,

  output wire  [RESP_WIDTH-1:0]                     s_axi_lite_bresp,
  input  wire                                       s_axi_lite_bready,
  output reg                                        s_axi_lite_bvalid,

  input  wire					    core_clk,
  input  wire					    core_rstn,	    // Active high core reset

  // Interrupt signals coming/going from/to Header validation module
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

  output wire [31:0]                                o_rx_pkt_hndl_dbg_ctrl,

  input  wire [C_NUM_QP -1:0]                       i_qp_pkt_rcvd_intr,
  input  wire [C_NUM_QP -1:0]                       i_qp_fatal_err,
  output wire [C_NUM_QP -1:0]                       o_qp_clr_fatal_err,

  input  wire [C_NUM_QP -1:0]                       i_qp_wq_cmpl_intr,
  output wire [C_NUM_QP -1:0]                       o_rq_intr_sts_clr,
  output wire [C_NUM_QP -1:0]                       o_cq_intr_sts_clr,

  input  wire  [C_NUM_QP -1 :0]                     i_rq_full,  // Rcv Q full for QPn
  input  wire  [C_NUM_QP -1 :0]                     i_osq_full, // Outstanding Q full for QPn
  input  wire  [C_NUM_QP -1 :0]                     i_osq_almost_full, // Outstanding Q full for QPn
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

  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_stat_ssn_idx,    // Index for reading/writing MSN
  input  wire  [23:0]                               i_qp_stat_ssn, // Expected MSN for Qp incoming messages
  output wire  [23:0]                               o_qp_stat_ssn, // Expected MSN for Qp incoming messages write data from hdr validation
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

  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_ret_sq_psn_idx,    // Index for reading/writing RQ PI DB
  input  wire  [23:0]                               i_qp_ret_sq_psn,
  output wire  [23:0]                               o_qp_ret_sq_psn,
  input  wire                                       i_qp_ret_sq_psn_req,
  input  wire                                       i_qp_ret_sq_psn_wrn,
  output wire                                       o_qp_ret_sq_psn_valid,
  output wire                                       o_qp_ret_sq_psn_valid_int,

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

  input  wire  [31:0]                               i_wqe_proc_sts,
  input  wire  [31:0]                               i_rx_pkt_vld_sts,
  input  wire  [31:0]                               i_qp_mgr_sts,

  // SEND Q Full/empty status for arbitration
  output wire  [C_NUM_QP -1 :0]                     o_sq_empty,
  output wire  [C_NUM_QP -1 :0]                     o_sq_full,

//  // Explicit ack to resp handler

  // Update signals from cache module
  input  wire                                       i_status_upd_needed,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_status_upd_indx,

  //Configuration outputs going to other modules (generic)
  output wire                                       o_rdma_en,
  output wire                                       o_rdma_adv_conf_sw_override,
  output wire                                       o_rdma_adv_conf_errbuf_overwr_en,
  output wire [3:0]				    o_rdma_adv_base_cnt,
  output wire [1:0]                                 o_tx_ack_gen,
  output wire                                       o_err_buf_en,
  output wire [1:0]                                 o_flow_credits,
  output wire [15:0]                                o_rdma_udp_src_port,
  output wire                                       o_depkt_bypass_en,               // RDMA interface bypass feature enable
  output wire [C_QP_INDX_WIDTH-1:0]                 o_num_qp_en,                      // Number of QPs enabled
  output wire [47:0]                                o_mac_rdma_addr,                 // Ethernet MAC destination (own) address from RDMA registers
  output wire [31:0]                                o_ipv4_rdma_addr,                // IPv4 destination (own) address from RDMA registers (for depkt module)
  output wire [127:0]                               o_ipv6_rdma_addr,                // IPv6 destination (own) address form RDMA registers (for depkt_module)

  output wire [31:0]                                o_bypass_buf_ba,
  output wire [15:0]                                o_bypass_buf_sz_num_bufs,
  output wire [15:0]                                o_bypass_buf_sz_buf_sz,
  input  wire [15:0]                                i_bypass_buf_wrptr,

  output wire [31:0]                                o_data_buf_ba,
  output wire [15:0]                                o_data_buf_sz_num_bufs,
  output wire [15:0]                                o_data_buf_sz_buf_sz,

  output wire [9:0]                                 o_connect_io_qp_rq_pi_db_wptr,
  input  wire 	                                    i_connect_io_qp_rq_pi_db_rdy,
  output wire [15:0]                                o_rq_pi_db_hw_hndshk,
  output wire                                       o_hw_hndshk_disable_to_0,

  output wire [31:0]                                o_rq_err_pkt_buf_ba,
  output wire [15:0]                                o_rq_err_pkt_buf_sz_num_bufs,
  output wire [15:0]                                o_rq_err_pkt_buf_sz_buf_sz,
  output wire [31:0]                                o_resp_err_pkt_buf_ba,
  output wire [15:0]                                o_resp_err_pkt_buf_sz_num_bufs,
  output wire [15:0]                                o_resp_err_pkt_buf_sz_buf_sz,
  output wire [31:0]                                o_tx_hdr_buf_ba,
  output wire [15:0]                                o_tx_hdr_buf_sz_num_hdrs,
  output wire [15:0]                                o_tx_hdr_buf_sz_buf_sz,

  output wire [31:0]                                o_tx_sgl_buf_ba,
  output wire [15:0]                                o_tx_sgl_buf_sz_num_sgls,
  output wire [15:0]                                o_tx_sgl_buf_sz_buf_sz,

  output wire                                       o_rdma_conf_ipver,

  // HW Doorbell WQE template outputs (configured once by CPU, used by HW Doorbell)
  output wire [31:0]                                o_hw_wqe_remote_addr_lo,
  output wire [31:0]                                o_hw_wqe_remote_addr_hi,
  output wire [31:0]                                o_hw_wqe_rkey,
  output wire [31:0]                                o_hw_wqe_local_addr,
  output wire [7:0]                                 o_hw_wqe_opcode,
  output wire [15:0]                                o_hw_wqe_wrid,

  output wire  [31:0]                               o_timeoutreg,
  output wire  [C_NUM_QP -1 :0]                     o_qp_disable_pulse,

  output wire  [31:0]                               o_out_errsts_q_ba,
  output wire  [15:0]                               o_out_errsts_q_sz,
  input  wire  [15:0]                               i_out_errsts_q_wrptr,

  output wire  [31:0]                               o_in_errsts_q_ba,
  output wire  [15:0]                               o_in_errsts_q_sz,
  input  wire  [15:0]                               i_in_errsts_q_wrptr,

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

  input  wire                                       i_qp_sq_ba_req_int,
  input  wire                                       i_qp_sq_ba_req,
  output wire                                       o_qp_sq_ba_valid_int,
  output wire                                       o_qp_sq_ba_valid,
  output wire  [31:0]                               o_qp_sq_ba,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_sq_ba_idx,   // Index for reading Qp SQ BA

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

  input  wire                                       i_qp_cq_hdptr_req,
  input  wire                                       i_qp_cq_hdptr_retry_req,
  output wire                                       o_qp_cq_hdptr_valid,
  output wire                                       o_qp_cq_hdptr_valid_retry,
  output wire  [15:0]                               o_qp_cq_hdptr,
  input  wire  [15:0]                               i_qp_cq_hdptr,
  input  wire                                       i_qp_cq_hdptr_wrn,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_cq_hdptr_idx,   // Index for reading CQ head pointer

  input  wire                                       i_qp_rq_cidb_req,
  output wire                                       o_qp_rq_cidb_valid,
  output wire  [31:0]                               o_qp_rq_cidb,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_rq_cidb_idx,   // Index for reading RQ CI DB

  output wire  [15:0]                               o_qp_sq_pidb,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_sq_pidb_idx,   // Index for reading SQ PI DB
  input  wire                                       i_qp_sq_pidb_req,
  output wire                                       o_qp_sq_pidb_valid,

  input wire  [15:0]                                i_qp_sq_pidb_hndshk,
  input wire  [31:0]                                i_qp_sq_pidb_wr_addr_hndshk,
  input wire                                        i_qp_sq_pidb_wr_valid_hndshk,
  output wire                                       o_qp_sq_pidb_wr_rdy,

  input wire  [15:0]                                i_qp_rq_cidb_hndshk,
  input wire  [31:0]                                i_qp_rq_cidb_wr_addr_hndshk,
  input wire                                        i_qp_rq_cidb_wr_valid_hndshk,
  output wire                                       o_qp_rq_cidb_wr_rdy,

  input  wire                                       i_qp_rq_depth_req,
  output wire                                       o_qp_rq_depth_valid,
  output wire  [15:0]                               o_qp_rq_depth,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_rq_depth_idx,   // Index for reading RQ depth

  input  wire                                       i_qp_sq_depth_req,
  output wire                                       o_qp_sq_depth_valid,
  output wire  [15:0]                               o_qp_sq_depth,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_sq_depth_idx,   // Index for reading RQ depth

  // The CQ depth is equal to SQ depth. This information is shared by QP cache
  // manager and resp handler. Priority is for cache manager
  input  wire                                       i_qp_cq_depth_req,
  output wire                                       o_qp_cq_depth_valid,
  output wire                                       o_qp_cq_depth_rdy,
  output wire  [15:0]                               o_qp_cq_depth,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_cq_depth_idx,   // Index for reading Q depth

  input  wire                                       i_qp_sq_psn_req,
  input  wire                                       i_qp_sq_psn_wqe_req,
  input  wire                                       i_qp_sq_psn_retry_req,
  output wire                                       o_qp_sq_psn_valid,
  output wire                                       o_qp_sq_psn_wqe_valid,
  output wire                                       o_qp_sq_psn_retry_valid,
  output wire  [23:0]                               o_qp_sq_psn,
  input  wire                                       i_qp_sq_psn_wrn,
  input  wire                                       i_qp_sq_psn_retry_wrn,
  input  wire  [23:0]                               i_qp_sq_psn,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_sq_psn_idx,   // Index for reading Q depth
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_sq_psn_wqe_idx,   // Index for reading Q depth
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_sq_psn_retry_idx,   // Index for reading Q depth

  (* mark_debug = "true" *)   output wire  [31:0]                               o_qp_last_rq,
  (* mark_debug = "true" *)   input wire   [31:0]                               i_qp_last_rq,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_last_rq_idx,   // Index for reading Q depth
  input  wire                                       i_qp_last_rq_req,
  (* mark_debug = "true" *)   input  wire                                       i_qp_last_rq_wrn,
  output wire                                       o_qp_last_rq_valid,

  input  wire                                       i_qp_dest_qpid_req_wqe_proc,
  input  wire                                       i_qp_dest_qpid_req_rx_pkt,
  output wire                                       o_qp_dest_qpid_valid_wqe_proc,
  output wire                                       o_qp_dest_qpid_valid_rx_pkt,
  output wire  [23:0]                               o_qp_dest_qpid,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_dest_qpid_idx,   // Index for reading Q depth

  input  wire                                       i_qp_mac_remote_addrl_req,
  input  wire                                       i_qp_mac_remote_addrl_wqe_req,
  output wire                                       o_qp_mac_remote_addrl_valid,
  output wire                                       o_qp_mac_remote_addrl_wqe_valid,
  output wire  [31:0]                               o_qp_mac_remote_addrl,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_mac_remote_addrl_idx,   // Index for reading Q depth
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
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_mac_remote_addrm_idx,   // Index for reading Q depth
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
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_ip_remote_addr1_idx,   // Index for reading Q depth
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_ip_remote_addr1_wqe_idx,   // Index for reading Q depth

  output wire  [31:0]                               o_qp_ip_remote_addr1_replica,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_ip_remote_addr1_replica_idx,   // Index for reading Q depth
  input  wire                                       i_qp_ip_remote_addr1_replica_req,
  output wire                                       o_qp_ip_remote_addr1_replica_valid,

(* mark_debug = "true" *)  input  wire  [15:0]                               i_qp_curr_sqptr_proc,
(* mark_debug = "true" *)  input  wire                                       i_qp_curr_sqptr_proc_wen,
(* mark_debug = "true" *)  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_curr_sqptr_proc_idx,   // Index for writing curent SQ pointer
  output wire                                       o_qp_curr_sqptr_proc_valid,
  input  wire                                       i_qp_curr_sqptr_rdreq,
(* mark_debug = "true" *)  output wire  [15:0]                               o_qp_curr_sqptr_proc,

  // Response PSN status register. Read/write interface to RX pkt handler
  input  wire  [23:0]                               i_qp_stat_resp_psn,
  input  wire                                       i_qp_stat_resp_psn_wen,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_stat_resp_psn_idx,
  output wire                                       o_qp_stat_resp_psn_valid,
  input  wire                                       i_qp_stat_resp_psn_rdreq,
  output wire  [23:0]                               o_qp_stat_resp_psn,

  input  wire  [9:0]                                i_qp_stat_nak,
  input  wire                                       i_qp_stat_nak_wen,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_stat_nak_idx,
  output wire                                       o_qp_stat_nak_valid,
  input  wire                                       i_qp_stat_nak_rdreq,
  output wire  [9:0]                                o_qp_stat_nak,

  input  wire  [2:0]                                i_qp_stat_retry_cnt,
  input  wire                                       i_qp_stat_retry_cnt_wen,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_stat_retry_cnt_idx,
  output wire                                       o_qp_stat_retry_cnt_valid,
  input  wire                                       i_qp_stat_retry_cnt_rdreq,
  output wire  [2:0]                                o_qp_stat_retry_cnt,

  input  wire  [23:0]                               i_qp_stat_rq_buf_ca,
  input  wire                                       i_qp_stat_rq_buf_ca_wen,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_stat_rq_buf_ca_idx,
  output wire                                       o_qp_stat_rq_buf_ca_valid,
  input  wire                                       i_qp_stat_rq_buf_ca_rdreq,
  output wire  [23:0]                               o_qp_stat_rq_buf_ca,

  input  wire  [15:0]                               i_qp_stat_wqe_cnt,
  input  wire                                       i_qp_stat_wqe_cnt_wen,
  input  wire  [C_QP_INDX_WIDTH -1: 0]              i_qp_stat_wqe_cnt_idx,
  output wire                                       o_qp_stat_wqe_cnt_valid,
  input  wire                                       i_qp_stat_wqe_cnt_rdreq,
  output wire  [15:0]                               o_qp_stat_wqe_cnt,

  //Performance debug counters i/f
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
  //Debug registers
  input  wire  [120:0]				    i_dbg_bram_rdata,
  output wire  [9:0]				    o_dbg_bram_raddr,
  input  wire  [7:0]				    i_axi_rd_err_cnt,

  input  wire  [31:0]                               i_last_in_pkt_info,
  input  wire  [31:0]                               i_last_out_pkt_info

  );
`include "rdma_macros.vh"

  // AXI lite operation registers
  reg   [16:0] wr_addr_r;
  reg   [16:0] rd_addr_r;
  reg          wr_req_r;
  reg          rd_req_r;
  reg          reset_released_r;
  reg          rvalid_delayed;
  reg [31:0] rx_pkt_hndl_dbg_ctrl;

  reg rdma_conf_rdma_en;
  reg rdma_conf_ipver;
  reg rdma_conf_depkt_bypass_en;
  reg [1:0]  rdma_conf_tx_ack_gen;
  reg rdma_conf_err_buf_en;
  reg [1:0] rdma_conf_flow_credits;
  reg [7:0]  rdma_conf_num_qps_enabled;
  reg [15:0] rdma_conf_udp_src_port;

  reg [15:0] rdma_sw_override_cnt;
(* mark_debug = "true" *)  reg rdma_adv_conf_sw_override;
  reg rdma_adv_conf_sw_override_ff;
  reg rdma_adv_conf_errbuf_overwr_en;
  reg [3:0]    rdma_adv_base_cnt;

  reg [31:0]    mac_rdma_addr_lsb;
  reg [15:0]    mac_rdma_addr_msb;

  reg [31:0] ipv4_rdma_addr;

  // HW Doorbell WQE template registers
  reg [31:0] hw_wqe_remote_addr_lo;
  reg [31:0] hw_wqe_remote_addr_hi;
  reg [31:0] hw_wqe_rkey;
  reg [31:0] hw_wqe_local_addr;
  reg [7:0]  hw_wqe_opcode;
  reg [15:0] hw_wqe_wrid;
  reg [31:0] ipv6_rdma_addr1;
  reg [31:0] ipv6_rdma_addr2;
  reg [31:0] ipv6_rdma_addr3;
  reg [31:0] ipv6_rdma_addr4;

  reg [31:0] tx_hdr_buf_ba;
  reg [15:0] tx_hdr_buf_sz_num_hdrs;
  reg [15:0] tx_hdr_buf_sz_buf_sz;

  reg [31:0] tx_sgl_buf_ba;
  reg [15:0] tx_sgl_buf_sz_num_sgls;
  reg [15:0] tx_sgl_buf_sz_buf_sz;

  reg [31:0] bypass_buf_ba;
  reg [15:0] bypass_buf_sz_num_bufs;
  reg [15:0] bypass_buf_sz_buf_sz;

  reg [31:0] data_buf_ba;
  reg [15:0] data_buf_sz_num_bufs;
  reg [15:0] data_buf_sz_buf_sz;
  reg        hw_hndshk_disable_to_0;

  reg [9:0]  connect_io_qp_rq_pi_db_wptr;
  reg [7:0]  connect_io_qpid;

  reg [31:0] rq_err_pkt_buf_ba;
  reg [15:0] rq_err_pkt_buf_sz_num_bufs;
  reg [15:0] rq_err_pkt_buf_sz_buf_sz;
  reg [31:0] resp_err_pkt_buf_ba;
  reg [15:0] resp_err_pkt_buf_sz_num_bufs;
  reg [15:0] resp_err_pkt_buf_sz_buf_sz;

  reg [4:0] timeout;
  reg [2:0] retry_cnt;
  reg [2:0] rnr_retry_cnt;
  reg [4:0] rnr_nack_tval;

  reg [C_NUM_QP -1 :0] sq_full_ff;
  reg [C_NUM_QP -1 :0] sq_empty_ff;

  reg [31:0] out_errsts_q_ba;
  reg [15:0] out_errsts_q_sz;

  reg [31:0] in_errsts_q_ba ;
  reg [15:0] in_errsts_q_sz ;
  reg [31:0] global_dbg_cnt ;
  reg [15:0] int_cnt_value;

  reg intr_en_pkt_valdn_err;
  reg intr_en_wqe_cmpl;
  reg intr_en_mad_pkt_rcvd;
  reg intr_en_bypass_pkt_rcvd;
  reg intr_en_rnr_nak_gen;
  reg intr_en_ill_opc_in_sq;
  reg intr_en_fatal_err;
  reg intr_en_qp_pkt_rcvd;

  reg qp_cq_hdptr_req_ff;
  reg qp_cq_hdptr_retry_req_ff;
  reg qp_conf_req_wqe_proc_ff;
  reg qp_conf_req_resp_hndl_ff;
  reg qp_conf_req_rx_pkt_ff;
  reg qp_conf_req_replica_ff;
  reg qp_adv_conf_req_ff;
  reg qp_rq_pi_db_req_ff;
  reg qp_ret_sq_psn_req_ff;
  reg qp_ret_sq_psn_req_int_ff;
  reg qp_rq_ba_req_ff;
  reg qp_sq_ba_req_ff;
  reg qp_sq_ba_req_int_ff;
  reg qp_cq_ba_req_ff;
  reg qp_rq_wrptrdb_req_ff;
  reg qp_sq_cmpldb_req_ff;
  reg qp_rq_cidb_req_ff;
  reg qp_sq_pidb_req_ff;
  reg qp_sq_pidb_req_hndshk_ff;
  reg qp_rq_cidb_req_hndshk_ff;
  reg qp_rq_depth_req_ff;
  reg qp_sq_depth_req_ff;
  reg qp_cq_depth_req_ff;
  reg qp_sq_psn_req_ff;
  reg qp_sq_psn_wqe_req_ff;
  reg qp_sq_psn_retry_req_ff;
  reg qp_last_rq_req_ff;
  reg qp_dest_qpid_req_wqe_proc_ff;
  reg qp_dest_qpid_req_rx_pkt_ff;
  reg qp_mac_remote_addrl_req_ff;
  reg qp_mac_remote_addrl_req_replica_ff;
  reg qp_mac_remote_addrm_req_ff;
  reg qp_mac_remote_addrm_req_replica_ff;
  reg qp_mac_remote_addrl_wqe_req_ff;
  reg qp_mac_remote_addrm_wqe_req_ff;
  reg qp_ip_remote_addr1_req_ff;
  reg qp_ip_remote_addr1_req_replica_ff;
  reg qp_ip_remote_addr1_wqe_req_ff;
  reg qp_curr_sqptr_req_ff;
  reg qp_stat_resp_psn_req_ff;
  reg qp_stat_nak_req_ff;
  reg qp_stat_rq_buf_ca_rdreq_ff;
  reg qp_stat_wqe_cnt_rdreq_ff;
  reg qp_stat_msn_req_ff;
  reg qp_stat_ssn_req_ff;
  reg qp_rq_wrptrdb_add_req_ff;
  reg qp_sq_cmpldb_add_req_ff;
  reg sq_pidb_bram_wen_ff;
  reg  [15:0] sqe_backpressure_cnt_ff;
  reg  [15:0] osq_backpressure_cnt_ff;
  reg  [15:0] all_sqes_empty_cnt_ff;

  genvar i, j;


  wire  clear_pend_stat_masked;
  wire  [7:0] pending_idx;
  wire  axi_lite_access_to_rqpidb_reg;
  wire  [C_QP_INDX_WIDTH -1: 0]         rq_cidb_idx;   // Index for reading RQ CI DB

  wire  [C_QP_INDX_WIDTH -1 :0]         qp_conf_wr_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_conf_rd_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_conf_bram_addr;
  wire                                  qp_conf_bram_wen;

  wire  [C_QP_INDX_WIDTH -1 :0]         qp_adv_conf_wr_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_adv_conf_rd_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_adv_conf_bram_addr;
  wire                                  qp_adv_conf_bram_wen;

  wire  [C_QP_INDX_WIDTH -1 :0]         qp_rq_ba_wr_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_rq_ba_rd_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_rq_ba_bram_addr;
  wire                                  qp_rq_ba_bram_wen;

  wire  [C_QP_INDX_WIDTH -1 :0]         qp_sq_ba_wr_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_sq_ba_rd_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_sq_ba_bram_addr;
  wire                                  qp_sq_ba_bram_wen;

  wire  [C_QP_INDX_WIDTH -1 :0]         qp_cq_ba_wr_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_cq_ba_rd_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_cq_ba_bram_addr;
  wire                                  qp_cq_ba_bram_wen;

  wire  [C_QP_INDX_WIDTH -1 :0]         qp_rq_wrptrdb_add_wr_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_rq_wrptrdb_add_rd_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_rq_wrptrdb_add_bram_addr;
  wire                                  qp_rq_wrptrdb_add_bram_wen;

  wire  [C_QP_INDX_WIDTH -1 :0]         qp_sq_cmpldb_add_wr_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_sq_cmpldb_add_rd_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_sq_cmpldb_add_bram_addr;
  wire                                  qp_sq_cmpldb_add_bram_wen;

  wire  [C_QP_INDX_WIDTH -1 :0]         qp_cq_hdptr_wr_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_cq_hdptr_rd_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_cq_hdptr_bram_addr;
  wire                                  qp_cq_hdptr_bram_wen;

  wire  [C_QP_INDX_WIDTH -1 :0]         qp_rq_cidb_wr_addr;
  wire  [31:0]                          qp_rq_cidb_wr_addr_hndshk;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_rq_cidb_rd_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_rq_cidb_bram_addr;
  wire                                  qp_rq_cidb_bram_wen;

  wire  [C_QP_INDX_WIDTH -1 :0]         qp_sq_pidb_wr_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_sq_pidb_hndshk_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_sq_pidb_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_sq_pidb_rd_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_sq_pidb_bram_addr;
  (* mark_debug = "true" *) wire                                  qp_sq_pidb_bram_wen;

  wire  [C_QP_INDX_WIDTH -1 :0]         qp_q_depth_wr_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_q_depth_rd_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_q_depth_bram_addr;
  wire                                  qp_q_depth_bram_wen;

  wire  [C_QP_INDX_WIDTH -1 :0]         qp_sq_psn_wr_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_sq_psn_rd_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_sq_psn_bram_addr;
  wire                                  qp_sq_psn_bram_wen;

  wire  [C_QP_INDX_WIDTH -1 :0]         qp_last_rq_wr_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_last_rq_rd_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_last_rq_bram_addr;
  (* mark_debug = "true" *)   wire                                  qp_last_rq_bram_wen;

  wire  [C_QP_INDX_WIDTH -1 :0]         qp_dest_qpid_wr_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_dest_qpid_rd_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_dest_qpid_bram_addr;
  wire                                  qp_dest_qpid_bram_wen;

  wire  [C_QP_INDX_WIDTH -1 :0]         qp_mac_remote_addrl_wr_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_mac_remote_addrl_rd_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_mac_remote_addrl_bram_addr;
  wire                                  qp_mac_remote_addrl_bram_wen;

  wire  [C_QP_INDX_WIDTH -1 :0]         qp_mac_remote_addrm_wr_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_mac_remote_addrm_rd_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_mac_remote_addrm_bram_addr;
  wire                                  qp_mac_remote_addrm_bram_wen;

  wire  [C_QP_INDX_WIDTH -1 :0]         qp_ip_remote_addr1_wr_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_ip_remote_addr1_rd_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_ip_remote_addr1_bram_addr;
  wire                                  qp_ip_remote_addr1_bram_wen;


  wire  [C_QP_INDX_WIDTH -1 :0]         qp_stat_msn_wr_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_stat_msn_rd_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_stat_msn_bram_addr;
  wire                                  qp_stat_msn_bram_wen;

  wire  [C_QP_INDX_WIDTH -1 :0]         qp_stat_ssn_wr_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_stat_ssn_rd_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_stat_ssn_bram_addr;
  wire                                  qp_stat_ssn_bram_wen;

  wire  [C_QP_INDX_WIDTH -1: 0]         stat_curr_sqptr_proc_addr;
  wire  [C_QP_INDX_WIDTH -1: 0]         stat_curr_sqptr_proc_wr_addr;
  wire  [C_QP_INDX_WIDTH -1: 0]         stat_curr_sqptr_proc_rd_addr;
  wire  [C_QP_INDX_WIDTH -1: 0]         stat_curr_sqptr_proc_bram_addr;
  wire                                  axi_curr_sqptr_proc_read;
  wire                                  stat_curr_sqptr_bram_wen;
  wire                                  qp_stat_rq_pi_db_bram_wen;
  wire  [15:0]                          curr_sqptr_proc;

  wire  [C_QP_INDX_WIDTH -1 :0]         qp_stat_nak_bram_addr;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_wqe_cnt_bram_addr;
  wire  		                qp_wqe_cnt_bram_wen;
  wire  [C_QP_INDX_WIDTH -1 :0]         qp_stat_rq_pi_db_bram_addr;

  wire  [C_QP_INDX_WIDTH -1: 0]         qp_depth_idx;   // Index for reading Q depth
  wire  [C_QP_INDX_WIDTH -1: 0]         muxed_qp_sq_psn_idx;

  wire  [31:0] s_axi_qp_config_rdata;
  wire  [31:0] s_axi_qp_adv_config_rdata;
  wire  [31:0] s_axi_rq_ba_rdata;
  wire  [31:0] s_axi_sq_ba_rdata;
  wire  [31:0] s_axi_cq_ba_rdata;
  wire  [31:0] s_axi_rq_wrptrdb_add_rdata;
  wire  [31:0] s_axi_sq_cmpldb_add_rdata;
  wire  [31:0] s_axi_cq_hdptr_rdata;
  wire  [31:0] s_axi_rq_cidb_rdata;
  wire  [31:0] s_axi_sq_pidb_rdata;
  wire  [31:0] s_axi_q_depth_rdata;
  wire  [31:0] s_axi_sq_psn_rdata;
  (* mark_debug = "true" *)   wire  [31:0] s_axi_last_rq_rdata;
  wire  [31:0] s_axi_dest_qpid_rdata;
  wire  [31:0] s_axi_timeout_rdata;
  wire  [31:0] s_axi_mac_remote_addrl_rdata;
  wire  [31:0] s_axi_mac_remote_addrm_rdata;
  wire  [31:0] s_axi_ip_remote_addr1_rdata;
  wire  [31:0] s_axi_curr_sqptr_proc_rdata;
  wire  [31:0] s_axi_stat_resp_psn_rdata;
  wire  [31:0] s_axi_stat_rq_buf_ca_rdata;
  wire  [31:0] s_axi_stat_wqe_cnt_rdata;
  wire  [31:0] s_axi_stat_rq_pi_db_rdata;
  wire  [31:0] s_axi_stat_ret_sq_psn_rdata;
  wire  [31:0] s_axi_stat_msn_rdata;
  wire  [31:0] s_axi_stat_qpn_rdata;
  wire  [31:0] s_axi_stat_ssn_rdata;
  wire  [C_QP_INDX_WIDTH -1: 0] muxed_qp_mac_remote_addrl_idx;   // Index for reading Q depth
  wire  [C_QP_INDX_WIDTH -1: 0] muxed_qp_mac_remote_addrm_idx;   // Index for reading Q depth
  wire  [C_QP_INDX_WIDTH -1: 0] muxed_qp_ip_remote_addr1_idx;   // Index for reading Q depth

  wire generic_reg_rd_access;
  wire generic_reg_wr_access;
  wire intr_clr;
  wire [15:0] sq_pidb;
  wire sq_empty;
  wire sq_full;
  wire [C_NUM_QP -1:0] pending_update;
  wire [7:0] jump;
  wire [15:0] sqe_backpressure_cnt, osq_backpressure_cnt, all_sqes_empty_cnt;

  wire [C_QP_INDX_WIDTH-1:0] qp_stat_ret_sq_psn_rd_addr;

  wire [C_QP_INDX_WIDTH-1:0] qp_stat_rq_pi_db_wr_addr;
  wire [C_QP_INDX_WIDTH-1:0] qp_stat_rq_pi_db_rd_addr;
  wire  [C_QP_INDX_WIDTH-1:0] qp_timeout_wr_addr;
  wire  [C_QP_INDX_WIDTH-1:0] qp_timeout_rd_addr;
  wire  [C_QP_INDX_WIDTH-1:0] qp_timeout_bram_addr;

  wire [C_QP_INDX_WIDTH-1:0] qp_stat_ret_sq_psn_bram_addr;
  reg  [2:0] pending_upd_ns;
  reg  [2:0] pending_upd_cs;
  reg  clear_pend_stat;
  reg  [C_NUM_QP -1:0] pending_update_ff;
  reg  [2:0] msb_cnt;
  reg  [C_QP_INDX_WIDTH -3 -1:0] lsb_cnt;
  reg  [255:0] rq_intr_sts_clr;
  reg  [255:0] cq_intr_sts_clr;
  wire         qp_fatal_sts;
  reg         qp_fatal_sts_ff;

  // Dividing the QPs into 8 equal parts. Each chunk is called QP_CHUNK
  // This is done for a faster update of the sq_empty/full signals in case
  // only a couple of QPs are activ
  localparam QP_CHUNK = (C_NUM_QP < 8) ? 1 : (C_NUM_QP/8); //C_NUM_QP/8;

  localparam IDLE               = 3'b000;
  localparam FIND_PEND_UPD      = 3'b001;
  localparam WAIT_BRAM          = 3'b010;
  localparam INCR_MSB_CNT       = 3'b011;
  localparam INCR_LSB_CNT       = 3'b100;
  localparam UPDATE_PEND_STAT   = 3'b101;

  localparam RDMA_CONF_REG         = 17'h000;
  localparam RDMA_ADV_CONF_REG     = 17'h004;
  localparam MAC_RDMA_ADDR_LSB_REG = 17'h010;
  localparam MAC_RDMA_ADDR_MSB_REG = 17'h014;
  localparam IPV6_RDMA_ADDR1_REG   = 17'h020;
  localparam IPV6_RDMA_ADDR2_REG   = 17'h024;
  localparam IPV6_RDMA_ADDR3_REG   = 17'h028;
  localparam IPV6_RDMA_ADDR4_REG   = 17'h02C;
  localparam TX_HDR_BUF_BA_REG      = 17'h030;
  localparam TX_HDR_BUF_SZ_REG      = 17'h038;
  localparam TX_SGL_BUF_BA_REG      = 17'h040;
  localparam TX_SGL_BUF_SZ_REG      = 17'h048;
  localparam BYPASS_BUF_BA_REG      = 17'h050;
  localparam BYPASS_BUF_SZ_REG      = 17'h058;
  localparam BYPASS_BUF_WRPTR_REG   = 17'h05C;
  localparam RQ_ERR_PKT_BUF_BA_REG     = 17'h060;
  localparam RQ_ERR_PKT_BUF_SZ_REG     = 17'h068;
  localparam IPV4_RDMA_ADDR_REG       = 17'h070;
  localparam OUT_ERRSTS_Q_BA_REG    = 17'h078;
  localparam OUT_ERRSTS_Q_SZ_REG    = 17'h080;
  localparam OUT_ERRSTS_Q_WRPTR_REG = 17'h084;
  localparam IN_ERRSTS_Q_BA_REG     = 17'h088;
  localparam IN_ERRSTS_Q_SZ_REG     = 17'h090;
  localparam IN_ERRSTS_Q_WRPTR_REG  = 17'h094;
  localparam DATA_BUF_BA_REG        = 17'h0A0;
  localparam DATA_BUF_SZ_REG        = 17'h0A8;
  localparam CNCT_IO_CONF_REG       = 17'h0AC;
  localparam RESP_ERR_PKT_BUF_BA_REG     = 17'h0B0;
  localparam RESP_ERR_PKT_BUF_SZ_REG     = 17'h0B8;
  localparam RX_PKT_HNDL_DBG_CTRL_REG    = 17'h0CC;
  // HW Doorbell WQE template registers
  localparam HW_WQE_REMOTE_ADDR_LO_REG   = 17'h0D0;
  localparam HW_WQE_REMOTE_ADDR_HI_REG   = 17'h0D4;
  localparam HW_WQE_RKEY_REG             = 17'h0D8;
  localparam HW_WQE_LOCAL_ADDR_REG       = 17'h0DC;
  localparam HW_WQE_OPCODE_WRID_REG      = 17'h0E0;
  localparam INC_SR_PKT_CNT_REG     = 17'h100;
  localparam INC_AM_PKT_CNT_REG     = 17'h104;
  localparam OUT_SR_PKT_CNT_REG     = 17'h108;
  localparam OUT_AM_PKT_CNT_REG     = 17'h10C;
  localparam LAST_IN_PKT_REG        = 17'h110;
  localparam LAST_OUT_PKT_REG       = 17'h114;
  localparam INV_DUP_PKT_CNT_REG    = 17'h118;
  localparam RNR_IN_PKT_STS_REG     = 17'h11C;
  localparam RNR_OUT_PKT_STS_REG    = 17'h120;
  localparam WQE_PROC_STS_REG       = 17'h124;
  localparam RX_PKT_VLD_STS_REG     = 17'h128;
  localparam QP_MGR_STS_REG         = 17'h12C;
  localparam INC_ALL_DROPPED_CNT_REG= 17'h130;
  localparam INC_NACK_CNT_REG       = 17'h134;
  localparam OUT_NACK_CNT_REG       = 17'h138;
  localparam RESP_HNDL_STS_REG      = 17'h13C;
  localparam RETRY_CNT_STS_REG      = 17'h140;
  localparam DBG_CNT_OVERRIDE_REG   = 17'h144;
  localparam IPG_0_4_PKT_CNT_REG    = 17'h148;
  localparam IPG_5_9_PKT_CNT_REG    = 17'h14C;
  localparam IPG_10_14_PKT_CNT_REG  = 17'h150;
  localparam IPG_15_19_PKT_CNT_REG  = 17'h154;
  localparam GLOBAL_DBG_CNTR	    = 17'h158;
  localparam OSQ_BKP_SQE_BKP_CNT    = 17'h15C;
  localparam RETRY_TX_BKP_HDR_BKP_CNT = 17'h160;
  localparam SQE_EMPTY_WQE_IDLE_CNT = 17'h164;
  localparam WQE_PROC_SM_CNT0	    = 17'h168;
  localparam WQE_PROC_SM_CNT1	    = 17'h16C;
  localparam WQE_PROC_SM_CNT2	    = 17'h170;
  localparam INTR_EN_REG            = 17'h180;
  localparam INTR_STS_REG           = 17'h184;
  localparam RQ_INTR_STS1_REG       = 17'h190;
  localparam RQ_INTR_STS2_REG       = 17'h194;
  localparam RQ_INTR_STS3_REG       = 17'h198;
  localparam RQ_INTR_STS4_REG       = 17'h19C;
  localparam RQ_INTR_STS5_REG       = 17'h1A0;
  localparam RQ_INTR_STS6_REG       = 17'h1A4;
  localparam RQ_INTR_STS7_REG       = 17'h1A8;
  localparam RQ_INTR_STS8_REG       = 17'h1AC;
  localparam CQ_INTR_STS1_REG       = 17'h1B0;
  localparam CQ_INTR_STS2_REG       = 17'h1B4;
  localparam CQ_INTR_STS3_REG       = 17'h1B8;
  localparam CQ_INTR_STS4_REG       = 17'h1BC;
  localparam CQ_INTR_STS5_REG       = 17'h1C0;
  localparam CQ_INTR_STS6_REG       = 17'h1C4;
  localparam CQ_INTR_STS7_REG       = 17'h1C8;
  localparam CQ_INTR_STS8_REG       = 17'h1CC;

  localparam QP_CONF_QPN            = 8'h00;
  localparam QP_ADV_CONF_QPN        = 8'h04;
  localparam RQ_BUF_BA_QPN          = 8'h08;
  localparam SQ_BA_QPN              = 8'h10;
  localparam CQ_BA_QPN              = 8'h18;
  localparam RQ_WRPTR_DB_ADD_QPN    = 8'h20;
  localparam SQ_CMPL_DB_ADD_QPN     = 8'h28;
  localparam CQ_HEAD_QPN            = 8'h30;
  localparam RQ_CI_DB_QPN           = 8'h34;
  localparam SQ_PI_DB_QPN           = 8'h38;
  localparam Q_DEPTH_QPN            = 8'h3C;
  localparam SQ_PSN_QPN             = 8'h40;
  localparam LAST_RQ_QPN            = 8'h44;
  localparam DEST_QP_CONF_QPN       = 8'h48;
  localparam TIMEOUT_QPN            = 8'h4C;
  localparam MAC_REMOTE_ADDR_LSB_QPN  = 8'h50;
  localparam MAC_REMOTE_ADDR_MSB_QPN  = 8'h54;
  localparam IP_REMOTE_ADDR1_QPN      = 8'h60;
  localparam STAT_SSN_QPN           = 8'h80;
  localparam STAT_MSN_QPN           = 8'h84;
  localparam STAT_QPN               = 8'h88;
  localparam STAT_CURR_SQPTR_PROC_QPN  = 8'h8C;
  localparam STAT_RESP_PSN_QPN      = 8'h90;
  localparam STAT_RQ_BUF_CA         = 8'h94;
  localparam STAT_WQE_CNT           = 8'h98;
  localparam STAT_RQ_PI_DB          = 8'h9C;
  localparam STAT_RET_SQ_PSN        = 8'hA0;

  localparam LOG_NUM_QP = clog2(C_NUM_QP);

  //******************************************************************************
  //A write address phase is accepted only when there is no pending read or
  //same clock read transaction will get the highest priority and processed
  //first. write transaction will not be accepted until the read transaction
  //is completed.
  //******************************************************************************
  assign s_axi_lite_awready = ((~wr_req_r) && (!(rd_req_r || s_axi_lite_arvalid))) && reset_released_r;
  assign s_axi_lite_bresp   = 2'b00;
  assign s_axi_lite_rresp   = 2'b00;
  assign s_axi_lite_wready  = wr_req_r && ~s_axi_lite_bvalid;
  assign s_axi_lite_arready = ~rd_req_r && ~wr_req_r && reset_released_r;

  // 根据 AXI 协议规范，复位后 AWREADY 和 ARREADY 信号应至少保持一个时钟周期的低电平
  // 通过 reset_released_r 信号实现该要求
  always @(posedge s_axi_lite_aclk)
  begin
      if(~s_axi_lite_aresetn) begin
          reset_released_r <= 1'b0;
      end else begin
          reset_released_r <= 1'b1;
      end
  end

  //******************************************************************************
  //AXI Lite trasaction decoding and address latching logic.
  //when s_axi_lite_a*valid signal is asserted by the master the address is latched
  //and wr_req_r or rd_req_r signal is asserted until data phase is completed
  //******************************************************************************

  always @(posedge s_axi_lite_aclk)
  begin
      if(~s_axi_lite_aresetn)begin
          wr_req_r  <= 1'b0;
          rd_req_r  <= 1'b0;
          wr_addr_r <= 'h00;
          rd_addr_r <= 'h00;
         // s_axi_lite_rready_r <= 'h00;
      end else begin
         // s_axi_lite_rready_r <= s_axi_lite_rready;
          if(s_axi_lite_awvalid && s_axi_lite_awready) begin
              wr_req_r  <= 1'b1;
              wr_addr_r <= s_axi_lite_awaddr[16:0];
          end else if (s_axi_lite_bvalid && s_axi_lite_bready) begin
              wr_req_r  <= 1'b0;
              wr_addr_r <= 6'h00;
          end else begin
              wr_req_r  <= wr_req_r;
              wr_addr_r <= wr_addr_r;
          end

          if(s_axi_lite_arvalid && s_axi_lite_arready) begin
              rd_req_r  <= 1'b1;
              rd_addr_r <= s_axi_lite_araddr;
          end else if (s_axi_lite_rvalid && s_axi_lite_rready) begin
              rd_req_r  <= 1'b0;
              rd_addr_r <= rd_addr_r;
          end else begin
              rd_req_r  <= rd_req_r;
              rd_addr_r <= rd_addr_r;
          end
      end
  end

wire  [255:0]   w_qp_pkt_rcvd_intr = { {(256-C_NUM_QP){1'b0}}, i_qp_pkt_rcvd_intr};
wire  [255:0]   w_qp_wq_cmpl_intr  = { {(256-C_NUM_QP){1'b0}}, i_qp_wq_cmpl_intr };

  //******************************************************************************
  //AXI Lite read trasaction processing logic.
  //when a read transaction is received, depending on address bits [13:2] the
  //data is recovered and sent on to s_axi_lite_rdata signal along with s_axi_lite_rvalid.
  //The address bits [1:0] are not considred and it is expected that the
  //address is word aligned and reads complete word information.
  //******************************************************************************
  always @(posedge s_axi_lite_aclk)
  begin
      if(~s_axi_lite_aresetn)begin
          s_axi_lite_rvalid <= 1'b0;
          s_axi_lite_rdata  <= 32'd0;
          rvalid_delayed <= 1'b0;
      end else begin
          if(rd_req_r) begin
              if(s_axi_lite_rvalid && s_axi_lite_rready ) begin
                  s_axi_lite_rvalid <= 1'b0;
                  rvalid_delayed <= 1'b0;
              end else begin
                  s_axi_lite_rvalid <= rvalid_delayed;
                  rvalid_delayed <= 1'b1;
              end
              if(~s_axi_lite_rvalid & generic_reg_rd_access) begin
		s_axi_lite_rdata	<=	32'h0;
                  case (rd_addr_r[9:2])
                      RDMA_CONF_REG[9:2]: s_axi_lite_rdata <= {rdma_conf_udp_src_port ,rdma_conf_num_qps_enabled, rdma_conf_flow_credits, rdma_conf_err_buf_en,
                                                                rdma_conf_tx_ack_gen, rdma_conf_depkt_bypass_en, rdma_conf_ipver, rdma_conf_rdma_en};

                      RDMA_ADV_CONF_REG[9:2]: s_axi_lite_rdata <= {12'h0,rdma_adv_base_cnt,14'h0, rdma_adv_conf_errbuf_overwr_en, rdma_adv_conf_sw_override};

                      MAC_RDMA_ADDR_LSB_REG[9:2]: s_axi_lite_rdata <= mac_rdma_addr_lsb;
                      MAC_RDMA_ADDR_MSB_REG[9:2]: s_axi_lite_rdata <= {16'b0, mac_rdma_addr_msb};
                      IPV6_RDMA_ADDR1_REG[9:2]:     s_axi_lite_rdata <= ipv6_rdma_addr1    ;
                      IPV6_RDMA_ADDR2_REG[9:2]:     s_axi_lite_rdata <= ipv6_rdma_addr2    ;
                      IPV6_RDMA_ADDR3_REG[9:2]:     s_axi_lite_rdata <= ipv6_rdma_addr3    ;
                      IPV6_RDMA_ADDR4_REG[9:2]:     s_axi_lite_rdata <= ipv6_rdma_addr4    ;
                      TX_HDR_BUF_BA_REG[9:2]:    s_axi_lite_rdata <= tx_hdr_buf_ba   ;

                      TX_HDR_BUF_SZ_REG[9:2]:    s_axi_lite_rdata <= {tx_hdr_buf_sz_buf_sz, tx_hdr_buf_sz_num_hdrs};
                      TX_SGL_BUF_BA_REG[9:2]:    s_axi_lite_rdata <= tx_sgl_buf_ba;

                      TX_SGL_BUF_SZ_REG[9:2]:    s_axi_lite_rdata <= {tx_sgl_buf_sz_buf_sz,tx_sgl_buf_sz_num_sgls};
                      BYPASS_BUF_BA_REG[9:2]:    s_axi_lite_rdata <= bypass_buf_ba;
                      BYPASS_BUF_SZ_REG[9:2]:    s_axi_lite_rdata <= {bypass_buf_sz_buf_sz, bypass_buf_sz_num_bufs};
                      BYPASS_BUF_WRPTR_REG[9:2]: s_axi_lite_rdata <= {16'b0, i_bypass_buf_wrptr};

                      RQ_ERR_PKT_BUF_BA_REG[9:2]:   s_axi_lite_rdata <= rq_err_pkt_buf_ba;
                      RQ_ERR_PKT_BUF_SZ_REG[9:2]:   s_axi_lite_rdata <= {rq_err_pkt_buf_sz_buf_sz,rq_err_pkt_buf_sz_num_bufs};
                      IPV4_RDMA_ADDR_REG[9:2]:     s_axi_lite_rdata <= ipv4_rdma_addr;

                      OUT_ERRSTS_Q_BA_REG[9:2]:  s_axi_lite_rdata <= out_errsts_q_ba;
                      OUT_ERRSTS_Q_SZ_REG[9:2]:  s_axi_lite_rdata <= {16'b0, out_errsts_q_sz};
                      OUT_ERRSTS_Q_WRPTR_REG[9:2]:  s_axi_lite_rdata <= {16'b0, i_out_errsts_q_wrptr};

                      IN_ERRSTS_Q_BA_REG[9:2]:  s_axi_lite_rdata <= in_errsts_q_ba;
                      IN_ERRSTS_Q_SZ_REG[9:2]:  s_axi_lite_rdata <= {16'b0, in_errsts_q_sz};
                      IN_ERRSTS_Q_WRPTR_REG[9:2]:  s_axi_lite_rdata <= {16'b0, i_in_errsts_q_wrptr};

                      DATA_BUF_BA_REG[9:2]:      s_axi_lite_rdata <= data_buf_ba;
                      DATA_BUF_SZ_REG[9:2]:      s_axi_lite_rdata <= {data_buf_sz_buf_sz, data_buf_sz_num_bufs};

                      //CNCT_IO_CONF_REG[9:2]:     s_axi_lite_rdata <= {connect_io_residual_rq, 6'b0, connect_io_qp_rq_pi_db_wptr};
                      //UPdated the CNCT_IO_CONF register to have QPID and
                      //address. The QPID is used to get the current RQ_PI_DB
                      //value from BRAM which is fed to NVMf via the HW
                      //handhsake mechanism
                      CNCT_IO_CONF_REG[9:2]:     s_axi_lite_rdata <= {i_connect_io_qp_rq_pi_db_rdy,7'b0,connect_io_qpid , 6'b0, connect_io_qp_rq_pi_db_wptr};

                      RESP_ERR_PKT_BUF_BA_REG[9:2]:   s_axi_lite_rdata <= resp_err_pkt_buf_ba;
                      RESP_ERR_PKT_BUF_SZ_REG[9:2]:   s_axi_lite_rdata <= {resp_err_pkt_buf_sz_buf_sz,resp_err_pkt_buf_sz_num_bufs};

                      RX_PKT_HNDL_DBG_CTRL_REG[9:2]: s_axi_lite_rdata <= rx_pkt_hndl_dbg_ctrl;

                      // HW Doorbell WQE template registers
                      HW_WQE_REMOTE_ADDR_LO_REG[9:2]: s_axi_lite_rdata <= hw_wqe_remote_addr_lo;
                      HW_WQE_REMOTE_ADDR_HI_REG[9:2]: s_axi_lite_rdata <= hw_wqe_remote_addr_hi;
                      HW_WQE_RKEY_REG[9:2]:           s_axi_lite_rdata <= hw_wqe_rkey;
                      HW_WQE_LOCAL_ADDR_REG[9:2]:     s_axi_lite_rdata <= hw_wqe_local_addr;
                      HW_WQE_OPCODE_WRID_REG[9:2]:    s_axi_lite_rdata <= {8'd0, hw_wqe_wrid, hw_wqe_opcode};
                      INC_SR_PKT_CNT_REG[9:2]:   s_axi_lite_rdata <= {i_inc_rresp_pkt_cnt, i_inc_send_pkt_cnt};
                      INC_AM_PKT_CNT_REG[9:2]:   s_axi_lite_rdata <= {i_inc_mad_pkt_cnt, i_inc_ack_pkt_cnt};

                      OUT_SR_PKT_CNT_REG[9:2]:   s_axi_lite_rdata <= {i_out_rdwr_pkt_cnt, i_out_send_pkt_cnt};
                      OUT_AM_PKT_CNT_REG[9:2]:   s_axi_lite_rdata <= {i_out_mad_pkt_cnt, i_out_ack_pkt_cnt};

                      LAST_IN_PKT_REG[9:2]:      s_axi_lite_rdata <= i_last_in_pkt_info;//{last_in_pkt_psn_lsb, last_in_pkt_qpid, last_in_pkt_opcode};

                      LAST_OUT_PKT_REG[9:2]:     s_axi_lite_rdata <= i_last_out_pkt_info;//{last_out_pkt_psn_lsb, last_out_pkt_qpid, last_out_pkt_opcode};
                      INV_DUP_PKT_CNT_REG[9:2]:  s_axi_lite_rdata <= {i_inc_dup_pkt_cnt, i_inc_inv_pkt_cnt};
                      RNR_IN_PKT_STS_REG[9:2]:   s_axi_lite_rdata <= 'b0;
                      RNR_OUT_PKT_STS_REG[9:2]:  s_axi_lite_rdata <= 'b0;
                      WQE_PROC_STS_REG[9:2]:     s_axi_lite_rdata <= i_wqe_proc_sts;
                      RX_PKT_VLD_STS_REG[9:2]:   s_axi_lite_rdata <= i_rx_pkt_vld_sts;
                      QP_MGR_STS_REG[9:2]:       s_axi_lite_rdata <= i_qp_mgr_sts;
                      INC_ALL_DROPPED_CNT_REG[9:2]: s_axi_lite_rdata <= i_inc_all_dropped_cnt;
                      INC_NACK_CNT_REG[9:2]:     s_axi_lite_rdata <= {16'h0, i_inc_nack_cnt};
                      OUT_NACK_CNT_REG[9:2]:     s_axi_lite_rdata <= {16'h0, i_out_nack_cnt};
                      RESP_HNDL_STS_REG[9:2]:    s_axi_lite_rdata <= i_resp_hndler_sts;
                      RETRY_CNT_STS_REG[9:2]:    s_axi_lite_rdata <= i_stat_retry_cnt;
                      DBG_CNT_OVERRIDE_REG[9:2]: s_axi_lite_rdata <= {8'h0,i_axi_rd_err_cnt,rdma_sw_override_cnt};//i_min_ipg_stat;
                      IPG_0_4_PKT_CNT_REG[9:2]:  s_axi_lite_rdata <= i_ipg_0_4_cnt;
                      IPG_5_9_PKT_CNT_REG[9:2]:  s_axi_lite_rdata <= i_ipg_5_9_cnt;
                      IPG_10_14_PKT_CNT_REG[9:2]:s_axi_lite_rdata <= i_ipg_10_14_cnt;
                      IPG_15_19_PKT_CNT_REG[9:2]:s_axi_lite_rdata <= i_ipg_15_19_cnt;
		      GLOBAL_DBG_CNTR[9:2]	:s_axi_lite_rdata <= global_dbg_cnt ;
		      OSQ_BKP_SQE_BKP_CNT[9:2]	:s_axi_lite_rdata <= 	{osq_backpressure_cnt_ff, sqe_backpressure_cnt_ff};
		      RETRY_TX_BKP_HDR_BKP_CNT[9:2]:s_axi_lite_rdata <=      {i_retry_tx_backpressure_cnt,   i_hdr_backpressure_cnt}       ;
		      SQE_EMPTY_WQE_IDLE_CNT[9:2]:s_axi_lite_rdata   <=      {all_sqes_empty_cnt_ff, i_wqe_fsm_idle_cnt}               ;
		      WQE_PROC_SM_CNT0[9:2]	: s_axi_lite_rdata   <=      {i_wqe_proc_rd_q_info_cnt , i_wqe_proc_rd_wqe_cnt};
		      WQE_PROC_SM_CNT1[9:2]	: s_axi_lite_rdata   <=	     {i_wqe_proc_ip_chksum_cnt , i_wqe_proc_wait0_cnt };
		      WQE_PROC_SM_CNT2[9:2]	: s_axi_lite_rdata   <=	     {i_wqe_proc_hdr_sto_cnt , i_wqe_proc_hdr_gen_cnt };

                      INTR_EN_REG[9:2]:          s_axi_lite_rdata <= {25'b0, intr_en_fatal_err, intr_en_qp_pkt_rcvd, intr_en_ill_opc_in_sq, intr_en_wqe_cmpl,
                                                                     intr_en_rnr_nak_gen,
                                                                     intr_en_bypass_pkt_rcvd,intr_en_mad_pkt_rcvd,intr_en_pkt_valdn_err};

                      INTR_STS_REG[9:2]:         s_axi_lite_rdata <= {25'b0, qp_fatal_sts, |(i_qp_pkt_rcvd_intr), i_ill_opc_in_sq_intr, |(i_qp_wq_cmpl_intr),
                                                                     i_rnr_nack_gen_intr,
                                                                     i_bypass_pkt_rcvd_intr, i_mad_pkt_rcvd_intr, i_pkt_valdn_err_intr};
                      RQ_INTR_STS1_REG[9:2]:     s_axi_lite_rdata <= w_qp_pkt_rcvd_intr[31:0];

                      RQ_INTR_STS2_REG[9:2]:     s_axi_lite_rdata <= w_qp_pkt_rcvd_intr[63:32];

                      RQ_INTR_STS3_REG[9:2]:	 s_axi_lite_rdata <= w_qp_pkt_rcvd_intr[95:64];

                      RQ_INTR_STS4_REG[9:2]:	 s_axi_lite_rdata <= w_qp_pkt_rcvd_intr[127:96];

                      RQ_INTR_STS5_REG[9:2]:	 s_axi_lite_rdata <= w_qp_pkt_rcvd_intr[159:128];

                      RQ_INTR_STS6_REG[9:2]:	 s_axi_lite_rdata <= w_qp_pkt_rcvd_intr[191:160];

                      RQ_INTR_STS7_REG[9:2]:	 s_axi_lite_rdata <= w_qp_pkt_rcvd_intr[223:192];

                      RQ_INTR_STS8_REG[9:2]:     s_axi_lite_rdata <= w_qp_pkt_rcvd_intr[255:224];

                      CQ_INTR_STS1_REG[9:2]:     s_axi_lite_rdata <= w_qp_wq_cmpl_intr[31:0];

                      CQ_INTR_STS2_REG[9:2]:	 s_axi_lite_rdata <= w_qp_wq_cmpl_intr[63:32];

                      CQ_INTR_STS3_REG[9:2]:	 s_axi_lite_rdata <= w_qp_wq_cmpl_intr[95:64];

                      CQ_INTR_STS4_REG[9:2]:	 s_axi_lite_rdata <= w_qp_wq_cmpl_intr[127:96];

                      CQ_INTR_STS5_REG[9:2]:	 s_axi_lite_rdata <= w_qp_wq_cmpl_intr[159:128];

                      CQ_INTR_STS6_REG[9:2]:	 s_axi_lite_rdata <= w_qp_wq_cmpl_intr[191:160];

                      CQ_INTR_STS7_REG[9:2]:	 s_axi_lite_rdata <= w_qp_wq_cmpl_intr[223:192];

                      CQ_INTR_STS8_REG[9:2]:	 s_axi_lite_rdata <= w_qp_wq_cmpl_intr[255:224];

                      default:                   s_axi_lite_rdata <= 'b0;

                  endcase
              end
              else if (~s_axi_lite_rvalid & ~generic_reg_rd_access & (rd_addr_r[16:14]!=3'b111)) begin
                  case (rd_addr_r[7:0])
                      QP_CONF_QPN:          s_axi_lite_rdata <= s_axi_qp_config_rdata;
                      QP_ADV_CONF_QPN:      s_axi_lite_rdata <= s_axi_qp_adv_config_rdata;
                      RQ_BUF_BA_QPN:        s_axi_lite_rdata <= s_axi_rq_ba_rdata;
                      SQ_BA_QPN:            s_axi_lite_rdata <= s_axi_sq_ba_rdata;
                      CQ_BA_QPN:            s_axi_lite_rdata <= s_axi_cq_ba_rdata;
                      RQ_WRPTR_DB_ADD_QPN:  s_axi_lite_rdata <= s_axi_rq_wrptrdb_add_rdata;
                      SQ_CMPL_DB_ADD_QPN:   s_axi_lite_rdata <= s_axi_sq_cmpldb_add_rdata;
                      CQ_HEAD_QPN:          s_axi_lite_rdata <= s_axi_cq_hdptr_rdata;
                      RQ_CI_DB_QPN:         s_axi_lite_rdata <= s_axi_rq_cidb_rdata;
                      SQ_PI_DB_QPN:         s_axi_lite_rdata <= s_axi_sq_pidb_rdata;
                      Q_DEPTH_QPN:          s_axi_lite_rdata <= s_axi_q_depth_rdata;
                      SQ_PSN_QPN:           s_axi_lite_rdata <= s_axi_sq_psn_rdata;
                      LAST_RQ_QPN:          s_axi_lite_rdata <= s_axi_last_rq_rdata;
                      DEST_QP_CONF_QPN:     s_axi_lite_rdata <= s_axi_dest_qpid_rdata;
                      TIMEOUT_QPN:          s_axi_lite_rdata <= s_axi_timeout_rdata;
                      MAC_REMOTE_ADDR_LSB_QPN:s_axi_lite_rdata <= s_axi_mac_remote_addrl_rdata;
                      MAC_REMOTE_ADDR_MSB_QPN:s_axi_lite_rdata <= s_axi_mac_remote_addrm_rdata;
                      IP_REMOTE_ADDR1_QPN:    s_axi_lite_rdata <= s_axi_ip_remote_addr1_rdata;
                      STAT_SSN_QPN:         s_axi_lite_rdata <= s_axi_stat_ssn_rdata;
                      STAT_MSN_QPN:         s_axi_lite_rdata <= s_axi_stat_msn_rdata;
                      STAT_QPN:             s_axi_lite_rdata <= s_axi_stat_qpn_rdata;
                      STAT_CURR_SQPTR_PROC_QPN: s_axi_lite_rdata <= s_axi_curr_sqptr_proc_rdata;
                      STAT_RESP_PSN_QPN:    s_axi_lite_rdata <= s_axi_stat_resp_psn_rdata;
                      STAT_RQ_BUF_CA:       s_axi_lite_rdata <= s_axi_stat_rq_buf_ca_rdata;
                      STAT_WQE_CNT:         s_axi_lite_rdata <= s_axi_stat_wqe_cnt_rdata;
                      STAT_RQ_PI_DB:        s_axi_lite_rdata <= s_axi_stat_rq_pi_db_rdata;
                      STAT_RET_SQ_PSN:      s_axi_lite_rdata <= s_axi_stat_ret_sq_psn_rdata;
		      default	:	   s_axi_lite_rdata <= 'h0;
                   endcase
                end
		else if (~s_axi_lite_rvalid & ~generic_reg_rd_access & (rd_addr_r[16:14]==3'b111)) begin  //Address Space: 0x1_C000- 0x1_FFFF
			    case(rd_addr_r[3:2])
			    2'b00: s_axi_lite_rdata <= i_dbg_bram_rdata[31:0];   //Remote offset lsb 32 bits
			    2'b01: s_axi_lite_rdata <= i_dbg_bram_rdata[63:32];  //Remote Offset msb 32 bits
			    2'b10: s_axi_lite_rdata <= i_dbg_bram_rdata[95:64];  //Remote tag
			    2'b11: s_axi_lite_rdata <= {7'h0,i_dbg_bram_rdata[120:96]}; //Retry[24],WR ID[23:8], QP ID[7:0]
			    endcase
                end
              else if (s_axi_lite_rready)
                  s_axi_lite_rdata <= 'b0;
          end
      end
  end

  assign generic_reg_rd_access = (rd_addr_r[16:9] == 'b0);

  //******************************************************************************
  //AXI Lite write trasaction processing logic.
  //when a write transaction is received, depending on address bits [5:2] the
  //data is written in to the corresponding register.
  //The address bits [1:0] are not considred and it is expected that the
  //address is word aligned and writes into entire register.
  //******************************************************************************
  always @(posedge s_axi_lite_aclk)
  begin
      if(~s_axi_lite_aresetn)begin

          rdma_conf_rdma_en <= 'b0;
          rdma_conf_ipver <= 'b0;
          rdma_conf_tx_ack_gen <= 'b0;
          rdma_conf_err_buf_en <= 'b0;
          rdma_conf_flow_credits <= 'b0;
          rdma_conf_depkt_bypass_en <= 'b0;
          rdma_conf_num_qps_enabled <= 'b0;
          rdma_conf_udp_src_port <= 'b0;
          rdma_adv_conf_sw_override <= 'b0;
          rdma_adv_conf_errbuf_overwr_en <= 'b0;
          rdma_adv_base_cnt  <= 'd10;

          mac_rdma_addr_lsb <= 'b0;
          mac_rdma_addr_msb <= 'b0;

          ipv4_rdma_addr <= 'b0;
          ipv6_rdma_addr1 <= 'b0;
          ipv6_rdma_addr2 <= 'b0;
          ipv6_rdma_addr3 <= 'b0;
          ipv6_rdma_addr4 <= 'b0;

          tx_hdr_buf_ba <= 'b0;
          tx_hdr_buf_sz_num_hdrs <= 'b0;
          tx_hdr_buf_sz_buf_sz <= 'b0;

          tx_sgl_buf_ba <= 'b0;
          tx_sgl_buf_sz_num_sgls <= 'b0;
          tx_sgl_buf_sz_buf_sz <= 'b0;

          bypass_buf_ba <= 'b0;
          bypass_buf_sz_num_bufs <= 'b0;
          bypass_buf_sz_buf_sz <= 'b0;
          //bypass_buf_wrptr <= 'b0;

          data_buf_ba <= 'b0;
          data_buf_sz_num_bufs <= 'b0;
          data_buf_sz_buf_sz <= 'b0;

          connect_io_qp_rq_pi_db_wptr <= 'b0;
          connect_io_qpid <= 'b0;
          //connect_io_residual_rq <= 'b0;

          rq_err_pkt_buf_ba <= 'b0;
          rq_err_pkt_buf_sz_num_bufs <= 'b0;
          rq_err_pkt_buf_sz_buf_sz <= 'b0;
          //err_pkt_buf_wrptr <= 'b0;

          resp_err_pkt_buf_ba <= 'b0;
          resp_err_pkt_buf_sz_num_bufs <= 'b0;
          resp_err_pkt_buf_sz_buf_sz <= 'b0;

          rx_pkt_hndl_dbg_ctrl <= 'b0;

          rnr_nack_tval <= 'b0;
          retry_cnt <= 'b1;
          rnr_retry_cnt <= 'b1;
          timeout <= 'b0;

          out_errsts_q_ba <= 'b0;
          out_errsts_q_sz <= 'b0;

          in_errsts_q_ba  <= 'b0;
          in_errsts_q_sz  <= 'b0;

          hw_wqe_remote_addr_lo <= 32'd0;
          hw_wqe_remote_addr_hi <= 32'd0;
          hw_wqe_rkey           <= 32'd0;
          hw_wqe_local_addr     <= 32'd0;
          hw_wqe_opcode         <= 8'h00;  // RDMA_WRITE WQE opcode
          hw_wqe_wrid           <= 16'd0;

          intr_en_pkt_valdn_err <= 'b0;
          intr_en_wqe_cmpl <= 'b0;
          intr_en_mad_pkt_rcvd <= 'b0;
          intr_en_bypass_pkt_rcvd <= 'b0;
          intr_en_rnr_nak_gen <= 'b0;
          intr_en_qp_pkt_rcvd <= 'b0;
          intr_en_fatal_err <= 'b0;
          intr_en_ill_opc_in_sq <= 'b0;
          rq_intr_sts_clr <= 'b0;

      end else begin

          if(wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid & generic_reg_wr_access) begin
              case (wr_addr_r[9:2])
                  RDMA_CONF_REG[9:2]: begin
                      rdma_conf_rdma_en           <= s_axi_lite_wdata[0];
                      rdma_conf_ipver              <= s_axi_lite_wdata[1];
                      rdma_conf_depkt_bypass_en    <= s_axi_lite_wdata[2];
                      rdma_conf_tx_ack_gen         <= s_axi_lite_wdata[4:3];
                      rdma_conf_err_buf_en         <= s_axi_lite_wdata[5];
                      rdma_conf_flow_credits       <= s_axi_lite_wdata[7:6];
                      rdma_conf_num_qps_enabled    <= s_axi_lite_wdata[15:8];
                      rdma_conf_udp_src_port       <= s_axi_lite_wdata[31:16];
                  end

                  RDMA_ADV_CONF_REG[9:2]: begin
                      rdma_adv_conf_sw_override    <= s_axi_lite_wdata[0];
                      rdma_adv_conf_errbuf_overwr_en    <= s_axi_lite_wdata[1];
                      rdma_adv_base_cnt	    <= s_axi_lite_wdata[19:16];
                  end

                  MAC_RDMA_ADDR_LSB_REG[9:2]: mac_rdma_addr_lsb <= s_axi_lite_wdata[31:0];
                  MAC_RDMA_ADDR_MSB_REG[9:2]: mac_rdma_addr_msb <= s_axi_lite_wdata[15:0];
                  IPV6_RDMA_ADDR1_REG[9:2]:   ipv6_rdma_addr1     <= s_axi_lite_wdata[31:0];
                  IPV6_RDMA_ADDR2_REG[9:2]:   ipv6_rdma_addr2     <= s_axi_lite_wdata[31:0];
                  IPV6_RDMA_ADDR3_REG[9:2]:   ipv6_rdma_addr3     <= s_axi_lite_wdata[31:0];
                  IPV6_RDMA_ADDR4_REG[9:2]:   ipv6_rdma_addr4     <= s_axi_lite_wdata[31:0];
                  TX_HDR_BUF_BA_REG[9:2]:    tx_hdr_buf_ba    <= s_axi_lite_wdata[31:0];

                  TX_HDR_BUF_SZ_REG[9:2]: begin
                      tx_hdr_buf_sz_num_hdrs    <= s_axi_lite_wdata[15:0];
                      tx_hdr_buf_sz_buf_sz      <= s_axi_lite_wdata[31:16];
                  end

                  TX_SGL_BUF_BA_REG[9:2]:    tx_sgl_buf_ba    <= s_axi_lite_wdata[31:0];

                  TX_SGL_BUF_SZ_REG[9:2]: begin
                      tx_sgl_buf_sz_num_sgls    <= s_axi_lite_wdata[15:0];
                      tx_sgl_buf_sz_buf_sz      <= s_axi_lite_wdata[31:16];
                  end

                  BYPASS_BUF_BA_REG[9:2]:    bypass_buf_ba    <= s_axi_lite_wdata[31:0];

                  BYPASS_BUF_SZ_REG[9:2]: begin
                      bypass_buf_sz_num_bufs    <= s_axi_lite_wdata[15:0];
                      bypass_buf_sz_buf_sz      <= s_axi_lite_wdata[31:16];
                  end

//                  BYPASS_BUF_WRPTR_REG[9:2]: bypass_buf_wrptr <= s_axi_lite_wdata[15:0];

                  RQ_ERR_PKT_BUF_BA_REG[9:2]:   rq_err_pkt_buf_ba    <= s_axi_lite_wdata[31:0];

                  RQ_ERR_PKT_BUF_SZ_REG[9:2]: begin
                      rq_err_pkt_buf_sz_num_bufs    <= s_axi_lite_wdata[15:0];
                      rq_err_pkt_buf_sz_buf_sz      <= s_axi_lite_wdata[31:16];
                  end

                  DATA_BUF_BA_REG[9:2]:      data_buf_ba    <= s_axi_lite_wdata[31:0];

                  DATA_BUF_SZ_REG[9:2]: begin
                      data_buf_sz_num_bufs    <= s_axi_lite_wdata[15:0];
                      data_buf_sz_buf_sz      <= s_axi_lite_wdata[31:16];
                  end

                  CNCT_IO_CONF_REG[9:2]: begin
                      connect_io_qp_rq_pi_db_wptr <= s_axi_lite_wdata[9:0];
                      connect_io_qpid        <= s_axi_lite_wdata[23:16];
                      //connect_io_residual_rq <= s_axi_lite_wdata[31:16];
                  end

                  RESP_ERR_PKT_BUF_BA_REG[9:2]:   resp_err_pkt_buf_ba    <= s_axi_lite_wdata[31:0];

                  RESP_ERR_PKT_BUF_SZ_REG[9:2]: begin
                      resp_err_pkt_buf_sz_num_bufs    <= s_axi_lite_wdata[15:0];
                      resp_err_pkt_buf_sz_buf_sz      <= s_axi_lite_wdata[31:16];
                  end

                  RX_PKT_HNDL_DBG_CTRL_REG[9:2]: rx_pkt_hndl_dbg_ctrl <= s_axi_lite_wdata[31:0];

               //   ERR_PKT_BUF_WRPTR_REG[9:2]:    err_pkt_buf_wrptr <= s_axi_lite_wdata[15:0];
                  IPV4_RDMA_ADDR_REG[9:2]: begin
                      ipv4_rdma_addr     <= s_axi_lite_wdata[31:0];
                  end

                  // HW Doorbell WQE template registers
                  HW_WQE_REMOTE_ADDR_LO_REG[9:2]: hw_wqe_remote_addr_lo <= s_axi_lite_wdata[31:0];
                  HW_WQE_REMOTE_ADDR_HI_REG[9:2]: hw_wqe_remote_addr_hi <= s_axi_lite_wdata[31:0];
                  HW_WQE_RKEY_REG[9:2]:           hw_wqe_rkey           <= s_axi_lite_wdata[31:0];
                  HW_WQE_LOCAL_ADDR_REG[9:2]:     hw_wqe_local_addr     <= s_axi_lite_wdata[31:0];
                  HW_WQE_OPCODE_WRID_REG[9:2]: begin
                      hw_wqe_opcode         <= s_axi_lite_wdata[7:0];
                      hw_wqe_wrid           <= s_axi_lite_wdata[23:8];
                  end

                  OUT_ERRSTS_Q_BA_REG[9:2]:   out_errsts_q_ba    <= s_axi_lite_wdata[31:0];
                  OUT_ERRSTS_Q_SZ_REG[9:2]:   out_errsts_q_sz    <= s_axi_lite_wdata[15:0];

                  IN_ERRSTS_Q_BA_REG[9:2]:    in_errsts_q_ba     <= s_axi_lite_wdata[31:0];
                  IN_ERRSTS_Q_SZ_REG[9:2]:    in_errsts_q_sz     <= s_axi_lite_wdata[15:0];
		  //GLOBAL_DBG_CNTR[9:2]	 :    global_dbg_cnt	 <= s_axi_lite_wdata[31:0]; //Already in use

                  INTR_EN_REG[9:2]: begin
                      intr_en_pkt_valdn_err       <= s_axi_lite_wdata[0];
                      intr_en_mad_pkt_rcvd        <= s_axi_lite_wdata[1];
                      intr_en_bypass_pkt_rcvd     <= s_axi_lite_wdata[2];
                      intr_en_rnr_nak_gen         <= s_axi_lite_wdata[3];
                      intr_en_wqe_cmpl            <= s_axi_lite_wdata[4];
                      intr_en_ill_opc_in_sq       <= s_axi_lite_wdata[5];
                      intr_en_qp_pkt_rcvd         <= s_axi_lite_wdata[6];
                      intr_en_fatal_err           <= s_axi_lite_wdata[7];
                  end

                  RQ_INTR_STS1_REG[9:2]: rq_intr_sts_clr[31:0] <= s_axi_lite_wdata[31:0];
                  RQ_INTR_STS2_REG[9:2]: rq_intr_sts_clr[32*1 +: 32] <= s_axi_lite_wdata[31:0];
                  RQ_INTR_STS3_REG[9:2]: rq_intr_sts_clr[32*2 +: 32] <= s_axi_lite_wdata[31:0];
                  RQ_INTR_STS4_REG[9:2]: rq_intr_sts_clr[32*3 +: 32] <= s_axi_lite_wdata[31:0];
                  RQ_INTR_STS5_REG[9:2]: rq_intr_sts_clr[32*4 +: 32] <= s_axi_lite_wdata[31:0];
                  RQ_INTR_STS6_REG[9:2]: rq_intr_sts_clr[32*5 +: 32] <= s_axi_lite_wdata[31:0];
                  RQ_INTR_STS7_REG[9:2]: rq_intr_sts_clr[32*6 +: 32] <= s_axi_lite_wdata[31:0];
                  RQ_INTR_STS8_REG[9:2]: rq_intr_sts_clr[32*7 +: 32] <= s_axi_lite_wdata[31:0];

                  CQ_INTR_STS1_REG[9:2]: cq_intr_sts_clr[31:0] <= s_axi_lite_wdata[31:0];
                  CQ_INTR_STS2_REG[9:2]: cq_intr_sts_clr[32*1 +: 32] <= s_axi_lite_wdata[31:0];
                  CQ_INTR_STS3_REG[9:2]: cq_intr_sts_clr[32*2 +: 32] <= s_axi_lite_wdata[31:0];
                  CQ_INTR_STS4_REG[9:2]: cq_intr_sts_clr[32*3 +: 32] <= s_axi_lite_wdata[31:0];
                  CQ_INTR_STS5_REG[9:2]: cq_intr_sts_clr[32*4 +: 32] <= s_axi_lite_wdata[31:0];
                  CQ_INTR_STS6_REG[9:2]: cq_intr_sts_clr[32*5 +: 32] <= s_axi_lite_wdata[31:0];
                  CQ_INTR_STS7_REG[9:2]: cq_intr_sts_clr[32*6 +: 32] <= s_axi_lite_wdata[31:0];
                  CQ_INTR_STS8_REG[9:2]: cq_intr_sts_clr[32*7 +: 32] <= s_axi_lite_wdata[31:0];

              endcase
          end else begin
              rq_intr_sts_clr[255:0] <= 'b0;
              cq_intr_sts_clr[255:0] <= 'b0;
          end
      end
  end

  assign intr_clr = wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid & generic_reg_wr_access & (wr_addr_r[9:2] == INTR_STS_REG[9:2]);

  assign o_intr_clr_pkt_valdn_err      = intr_clr ? s_axi_lite_wdata[0] : 1'b0;
  assign o_intr_clr_mad_pkt_rcvd       = intr_clr ? s_axi_lite_wdata[1] : 1'b0;
  assign o_intr_clr_bypass_pkt_rcvd    = intr_clr ? s_axi_lite_wdata[2] : 1'b0;
  assign o_intr_clr_rnr_nak_gen        = intr_clr ? s_axi_lite_wdata[3] : 1'b0;
  assign o_intr_clr_wqe_cmpl           = intr_clr ? s_axi_lite_wdata[4] : 1'b0;
  assign o_intr_clr_ill_opc_in_sq      = intr_clr ? s_axi_lite_wdata[5] : 1'b0;
  assign o_intr_clr_qp_pkt_rcvd        = intr_clr ? s_axi_lite_wdata[6] : 1'b0;
  assign o_intr_clr_fatal_err          = ~qp_fatal_sts & qp_fatal_sts_ff;

  assign o_rq_intr_sts_clr = rq_intr_sts_clr;
  assign o_cq_intr_sts_clr = cq_intr_sts_clr;
  assign qp_fatal_sts      = |(i_qp_fatal_err);
  `MSFF_R(qp_fatal_sts_ff,qp_fatal_sts, core_clk, ~core_rstn)

  assign generic_reg_wr_access = (wr_addr_r[16:9] == 'b0);

  //********************************************************************************
  //This logic will generate BVALID signal for the write transaction.
  //********************************************************************************
  always @(posedge s_axi_lite_aclk)
  begin
      if(~s_axi_lite_aresetn) begin
          s_axi_lite_bvalid <= 1'b0;
      end else begin
          if(wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid) begin
              s_axi_lite_bvalid <= 1'b1;
          end else if(s_axi_lite_bready) begin
              s_axi_lite_bvalid <= 1'b0;
          end else begin
              s_axi_lite_bvalid <= s_axi_lite_bvalid;
          end
      end
  end

// BRAM: QP configuration registers (only 22 bits implemented)
// [0]      - QP_EN
// [1]      - ACK COALSC EN
// [2]      - RQ_INTR_EN
// [3]      - CQ_INTR_EN
// [4]      - HW_HNDSHK_DIS
// [7:4]    - RESERVED - not in BRAN
// [10:8]   - PMTU
// [15:11]  - RESERVED - not in BRAM
// [23:16]  - MAX_RD_OS
// [31:24]  - RQ_BUF_SZ
// ============================================================================
// QP SQ PI Doorbell BRAM
// ============================================================================
xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (27*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (27),              //positive integer
  .READ_DATA_WIDTH_A  (27),              //positive integer
  .BYTE_WRITE_WIDTH_A (27),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (27),              //positive integer
  .READ_DATA_WIDTH_B  (27),              //positive integer
  .BYTE_WRITE_WIDTH_B (27),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_qp_conf_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_conf_bram_wen),
  .addra          (qp_conf_bram_addr),
  .dina           ({s_axi_lite_wdata[31:24],s_axi_lite_wdata[23:16],s_axi_lite_wdata[10:6],s_axi_lite_wdata[5:0]}),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          ({s_axi_qp_config_rdata[31:16], s_axi_qp_config_rdata[10:6], s_axi_qp_config_rdata[5:0]}),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (1'b0),
  .addrb          (i_qp_conf_idx[0+:C_QP_INDX_WIDTH]),
  .dinb           (27'b0),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          ({o_qp_conf[31:24],o_qp_conf[23:16],o_qp_conf[10:6],o_qp_conf[5:0]}),
  .sbiterrb       (),
  .dbiterrb       ()

);

    assign o_qp_conf[15:11] = 'b0;
    assign o_qp_conf_replica[15:11] = 'b0;
    assign s_axi_qp_config_rdata[15:11] = 'b0;

    assign qp_conf_wr_addr = wr_addr_r[8+:C_QP_INDX_WIDTH] -8'h1 ;
    assign qp_conf_rd_addr = rd_addr_r[8+:C_QP_INDX_WIDTH] -8'h1;
    assign qp_conf_bram_addr =  qp_conf_bram_wen ? qp_conf_wr_addr : qp_conf_rd_addr;
    assign qp_conf_bram_wen = (wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid) && ((wr_addr_r[7:0] == QP_CONF_QPN) &&  (wr_addr_r[16:9] != 'b0));

// REPLICA MEMORY
// Some memories need to be replicated since IPG 0 implementation requires
// 2 parallel paths and hence needs independent access to some registers
// (without any delay). Any writes happen to both memories. Reads are
// independent
xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (27*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (27),              //positive integer
  .READ_DATA_WIDTH_A  (27),              //positive integer
  .BYTE_WRITE_WIDTH_A (27),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (27),              //positive integer
  .READ_DATA_WIDTH_B  (27),              //positive integer
  .BYTE_WRITE_WIDTH_B (27),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_replica_qp_conf_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_conf_bram_wen),
  .addra          (qp_conf_bram_addr),
  .dina           ({s_axi_lite_wdata[31:24],s_axi_lite_wdata[23:16],s_axi_lite_wdata[10:6],s_axi_lite_wdata[5:0]}),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (1'b0),
  .addrb          (i_qp_conf_replica_idx[0+:C_QP_INDX_WIDTH]),
  .dinb           (27'b0),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          ({o_qp_conf_replica[31:24],o_qp_conf_replica[23:16],o_qp_conf_replica[10:6],o_qp_conf_replica[5:0]}),
  .sbiterrb       (),
  .dbiterrb       ()

);

// BRAM: QP advance configuration registers (only 30 bits implemented)
// [5:0]    - TRAFFIC CLASS
// [7:6]    - RESERVED
// [15:8]   - TIME_TO_LIVE
// [31:16]  - P_KEY

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (30*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (30),              //positive integer
  .READ_DATA_WIDTH_A  (30),              //positive integer
  .BYTE_WRITE_WIDTH_A (30),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (30),              //positive integer
  .READ_DATA_WIDTH_B  (30),              //positive integer
  .BYTE_WRITE_WIDTH_B (30),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_qp_adv_conf_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_adv_conf_bram_wen),
  .addra          (qp_adv_conf_bram_addr),
  .dina           ({s_axi_lite_wdata[31:8],s_axi_lite_wdata[5:0]}),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          ({s_axi_qp_adv_config_rdata[31:8], s_axi_qp_adv_config_rdata[5:0]}),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (1'b0),
  .addrb          (i_qp_adv_conf_idx[0+:C_QP_INDX_WIDTH]),
  .dinb           (30'b0),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          ({o_qp_adv_conf[31:8],o_qp_adv_conf[5:0]}),
  .sbiterrb       (),
  .dbiterrb       ()

);

    assign o_qp_adv_conf[7:6]   = 'b0;
    assign s_axi_qp_adv_config_rdata[7:6]   = 'b0;

    assign qp_adv_conf_wr_addr = wr_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_adv_conf_rd_addr = rd_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_adv_conf_bram_addr =  qp_adv_conf_bram_wen ? qp_adv_conf_wr_addr : qp_adv_conf_rd_addr;
    assign qp_adv_conf_bram_wen = (wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid) && ((wr_addr_r[7:0] == QP_ADV_CONF_QPN) &&  (wr_addr_r[16:9] != 'b0));

// BRAM: QP RQ BUF BASE address registers (only 24 bits implemented)
// [7:0]    - RESERVED
// [31:8]   - RQ_BUF_BA

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (24*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (24),              //positive integer
  .READ_DATA_WIDTH_A  (24),              //positive integer
  .BYTE_WRITE_WIDTH_A (24),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (24),              //positive integer
  .READ_DATA_WIDTH_B  (24),              //positive integer
  .BYTE_WRITE_WIDTH_B (24),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_qp_rq_ba_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_rq_ba_bram_wen),
  .addra          (qp_rq_ba_bram_addr),
  .dina           (s_axi_lite_wdata[31:8]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (s_axi_rq_ba_rdata[31:8]),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (1'b0),
  .addrb          (i_qp_rq_ba_idx[0+:C_QP_INDX_WIDTH]),
  .dinb           (24'b0),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_rq_ba[23:0]),
  .sbiterrb       (),
  .dbiterrb       ()

);

    assign s_axi_rq_ba_rdata[7:0]   = 'b0;

    assign qp_rq_ba_wr_addr = wr_addr_r[8+:C_QP_INDX_WIDTH]-8'h1;
    assign qp_rq_ba_rd_addr = rd_addr_r[8+:C_QP_INDX_WIDTH]-8'h1;
    assign qp_rq_ba_bram_addr =  qp_rq_ba_bram_wen ? qp_rq_ba_wr_addr : qp_rq_ba_rd_addr;
    assign qp_rq_ba_bram_wen  = (wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid) && ((wr_addr_r[7:0] == RQ_BUF_BA_QPN) &&  (wr_addr_r[16:9] != 'b0));

// BRAM: QP SQ BASE address registers (only 27 bits implemented)
// [4:0]    - RESERVED
// [31:5]   - SQ_BA

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (27*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (27),              //positive integer
  .READ_DATA_WIDTH_A  (27),              //positive integer
  .BYTE_WRITE_WIDTH_A (27),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (27),              //positive integer
  .READ_DATA_WIDTH_B  (27),              //positive integer
  .BYTE_WRITE_WIDTH_B (27),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_qp_sq_ba_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_sq_ba_bram_wen),
  .addra          (qp_sq_ba_bram_addr),
  .dina           (s_axi_lite_wdata[31:5]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (s_axi_sq_ba_rdata[31:5]),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (1'b0),
  .addrb          (i_qp_sq_ba_idx[0+:C_QP_INDX_WIDTH]),
  .dinb           (27'b0),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_sq_ba[31:5]),
  .sbiterrb       (),
  .dbiterrb       ()

);

    assign o_qp_sq_ba[4:0]   = 'b0;
    assign s_axi_sq_ba_rdata[4:0]   = 'b0;

    assign qp_sq_ba_wr_addr = wr_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_sq_ba_rd_addr = rd_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_sq_ba_bram_addr =  qp_sq_ba_bram_wen ? qp_sq_ba_wr_addr : qp_sq_ba_rd_addr;
    assign qp_sq_ba_bram_wen  = (wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid) && ((wr_addr_r[7:0] == SQ_BA_QPN) &&  (wr_addr_r[16:9] != 'b0));

// BRAM: QP CQ BASE address registers (only 27 bits implemented)
// [4:0]    - RESERVED
// [31:5]   - CQ_BA
xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (27*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (27),              //positive integer
  .READ_DATA_WIDTH_A  (27),              //positive integer
  .BYTE_WRITE_WIDTH_A (27),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (27),              //positive integer
  .READ_DATA_WIDTH_B  (27),              //positive integer
  .BYTE_WRITE_WIDTH_B (27),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_qp_cq_ba_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_cq_ba_bram_wen),
  .addra          (qp_cq_ba_bram_addr),
  .dina           (s_axi_lite_wdata[31:5]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (s_axi_cq_ba_rdata[31:5]),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (1'b0),
  .addrb          (i_qp_cq_ba_idx[0+:C_QP_INDX_WIDTH]),
  .dinb           (27'b0),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_cq_ba[31:5]),
  .sbiterrb       (),
  .dbiterrb       ()

);

    assign o_qp_cq_ba[4:0]   = 'b0;
    assign s_axi_cq_ba_rdata[4:0]   = 'b0;

    assign qp_cq_ba_wr_addr = wr_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1; // The repeating registers start at 0x200 so need to normalize
    assign qp_cq_ba_rd_addr = rd_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_cq_ba_bram_addr =  qp_cq_ba_bram_wen ? qp_cq_ba_wr_addr : qp_cq_ba_rd_addr;
    assign qp_cq_ba_bram_wen  = (wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid) && ((wr_addr_r[7:0] == CQ_BA_QPN) &&  (wr_addr_r[16:9] != 'b0));

// BRAM: QP RQ WRPTR DB address registers
// [31:0]   - RQ_WRPTR_DB_ADD

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (32*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (32),              //positive integer
  .READ_DATA_WIDTH_A  (32),              //positive integer
  .BYTE_WRITE_WIDTH_A (32),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (32),              //positive integer
  .READ_DATA_WIDTH_B  (32),              //positive integer
  .BYTE_WRITE_WIDTH_B (32),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_qp_rq_wrptrdb_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_rq_wrptrdb_add_bram_wen),
  .addra          (qp_rq_wrptrdb_add_bram_addr),
  .dina           (s_axi_lite_wdata[31:0]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (s_axi_rq_wrptrdb_add_rdata),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (1'b0),
  .addrb          (i_qp_rq_wrptrdb_add_idx[0+:C_QP_INDX_WIDTH]),
  .dinb           ('b0),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_rq_wrptrdb_add[31:0]),
  .sbiterrb       (),
  .dbiterrb       ()

);

    assign qp_rq_wrptrdb_add_wr_addr = wr_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;// The repeating registers start at 0x200 so need to normalize
    assign qp_rq_wrptrdb_add_rd_addr = rd_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_rq_wrptrdb_add_bram_addr =  qp_rq_wrptrdb_add_bram_wen ? qp_rq_wrptrdb_add_wr_addr : qp_rq_wrptrdb_add_rd_addr;
    assign qp_rq_wrptrdb_add_bram_wen  = (wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid) && ((wr_addr_r[7:0] == RQ_WRPTR_DB_ADD_QPN) &&  (wr_addr_r[16:9] != 'b0));

// BRAM: QP SQ completions DB address registers
// [31:0]   - SQ_CMPL_DB_ADD

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (32*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (32),              //positive integer
  .READ_DATA_WIDTH_A  (32),              //positive integer
  .BYTE_WRITE_WIDTH_A (32),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (32),              //positive integer
  .READ_DATA_WIDTH_B  (32),              //positive integer
  .BYTE_WRITE_WIDTH_B (32),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_qp_sq_cmpldb_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_sq_cmpldb_add_bram_wen),
  .addra          (qp_sq_cmpldb_add_bram_addr),
  .dina           (s_axi_lite_wdata[31:0]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (s_axi_sq_cmpldb_add_rdata),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (1'b0),
  .addrb          (i_qp_sq_cmpldb_add_idx[0+:C_QP_INDX_WIDTH]),
  .dinb           ('b0),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_sq_cmpldb_add[31:0]),
  .sbiterrb       (),
  .dbiterrb       ()

);

    assign qp_sq_cmpldb_add_wr_addr = wr_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;// The repeating registers start at 0x200 so need to normalize
    assign qp_sq_cmpldb_add_rd_addr = rd_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_sq_cmpldb_add_bram_addr =  qp_sq_cmpldb_add_bram_wen ? qp_sq_cmpldb_add_wr_addr : qp_sq_cmpldb_add_rd_addr;
    assign qp_sq_cmpldb_add_bram_wen  = (wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid) && ((wr_addr_r[7:0] == SQ_CMPL_DB_ADD_QPN) &&  (wr_addr_r[16:9] != 'b0));

// BRAM: QP CQ Head pointer registers
// [15:0]   - CQ_HDPTR

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (16*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (16),              //positive integer
  .READ_DATA_WIDTH_A  (16),              //positive integer
  .BYTE_WRITE_WIDTH_A (16),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (16),              //positive integer
  .READ_DATA_WIDTH_B  (16),              //positive integer
  .BYTE_WRITE_WIDTH_B (16),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_qp_cq_hdptr_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_cq_hdptr_bram_wen),
  .addra          (qp_cq_hdptr_bram_addr),
  .dina           (s_axi_lite_wdata[15:0]),  // CQ Head pointer - from AXI-Lite
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (s_axi_cq_hdptr_rdata[15:0]),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (i_qp_cq_hdptr_wrn & ~i_qp_cq_hdptr_retry_req),
  .addrb          (i_qp_cq_hdptr_idx[0+:C_QP_INDX_WIDTH]),
  .dinb           (i_qp_cq_hdptr),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_cq_hdptr[15:0]),
  .sbiterrb       (),
  .dbiterrb       ()

);

    assign s_axi_cq_hdptr_rdata[31:16]   = 'b0;

    assign qp_cq_hdptr_wr_addr = wr_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;// The repeating registers start at 0x200 so need to normalize
    assign qp_cq_hdptr_rd_addr = rd_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_cq_hdptr_bram_addr =  qp_cq_hdptr_bram_wen ? qp_cq_hdptr_wr_addr : qp_cq_hdptr_rd_addr;
    // SW override
    assign qp_cq_hdptr_bram_wen  = rdma_adv_conf_sw_override & (wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid) && ((wr_addr_r[7:0] == CQ_HEAD_QPN) &&  (wr_addr_r[16:9] != 'b0));

// BRAM: QP RQ CI doorbell registers
// [15:0]   - RQ CI Doorbell

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (16*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (16),              //positive integer
  .READ_DATA_WIDTH_A  (16),              //positive integer
  .BYTE_WRITE_WIDTH_A (16),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (16),              //positive integer
  .READ_DATA_WIDTH_B  (16),              //positive integer
  .BYTE_WRITE_WIDTH_B (16),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_qp_rq_ci_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_rq_cidb_bram_wen),
  .addra          (qp_rq_cidb_bram_addr),
  .dina           (s_axi_lite_wdata[15:0]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (s_axi_rq_cidb_rdata[15:0]),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (i_qp_rq_cidb_wr_valid_hndshk & ~i_qp_rq_cidb_req),
  .addrb          (rq_cidb_idx[0+:C_QP_INDX_WIDTH]),
  .dinb           (i_qp_rq_cidb_hndshk),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_rq_cidb[15:0]),
  .sbiterrb       (),
  .dbiterrb       ()

);

    assign o_qp_rq_cidb[31:16]   = 'b0;
    assign s_axi_rq_cidb_rdata[31:16]   = 'b0;

    assign rq_cidb_idx = i_qp_rq_cidb_req ? i_qp_rq_cidb_idx : qp_rq_cidb_wr_addr_hndshk;
    assign qp_rq_cidb_wr_addr_hndshk = i_qp_rq_cidb_wr_addr_hndshk[8+:C_QP_INDX_WIDTH] - 8'h1;

    assign qp_rq_cidb_wr_addr = wr_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;// The repeating registers start at 0x200 so need to normalize
    assign qp_rq_cidb_rd_addr = rd_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_rq_cidb_bram_addr =  qp_rq_cidb_bram_wen ? qp_rq_cidb_wr_addr : qp_rq_cidb_rd_addr;
    assign qp_rq_cidb_bram_wen  = (wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid) && ((wr_addr_r[7:0] == RQ_CI_DB_QPN) &&  (wr_addr_r[16:9] != 'b0));

// BRAM: QP SQ PI doorbell registers
// [15:0]   - SQ PI Doorbell

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (16*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (16),              //positive integer
  .READ_DATA_WIDTH_A  (16),              //positive integer
  .BYTE_WRITE_WIDTH_A (16),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (16),              //positive integer
  .READ_DATA_WIDTH_B  (16),              //positive integer
  .BYTE_WRITE_WIDTH_B (16),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_qp_sq_pidb_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_sq_pidb_bram_wen),
  .addra          (qp_sq_pidb_bram_addr),
  .dina           (s_axi_lite_wdata[15:0]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (s_axi_sq_pidb_rdata[15:0]),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (qp_sq_pidb_wen),
  .addrb          (qp_sq_pidb_addr),
  .dinb           (i_qp_sq_pidb_hndshk),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (sq_pidb[15:0]),
  .sbiterrb       (),
  .dbiterrb       ()

);

    assign s_axi_sq_pidb_rdata[31:16]   = 'b0;
    assign o_qp_sq_pidb[15:0] = sq_pidb[15:0];

    assign qp_sq_pidb_addr = i_qp_sq_pidb_req ? i_qp_sq_pidb_idx : (i_qp_sq_pidb_wr_valid_hndshk ? qp_sq_pidb_hndshk_addr : pending_idx);
    assign qp_sq_pidb_wen = i_qp_sq_pidb_req ? 1'b0 : i_qp_sq_pidb_wr_valid_hndshk;

    assign qp_sq_pidb_hndshk_addr = i_qp_sq_pidb_wr_addr_hndshk[8+:C_QP_INDX_WIDTH] - 8'h1;

    assign qp_sq_pidb_wr_addr = wr_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;// The repeating registers start at 0x200 so need to normalize
    assign qp_sq_pidb_rd_addr = rd_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_sq_pidb_bram_addr =  qp_sq_pidb_bram_wen ? qp_sq_pidb_wr_addr : qp_sq_pidb_rd_addr;
    assign qp_sq_pidb_bram_wen  = (wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid) && ((wr_addr_r[7:0] == SQ_PI_DB_QPN) && (wr_addr_r[16:9] != 'b0));

// BRAM: QP Queue depth registers - implemented in 2 different BRAMs as they
// are required asynchronously
// [15:0]   - SQ depth
// [31:16]  - RQ depth

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (16*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (16),              //positive integer
  .READ_DATA_WIDTH_A  (16),              //positive integer
  .BYTE_WRITE_WIDTH_A (16),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (16),              //positive integer
  .READ_DATA_WIDTH_B  (16),              //positive integer
  .BYTE_WRITE_WIDTH_B (16),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_qp_sq_depth_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_q_depth_bram_wen),
  .addra          (qp_q_depth_bram_addr),
  .dina           (s_axi_lite_wdata[15:0]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (s_axi_q_depth_rdata[15:0]),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (1'b0),
  .addrb          (qp_depth_idx[0+:C_QP_INDX_WIDTH]),
  .dinb           (16'b0),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_sq_depth[15:0]),
  .sbiterrb       (),
  .dbiterrb       ()

);

 assign qp_depth_idx = i_qp_cq_depth_req ? i_qp_cq_depth_idx : i_qp_sq_depth_idx;
 assign o_qp_cq_depth = o_qp_sq_depth;

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (16*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (16),              //positive integer
  .READ_DATA_WIDTH_A  (16),              //positive integer
  .BYTE_WRITE_WIDTH_A (16),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (16),              //positive integer
  .READ_DATA_WIDTH_B  (16),              //positive integer
  .BYTE_WRITE_WIDTH_B (16),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_qp_rq_depth_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_q_depth_bram_wen),
  .addra          (qp_q_depth_bram_addr),
  .dina           (s_axi_lite_wdata[31:16]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (s_axi_q_depth_rdata[31:16]),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (1'b0),
  .addrb          (i_qp_rq_depth_idx[0+:C_QP_INDX_WIDTH]),
  .dinb           (16'b0),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_rq_depth[15:0]),
  .sbiterrb       (),
  .dbiterrb       ()

);

    assign qp_q_depth_wr_addr = wr_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;// The repeating registers start at 0x200 so need to normalize
    assign qp_q_depth_rd_addr = rd_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_q_depth_bram_addr =  qp_q_depth_bram_wen ? qp_q_depth_wr_addr : qp_q_depth_rd_addr;
    assign qp_q_depth_bram_wen  = (wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid) && ((wr_addr_r[7:0] == Q_DEPTH_QPN) &&  (wr_addr_r[16:9] != 'b0));

// BRAM: QP SQ PSN registers
// [23:0]   - SQ PSN

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (24*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (24),              //positive integer
  .READ_DATA_WIDTH_A  (24),              //positive integer
  .BYTE_WRITE_WIDTH_A (24),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (24),              //positive integer
  .READ_DATA_WIDTH_B  (24),              //positive integer
  .BYTE_WRITE_WIDTH_B (24),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_qp_sq_psn_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_sq_psn_bram_wen),
  .addra          (qp_sq_psn_bram_addr),
  .dina           (s_axi_lite_wdata[23:0]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (s_axi_sq_psn_rdata[23:0]),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (((i_qp_sq_psn_wrn | i_qp_sq_psn_retry_wrn) & ~i_qp_sq_psn_req)),
  .addrb          (muxed_qp_sq_psn_idx[0+:C_QP_INDX_WIDTH]),
  .dinb           (i_qp_sq_psn),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_sq_psn[23:0]),
  .sbiterrb       (),
  .dbiterrb       ()

);

    assign muxed_qp_sq_psn_idx = i_qp_sq_psn_req ? i_qp_sq_psn_idx : ((i_qp_sq_psn_retry_req | i_qp_sq_psn_retry_wrn) ? i_qp_sq_psn_retry_idx : i_qp_sq_psn_wqe_idx);
    assign s_axi_sq_psn_rdata[31:24]   = 'b0;

    assign qp_sq_psn_wr_addr = wr_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;// The repeating registers start at 0x200 so need to normalize
    assign qp_sq_psn_rd_addr = rd_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_sq_psn_bram_addr =  qp_sq_psn_bram_wen ? qp_sq_psn_wr_addr : qp_sq_psn_rd_addr;
    assign qp_sq_psn_bram_wen  = (wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid) && ((wr_addr_r[7:0] == SQ_PSN_QPN) &&  (wr_addr_r[16:9] != 'b0));

genvar k0;
generate
for (k0 = 0; k0 <C_NUM_QP; k0 = k0 +1)
  begin: qp_disable_pulse
   //Whenever QP enable bit write pulse is used to reset the
   //first_outgoing_pkt_ff in resp_pkt_handler.
   assign o_qp_disable_pulse[k0] = qp_conf_bram_wen & (qp_conf_wr_addr == k0) & ~s_axi_lite_wdata[0]; //TODO
  end
endgenerate

// BRAM: QP RQ PSN registers
// [23:0]   - RQ PSN

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (32*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (32),              //positive integer
  .READ_DATA_WIDTH_A  (32),              //positive integer
  .BYTE_WRITE_WIDTH_A (32),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (32),              //positive integer
  .READ_DATA_WIDTH_B  (32),              //positive integer
  .BYTE_WRITE_WIDTH_B (32),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_qp_last_rq_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_last_rq_bram_wen),
  .addra          (qp_last_rq_bram_addr),
  .dina           (s_axi_lite_wdata[31:0]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (s_axi_last_rq_rdata[31:0]),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (i_qp_last_rq_wrn),
  .addrb          (i_qp_last_rq_idx[0+:C_QP_INDX_WIDTH]),
  .dinb           (i_qp_last_rq),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_last_rq[31:0]),
  .sbiterrb       (),
  .dbiterrb       ()

);

    assign qp_last_rq_wr_addr = wr_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;// The repeating registers start at 0x200 so need to normalize
    assign qp_last_rq_rd_addr = rd_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_last_rq_bram_addr =  qp_last_rq_bram_wen ? qp_last_rq_wr_addr : qp_last_rq_rd_addr;
    assign qp_last_rq_bram_wen  = (wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid) && ((wr_addr_r[7:0] == LAST_RQ_QPN) &&  (wr_addr_r[16:9] != 'b0));

// BRAM: Dest QP conf registers
// [23:0]   - Dest QP ID

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (24*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (24),              //positive integer
  .READ_DATA_WIDTH_A  (24),              //positive integer
  .BYTE_WRITE_WIDTH_A (24),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (24),              //positive integer
  .READ_DATA_WIDTH_B  (24),              //positive integer
  .BYTE_WRITE_WIDTH_B (24),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_qp_dest_qpid_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_dest_qpid_bram_wen),
  .addra          (qp_dest_qpid_bram_addr),
  .dina           (s_axi_lite_wdata[23:0]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (s_axi_dest_qpid_rdata[23:0]),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (1'b0),
  .addrb          (i_qp_dest_qpid_idx[0+:C_QP_INDX_WIDTH]),
  .dinb           (24'b0),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_dest_qpid[23:0]),
  .sbiterrb       (),
  .dbiterrb       ()

);

    assign s_axi_dest_qpid_rdata[31:24]   = 'b0;

    assign qp_dest_qpid_wr_addr = wr_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;// The repeating registers start at 0x200 so need to normalize
    assign qp_dest_qpid_rd_addr = rd_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_dest_qpid_bram_addr =  qp_dest_qpid_bram_wen ? qp_dest_qpid_wr_addr : qp_dest_qpid_rd_addr;
    assign qp_dest_qpid_bram_wen  = (wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid) && ((wr_addr_r[7:0] == DEST_QP_CONF_QPN) &&  (wr_addr_r[16:9] != 'b0));

// //-----------------------------------------------------------------------------------------------------
// BRAM: QP timeout register
// [4:0]   - TIMEOUT VALUE
// [7:5]   - reserved - not implemented
// [10:8]  - RETRY_CNT
// [13:11] - RNR_RETRY_CNT
// [15:14] - reserved - not implemented
// [20:16] - RNR_NACK_TVAL
// [31:21] - reserved - not implemented
// Total 16 bits implemented
xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (16*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (16),              //positive integer
  .READ_DATA_WIDTH_A  (16),              //positive integer
  .BYTE_WRITE_WIDTH_A (16),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (16),              //positive integer
  .READ_DATA_WIDTH_B  (16),              //positive integer
  .BYTE_WRITE_WIDTH_B (16),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_qp_timeout_reg1 (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_timeout_bram_wen),
  .addra          (qp_timeout_bram_addr),
  .dina           ({s_axi_lite_wdata[20:16], s_axi_lite_wdata[13:11], s_axi_lite_wdata[10:8], s_axi_lite_wdata[4:0]}),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          ({s_axi_timeout_rdata[20:16],s_axi_timeout_rdata[13:11], s_axi_timeout_rdata[10:8],s_axi_timeout_rdata[4:0]}),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (1'b0),
  .addrb          (i_qp_timeout_idx[0+:C_QP_INDX_WIDTH]),
  .dinb           ('b0),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          ({o_qp_timeout[20:16], o_qp_timeout[13:11], o_qp_timeout[10:8], o_qp_timeout[4:0]}),
  .sbiterrb       (),
  .dbiterrb       ()

);

// These are status bits implemented for STAT_QP register.
//  stat - [26:24] - CURR_RETRY_CNT
//  stat - [27]    - REserved - not implemented
//  stat - [30:28] - CURR_RNR_NACK_CNT

    assign o_qp_timeout[7:5]   = 'b0;
    assign o_qp_timeout[15:14]   = 'b0;
    assign o_qp_timeout[31:21]   = 'b0;
    assign s_axi_timeout_rdata[7:5]   = 'b0;
    assign s_axi_timeout_rdata[15:14]   = 'b0;
    assign s_axi_timeout_rdata[31:21]   = 'b0;

    assign qp_timeout_wr_addr = wr_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_timeout_rd_addr = rd_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_timeout_bram_addr =  qp_timeout_bram_wen ? qp_timeout_wr_addr : qp_timeout_rd_addr;
    assign qp_timeout_bram_wen  = (wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid) && ((wr_addr_r[7:0] == TIMEOUT_QPN) &&  (wr_addr_r[16:9] != 'b0));

// BRAM: QP MAC REMOTE ADDR LSB register
// [31:0]   - MAC REMOTE ADDR VALUE
xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (32*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (32),              //positive integer
  .READ_DATA_WIDTH_A  (32),              //positive integer
  .BYTE_WRITE_WIDTH_A (32),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (32),              //positive integer
  .READ_DATA_WIDTH_B  (32),              //positive integer
  .BYTE_WRITE_WIDTH_B (32),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_qp_mac_remote1_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_mac_remote_addrl_bram_wen),
  .addra          (qp_mac_remote_addrl_bram_addr),
  .dina           (s_axi_lite_wdata[31:0]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (s_axi_mac_remote_addrl_rdata),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (1'b0),
  .addrb          (muxed_qp_mac_remote_addrl_idx[0+:C_QP_INDX_WIDTH]),
  .dinb           ('b0),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_mac_remote_addrl[31:0]),
  .sbiterrb       (),
  .dbiterrb       ()

);

    assign muxed_qp_mac_remote_addrl_idx = i_qp_mac_remote_addrl_req ? i_qp_mac_remote_addrl_idx : i_qp_mac_remote_addrl_wqe_idx;
    assign qp_mac_remote_addrl_wr_addr = wr_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_mac_remote_addrl_rd_addr = rd_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_mac_remote_addrl_bram_addr =  qp_mac_remote_addrl_bram_wen ? qp_mac_remote_addrl_wr_addr : qp_mac_remote_addrl_rd_addr;
    assign qp_mac_remote_addrl_bram_wen  = (wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid) && ((wr_addr_r[7:0] == MAC_REMOTE_ADDR_LSB_QPN) &&  (wr_addr_r[16:9] != 'b0));

// REPLICA MEMORY
// Some memories need to be replicated since IPG 0 implementation requires
// 2 parallel paths and hence needs independent access to some registers
// (without any delay). Any writes happen to both memories. Reads are
// independent
xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (32*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (32),              //positive integer
  .READ_DATA_WIDTH_A  (32),              //positive integer
  .BYTE_WRITE_WIDTH_A (32),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (32),              //positive integer
  .READ_DATA_WIDTH_B  (32),              //positive integer
  .BYTE_WRITE_WIDTH_B (32),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_qp_mac_remote1_replica_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_mac_remote_addrl_bram_wen),
  .addra          (qp_mac_remote_addrl_bram_addr),
  .dina           (s_axi_lite_wdata[31:0]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (1'b0),
  .addrb          (i_qp_mac_remote_addrl_replica_idx[0+:C_QP_INDX_WIDTH]),
  .dinb           ('b0),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_mac_remote_addrl_replica[31:0]),
  .sbiterrb       (),
  .dbiterrb       ()

);

// BRAM: QP MAC DEST ADDR MSB register
// [15:0]   - MAC DEST ADDR VALUE

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (16*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (16),              //positive integer
  .READ_DATA_WIDTH_A  (16),              //positive integer
  .BYTE_WRITE_WIDTH_A (16),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (16),              //positive integer
  .READ_DATA_WIDTH_B  (16),              //positive integer
  .BYTE_WRITE_WIDTH_B (16),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_qp_mac_remote2_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_mac_remote_addrm_bram_wen),
  .addra          (qp_mac_remote_addrm_bram_addr),
  .dina           (s_axi_lite_wdata[15:0]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (s_axi_mac_remote_addrm_rdata[15:0]),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (1'b0),
  .addrb          (muxed_qp_mac_remote_addrm_idx[0+:C_QP_INDX_WIDTH]),
  .dinb           (16'b0),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_mac_remote_addrm[15:0]),
  .sbiterrb       (),
  .dbiterrb       ()

);

    assign o_qp_mac_remote_addrm[31:16]   = 'b0;
    assign s_axi_mac_remote_addrm_rdata[31:16]   = 'b0;

    assign muxed_qp_mac_remote_addrm_idx = i_qp_mac_remote_addrm_req ? i_qp_mac_remote_addrm_idx : i_qp_mac_remote_addrm_wqe_idx;
    assign qp_mac_remote_addrm_wr_addr = wr_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_mac_remote_addrm_rd_addr = rd_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_mac_remote_addrm_bram_addr =  qp_mac_remote_addrm_bram_wen ? qp_mac_remote_addrm_wr_addr : qp_mac_remote_addrm_rd_addr;
    assign qp_mac_remote_addrm_bram_wen  = (wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid) && ((wr_addr_r[7:0] == MAC_REMOTE_ADDR_MSB_QPN) &&  (wr_addr_r[16:9] != 'b0));

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (16*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (16),              //positive integer
  .READ_DATA_WIDTH_A  (16),              //positive integer
  .BYTE_WRITE_WIDTH_A (16),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (16),              //positive integer
  .READ_DATA_WIDTH_B  (16),              //positive integer
  .BYTE_WRITE_WIDTH_B (16),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_qp_mac_remote2_replica_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_mac_remote_addrm_bram_wen),
  .addra          (qp_mac_remote_addrm_bram_addr),
  .dina           (s_axi_lite_wdata[15:0]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (1'b0),
  .addrb          (i_qp_mac_remote_addrm_replica_idx[0+:C_QP_INDX_WIDTH]),
  .dinb           (16'b0),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_mac_remote_addrm_replica[15:0]),
  .sbiterrb       (),
  .dbiterrb       ()

);

// BRAM: QP IP DEST ADDR1 register
// [31:0]   - IP DEST ADDR LSB 1 VALUE

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (32*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (32),              //positive integer
  .READ_DATA_WIDTH_A  (32),              //positive integer
  .BYTE_WRITE_WIDTH_A (32),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (32),              //positive integer
  .READ_DATA_WIDTH_B  (32),              //positive integer
  .BYTE_WRITE_WIDTH_B (32),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_qp_ip_remote1_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_ip_remote_addr1_bram_wen),
  .addra          (qp_ip_remote_addr1_bram_addr),
  .dina           (s_axi_lite_wdata[31:0]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (s_axi_ip_remote_addr1_rdata),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (1'b0),
  .addrb          (muxed_qp_ip_remote_addr1_idx[0+:C_QP_INDX_WIDTH]),
  .dinb           ('b0),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_ip_remote_addr1[31:0]),
  .sbiterrb       (),
  .dbiterrb       ()

);

    assign muxed_qp_ip_remote_addr1_idx = i_qp_ip_remote_addr1_req ? i_qp_ip_remote_addr1_idx : i_qp_ip_remote_addr1_wqe_idx;
    assign qp_ip_remote_addr1_wr_addr = wr_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_ip_remote_addr1_rd_addr = rd_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_ip_remote_addr1_bram_addr =  qp_ip_remote_addr1_bram_wen ? qp_ip_remote_addr1_wr_addr : qp_ip_remote_addr1_rd_addr;
    assign qp_ip_remote_addr1_bram_wen  = (wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid) && ((wr_addr_r[7:0] == IP_REMOTE_ADDR1_QPN) &&  (wr_addr_r[16:9] != 'b0));

// REPLICA memory
// Some memories need to be replicated since IPG 0 implementation requires
// 2 parallel paths and hence needs independent access to some registers
// (without any delay). Any writes happen to both memories. Reads are
// independent
xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (32*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (32),              //positive integer
  .READ_DATA_WIDTH_A  (32),              //positive integer
  .BYTE_WRITE_WIDTH_A (32),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (32),              //positive integer
  .READ_DATA_WIDTH_B  (32),              //positive integer
  .BYTE_WRITE_WIDTH_B (32),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_qp_ip_remote1_replica_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_ip_remote_addr1_bram_wen),
  .addra          (qp_ip_remote_addr1_bram_addr),
  .dina           (s_axi_lite_wdata[31:0]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (1'b0),
  .addrb          (i_qp_ip_remote_addr1_replica_idx[0+:C_QP_INDX_WIDTH]),
  .dinb           ('b0),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_ip_remote_addr1_replica[31:0]),
  .sbiterrb       (),
  .dbiterrb       ()

);

// BRAM: STAT CURR SQ_PTR_PROC register
// [15:0]   - STAT_CURR_SQPTR_PROC - Read only

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (16*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (16),              //positive integer
  .READ_DATA_WIDTH_A  (16),              //positive integer
  .BYTE_WRITE_WIDTH_A (16),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("read_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (16),              //positive integer
  .READ_DATA_WIDTH_B  (16),              //positive integer
  .BYTE_WRITE_WIDTH_B (16),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("read_first")      //string; "write_first", "read_first", "no_change"

) inst_qp_curr_sqptr_proc_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (stat_curr_sqptr_bram_wen),
  .addra          (stat_curr_sqptr_proc_addr),
  .dina           (s_axi_lite_wdata[15:0]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (s_axi_curr_sqptr_proc_rdata[15:0]),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (i_qp_curr_sqptr_proc_wen),
  .addrb          (i_qp_curr_sqptr_proc_idx),
  .dinb           (i_qp_curr_sqptr_proc),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_curr_sqptr_proc),
  .sbiterrb       (),
  .dbiterrb       ()

);

    assign s_axi_curr_sqptr_proc_rdata[31:16]   = 'b0;

    // The AXI lite interface and the logic that updates the SQ full/empty
    // share the BRAM port A. BRAM port B is only dedicated for the QP manager
    assign curr_sqptr_proc = s_axi_curr_sqptr_proc_rdata[15:0];

    assign stat_curr_sqptr_proc_addr = (axi_curr_sqptr_proc_read | stat_curr_sqptr_bram_wen) ? stat_curr_sqptr_proc_bram_addr : pending_idx;
    assign stat_curr_sqptr_proc_wr_addr = wr_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign stat_curr_sqptr_proc_rd_addr = rd_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign stat_curr_sqptr_proc_bram_addr = stat_curr_sqptr_bram_wen ? stat_curr_sqptr_proc_wr_addr : stat_curr_sqptr_proc_rd_addr;
    assign axi_curr_sqptr_proc_read = ~generic_reg_rd_access & (rd_addr_r[7:0] == STAT_CURR_SQPTR_PROC_QPN) & ~s_axi_lite_rvalid;
    assign stat_curr_sqptr_bram_wen  = rdma_adv_conf_sw_override && (wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid) &&
                                        ((wr_addr_r[7:0] == STAT_CURR_SQPTR_PROC_QPN) &&  (wr_addr_r[16:9] != 'b0));

// BRAM: STAT MSN register
// [23:0]   - STAT CURR MSN

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (24*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (24),              //positive integer
  .READ_DATA_WIDTH_A  (24),              //positive integer
  .BYTE_WRITE_WIDTH_A (24),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (24),              //positive integer
  .READ_DATA_WIDTH_B  (24),              //positive integer
  .BYTE_WRITE_WIDTH_B (24),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_qp_stat_msn_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_stat_msn_bram_wen),
  .addra          (qp_stat_msn_bram_addr),
  .dina           (s_axi_lite_wdata[23:0]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (s_axi_stat_msn_rdata[23:0]),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (i_qp_stat_msn_wrn),
  .addrb          (i_qp_stat_msn_idx[0+:C_QP_INDX_WIDTH]),
  .dinb           (i_qp_stat_msn[23:0]),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_stat_msn),
  .sbiterrb       (),
  .dbiterrb       ()

);

    assign s_axi_stat_msn_rdata[31:24]   = 'b0;

    assign qp_stat_msn_rd_addr = rd_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_stat_msn_wr_addr = wr_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_stat_msn_bram_addr = qp_stat_msn_bram_wen ? qp_stat_msn_wr_addr :  qp_stat_msn_rd_addr; // READ ONLY REGISTER
    assign qp_stat_msn_bram_wen  = (wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid) &&
                                   (((wr_addr_r[7:0] == STAT_MSN_QPN) ) &&  (wr_addr_r[16:9] != 'b0));

////-----------------------------------------------------------------------------------------------------
// BRAM: STAT SSN register
// [23:0]   - STAT CURR SSN

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (24*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (24),              //positive integer
  .READ_DATA_WIDTH_A  (24),              //positive integer
  .BYTE_WRITE_WIDTH_A (24),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (24),              //positive integer
  .READ_DATA_WIDTH_B  (24),              //positive integer
  .BYTE_WRITE_WIDTH_B (24),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_qp_stat_ssn_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_stat_ssn_bram_wen),
  .addra          (qp_stat_ssn_bram_addr),
  .dina           (s_axi_lite_wdata[23:0]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (s_axi_stat_ssn_rdata[23:0]),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (i_qp_stat_ssn_wrn),
  .addrb          (i_qp_stat_ssn_idx[0+:C_QP_INDX_WIDTH]),
  .dinb           (i_qp_stat_ssn[23:0]),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_stat_ssn[23:0]),
  .sbiterrb       (),
  .dbiterrb       ()

);

    assign s_axi_stat_ssn_rdata[31:24]   = 'b0;

    assign qp_stat_ssn_wr_addr = wr_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_stat_ssn_rd_addr = rd_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_stat_ssn_bram_addr =  qp_stat_ssn_bram_wen ? qp_stat_ssn_wr_addr: qp_stat_ssn_rd_addr; // READ ONLY REGISTER
    assign qp_stat_ssn_bram_wen  = (wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid) &&
                                   (((wr_addr_r[7:0] == STAT_SSN_QPN) ) &&  (wr_addr_r[16:9] != 'b0));

// BRAM: QP STAT NAK register
// Bits in the QP stat register related to NAK are implemented in this BRAM
// Also include the twp fields of STAT_QPn register
// Implementing in 2 different BRAMs as Curr_retry_cnt is generated by
// resp_handler while the other bits are generated by rx_pkt_handler
// [26:24]  - CURR_RETRY_CNT (3 bits)
// [22:16]  - NAK_SYNDRM_RCVD (7 bits)
// [28:30]  - CURR_RNR_NAK_CNT (3 bits)

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (10*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (10),              //positive integer
  .READ_DATA_WIDTH_A  (10),              //positive integer
  .BYTE_WRITE_WIDTH_A (10),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (10),              //positive integer
  .READ_DATA_WIDTH_B  (10),              //positive integer
  .BYTE_WRITE_WIDTH_B (10),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_stat_psn_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_stat_nak_bram_wen),
  .addra          (qp_stat_nak_bram_addr),
  .dina           ({s_axi_lite_wdata[30:28], s_axi_lite_wdata[22:16]}),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          ({s_axi_stat_qpn_rdata[30:28], s_axi_stat_qpn_rdata[22:16]}),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (i_qp_stat_nak_wen),
  .addrb          (i_qp_stat_nak_idx),
  .dinb           (i_qp_stat_nak),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_stat_nak),
  .sbiterrb       (),
  .dbiterrb       ()

);

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (3*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (3),              //positive integer
  .READ_DATA_WIDTH_A  (3),              //positive integer
  .BYTE_WRITE_WIDTH_A (3),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (3),              //positive integer
  .READ_DATA_WIDTH_B  (3),              //positive integer
  .BYTE_WRITE_WIDTH_B (3),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_stat_retry_cnt_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_stat_nak_bram_wen),
  .addra          (qp_stat_nak_bram_addr),
  .dina           (s_axi_lite_wdata[26:24]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (s_axi_stat_qpn_rdata[26:24]),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (i_qp_stat_retry_cnt_wen),
  .addrb          (i_qp_stat_retry_cnt_idx),
  .dinb           (i_qp_stat_retry_cnt),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_stat_retry_cnt),
  .sbiterrb       (),
  .dbiterrb       ()

);

    assign s_axi_stat_qpn_rdata[0]    = i_qp_fatal_err[qp_stat_nak_bram_addr]; // bram address is the QP index
    assign s_axi_stat_qpn_rdata[1]    = i_rq_full[qp_stat_nak_bram_addr]; // bram address is the QP index
    assign s_axi_stat_qpn_rdata[2]    = sq_full_ff[qp_stat_nak_bram_addr]; // bram address is the QP index
    assign s_axi_stat_qpn_rdata[3]    = i_osq_full[qp_stat_nak_bram_addr]; // bram address is the QP index
    assign s_axi_stat_qpn_rdata[4]    = 1'b0;  //i_cq_full[qp_stat_nak_bram_addr]; // CQ full not implemented
    assign s_axi_stat_qpn_rdata[7:5]    = 'b0;
    assign s_axi_stat_qpn_rdata[8]    = 1'b0; //i_rq_empty[qp_stat_nak_bram_addr]; // RQ empty not getting generated
    assign s_axi_stat_qpn_rdata[9]    = sq_empty_ff[qp_stat_nak_bram_addr]; // bram address is the QP index
    assign s_axi_stat_qpn_rdata[10]   = i_osq_empty[qp_stat_nak_bram_addr]; // bram address is the QP index
    assign s_axi_stat_qpn_rdata[11]   = i_qp_retried[qp_stat_nak_bram_addr];
    assign s_axi_stat_qpn_rdata[15:12]   = 'b0;
    assign s_axi_stat_qpn_rdata[23]   = 'b0;
    assign s_axi_stat_qpn_rdata[27]   = 'b0;
    assign s_axi_stat_qpn_rdata[31]   = 'b0;
    assign qp_stat_nak_bram_addr = qp_stat_nak_bram_wen ? (wr_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1) : (rd_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1);
    assign qp_stat_nak_bram_wen  = (wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid) && ((wr_addr_r[7:0] == STAT_QPN) &&  (wr_addr_r[16:9] != 'b0));

// BRAM: STAT RESP PSN register
// [23:0]   - STAT_RESP_PSN - Read only

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (24*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (24),              //positive integer
  .READ_DATA_WIDTH_A  (24),              //positive integer
  .BYTE_WRITE_WIDTH_A (24),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (24),              //positive integer
  .READ_DATA_WIDTH_B  (24),              //positive integer
  .BYTE_WRITE_WIDTH_B (24),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_stat_resp_psn_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_sq_psn_bram_wen),
  .addra          (qp_sq_psn_bram_addr),
  .dina           ((s_axi_lite_wdata[23:0] - 1'b1)),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (s_axi_stat_resp_psn_rdata[23:0]),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (i_qp_stat_resp_psn_wen),
  .addrb          (i_qp_stat_resp_psn_idx),
  .dinb           (i_qp_stat_resp_psn),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_stat_resp_psn),
  .sbiterrb       (),
  .dbiterrb       ()

);

    assign s_axi_stat_resp_psn_rdata[31:24]   = 'b0;

// BRAM: STAT RQ BUF CA register
// [31:8]   - STAT_RQ_BUF_CA - Read only

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (24*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (24),              //positive integer
  .READ_DATA_WIDTH_A  (24),              //positive integer
  .BYTE_WRITE_WIDTH_A (24),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (24),              //positive integer
  .READ_DATA_WIDTH_B  (24),              //positive integer
  .BYTE_WRITE_WIDTH_B (24),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_rq_buf_ca_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_rq_ba_bram_wen),
  .addra          (qp_rq_ba_bram_addr),
  .dina           (s_axi_lite_wdata[31:8]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (s_axi_stat_rq_buf_ca_rdata[31:8]),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (i_qp_stat_rq_buf_ca_wen),
  .addrb          (i_qp_stat_rq_buf_ca_idx),
  .dinb           (i_qp_stat_rq_buf_ca),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_stat_rq_buf_ca),
  .sbiterrb       (),
  .dbiterrb       ()

);

    assign s_axi_stat_rq_buf_ca_rdata[7:0]   = 'b0;

// BRAM: STAT WQE register
// [15:0]   - WQE_CNT_POP - Read only

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (16*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (16),              //positive integer
  .READ_DATA_WIDTH_A  (16),              //positive integer
  .BYTE_WRITE_WIDTH_A (16),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (16),              //positive integer
  .READ_DATA_WIDTH_B  (16),              //positive integer
  .BYTE_WRITE_WIDTH_B (16),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_stat_wqe_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_wqe_cnt_bram_wen),
  .addra          (qp_wqe_cnt_bram_addr),
  .dina           (s_axi_lite_wdata[15:0]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (s_axi_stat_wqe_cnt_rdata[15:0]),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (i_qp_stat_wqe_cnt_wen),
  .addrb          (i_qp_stat_wqe_cnt_idx),
  .dinb           (i_qp_stat_wqe_cnt),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_stat_wqe_cnt),
  .sbiterrb       (),
  .dbiterrb       ()
);
    assign s_axi_stat_wqe_cnt_rdata[31:16]   = 'b0;
    assign qp_wqe_cnt_bram_addr = qp_wqe_cnt_bram_wen ? (wr_addr_r[8+:C_QP_INDX_WIDTH]-8'h1) : (rd_addr_r[8+:C_QP_INDX_WIDTH]-8'h1);
    assign qp_wqe_cnt_bram_wen  = rdma_adv_conf_sw_override & (wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid) &&
                                   (((wr_addr_r[7:0] == STAT_WQE_CNT) ) &&  (wr_addr_r[16:9] != 'b0));
// BRAM: STAT RQ_PI_DB register
// [15:0]   - RQ_PI - Read only

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (16*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (16),              //positive integer
  .READ_DATA_WIDTH_A  (16),              //positive integer
  .BYTE_WRITE_WIDTH_A (16),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (16),              //positive integer
  .READ_DATA_WIDTH_B  (16),              //positive integer
  .BYTE_WRITE_WIDTH_B (16),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_stat_rq_pi_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (qp_stat_rq_pi_db_bram_wen),
  .addra          (qp_stat_rq_pi_db_bram_addr),
  .dina           (s_axi_lite_wdata[15:0]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (s_axi_stat_rq_pi_db_rdata[15:0]),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (i_qp_rq_pi_db_wrn),
  .addrb          (i_qp_rq_pi_db_idx),
  .dinb           (i_qp_rq_pi_db),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_rq_pi_db),
  .sbiterrb       (),
  .dbiterrb       ()
);

    assign s_axi_stat_rq_pi_db_rdata[31:16]   = 'b0;
    assign qp_stat_rq_pi_db_wr_addr = wr_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_stat_rq_pi_db_rd_addr = rd_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    // This is to support connect on IO command. After the connect IO SW
    // updates are over there may be some residual RQ doorbell for NVmf. They
    // need to be transmitted to NVMf. This is done using the cnct_io_conf
    assign qp_stat_rq_pi_db_bram_addr =  axi_lite_access_to_rqpidb_reg ?
                                         (qp_stat_rq_pi_db_bram_wen ? qp_stat_rq_pi_db_wr_addr: qp_stat_rq_pi_db_rd_addr) : connect_io_qpid[0+:C_QP_INDX_WIDTH]; // READ ONLY REGISTER
    assign qp_stat_rq_pi_db_bram_wen  = rdma_adv_conf_sw_override & (wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid) &&
                                   (((wr_addr_r[7:0] == STAT_RQ_PI_DB) ) &&  (wr_addr_r[16:9] != 'b0));

    assign axi_lite_access_to_rqpidb_reg = (wr_addr_r[7:0] == STAT_RQ_PI_DB) || (rd_addr_r[7:0] == STAT_RQ_PI_DB);

    assign o_rq_pi_db_hw_hndshk = s_axi_stat_rq_pi_db_rdata[15:0];

// BRAM: STAT RET_SQ_PSN register
// [23:0]   - RETRIED_SQ_PSN - Read only

xpm_memory_tdpram # (

  // Common module parameters
  .MEMORY_SIZE        (24*C_NUM_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("independent_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (24),              //positive integer
  .READ_DATA_WIDTH_A  (24),              //positive integer
  .BYTE_WRITE_WIDTH_A (24),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_A ("0"),             //string
  .READ_LATENCY_A     (1),               //non-negative integer
  .WRITE_MODE_A       ("write_first"),     //string; "write_first", "read_first", "no_change"

  // Port B module parameters
  .WRITE_DATA_WIDTH_B (24),              //positive integer
  .READ_DATA_WIDTH_B  (24),              //positive integer
  .BYTE_WRITE_WIDTH_B (24),              //integer; 8, 9, or WRITE_DATA_WIDTH_B value
  .ADDR_WIDTH_B       (C_QP_INDX_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //vector of READ_DATA_WIDTH_B bits
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("write_first")      //string; "write_first", "read_first", "no_change"

) inst_stat_ret_sq_psn_regs (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (s_axi_lite_aclk),
  .rsta           (~s_axi_lite_aresetn),
  .ena            (1'b1),
  .regcea         (1'b1),
  .wea            (1'b0),
  .addra          (qp_stat_ret_sq_psn_bram_addr),
  .dina           (s_axi_lite_wdata[23:0]),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),
  .douta          (s_axi_stat_ret_sq_psn_rdata[23:0]),
  .sbiterra       (),
  .dbiterra       (),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .web            (i_qp_ret_sq_psn_wrn),
  .addrb          (i_qp_ret_sq_psn_idx),
  .dinb           (i_qp_ret_sq_psn),
  .injectsbiterrb (1'b0),
  .injectdbiterrb (1'b0),
  .doutb          (o_qp_ret_sq_psn),
  .sbiterrb       (),
  .dbiterrb       ()
);

    assign s_axi_stat_ret_sq_psn_rdata[31:24]   = 'b0;
    assign qp_stat_ret_sq_psn_rd_addr = rd_addr_r[8+:C_QP_INDX_WIDTH] - 8'h1;
    assign qp_stat_ret_sq_psn_bram_addr =  qp_stat_ret_sq_psn_rd_addr;

// Generating SEND Q full/empty/available_to_process signals
// Whenever the SQ_PI_DB or the STAT_CURR_SQPTR_PROC is updated, the
// full/empty/available_to_process signals change
// since both these process occur asynchronously and can come at the same
// time, the following method for updating the empty/full signals is used.
// Everytime such a write happens, a pending signal is set. Once the fifo
// empty/full signal is updated, it is reset

generate
    for (i=0; i<C_NUM_QP; i= i+1) begin: pend_upd_gen
        assign pending_update[i] = (((i[C_QP_INDX_WIDTH -1 :0]==qp_sq_pidb_wr_addr) & qp_sq_pidb_bram_wen & rdma_conf_rdma_en) ||             // Either the SQ pI DB is written to OR
                                    ((i[C_QP_INDX_WIDTH -1 :0]==qp_sq_pidb_hndshk_addr[C_QP_INDX_WIDTH -1:0]) & i_qp_sq_pidb_wr_valid_hndshk) ||
                                    ((i[C_QP_INDX_WIDTH -1 :0]==i_qp_curr_sqptr_proc_idx) & i_qp_curr_sqptr_proc_wen) ||
                                    ((i[C_QP_INDX_WIDTH -1 :0]==stat_curr_sqptr_proc_addr) & stat_curr_sqptr_bram_wen) ||
                                    ((i[C_QP_INDX_WIDTH -1 :0]==qp_sq_pidb_bram_addr) & qp_sq_pidb_bram_wen) ||
                                    ((i[C_QP_INDX_WIDTH -1 :0]==i_status_upd_indx) & i_status_upd_needed)) ? 1'b1:  // curr_sqptr_proc is written to
                                    ((clear_pend_stat_masked && (i[C_QP_INDX_WIDTH -1 :0]==(pending_idx))) ? 1'b0 : pending_update_ff[i]); // else clear is pending stat completed
end
endgenerate

`MSFF_R(pending_update_ff, pending_update, core_clk, ~core_rstn)
`MSFF_R(sq_pidb_bram_wen_ff, qp_sq_pidb_bram_wen, core_clk, ~core_rstn)

// Need to handle a scenario where the write to a particular SQ_PIDB occurs
// when (in the next cycle) the clear for that QP is being generated. Then the
// pidb can get lost. It is ok to lose this when there are more requests
// coming. However, if that is the last request on the QP, this will lead to
// particular request never being scheduled since the QP_EMPTY will be
// asserted for that QP. The masking logic takes care of that.
assign clear_pend_stat_masked = clear_pend_stat & ~sq_pidb_bram_wen_ff;

generate
    for (j=0; j<C_NUM_QP; j= j+1) begin : empty_full_gen
        `MSFF_RL(sq_empty_ff[j], ((pending_upd_cs == UPDATE_PEND_STAT & (pending_idx == j)) ? sq_empty : sq_empty_ff[j]) , core_clk, ~core_rstn, 1'b1) // load init value of 1
        `MSFF_R(sq_full_ff[j],  ((pending_upd_cs == UPDATE_PEND_STAT & (pending_idx == j)) ? sq_full  : sq_full_ff[j]) , core_clk, ~core_rstn)
    end
endgenerate

assign pending_idx = C_NUM_QP >=8 ? (msb_cnt*QP_CHUNK + lsb_cnt) : (msb_cnt);

assign sq_empty = (sq_pidb == curr_sqptr_proc) ? 1'b1 : 1'b0;
assign sq_full =  (sq_pidb[C_QP_INDX_WIDTH] != curr_sqptr_proc[C_QP_INDX_WIDTH]) && (sq_pidb[C_QP_INDX_WIDTH -1:0] == curr_sqptr_proc[C_QP_INDX_WIDTH-1:0]);

assign o_sq_full = sq_full_ff;
assign o_sq_empty = sq_empty_ff;

always @(*)
begin
    pending_upd_ns <= pending_upd_cs;
    clear_pend_stat <= 1'b0;
    case (pending_upd_cs)

        IDLE:
        begin
            if (|pending_update_ff) begin
                pending_upd_ns <= FIND_PEND_UPD; // Find the SQ that needs full/empty update
            end
        end

        FIND_PEND_UPD:
        begin
            if (C_NUM_QP >= 8) begin
                if (pending_update_ff[msb_cnt*QP_CHUNK + lsb_cnt])
                    pending_upd_ns <= WAIT_BRAM;
                else if (jump[msb_cnt])
                    pending_upd_ns <= INCR_MSB_CNT;
                else
                    pending_upd_ns <= INCR_LSB_CNT;
            end else begin
                if (pending_update_ff[msb_cnt])
                    pending_upd_ns <= WAIT_BRAM;
                else
                    pending_upd_ns <= INCR_MSB_CNT;
            end
        end

        WAIT_BRAM:
        begin
            if (~(axi_curr_sqptr_proc_read | stat_curr_sqptr_bram_wen))
            pending_upd_ns <= UPDATE_PEND_STAT;
        end

        UPDATE_PEND_STAT:
        begin
            if (~(i_qp_sq_pidb_req | qp_sq_pidb_req_ff | i_qp_sq_pidb_wr_valid_hndshk | qp_sq_pidb_req_hndshk_ff)) begin
                clear_pend_stat <= 1'b1;
                pending_upd_ns <= IDLE;
            end
        end

        INCR_MSB_CNT:
        begin
            if (|pending_update_ff)
                pending_upd_ns <= FIND_PEND_UPD;
            else
                pending_upd_ns <= IDLE;
        end

        INCR_LSB_CNT:
        begin
            if (|pending_update_ff)
                pending_upd_ns <= FIND_PEND_UPD;
            else
                pending_upd_ns <= IDLE;
        end

    endcase
end

genvar k;
generate
for (k=0; k<8; k=k+1)
begin : loop1
    assign jump[k] = (C_NUM_QP >= 8) ? (~(|pending_update[k*QP_CHUNK +: QP_CHUNK]) ? 1'b1 : 1'b0) : 1'b1;
end
endgenerate

generate
for (k=0; k<C_NUM_QP; k=k+1)
 begin: qp_fatal_clr_gen
    assign o_qp_clr_fatal_err[k] = (qp_conf_bram_wen & ~s_axi_lite_wdata[0]) && (k == qp_conf_wr_addr);
 end
endgenerate

generate

if (C_EN_DEBUG_REGS == 1) begin
//----Performance debug counters logic-------------------------------//
//   global_dbg_cnt[0]  --> RWSC, Enable All Counters
//   global_dbg_cnt[1]  --> RW, Clear All Counters
//   global_dbg_cnt[15:2]-->RW, Reserved Bits
//   global_dbg_cnt[31:16] -->RW, Global Count value
//                         -- 0, counters are enabled all the time
//                         -- N(non-zero), Counters are enabled for only N clocks

always @(posedge s_axi_lite_aclk)
begin
	if(~s_axi_lite_aresetn) begin
		global_dbg_cnt[31:0]	<=	32'h1;
	end else if(wr_req_r && s_axi_lite_wvalid && ~s_axi_lite_bvalid & generic_reg_wr_access & (wr_addr_r[9:2] == GLOBAL_DBG_CNTR[9:2])) begin
		global_dbg_cnt[31:0]	<=	s_axi_lite_wdata[31:0];
	end else if((|global_dbg_cnt[31:16]) && (int_cnt_value == (global_dbg_cnt[31:16] - 1'b1))) begin
		global_dbg_cnt[0]	<=	1'b0;  //This bit will be self cleared after global_dbg_cnt[31:16] of axi_lite_aclk's
	end
end

`MSFF_R(int_cnt_value, (global_dbg_cnt[0] ? int_cnt_value + 1 : 0), core_clk, ~core_rstn)

assign sqe_backpressure_cnt	= global_dbg_cnt[0] ? ((|(~sq_empty_ff & ~i_osq_almost_full) & i_qp_mgr_sts[1]) ?
							sqe_backpressure_cnt_ff + 1 : sqe_backpressure_cnt_ff)
						 : sqe_backpressure_cnt_ff;
assign osq_backpressure_cnt	= global_dbg_cnt[0] ? (|(~sq_empty_ff & i_osq_almost_full) ?
							osq_backpressure_cnt_ff + 1 : osq_backpressure_cnt_ff)
						 : osq_backpressure_cnt_ff;

assign all_sqes_empty_cnt	= global_dbg_cnt[0] ? ((&sq_empty_ff) ? all_sqes_empty_cnt_ff + 1 : all_sqes_empty_cnt_ff) : all_sqes_empty_cnt_ff;

end

else begin

always @(*) global_dbg_cnt = 32'h0;
assign  sqe_backpressure_cnt = 16'h0;
assign  osq_backpressure_cnt = 16'h0;
assign  all_sqes_empty_cnt   = 16'h0;

end
endgenerate

`MSFF_R(msb_cnt, (pending_upd_cs == INCR_MSB_CNT ? msb_cnt +1'b1  : msb_cnt) , core_clk, ~core_rstn)
`MSFF_R(lsb_cnt, (pending_upd_cs == INCR_LSB_CNT ? lsb_cnt +1'b1  : lsb_cnt) , core_clk, ~core_rstn)

`MSFF_RL(pending_upd_cs, pending_upd_ns , core_clk, ~core_rstn, 3'b000)

//---------------- ADDED for DEBUG can be removed later ------------------------
`MSFF_RL(rdma_adv_conf_sw_override_ff, rdma_adv_conf_sw_override , core_clk, ~core_rstn, 3'b000)
assign posedge_rdma_sw_override = ~rdma_adv_conf_sw_override_ff & rdma_adv_conf_sw_override;
`MSFF_RL(rdma_sw_override_cnt, (posedge_rdma_sw_override ? (rdma_sw_override_cnt + 1'b1) : rdma_sw_override_cnt) , core_clk, ~core_rstn, 3'b000)

assign o_dbg_cnt_override = rdma_sw_override_cnt;

`MSFF_R(hw_hndshk_disable_to_0, (qp_conf_bram_wen & ~s_axi_lite_wdata[4]), core_clk, ~core_rstn)

`MSFF_R(qp_conf_req_rx_pkt_ff           , i_qp_conf_req_rx_pkt          , core_clk, ~core_rstn)
`MSFF_R(qp_conf_req_replica_ff          , i_qp_conf_replica_req         , core_clk, ~core_rstn)
`MSFF_R(qp_conf_req_wqe_proc_ff         , i_qp_conf_req_wqe_proc & ~i_qp_conf_req_rx_pkt     , core_clk, ~core_rstn)
`MSFF_R(qp_conf_req_resp_hndl_ff        , (i_qp_conf_req_resp_hndl & ~i_qp_conf_req_rx_pkt & ~i_qp_conf_req_wqe_proc) , core_clk, ~core_rstn)
`MSFF_R(qp_adv_conf_req_ff              , i_qp_adv_conf_req             , core_clk, ~core_rstn)
`MSFF_R(qp_rq_pi_db_req_ff              , i_qp_rq_pi_db_req             , core_clk, ~core_rstn)
`MSFF_R(qp_ret_sq_psn_req_ff            , i_qp_ret_sq_psn_req           , core_clk, ~core_rstn)
`MSFF_R(qp_ret_sq_psn_req_int_ff        , i_qp_ret_sq_psn_wrn & ~i_qp_ret_sq_psn_req , core_clk, ~core_rstn)
`MSFF_R(qp_rq_ba_req_ff                 , i_qp_rq_ba_req                , core_clk, ~core_rstn)
`MSFF_R(qp_sq_ba_req_ff                 , i_qp_sq_ba_req                , core_clk, ~core_rstn)
`MSFF_R(qp_sq_ba_req_int_ff             , (i_qp_sq_ba_req_int & ~i_qp_sq_ba_req) , core_clk, ~core_rstn)
`MSFF_R(qp_cq_ba_req_ff                 , i_qp_cq_ba_req                , core_clk, ~core_rstn)
`MSFF_R(qp_rq_wrptrdb_req_ff            , i_qp_rq_wrptrdb_add_req       , core_clk, ~core_rstn)
`MSFF_R(qp_sq_cmpldb_req_ff             , i_qp_sq_cmpldb_add_req        , core_clk, ~core_rstn)
`MSFF_R(qp_cq_hdptr_req_ff              , (i_qp_cq_hdptr_req & ~i_qp_cq_hdptr_retry_req) , core_clk, ~core_rstn)
`MSFF_R(qp_cq_hdptr_retry_req_ff        , i_qp_cq_hdptr_retry_req       , core_clk, ~core_rstn)
`MSFF_R(qp_rq_cidb_req_ff               , i_qp_rq_cidb_req              , core_clk, ~core_rstn)
`MSFF_R(qp_rq_cidb_req_hndshk_ff        , i_qp_rq_cidb_wr_valid_hndshk & ~i_qp_rq_cidb_req, core_clk, ~core_rstn)
`MSFF_R(qp_sq_pidb_req_ff               , i_qp_sq_pidb_req              , core_clk, ~core_rstn)
`MSFF_R(qp_sq_pidb_req_hndshk_ff        , i_qp_sq_pidb_wr_valid_hndshk & ~i_qp_sq_pidb_req, core_clk, ~core_rstn)
`MSFF_R(qp_rq_depth_req_ff              , i_qp_rq_depth_req             , core_clk, ~core_rstn)
`MSFF_R(qp_sq_depth_req_ff              , (i_qp_sq_depth_req & ~i_qp_cq_depth_req) , core_clk, ~core_rstn)
`MSFF_R(qp_sq_psn_req_ff                , i_qp_sq_psn_req               , core_clk, ~core_rstn)
`MSFF_R(qp_sq_psn_wqe_req_ff            , (i_qp_sq_psn_wqe_req & ~i_qp_sq_psn_req) , core_clk, ~core_rstn)
`MSFF_R(qp_sq_psn_retry_req_ff          , (i_qp_sq_psn_retry_req & ~i_qp_sq_psn_req) , core_clk, ~core_rstn)
`MSFF_R(qp_last_rq_req_ff               , i_qp_last_rq_req              , core_clk, ~core_rstn)
`MSFF_R(qp_dest_qpid_req_wqe_proc_ff    , i_qp_dest_qpid_req_wqe_proc   , core_clk, ~core_rstn)
`MSFF_R(qp_dest_qpid_req_rx_pkt_ff      , i_qp_dest_qpid_req_rx_pkt     , core_clk, ~core_rstn)
`MSFF_R(qp_mac_remote_addrl_req_ff      , i_qp_mac_remote_addrl_req     , core_clk, ~core_rstn)
`MSFF_R(qp_mac_remote_addrl_req_replica_ff , i_qp_mac_remote_addrl_replica_req , core_clk, ~core_rstn)
`MSFF_R(qp_mac_remote_addrm_req_ff      , i_qp_mac_remote_addrm_req     , core_clk, ~core_rstn)
`MSFF_R(qp_mac_remote_addrm_req_replica_ff , i_qp_mac_remote_addrm_replica_req     , core_clk, ~core_rstn)
`MSFF_R(qp_mac_remote_addrl_wqe_req_ff  , (i_qp_mac_remote_addrl_wqe_req & ~i_qp_mac_remote_addrl_req), core_clk, ~core_rstn)
`MSFF_R(qp_mac_remote_addrm_wqe_req_ff  , (i_qp_mac_remote_addrm_wqe_req & ~i_qp_mac_remote_addrm_req), core_clk, ~core_rstn)
`MSFF_R(qp_ip_remote_addr1_req_ff       , i_qp_ip_remote_addr1_req      , core_clk, ~core_rstn)
`MSFF_R(qp_ip_remote_addr1_req_replica_ff , i_qp_ip_remote_addr1_replica_req      , core_clk, ~core_rstn)
`MSFF_R(qp_ip_remote_addr1_wqe_req_ff   , (i_qp_ip_remote_addr1_wqe_req & ~i_qp_ip_remote_addr1_req) , core_clk, ~core_rstn)
`MSFF_R(qp_curr_sqptr_req_ff            , i_qp_curr_sqptr_rdreq         , core_clk, ~core_rstn)
`MSFF_R(qp_stat_resp_psn_req_ff         , i_qp_stat_resp_psn_rdreq      , core_clk, ~core_rstn)
`MSFF_R(qp_stat_msn_req_ff              , i_qp_stat_msn_req             , core_clk, ~core_rstn)
`MSFF_R(qp_stat_ssn_req_ff              , i_qp_stat_ssn_req             , core_clk, ~core_rstn)
`MSFF_R(qp_stat_nak_req_ff              , i_qp_stat_nak_rdreq           , core_clk, ~core_rstn)
`MSFF_R(qp_stat_rq_buf_ca_rdreq_ff      , i_qp_stat_rq_buf_ca_rdreq     , core_clk, ~core_rstn)
`MSFF_R(qp_stat_wqe_cnt_rdreq_ff        , i_qp_stat_wqe_cnt_rdreq       , core_clk, ~core_rstn)
`MSFF_R(qp_rq_wrptrdb_add_req_ff        , i_qp_rq_wrptrdb_add_req       , core_clk, ~core_rstn)
`MSFF_R(qp_sq_cmpldb_add_req_ff         , i_qp_sq_cmpldb_add_req        , core_clk, ~core_rstn)

`MSFF_R(qp_cq_depth_req_ff              , i_qp_cq_depth_req, core_clk, ~core_rstn)

//----Performance debug counters FF stages-------------------------------//
`MSFF_R(sqe_backpressure_cnt_ff		,(global_dbg_cnt[1] ? 15'h0 : sqe_backpressure_cnt)	, core_clk, ~core_rstn )
`MSFF_R(osq_backpressure_cnt_ff		,(global_dbg_cnt[1] ? 15'h0 : osq_backpressure_cnt)	, core_clk, ~core_rstn )
`MSFF_R(all_sqes_empty_cnt_ff		,(global_dbg_cnt[1] ? 15'h0 : all_sqes_empty_cnt)	, core_clk, ~core_rstn )

 assign o_qp_sq_cmpldb_add_valid        = qp_sq_cmpldb_add_req_ff;
 assign o_qp_rq_wrptrdb_add_valid       = qp_rq_wrptrdb_add_req_ff ;
 assign o_qp_cq_hdptr_valid             = qp_cq_hdptr_req_ff       ;
 assign o_qp_cq_hdptr_valid_retry       = qp_cq_hdptr_retry_req_ff       ;
 assign o_qp_conf_valid_wqe_proc        = qp_conf_req_wqe_proc_ff  ;
 assign o_qp_conf_valid_resp_hndl       = qp_conf_req_resp_hndl_ff ;
 assign o_qp_conf_valid_rx_pkt          = qp_conf_req_rx_pkt_ff    ;
 assign o_qp_conf_replica_valid         = qp_conf_req_replica_ff    ;
 assign o_qp_adv_conf_valid             = qp_adv_conf_req_ff       ;
 assign o_qp_rq_pi_db_valid             = qp_rq_pi_db_req_ff       ;
 assign o_qp_ret_sq_psn_valid           = qp_ret_sq_psn_req_ff       ;
 assign o_qp_ret_sq_psn_valid_int       = qp_ret_sq_psn_req_int_ff       ;
 assign o_qp_rq_ba_valid                = qp_rq_ba_req_ff          ;
 assign o_qp_sq_ba_valid                = qp_sq_ba_req_ff          ;
 assign o_qp_sq_ba_valid_int            = qp_sq_ba_req_int_ff          ;
 assign o_qp_cq_ba_valid                = qp_cq_ba_req_ff          ;
 assign o_qp_rq_wrptrdb_valid           = qp_rq_wrptrdb_req_ff     ;
 assign o_qp_sq_cmpldb_valid            = qp_sq_cmpldb_req_ff      ;
 assign o_qp_rq_cidb_valid              = qp_rq_cidb_req_ff        ;
 assign o_qp_rq_cidb_wr_rdy             = qp_rq_cidb_req_hndshk_ff ;
 assign o_qp_sq_pidb_valid              = qp_sq_pidb_req_ff        ;
 assign o_qp_sq_pidb_wr_rdy             = qp_sq_pidb_req_hndshk_ff & i_qp_sq_pidb_wr_valid_hndshk ;
 assign o_qp_rq_depth_valid             = qp_rq_depth_req_ff       ;
 assign o_qp_sq_depth_valid             = qp_sq_depth_req_ff       ;
 assign o_qp_cq_depth_valid             = qp_cq_depth_req_ff       ;
 assign o_qp_sq_psn_valid               = qp_sq_psn_req_ff         ;
 assign o_qp_sq_psn_wqe_valid           = qp_sq_psn_wqe_req_ff     ;
 assign o_qp_sq_psn_retry_valid         = qp_sq_psn_retry_req_ff & ~i_qp_sq_psn_req ;
 assign o_qp_last_rq_valid              = qp_last_rq_req_ff        ;
 assign o_qp_dest_qpid_valid_wqe_proc   = qp_dest_qpid_req_wqe_proc_ff;
 assign o_qp_dest_qpid_valid_rx_pkt     = qp_dest_qpid_req_rx_pkt_ff  ;
 assign o_qp_mac_remote_addrl_valid       = qp_mac_remote_addrl_req_ff ;
 assign o_qp_mac_remote_addrl_replica_valid = qp_mac_remote_addrl_req_replica_ff ;
 assign o_qp_mac_remote_addrm_valid       = qp_mac_remote_addrm_req_ff ;
 assign o_qp_mac_remote_addrm_replica_valid = qp_mac_remote_addrm_req_replica_ff ;
 assign o_qp_mac_remote_addrl_wqe_valid   = qp_mac_remote_addrl_wqe_req_ff ;
 assign o_qp_mac_remote_addrm_wqe_valid   = qp_mac_remote_addrm_wqe_req_ff ;
 assign o_qp_ip_remote_addr1_valid        = qp_ip_remote_addr1_req_ff  ;
 assign o_qp_ip_remote_addr1_replica_valid = qp_ip_remote_addr1_req_replica_ff  ;
 assign o_qp_curr_sqptr_proc_valid      = qp_curr_sqptr_req_ff     ;
 assign o_qp_stat_resp_psn_valid        = qp_stat_resp_psn_req_ff     ;
 assign o_qp_stat_rq_buf_ca_valid       = qp_stat_nak_req_ff     ;
 assign o_qp_stat_nak_valid             = qp_stat_rq_buf_ca_rdreq_ff     ;
 assign o_qp_stat_wqe_cnt_valid             = qp_stat_wqe_cnt_rdreq_ff     ;
 assign o_qp_stat_msn_valid             = qp_stat_msn_req_ff       ;
 assign o_qp_stat_ssn_valid             = qp_stat_ssn_req_ff       ;

 assign o_rdma_en = rdma_conf_rdma_en;
 assign o_tx_ack_gen = rdma_conf_tx_ack_gen;
 assign o_err_buf_en = rdma_conf_err_buf_en;
 assign o_flow_credits = rdma_conf_flow_credits;
 assign o_depkt_bypass_en = rdma_conf_depkt_bypass_en;
 assign o_num_qp_en = rdma_conf_num_qps_enabled;
 assign o_rdma_udp_src_port = rdma_conf_udp_src_port;
 assign o_ipv4_rdma_addr = ipv4_rdma_addr;
 assign o_ipv6_rdma_addr = {ipv6_rdma_addr4, ipv6_rdma_addr3, ipv6_rdma_addr2, ipv6_rdma_addr1};
 assign o_mac_rdma_addr = {mac_rdma_addr_msb, mac_rdma_addr_lsb};
 assign o_timeoutreg = {11'b0,rnr_nack_tval,2'b0, rnr_retry_cnt ,retry_cnt,3'b0,timeout};

 assign o_bypass_buf_ba = bypass_buf_ba;
 assign o_bypass_buf_sz_num_bufs = bypass_buf_sz_num_bufs;
 assign o_bypass_buf_sz_buf_sz = bypass_buf_sz_buf_sz;

 assign o_data_buf_ba = data_buf_ba;
 assign o_data_buf_sz_num_bufs = data_buf_sz_num_bufs;
 assign o_data_buf_sz_buf_sz = data_buf_sz_buf_sz;

 assign o_connect_io_qp_rq_pi_db_wptr = connect_io_qp_rq_pi_db_wptr;
 assign o_connect_io_qpid = connect_io_qpid;
 assign o_hw_hndshk_disable_to_0 = hw_hndshk_disable_to_0 & rdma_adv_conf_sw_override;

 assign o_rq_err_pkt_buf_ba = rq_err_pkt_buf_ba;
 assign o_rq_err_pkt_buf_sz_num_bufs = rq_err_pkt_buf_sz_num_bufs;
 assign o_rq_err_pkt_buf_sz_buf_sz = rq_err_pkt_buf_sz_buf_sz;

 assign o_resp_err_pkt_buf_ba = resp_err_pkt_buf_ba;
 assign o_resp_err_pkt_buf_sz_num_bufs = resp_err_pkt_buf_sz_num_bufs;
 assign o_resp_err_pkt_buf_sz_buf_sz = resp_err_pkt_buf_sz_buf_sz;

 assign o_tx_hdr_buf_ba = tx_hdr_buf_ba;
 assign o_tx_hdr_buf_sz_num_hdrs = tx_hdr_buf_sz_num_hdrs;
 assign o_tx_hdr_buf_sz_buf_sz = tx_hdr_buf_sz_buf_sz;

 assign o_tx_sgl_buf_ba = tx_sgl_buf_ba;
 assign o_tx_sgl_buf_sz_num_sgls = tx_sgl_buf_sz_num_sgls;
 assign o_tx_sgl_buf_sz_buf_sz = tx_sgl_buf_sz_buf_sz;

 assign o_rdma_conf_ipver = rdma_conf_ipver;
 assign o_rdma_adv_conf_sw_override = rdma_adv_conf_sw_override;
 assign o_rdma_adv_conf_errbuf_overwr_en = rdma_adv_conf_errbuf_overwr_en;
 assign o_rdma_adv_base_cnt    = rdma_adv_base_cnt;

 // HW Doorbell WQE template outputs
 assign o_hw_wqe_remote_addr_lo = hw_wqe_remote_addr_lo;
 assign o_hw_wqe_remote_addr_hi = hw_wqe_remote_addr_hi;
 assign o_hw_wqe_rkey           = hw_wqe_rkey;
 assign o_hw_wqe_local_addr     = hw_wqe_local_addr;
 assign o_hw_wqe_opcode         = hw_wqe_opcode;
 assign o_hw_wqe_wrid           = hw_wqe_wrid;

 assign o_intr_en_pkt_valdn_err      = intr_en_pkt_valdn_err;
 assign o_intr_en_wqe_cmpl           = intr_en_wqe_cmpl;
 assign o_intr_en_mad_pkt_rcvd       = intr_en_mad_pkt_rcvd;
 assign o_intr_en_bypass_pkt_rcvd    = intr_en_bypass_pkt_rcvd;
 assign o_intr_en_rnr_nak_gen        = intr_en_rnr_nak_gen;
 assign o_intr_en_ill_opc_in_sq      = intr_en_ill_opc_in_sq;
 assign o_intr_en_fatal_err          = intr_en_fatal_err;
 assign o_intr_en_qp_pkt_rcvd        = intr_en_qp_pkt_rcvd;

assign o_out_errsts_q_ba = out_errsts_q_ba;
assign o_out_errsts_q_sz = out_errsts_q_sz;

assign o_in_errsts_q_ba = in_errsts_q_ba;
assign o_in_errsts_q_sz = in_errsts_q_sz;

assign o_rx_pkt_hndl_dbg_ctrl = rx_pkt_hndl_dbg_ctrl;

assign o_global_dbg_cnt_value = global_dbg_cnt[31:16];
assign o_global_dbg_cnt_clr   = global_dbg_cnt[1];
assign o_global_dbg_cnt_en    = global_dbg_cnt[0];
assign o_dbg_bram_raddr	      = rd_addr_r[13:4];

// Non-synthesizable code

  `ifdef SIMULATION
    reg [20*8-1:0] pending_upd_ns_string = "null";
    reg [20*8-1:0] pending_upd_cs_string = "null";

    always @* begin
      case (pending_upd_cs)
         IDLE             : pending_upd_cs_string = "IDLE            " ;
         FIND_PEND_UPD    : pending_upd_cs_string = "FIND_PEND_UPD   ";
         WAIT_BRAM        : pending_upd_cs_string = "WAIT_BRAM       "      ;
         INCR_LSB_CNT     : pending_upd_cs_string = "INCR_LSB_CNT        " ;
         INCR_MSB_CNT     : pending_upd_cs_string = "INCR_MSB_CNT        " ;
         UPDATE_PEND_STAT : pending_upd_cs_string = "UPDATE_PEND_STAT" ;
      endcase
      case (pending_upd_ns)
         IDLE             : pending_upd_ns_string = "IDLE            " ;
         FIND_PEND_UPD    : pending_upd_ns_string = "FIND_PEND_UPD   ";
         WAIT_BRAM        : pending_upd_ns_string = "WAIT_BRAM       "      ;
         INCR_LSB_CNT     : pending_upd_ns_string = "INCR_LSB_CNT        " ;
         INCR_MSB_CNT     : pending_upd_ns_string = "INCR_MSB_CNT        " ;
         UPDATE_PEND_STAT : pending_upd_ns_string = "UPDATE_PEND_STAT" ;
      endcase
    end
  `endif

endmodule

