// resp_handler_top.v
// 文件名          : resp_handler_top.v
// 版本            : v1.0
// 描述            : 响应处理顶层模块，处理 RX 包处理器发来的 ACK/NAK
//                   包含 OSQ 仲裁、响应 FSM、重传定时器子模块
// Verilog 标准    : Verilog'2001

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
`timescale 1ps/1ps

(* DowngradeIPIdentifiedWarnings="yes" *)
module resp_handler_top
#(
    parameter   C_M_AXI_ADDR_WIDTH      = 32,
    parameter   C_NUM_QP                = 256,
    parameter   C_QP_INDX_WIDTH         = 8,
    parameter   C_OS_Q_DEPTH            = 8,
    parameter   C_OS_Q_INDX_WIDTH       = 3,
    parameter   C_EN_NVMOF_HW_HNDSHK    = 0,  // Enabled hardware handshake with NVMoF
    parameter   C_NUM_CYCLES_4US        = 512, // Number of clock cycles that make 4 us (for 125Mhz clk period it is 512)
    parameter   STB_WIDTH               = 4,
    parameter   C_OSQ_PSN_WIDTH		= 8,
    parameter   C_EN_WR_RETRY_DATA_BUF          = 1,
    parameter   RESP_WIDTH              = 2
)
(
  input  wire				     core_clk,
  input  wire				     core_rstn,	    // Active low core reset

  input  wire [C_QP_INDX_WIDTH-1:0]          i_wqe_qpid,                      // QP ID of WQE
  input  wire [ 7:0]                         i_wqe_opcode,                    // BTH.Opcode of outbound request
  input  wire [15:0]                         i_wqe_wrid,
  input  wire [14:0]                         i_wqe_data_bufid,                // Data buffer ID for RDMA WRITES
  input  wire                                i_wqe_retried,                   // Retried work request
  input  wire [23:0]                         i_wqe_send_end_psn,              // End PSN of most recent request (last incase of READ/WRITE)
  input  wire [23:0]                         i_wqe_send_start_psn,            // start PSN of most recent request (first in case of READ/WRITE)
  input  wire [23:0]                         i_wqe_send_msn,
  input  wire [C_M_AXI_ADDR_WIDTH-1:0]       i_wqe_rdma_rd_rcv_ba,            // If request is RDMA READ, receive buffer base address
  input  wire [31:0]                         i_wqe_rdma_rd_res_len,           // If request is RDMA READ, response length in bytes
  input  wire                                i_wqe_push_req,                  // request from WQE Processor to push WQE
  input  wire                                i_wqe_exp_ack_set,               // Explicit ack bit is set in this WQE
  output wire                                o_wqe_push_rdy,                  // response to WQE Processor; 0 - busy; 1 - completed
  output wire [C_NUM_QP -1:0]                o_osq_full,                      // Oustanding Q full - 1 bit for each QP
  output wire [C_NUM_QP -1:0]                o_osq_almost_full,                      // Oustanding Q full - 1 bit for each QP
  output wire [C_NUM_QP -1: 0]               o_osq_empty,
  output wire                                o_freeup_data_buf,               // Freeup RDMA WRITE DATA buffer
  output wire [14:0]                         o_freeup_data_bufid,             // BUffer ID to be freed up
  input  wire [C_NUM_QP -1:0]                i_osq_wqe_nack_resp,             // WQE proc has handled the QP nack

  input  wire                                i_bypass_en,
  input  wire [C_NUM_QP -1:0]                i_qp_fatal,

  input  wire                                i_rd_rsp_wr_done,
  input  wire [C_QP_INDX_WIDTH-1:0]          i_rd_rsp_qpid,

  output wire [C_OS_Q_INDX_WIDTH :0]         o_num_valid_osq_entries,         // Number of valid OSQ entries
  input  wire [C_QP_INDX_WIDTH-1:0]          i_qpid_valid_entries,            // QPID for getting valid entries

  output wire [C_NUM_QP -1: 0]               o_osq_nacked,                    // The outstanding Qs that have been nacked

  // Explicit ack from QP manager
  input  wire  [C_NUM_QP -1:0]               i_explicit_ack_set,
  input  wire  [C_NUM_QP -1:0] 		     i_qp_disable_pulse,

  output wire [31:0]                         o_resp_hndler_sts,
  output wire [31:0]                         o_stat_retry_count,

  input  wire [C_QP_INDX_WIDTH -1 :0]        i_qp_index_mpsnbuf,        // QP ID to read the max PSN buffer top entry
  input  wire                                i_mpsn_buf_req,            // Request for reading mpsn buffer (not pop)
  output wire                                o_mpsn_buf_valid,          // Mpsn buffer output valid (not pop)
  output wire [C_OSQ_PSN_WIDTH-1:0]          o_max_epsn,                // Max expected response PSN
  output wire [23:0]                         o_trnsfr_length,           // Transfer length for the WQE
  output wire [63:0]                         o_local_addr,               // Local address - relevant only for RDMA READ requests
  input  wire                                i_mpsnbuf_pop,             // Pop the MAX PSN buffer
  output wire [C_NUM_QP -1 :0]               o_mpsnbuf_empty,               // OSQ is empty - one hot
  output wire [C_NUM_QP -1: 0]               o_retry_counter_expired,   // Retry counter (max number of retries) has expired - one hot
                                                                        // also asserted for RNR NAK timer expiry
  // Completion interrupt
  input  wire                                i_intr_en_wqe_cmpl,
  input  wire                                i_intr_clr_wqe_cmpl,
  output wire                                o_intr_wqe_cmpl,
  output wire [C_NUM_QP -1 :0]               o_intr_wqe_cmpl_sts,
  input  wire [C_NUM_QP -1 :0]               i_clr_wqe_cmpl_sts,

  input  wire [C_QP_INDX_WIDTH -1 :0]        i_qp_index_acknack,        // QP ID for ack_nack packet PSN
  input  wire                                i_acknack_valid,           // Valid signal qualifying the qp_index and acked PSN
  input  wire [23:0]                         i_acknacked_psn,           // PSN for the packet being acked/nacked
  input  wire [23:0]                         i_acknacked_msn,           // MSN for the packet being acked/nacked
  input  wire [7:0]                          i_pkt_nacksyndrome,        // NACK Syndrome. Valid when the i_pkt_nack is asserted
  input  wire [1:0]                          i_acknacked_opcode,        // 01:read-first/10:read-middle/11:read-last/only/00-acknowledge

  output wire [C_QP_INDX_WIDTH -1 :0]        o_retransmit_qpid,         // QP id for this retransmission is required
  output wire                                o_retransmit_reqd,         // Retransmission is required
  input  wire                                i_retransmit_accepted,         // Ack from QP manager that the retransmission is initiated
  output wire [23:0]                         o_psn_to_retry,
  output wire [23:0]                         o_ssn_to_retry,
  input  wire                                i_halt,
  input  wire [C_QP_INDX_WIDTH -1 :0]        i_halted_qpid,

  output wire [C_QP_INDX_WIDTH -1:0]         o_qp_conf_qp_idx,
  output wire                                o_qp_cq_ba_req,
  input  wire [C_M_AXI_ADDR_WIDTH -1:0]      i_qp_cq_ba,                      // CQ base address
  input  wire                                i_qp_cq_ba_valid,
  output wire                                o_qp_cq_depth_req,
  input  wire                                i_qp_cq_depth_valid,             // CQ depth
  input  wire [15:0]                         i_qp_cq_depth,
  output wire                                o_qp_sq_cmpldb_addr_req,
  input  wire                                i_qp_sq_cmpldb_addr_valid,       // SQ Completion DB address (points to RDMAif register)
  input  wire [C_M_AXI_ADDR_WIDTH -1:0]      i_qp_sq_cmpldb_addr,

  output wire                                o_qp_conf_req,
  input  wire                                i_qp_conf_valid,
  input  wire [31:0]                         i_qp_conf,

  output wire                                o_qp_cq_hdptr_req,
  input  wire                                i_qp_cq_hdptr_valid,             // CQ head pointer
  input  wire [15:0]                         i_qp_cq_hdptr,
  output wire [15:0]                         o_qp_cq_hdptr,
  output wire                                o_qp_cq_hdptr_wrn,

  output wire                                o_qp_sq_ba_req,
  input  wire                                i_qp_sq_ba_valid,
  input  wire [31:0]                         i_qp_sq_ba,

  // Generic config
  input  wire [31:0]                         i_data_buf_ba,
  input  wire [15:0]                         i_data_buf_sz,

  input  wire [7:0]                          i_num_elements_enabled,
  input  wire [4:0]                          i_timer_loadval_wqe,     //for 1st WQE goes out
  input  wire [4:0]                          i_timer_loadval_acknack, //for ACK/NACK received
  input  wire [3:0]			     i_cfg_base_cnt,
  input  wire                                i_dma_in_idle,

  output wire [C_NUM_QP -1:0]                o_qp_rnr_nacked,

  output wire [C_NUM_QP -1:0]                o_qp_retried,

  // Hardware handshake ports for NVMof (only enabled if C_EN_NVMOF_HW_HNDSHK is set to 1)
  output wire                                o_send_cq_db_cnt_valid,
  output wire [C_M_AXI_ADDR_WIDTH -1:0]      o_send_cq_db_addr,
  output wire [31:0]                         o_send_cq_db_cnt,
  input  wire                                i_send_cq_db_rdy,

  output wire [15:0]                         o_inc_nack_cnt,

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

 localparam IP2BUS_LEN_WIDTH = 7;
 localparam CQE_DB_SIZE_IN_BYTES = 7'd4; // Bytes

// MAXPSN buffer
// -------------------------------------------------------------------------------------
// |BYTE11|BYTE10|BYTE9-|BYTE8-|BYTE7-|BYTE6-|BYTE5-|BYTE4-|BYTE3-|BYTE2-|BYTE1-|BYTE0-|
// |------|--------------------|-------------------------------------------------------|
// | FPSN |    LENGTH          |                LOCAL BUFFER ADDRESS                   |
// |------|--------------------|-------------------------------------------------------|
// Total = 96 bits
 localparam MAXPSN_BUF_ENTRY_SIZE = 88 + C_OSQ_PSN_WIDTH; // bits

//Outstanding buffer
//|BYTE7-|BYTE6-|BYTE5-|BYTE4-|BYTE3-|BYTE2-|BYTE1-|BYTE0-|
//|------|-|-----------|------|------|------|-------------|
//| FPSN |R| BUFID     | MSN  | LPSN | OPC  |  WRID       |
//|------|-|-----------|------|------|------|-------------|
// RETRNSMT WQE - 1 bit
// BUFID        - 15 bits
// MSN LSB      - 8 bits
// OPcode       - 8 bits
// WReq ID      - 16 bits
// Total        - 56 bits
 localparam OSBUF_ENTRY_SIZE = 48 + C_OSQ_PSN_WIDTH + C_OSQ_PSN_WIDTH; // bits

// * Reason for having both first and last psn. This scneario is only valid for RDMA READ and RDMA WRITE requests
// Th RX packet handler requires the first PSN - for READ requests - since it
// needs to be generate a nack if the first READ PSN and all subsequent ones
// are not received. The resp_hanlder on the other hand needs the last PSN,
// since it can complete a transaction only when the last PSN has been acked.
// However, in case of a nacked WRITE transaciton, the new PSN that has to be
// retried has to be the FIRST PSN and not the last. Hence it also needs the

 localparam MASXPSN_BUF_MEM_SZ = C_OS_Q_DEPTH * MAXPSN_BUF_ENTRY_SIZE * C_NUM_QP; // memory size in bits
 localparam OSBUF_MEM_SZ = C_OS_Q_DEPTH * OSBUF_ENTRY_SIZE * C_NUM_QP; // memory size in bits

 localparam OS_Q_ADDR_WDITH = (clog2(C_OS_Q_DEPTH * C_NUM_QP));

 localparam RDMA_READ = 8'b00000100; // RC RDMA READ REQUEST opcode
 localparam NAK_SEQ_ERR = 8'b01100000;
 localparam RNR_NAK_ERR = 3'b001; // [7:5]
 localparam NO_ERROR = 8'b00000000;

 localparam RD_RESP_FIRST = 2'b01;
 localparam RD_RESP_MID   = 2'b10;

 // Response handler state is in IDLE
 localparam RESP_H_IN_IDLE     = 5'b00000;

 wire [C_QP_INDX_WIDTH -1 :0] retransmit_qpid;         // QP id for this retransmission is required
 wire phase_to_update_post_retry;
 wire nak_seq_error;
 wire rnr_nak_error;
 wire nack_for_psn_0;
 wire retransmit_reqd;
 wire wqe_push_for_non_nacked_qp;
 wire [31:0] resp_hndler_sts;
 wire [4:0] resp_h_cs;
 wire [C_OS_Q_INDX_WIDTH :0] selected_num_valid_osq_entries;         // Number of valid OSQ entries
 wire [C_OS_Q_INDX_WIDTH :0] push_pop_1_entry;
 wire [C_NUM_QP -1: 0] osq_push;
 wire [C_NUM_QP -1: 0] osq_pop;
 wire [C_NUM_QP -1: 0] mpsnbuf_push;
 wire [C_NUM_QP -1: 0] mpsnbuf_pop;
 wire [C_NUM_QP -1: 0] mpsnbuf_pop_for_nack;
 wire [C_NUM_QP -1: 0] mpsnbuf_pop_ored;
 wire [C_NUM_QP -1: 0] osq_full;
 wire [C_NUM_QP -1: 0] mpsnbuf_full;
 wire [C_NUM_QP -1: 0] mpsnbuf_almost_full;
 wire [C_NUM_QP -1: 0] osq_empty;
 wire [C_NUM_QP -1: 0] qp_id_valid_acknack;
 wire [C_NUM_QP -1: 0] qp_id_valid_nacked;
 wire  intr_wqe_cmpl_sts;
 wire [C_NUM_QP -1: 0] osq_almost_full;
 wire [15:0] osq_wrid;
 wire [7:0] osq_opcode;
 wire [C_OSQ_PSN_WIDTH-1:0] osq_start_psn;
 wire [C_OSQ_PSN_WIDTH-1:0] osq_end_psn;
 wire [7:0] osq_msn;
 wire [23:0] psn_to_retry;
 wire [23:0] msn_to_retry;
 wire [OS_Q_ADDR_WDITH -1:0] osq_rd_addr_ored [C_NUM_QP :0];
 wire [OS_Q_ADDR_WDITH -1:0] osq_wr_addr_ored [C_NUM_QP :0];
 wire [OS_Q_ADDR_WDITH -1:0] mpsnbuf_rd_addr_ored [C_NUM_QP :0];
 wire [OS_Q_ADDR_WDITH -1:0] mpsnbuf_wr_addr_ored [C_NUM_QP :0];
 wire [511:0] ip2bus_data;
 wire [C_M_AXI_ADDR_WIDTH -1:0] ip2bus_wraddr;
 wire ip2bus_wen;
 wire arbitrate;
 wire arbitration_done;
 wire valid_mpsnpush;
 wire [C_QP_INDX_WIDTH -1:0] osq_arbitrated_idx;
 wire [C_QP_INDX_WIDTH -1:0] osq_sampled_arbitrated_idx;
 wire [C_QP_INDX_WIDTH -1:0] arbitrated_idx_for_intr;
 wire [OS_Q_ADDR_WDITH -1:0] osq_wr_addr [C_NUM_QP -1 :0];
 wire [OS_Q_ADDR_WDITH -1:0] osq_rd_addr [C_NUM_QP -1 :0];
 wire [OS_Q_ADDR_WDITH -1:0] mpsnbuf_wr_addr [C_NUM_QP -1 :0];
 wire [OS_Q_ADDR_WDITH -1:0] mpsnbuf_rd_addr [C_NUM_QP -1 :0];
 wire pop_osq_from_fsm;
 wire [C_NUM_QP*OS_Q_ADDR_WDITH -1:0]osq_wr_addr_bus;
 wire [C_NUM_QP*OS_Q_ADDR_WDITH -1:0]osq_rd_addr_bus;
 wire [C_NUM_QP*OS_Q_ADDR_WDITH -1:0]mpsnbuf_wr_addr_bus;
 wire [C_NUM_QP*OS_Q_ADDR_WDITH -1:0]mpsnbuf_rd_addr_bus;
 wire [C_NUM_QP -1: 0] osq_timed_out;
 wire [C_NUM_QP -1: 0] osq_timed_out_sticky_wire;
 wire [23:0] acknacked_psn [C_NUM_QP -1:0];
 wire [23:0] acknacked_msn [C_NUM_QP -1:0];
 wire [23:0] last_acknacked_psn [C_NUM_QP -1:0];
 wire [23:0] acknacked_psn_for_arbitrated_qp;
 wire [23:0] acknacked_msn_for_arbitrated_qp;
 wire [23:0] last_acknacked_psn_for_arbitrated_qp;
 wire [C_NUM_QP -1: 0] timer_reload_for_wqe;
 wire [C_NUM_QP -1: 0] timer_reload_for_acknack;
 wire [C_NUM_QP -1: 0] timer_reload_for_acknack_pulse;
 wire [C_NUM_QP -1: 0] clr_timeout_n_nack;         // Clear for i_osq_timed_out
 wire [C_NUM_QP -1: 0] clr_pending_ack;         // Clear for i_osq_timed_out
 wire [C_NUM_QP -1: 0] osq_nacked;
 wire [C_NUM_QP -1: 0] arbitrated_idx_is_this;
 wire [C_NUM_QP -1: 0] osq_rnr_nacked;
 wire [C_NUM_QP -1: 0] rnr_nak_rcvd;
 wire [C_NUM_QP*OS_Q_ADDR_WDITH -1:0] osq_base_addr;	    // base address of where the Q exists
 wire [C_NUM_QP*OS_Q_ADDR_WDITH -1:0] mpsnbuf_base_addr;	    // base address of where the Q exists
 wire [C_NUM_QP -1 :0] mpsnbuf_empty;               // OSQ is empty - one hot
 wire [14:0] osq_data_bufid;
 wire osq_wqe_retried;
 wire [IP2BUS_LEN_WIDTH -1:0] ip2bus_len;
 wire [C_NUM_QP*(C_OS_Q_INDX_WIDTH+1) -1 :0] num_valid_osq_entries; // Number of valid entries in the queue
 wire [C_NUM_QP*(C_OS_Q_INDX_WIDTH+1) -1 :0] num_free_osq_entries_nc; // Not connected`
 wire [C_NUM_QP*(C_OS_Q_INDX_WIDTH+1) -1 :0] num_free_mpsn_entries_nc; // Not connected`
 wire [C_NUM_QP*(C_OS_Q_INDX_WIDTH+1) -1 :0] num_valid_mpsn_entries_nc; // Not connected`
 wire phase_bit_acknack_psn;
 wire [C_OSQ_PSN_WIDTH-1:0] curr_acknacked_psn_for_curr_qp;
 wire [C_OSQ_PSN_WIDTH-1:0] last_acknacked_psn_for_curr_qp;
 reg [C_NUM_QP -1: 0] timer_disabled_per_qp;
 wire [C_NUM_QP -1: 0] qp_retried;

 reg [1:0] acknacked_opcode_ff;        // 01:read-first/10:read-middle/11:read-last/only/00-acknowledge
 reg nak_seq_error_ff;
 reg [C_NUM_QP -1: 0] arbitrated_idx_is_this_ff;
 reg [15:0] inc_nack_cnt;
 reg [C_QP_INDX_WIDTH -1 :0] qp_index_acknack_ff;        // QP ID for ack_nack packet PSN
 reg acknack_valid_ff;
 reg [C_NUM_QP -1 :0] phase_bit_acknack_psn_ff;
 reg [C_NUM_QP -1 :0] wqe_cmpl_intr_sts;
 reg [C_OS_Q_INDX_WIDTH :0] num_valid_osq_entries_ff;         // Number of valid OSQ entries
 reg [C_NUM_QP -1: 0] osq_empty_ff;
 reg [C_NUM_QP -1: 0] timer_en_ff;
 reg [C_NUM_QP -1 :0] mpsnbuf_empty_ff;               // OSQ is empty - one hot
 reg [C_NUM_QP -1 :0] mpsnbuf_empty_2ff;               // OSQ is empty - one hot
 reg [C_NUM_QP -1: 0] osq_timed_out_sticky;
 reg [23:0] acknacked_psn_ff [C_NUM_QP -1:0];
 reg [23:0] acknacked_msn_ff [C_NUM_QP -1:0];
 reg [23:0] last_acknacked_psn_ff [C_NUM_QP -1:0];
 reg [C_NUM_QP -1: 0] timer_reload_for_wqe_ff;
 reg [C_NUM_QP -1: 0] timer_reload_for_acknack_ff;
 reg [C_NUM_QP -1: 0] osq_nacked_ff;
 reg [C_NUM_QP -1: 0] qp_retried_ff;
 reg [C_NUM_QP -1: 0] osq_rnr_nacked_ff;
 reg [4:0] rnr_nak_timer_ff;
 reg [C_NUM_QP -1 :0] first_outgoing_pkt_ff;
 reg [C_NUM_QP -1 :0] first_outstanding_pkt_ff;
 reg [C_NUM_QP -1 :0] first_outgoing_pkt_2ff;
 reg mpsnbuf_req_ff;
 reg mpsnbuf_req_2ff;

 genvar j;

