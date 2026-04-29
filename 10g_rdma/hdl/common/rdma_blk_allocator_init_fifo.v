// rdma_blk_allocator_init_fifo.v
// 文件名          : rdma_blk_allocator_init_fifo.v
// 版本            : v1.0
// 描述            : 块分配器初始化 FIFO 模块，预初始化空闲资源列表
// Verilog 标准    : Verilog'2001

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
`timescale 1ps/1ps

(* DowngradeIPIdentifiedWarnings="yes" *)
module rdma_blk_allocator_init_fifo
#(
parameter	C_Q_DEPTH    = 32,	    // Number of entries in each queue
parameter       C_BRAM_N_FLOP = 0,          // 1 = BRAM, 0 = FLOP
parameter       C_FLOP_BRAM_OUTPUT = 0,     // Flop the output of BRAM
parameter	C_PTR_WIDTH  = 5            // Pointer size reqd for accessing the Q depth
)
(
input   wire					core_clk,	    // Escape Mode Transmit Clock
input   wire					core_rst,	    // Active high core reset

// Queue pointers
output  wire					o_q_empty,	    // Q is empty
output  wire					o_q_full,	    // Q is full
output  wire   [C_PTR_WIDTH :0]			o_num_valid_entries, // Number of valid entries in the queue
output  wire   [C_PTR_WIDTH :0]			o_num_free_entries,  // Number of free entries in the queue

// configurations
input   wire   [C_PTR_WIDTH :0]			i_q_depth,	    // configured depth of the queue
input   wire					i_initialize,	    // Initialize the fifo
output  wire                                    o_fifo_busy,        // Busy with initialization

input	wire					i_q_push,	    // Push enable for a queue
input   wire   [C_PTR_WIDTH -1: 0]		i_q_push_data,	    // Data to be pushed

input   wire					i_q_pop,	    // Pop enable for a queue
output  wire   [C_PTR_WIDTH -1: 0]		o_q_pop_data	    // Pop Data

);

reg	[C_PTR_WIDTH :0]	rd_ptr; // Read pointer with roll over bit
reg	[C_PTR_WIDTH :0]	wr_ptr; // Write pointer with roll over bit

reg     [C_PTR_WIDTH :0]	num_valid_entries; // Number of valid entries in the queue
reg     [C_PTR_WIDTH :0]	num_free_entries;  // Number of free entries in the queue
reg     [C_PTR_WIDTH -1:0]	mem[C_Q_DEPTH -1:0]; // fifo memory
reg     [C_PTR_WIDTH -1:0]	mem_init;
reg                             init_start;
reg                             reset_released;
reg                             reset_released_ff;
wire				fifo_full;
wire     [C_PTR_WIDTH -1:0]     bram_rdata;
wire				fifo_empty;
wire				valid_pop;
wire				valid_push;
wire				push_num_entries;
wire				pop_num_entries;
wire   [C_PTR_WIDTH -1: 0]	q_push_data;	    // Data to be pushed
genvar	i;

assign push_num_entries = 1'b1;
assign pop_num_entries = 1'b1;

always @ (posedge core_clk or posedge core_rst)
begin
    if(core_rst)
    begin
	rd_ptr  <=  'b0;
    end else begin
	if (i_initialize)
	    rd_ptr <= 'b0;
	else if (valid_pop) begin
	    if (rd_ptr[C_PTR_WIDTH -1:0] + pop_num_entries < i_q_depth)
		rd_ptr[C_PTR_WIDTH -1:0] <= rd_ptr[C_PTR_WIDTH -1:0] + pop_num_entries;
	    else begin// roll over after i_q_depth
		rd_ptr[C_PTR_WIDTH -1:0] <= rd_ptr[C_PTR_WIDTH -1:0] + pop_num_entries - i_q_depth;
		rd_ptr[C_PTR_WIDTH] <= ~rd_ptr[C_PTR_WIDTH];
	    end
	end
    end
end

always @ (posedge core_clk or posedge core_rst)
begin
    if(core_rst)
    begin
	reset_released <= 1'b0;
	reset_released_ff <= 1'b0;
    end else begin
        reset_released <= 1'b1;
	reset_released_ff <= reset_released;
    end
end

assign reset_rel_init = reset_released_ff ^ reset_released;

assign valid_pop = i_q_pop && !fifo_empty && pop_num_entries <= num_valid_entries;
assign valid_push = i_q_push && !fifo_full && push_num_entries <= num_free_entries;

always @ (posedge core_clk or posedge core_rst)
begin
    if(core_rst)
    begin
	wr_ptr  <=  'b0;
    end else begin
        if (reset_rel_init || i_initialize)
            wr_ptr <= {1'b1, {(C_PTR_WIDTH){1'b0}}};
	else if (valid_push) begin
	    if (wr_ptr[C_PTR_WIDTH-1:0] + push_num_entries < i_q_depth)
		wr_ptr[C_PTR_WIDTH-1 :0] <= wr_ptr[C_PTR_WIDTH -1:0] + push_num_entries;
	    else begin// roll over ater i_q_depth
		wr_ptr[C_PTR_WIDTH-1 :0] <= wr_ptr[C_PTR_WIDTH -1:0] + push_num_entries - i_q_depth;
		wr_ptr[C_PTR_WIDTH] <= ~wr_ptr[C_PTR_WIDTH];
	    end
	end
    end
end

generate
if (C_BRAM_N_FLOP == 0) begin

    for (i=0; i<C_Q_DEPTH; i=i+1) begin : mem_init
        always @ (posedge core_clk)
        begin
            if (i_initialize || reset_rel_init) begin
                mem[i] <= i;
            end else if (valid_push && i == wr_ptr[C_PTR_WIDTH -1:0]) begin
                mem[i] <= i_q_push_data;
            end
        end
    end

end else begin
    always @ (posedge core_clk or posedge core_rst)
    begin
        if(core_rst) begin
    	    mem_init  <=  'b0;
            init_start <= 1'b0;
        end else begin
            if (i_initialize || reset_rel_init) begin
                init_start <= 1'b1;
            end else if (&(mem_init) == 1'b1)
                init_start <= 1'b0;

            if (init_start)
                mem_init <= mem_init + 1'b1;
            else
                mem_init <= 'b0;
        end
    end

    blk_mem_gen_wrapper
        #(
        .c_mem_type                         (1),    // 0- Single Port RAM, 1-SDP RAM, 2-TDP RAM, 3-SP ROM, 4-DP ROM
        .c_byte_size                        (8),    // 8 or 9
        .c_has_mem_output_regs_a            (1),    // 0 or 1
        .c_has_mem_output_regs_b            (C_FLOP_BRAM_OUTPUT),    // 0 or 1
        .c_write_width_a                    (C_PTR_WIDTH),                           // 1 to 1152
        .c_write_depth_a                    (C_Q_DEPTH),       // 2 to 9011200
        .c_read_width_a                     (C_PTR_WIDTH),                           // 1 to 1152
        .c_read_depth_a                     (C_Q_DEPTH),       // 2 to 9011200
        .c_addra_width                      (C_PTR_WIDTH),                       // 1 to 24
        .c_write_mode_a                     ("WRITE_FIRST"),                               // WRITE_FIRST, READ_FIRST, NO_CHANGE
        .c_write_width_b                    (C_PTR_WIDTH),                           // 1 to 1152
        .c_write_depth_b                    (C_Q_DEPTH),       // 2 to 9011200
        .c_read_width_b                     (C_PTR_WIDTH),                           // 1 to 1152
        .c_read_depth_b                     (C_Q_DEPTH),       // 2 to 9011200
        .c_addrb_width                      (C_PTR_WIDTH),                       // 1 to 24
        .c_write_mode_b                     ("WRITE_FIRST")                                // WRITE_FIRST, READ_FIRST, NO_CHANGE
    ) inst_dcmd_tbl_bram
    (
        // Port A - used for writes into the block allocator fifo
        .clka                               (core_clk),
        .ssra                               (core_rst),
        .dina                               (i_q_push_data | mem_init),
        //.addra                              (i_dcmd_tbl_addr[2+:C_DCMD_TBL_INDX_WIDTH]), // The address is a byte address
        .addra                              (wr_ptr[C_PTR_WIDTH -1:0] | mem_init), // The address is a byte address
        .ena                                (1'b1),
        .regcea                             (1'b1),
        .wea                                (valid_push | init_start),
        .douta                              (),
        //Port B interface - used for block alloctor pop
        .clkb                               (core_clk),
        .ssrb                               (core_rst),
        .dinb                               ({C_PTR_WIDTH{1'b0}}),
        .addrb                              (rd_ptr[C_PTR_WIDTH -1:0]),
        .enb                                (1'b1),//(i_q_pop),
        .regceb                             (1'b1),
        .web                                (1'b0),
        .doutb                              (bram_rdata),

        .dbiterr                            (),
        .sbiterr                            ()

    );
    end

endgenerate

always @ (posedge core_clk or posedge core_rst)
begin
    if(core_rst)
    begin
	num_valid_entries  <=  'b0;
	num_free_entries   <=  C_Q_DEPTH;
    end else begin
	if (i_initialize) begin
	    num_free_entries <= 'b0;
	    num_valid_entries <= i_q_depth;
	end else if (valid_push & !valid_pop) begin
	    num_valid_entries <= num_valid_entries + push_num_entries;
	    num_free_entries <= num_free_entries - push_num_entries;
	end else if (valid_pop & !valid_push) begin
	    num_valid_entries <= num_valid_entries - pop_num_entries;
	    num_free_entries <= num_free_entries + pop_num_entries;
	end else if (valid_pop & valid_push) begin
	    num_valid_entries <= num_valid_entries - pop_num_entries + push_num_entries;
	    num_free_entries <= num_free_entries + pop_num_entries - push_num_entries;
	end
    end
end

assign fifo_empty = (wr_ptr == rd_ptr) ? 1'b1 : 1'b0;

assign fifo_full = (wr_ptr[C_PTR_WIDTH] != rd_ptr[C_PTR_WIDTH]) && (wr_ptr[C_PTR_WIDTH -1:0] == rd_ptr[C_PTR_WIDTH-1:0]);

assign o_q_full = fifo_full;
assign o_q_empty = fifo_empty;
assign o_q_pop_data = C_BRAM_N_FLOP ? bram_rdata : mem[rd_ptr[C_PTR_WIDTH -1:0]];
assign o_num_valid_entries = num_valid_entries;
assign o_num_free_entries = num_free_entries;
assign o_fifo_busy = C_BRAM_N_FLOP ? init_start : 1'b0;

endmodule

