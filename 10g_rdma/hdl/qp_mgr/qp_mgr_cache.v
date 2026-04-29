// qp_mgr_cache.v
// 文件名          : qp_mgr_cache.v
// 版本            : v1.0
// 描述            : QP WQE 缓存模块，从 DDR 读取 Send WQE 并进行缓存管理
//                   维护 SQ 指针，协调仲裁与 WQE 下发
// Verilog 标准    : Verilog'2001

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
`timescale 1ps/1ps

(* DowngradeIPIdentifiedWarnings="yes" *)
module qp_mgr_cache
#(
    parameter   C_NUM_QP                = 128,
    parameter   C_M_AXI_ADDR_WIDTH      = 32,
    parameter   C_QP_INDX_WIDTH         = 7
)
(
  input  wire                                       core_clk,
  input  wire                                       core_rstn,

  output wire  [2:0]                                o_fsm_status,
  output wire  [15:0]                               o_stat_num_wqe_cnt,

  // Configuration details
  input  wire                                       i_sw_override_en,
  input  wire					    i_rdma_en,
  input  wire  [C_NUM_QP -1:0]                      i_sq_empty,
  input  wire  [C_NUM_QP -1:0]                      i_osq_almost_full,
  input  wire  [C_QP_INDX_WIDTH -1 :0]              i_qp_sq_arbitrated_idx,
  input  wire                                       i_wqe_fifo_full,
  input  wire                                       i_arbitration_done,
  output wire                                       o_arbitrate,
  output wire                                       o_sample_arbitrated_sq,

  output wire                                       o_status_upd_needed,

  output wire                                       o_qp_sq_ba_req,
  input  wire                                       i_qp_sq_ba_valid,
  input  wire [31:0]                                i_qp_sq_ba,

  output wire                                       o_qp_sq_depth_req,
  input  wire                                       i_qp_sq_depth_valid,
  input  wire [15:0]                                i_qp_sq_depth,

  output wire                                       o_qp_sq_pidb_req,
  input  wire                                       i_qp_sq_pidb_valid,
  input  wire [15:0]                                i_qp_sq_pidb,

  input  wire                                       i_qp_curr_sqptr_valid,
  output wire                                       o_qp_curr_sqptr_rdreq,
  input  wire [15:0]                                i_qp_curr_sqptr_proc,
  output wire                                       o_update_curr_sqptr,
  output wire [15:0]                                o_qp_curr_sqptr,

  input  wire                                       i_qp_stat_wqe_cnt_valid,
  output wire                                       o_qp_stat_wqe_cnt_rdreq,
  input  wire [15:0]                                i_qp_stat_wqe_cnt,
  output wire                                       o_update_qp_stat_wqe_cnt,
  output wire [15:0]                                o_qp_stat_wqe_cnt,

  input  wire                                       i_halt,
  output wire                                       o_halted,

  // AXI master module interface
  output wire                                       o_axi_ren_valid,
  output wire [C_M_AXI_ADDR_WIDTH -1:0]             o_axi_read_addr,
  input  wire                                       i_wqe_dataread

);
`include "rdma_macros.vh"

localparam SQ_ENTRY_SIZE = 64; // 64 Bytes

localparam IDLE                     = 3'b000;
localparam ARBITRATE_SQ             = 3'b001;
localparam FETCH_SQ_ENTRY           = 3'b010;
localparam PUSH_SQ_UPD_CURR_SQPTR   = 3'b011;
localparam GET_ELEM_ADDR            = 3'b100;
localparam GET_ARBITRATED_SQ        = 3'b101;
localparam HALTED                   = 3'b110;
localparam CHECK_SQ_EMPTY           = 3'b111;

reg [2:0] cache_ns;
reg [2:0] cache_cs;
reg [15:0] qp_sq_depth_ff;
reg [15:0] qp_sq_pidb_ff;
reg [15:0] qp_stat_wqe_cnt_ff;
reg [31:0] qp_sq_ba_ff;
reg [15:0] qp_curr_sqptr_proc_ff;
reg [15:0] num_global_wqe_cnt;

wire [15:0] new_qp_stat_wqe_cnt;
wire [15:0] new_curr_sqptr_proc;
wire [15:0] curr_sqptr_base_0;
wire [C_M_AXI_ADDR_WIDTH -1:0] sq_read_addr_to_axi;
wire sq_empty;

