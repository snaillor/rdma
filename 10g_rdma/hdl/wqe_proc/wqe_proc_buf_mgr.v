// wqe_proc_buf_mgr.v
// 文件名          : wqe_proc_buf_mgr.v
// 版本            : v1.0
// 描述            : WQE 缓冲区管理模块，管理发送头部缓冲区和 SGL 缓冲区
//                   根据寄存器配置生成 SGL 列表，协调 DMA 数据读取
// Verilog 标准    : Verilog'2001

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
`timescale 1ps/1ps

(* DowngradeIPIdentifiedWarnings="yes" *)
module wqe_proc_buf_mgr
#(
    parameter C_MAX_QP = 8,
    parameter C_MAX_QID_WIDTH = 3,
    parameter C_M_AXI_DATA_WIDTH = 512,
    parameter C_M_AXI_ADDR_WIDTH = 32,
    parameter C_M_AXI_ID_WIDTH = 4,
    parameter C_S_AXI_DATA_WIDTH = 512,
    parameter C_S_AXI_ADDR_WIDTH = 32,
    parameter C_S_AXI_ID_WIDTH = 4,
    parameter C_AXI_DMA_ADDR = 32'h50024000,
    parameter IP2BUS_LEN_WIDTH = 8,
    parameter C_MAX_HDR_DEPTH = 128,
    parameter C_EN_DEBUG = 0,
    parameter C_MAX_SGL_DEPTH = 32
 ) (
    input                                       core_clk,
    input                                       core_rst,

    output reg                                  o_buf_mngr_rdy,
    input       [1023:0]                        i_hdr_data,
    input       [7:0]                           i_hdr_len,
    input                                       i_hdr_valid,

    input       [31:0]                          i_reg_tx_hdr_buf_ba,
    input       [15:0]                          i_reg_tx_hdr_buf_depth,
    input       [15:0]                          i_reg_tx_hdr_buf_size,
    input       [31:0]                          i_reg_tx_sgl_buf_ba,
    input       [15:0]                          i_reg_tx_sgl_buf_depth,
    input       [15:0]                          i_reg_tx_sgl_buf_size,
    input                                       i_reg_ip_ver,

    //Axi master interface
    output  reg    [C_M_AXI_ADDR_WIDTH -1 :0 ]  maxi_addr,
   (* mark_debug = "true" *) output  reg                                 maxi_wr_rdn,
   (* mark_debug = "true" *) output  reg                                 maxi_en,
    output  reg    [IP2BUS_LEN_WIDTH-1:0]       maxi_len,
    input                                       maxi_wdata_rdy,
    output  reg    [C_M_AXI_DATA_WIDTH-1:0]     maxi_wdata,
    input          [C_M_AXI_DATA_WIDTH-1:0]     maxi_rdata,
    input                                       maxi_rvalid,
   (* mark_debug = "true" *) input                                       maxi_done,
   (* mark_debug = "true" *) input                                       maxi_busy,
   (* mark_debug = "true" *) input                                       maxi_error,

    output      [19:0]                           buf_mgr_ptr,
    //SGL Buffer signals
    output reg [15:0]                            sgl_head_ptr,
    input [14:0]                                 sgl_bram_rd_addr,
    input                                        sgl_bram_rd_en,
    output [511:0]                               sgl_bram_rd_data,
    input [14:0]                                 hdr_bram_rd_addr,
    input                                        hdr_bram_rd_en,
    output [511:0]                               hdr_bram_rd_data,
    input                                        hdr_bram_pop,

    input                                       wqe_opcode_err,
    input      [31:0]                           i_out_errsts_q_ba,
    input      [15:0]                           i_out_errsts_q_sz,
    output reg [15:0]                           o_out_errsts_q_wrptr,
    input                                       i_intr_en_ill_opc_in_sq,
    input                                       i_intr_clr_ill_opc_in_sq,
    output reg                                  o_ill_opc_in_sq_intr,
    input                                       i_debug_cnt_en,
    input                                       i_debug_cnt_clr,
    output reg  [15:0]                          o_wqe_proc_hdr_sgl_buf_full_cnt,
    output reg  [15:0]                          o_wqe_proc_maxis_bk_pressure,
    input                                       i_m_axis_bkp_pressure
);
`include "rdma_macros.vh"

    localparam SGL_BRAM_ADDR_WIDTH = clog2(C_MAX_SGL_DEPTH);
    localparam HDR_BRAM_ADDR_WIDTH = clog2(C_MAX_HDR_DEPTH);
    localparam IDLE = 3'b001;
    localparam EN_DMA = 3'b000;
    localparam WR_HDR = 3'b010;
    localparam WR_DMA_TAIL = 3'b011;
    localparam WAIT_ON_AXI = 3'b100;
    localparam RST_DMA = 3'b101;

   (* mark_debug = "true" *) reg  [2:0]                        buf_mgr_cs;
    reg  [15:0]                       hdr_head_ptr;
    reg  [15:0]                       hdr_tail_ptr;
    reg  [15:0]                       sgl_head_ptr_prev;
    reg  [15:0]                       sgl_tail_ptr;
    reg  [511:0]                      sgl_bram_wr_data;
    wire [SGL_BRAM_ADDR_WIDTH-1:0]    sgl_bram_wr_addr;
    reg                               sgl_bram_wr_en;
    reg                               sgl_bram_rd_en_r;
    reg                               hdr_bram_rd_en_r;
    wire [31:0]                       sgl_next_desc;
    reg                               sgl_wr_done;
    reg                               sgl_wr_wait;
    reg  [511:0]                      hdr_bram_wr_data;
    reg  [HDR_BRAM_ADDR_WIDTH:0]      hdr_bram_wr_addr;
    reg                               hdr_bram_wr_en;
   (* mark_debug = "true" *) reg                               sgl_buf_full;
   (* mark_debug = "true" *) reg                               dma_error;
   (* mark_debug = "true" *) reg                               hdr_buf_full;
   (* mark_debug = "true" *) reg  [SGL_BRAM_ADDR_WIDTH-1:0]    sgl_wr_cnt;
    reg                               curr_desc_done;
    reg                               dma_en_done;
    reg                               dma_cr_done;
    reg                               m_axis_bkp_pressure;

