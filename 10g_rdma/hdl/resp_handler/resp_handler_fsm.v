// resp_handler_fsm.v
// 文件名          : resp_handler_fsm.v
// 版本            : v1.0
// 描述            : 响应处理状态机，解析 ACK/NAK 并驱动重传/完成队列更新
//                   状态包括空闲、仲裁、PSN 比较、CQ 更新、重传触发等
// Verilog 标准    : Verilog'2001

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
`timescale 1ps/1ps

(* DowngradeIPIdentifiedWarnings="yes" *)
module resp_handler_fsm
#(
    parameter   C_NUM_QP                = 256,
    parameter   C_M_AXI_ADDR_WIDTH      = 32,
    parameter   C_QP_INDX_WIDTH         = 8,
    parameter   C_EN_NVMOF_HW_HNDSHK    = 1,  // Enabled hardware handshake with NVMoF
    parameter   C_OS_Q_DEPTH            = 8,
    parameter   IP2BUS_LEN_WIDTH        = 7,
    parameter   C_OSQ_PSN_WIDTH		= 10,
    parameter   C_EN_WR_RETRY_DATA_BUF		= 1,
    parameter   C_OS_Q_INDX_WIDTH       = 3
)
(
  input  wire				     core_clk,
  input  wire				     core_rstn,	    // Active low core reset

  input  wire                                i_acks_to_process,
  input  wire [C_NUM_QP -1: 0]               i_osq_timed_out,       // Outstanding Q timed out; sticky bit
  input  wire [C_NUM_QP -1: 0]               i_osq_rnr_nacked,       // QP RNR nacked
  output wire [C_NUM_QP -1: 0]               o_clr_timeout_n_nack,         // Clear for i_osq_timed_out and i_osq_nacked
  output wire [C_NUM_QP -1: 0]               o_clr_pending_ack,         // Clear for i_osq_timed_out and i_osq_nacked
  output wire                                o_arbitrate,
  input  wire                                i_arbitration_done,
  input  wire [C_QP_INDX_WIDTH -1:0]         i_arbitrated_indx,
  output wire [C_QP_INDX_WIDTH -1:0]         o_sampled_arbitrated_indx,
  output wire [C_QP_INDX_WIDTH -1:0]         o_arbitrated_qp_for_intr,
  output wire                                o_phase_to_update_post_retry,

  output wire [31:0]                         o_resp_hndler_sts,
  output wire [31:0]                         o_stat_retry_count,

  input  wire                                i_bypass_en,
  input  wire [C_NUM_QP -1: 0]               i_qp_fatal,
  input  wire 				     i_dma_in_idle,

  input  wire [C_NUM_QP -1: 0]               i_first_outgoing_pkt,
  input  wire [C_OSQ_PSN_WIDTH-1:0]          i_wqe_send_start_psn,
  input  wire [C_QP_INDX_WIDTH-1:0]          i_wqe_qpid,                      // QP ID of WQE
  input  wire                                i_wqe_push_req,                  // request from WQE Processor to push WQE

  output wire                                o_pop_osq,
  output wire                                o_pop_mpsn,
  input  wire                                i_osq_empty,
  input  wire                                i_mpsnbuf_empty,
  input  wire                                i_phase_bit_acknack_psn,
  input  wire [7:0]		             i_osq_entry_msn,
  input  wire [C_OSQ_PSN_WIDTH-1:0]          i_osq_entry_end_psn,
  input  wire [C_OSQ_PSN_WIDTH-1:0]          i_osq_entry_start_psn,
  input  wire [23:0]                         i_osq_acknacked_psn,
  input  wire [23:0]                         i_osq_acknacked_msn,
  input  wire [23:0]                         i_osq_last_acknacked_psn,
  input  wire [ 7:0]                         i_osq_opcode,                    // BTH.Opcode of outbound request
  input  wire [15:0]                         i_osq_wrid,
  input  wire [14:0]                         i_osq_wqe_data_bufid,
  input  wire                                i_osq_wqe_retried,
  input  wire                                i_osq_nacked,
  input  wire                                i_osq_wqe_nack_resp,
  output wire [23:0]                         o_psn_to_retry,
  output wire [23:0]                         o_msn_to_retry,
  output wire                                o_freeup_data_buf,               // Freeup RDMA WRITE DATA buffer

  output wire                                o_qp_cq_ba_req,
  input  wire [C_M_AXI_ADDR_WIDTH -1:0]      i_qp_cq_ba,                      // CQ base address
  input  wire                                i_qp_cq_ba_valid,
  output wire                                o_qp_cq_depth_req,
  input  wire                                i_qp_cq_depth_valid,             // CQ depth
  input  wire [15:0]                         i_qp_cq_depth,
  output wire                                o_qp_sq_cmpldb_addr_req,
  input  wire                                i_qp_sq_cmpldb_addr_valid,       // SQ Completion DB address (points to RDMAif register)
  input  wire [C_M_AXI_ADDR_WIDTH -1:0]      i_qp_sq_cmpldb_addr,

  output wire                                o_qp_cq_hdptr_req,
  input  wire                                i_qp_cq_hdptr_valid,             // CQ head pointer
  input  wire [15:0]                         i_qp_cq_hdptr,
  output wire [15:0]                         o_qp_cq_hdptr,
  output wire                                o_qp_cq_hdptr_wrn,

  output wire                                o_qp_conf_req,
  input  wire                                i_qp_conf_valid,
  input  wire [31:0]                         i_qp_conf,

  output wire                                o_qp_sq_ba_req,
  input  wire                                i_qp_sq_ba_valid,
  input  wire [31:0]                         i_qp_sq_ba,

  input  wire                                i_rd_rsp_wr_done,
  input  wire [C_QP_INDX_WIDTH-1:0]	     i_rd_rsp_qpid,

  // Generic config
  input  wire [31:0]                         i_data_buf_ba,
  input  wire [15:0]                         i_data_buf_sz,

  // Completion interrupt
  input  wire                                i_intr_clr_wqe_cmpl,
  output wire                                o_intr_wqe_cmpl_sts,

  output wire [C_QP_INDX_WIDTH -1 :0]        o_retransmit_qpid,         // QP id for this retransmission is required
  output wire                                o_retransmit_reqd,         // Retransmission is required
  input  wire                                i_retransmit_accepted,         // Ack from QP manager that the retransmission is initiated

  // Hardware handshake ports for NVMof (only enabled if QP_CONF[4] is set to 0)
  output wire                                o_send_cq_db_cnt_valid,
  output wire [C_M_AXI_ADDR_WIDTH -1:0]      o_send_cq_db_addr,
  output wire [31:0]                         o_send_cq_db_cnt,
  input  wire                                i_send_cq_db_rdy,

  input  wire                                i_bus2ip_data_rdy,
  input  wire                                i_axi_master_done,
  output wire                                o_ip2bus_wen,                    // Write en to AXI master
  output wire [C_M_AXI_ADDR_WIDTH -1:0]      o_ip2bus_wraddr,                 // Write address
  output wire [IP2BUS_LEN_WIDTH -1:0]        o_ip2bus_len,
  output wire [511:0]                        o_ip2bus_data
);

`include "rdma_macros.vh"

localparam CQE_ENTRY_SIZE = 4; // Entry size in Bytes

localparam RDMA_WRITE = 8'b00000000; // This is the opcode of the WQE

