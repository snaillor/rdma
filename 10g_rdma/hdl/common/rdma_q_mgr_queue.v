// rdma_q_mgr_queue.v
// 文件名          : rdma_q_mgr_queue.v
// 版本            : v1.0
// 描述            : 通用队列管理器模块，基于 BRAM 实现提交队列/完成队列管理
//                   支持入队/出队操作，可实例化为 SQ/CQ/Admin Queue
// Verilog 标准    : Verilog'2001
//      component instantiations:               "<MODULE>I_<#|FUNC>

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
`timescale 1ps/1ps

(* DowngradeIPIdentifiedWarnings="yes" *)
module rdma_q_mgr_queue
#(
parameter       C_Q_DEPTH    = 32,          // Number of entries in each queue
parameter       C_ENTRY_SIZE = 64,          // Size of each entry in Bytes. SQ size is 64B
parameter       C_PTR_WIDTH  = 5,          // Pointer size reqd for accessing the Q depth
parameter       C_THRESHOLD  = 4,          // Threshold for generating almost full
parameter       C_PUSH_POP_1 = 1,          // If the design only requires single element push/pop
parameter       C_ADDR_WIDTH = 32          // System address bus width
)
(
input   wire                                    core_clk,           // Escape Mode Transmit Clock
input   wire                                    core_rst,           // Active high core reset

// Queue pointers
output  wire   [C_ADDR_WIDTH -1:0]              o_rd_addr,          // Read Address (base addr accounted for) stacked on one bus
output  wire   [C_ADDR_WIDTH -1:0]              o_wr_addr,          // Write Address stacked on one bus
output  wire   [C_PTR_WIDTH -1:0]               o_rd_ptr,           // Read pointer
output  wire   [C_PTR_WIDTH -1:0]               o_wr_ptr,           // Read pointer
output  wire                                    o_q_empty,          // Q is empty
output  wire                                    o_q_full,           // Q is full
output  wire                                    o_q_almost_full,    // Q is full -1
output  wire   [C_PTR_WIDTH :0]                 o_num_valid_entries, // Number of valid entries in the queue
output  wire   [C_PTR_WIDTH :0]                 o_num_free_entries,  // Number of free entries in the queue

// Configuration
input   wire   [C_ADDR_WIDTH -1:0]              i_base_addr,        // base address of where the Q exists
input   wire   [C_PTR_WIDTH :0]                 i_q_depth,          // Q depth
input   wire                                    i_init,             // Initialize to q_depth

input   wire                                    i_q_push,           // Push enable for a queue
input   wire   [C_PTR_WIDTH :0]                 i_push_num_entries, // Number of entries to be pushed

input   wire                                    i_q_pop,            // Pop enable for a queue
input   wire   [C_PTR_WIDTH :0]                 i_pop_num_entries  // Number of entries to be popped

);
`include "rdma_macros.vh"

reg     [C_PTR_WIDTH :0]        rd_ptr_ff; // Read pointer with roll over bit
wire    [C_PTR_WIDTH :0]        rd_ptr_nxt; // Read pointer with roll over bit

reg     [C_PTR_WIDTH :0]        wr_ptr; // Write pointer with roll over bit

reg     [C_PTR_WIDTH :0]        num_valid_entries; // Number of valid entries in the queue
reg     [C_PTR_WIDTH :0]        num_free_entries;  // Number of free entries in the queue
wire                            fifo_full;
wire                            fifo_almost_full;
wire                            fifo_empty;
wire                            valid_pop;
wire                            valid_push;

localparam ADDR_SHIFT =  C_ENTRY_SIZE == 1   ? 0 :
                        (C_ENTRY_SIZE == 4   ? 2 :
                        (C_ENTRY_SIZE == 8   ? 3 :
                        (C_ENTRY_SIZE == 16  ? 4 :
                        (C_ENTRY_SIZE == 32  ? 5 :
                        (C_ENTRY_SIZE == 64  ? 6 :
                        (C_ENTRY_SIZE == 128 ? 7 : 8))))));

assign rd_ptr_nxt[C_PTR_WIDTH -1:0] = valid_pop ?
                    ((rd_ptr_ff[C_PTR_WIDTH -1:0] + i_pop_num_entries < i_q_depth) ?
                     rd_ptr_ff[C_PTR_WIDTH -1:0] + i_pop_num_entries :
                     (rd_ptr_ff[C_PTR_WIDTH -1:0] + i_pop_num_entries - i_q_depth)) : rd_ptr_ff[C_PTR_WIDTH -1:0];
assign rd_ptr_nxt[C_PTR_WIDTH] = valid_pop ?
                    ((rd_ptr_ff[C_PTR_WIDTH -1:0] + i_pop_num_entries < i_q_depth) ? rd_ptr_ff[C_PTR_WIDTH] : ~rd_ptr_ff[C_PTR_WIDTH]) : rd_ptr_ff[C_PTR_WIDTH];

