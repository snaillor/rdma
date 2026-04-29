// rdma_blk_allocator.v
// 文件名          : rdma_blk_allocator.v
// 版本            : v1.0
// 描述            : 通用块分配器模块，管理空闲缓冲区、表项、SGL 块等资源
//                   支持分配与释放操作，维护空闲资源链表
// Verilog 标准    : Verilog'2001
//      component instantiations:               "<MODULE>I_<#|FUNC>

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////

`timescale 1ps/1ps

(* DowngradeIPIdentifiedWarnings="yes" *)
module rdma_blk_allocator
#(
parameter	C_NUM_BLK	      = 24,	// Number of blocks to be allocated
parameter       C_BRAM_N_FLOP         = 0,          // 1 = BRAM, 0 = FLOP
parameter       C_FLOP_BRAM_OUTPUT    = 0,      // Flip the output of BRAM
parameter	C_BLK_PTR_WIDTH	      = 5	// Width for block number
)
(
input   wire					core_clk,
input   wire					core_rst,		    // Active high core reset

// Configuration
input   wire	[C_BLK_PTR_WIDTH :0]		i_num_blocks_enabled,	    // Number of enabled blocks (less than max)
input   wire	[15:0]				i_blk_size,		    // Block size in bytes // max size 64KB
input   wire	[31:0]				i_blk_base_addr,	    // Base address for the blocks
output  wire                                    o_fifo_busy,                // Busy with initialization

// Free block interface
input	wire					i_push_free_block,	    // Push enable for a queue
input   wire	[C_BLK_PTR_WIDTH -1: 0]		i_push_free_block_num,	    // Data to be pushed

input   wire   	 				i_pop_free_block,	    // Pop enable for a queue
output  wire   	[C_BLK_PTR_WIDTH -1: 0]		o_free_block_num,	    // Popped Data
output  wire   	[31:0]				o_free_block_addr,	    // Address of the free block
output  wire   	 				o_no_free_blocks_left,	    // No more free blocks left to be allocted
output  wire   	[C_BLK_PTR_WIDTH :0]		o_num_valid_entries	    // Number of valid blocks left (status signal)

);

reg     [C_BLK_PTR_WIDTH :0]	num_blocks_enabled_d;  // Delayed version of Number of blocks enabled
wire				initialize_fifo;
wire				q_full;
wire   [C_BLK_PTR_WIDTH :0]	num_free_entries;  // Number of free entries in the queue

always @ (posedge core_clk or posedge core_rst)
begin
    if(core_rst)
    begin
	num_blocks_enabled_d <= 'b0;
    end else begin
	num_blocks_enabled_d <= i_num_blocks_enabled;
    end
end

// Whenever there is a change in configuration re-initialize the fifo
assign initialize_fifo	 = |(num_blocks_enabled_d ^ i_num_blocks_enabled);
assign o_free_block_addr = i_blk_base_addr + o_free_block_num * i_blk_size;

rdma_blk_allocator_init_fifo
#(
.C_Q_DEPTH(C_NUM_BLK),	    // Number of entries in each queue
.C_BRAM_N_FLOP(C_BRAM_N_FLOP),        // Implement the block allocator fifo in BRAM or FLOPs
.C_FLOP_BRAM_OUTPUT(C_FLOP_BRAM_OUTPUT),
.C_PTR_WIDTH(C_BLK_PTR_WIDTH)         // Pointer size reqd for accessing the Q depth
)
inst_init_fifo(
.core_clk			(core_clk),		    // Escape Mode Transmit Clock
.core_rst			(core_rst),		    // Active high core reset

// Queue pointers
.o_q_empty			(o_no_free_blocks_left),    // Q is empty
.o_q_full			(q_full),		    // Q is6 full
.o_num_valid_entries		(o_num_valid_entries),	    // Number of valid entries in the queue
.o_num_free_entries		(num_free_entries),	    // Number of free entries in the queue

// configurations
.i_q_depth			(i_num_blocks_enabled),	    // configured depth of the queue
.i_initialize			(initialize_fifo),	    // Initialize the fifo
.o_fifo_busy                    (o_fifo_busy),              // Busy with initialization

.i_q_push			(i_push_free_block),	    // Push enable for a queue
.i_q_push_data			(i_push_free_block_num),	    // Data to be pushed

.i_q_pop			(i_pop_free_block),	    // Pop enable for a queue
.o_q_pop_data			(o_free_block_num)	    // Pop Data

);

endmodule