// ------------------------------------
// |BYTE4-|BYTE3-|BYTE2-|BYTE1-|BYTE0-|
// |------|------|------|-------------|
// | Flags| Rsvd | OPC  |  WRID       |
// |------|------|------|-------------|

localparam IDLE                     = 5'b00000;
localparam GET_ARBITRATED_OSQ       = 5'b00001;
localparam CHECK_ERROR              = 5'b00010;
localparam GET_QP_DATA              = 5'b00011;
localparam WRITE_CQE                = 5'b00100;
localparam INCR_CQ_CNT_UPD_DB       = 5'b00101;
localparam POP_OSQ                  = 5'b00110;
localparam CHECK_OSQ                = 5'b00111;
localparam ARBITRATE_OSQ            = 5'b01000;
localparam RETRANSMIT               = 5'b01001;
localparam WRITE_CMPL_CNT           = 5'b01010;
localparam FLUSH_POP_OSQ            = 5'b01011;
localparam WAIT_VALID_DATA          = 5'b01100;
localparam UPD_CQHD                 = 5'b01101;
localparam WAIT_VALID_DATA2         = 5'b01110;
localparam CHECK_FLUSH_OSQ          = 5'b01111;
localparam REWRITE_SQ               = 5'b10000;
localparam START_RETRANSMIT         = 5'b10001;
localparam WRITE_CMPL_CNT_PRENACK   = 5'b10010;
localparam FLUSH_POP_MPSNBUF        = 5'b10011;
localparam CHECK_FLUSH_MPSNBUF      = 5'b10100;
localparam START_RETRANSMIT_QPM     = 5'b10101;
localparam UPD_PHASE_BIT            = 5'b10110;
localparam UPD_PHASE_BIT2           = 5'b10111;
localparam GET_WRITE_QP_DATA        = 5'b11000;
localparam WAIT_AXI_DONE            = 5'b11001;
localparam WAIT_OSQ_STABLE          = 5'b11010;
localparam WAIT_DATA_STABLE         = 5'b11011;
localparam WAIT_AXI_DONE_CQ         = 5'b11100;
localparam WAIT_AXI_DONE_CQ_RETRANSMIT = 5'b11101;

localparam QP1 = 'd1;
localparam QP0 = 'd0;

localparam SQ_ENTRY_SIZE = 64; // 64 Bytes

localparam CQE_DB_SZ_IN_BYTES = 4; // Bytes
localparam SQ_REWRITE_SZ_IN_BYTES = 12; // Bytes

reg [4:0] resp_h_ns;
reg [4:0] resp_h_cs;
reg [C_M_AXI_ADDR_WIDTH -1:0] qp_cq_ba_ff;                      // CQ base address
reg [15:0] qp_cq_depth_ff;
reg [15:0] qp_cq_hdptr_ff;
reg [15:0] rewrite_sq_ptr_ff;
reg [C_M_AXI_ADDR_WIDTH -1:0] qp_sq_cmpldb_addr_ff;
reg [31:0] cq_dbcount_ff;
reg [31:0] cq_dbcount;
reg [C_NUM_QP -1 :0] clr_timeout_n_nack_ff;
reg [C_QP_INDX_WIDTH -1:0] arbitrated_indx_ff;
reg [C_QP_INDX_WIDTH -1:0] arbitrated_indx_2ff;
reg [C_QP_INDX_WIDTH -1:0] arbitrated_qp_for_cmpl;
reg [C_OS_Q_INDX_WIDTH:0] rd_resp_last_wr_done_cnt [0: C_NUM_QP-1];
reg osq_empty_ff;
reg osq_empty_2ff;
reg wqe_cmpl_intr_sts;
reg completion_posted;
reg completion_posted_2ff;
reg qp_cq_intr_en_ff;
reg qp_hw_hndshk_dis_ff;
reg qp_cqe_write_en_ff;
reg [31:0] qp_sq_ba_ff;
reg [31:0] data_buf_addr_ff;
reg [31:0] data_buf_addr_2ff;
reg [23:0] psn_to_retry;
reg [23:0] osq_acknacked_psn_sampled;
reg [23:0] osq_last_acknacked_psn_sampled;
reg [7:0] msn_to_retry;
reg [23:0] timeout_psn_to_retry_ff;
reg [23:0] timeout_psn_to_retry;
reg [C_OSQ_PSN_WIDTH-1:0] last_osq_psn_ff [C_NUM_QP -1:0];
reg osq_wqe_nack_resp_ff;
reg [C_NUM_QP -1 :0] phase_bit_osq_psn_ff;
// During retransmit the phase bit might flip, if the packet that needs to be
// retried is from a different phase. So, the phase bit ff should be updated
// just after retrnsmit is initiated.
reg upd_phase_post_retransmit;
reg upd_phase_post_retransmit_ff;
reg osq_nacked_sampled;
reg phase_bit_acknack_psn_sampled;
reg [31:0] retry_count_ff;
reg [7:0]  osq_opcode_ff;
wire [23:0] osq_acknacked_psn_plus1;
wire upd_phase_retransmit_pop;
wire pop_osq;
wire osq_rnr_nacked;
wire completion_posted_posedge;
wire osq_timed_out;
wire phase_bit_osq_psn;
wire completion_accepted;
wire [C_OSQ_PSN_WIDTH-1:0] last_osq_psn_for_arbitrated_idx;
wire [C_OSQ_PSN_WIDTH-1:0] last_osq_psn[C_NUM_QP -1:0];
wire [31:0] data_buf_addr;
wire [15:0] next_rewrite_sq_ptr;
wire [C_NUM_QP -1 :0] clr_timeout_n_nack;
wire [C_NUM_QP -1 :0] clr_pending_ack;
wire [15:0] new_cq_hdptr;
wire [15:0] qp_cq_hdptr_base_0;
wire [15:0] next_sq_ptr;
wire [15:0] sq_ptr_frm_cqhd;
wire [31:0] cqe_entry;
wire [C_M_AXI_ADDR_WIDTH -1:0] cqe_axi_address;
wire [C_M_AXI_ADDR_WIDTH -1:0] sq_wqe_addr;
wire rollover_occured;
wire [7:0] error_flag;
wire [511:0] retransmit_sq_wqe;
wire no_new_ack;
wire nacked_psn_rolled_over;
wire osq_psn_rolled_over;
wire [23:0] full_psn_to_retry;
wire phase_mismatch;
wire psn_0_nacked;
reg  pending_cqdb_update;
reg  qp_fatal_flush;
genvar i;