// Sample the incoming acked (or nacked) PSN for every QP as it comes from the
// RX packet handler

// When a packet is retried, the PSN value is updated to save the last ACKed
// not assumed to be acked.

assign curr_acknacked_psn_for_curr_qp = acknacked_psn_ff[i_qp_index_acknack][C_OSQ_PSN_WIDTH-1:0];
assign last_acknacked_psn_for_curr_qp = last_acknacked_psn_ff[i_qp_index_acknack][C_OSQ_PSN_WIDTH-1:0];

`MSFF_R(acknack_valid_ff, i_acknack_valid, core_clk, ~core_rstn)
`MSFF_R(qp_index_acknack_ff, i_qp_index_acknack, core_clk, ~core_rstn)

// There is a special case where the PSN = 0 is NACKED. In this case and ONLY
// in this case the phase bit should not change/toggle. Since in this case the
// acked PSN is actually from the other "side". However, if the nacked psn is
// greater than 0, the rollover has occured and the next ack/nack can never go
// back to the previous "side"
assign phase_bit_acknack_psn =  (((curr_acknacked_psn_for_curr_qp[C_OSQ_PSN_WIDTH-1:0] < last_acknacked_psn_for_curr_qp[C_OSQ_PSN_WIDTH-1:0]) & ~nack_for_psn_0) ) ?
                                ~phase_bit_acknack_psn_ff[qp_index_acknack_ff] : phase_bit_acknack_psn_ff[qp_index_acknack_ff];