// NOrmally, the CQ doorbell value (for the SEND q) is not really used.
// The curr_sqptr value is used along with SQ PI DB to figure out the FIFO
// full/empty condition. HOwever, in case of error when re-transmission needs
// to happen, the QP cache module moves the curr_sqptr value to the value in
// the CQ DB value. This is not expected to happen very frequntly. Right now
// the logic in the Resp handler module waits for the cache manager to ack the
// retransmission and hence is not very pipelined. This should ideally not be
// a problem if the retransmission happens very infrequently.

always @ (posedge core_clk or negedge core_rstn)
begin
    if(~core_rstn)
    begin
        cache_cs <= IDLE;
    end
    else if(!i_rdma_en) begin
        cache_cs <= IDLE;
    end
    else begin
        cache_cs <= cache_ns;
    end
end

always @(*)
begin
    cache_ns <= cache_cs;
    case (cache_cs)

        IDLE:
        begin
            if (i_sw_override_en) begin
                cache_ns <= IDLE;
            end else if (i_halt) begin
                cache_ns <= HALTED;
            end else if (~(&i_sq_empty) & ~i_wqe_fifo_full) begin
                cache_ns <= GET_ARBITRATED_SQ;
            end
        end

        // BY default the arbiter will work and get a valid SQ to work on, so
        // no need to ask to arbitrate , if all SQ's are empty then go back to
        // IDLE state
        GET_ARBITRATED_SQ:
        begin
            if (i_sw_override_en) begin
                cache_ns <= IDLE;
            end else if (i_halt) begin
                cache_ns <= HALTED;
            end else if (i_arbitration_done) begin
                cache_ns <= ARBITRATE_SQ;
            end else if(&i_sq_empty) begin
		cache_ns <= IDLE;
	    end
        end

        // Before moving to next step ask the Arbiter to arbitrate and get the next
        ARBITRATE_SQ:
        begin
            // Since arbitration happends in the background, and
            // osq_almost_full is an asynchronous event, it is possible that
            // after the arbitration was done, the sq became alsmot_full. in
            // such a case, this QP should not be used
            if (i_osq_almost_full[i_qp_sq_arbitrated_idx])
                cache_ns <= IDLE;
            else
                cache_ns <= GET_ELEM_ADDR;
        end

        GET_ELEM_ADDR:
        begin
            if (i_qp_sq_ba_valid & i_qp_curr_sqptr_valid & i_qp_sq_depth_valid & i_qp_sq_pidb_valid & i_qp_stat_wqe_cnt_valid) begin
                cache_ns <= CHECK_SQ_EMPTY;
            end
        end

        // as there is a delay between the PI and curr pointer update and the
        // FIFO empty signal beign updated, checking if the SQ is empty
        CHECK_SQ_EMPTY:
        begin
            if (sq_empty)
                cache_ns <= IDLE;
            else
                cache_ns <= FETCH_SQ_ENTRY;
        end

        FETCH_SQ_ENTRY:
        begin
            if (i_wqe_dataread) begin // data read back from DDR
                cache_ns <= PUSH_SQ_UPD_CURR_SQPTR;
            end
        end

        PUSH_SQ_UPD_CURR_SQPTR:
        begin
            cache_ns <= IDLE;
        end

        HALTED:
        begin
            if (~i_halt)
                cache_ns <= IDLE;
        end

    endcase
end

