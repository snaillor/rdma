// qp_mgr_retransmit.v
// 文件名          : qp_mgr_retransmit.v
// 版本            : v1.0
// 描述            : QP 重传控制模块，处理 PSN 失序或 NAK 触发的重传
//                   恢复 PSN/SSN，清理 WQE FIFO，暂停/恢复发送流程
// Verilog 标准    : Verilog'2001

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
`timescale 1ps/1ps

(* DowngradeIPIdentifiedWarnings="yes" *)
module qp_mgr_retransmit
#(
    parameter   C_NUM_QP                = 128,
    parameter   C_WQE_FIFO_IDX_WIDTH    = 3,
    parameter   C_QP_INDX_WIDTH         = 7
)
(
  input  wire                                       core_clk,
  input  wire                                       core_rstn,

  // Configuration details
  input  wire                                       i_retransmit_reqd,
  input  wire [C_QP_INDX_WIDTH -1 :0]               i_retransmit_qpid,        // QP id for this retransmission is required
  output wire                                       o_retransmit_accepted,
  input  wire [23:0]                                i_psn_to_retry,
  input  wire [23:0]                                i_ssn_to_retry,

  input  wire [C_WQE_FIFO_IDX_WIDTH  :0]            i_num_valid_entries,

  output wire                                       o_qp_cq_hdptr_req,
  input  wire                                       i_qp_cq_hdptr_valid,
  input  wire [15:0]                                i_qp_cq_hdptr,
  output wire [C_QP_INDX_WIDTH -1: 0]               o_qp_cq_hdptr_idx,   // Index for reading Q depth

  // configuration that is updated
  output wire [15:0]                                o_qp_curr_sqptr_proc,
  output wire                                       o_qp_curr_sqptr_proc_wen,
  output wire [C_QP_INDX_WIDTH -1: 0]               o_qp_curr_sqptr_proc_idx,   // Index for writing curent SQ pointer

  output wire [23:0]                                o_qp_stat_ret_sq_psn,
  output wire                                       o_qp_stat_ret_sq_psn_wen,
  output wire [C_QP_INDX_WIDTH -1: 0]               o_qp_stat_ret_sq_psn_idx,
  input  wire                                       i_qp_stat_ret_sq_psn_valid,

  output wire                                       o_qp_sq_psn_req,
  input  wire                                       i_qp_sq_psn_valid,
  input  wire  [23:0]                               i_qp_sq_psn,
  output wire                                       o_qp_sq_psn_wrn,
  output wire  [23:0]                               o_qp_sq_psn,
  output wire  [C_QP_INDX_WIDTH -1: 0]              o_qp_sq_psn_idx,   // Index for reading Q depth

  output wire  [C_QP_INDX_WIDTH -1: 0]              o_qp_stat_ssn_idx,    // Index for reading/writing MSN
  output wire  [23:0]                               o_qp_stat_ssn, // Expected MSN for Qp incoming messages
  input  wire  [23:0]                               i_qp_stat_ssn, // Expected MSN for Qp incoming messages write data from hdr validation
  output wire                                       o_qp_stat_ssn_req,
  output wire                                       o_qp_stat_ssn_wrn,
  input  wire                                       i_qp_stat_ssn_valid,

  input  wire  [511:0]                              i_wqe,
  output wire  [511:0]                              o_wqe,
  output wire                                       o_wqe_fifo_push,
  output wire                                       o_wqe_fifo_pop,

  output wire                                       o_halt,
  output wire [C_QP_INDX_WIDTH -1 :0]               o_halted_qpid,
  input  wire                                       i_halted

);
`include "rdma_macros.vh"

localparam IDLE                     = 3'b000;
localparam HALT_PROCESS             = 3'b001;
localparam GET_CONF                 = 3'b010;
localparam UPD_CONF                 = 3'b011;
localparam CLEAN_SWQE_FIFO          = 3'b100;
localparam POP_SWQE                 = 3'b101;
localparam PUSH_SWQE                = 3'b110;
localparam CHECK_SWQE               = 3'b111;