assign nack_for_psn_0 =  acknack_valid_ff & (acknacked_psn_ff[qp_index_acknack_ff][C_OSQ_PSN_WIDTH-1:0] == 'h0) & (osq_nacked_ff[qp_index_acknack_ff] | osq_rnr_nacked_ff[qp_index_acknack_ff]);

// last_acknaked_psn. This does not happen with RDMA READ transactions as the
// opcode is known

`MSFF_R(acknacked_opcode_ff, i_acknacked_opcode, core_clk, ~core_rstn)
`MSFF_R(nak_seq_error_ff, nak_seq_error, core_clk, ~core_rstn)

generate
    for (j=0; j<C_NUM_QP; j=j+1) begin: gen_acknackpsn_timer

        assign qp_retried[j] = ((j == retransmit_qpid) & (retransmit_reqd & i_retransmit_accepted)) ? 1'b1 : ((i_acknack_valid & (j == i_qp_index_acknack)) ? 1'b0 : qp_retried_ff[j]);

        `MSFF_R(qp_retried_ff[j], qp_retried[j], core_clk, ~core_rstn)

        assign qp_id_valid_acknack[j] = (i_acknack_valid & (j == i_qp_index_acknack) &
                                        (((i_acknacked_opcode != RD_RESP_MID) & (i_acknacked_opcode != RD_RESP_FIRST)) | nak_seq_error)) ? 1'b1 : 1'b0;

        assign acknacked_psn[j] = (first_outgoing_pkt_ff[j] & i_wqe_push_req & (i_wqe_qpid == j)) ? (i_wqe_send_start_psn - 1'b1) :
                                    (qp_id_valid_acknack[j] ? i_acknacked_psn[23:0] :
                                                         (clr_timeout_n_nack[j] ? (psn_to_retry -1'b1) : acknacked_psn_ff[j]));

        `MSFF_R(acknacked_psn_ff[j], acknacked_psn[j], core_clk, ~core_rstn)

        assign acknacked_msn[j] = qp_id_valid_acknack[j] ? i_acknacked_msn[23:0] :
                                                         (clr_timeout_n_nack[j] ? (msn_to_retry -1'b1) : acknacked_msn_ff[j]);

        `MSFF_R(acknacked_msn_ff[j], acknacked_msn[j], core_clk, ~core_rstn)

        // The last acnacked_psn is stored to identify the roll-over
        // condition. If the last_acknacked_psn is greater than acknacked_psn
        // it means rollover has happened
        // for the first outgoing packet, the psn -1 is saved as the last
        // acknacked psn

        assign last_acknacked_psn[j] = (first_outgoing_pkt_ff[j] & i_wqe_push_req & (i_wqe_qpid == j)) ? (i_wqe_send_start_psn - 1'b1) :
                                        ((qp_id_valid_acknack[j] /*|| qp_id_valid_nacked[j]*/)? acknacked_psn_ff[j] :
                                        (clr_timeout_n_nack[j] ? (psn_to_retry -1'b1) : last_acknacked_psn_ff[j]));

        `MSFF_R(last_acknacked_psn_ff[j], last_acknacked_psn[j], core_clk, ~core_rstn)

        `MSFF_R(phase_bit_acknack_psn_ff[j], (i_qp_disable_pulse[j] ? 1'b0: (((j == i_qp_index_acknack) & acknack_valid_ff &
                                    (((acknacked_opcode_ff != RD_RESP_MID) & (acknacked_opcode_ff != RD_RESP_FIRST)) | nak_seq_error_ff ))? phase_bit_acknack_psn :
                                    (clr_timeout_n_nack[j] ? phase_to_update_post_retry : phase_bit_acknack_psn_ff[j]))), core_clk, ~core_rstn)

        // Setting the last acknaked PSN is tricky. If it is set to 0, it does
        // not take into account the scenario where the first PSN is
        // a very large number and the first ack recv has already rolled over.
        // So the last_acknacked psn needs to be set to 1 less than the first
        // outgoing PSN
        //suri `MSFF_RL(first_outgoing_pkt_ff[j], ((i_wqe_push_req && (i_wqe_qpid == j)) ? 1'b0 : first_outgoing_pkt_ff[j]), core_clk, ~core_rstn, 1'b1)
        `MSFF_RL(first_outgoing_pkt_ff[j], (i_qp_disable_pulse[j]? 1'b1 : ((i_wqe_push_req && (i_wqe_qpid == j)) ? 1'b0 : first_outgoing_pkt_ff[j])), core_clk, ~core_rstn, 1'b1)
        `MSFF_RL(first_outgoing_pkt_2ff[j], first_outgoing_pkt_ff[j], core_clk, ~core_rstn, 1'b1)

        //--------------------------------------- timer logic----

        // a read request is pending
        `MSFF_RL(timer_en_ff[j], ((i_wqe_push_req && (i_wqe_qpid == j)) ? (i_wqe_exp_ack_set || valid_mpsnpush):
                                                                         ((osq_empty[j] | timer_disabled_per_qp[j]) ? 1'b0 : timer_en_ff[j])), core_clk, ~core_rstn, 1'b1)
        // Reload timer under the following conditions
        // a. first WQE goes out
        // b. New ack is recievd
        // c. Keep the timer under reset if the QP has already been nacked
        assign timer_reload_for_wqe[j] = (first_outstanding_pkt_ff[j] & i_wqe_push_req & (i_wqe_qpid == j));
        assign timer_reload_for_acknack_pulse[j] = (i_acknack_valid & (j == i_qp_index_acknack) & ~rnr_nak_error);
        assign timer_reload_for_acknack[j] = ((i_acknack_valid & (j == i_qp_index_acknack) & ~rnr_nak_error) | osq_nacked_ff[j]);
        assign osq_timed_out_sticky_wire[j] = (clr_timeout_n_nack[j] | qp_id_valid_acknack[j])? 1'b0 : (osq_timed_out[j] | osq_timed_out_sticky[j]);
        assign osq_nacked[j] = (i_acknack_valid & (j == i_qp_index_acknack) && nak_seq_error & ~(i_halt & (i_halted_qpid ==j))) ? 1'b1 : osq_nacked_ff[j];

        `MSFF_RL(first_outstanding_pkt_ff[j], ((clr_timeout_n_nack[j] | i_qp_disable_pulse[j]) ? 1'b1: ((i_wqe_push_req && (i_wqe_qpid == j)) ? 1'b0 : first_outstanding_pkt_ff[j])), core_clk, ~core_rstn, 1'b1)
        // Unless an ack is processed and the arbitrated QP moves to another
        // (clr_pending_ack[j] & ~timer_reload_ff[j]) - this condition is
        // added to take care of the following case: The ack came in while the
        // FSM was processing the same QP. But this new ack was not sampled.
        // However, the clear was aserted.
        `MSFF_R(timer_reload_for_wqe_ff[j], (timer_reload_for_wqe[j] ? 1'b1 : ((first_outgoing_pkt_2ff[j] | clr_pending_ack[j] | osq_rnr_nacked[j]) ? 1'b0 : timer_reload_for_wqe_ff[j])), core_clk, ~core_rstn)
        `MSFF_R(timer_reload_for_acknack_ff[j], (timer_reload_for_acknack[j] ? 1'b1 : ((first_outgoing_pkt_2ff[j] | clr_pending_ack[j] | osq_rnr_nacked[j]) ? 1'b0 : timer_reload_for_acknack_ff[j])), core_clk, ~core_rstn)

        assign arbitrated_idx_is_this[j] = ((j == osq_sampled_arbitrated_idx) && (resp_h_cs != RESP_H_IN_IDLE)) ? 1'b1 : 1'b0;
        `MSFF_R(arbitrated_idx_is_this_ff[j], arbitrated_idx_is_this[j], core_clk, ~core_rstn)

        // Apart from generating a different counter value for the timeout, nothing
        // special is being done for RNR_NAK. when this special counter expires, the
        // FSM will retry those messages.
        assign osq_rnr_nacked[j] = (i_acknack_valid & (j == i_qp_index_acknack) && rnr_nak_error) ? 1'b1 :
                                                               (clr_timeout_n_nack[j] ? 1'b0 : osq_rnr_nacked_ff[j]);

        `MSFF_R(osq_nacked_ff[j], (clr_timeout_n_nack[j] ? 1'b0 : (osq_nacked[j] | osq_nacked_ff[j])), core_clk, ~core_rstn)
        `MSFF_R(osq_timed_out_sticky[j], ((clr_timeout_n_nack[j] | timer_reload_for_wqe_ff[j] | timer_reload_for_acknack_ff[j])? 1'b0 : osq_timed_out_sticky_wire[j]), core_clk, ~core_rstn)

    end
endgenerate

assign o_qp_rnr_nacked = osq_rnr_nacked_ff;
assign o_qp_retried = qp_retried_ff;

assign rnr_nak_error = i_pkt_nacksyndrome[7:5] == RNR_NAK_ERR ? 1'b1 : 1'b0;
assign nak_seq_error = i_pkt_nacksyndrome == NAK_SEQ_ERR ? 1'b1 : 1'b0;

`MSFF_R(inc_nack_cnt, (i_acknack_valid & (rnr_nak_error | nak_seq_error) ? (inc_nack_cnt + 1'b1) : inc_nack_cnt), core_clk, ~core_rstn)

assign acknacked_psn_for_arbitrated_qp = acknacked_psn_ff[osq_sampled_arbitrated_idx];
assign acknacked_msn_for_arbitrated_qp = acknacked_msn_ff[osq_sampled_arbitrated_idx];
assign last_acknacked_psn_for_arbitrated_qp = last_acknacked_psn_ff[osq_sampled_arbitrated_idx];

assign o_inc_nack_cnt = inc_nack_cnt;

// Two sets of outstanding FIFOs are maintained.
// One for MAX PSN - the information about what can be the max expected PSN is
// required by the RX packet handler. So, all WQEs that are generated by WQE
// proc module that either have the explicit ack bit set or is a RDMA READ
// destination)
// Contents of the MAX PSN buffer are:
// Total = 96 bits
// The other buffer is for the response handler module. For every acknowledged
// needs to be rung to RDMAIf

// Outstanding FIFO - for response handler module
// The memory for all the 256 FIFOs are meged into one XPM memory instance to
// have a better optimized memory utilization.
xpm_memory_sdpram # (

  // Common module parameters
  .MEMORY_SIZE        (OSBUF_MEM_SZ),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("common_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (OSBUF_ENTRY_SIZE),              //positive integer
  .BYTE_WRITE_WIDTH_A (OSBUF_ENTRY_SIZE),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (OS_Q_ADDR_WDITH),               //positive integer

  // Port B module parameters
  .READ_DATA_WIDTH_B  (OSBUF_ENTRY_SIZE),              //positive integer
  .ADDR_WIDTH_B       (OS_Q_ADDR_WDITH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //string
  .READ_LATENCY_B     (2),               //non-negative integer
  .WRITE_MODE_B       ("read_first")     //string; "write_first", "read_first", "no_change"

) inst_xpm_osq (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (core_clk),
  .ena            (1'b1),
  .wea            (wqe_push_for_non_nacked_qp),//(i_wqe_push_req),
  .addra          (osq_wr_addr_ored[C_NUM_QP][OS_Q_ADDR_WDITH -1:0]),
  .dina           ({i_wqe_send_start_psn[C_OSQ_PSN_WIDTH-1:0], i_wqe_retried,i_wqe_data_bufid[14:0], i_wqe_send_msn[7:0], i_wqe_send_end_psn[C_OSQ_PSN_WIDTH-1:0], i_wqe_opcode, i_wqe_wrid}),
  .injectsbiterra (1'b0),  //do not change
  .injectdbiterra (1'b0),  //do not change

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .addrb          (osq_rd_addr_ored[C_NUM_QP][OS_Q_ADDR_WDITH -1:0]),
  .doutb          ({osq_start_psn, osq_wqe_retried, osq_data_bufid,osq_msn,osq_end_psn,osq_opcode,osq_wrid}),
  .sbiterrb       (),      //do not change
  .dbiterrb       ()       //do not change

);

assign o_psn_to_retry = psn_to_retry;
assign o_ssn_to_retry = msn_to_retry;
assign o_freeup_data_bufid = osq_data_bufid;

// This is the osq implementation. The actual memory is implemented in the XPM
// memory. This module manages the pointers for the memory and generates
// full/emplty for the queues
rdma_q_mgr_init_top
#(
    .C_NUM_QUEUES(C_NUM_QP),          	            // Number of queues
    .C_Q_DEPTH   (C_OS_Q_DEPTH),                    // Number of entries in each queue
    .C_ENTRY_SIZE(1),	                            // *See below. Size of each entry in Bytes. SQ size is 64B
    .C_THRESHOLD(5),                                // Threshold for generating almost full
    .C_PTR_WIDTH (C_OS_Q_INDX_WIDTH),	            // Pointer size reqd for accessing the Q depth
    .C_ADDR_WIDTH(OS_Q_ADDR_WDITH)	            // System address bus width
    //* C_ENTRY_SIZE - This parameter is used to generate the address for the
    //memory which is likely in DDR and generates a BYTE address. However
    //since we are directly using this address for he BRAM which houses the
    //OSQ the address is entry address (as each entry houses the entire OSQ
    //content for one valida transaction). hence a size of 1 is given so that
    //the address maps to the correct entry.
) inst_osq_manager
(
    .core_clk                           (core_clk),
    .core_rst                           (~core_rstn),	    // Active high core reset

// Queue pointers
    .o_rd_ptr                           (),	    // Read pointers stacked on one bus
    .o_wr_ptr                           (),	    // Write pointers stacked on one bus
    .o_rd_addr                          (osq_rd_addr_bus),     // Read addres
    .o_wr_addr                          (osq_wr_addr_bus),     // Write address
    .o_q_full                           (osq_full),     	    // Queue is full
    .o_q_almost_full                    (osq_almost_full),	    // Queue is full
    .o_q_empty                          (osq_empty),     	    // Queue is empty
    .o_num_valid_entries                (num_valid_osq_entries), // Number of valid entries in the queue
    .o_num_free_entries                 (num_free_osq_entries_nc),  // Number of free entries in the queue

    .i_base_addr                        (osq_base_addr),	    // base address of where the Q exists
    .i_q_depth                          ({C_NUM_QP{C_OS_Q_DEPTH[0+:(C_OS_Q_INDX_WIDTH+1)]}}),      // Configurable q depth (less than max as defined by param)

    .i_q_push                           (osq_push),	                                        // Push enable for a queue
    .i_push_num_entries                 ({C_NUM_QP{push_pop_1_entry}}),          // Number of entries to be pushed - always 1

    .i_q_pop                            (osq_pop),	                                        // Pop enable for a queue
    .i_pop_num_entries                  ({C_NUM_QP{push_pop_1_entry}})           // Number of entries to be popped - always 1

);

assign selected_num_valid_osq_entries = num_valid_osq_entries[(i_qpid_valid_entries*(C_OS_Q_INDX_WIDTH+1)) +: C_OS_Q_INDX_WIDTH+1];
`MSFF_R(num_valid_osq_entries_ff, selected_num_valid_osq_entries, core_clk, ~core_rstn)
assign o_num_valid_osq_entries = num_valid_osq_entries_ff;

assign push_pop_1_entry = {{C_OS_Q_INDX_WIDTH{1'b0}}, 1'b1};

assign o_wqe_push_rdy = 1'b1; //Can be changed later to add delay

assign o_osq_empty = osq_empty;

assign osq_rd_addr_ored[0] = 'd0;
assign osq_wr_addr_ored[0] = 'd0;

assign wqe_push_for_non_nacked_qp = (osq_nacked_ff[i_wqe_qpid] & i_osq_wqe_nack_resp[i_wqe_qpid]) ? 1'b0 : i_wqe_push_req;

assign o_osq_nacked = osq_nacked_ff | osq_rnr_nacked_ff | osq_timed_out_sticky;

genvar i;
generate
    for (i=0; i<C_NUM_QP; i=i+1) begin: gen_osq_param
        assign osq_push[i] = (i_wqe_qpid == i) ? wqe_push_for_non_nacked_qp : 1'b0;
        assign osq_wr_addr[i] = (i_wqe_qpid == i) ? osq_wr_addr_bus[i*OS_Q_ADDR_WDITH +: OS_Q_ADDR_WDITH] : 'd0;

        assign osq_rd_addr[i] = (osq_sampled_arbitrated_idx == i) ? osq_rd_addr_bus[i*OS_Q_ADDR_WDITH +: OS_Q_ADDR_WDITH] : 'd0;
        assign osq_pop[i] = (osq_sampled_arbitrated_idx == i) ? pop_osq_from_fsm : 1'b0;

        assign osq_rd_addr_ored[i+1] = osq_rd_addr_ored[i] | osq_rd_addr[i];
        assign osq_wr_addr_ored[i+1] = osq_wr_addr_ored[i] | osq_wr_addr[i];

        assign osq_base_addr[i*OS_Q_ADDR_WDITH+:OS_Q_ADDR_WDITH] = i*C_OS_Q_DEPTH;
    end
endgenerate

genvar n;
generate
    for (n=0; n<C_NUM_QP; n=n+1) begin: gen_wqe_intr
        `MSFF_R(wqe_cmpl_intr_sts[n], (i_clr_wqe_cmpl_sts[n] ? 1'b0 : ((arbitrated_idx_for_intr == n) ? (intr_wqe_cmpl_sts || wqe_cmpl_intr_sts[n]) :
                                                                    wqe_cmpl_intr_sts[n])) , core_clk, ~core_rstn)
    end
endgenerate

assign o_intr_wqe_cmpl = |(wqe_cmpl_intr_sts) & i_intr_en_wqe_cmpl;
assign o_intr_wqe_cmpl_sts = wqe_cmpl_intr_sts;

//Arbiter to arbitrate between the QPs that need processing

  // Single QP: no arbitration needed
  assign arbitration_done   = arbitrate & ~osq_empty_ff;
  assign osq_arbitrated_idx = {C_QP_INDX_WIDTH{1'b0}};

// Adding flop to ease timing
`MSFF_R(osq_empty_ff, osq_empty, core_clk, ~core_rstn)
assign o_qp_conf_qp_idx = osq_sampled_arbitrated_idx;

// Response handler FSM instance -----------------------------------------
resp_handler_fsm
#(
    .C_NUM_QP             (C_NUM_QP          ),
    .C_M_AXI_ADDR_WIDTH   (C_M_AXI_ADDR_WIDTH),
    .C_QP_INDX_WIDTH      (C_QP_INDX_WIDTH   ),
    .C_EN_NVMOF_HW_HNDSHK (C_EN_NVMOF_HW_HNDSHK),
    .IP2BUS_LEN_WIDTH     (IP2BUS_LEN_WIDTH ),
    .C_OS_Q_DEPTH         (C_OS_Q_DEPTH      ),
    .C_OSQ_PSN_WIDTH	  (C_OSQ_PSN_WIDTH   ),
    .C_EN_WR_RETRY_DATA_BUF(C_EN_WR_RETRY_DATA_BUF    ),
    .C_OS_Q_INDX_WIDTH    (C_OS_Q_INDX_WIDTH )
) inst_resp_handler_fsm
(
    .core_clk                   (core_clk),
    .core_rstn                  (core_rstn),	    // Active low core reset

    .i_acks_to_process          (~(&osq_empty)), // ideally should check for valid ack, but it will be too expnesive logic wise
    .o_arbitrate                (arbitrate),
    .i_arbitration_done         (arbitration_done),
    .i_arbitrated_indx          (osq_arbitrated_idx),
    .o_sampled_arbitrated_indx  (osq_sampled_arbitrated_idx),
    .o_arbitrated_qp_for_intr   (arbitrated_idx_for_intr),
    .o_resp_hndler_sts          (resp_hndler_sts),
    .o_stat_retry_count         (o_stat_retry_count),
    .o_phase_to_update_post_retry(phase_to_update_post_retry),

    .i_bypass_en                (i_bypass_en),
    .i_qp_fatal                 (i_qp_fatal),
    .i_dma_in_idle		(i_dma_in_idle),

    .i_first_outgoing_pkt       (first_outgoing_pkt_ff),
    .i_wqe_qpid                 (i_wqe_qpid),
    .i_wqe_send_start_psn       (i_wqe_send_start_psn[C_OSQ_PSN_WIDTH-1:0]),
    .i_wqe_push_req             (i_wqe_push_req),

    .o_pop_osq                  (pop_osq_from_fsm),
    .o_pop_mpsn                 (pop_mpsn_from_fsm),
    .i_osq_empty                (osq_empty[osq_sampled_arbitrated_idx]),
    .i_mpsnbuf_empty            (mpsnbuf_empty[osq_sampled_arbitrated_idx]),
    .i_phase_bit_acknack_psn    (phase_bit_acknack_psn_ff[osq_sampled_arbitrated_idx]),
    .i_osq_entry_msn            (osq_msn     ),
    .i_osq_entry_end_psn        (osq_end_psn     ),
    .i_osq_entry_start_psn      (osq_start_psn     ),
    .i_osq_acknacked_psn        (acknacked_psn_for_arbitrated_qp),
    .i_osq_acknacked_msn        (acknacked_msn_for_arbitrated_qp),
    .i_osq_last_acknacked_psn   (last_acknacked_psn_for_arbitrated_qp),
    .i_osq_timed_out            (osq_timed_out_sticky),
    .i_osq_rnr_nacked           (osq_rnr_nacked_ff),
    .o_clr_timeout_n_nack       (clr_timeout_n_nack ),
    .o_clr_pending_ack          (clr_pending_ack ),
    .i_osq_nacked               (osq_nacked_ff[osq_sampled_arbitrated_idx]),
    .i_osq_wqe_nack_resp        (i_osq_wqe_nack_resp[osq_sampled_arbitrated_idx]),
    .i_osq_opcode               (osq_opcode  ),                    // BTH.Opcode of outbound request
    .i_osq_wrid                 (osq_wrid    ),
    .o_psn_to_retry             (psn_to_retry),
    .o_msn_to_retry             (msn_to_retry),
    .o_freeup_data_buf          (o_freeup_data_buf),
    .i_osq_wqe_retried          (osq_wqe_retried),
    .i_osq_wqe_data_bufid       (osq_data_bufid),

    .o_qp_cq_ba_req             (o_qp_cq_ba_req           ),
    .i_qp_cq_ba                 (i_qp_cq_ba               ),                      // CQ base address
    .i_qp_cq_ba_valid           (i_qp_cq_ba_valid         ),
    .o_qp_cq_depth_req          (o_qp_cq_depth_req        ),
    .i_qp_cq_depth_valid        (i_qp_cq_depth_valid      ),             // CQ depth
    .i_qp_cq_depth              (i_qp_cq_depth            ),
    .o_qp_sq_cmpldb_addr_req    (o_qp_sq_cmpldb_addr_req  ),
    .i_qp_sq_cmpldb_addr_valid  (i_qp_sq_cmpldb_addr_valid),       // SQ Completion DB address (points to RDMAif register)
    .i_qp_sq_cmpldb_addr        (i_qp_sq_cmpldb_addr      ),

    .o_qp_sq_ba_req             (o_qp_sq_ba_req  ),
    .i_qp_sq_ba_valid           (i_qp_sq_ba_valid),
    .i_qp_sq_ba                 (i_qp_sq_ba      ),

    .i_data_buf_ba              (i_data_buf_ba   ),
    .i_data_buf_sz              (i_data_buf_sz   ),

    .o_qp_conf_req              (o_qp_conf_req            ),
    .i_qp_conf_valid            (i_qp_conf_valid          ),
    .i_qp_conf                  (i_qp_conf                ),

    .o_qp_cq_hdptr_req          (o_qp_cq_hdptr_req        ),
    .i_qp_cq_hdptr_valid        (i_qp_cq_hdptr_valid      ),             // CQ head pointer
    .i_qp_cq_hdptr              (i_qp_cq_hdptr            ),
    .o_qp_cq_hdptr              (o_qp_cq_hdptr            ),
    .o_qp_cq_hdptr_wrn          (o_qp_cq_hdptr_wrn        ),

    .i_rd_rsp_wr_done           (i_rd_rsp_wr_done),
    .i_rd_rsp_qpid              (i_rd_rsp_qpid),

    .i_intr_clr_wqe_cmpl        (i_intr_clr_wqe_cmpl      ),
    .o_intr_wqe_cmpl_sts        (intr_wqe_cmpl_sts        ),

    .o_retransmit_qpid          (retransmit_qpid  ),         // QP id for this retransmission is required
    .o_retransmit_reqd          (retransmit_reqd  ),         // Retransmission is required
    .i_retransmit_accepted      (i_retransmit_accepted  ),         // Ack from QP manager that the retransmission is initiated

  // Hardware handshake ports for NVMof (only enabled if C_EN_NVMOF_HW_HNDSHK is set to 1)
    .o_send_cq_db_cnt_valid     (o_send_cq_db_cnt_valid),
    .o_send_cq_db_addr          (o_send_cq_db_addr     ),
    .o_send_cq_db_cnt           (o_send_cq_db_cnt      ),
    .i_send_cq_db_rdy           (i_send_cq_db_rdy      ),

    .i_bus2ip_data_rdy          (bus2ip_data_rdy),
    .i_axi_master_done          (axi_master_done),
    .o_ip2bus_wen               (ip2bus_wen),                    // Write en to AXI master
    .o_ip2bus_len               (ip2bus_len),
    .o_ip2bus_wraddr            (ip2bus_wraddr),                 // Write address
    .o_ip2bus_data              (ip2bus_data)
);

assign o_retransmit_reqd = retransmit_reqd;
assign o_osq_full = osq_full;
assign o_osq_almost_full = osq_almost_full;
assign o_retransmit_qpid = retransmit_qpid;
assign o_resp_hndler_sts = resp_hndler_sts;

// Need the fsm state
assign resp_h_cs = resp_hndler_sts[8+:5];

// Outstanding FIFO - max PSN . This is for use by the RX packet validation
// module. An entry is pushed into this FIFO when the WQE opcode is RDMA_READ.
// In case of coalesced acks, this serves to provide the MAX PSN number that
// is allowed. In other words, any coalesced ack cannot skip t;
// he explicit ack for
// a RDMA READ operation. The pop is done directly by the RX packet handler/
// The memory for all the 256 FIFOs are meged into one XPM memory instance to
// have a better optimized memory utilization.

xpm_memory_sdpram # (

  // Common module parameters
  .MEMORY_SIZE        (MASXPSN_BUF_MEM_SZ),            //positive integer
  .MEMORY_PRIMITIVE   ("auto"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("common_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (MAXPSN_BUF_ENTRY_SIZE),              //positive integer
  .BYTE_WRITE_WIDTH_A (MAXPSN_BUF_ENTRY_SIZE),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (OS_Q_ADDR_WDITH),               //positive integer

  // Port B module parameters
  .READ_DATA_WIDTH_B  (MAXPSN_BUF_ENTRY_SIZE),              //positive integer
  .ADDR_WIDTH_B       (OS_Q_ADDR_WDITH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //string
  .READ_LATENCY_B     (2),               //non-negative integer
  .WRITE_MODE_B       ("read_first")     //string; "write_first", "read_first", "no_change"

) inst_xpm_max_psn_q (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (core_clk),
  .ena            (1'b1),
  .wea            (valid_mpsnpush),
  .addra          (mpsnbuf_wr_addr_ored[C_NUM_QP][OS_Q_ADDR_WDITH -1:0]),
  .dina           ({i_wqe_send_start_psn[C_OSQ_PSN_WIDTH-1:0], i_wqe_rdma_rd_res_len[23:0], {(64 - C_M_AXI_ADDR_WIDTH){1'b0}}, i_wqe_rdma_rd_rcv_ba}),
  .injectsbiterra (1'b0),  //do not change
  .injectdbiterra (1'b0),  //do not change

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (~core_rstn),
  .enb            (1'b1),
  .regceb         (1'b1),
  .addrb          (mpsnbuf_rd_addr_ored[C_NUM_QP][OS_Q_ADDR_WDITH -1:0]),
  .doutb          ({o_max_epsn, o_trnsfr_length, o_local_addr}),
  .sbiterrb       (),      //do not change
  .dbiterrb       ()       //do not change

);

 `MSFF_R(mpsnbuf_req_ff, i_mpsn_buf_req, core_clk, ~core_rstn)
 `MSFF_R(mpsnbuf_req_2ff, mpsnbuf_req_ff, core_clk, ~core_rstn)

 assign o_mpsn_buf_valid = mpsnbuf_req_2ff;

// This is the max psn q implementation. The actual memory is implemented in the XPM
// memory. This module manages the pointers for the memory and generates
// full/emplty for the queues
rdma_q_mgr_init_top
#(
    .C_NUM_QUEUES(C_NUM_QP),          	            // Number of queues
    .C_Q_DEPTH   (C_OS_Q_DEPTH),                    // Number of entries in each queue
    .C_ENTRY_SIZE(1),	                            // * see below. Size of each entry in Bytes. SQ size is 64B
    .C_PTR_WIDTH (C_OS_Q_INDX_WIDTH),	            // Pointer size reqd for accessing the Q depth
    .C_ADDR_WIDTH(OS_Q_ADDR_WDITH)	            // System address bus width
    //* C_ENTRY_SIZE - This parameter is used to generate the address for the
    //memory which is likely in DDR and generates a BYTE address. However
    //since we are directly using this address for he BRAM which houses the
    //OSQ the address is entry address (as each entry houses the entire OSQ
    //content for one valida transaction). hence a size of 1 is given so that
    //the address maps to the correct entry.
) inst_mpsnbuf_manager
(
    .core_clk                           (core_clk),
    .core_rst                           (~core_rstn),	    // Active high core reset

// Queue pointers
    .o_rd_ptr                           (),	    // Read pointers stacked on one bus
    .o_wr_ptr                           (),	    // Write pointers stacked on one bus
    .o_rd_addr                          (mpsnbuf_rd_addr_bus),     // Read addres
    .o_wr_addr                          (mpsnbuf_wr_addr_bus),     // Write address
    .o_q_full                           (mpsnbuf_full),     	    // Queue is full
    .o_q_almost_full                    (mpsnbuf_almost_full),	    // Queue is full
    .o_q_empty                          (mpsnbuf_empty),     	    // Queue is empty
    .o_num_valid_entries                (num_valid_mpsn_entries_nc), // Number of valid entries in the queue
    .o_num_free_entries                 (num_free_mpsn_entries_nc),  // Number of free entries in the queue

    .i_base_addr                        (mpsnbuf_base_addr), // address of where the Q exists
    .i_q_depth                          ({C_NUM_QP{C_OS_Q_DEPTH[0+:(C_OS_Q_INDX_WIDTH+1)]}}),      // Configurable q depth (less than max as defined by param)

    .i_q_push                           (mpsnbuf_push),	    // Push enable for a queue
    .i_push_num_entries                 ({C_NUM_QP{{C_OS_Q_INDX_WIDTH{1'b0}}, 1'b1}}),          // Number of entries to be pushed - always 1

    .i_q_pop                            (mpsnbuf_pop_ored),	            // Pop enable for a queue
    .i_pop_num_entries                  ({C_NUM_QP{{C_OS_Q_INDX_WIDTH{1'b0}}, 1'b1}})           // Number of entries to be popped - always 1

);

// When the buffer becomes empty and then an entry is pushed, there is
// a read-write collision. As a result the data is x for one clock cycle.
// To avoid this, the empty->not-empty is delayed by 2 clock cycles.

`MSFF_R(mpsnbuf_empty_ff,  mpsnbuf_empty,    core_clk, ~core_rstn)
`MSFF_R(mpsnbuf_empty_2ff, mpsnbuf_empty_ff, core_clk, ~core_rstn)

assign o_mpsnbuf_empty = mpsnbuf_empty | mpsnbuf_empty_ff | mpsnbuf_empty_2ff;

// Only READ WQEs go into the max psn buffer
assign valid_mpsnpush = (i_wqe_opcode == RDMA_READ) ? wqe_push_for_non_nacked_qp : 1'b0;

assign mpsnbuf_wr_addr_ored[0] = 32'b0;
assign mpsnbuf_rd_addr_ored[0] = 32'b0;

// We can OR them because the nack pop QPID and the RX packet handler QPID
// will never be the same. Once the QP is nacked, that QP cannot be acked
// unless the packet is retried
assign mpsnbuf_pop_ored = mpsnbuf_pop | mpsnbuf_pop_for_nack;

genvar k;
generate
    for (k=0; k<C_NUM_QP; k=k+1) begin: gen_mpsn_push_pop
        assign mpsnbuf_push[k] = (i_wqe_qpid == k) ? valid_mpsnpush : 1'b0;  // push initiated by WQE proc
        assign mpsnbuf_wr_addr[k] = (i_wqe_qpid == k) ? mpsnbuf_wr_addr_bus[k*OS_Q_ADDR_WDITH +: OS_Q_ADDR_WDITH] : 'd0;

        assign mpsnbuf_pop[k]  = (i_qp_index_mpsnbuf == k) ? i_mpsnbuf_pop : 1'b0; // pop initiated by RX packet handler
        assign mpsnbuf_pop_for_nack[k]  = (osq_sampled_arbitrated_idx == k) ? pop_mpsn_from_fsm : 1'b0; // pop initiated by FSM for flushing

        assign mpsnbuf_rd_addr[k] = (i_qp_index_mpsnbuf == k) ? mpsnbuf_rd_addr_bus[k*OS_Q_ADDR_WDITH +: OS_Q_ADDR_WDITH] : 'd0;

        assign mpsnbuf_rd_addr_ored[k+1] = mpsnbuf_rd_addr_ored[k] | mpsnbuf_rd_addr[k];
        assign mpsnbuf_wr_addr_ored[k+1] = mpsnbuf_wr_addr_ored[k] | mpsnbuf_wr_addr[k];

        assign mpsnbuf_base_addr[k*OS_Q_ADDR_WDITH+:OS_Q_ADDR_WDITH] = k*C_OS_Q_DEPTH;

    end
endgenerate

resp_handler_timer
#(
    .C_NUM_QP                (C_NUM_QP         ),
    .C_QP_INDX_WIDTH         (C_QP_INDX_WIDTH  ),
    .C_NUM_CYCLES_4US        (C_NUM_CYCLES_4US ), // Number of clock cycles that make 4 us (for 125Mhz clk period it is 512)
    .C_OS_Q_INDX_WIDTH       (C_OS_Q_INDX_WIDTH)
) inst_timer
(
  .core_clk             (core_clk ),
  .core_rstn            (core_rstn),	    // Active low core reset
  .i_cfg_base_cnt	(i_cfg_base_cnt),
  .o_q_timed_out        (osq_timed_out),
  .i_timer_en           ((~osq_empty_ff & ~timer_disabled_per_qp) | osq_rnr_nacked_ff),
  .i_rnr_nak_rcvd       (rnr_nak_rcvd),
  .i_rnr_nak_timer      (i_pkt_nacksyndrome[4:0]),
  .i_reload_timer_wqe   (timer_reload_for_wqe ),//| osq_empty),
  .i_reload_timer_acknack(timer_reload_for_acknack_pulse ),//| osq_empty),
  .i_reset_timer_osq_nacked(osq_nacked_ff),//| osq_empty),
  .i_reload_value_wqe    (i_timer_loadval_wqe),     //re-load value when 1st WQE goes out
  .i_reload_value_acknack(i_timer_loadval_acknack)  //re-load value on other ACK/NACK recieved and other cases

);

genvar k0;
generate
for (k0=0;k0 < C_NUM_QP; k0 = k0+1)
begin: timer_disable

always @(posedge core_clk)
begin
	if(~core_rstn)
	    timer_disabled_per_qp[k0] <= {C_NUM_QP{1'b0}};
	else if(i_acknack_valid & (i_qp_index_acknack == k0))
	    timer_disabled_per_qp[k0] <= ~(|i_timer_loadval_acknack);
	else if(i_wqe_push_req & (i_wqe_qpid == k0))
	    timer_disabled_per_qp[k0] <= ~(|i_timer_loadval_wqe);

end
end
endgenerate

assign rnr_nak_rcvd = ~osq_rnr_nacked_ff & (osq_rnr_nacked ^ osq_rnr_nacked_ff); // checking posedge

`MSFF_R(osq_rnr_nacked_ff, osq_rnr_nacked, core_clk, ~core_rstn)
`MSFF_R(rnr_nak_timer_ff, i_pkt_nacksyndrome[4:0], core_clk, ~core_rstn)

//AXI master to write completions and doorbell to RDMAif
rdma_axi_master
#(
.C_M_AXI_ADDR_WIDTH(C_M_AXI_ADDR_WIDTH),
.C_M_AXI_DATA_WIDTH(512),
.C_M_AXI_THREAD_ID_WIDTH(1),
.IP2BUS_LEN_WIDTH(IP2BUS_LEN_WIDTH)
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
.bus2ip_data                    (),
.bus2ip_dvalid                  (),     // Only used for writes
.ip2bus_data                    (ip2bus_data),
.bus2ip_data_rdy                (bus2ip_data_rdy),
.axi_m_en                       (ip2bus_wen),
.wr_rdn                         (1'b1),             //1 = write; 0 = read
.ip2bus_addr                    (ip2bus_wraddr),
.ip2bus_len                     (ip2bus_len),         //length in bytes

.axi_master_done                (axi_master_done),
.axi_master_busy                (axi_master_busy),
.axi_master_bvalid              (axi_master_bvalid),
.axi_master_error               (axi_master_error_nc)

    );

  endmodule