// In case of retransmission, the data will be used from the DDR (which is
// reflected from RDMAif to DDR whenever the data is read from the RDMAif buffer).
// The WQE processor module provides the buffer pool ID which identifies the
// data buffer which houses the data for this RDMA WRITE transation. The
// resp_handler module uses this buffer ID to update the address in the WQE
// such that it points to the DDR instead of RDMAif local address.
// Please refer to the spec doc for more details. The first 16B of the WEQ
// entry (format below) is rewritten by the resp_handler
//--------|-----------------------------|           -------|-----------------------------|
// Byte 0 |       WRID/CONTEXT          |           Byte 32|                             |
// Byte 1 |_____________________________|           Byte 33|                             |
// Byte 2 |         BUFID/RESERVED   |R_|           Byte 34|                             |
// Byte 3 |_____________________________|           Byte 35|                             |
// BYte 4 |                             |           BYte 36|                             |
// Byte 5 |      LOCAL ADDRESS          |           Byte 37|                             |
// Byte 6 |                             |           Byte 38|                             |
// Byte 7 |                             |           Byte 39|       COMPLETTION INFO      |
// Byte 8 |                             |           Byte 40|                             |
// Byte 9 |                             |           Byte 41|                             |
// Byte 10|                             |           Byte 42|                             |
// Byte 11|_____________________________|           Byte 43|                             |
// Byte 12|         LENGTH              |           Byte 44|                             |
// Byte 13|                             |           Byte 45|                             |
// Byte 14|                             |           Byte 46|                             |
// Byte 15|_____________________________|           Byte 47|_____________________________|
// Byte 16|_________OPCODE______________|           Byte 48|                             |
// Byte 17|        RESERVED             |           Byte 49|                             |
// BYte 18|                             |           BYte 50|                             |
// Byte 19|_____________________________|           Byte 51|                             |
// Byte 20|                             |           Byte 52|                             |
// Byte 21|      REMOTE OFFSET          |           Byte 53|                             |
// Byte 22|                             |           Byte 54|                             |
// Byte 23|                             |           Byte 55|                             |
// Byte 24|                             |           Byte 56|        RESERVED             |
// Byte 25|                             |           Byte 57|                             |
// Byte 26|                             |           Byte 58|                             |
// Byte 27|_____________________________|           Byte 59|                             |
// Byte 28|                             |           Byte 60|                             |
// Byte 29|        REMOTE TAG           |           Byte 61|                             |
// Byte 30|                             |           Byte 62|                             |
// Byte 31|_____________________________|           Byte 63|_____________________________|

// NOrmally, the CQ doorbell value (for the SEND q) is not really used.
// The curr_sqptr value is used along with SQ PI DB to figure out the FIFO
// full/empty condition. HOwever, in case of error when re-transmission needs
// to happen, the QP retransmit module moves the curr_sqptr value to the value in
// the CQ DB value. This is not expected to happen very frequntly. Right now
// the logic in the Resp handler module waits for the QP manager to ack the
// retransmission and hence is not very pipelined. This should ideally not be
// a problem if the retransmission happens very infrequently.

always @ (posedge core_clk or negedge core_rstn)
begin
    if(~core_rstn)
    begin
        resp_h_cs <= IDLE;
    end
    else begin
        resp_h_cs <= resp_h_ns;
    end
end

