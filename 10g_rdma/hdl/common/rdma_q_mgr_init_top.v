// rdma_q_mgr_init_top.v
// 文件名          : rdma_q_mgr_init_top.v
// 版本            : v1.0
// 描述            : 队列管理器初始化顶层模块，完成队列的复位与预初始化
// Verilog 标准    : Verilog'2001
//      device pins:                            "*_pin"
//      component instantiations:               "<MODULE>I_<#|FUNC>

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
`timescale 1ps/1ps

(* DowngradeIPIdentifiedWarnings="yes" *)
module rdma_q_mgr_init_top
#(
parameter	C_NUM_QUEUES = 1024,	    // Number of queues
parameter	C_Q_DEPTH    = 32,	    // Number of entries in each queue
parameter	C_ENTRY_SIZE = 64,	    // Size of each entry in Bytes. SQ size is 64B
parameter	C_PTR_WIDTH  = 5,	    // Pointer size reqd for accessing the Q depth
parameter       C_THRESHOLD  = 4,
parameter       C_PUSH_POP_1 = 1,          // If the design only requires single element push/pop
parameter       C_ADDR_WIDTH = 32	    // System address bus width
)
(
input   wire					    core_clk,
input   wire					    core_rst,	    // Active high core reset

// Queue pointers
output  wire   [C_NUM_QUEUES*C_ADDR_WIDTH -1:0]	    o_rd_addr,	    // Read address stacked on one bus
output  wire   [C_NUM_QUEUES*C_ADDR_WIDTH -1:0]	    o_wr_addr,	    // Write address stacked on one bus
output  wire   [C_NUM_QUEUES*C_PTR_WIDTH -1:0]	    o_rd_ptr,	    // Read pointer stacked on one bus
output  wire   [C_NUM_QUEUES*C_PTR_WIDTH -1:0]	    o_wr_ptr,	    // Write pointer stacked on one bus
output  wire   [C_NUM_QUEUES -1:0]		    o_q_full,	    // Queue is full
output  wire   [C_NUM_QUEUES -1:0]                  o_q_almost_full,    // Q is full -1
output  wire   [C_NUM_QUEUES -1:0]		    o_q_empty,	    // Queue is empty
output  wire   [C_NUM_QUEUES*(C_PTR_WIDTH+1) -1 :0] o_num_valid_entries, // Number of valid entries in the queue
output  wire   [C_NUM_QUEUES*(C_PTR_WIDTH+1) -1 :0] o_num_free_entries,  // Number of free entries in the queue

// Configuration
input   wire   [C_NUM_QUEUES*C_ADDR_WIDTH -1:0]	    i_base_addr,	    // base address of where the Q exists
input   wire   [C_NUM_QUEUES*(C_PTR_WIDTH+1) -1 :0] i_q_depth,          // Configurable q depth (less than max as defined by param)

input	wire   [C_NUM_QUEUES -1:0]		    i_q_push,	    // Push enable for a queue
input   wire   [C_NUM_QUEUES*(C_PTR_WIDTH+1) -1 :0] i_push_num_entries, // Number of entries to be pushed

input   wire   [C_NUM_QUEUES -1:0]		    i_q_pop,	    // Pop enable for a queue
input   wire   [C_NUM_QUEUES*(C_PTR_WIDTH+1) -1 :0] i_pop_num_entries  // Number of entries to be popped

);
`include "rdma_macros.vh"

wire initialize;
reg [C_NUM_QUEUES*(C_PTR_WIDTH+1) -1:0] q_depth_ff;

`MSFF_R(q_depth_ff, i_q_depth, core_clk, core_rst)

assign initialize = |(i_q_depth ^ q_depth_ff);

genvar i;

generate for (i=1; i<=C_NUM_QUEUES; i=i+1) begin : queue_gen

    rdma_q_mgr_queue
    #(
    .C_Q_DEPTH(C_Q_DEPTH),	    // Number of entries in each queue
    .C_ENTRY_SIZE(C_ENTRY_SIZE),    // Size of each entry in Bytes. SQ size is 64B
    .C_ADDR_WIDTH(C_ADDR_WIDTH),
    .C_THRESHOLD(C_THRESHOLD),
    .C_PUSH_POP_1(C_PUSH_POP_1),
    .C_PTR_WIDTH(C_PTR_WIDTH)	    // Pointer size reqd for accessing the Q depth
    ) inst_q
    (
    .core_clk			    (core_clk),					// Clock
    .core_rst			    (core_rst),					// Active high core reset

    // Queue pointers
    .o_rd_addr			    (o_rd_addr[i*C_ADDR_WIDTH -1:(i-1)*C_ADDR_WIDTH]),		// Read address stacked on one bus
    .o_wr_addr			    (o_wr_addr[i*C_ADDR_WIDTH -1:(i-1)*C_ADDR_WIDTH]),		// Write address stacked on one bus
    .o_rd_ptr                       (o_rd_ptr[(i-1)*C_PTR_WIDTH +:C_PTR_WIDTH]),                // read pointer
    .o_wr_ptr		            (o_wr_ptr[(i-1)*C_PTR_WIDTH +:C_PTR_WIDTH]),	        // write pointer
    .o_num_valid_entries	    (o_num_valid_entries[(i-1)*(C_PTR_WIDTH+1) +:C_PTR_WIDTH+1]),  // Number of valid entries stacked
    .o_num_free_entries		    (o_num_free_entries[(i-1)*(C_PTR_WIDTH+1) +:C_PTR_WIDTH+1]),	// Number of free entries stacked
    .o_q_empty			    (o_q_empty[i-1]),
    .o_q_full			    (o_q_full[i-1]),
    .o_q_almost_full                (o_q_almost_full[i-1]),    // Q is full -1

    // Configuration
    .i_base_addr		    (i_base_addr[i*C_ADDR_WIDTH -1:(i-1)*C_ADDR_WIDTH]),	// Base address of queues
    .i_q_depth                      (i_q_depth[(i-1)*(C_PTR_WIDTH+1)+:C_PTR_WIDTH+1]),
    .i_init                         (initialize),

    .i_q_push			    (i_q_push[i-1]),				// Push enable for a queue
    .i_push_num_entries		    (i_push_num_entries[(i-1)*(C_PTR_WIDTH+1)+:(C_PTR_WIDTH+1)]),	// Number of entries to be pushed

    .i_q_pop			    (i_q_pop[i-1]),				// Pop enable for a queue
    .i_pop_num_entries		    (i_pop_num_entries[(i-1)*(C_PTR_WIDTH+1)+:(C_PTR_WIDTH+1)])     // Number of entries to be popped
    );

    end
endgenerate

endmodule