reg [2:0] retry_ns;
reg [2:0] retry_cs;
reg [C_WQE_FIFO_IDX_WIDTH  :0] sq_fifo_unclean_entries_ff;
reg [C_WQE_FIFO_IDX_WIDTH  :0] sq_fifo_unclean_entries;
reg [15:0] qp_cq_hdptr_ff;
reg [23:0] qp_sq_psn_ff;
reg [23:0] qp_stat_ssn_ff;
reg [C_QP_INDX_WIDTH -1 :0] qp_retry_idx;
reg [511:0] wqe_ff;
reg [23:0] psn_to_retry_ff;
reg [23:0] ssn_to_retry_ff;

always @ (posedge core_clk or negedge core_rstn)
begin
    if(~core_rstn)
    begin
        retry_cs <= IDLE;
    end
    else begin
        retry_cs <= retry_ns;
    end
end

always @(*)
begin
    retry_ns <= retry_cs;
    sq_fifo_unclean_entries <= sq_fifo_unclean_entries_ff;
    case (retry_cs)

        IDLE:
        begin
            if (i_retransmit_reqd) begin
                retry_ns <= HALT_PROCESS;
            end
        end

        HALT_PROCESS:
        begin
            if (i_halted)
                retry_ns <= GET_CONF;
        end

        GET_CONF:
        begin
            sq_fifo_unclean_entries <= i_num_valid_entries;
            if (i_qp_cq_hdptr_valid & i_qp_sq_psn_valid & i_qp_stat_ssn_valid)
                retry_ns <= UPD_CONF;
        end

        UPD_CONF:
        begin
            if (i_qp_sq_psn_valid & i_qp_stat_ret_sq_psn_valid)
                retry_ns <= CLEAN_SWQE_FIFO;
        end

        CLEAN_SWQE_FIFO:
        begin
            if (sq_fifo_unclean_entries_ff != 'b0) begin
                retry_ns <= POP_SWQE;
            end else
                retry_ns <= IDLE;
        end

        POP_SWQE:
        begin
            retry_ns <= CHECK_SWQE;
        end

        CHECK_SWQE:
        begin
            sq_fifo_unclean_entries <= sq_fifo_unclean_entries_ff -1'b1;
            if (i_wqe[136 +: 8] == qp_retry_idx) begin // location of the inserted QP ID
                retry_ns <= CLEAN_SWQE_FIFO;
            end else
                retry_ns <= PUSH_SWQE;
        end
        PUSH_SWQE:
            retry_ns <= CLEAN_SWQE_FIFO;

    endcase
end

`MSFF_R(sq_fifo_unclean_entries_ff, sq_fifo_unclean_entries, core_clk, ~core_rstn)
`MSFF_R(qp_sq_psn_ff, (((retry_cs == GET_CONF) & i_qp_sq_psn_valid) ? i_qp_sq_psn : qp_sq_psn_ff), core_clk, ~core_rstn)
`MSFF_R(qp_stat_ssn_ff, (i_qp_stat_ssn_valid ? i_qp_stat_ssn : qp_stat_ssn_ff), core_clk, ~core_rstn)
`MSFF_R(qp_cq_hdptr_ff, (i_qp_cq_hdptr_valid ? i_qp_cq_hdptr : qp_cq_hdptr_ff), core_clk, ~core_rstn)
`MSFF_R(qp_retry_idx, (retry_cs == IDLE ? i_retransmit_qpid : qp_retry_idx), core_clk, ~core_rstn)

`MSFF_R(wqe_ff, i_wqe, core_clk, ~core_rstn)

assign o_wqe = wqe_ff;
assign o_qp_stat_ret_sq_psn = qp_sq_psn_ff;

`MSFF_R(psn_to_retry_ff, ((i_retransmit_reqd & (retry_cs == IDLE)) ? i_psn_to_retry : psn_to_retry_ff), core_clk, ~core_rstn)
`MSFF_R(ssn_to_retry_ff, ((i_retransmit_reqd & (retry_cs == IDLE)) ? i_ssn_to_retry : ssn_to_retry_ff), core_clk, ~core_rstn)

assign o_qp_sq_psn          = psn_to_retry_ff;//{qp_sq_psn_ff[23:8], (i_psn_to_retry)};
assign o_qp_stat_ssn        = ssn_to_retry_ff;//{qp_stat_ssn_ff[23:8], (i_ssn_to_retry)};
assign o_qp_curr_sqptr_proc = qp_cq_hdptr_ff ; //(qp_cq_hdptr_ff == 16'b0) ? 16'h1 : qp_cq_hdptr_ff; //- 1'b1;

assign o_qp_sq_psn_req   = ((retry_cs == GET_CONF) || (retry_cs == UPD_CONF)) ? 1'b1 : 1'b0;
assign o_qp_stat_ssn_req = (retry_cs == GET_CONF) ? 1'b1 : 1'b0;
assign o_qp_cq_hdptr_req = (retry_cs == GET_CONF) ? 1'b1 : 1'b0;

assign o_qp_sq_psn_wrn          = (retry_cs == UPD_CONF) ? 1'b1 : 1'b0;
assign o_qp_stat_ret_sq_psn_wen = (retry_cs == UPD_CONF) ? 1'b1 : 1'b0;
assign o_qp_stat_ssn_wrn        = (retry_cs == UPD_CONF) ? 1'b1 : 1'b0;
assign o_qp_curr_sqptr_proc_wen = (retry_cs == UPD_CONF) ? 1'b1 : 1'b0;

assign o_wqe_fifo_push = (retry_cs == PUSH_SWQE) ? 1'b1 : 1'b0;
assign o_wqe_fifo_pop  = (retry_cs == POP_SWQE)  ? 1'b1 : 1'b0;

assign o_halt = (retry_cs != IDLE) ? 1'b1 : 1'b0;
assign o_halted_qpid = qp_retry_idx;
assign o_qp_stat_ssn_idx = qp_retry_idx;
assign o_qp_sq_psn_idx = qp_retry_idx;
assign o_qp_stat_ret_sq_psn_idx = qp_retry_idx;
assign o_qp_curr_sqptr_proc_idx = qp_retry_idx;
assign o_qp_cq_hdptr_idx = qp_retry_idx;

assign o_retransmit_accepted = (retry_cs == IDLE) ? 1'b1 : 1'b0;

// Non-synthesizable code

  `ifdef SIMULATION
    reg [20*8-1:0] retry_cs_string = "null";
    reg [20*8-1:0] retry_ns_string = "null";

    always @* begin
      case (retry_cs)
        IDLE                 : retry_cs_string = "IDLE           ";
        HALT_PROCESS         : retry_cs_string = "HALT_PROCESS   ";
        GET_CONF             : retry_cs_string = "GET_CONF       ";
        UPD_CONF             : retry_cs_string = "UPD_CONF       ";
        CLEAN_SWQE_FIFO      : retry_cs_string = "CLEAN_SWQE_FIFO";
        POP_SWQE             : retry_cs_string = "POP_SWQE       ";
        PUSH_SWQE            : retry_cs_string = "PUSH_SWQE      ";
        CHECK_SWQE           : retry_cs_string = "CHECK_SWQE     ";
      endcase
      case (retry_ns)
        IDLE                 : retry_ns_string = "IDLE           ";
        HALT_PROCESS         : retry_ns_string = "HALT_PROCESS   ";
        GET_CONF             : retry_ns_string = "GET_CONF       ";
        UPD_CONF             : retry_ns_string = "UPD_CONF       ";
        CLEAN_SWQE_FIFO      : retry_ns_string = "CLEAN_SWQE_FIFO";
        POP_SWQE             : retry_ns_string = "POP_SWQE       ";
        PUSH_SWQE            : retry_ns_string = "PUSH_SWQE      ";
        CHECK_SWQE           : retry_ns_string = "CHECK_SWQE     ";
      endcase
    end
  `endif

endmodule