always @(*)
begin
    resp_h_ns <= resp_h_cs;
    cq_dbcount <= cq_dbcount_ff;
    case (resp_h_cs)

        IDLE:
        begin
            cq_dbcount <= 'd0;
            if (i_acks_to_process) begin
                resp_h_ns <= GET_ARBITRATED_OSQ;
            end
        end

        // BY default the arbiter will work and get a valid OSQ to work on, so
        // no need to ask to arbitrate
        GET_ARBITRATED_OSQ:
        begin
            if (i_arbitration_done) begin
                resp_h_ns <= WAIT_VALID_DATA;
            end
        end

        WAIT_VALID_DATA:
        begin
            resp_h_ns <= WAIT_VALID_DATA2;
        end

        WAIT_VALID_DATA2:
        begin
            resp_h_ns <= UPD_PHASE_BIT;
        end

        UPD_PHASE_BIT:
        begin
            // Handle a case where the osq just became non-empty; wait one
            // more cycle
            if (osq_empty_2ff & ~osq_empty_ff)
                resp_h_ns <= UPD_PHASE_BIT;
            else
                resp_h_ns <= CHECK_ERROR;
        end

        CHECK_ERROR:
        begin
            // QP1 is UD so no ack expected. In bypass mode also the ACKs are
            // sent directly to bypass buffer, hence in bypass mode the WQEs
            // are completed as soon as the command is completed by the WQE
            // processor
            // In case there is a fatal error on the QP, all the WQEs posted
            // on that outstanding Q needs to be completed in error
            if (arbitrated_indx_ff == QP0 || (no_new_ack & ~osq_timed_out & ~osq_nacked_sampled & ~i_qp_fatal[arbitrated_indx_ff]))
                resp_h_ns <= ARBITRATE_OSQ;
            // we cannot retry it.
            // response the processing of this QP needs to wait
            else if (~pending_cqdb_update & ((i_osq_rnr_nacked[arbitrated_indx_ff] & ~osq_timed_out) || ((osq_nacked_sampled | osq_timed_out) & ~osq_wqe_nack_resp_ff)))
                resp_h_ns <= ARBITRATE_OSQ;
            else if ((arbitrated_indx_ff == QP1) || i_bypass_en || (i_qp_fatal[arbitrated_indx_ff] & i_dma_in_idle) || pending_cqdb_update)
                resp_h_ns <= GET_QP_DATA;
            else if (i_qp_fatal[arbitrated_indx_ff] & ~i_dma_in_idle)
                resp_h_ns <= ARBITRATE_OSQ;
            else if (psn_0_nacked) begin // See comment below***
                if ((i_osq_entry_end_psn < i_osq_entry_start_psn) | (i_osq_entry_start_psn == 'b0)) // case 1, case 2
                    resp_h_ns <= START_RETRANSMIT;
                else // case 3
                    resp_h_ns <= GET_QP_DATA;
            end
            else if (((i_osq_entry_end_psn > (osq_acknacked_psn_sampled[C_OSQ_PSN_WIDTH-1:0])) & osq_timed_out & ~phase_mismatch) |
                    ((i_osq_entry_end_psn < (osq_acknacked_psn_sampled[C_OSQ_PSN_WIDTH-1:0])) & osq_timed_out & phase_mismatch))
                resp_h_ns <= START_RETRANSMIT;
            else if (((i_osq_entry_end_psn >= (osq_acknacked_psn_sampled[C_OSQ_PSN_WIDTH-1:0])) & (osq_nacked_sampled | osq_rnr_nacked) & ~phase_mismatch) |
                    ((i_osq_entry_end_psn <= (osq_acknacked_psn_sampled[C_OSQ_PSN_WIDTH-1:0])) & (osq_nacked_sampled | osq_rnr_nacked) & phase_mismatch))
                resp_h_ns <= START_RETRANSMIT;
            else if (((i_osq_entry_end_psn > osq_acknacked_psn_sampled[C_OSQ_PSN_WIDTH-1:0]) && ~phase_mismatch) ||
                    (i_osq_empty || osq_empty_ff || osq_empty_2ff))
                resp_h_ns <= ARBITRATE_OSQ;
            else if ((i_osq_entry_end_psn < osq_acknacked_psn_sampled[C_OSQ_PSN_WIDTH-1:0]) && phase_mismatch)
                resp_h_ns <= ARBITRATE_OSQ;
            else
                resp_h_ns <= GET_QP_DATA;
        end
        // ***Nack for PSN 0 is a special case and needs to be handled
        // separately. It is so because of multiple reasons - no OSQ PSN can
        // be greater than 0 - so normal conditions cannot be applied.
        // Secondly when the NACKed psn is 0, the phase bit needs to go back
        // as the last valid acked PSN would be before roll over.
        // There are 3 different cases for psn 0 nacked
        // SPSN denotes start PSN, EPSN denotes end PSN and "|" denotes
        // rollover point
        // (1)SPSN.................| nack0...EPSN         => EPSN is > 0 on the rolled over side
        // (2).....................| nack0/SPSN...EPSN    => SPSN is 0, EPSN > 0
        // (3)SPSN1 EPSN1 SPSN2....| nack0...EPSN2        => EPSN1 needs to be completed, SPSN2 needs to be retried

        GET_QP_DATA:
        begin
            if ( i_qp_cq_ba_valid & i_qp_cq_depth_valid & i_qp_cq_hdptr_valid & i_qp_conf_valid)
                resp_h_ns <= WRITE_CQE;
        end

        GET_WRITE_QP_DATA:
        begin
            if (i_qp_sq_ba_valid & i_qp_cq_hdptr_valid & i_qp_cq_depth_valid)
                resp_h_ns <= WAIT_DATA_STABLE;
        end

        WAIT_DATA_STABLE:
        begin
            resp_h_ns <= RETRANSMIT;
        end

        WRITE_CQE:
        begin
            if (i_bus2ip_data_rdy | ~qp_cqe_write_en_ff) begin
                resp_h_ns <= INCR_CQ_CNT_UPD_DB;
            end
        end
        // RDMAif module requires the number of completions, instead of the CQ
        // doorbell. Hence the counts are added up for all pending completions
        // in one QP
        INCR_CQ_CNT_UPD_DB:
        begin
            if (i_send_cq_db_rdy || qp_hw_hndshk_dis_ff) begin
                cq_dbcount <= cq_dbcount_ff + 1'b1;
                resp_h_ns <= UPD_CQHD;
            end
        end

        UPD_CQHD:
        begin
            if (i_qp_cq_hdptr_valid)
                resp_h_ns <= POP_OSQ;
        end

        POP_OSQ:
        begin
            resp_h_ns <= UPD_PHASE_BIT2;
        end

        UPD_PHASE_BIT2:
        begin
            // Handle a case where the osq just became non-empty; wait one
            // more cycle
            if (osq_empty_2ff & ~osq_empty_ff)
                resp_h_ns <= UPD_PHASE_BIT2;
            else
                resp_h_ns <= CHECK_OSQ;

        end

        CHECK_OSQ:
        begin
            if ((i_osq_rnr_nacked[arbitrated_indx_ff] & ~i_osq_timed_out[arbitrated_indx_ff]) || (i_osq_empty || osq_empty_ff || osq_empty_2ff) ||
                ((osq_nacked_sampled | osq_timed_out) & ~osq_wqe_nack_resp_ff))
                resp_h_ns <= WRITE_CMPL_CNT;
            else if (i_qp_fatal[arbitrated_indx_ff])
                resp_h_ns <= CHECK_ERROR;

            // A nack for packet n actually means ack for all packets till
            // n-1. So, the previous acked packets need to be completed and
            // the corresponding count needs to be written before starting
            // retry
            else if (psn_0_nacked) begin // See comment above***
                if ((i_osq_entry_end_psn < i_osq_entry_start_psn) | (i_osq_entry_start_psn == 'b0)) // case 1, case 2
                    resp_h_ns <= WRITE_CMPL_CNT_PRENACK; //START_RETRANSMIT;
                else // case 3
                    resp_h_ns <= GET_QP_DATA;
            end
            else if (((i_osq_entry_end_psn > (osq_acknacked_psn_sampled[C_OSQ_PSN_WIDTH-1:0])) && osq_timed_out && ~phase_mismatch) |
                ((i_osq_entry_end_psn < (osq_acknacked_psn_sampled[C_OSQ_PSN_WIDTH-1:0])) && osq_timed_out & phase_mismatch))
                resp_h_ns <= WRITE_CMPL_CNT_PRENACK;
            else if (((i_osq_entry_end_psn >= (osq_acknacked_psn_sampled[C_OSQ_PSN_WIDTH-1:0])) && (osq_nacked_sampled | osq_rnr_nacked) && ~phase_mismatch) |
                ((i_osq_entry_end_psn <= (osq_acknacked_psn_sampled[C_OSQ_PSN_WIDTH-1:0])) && (osq_nacked_sampled | osq_rnr_nacked) && phase_mismatch))
                resp_h_ns <= WRITE_CMPL_CNT_PRENACK;
            else if ((i_osq_entry_end_psn > osq_acknacked_psn_sampled[C_OSQ_PSN_WIDTH-1:0]) && ~phase_mismatch) // no more completed WQEs to process
                resp_h_ns <= WRITE_CMPL_CNT;
            else if ((i_osq_entry_end_psn < osq_acknacked_psn_sampled[C_OSQ_PSN_WIDTH-1:0]) && phase_mismatch)
                resp_h_ns <= WRITE_CMPL_CNT;
            else
                resp_h_ns <= CHECK_ERROR;
        end

        WRITE_CMPL_CNT_PRENACK:
        begin
            if (i_bus2ip_data_rdy | (~qp_hw_hndshk_dis_ff))
                resp_h_ns <= WAIT_AXI_DONE_CQ_RETRANSMIT;
        end

        WRITE_CMPL_CNT:
        begin
            if (i_bus2ip_data_rdy | (~qp_hw_hndshk_dis_ff))
                resp_h_ns <= WAIT_AXI_DONE_CQ;
        end

        WAIT_AXI_DONE_CQ:
        begin
            if (i_axi_master_done | ~qp_hw_hndshk_dis_ff)
                resp_h_ns <= ARBITRATE_OSQ;
        end

        WAIT_AXI_DONE_CQ_RETRANSMIT:
        begin
            if (i_axi_master_done | ~qp_hw_hndshk_dis_ff)
                resp_h_ns <= START_RETRANSMIT;
        end

        // Before moving to IDLE ask the Arbiter to arbitrate and get the next
        ARBITRATE_OSQ:
        begin
            resp_h_ns <= IDLE;
        end

        START_RETRANSMIT:
        begin
                resp_h_ns <= GET_WRITE_QP_DATA;
        end

        RETRANSMIT:
        begin
            if (i_osq_opcode == RDMA_WRITE & ~i_osq_wqe_retried & C_EN_WR_RETRY_DATA_BUF)
                resp_h_ns <= REWRITE_SQ;
            else
                resp_h_ns <= FLUSH_POP_OSQ;
        end

        REWRITE_SQ:
        begin
            if (i_bus2ip_data_rdy)
                resp_h_ns <= WAIT_AXI_DONE;
        end

        WAIT_AXI_DONE:
        begin
            if (i_axi_master_done)
                resp_h_ns <= FLUSH_POP_OSQ;
        end

        FLUSH_POP_OSQ:
        begin
            resp_h_ns <= WAIT_OSQ_STABLE;
        end

        WAIT_OSQ_STABLE:
        begin
            resp_h_ns <= CHECK_FLUSH_OSQ;
        end

        CHECK_FLUSH_OSQ:
        begin
            if (i_osq_empty)
                resp_h_ns <= FLUSH_POP_MPSNBUF;
            else
                resp_h_ns <= RETRANSMIT;
        end

        FLUSH_POP_MPSNBUF:
        begin
            resp_h_ns <= CHECK_FLUSH_MPSNBUF;
        end

        CHECK_FLUSH_MPSNBUF:
        begin
            if (i_mpsnbuf_empty)
                resp_h_ns <= START_RETRANSMIT_QPM;
            else
                resp_h_ns <= FLUSH_POP_MPSNBUF;
        end

        START_RETRANSMIT_QPM:
        begin
            if (i_retransmit_accepted)
                resp_h_ns <= ARBITRATE_OSQ;
        end

    endcase
end

assign osq_rnr_nacked = i_osq_rnr_nacked[arbitrated_indx_ff];

assign osq_acknacked_psn_plus1 = osq_acknacked_psn_sampled[23:0] + 1'b1;

`MSFF_R(osq_wqe_nack_resp_ff, i_osq_wqe_nack_resp, core_clk, ~core_rstn)

`MSFF_R(msn_to_retry, (resp_h_cs == START_RETRANSMIT) ? i_osq_entry_msn : msn_to_retry, core_clk, ~core_rstn)
`MSFF_R(psn_to_retry, (resp_h_cs == START_RETRANSMIT) ? full_psn_to_retry : psn_to_retry[23:0], core_clk, ~core_rstn)

`MSFF_R(retry_count_ff, (((resp_h_cs == START_RETRANSMIT_QPM) & i_retransmit_accepted) ?
                                            (~(&retry_count_ff) ? (retry_count_ff + 1'b1) : retry_count_ff) : retry_count_ff), core_clk, ~core_rstn)
assign o_stat_retry_count = retry_count_ff;

//--- sample incoming acknack data -----//
// The reason why these values need to be sampled is to avoid the possibility
// of an ack coming while the FSM is in progress for the same QP, in which case some values
// may not be consistent denepding on when the ack was received.
`MSFF_R(osq_acknacked_psn_sampled, ((resp_h_cs != WAIT_VALID_DATA2) && (resp_h_cs != UPD_PHASE_BIT) && (resp_h_cs != UPD_PHASE_BIT2) && (resp_h_cs != CHECK_OSQ)) ?
                                            i_osq_acknacked_psn : osq_acknacked_psn_sampled, core_clk, ~core_rstn)

`MSFF_R(osq_last_acknacked_psn_sampled, ((resp_h_cs != WAIT_VALID_DATA2) && (resp_h_cs != UPD_PHASE_BIT) && (resp_h_cs != UPD_PHASE_BIT2) && (resp_h_cs != CHECK_OSQ)) ?
                                            i_osq_last_acknacked_psn : osq_last_acknacked_psn_sampled, core_clk, ~core_rstn)

// The phase bit gets updated one clock cycle after the incoming PSN. So, if
// the PSN was updated, we need to give one extra clock cycle for the phase to
// get updated
`MSFF_R(phase_bit_acknack_psn_sampled, (/*(resp_h_cs != WAIT_VALID_DATA2) &*/ (resp_h_cs != UPD_PHASE_BIT) && /*(resp_h_cs != UPD_PHASE_BIT2) &&*/ (resp_h_cs != CHECK_OSQ)) ?
                                            i_phase_bit_acknack_psn : phase_bit_acknack_psn_sampled, core_clk, ~core_rstn)

`MSFF_R(osq_nacked_sampled, ((resp_h_cs != WAIT_VALID_DATA2) && (resp_h_cs != UPD_PHASE_BIT) && (resp_h_cs != UPD_PHASE_BIT2) && (resp_h_cs != CHECK_OSQ)) ?
                                            i_osq_nacked : osq_nacked_sampled, core_clk, ~core_rstn)

assign nacked_psn_rolled_over = (((osq_acknacked_psn_sampled[C_OSQ_PSN_WIDTH-1:0] < i_osq_entry_start_psn)/* | psn_0_nacked*/)) ? 1'b1 : 1'b0;

assign osq_psn_rolled_over = i_osq_entry_start_psn > i_osq_entry_end_psn ? 1'b1 : 1'b0;

//********************************
// 8'hfd
// 8'hfe
// 8'hff___
// 8'h00    osq_start_psn
// 8'h01    acknacked_psn
// 8'h02    osq_end_psn
// *******************************
//********************************
// 8'hfd
// 8'hfe
// 8'hff___ acknacked_psn
// 8'h00    osq_start_psn
// 8'h01    osq_end_psn
// 8'h02
// *******************************
//********************************
// 8'hfd
// 8'hfe    osq_start_psn
// 8'hff___
// 8'h00    acknacked_psn
// 8'h01    osq_end_psn
// 8'h02
// *******************************
//********************************
// 8'hfd
// 8'hfe    osq_start_psn
// 8'hff___ acknacked_psn
// 8'h00
// 8'h01    osq_end_psn
// 8'h02
// *******************************
always @(*)
begin
    case ({osq_psn_rolled_over, phase_mismatch})
        2'b00: timeout_psn_to_retry <= {osq_acknacked_psn_sampled[23:C_OSQ_PSN_WIDTH], i_osq_entry_start_psn};
        2'b01: timeout_psn_to_retry <= {osq_acknacked_psn_plus1[23:C_OSQ_PSN_WIDTH], i_osq_entry_start_psn};
        2'b10: timeout_psn_to_retry <= {(osq_acknacked_psn_sampled[23:C_OSQ_PSN_WIDTH] -1'b1), i_osq_entry_start_psn};
        2'b11: timeout_psn_to_retry <= {osq_acknacked_psn_sampled[23:C_OSQ_PSN_WIDTH], i_osq_entry_start_psn};
    endcase
end

`MSFF_R(timeout_psn_to_retry_ff, timeout_psn_to_retry , core_clk, ~core_rstn)

assign full_psn_to_retry = (nacked_psn_rolled_over && (~osq_timed_out || osq_rnr_nacked)) ? {(osq_acknacked_psn_sampled[23:C_OSQ_PSN_WIDTH] -1'b1), i_osq_entry_start_psn} :
                           (osq_timed_out  ?  timeout_psn_to_retry_ff : {osq_acknacked_psn_sampled[23:C_OSQ_PSN_WIDTH], i_osq_entry_start_psn});

assign o_msn_to_retry = {i_osq_acknacked_msn[23:8], msn_to_retry};
assign o_psn_to_retry = psn_to_retry;//{i_osq_acknacked_psn[23:8], psn_to_retry};

assign completion_accepted = (((resp_h_cs == WAIT_AXI_DONE_CQ) || (resp_h_cs == WAIT_AXI_DONE_CQ_RETRANSMIT)) && (i_axi_master_done | (~qp_hw_hndshk_dis_ff)));

`MSFF_R(completion_posted, (((i_bus2ip_data_rdy || (~qp_hw_hndshk_dis_ff)) && ((resp_h_cs == WRITE_CMPL_CNT) || (resp_h_cs == WRITE_CMPL_CNT_PRENACK))) ? 1'b1 :
                                                    (completion_accepted ? 1'b0 : completion_posted)), core_clk, ~core_rstn)

// acceepted.
`MSFF_R(completion_posted_2ff, completion_posted, core_clk, ~core_rstn)
`MSFF_R(arbitrated_qp_for_cmpl, (completion_posted ? arbitrated_qp_for_cmpl : arbitrated_indx_ff), core_clk, ~core_rstn)

assign completion_posted_posedge = completion_posted && (completion_posted ^ completion_posted_2ff);

assign o_intr_wqe_cmpl_sts = completion_accepted && qp_cq_intr_en_ff;//wqe_cmpl_intr_sts;

assign osq_timed_out = i_osq_timed_out[arbitrated_indx_ff];

assign psn_0_nacked = (osq_nacked_sampled || osq_rnr_nacked) && (osq_acknacked_psn_sampled[C_OSQ_PSN_WIDTH-1:0] == 'b0);
assign o_arbitrated_qp_for_intr = arbitrated_indx_2ff;//arbitrated_qp_for_cmpl;

`MSFF_R(qp_cq_ba_ff,          (i_qp_cq_ba_valid          ? i_qp_cq_ba          : qp_cq_ba_ff),          core_clk, ~core_rstn)
`MSFF_R(qp_cq_depth_ff,       (i_qp_cq_depth_valid       ? i_qp_cq_depth       : qp_cq_depth_ff),       core_clk, ~core_rstn)
`MSFF_R(qp_cq_hdptr_ff,       (i_qp_cq_hdptr_valid       ? i_qp_cq_hdptr       : qp_cq_hdptr_ff),       core_clk, ~core_rstn)
`MSFF_R(qp_sq_cmpldb_addr_ff, (i_qp_sq_cmpldb_addr_valid ? i_qp_sq_cmpldb_addr : qp_sq_cmpldb_addr_ff), core_clk, ~core_rstn)
`MSFF_R(qp_cq_intr_en_ff,     (i_qp_conf_valid           ? i_qp_conf[3]        : qp_cq_intr_en_ff),     core_clk, ~core_rstn)
`MSFF_R(qp_hw_hndshk_dis_ff,  (i_qp_conf_valid           ? i_qp_conf[4]        : qp_hw_hndshk_dis_ff),  core_clk, ~core_rstn)
`MSFF_R(qp_cqe_write_en_ff,   (i_qp_conf_valid           ? i_qp_conf[5]        : qp_cqe_write_en_ff),   core_clk, ~core_rstn)
`MSFF_R(qp_sq_ba_ff,          (i_qp_sq_ba_valid          ? i_qp_sq_ba          : qp_sq_ba_ff),          core_clk, ~core_rstn)

`MSFF_R(arbitrated_indx_ff, ((i_arbitration_done && (resp_h_cs == GET_ARBITRATED_OSQ)) ? i_arbitrated_indx : arbitrated_indx_ff), core_clk, ~core_rstn)

`MSFF_R(arbitrated_indx_2ff, arbitrated_indx_ff, core_clk, ~core_rstn)

`MSFF_R(cq_dbcount_ff, cq_dbcount, core_clk, ~core_rstn)

`MSFF_R(osq_empty_ff, i_osq_empty, core_clk, ~core_rstn)
`MSFF_R(osq_empty_2ff, osq_empty_ff, core_clk, ~core_rstn)

assign o_retransmit_reqd = (resp_h_cs == START_RETRANSMIT_QPM) ? 1'b1 : 1'b0;
assign o_retransmit_qpid = arbitrated_indx_ff;

// Rollover can occur on the incoming ack nacked psn and also the osq psn.
// When both rollovers occur, they cancel each other.
assign rollover_occured = ((osq_last_acknacked_psn_sampled[C_OSQ_PSN_WIDTH-1:0]  > i_osq_acknacked_psn[C_OSQ_PSN_WIDTH-1:0])) ? 1'b1 : 1'b0;
assign no_new_ack = ((i_osq_last_acknacked_psn[C_OSQ_PSN_WIDTH-1:0] == i_osq_acknacked_psn[C_OSQ_PSN_WIDTH-1:0]) && (arbitrated_indx_ff != QP1) && ~i_bypass_en) ? 1'b1 : 1'b0;
assign last_osq_psn_for_arbitrated_idx = last_osq_psn_ff[arbitrated_indx_ff];

genvar j;
generate
    for (j=0; j<C_NUM_QP; j=j+1) begin: gen_lastacknack_osq_psn
        assign last_osq_psn[j] = (i_first_outgoing_pkt[j] & i_wqe_push_req & (i_wqe_qpid == j)) ? (i_wqe_send_start_psn - 1'b1) :
                                 (((j == arbitrated_indx_ff) & ~(i_osq_empty | osq_empty_ff | osq_empty_2ff) &((resp_h_cs == UPD_PHASE_BIT) || (resp_h_cs == UPD_PHASE_BIT2))) ?
                                  i_osq_entry_end_psn : (((j == arbitrated_indx_ff) & (resp_h_cs == RETRANSMIT)) ? psn_to_retry - 1'h1 : last_osq_psn_ff[j]));
        `MSFF_R(last_osq_psn_ff[j], last_osq_psn[j], core_clk, ~core_rstn)

        //`MSFF_R(phase_bit_osq_psn_ff[j], (((j == arbitrated_indx_ff) & ((resp_h_cs == UPD_PHASE_BIT ) || (resp_h_cs == UPD_PHASE_BIT2) | upd_phase_retransmit_pop)) ?
        `MSFF_R(phase_bit_osq_psn_ff[j], (i_first_outgoing_pkt[j] ? 1'b0 : (((j == arbitrated_indx_ff) & ((resp_h_cs == UPD_PHASE_BIT ) || (resp_h_cs == UPD_PHASE_BIT2) | upd_phase_retransmit_pop)) ?
                                    phase_bit_osq_psn : phase_bit_osq_psn_ff[j])), core_clk, ~core_rstn)
    end
endgenerate

assign phase_bit_osq_psn = ((i_osq_entry_end_psn < last_osq_psn_for_arbitrated_idx) & ~(i_osq_empty | osq_empty_ff | osq_empty_2ff)) ? ~phase_bit_osq_psn_ff[arbitrated_indx_ff] :
                                                                                                       phase_bit_osq_psn_ff[arbitrated_indx_ff];

assign phase_mismatch = (phase_bit_acknack_psn_sampled ^ phase_bit_osq_psn_ff[arbitrated_indx_ff]);

// This signal is used to update the acknacked_psn post retry. After retry is
// initiated, the psn of both the osq psn and acknacked_psn should match.
assign o_phase_to_update_post_retry = phase_bit_osq_psn_ff[arbitrated_indx_ff];

`MSFF_R(upd_phase_post_retransmit, ((resp_h_cs == START_RETRANSMIT) ? 1'b1 : (pop_osq ? 1'b0 : upd_phase_post_retransmit)) , core_clk, ~core_rstn)
assign upd_phase_retransmit_pop = upd_phase_post_retransmit & pop_osq;
//`MSFF_R(upd_phase_post_retransmit_ff, upd_phase_post_retransmit , core_clk, ~core_rstn)

assign new_cq_hdptr = (qp_cq_hdptr_ff == qp_cq_depth_ff) ? 16'h1 : (qp_cq_hdptr_ff + 1'b1); // Updated CQ headpointer

assign qp_cq_hdptr_base_0 = (qp_cq_hdptr_ff == qp_cq_depth_ff) ? 16'h0 : qp_cq_hdptr_ff;
assign cqe_axi_address =  qp_cq_ba_ff + (qp_cq_hdptr_base_0 * CQE_ENTRY_SIZE);

// Since the CQ and SQ depths are same and the last completed SQ WQE is
// signified by the CQ head pointer, the next SQ WQE that needs to be
// rewritten can be got from the CQ head pointer.
assign next_rewrite_sq_ptr = (resp_h_cs == WAIT_DATA_STABLE) ? sq_ptr_frm_cqhd : ((resp_h_cs == FLUSH_POP_OSQ) ? next_sq_ptr : rewrite_sq_ptr_ff) ;
assign next_sq_ptr = ((rewrite_sq_ptr_ff + 1'b1) < qp_cq_depth_ff) ? (rewrite_sq_ptr_ff + 1'b1) :16'b0;
`MSFF_R(rewrite_sq_ptr_ff, next_rewrite_sq_ptr, core_clk, ~core_rstn)

// this is to take care of the case when even the first command has not
// completed. So CQHD is 0 (in no other case the CQHD will be 0). IN this case
// dont do -1 just use the 0 value.
assign sq_ptr_frm_cqhd = (qp_cq_hdptr_ff == qp_cq_depth_ff) ? 16'b0 : qp_cq_hdptr_ff;

assign o_arbitrate = (resp_h_cs == ARBITRATE_OSQ) ? 1'b1 : 1'b0;
assign o_sampled_arbitrated_indx = arbitrated_indx_ff;

assign error_flag = {7'b0, i_qp_fatal[arbitrated_indx_ff]};
assign cqe_entry = {480'h0, error_flag, i_osq_opcode, i_osq_wrid}; // 512 - 32 = 480;

assign o_ip2bus_data =  (((resp_h_cs == WRITE_CMPL_CNT) || (resp_h_cs == WRITE_CMPL_CNT_PRENACK)) & qp_hw_hndshk_dis_ff) ?
                                                            {480'h0, cq_dbcount_ff} : ((resp_h_cs == REWRITE_SQ) ? retransmit_sq_wqe : cqe_entry);
assign o_ip2bus_wraddr =(((resp_h_cs == WRITE_CMPL_CNT) || (resp_h_cs == WRITE_CMPL_CNT_PRENACK)) & qp_hw_hndshk_dis_ff) ?
                                                            qp_sq_cmpldb_addr_ff : ((resp_h_cs == REWRITE_SQ) ? sq_wqe_addr : cqe_axi_address);
assign o_ip2bus_wen  =  ((((resp_h_cs == WRITE_CMPL_CNT) || (resp_h_cs == WRITE_CMPL_CNT_PRENACK)) & qp_hw_hndshk_dis_ff) ||
                                ((resp_h_cs == WRITE_CQE) & qp_cqe_write_en_ff) || (resp_h_cs == REWRITE_SQ)) ? 1'b1 : 1'b0;
assign o_ip2bus_len  =  ((((resp_h_cs == WRITE_CMPL_CNT) || (resp_h_cs == WRITE_CMPL_CNT_PRENACK)) & qp_hw_hndshk_dis_ff) ||
                                (resp_h_cs == WRITE_CQE)) ? CQE_DB_SZ_IN_BYTES : SQ_REWRITE_SZ_IN_BYTES;

// Direct HW handshake with NVMf ------
assign o_send_cq_db_cnt_valid = ((resp_h_cs == INCR_CQ_CNT_UPD_DB) & ~qp_hw_hndshk_dis_ff) ? 1'b1 : 1'b0;
assign o_send_cq_db_cnt = 32'h1;//cq_dbcount_ff;
assign o_send_cq_db_addr = qp_sq_cmpldb_addr_ff;

assign retransmit_sq_wqe = {416'h0, data_buf_addr_2ff, i_osq_wqe_data_bufid, 1'b1, i_osq_wrid}; // 512 - 96 (12 BYtes) = 416
assign sq_wqe_addr =  qp_sq_ba_ff + rewrite_sq_ptr_ff * SQ_ENTRY_SIZE;
assign data_buf_addr = i_data_buf_ba + i_osq_wqe_data_bufid * i_data_buf_sz;
`MSFF_R(data_buf_addr_ff, data_buf_addr, core_clk, ~core_rstn)
`MSFF_R(data_buf_addr_2ff, data_buf_addr_ff, core_clk, ~core_rstn)

assign o_qp_sq_cmpldb_addr_req  = (resp_h_cs == GET_QP_DATA) ? 1'b1 : 1'b0;
assign o_qp_cq_hdptr_req        = ((resp_h_cs == GET_QP_DATA) | (resp_h_cs == UPD_CQHD) | (resp_h_cs == GET_WRITE_QP_DATA)) ? 1'b1 : 1'b0;
assign o_qp_cq_depth_req        = ((resp_h_cs == GET_QP_DATA) | (resp_h_cs == GET_WRITE_QP_DATA)) ? 1'b1 : 1'b0;
assign o_qp_cq_ba_req           = (resp_h_cs == GET_QP_DATA) ? 1'b1 : 1'b0;
assign o_qp_sq_ba_req           = (resp_h_cs == GET_WRITE_QP_DATA) ? 1'b1 : 1'b0;
assign o_qp_conf_req            = (resp_h_cs == GET_QP_DATA) ? 1'b1 : 1'b0;

assign pop_osq = (((resp_h_cs == INCR_CQ_CNT_UPD_DB) & (i_send_cq_db_rdy || qp_hw_hndshk_dis_ff)) || (resp_h_cs == FLUSH_POP_OSQ)) ? 1'b1 : 1'b0;

assign o_pop_osq = pop_osq;

//On Qp_fatal flush all OSQ buffer and MPSN buffer entries and do not retry
assign o_pop_mpsn = ((resp_h_cs == FLUSH_POP_MPSNBUF) | ((resp_h_cs == POP_OSQ) && i_qp_fatal[arbitrated_indx_ff])) ? 1'b1 : 1'b0;

assign o_qp_cq_hdptr_wrn = (resp_h_cs == UPD_CQHD) ? 1'b1 : 1'b0;
assign o_qp_cq_hdptr = new_cq_hdptr;

assign o_freeup_data_buf = ((resp_h_cs == WRITE_CQE) & (i_osq_opcode == RDMA_WRITE) & (i_bus2ip_data_rdy | ~qp_cqe_write_en_ff)) ? 1'b1 : 1'b0;

//The clear pending ack is added due to the following reason
//In low performance cases, timeout happens even if an ack is pending to be
//processed. Keep the timeout logic under reset if the ack is not yet
//processed. Once processed, timeout can be enabled again
generate
for (i=0; i<C_NUM_QP; i=i+1) begin: clr_timeout_and_pending_ack
    assign clr_timeout_n_nack[i] = ((arbitrated_indx_ff == i) && ((resp_h_cs == START_RETRANSMIT_QPM) && i_retransmit_accepted)) ? 1'b1 : 1'b0;
    assign clr_pending_ack[i] = ((arbitrated_indx_ff == i) && ((resp_h_cs == CHECK_ERROR) && ~(osq_nacked_sampled  & ~osq_wqe_nack_resp_ff) &&
                                    (i_osq_acknacked_psn == osq_acknacked_psn_sampled))) ? 1'b1 : 1'b0;
    end
endgenerate

`MSFF_R(clr_timeout_n_nack_ff, clr_timeout_n_nack, core_clk, ~core_rstn)

always @(posedge core_clk)
 begin
   if(~core_clk)
     osq_opcode_ff <= 'h0;
   else if(resp_h_cs == GET_QP_DATA)
     osq_opcode_ff <= i_osq_opcode;
 end

always @(posedge core_clk)
 begin
   if(~core_rstn)
     pending_cqdb_update <= 'h0;
   else if(qp_hw_hndshk_dis_ff & (resp_h_cs == CHECK_OSQ) & (resp_h_ns == CHECK_ERROR) & ~i_qp_fatal[arbitrated_indx_ff])
     pending_cqdb_update <= 'h1;
   else if(resp_h_cs == CHECK_ERROR)
     pending_cqdb_update <= 'h0;
 end
//-----On QP_fatal, wqe_proc still send wqe_entries to resp_handler for error
//completions preparation, For these completions FSM should not wait for
//rd_resp_last_wr_done counter value. qp_fatal_flush will be set 1 to go ahead
//with error completions preparation
always @(posedge core_clk)
 begin
  if(~core_rstn)
    qp_fatal_flush = 'h0;
  else if((resp_h_cs == GET_QP_DATA) & i_qp_fatal[arbitrated_indx_ff])
    qp_fatal_flush = 'h1;
  else if(resp_h_cs == ARBITRATE_OSQ)
    qp_fatal_flush = 'h0;
  end

assign o_clr_timeout_n_nack = clr_timeout_n_nack_ff;
assign o_clr_pending_ack = clr_pending_ack;
assign o_resp_hndler_sts = {15'h0, i_acks_to_process, 3'h0,resp_h_cs,{(8-C_QP_INDX_WIDTH){1'b0}},arbitrated_indx_ff};

// Non-synthesizable code

  `ifdef SIMULATION
    reg [20*8-1:0] resp_h_cs_string = "null";
    reg [20*8-1:0] resp_h_ns_string = "null";

    always @* begin
      case (resp_h_cs)
         IDLE                       : resp_h_cs_string = "IDLE              " ;
         GET_ARBITRATED_OSQ         : resp_h_cs_string = "GET_ARBITRATED_OSQ";
         CHECK_ERROR                : resp_h_cs_string = "CHECK_ERROR       "      ;
         GET_QP_DATA                : resp_h_cs_string = "GET_QP_DATA       " ;
         GET_WRITE_QP_DATA          : resp_h_cs_string = "GET_WRITE_QP_DATA " ;
         WRITE_CQE                  : resp_h_cs_string = "WRITE_CQE         " ;
         INCR_CQ_CNT_UPD_DB         : resp_h_cs_string = "INCR_CQ_CNT_UPD_DB" ;
         POP_OSQ                    : resp_h_cs_string = "POP_OSQ           " ;
         UPD_CQHD                   : resp_h_cs_string = "UPD_CQHD          " ;
         WAIT_VALID_DATA            : resp_h_cs_string = "WAIT_VALID_DATA   " ;
         WAIT_VALID_DATA2           : resp_h_cs_string = "WAIT_VALID_DATA2  " ;
         CHECK_OSQ                  : resp_h_cs_string = "CHECK_OSQ         " ;
         ARBITRATE_OSQ              : resp_h_cs_string = "ARBITRATE_OSQ     " ;
         RETRANSMIT                 : resp_h_cs_string = "RETRANSMIT        " ;
         REWRITE_SQ                 : resp_h_cs_string = "REWRITE_SQ        " ;
         START_RETRANSMIT           : resp_h_cs_string = "START_RETRANSMIT  " ;
         WRITE_CMPL_CNT             : resp_h_cs_string = "WRITE_CMPL_CNT    " ;
         WRITE_CMPL_CNT_PRENACK     : resp_h_cs_string = "WRITE_CMPL_CNT_PRENACK    " ;
         FLUSH_POP_OSQ              : resp_h_cs_string = "FLUSH_POP_OSQ " ;
         WAIT_OSQ_STABLE            : resp_h_cs_string = "WAIT_OSQ_STABLE " ;
         WAIT_DATA_STABLE           : resp_h_cs_string = "WAIT_DATA_STABLE " ;
         WAIT_AXI_DONE              : resp_h_cs_string = "WAIT_AXI_DONE " ;
         WAIT_AXI_DONE_CQ           : resp_h_cs_string = "WAIT_AXI_DONE_CQ " ;
         WAIT_AXI_DONE_CQ_RETRANSMIT: resp_h_cs_string = "WAIT_AXI_DONE_CQ_RETRANSMIT " ;
         FLUSH_POP_MPSNBUF          : resp_h_cs_string = "FLUSH_POP_MPSNBUF " ;
         CHECK_FLUSH_MPSNBUF        : resp_h_cs_string = "CHECK_FLUSH_MPSNBUF " ;
         START_RETRANSMIT_QPM       : resp_h_cs_string = "START_RETRANSMIT_QPM " ;
         UPD_PHASE_BIT              : resp_h_cs_string = "UPD_PHASE_BIT" ;
         UPD_PHASE_BIT2             : resp_h_cs_string = "UPD_PHASE_BIT2" ;
      endcase
      case (resp_h_ns)
         IDLE                       : resp_h_ns_string = "IDLE              " ;
         GET_ARBITRATED_OSQ         : resp_h_ns_string = "GET_ARBITRATED_OSQ";
         CHECK_ERROR                : resp_h_ns_string = "CHECK_ERROR       "      ;
         GET_QP_DATA                : resp_h_ns_string = "GET_QP_DATA       " ;
         GET_WRITE_QP_DATA          : resp_h_ns_string = "GET_WRITE_QP_DATA " ;
         WRITE_CQE                  : resp_h_ns_string = "WRITE_CQE         " ;
         INCR_CQ_CNT_UPD_DB         : resp_h_ns_string = "INCR_CQ_CNT_UPD_DB" ;
         POP_OSQ                    : resp_h_ns_string = "POP_OSQ           " ;
         UPD_CQHD                   : resp_h_ns_string = "UPD_CQHD          " ;
         WAIT_VALID_DATA            : resp_h_ns_string = "WAIT_VALID_DATA   " ;
         WAIT_VALID_DATA2           : resp_h_ns_string = "WAIT_VALID_DATA2  " ;
         CHECK_OSQ                  : resp_h_ns_string = "CHECK_OSQ         " ;
         ARBITRATE_OSQ              : resp_h_ns_string = "ARBITRATE_OSQ     " ;
         RETRANSMIT                 : resp_h_ns_string = "RETRANSMIT        " ;
         REWRITE_SQ                 : resp_h_ns_string = "REWRITE_SQ        " ;
         START_RETRANSMIT           : resp_h_ns_string = "START_RETRANSMIT  " ;
         WRITE_CMPL_CNT             : resp_h_ns_string = "WRITE_CMPL_CNT    " ;
         WRITE_CMPL_CNT_PRENACK     : resp_h_ns_string = "WRITE_CMPL_CNT_PRENACK    " ;
         FLUSH_POP_OSQ              : resp_h_ns_string = "FLUSH_POP_OSQ " ;
         WAIT_OSQ_STABLE            : resp_h_ns_string = "WAIT_OSQ_STABLE " ;
         WAIT_DATA_STABLE           : resp_h_ns_string = "WAIT_DATA_STABLE " ;
         WAIT_AXI_DONE              : resp_h_ns_string = "WAIT_AXI_DONE " ;
         WAIT_AXI_DONE_CQ           : resp_h_ns_string = "WAIT_AXI_DONE_CQ " ;
         WAIT_AXI_DONE_CQ_RETRANSMIT: resp_h_ns_string = "WAIT_AXI_DONE_CQ_RETRANSMIT " ;
         FLUSH_POP_MPSNBUF          : resp_h_ns_string = "FLUSH_POP_MPSNBUF " ;
         CHECK_FLUSH_MPSNBUF        : resp_h_ns_string = "CHECK_FLUSH_MPSNBUF " ;
         START_RETRANSMIT_QPM       : resp_h_ns_string = "START_RETRANSMIT_QPM " ;
         UPD_PHASE_BIT              : resp_h_ns_string = "UPD_PHASE_BIT" ;
         UPD_PHASE_BIT2             : resp_h_ns_string = "UPD_PHASE_BIT2" ;
      endcase
    end
  `endif

endmodule

