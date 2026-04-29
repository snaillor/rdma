// wqe_proc_ack_buf.v
// 文件名          : wqe_proc_ack_buf.v
// 版本            : v1.0
// 描述            : WQE ACK 缓冲区模块，缓存接收到的 AETH 信息并传递给包头生成
// Verilog 标准    : Verilog'2001

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
`timescale 1ps/1ps

(* DowngradeIPIdentifiedWarnings="yes" *)
module wqe_proc_ack_buf
#( parameter C_MAX_QID_WIDTH = 3,
   parameter C_MAX_QP = 8,
   parameter C_FAMILY = "virtexu"
) (
    input                                       core_clk,
    input                                       core_rst,

    //Response handler ACK interface
    input                                       i_bres_valid,
    input                                       i_bres_exp_ack,
    input      [C_MAX_QID_WIDTH-1:0]            i_bres_dest_qpid,
    output                                      o_bres_fifo_full,
    input      [23:0]                           i_res_psn,
    input      [6:0]                            i_res_aeth_syndrome,
    input      [23:0]                           i_res_msn,

    input                                       i_hdr_gen_rdy,
    output reg                                  o_aeth_valid,
    output reg [31:0]                           o_aeth_hdr,
    output reg [C_MAX_QID_WIDTH-1:0]            o_aeth_qpid,
    output reg [23:0]                           o_aeth_psn,
    input                                       i_reg_rdma_en,
    input      [1:0]                            ack_resp_strategy
);

    localparam ACK_IGNORE_TIME = 4096;

    reg  [55 : 0]          aeth_bram_wr_data;
   (* mark_debug = "true" *) reg                                    aeth_bram_wr_en;
    wire [55 : 0]          aeth_bram_rd_data;
   (* mark_debug = "true" *) reg                                    aeth_bram_rd_en;
   (* mark_debug = "true" *) reg                                    aeth_bram_rd_en_r;
    reg  [C_MAX_QID_WIDTH-1 : 0] aeth_bram_wr_addr;
    reg  [C_MAX_QID_WIDTH-1 : 0] aeth_bram_rd_addr;
    reg  [15:0]                            ack_ign_cnt;
    reg  [C_MAX_QP-1:0]                    ignore_ack;
    reg  [C_MAX_QP-1:0]                    qp_ack_pending;
    reg  [C_MAX_QP-1:0]                    qp_nack_pending;
    reg  [C_MAX_QP-1:0]                    qp_send_acks;
    reg                                    arb_in_progress;

    integer i;

    assign o_bres_fifo_full = 1'b0;

    always @(posedge core_clk)
    begin
        if(core_rst) begin
            ack_ign_cnt <= 16'h0000;
            ignore_ack <= {C_MAX_QP{1'b0}};
            aeth_bram_wr_data <= 'd0;
            aeth_bram_wr_en <= 1'b0;
            aeth_bram_wr_addr <= {C_MAX_QID_WIDTH{1'b0}};
            qp_ack_pending <= {C_MAX_QP{1'b0}};
            qp_nack_pending <= {C_MAX_QP{1'b0}};
        end else begin
            if(ack_ign_cnt == ACK_IGNORE_TIME) begin
                ack_ign_cnt <= 16'h0000;
            end else if(ack_ign_cnt != ACK_IGNORE_TIME) begin
                ack_ign_cnt <= ack_ign_cnt + 1'b1;
            end

            aeth_bram_wr_data <= {i_res_psn,1'b0,i_res_aeth_syndrome,i_res_msn};
            aeth_bram_wr_addr <= i_bres_dest_qpid;
            for (i = 0; i < C_MAX_QP; i = i+1) begin
                if(i_reg_rdma_en && (i == i_bres_dest_qpid)) begin
                    aeth_bram_wr_en <= i_bres_valid;
                end
                if(i_reg_rdma_en && aeth_bram_wr_en && (i == aeth_bram_wr_addr)) begin
                //if(i_reg_rdma_en && i_bres_valid && (i == i_bres_dest_qpid)) begin
                    qp_ack_pending[i] <= 1'b1;
                    //qp_nack_pending[i] <= (|i_res_aeth_syndrome[6:5]) || i_bres_exp_ack;
                    qp_nack_pending[i] <= (|aeth_bram_wr_data[30:29]) || i_bres_exp_ack || qp_nack_pending[i];
                end else if (aeth_bram_rd_en && (i == aeth_bram_rd_addr)) begin
                    qp_ack_pending[i] <= 1'b0;
                    qp_nack_pending[i] <= 1'b0;
                end
            end
        end
    end

    always @(posedge core_clk)
    begin
        if(core_rst) begin
            aeth_bram_rd_en <= 1'b0;
            aeth_bram_rd_en_r <= 1'b0;
            o_aeth_valid <= 1'b0;
            o_aeth_hdr <= 32'd0;
            o_aeth_qpid <= 'd0;
            o_aeth_psn <= 'd0;
            aeth_bram_rd_addr <= {C_MAX_QID_WIDTH{1'b0}};
            arb_in_progress <= 1'b1;
            qp_send_acks <= {C_MAX_QP{1'b0}};
        end else begin
            aeth_bram_rd_en_r <= aeth_bram_rd_en;
            if( ~arb_in_progress && ~o_aeth_valid && ~aeth_bram_rd_en) begin
                aeth_bram_rd_en <= 1'b1;
            end else begin
                aeth_bram_rd_en <= 1'b0;
            end

            if((ack_ign_cnt == ACK_IGNORE_TIME || ack_resp_strategy == 2'b01) && (ack_resp_strategy != 2'b10)) begin
                for(i=0; i < C_MAX_QP; i = i+1) begin
                    if((i == aeth_bram_rd_addr) && aeth_bram_rd_en && ~(i_bres_valid && (i == i_bres_dest_qpid))) begin
                        qp_send_acks[i] <= 1'b0;
                    end else begin
                        qp_send_acks[i] <= qp_ack_pending[i];
                    end
                end
            end else if(aeth_bram_rd_en) begin
                for(i=0; i < C_MAX_QP; i = i+1) begin
                    if(i == aeth_bram_rd_addr) begin
                        qp_send_acks[i] <= 1'b0;
                    end
                end
            end

            if(aeth_bram_rd_en == 1'b1) begin
                arb_in_progress <= 1'b1;
                aeth_bram_rd_addr <= aeth_bram_rd_addr;
            end else if(arb_in_progress && ((|qp_send_acks) || (|qp_nack_pending))) begin
                if(aeth_bram_rd_addr < C_MAX_QP-1) begin
                    aeth_bram_rd_addr <= aeth_bram_rd_addr + 1'b1;
                    for(i=0; i < C_MAX_QP; i = i+1) begin
                        if((i == aeth_bram_rd_addr) && (i != C_MAX_QP-1)) begin
                            arb_in_progress <= ~(qp_send_acks[i+1] || qp_nack_pending[i+1]);
                        end else if ((i == aeth_bram_rd_addr) && (i == C_MAX_QP-1)) begin
                            arb_in_progress <= ~(qp_send_acks[0] || qp_nack_pending[0]);
                        end
                    end
                end else begin
                    aeth_bram_rd_addr <= 'd2;
                    arb_in_progress <= ~(qp_send_acks[2] || qp_nack_pending[2]);
                end
            end

            if(aeth_bram_rd_en_r) begin
                o_aeth_valid <= 1'b1;
                o_aeth_hdr <= aeth_bram_rd_data[31:0];
                o_aeth_qpid <= aeth_bram_rd_addr;
                o_aeth_psn <= aeth_bram_rd_data[55:32];
            end else if (i_hdr_gen_rdy) begin
                o_aeth_valid <= 1'b0;
            end
        end
    end

///////////////////////////////////////////////////////////////////////////////////////////
///////////////// Block RAM for Header pointer and buffer address /////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////
/*    blk_mem_gen_wrapper
         #(
             .c_mem_type                        (1),    // 0- Single Port RAM, 1-SDP RAM, 2-TDP RAM, 3-SP ROM, 4-DP ROM
             .c_byte_size                       (8),    // 8 or 9   // Updated to 8 since ECC is not enabled.
             .c_has_mem_output_regs_a           (0),    // 0 or 1
             .c_has_mem_output_regs_b           (0),    // 0 or 1
             .c_has_ssra                        (1),    // -- 0, 1
             .c_sinita_val                      ("0"),    // --"..."
             .c_write_width_a                   (56),   // 1 to 1152
             .c_write_depth_a                   (C_MAX_QP),      // 2 to 9011200
             .c_read_width_a                    (56),   // 1 to 1152
             .c_read_depth_a                    (C_MAX_QP),      // 2 to 9011200
             .c_addra_width                     (C_MAX_QID_WIDTH),      // 1 to 24
             .c_write_mode_a                    ("READ_FIRST"),        // WRITE_FIRST, READ_FIRST, NO_CHANGE
             .c_use_byte_wea                    (1),  // Added for Narrow Write
             .c_wea_width                       (8),  // Added for Narrow Write
             .c_use_byte_web                    (1),   // Added for Narrow Write
             .c_web_width                       (8), // Added for Narrow Write
             .c_has_ssrb                        (1),    // -- 0, 1
             .c_sinitb_val                      ("0"),    // --"..."
             .c_write_width_b                   (56),   // 1 to 1152
             .c_write_depth_b                   (C_MAX_QP),      // 2 to 9011200
             .c_read_width_b                    (56),   // 1 to 1152
             .c_read_depth_b                    (C_MAX_QP),      // 2 to 9011200
             .c_addrb_width                     (C_MAX_QID_WIDTH),      // 1 to 24
             .c_write_mode_b                    ("READ_FIRST")         // WRITE_FIRST, READ_FIRST, NO_CHANGE
         )
              hdr_ptr_bram
         (
             .clka                (core_clk),
             .ssra                (core_rst),
             .dina                (aeth_bram_wr_data),
             .addra               (aeth_bram_wr_addr),
             .ena                 (aeth_bram_wr_en),// Enable port A only for active read and write request
             .regcea              (1'b1),
             .wea                 ({8{1'b1}}),//(bus2ip_dvalid), // Write data valid
             .douta               (),
     //Port B interface
             .clkb                (core_clk),
             .ssrb                (core_rst),
             .dinb                ({56{1'b0}}),
             .addrb               (aeth_bram_rd_addr),
             .enb                 (aeth_bram_rd_en),
             .regceb              (1'b1),
             .web                 ({8{1'b0}}),//(web),
             .doutb               (aeth_bram_rd_data),

             .dbiterr             (        ),
             .sbiterr             (        )

       );  */

xpm_memory_sdpram # (

  // Common module parameters
  .MEMORY_SIZE        (56*C_MAX_QP),            //positive integer
  .MEMORY_PRIMITIVE   ("ultra"),          //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("common_clock"),  //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),          //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),          //string;
  .USE_MEM_INIT       (1),               //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"), //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),               //integer; 0,1
  .ECC_MODE           ("no_ecc"),        //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),               //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (56),              //positive integer
  .BYTE_WRITE_WIDTH_A (8),              //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (C_MAX_QID_WIDTH),               //positive integer

  // Port B module parameters
  .READ_DATA_WIDTH_B  (56),              //positive integer
  .ADDR_WIDTH_B       (C_MAX_QID_WIDTH),               //positive integer
  .READ_RESET_VALUE_B ("0"),             //string
  .READ_LATENCY_B     (1),               //non-negative integer
  .WRITE_MODE_B       ("read_first")     //string; "write_first", "read_first", "no_change"

) hdr_ptr_bram (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (core_clk),
  .ena            (aeth_bram_wr_en),
  .wea            ({7{1'b1}}),
  .addra          (aeth_bram_wr_addr),
  .dina           (aeth_bram_wr_data),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (core_rst),
  .enb            (aeth_bram_rd_en),
  .regceb         (1'b1),
  .addrb          (aeth_bram_rd_addr),
  .doutb          (aeth_bram_rd_data),
  .sbiterrb       (),
  .dbiterrb       ()

);

endmodule