`MSFF_R(qp_sq_ba_ff, (i_qp_sq_ba_valid ? i_qp_sq_ba : qp_sq_ba_ff), core_clk, ~core_rstn)
`MSFF_R(qp_sq_depth_ff, (i_qp_sq_depth_valid ? i_qp_sq_depth : qp_sq_depth_ff), core_clk, ~core_rstn)
`MSFF_R(qp_curr_sqptr_proc_ff, (i_qp_curr_sqptr_valid ? i_qp_curr_sqptr_proc : qp_curr_sqptr_proc_ff), core_clk, ~core_rstn)
`MSFF_R(qp_sq_pidb_ff, (i_qp_sq_pidb_valid ? i_qp_sq_pidb : qp_sq_pidb_ff), core_clk, ~core_rstn)
`MSFF_R(qp_stat_wqe_cnt_ff, (i_qp_stat_wqe_cnt_valid ? i_qp_stat_wqe_cnt : new_qp_stat_wqe_cnt), core_clk, ~core_rstn)

`MSFF_R(num_global_wqe_cnt, ((cache_cs == PUSH_SQ_UPD_CURR_SQPTR) ? (num_global_wqe_cnt + 1'b1) : num_global_wqe_cnt), core_clk, ~core_rstn)

assign new_curr_sqptr_proc =  (qp_curr_sqptr_proc_ff == qp_sq_depth_ff) ? 16'b1 : (qp_curr_sqptr_proc_ff + 1'b1);

assign new_qp_stat_wqe_cnt = ((cache_cs == FETCH_SQ_ENTRY) & i_wqe_dataread) ? qp_stat_wqe_cnt_ff + 1'b1 : qp_stat_wqe_cnt_ff;

assign curr_sqptr_base_0 = (qp_curr_sqptr_proc_ff == qp_sq_depth_ff) ? 16'b0 : qp_curr_sqptr_proc_ff;
assign sq_read_addr_to_axi = qp_sq_ba_ff + (curr_sqptr_base_0 * SQ_ENTRY_SIZE);

assign sq_empty = (qp_sq_pidb_ff == qp_curr_sqptr_proc_ff) ? 1'b1 : 1'b0;
assign o_qp_stat_wqe_cnt = qp_stat_wqe_cnt_ff;

// Sometimes a status update gets overwritten by a clear if it happens within
// one clock cycle of the update. Make sure if the SQ empty status is not
// correct, it is shown as pending
assign o_status_upd_needed = sq_empty & (cache_cs == CHECK_SQ_EMPTY);

assign o_axi_read_addr = sq_read_addr_to_axi;
assign o_qp_curr_sqptr = new_curr_sqptr_proc;

assign o_axi_ren_valid = ((cache_cs == CHECK_SQ_EMPTY) & ~sq_empty) ? 1'b1 : 1'b0;
assign o_qp_sq_ba_req = (cache_cs == GET_ELEM_ADDR) ? 1'b1 : 1'b0;
assign o_qp_sq_depth_req = (cache_cs == GET_ELEM_ADDR) ? 1'b1 : 1'b0;
assign o_qp_sq_pidb_req = (cache_cs == GET_ELEM_ADDR) ? 1'b1 : 1'b0;
assign o_qp_curr_sqptr_rdreq = (cache_cs == GET_ELEM_ADDR) ? 1'b1 : 1'b0;
assign o_qp_stat_wqe_cnt_rdreq = (cache_cs == GET_ELEM_ADDR) ? 1'b1 : 1'b0;
assign o_update_curr_sqptr = (cache_cs == PUSH_SQ_UPD_CURR_SQPTR) ? 1'b1 : 1'b0;
assign o_update_qp_stat_wqe_cnt = (cache_cs == PUSH_SQ_UPD_CURR_SQPTR) ? 1'b1 : 1'b0;
assign o_arbitrate = (cache_cs == ARBITRATE_SQ) ? 1'b1 : 1'b0;
assign o_sample_arbitrated_sq = (cache_cs == GET_ARBITRATED_SQ) ? 1'b1 : 1'b0;
assign o_halted = (cache_cs == HALTED) ? 1'b1 : 1'b0;
assign o_fsm_status = cache_cs;
assign o_stat_num_wqe_cnt = num_global_wqe_cnt;

// Non-synthesizable code

  `ifdef SIMULATION
    reg [20*8-1:0] cache_cs_string = "null";
    reg [20*8-1:0] cache_ns_string = "null";

    always @* begin
      case (cache_cs)
         IDLE                       : cache_cs_string = "IDLE"             ;
         ARBITRATE_SQ               : cache_cs_string = "ARBITRATE_SQ";
         GET_ARBITRATED_SQ          : cache_cs_string = "GET_ARBITRATED_SQ";
         FETCH_SQ_ENTRY             : cache_cs_string = "FETCH_SQ_ENTRY" ;
         CHECK_SQ_EMPTY             : cache_cs_string = "CHECK_SQ_EMPTY" ;
         PUSH_SQ_UPD_CURR_SQPTR     : cache_cs_string = "PUSH_SQ_UPD_CURR_SQPTR"      ;
         GET_ELEM_ADDR              : cache_cs_string = "GET_ELEM_ADDR" ;
      endcase
      case (cache_ns)
         IDLE                       : cache_ns_string = "IDLE"             ;
         ARBITRATE_SQ               : cache_ns_string = "ARBITRATE_SQ";
         GET_ARBITRATED_SQ          : cache_ns_string = "GET_ARBITRATED_SQ";
         FETCH_SQ_ENTRY             : cache_ns_string = "FETCH_SQ_ENTRY" ;
         CHECK_SQ_EMPTY             : cache_ns_string = "CHECK_SQ_EMPTY" ;
         PUSH_SQ_UPD_CURR_SQPTR     : cache_ns_string = "PUSH_SQ_UPD_CURR_SQPTR"      ;
         GET_ELEM_ADDR              : cache_ns_string = "GET_ELEM_ADDR" ;
      endcase
    end
  `endif

endmodule