//////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////// Debug counters logic //////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////
    generate if(C_EN_DEBUG == 1) begin:DEBUG_EN
        always @(posedge core_clk)
        begin
            if(core_rst) begin
                o_wqe_proc_hdr_sgl_buf_full_cnt <= 16'h0000;
                m_axis_bkp_pressure <= 1'b0;
                o_wqe_proc_maxis_bk_pressure <= 16'h0000;
            end else begin
                if(i_m_axis_bkp_pressure) begin
                    m_axis_bkp_pressure <= 1'b1;
                end
                if(i_debug_cnt_clr) begin
                    o_wqe_proc_hdr_sgl_buf_full_cnt <= 16'h0000;
                end else if (i_debug_cnt_en && (sgl_buf_full || hdr_buf_full)) begin
                    o_wqe_proc_hdr_sgl_buf_full_cnt <= o_wqe_proc_hdr_sgl_buf_full_cnt + 1'b1;
                end
                if(i_debug_cnt_clr) begin
                    o_wqe_proc_maxis_bk_pressure <= 16'h0000;
                end else if (i_debug_cnt_en && i_m_axis_bkp_pressure) begin
                    o_wqe_proc_maxis_bk_pressure <= o_wqe_proc_maxis_bk_pressure + 1'b1;
                end
            end
        end
    end else begin
        always@(*) begin
            o_wqe_proc_hdr_sgl_buf_full_cnt = 16'h0000;
            m_axis_bkp_pressure <= 1'b0;
            o_wqe_proc_maxis_bk_pressure <= 16'h0000;
        end
    end
    endgenerate

    assign sgl_bram_wr_addr = sgl_head_ptr[SGL_BRAM_ADDR_WIDTH-1:0];
    assign sgl_next_desc = {i_reg_tx_sgl_buf_ba[31:6] + (((sgl_head_ptr[14:0] + 1'b1) == i_reg_tx_sgl_buf_depth) ? 15'h0000 : (sgl_head_ptr[14:0] + 1'b1)),6'h00};
    assign buf_mgr_ptr = {sgl_head_ptr[7:0],sgl_tail_ptr[7:0],buf_mgr_cs,m_axis_bkp_pressure};

    always @(posedge core_clk)
    begin
        if(core_rst) begin
            o_buf_mngr_rdy <= 1'b0;
            maxi_addr <= {C_M_AXI_ADDR_WIDTH{1'b0}};
            maxi_wr_rdn <= 1'b0;
            maxi_en <= 1'b0;
            maxi_len <= {IP2BUS_LEN_WIDTH{1'b0}};
            maxi_wdata <= {C_M_AXI_DATA_WIDTH{1'b0}};
            hdr_head_ptr <= 16'h0000;
            sgl_bram_wr_en <= 1'b0;
            sgl_bram_wr_data <= 512'd0000000000000000;
            sgl_wr_done <= 1'b1;
            sgl_wr_wait <= 1'b0;
            buf_mgr_cs <= IDLE;
            curr_desc_done <= 1'b0;
            dma_en_done <= 1'b0;
            dma_cr_done <= 1'b0;
            o_out_errsts_q_wrptr <= 16'h0000;
        end else begin
            sgl_bram_wr_data[510:82] <= 'd0;
            case (buf_mgr_cs)
                IDLE: begin
                    o_buf_mngr_rdy <= 1'b0;
                    if(~sgl_buf_full && ~hdr_buf_full && (i_hdr_valid && ~o_buf_mngr_rdy) && (i_hdr_data[959:944] != 16'h0001)) begin
                        sgl_bram_wr_data[511] <= 1'b0;
                        if(wqe_opcode_err) begin
                            buf_mgr_cs <= WR_HDR;
                            sgl_bram_wr_en <= 1'b0;
                            maxi_en <= 1'b1;
                            maxi_wr_rdn <= 1'b1;
                            maxi_addr <= (i_out_errsts_q_ba + (o_out_errsts_q_wrptr[14:0] * 'd32));
                            maxi_wdata <= i_hdr_data[511:0];
                            maxi_len <= 'd32;
                            sgl_wr_done <= 1'b1;
                            hdr_bram_wr_en <= 1'b0;
                        end else begin
                            hdr_bram_wr_en <= 1'b1;
                            hdr_bram_wr_addr <= {hdr_head_ptr[HDR_BRAM_ADDR_WIDTH-1:0],1'b0};
                            hdr_bram_wr_data <= i_hdr_data[511:0];
                            buf_mgr_cs <= WR_HDR;
                            sgl_bram_wr_en <= 1'b1;
                            sgl_bram_wr_data[79:0] <= {8'h00,i_hdr_len,32'd0,(i_reg_tx_hdr_buf_ba + (hdr_head_ptr[14:0] * i_reg_tx_hdr_buf_size))};
                            sgl_bram_wr_data[80] <= 1'b1;
                            if(i_reg_ip_ver) begin
                                if(i_hdr_data[503:496] == 8'h0C || (i_hdr_data[503:496] == 8'h04 && i_hdr_data[959]) || i_hdr_data[503:496] == 8'h11 ) begin
                                    sgl_bram_wr_data[81] <= 1'b1;
                                    sgl_wr_done <= 1'b1;
                                end else begin
                                    sgl_bram_wr_data[81] <= 1'b0;
                                    sgl_wr_done <= 1'b0;
                                    sgl_wr_wait <= 1'b1;
                                end
                            end else begin
                                if(i_hdr_data[343:336] == 8'h0C || (i_hdr_data[343:336] == 8'h04 && i_hdr_data[959]) || i_hdr_data[343:336] == 8'h11 || ~|i_hdr_data[1023:1008]) begin
                                    sgl_bram_wr_data[81] <= 1'b1;
                                    sgl_wr_done <= 1'b1;
                                end else begin
                                    sgl_bram_wr_data[81] <= 1'b0;
                                    sgl_wr_done <= 1'b0;
                                    sgl_wr_wait <= 1'b1;
                                end
                            end
                        end
                    end else if (~sgl_buf_full && ~hdr_buf_full && (i_hdr_valid && ~o_buf_mngr_rdy) && (i_hdr_data[958:944] == 15'h0001)) begin
                        sgl_bram_wr_data[511] <= 1'b1;
                        sgl_bram_wr_en <= 1'b1;
                        sgl_wr_done <= 1'b1;
                        sgl_bram_wr_data[81:80] <= 2'b11;
                        sgl_bram_wr_data[79:0] <= {i_hdr_data[1023:1008],16'h0000,i_hdr_data[1007:960]};
                        buf_mgr_cs <= WR_HDR;
                        hdr_bram_wr_en <= 1'b0;
                    end else begin
                        hdr_bram_wr_en <= 1'b0;
                        sgl_bram_wr_en <= 1'b0;
                    end
                 end
                 WR_HDR:begin
                     hdr_bram_wr_en <= (i_hdr_data[958:944] != 15'h0001);
                     hdr_bram_wr_addr <= {hdr_head_ptr[6:0],1'b1};
                     hdr_bram_wr_data <= i_hdr_data[1023:512];
                     if((~maxi_busy && ~maxi_en && sgl_wr_done) || (i_hdr_data[958:944] == 15'h0001)) begin
                         o_buf_mngr_rdy <= 1'b1;
                         if(wqe_opcode_err) begin
                             buf_mgr_cs <= IDLE;
                             if(o_out_errsts_q_wrptr == i_out_errsts_q_sz - 1'b1) begin
                                 o_out_errsts_q_wrptr <= 16'h0000;
                             end else begin
                                 o_out_errsts_q_wrptr <= o_out_errsts_q_wrptr + 1'b1;
                             end
                         end else begin
                            buf_mgr_cs <= IDLE;
                            if((i_hdr_data[958:944] != 15'h0001) && (hdr_head_ptr[14:0] == i_reg_tx_hdr_buf_depth - 1'b1)) begin
                                hdr_head_ptr[14:0] <= 15'h0000;
                                hdr_head_ptr[15] <= ~hdr_head_ptr[15];
                            end else if((i_hdr_data[958:944] != 15'h0001)) begin
                                hdr_head_ptr[14:0] <= hdr_head_ptr[14:0] + 1'b1;
                            end
                        end
                    end
                     maxi_en <= 1'b0;
                     if(sgl_wr_wait ) begin
                         sgl_wr_wait <= 1'b0;
                         sgl_bram_wr_en <= 1'b0;
                     end else if(~sgl_wr_done && ~((sgl_tail_ptr[14:0] == sgl_head_ptr[14:0] ) && (sgl_tail_ptr[15] != sgl_head_ptr[15]))) begin
                         sgl_bram_wr_en <= 1'b1;
                         sgl_wr_done <= 1'b1;
                         sgl_bram_wr_data[81:80] <= 2'b10;
                         sgl_bram_wr_data[79:0] <= {i_hdr_data[1023:1008],16'h0000,i_hdr_data[1007:960]};
                     end else begin
                        sgl_bram_wr_en <= 1'b0;
                     end
                 end
             endcase
        end
    end

    always @(posedge core_clk)
    begin
        if(core_rst) begin
            sgl_head_ptr <= 16'h0000;
            sgl_head_ptr_prev <= 16'h0000;
            sgl_tail_ptr <= 16'h0000;
            sgl_buf_full <= 1'b0;
            hdr_buf_full <= 1'b0;
            hdr_tail_ptr <= 16'h0000;
            sgl_bram_rd_en_r <= 1'b0;
            hdr_bram_rd_en_r <= 1'b0;
            dma_error <= 1'b0;
            sgl_wr_cnt <= {SGL_BRAM_ADDR_WIDTH{1'b0}};
            o_ill_opc_in_sq_intr <= 1'b0;
        end else begin
            sgl_buf_full <= (sgl_tail_ptr[14:0] == sgl_head_ptr[14:0] ) && (sgl_tail_ptr[15] != sgl_head_ptr[15]);
            hdr_buf_full <= (hdr_tail_ptr[14:0] == hdr_head_ptr[14:0] ) && (hdr_tail_ptr[15] != hdr_head_ptr[15]);
            if(sgl_bram_wr_en) begin
                sgl_head_ptr_prev <= sgl_head_ptr;
                if(sgl_head_ptr[14:0] == i_reg_tx_sgl_buf_depth - 1'b1) begin
                    sgl_head_ptr[14:0] <= 15'h0000;
                    sgl_head_ptr[15] <= ~sgl_head_ptr[15];
                end else begin
                    sgl_head_ptr[14:0] <= sgl_head_ptr[14:0] + 1'b1;
                end
            end
            sgl_bram_rd_en_r <= sgl_bram_rd_en;
            hdr_bram_rd_en_r <= hdr_bram_rd_en;

//            if(sgl_bram_rd_en_r && ~sgl_bram_rd_en) begin
            if(sgl_bram_rd_en) begin
                    if(sgl_tail_ptr[14:0] == i_reg_tx_sgl_buf_depth - 1'b1) begin
                        sgl_tail_ptr[14:0] <= 15'h0000;
                        sgl_tail_ptr[15] <= ~sgl_tail_ptr[15];
                    end else begin
                        sgl_tail_ptr[14:0] <= sgl_tail_ptr[14:0] + 1'b1;
                    end
            end

//            if(hdr_bram_rd_en_r && ~hdr_bram_rd_en) begin
//              if(hdr_bram_rd_en && ~hdr_bram_rd_addr[0]) beginhdr_bram_pop
              if(hdr_bram_pop)begin
                if(hdr_tail_ptr[14:0] == i_reg_tx_hdr_buf_depth - 1'b1) begin
                    hdr_tail_ptr[14:0] <= 15'h0000;
                    hdr_tail_ptr[15] <= ~hdr_tail_ptr[15];
                end else begin
                    hdr_tail_ptr[14:0] <= hdr_tail_ptr[14:0] + 1'b1;
                end
            end
            ////////////////////////////////////////////////////////////////////
            ////////// Interrupt enable logic //////////////////////////////////
            ////////////////////////////////////////////////////////////////////

            if(wqe_opcode_err && maxi_done && i_intr_en_ill_opc_in_sq) begin
                o_ill_opc_in_sq_intr <= 1'b1;
            end else if(i_intr_clr_ill_opc_in_sq) begin
                o_ill_opc_in_sq_intr <= 1'b1;
            end
        end
    end

xpm_memory_sdpram # (

  // Common module parameters
  .MEMORY_SIZE        (512*C_MAX_SGL_DEPTH),            //positive integer
  .MEMORY_PRIMITIVE   ("ultra"),                         //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("common_clock"),                 //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),                         //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),                         //string;
  .USE_MEM_INIT       (1),                              //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"),                //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),                              //integer; 0,1
  .ECC_MODE           ("no_ecc"),                       //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),                              //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (512),                            //positive integer
  .BYTE_WRITE_WIDTH_A (512),                            //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (SGL_BRAM_ADDR_WIDTH),            //positive integer

  // Port B module parameters
  .READ_DATA_WIDTH_B  (512),                            //positive integer
  .ADDR_WIDTH_B       (SGL_BRAM_ADDR_WIDTH),            //positive integer
  .READ_RESET_VALUE_B ("0"),                            //string
  .READ_LATENCY_B     (1),                              //non-negative integer
  .WRITE_MODE_B       ("read_first")                    //string; "write_first", "read_first", "no_change"

) sgl_buffer_xpm (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (core_clk),
  .ena            (sgl_bram_wr_en),
  .wea            ({64{1'b1}}),
  .addra          (sgl_bram_wr_addr),
  .dina           (sgl_bram_wr_data),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (core_rst),
  .enb            (sgl_bram_rd_en),
  .regceb         (1'b1),
  .addrb          (sgl_bram_rd_addr[SGL_BRAM_ADDR_WIDTH-1:0]),
  .doutb          (sgl_bram_rd_data),
  .sbiterrb       (),
  .dbiterrb       ()

);

xpm_memory_sdpram # (

  // Common module parameters
  .MEMORY_SIZE        (512*2*C_MAX_HDR_DEPTH),          //positive integer
  .MEMORY_PRIMITIVE   ("ultra"),                        //string; "auto", "distributed", "block" or "ultra";
  .CLOCKING_MODE      ("common_clock"),                 //string; "common_clock", "independent_clock"
  .MEMORY_INIT_FILE   ("none"),                         //string; "none" or "<filename>.mem"
  .MEMORY_INIT_PARAM  (""    ),                         //string;
  .USE_MEM_INIT       (1),                              //integer; 0,1
  .WAKEUP_TIME        ("disable_sleep"),                //string; "disable_sleep" or "use_sleep_pin"
  .MESSAGE_CONTROL    (0),                              //integer; 0,1
  .ECC_MODE           ("no_ecc"),                       //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
  .AUTO_SLEEP_TIME    (0),                              //Do not Change

  // Port A module parameters
  .WRITE_DATA_WIDTH_A (512),                            //positive integer
  .BYTE_WRITE_WIDTH_A (512),                            //integer; 8, 9, or WRITE_DATA_WIDTH_A value
  .ADDR_WIDTH_A       (HDR_BRAM_ADDR_WIDTH+1),          //positive integer

  // Port B module parameters
  .READ_DATA_WIDTH_B  (512),                            //positive integer
  .ADDR_WIDTH_B       (HDR_BRAM_ADDR_WIDTH+1),          //positive integer
  .READ_RESET_VALUE_B ("0"),                            //string
  .READ_LATENCY_B     (1),                              //non-negative integer
  .WRITE_MODE_B       ("read_first")                    //string; "write_first", "read_first", "no_change"

) hdr_buffer_xpm (

  // Common module ports
  .sleep          (1'b0),

  // Port A module ports
  .clka           (core_clk),
  .ena            (hdr_bram_wr_en),
  .wea            ({64{1'b1}}),
  .addra          (hdr_bram_wr_addr),
  .dina           (hdr_bram_wr_data),
  .injectsbiterra (1'b0),
  .injectdbiterra (1'b0),

  // Port B module ports
  .clkb           (core_clk),
  .rstb           (core_rst),
  .enb            (hdr_bram_rd_en),       //bus2ip_rd_req),
  .regceb         (1'b1),
  .addrb          (hdr_bram_rd_addr[HDR_BRAM_ADDR_WIDTH:0]),
  .doutb          (hdr_bram_rd_data),
  .sbiterrb       (),
  .dbiterrb       ()

);

endmodule