`MSFF_R(rd_ptr_ff, rd_ptr_nxt, core_clk, core_rst)

assign valid_pop = i_q_pop && !fifo_empty && i_pop_num_entries <= num_valid_entries ;
assign valid_push = i_q_push && !fifo_full && i_push_num_entries <= num_free_entries;

generate if (~C_PUSH_POP_1) // Multi element push pop
begin
    always @ (posedge core_clk or posedge core_rst)
    begin
        if(core_rst)
        begin
            wr_ptr  <=  'b0;
        end else begin
            if (valid_push) begin
                if (wr_ptr[C_PTR_WIDTH-1:0] + i_push_num_entries < i_q_depth)
                    wr_ptr[C_PTR_WIDTH-1 :0] <= wr_ptr[C_PTR_WIDTH -1:0] + i_push_num_entries;
                else begin // roll over after i_q_depth
                    wr_ptr[C_PTR_WIDTH-1 :0] <= wr_ptr[C_PTR_WIDTH -1:0] + i_push_num_entries - i_q_depth;
                    wr_ptr[C_PTR_WIDTH] <= ~wr_ptr[C_PTR_WIDTH];
                end
            end
        end
    end
end else
begin // Single element push pop
    always @ (posedge core_clk or posedge core_rst)
    begin
        if(core_rst)
        begin
            wr_ptr  <=  'b0;
        end else begin
            if (valid_push) begin
                if (wr_ptr[C_PTR_WIDTH-1:0] + 1'b1 < i_q_depth)
                    wr_ptr[C_PTR_WIDTH-1 :0] <= wr_ptr[C_PTR_WIDTH -1:0] + 1'b1;
                else begin // roll over after i_q_depth
                    wr_ptr[C_PTR_WIDTH-1 :0] <= 'b0;
                    wr_ptr[C_PTR_WIDTH] <= ~wr_ptr[C_PTR_WIDTH];
                end
            end
        end
    end
end
endgenerate

generate if (~C_PUSH_POP_1)
begin
    always @ (posedge core_clk or posedge core_rst)
    begin
        if(core_rst)
        begin
            num_valid_entries  <=  'b0;
            num_free_entries   <=  C_Q_DEPTH;
        end else begin
            if (i_init) begin
                num_free_entries <= i_q_depth;
                num_valid_entries <= 'b0;
            end else begin
                case({valid_pop, valid_push})
                    2'b01: begin
                        num_valid_entries <= num_valid_entries + i_push_num_entries;
                        num_free_entries <= num_free_entries - i_push_num_entries;
                    end
                    2'b10: begin
                        num_valid_entries <= num_valid_entries - i_pop_num_entries;
                        num_free_entries <= num_free_entries + i_pop_num_entries;
                    end
                    2'b11: begin
                        num_valid_entries <= num_valid_entries - i_pop_num_entries + i_push_num_entries;
                        num_free_entries <= num_free_entries + i_pop_num_entries - i_push_num_entries;
                    end
                    2'b00: begin
                        num_valid_entries <= num_valid_entries;
                        num_free_entries <= num_free_entries;
                    end
                endcase
            end

        end
    end
end else
begin
    always @ (posedge core_clk or posedge core_rst)
    begin
        if(core_rst)
        begin
            num_valid_entries  <=  'b0;
            num_free_entries   <=  C_Q_DEPTH;
        end else begin
            if (i_init) begin
                num_free_entries <= i_q_depth;
                num_valid_entries <= 'b0;
            end else begin
                case({valid_pop, valid_push})
                    2'b01: begin
                        num_valid_entries <= num_valid_entries + 1'b1;
                        num_free_entries <= num_free_entries - 1'b1;
                    end
                    2'b10: begin
                        num_valid_entries <= num_valid_entries - 1'b1;
                        num_free_entries <= num_free_entries + 1'b1;
                    end
                    2'b11, 2'b00: begin
                        num_valid_entries <= num_valid_entries;
                        num_free_entries <= num_free_entries;
                    end
                endcase
            end

        end
    end
end
endgenerate

assign fifo_empty = (wr_ptr == rd_ptr_ff) ? 1'b1 : 1'b0;

assign fifo_full = (wr_ptr[C_PTR_WIDTH] != rd_ptr_ff[C_PTR_WIDTH]) && (wr_ptr[C_PTR_WIDTH -1:0] == rd_ptr_ff[C_PTR_WIDTH-1:0]);

// fifo almost full is generated when the depth -1 locations have been
// written. This is mainly used for NVMe SQs and CQs that do not allow writing
// to all locations
assign fifo_almost_full = (i_q_depth - num_valid_entries  <= C_THRESHOLD) ? 1'b1 : 1'b0;

assign o_wr_addr = i_base_addr + (wr_ptr[C_PTR_WIDTH -1:0] << ADDR_SHIFT);
assign o_rd_addr = i_base_addr + (rd_ptr_ff[C_PTR_WIDTH -1:0] << ADDR_SHIFT);
assign o_wr_ptr = wr_ptr[C_PTR_WIDTH -1:0];
assign o_rd_ptr = rd_ptr_ff[C_PTR_WIDTH -1:0];
assign o_q_full = fifo_full;
assign o_q_almost_full = fifo_almost_full;
assign o_q_empty = fifo_empty;
assign o_num_valid_entries = num_valid_entries;
assign o_num_free_entries = num_free_entries;

endmodule

