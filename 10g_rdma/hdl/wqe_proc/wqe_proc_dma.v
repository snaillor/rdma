// wqe_proc_dma.v
// 文件名          : wqe_proc_dma.v
// 版本            : v1.0
// 描述            : WQE DMA 引擎模块，通过 AXI4 接口从 DDR/BRAM 读取发送数据
//                   解析 SGL 列表，区分数据段与头部段，输出 AXI-Stream 数据流
// Verilog 标准    : Verilog'2001

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
`timescale 1ps/1ps

(* DowngradeIPIdentifiedWarnings="yes" *)
module wqe_proc_dma
  #(
    parameter C_M_AXI_DATA_WIDTH = 512,
    parameter C_M_AXI_ADDR_WIDTH = 32,
    parameter C_M_AXI_ID_WIDTH = 4,
    parameter C_AXIS_DATA_WIDTH = 512,
    parameter C_MAX_SGL_DEPTH = 128,
    parameter C_SGL_DATA_WIDTH = 82,
    parameter C_HDR_BUF_ADDR_WIDTH = 32,
    parameter C_HDR_BUF_DEPTH = 128,
    parameter C_VIVADO_VER = 1,
    parameter C_FAMILY = "virtex7"
    )
  (
   input                                core_clk,
   input                                core_rst,

   // AXI-4 Master signals
   output [C_M_AXI_ID_WIDTH-1 :0]       m_axi_dma_arid,
   output reg [C_M_AXI_ADDR_WIDTH-1:0]  m_axi_dma_araddr,
   output reg [7:0]                     m_axi_dma_arlen,
   output [2:0]                         m_axi_dma_arsize,
   output [1:0]                         m_axi_dma_arburst,
   output [3:0]                         m_axi_dma_arcache,
   output [2:0]                         m_axi_dma_arprot,
   output                               m_axi_dma_arvalid,
   input                                m_axi_dma_arready,
   input [C_M_AXI_ID_WIDTH-1 :0]        m_axi_dma_rid,
   input [C_M_AXI_DATA_WIDTH-1:0]       m_axi_dma_rdata,
   input [1:0]                          m_axi_dma_rresp,
   input                                m_axi_dma_rlast,
   input                                m_axi_dma_rvalid,
   output                               m_axi_dma_rready,
   output                               m_axi_dma_arlock,
   //AXI-4 Stream signals
   output reg [C_AXIS_DATA_WIDTH-1 : 0] m_axis_dma_tdata,
   output reg [C_AXIS_DATA_WIDTH/8-1:0] m_axis_dma_tkeep,
   output                               m_axis_dma_tvalid,
   input                                m_axis_dma_tready,
   output reg                           m_axis_dma_tlast,
   //SGL Buffer signals
   input [15:0]                         sgl_head_ptr,
   output [14:0]                        sgl_bram_rd_addr,
   output                               sgl_bram_rd_en,
   input [C_SGL_DATA_WIDTH-1:0]         sgl_bram_rd_data,
   output [14:0]                        hdr_bram_rd_addr,
   output                               hdr_bram_rd_en,
   input [511:0]                        hdr_bram_rd_data,
   //From Config space
   input [15:0]                         i_reg_tx_sgl_buf_depth,
   output reg                           o_dma_in_idle,
   output reg                           hdr_bram_pop
   );

`include "rdma_macros.vh"
//AXIS header and data write control FSM states
  localparam WRITE_HDR_1 = 2'b00;
  localparam WRITE_HDR_2 = 2'b01;
  localparam WRITE_DATA  = 2'b10;
/////////////////////////
  localparam SGL_TAIL_PTR_WIDTH = 16;
  localparam SGL_BRAM_ADDR_WIDTH = clog2(C_MAX_SGL_DEPTH);

  localparam SGL_ADDR_WIDTH = 64;
  localparam SGL_ADDR_LSB = 0;
  localparam SGL_LEN_WIDTH = 16;
  localparam SGL_LEN_LSB = SGL_ADDR_WIDTH;
  localparam SGL_SOF_LSB = SGL_LEN_LSB + SGL_LEN_WIDTH;
  localparam SGL_EOF_LSB = SGL_SOF_LSB + 1;
  localparam SGL_QP1_HDR_VAL_LSB = 511;

///////////////////////////////////////////////
//      AXI stream fifo bit arrangements     //
//  576     [575:512]  [511:0]               //
///////////////////////////////////////////////
  localparam AXIS_FIFO_TDATA_LSB = 0;
  localparam AXIS_FIFO_TDATA_W   = 512;
  localparam AXIS_FIFO_TKEEP_LSB = 512;
  localparam AXIS_FIFO_TKEEP_W   = 64;
  localparam AXIS_FIFO_TLAST_LSB = 576;
  localparam AXIS_FIFO_TLAST_W   = 1;

//AXI REQ FIFO Parameters
// 32(ADDR)+8(LEN)+SOF_EOF= 42
  localparam AXI_REQ_FIFO_WIDTH = C_M_AXI_ADDR_WIDTH + 13;

//AXIS DATA FIFO Parameters
//Width = 512(DATA)+64(TKEEP)+1(TLAST) = 577
  localparam AXIS_DATA_FIFO_WIDTH = 512 + 64 + 1;

//AXI LEN FIFO Parameters
//width = 6(LEN) + 1(EOF)= 7
  localparam AXI_LEN_FIFO_WIDTH = 7;
  localparam AXI_LEN_FIFO_EOF_LSB = 6;

//HDR REQ FIFO Parameters
// C_HDR_BUF_ADDR_WIDTH + 6(LEN) + 1(len>64) + 1(len[6]) +1(EOF) + 1(QP1_HDR_VAL)
  localparam HDR_REQ_FIFO_LEN_W   = 6;
  localparam HDR_REQ_FIFO_LEN_LSB = (C_HDR_BUF_ADDR_WIDTH + 1);
  localparam HDR_REQ_FIFO_EOF_LSB = (C_HDR_BUF_ADDR_WIDTH + 1)  + HDR_REQ_FIFO_LEN_W + 2;
  localparam HDR_QP1_HDR_VAL_LSB  = (C_HDR_BUF_ADDR_WIDTH + 1)  + HDR_REQ_FIFO_LEN_W + 3;
  localparam HDR_REQ_FIFO_WIDTH   = (C_HDR_BUF_ADDR_WIDTH + 1)  + HDR_REQ_FIFO_LEN_W + 1 + 1 + 1 + 1;

////////
  localparam VALID_DIS = 1'b0;
  localparam VALID_EN  = 1'b1;


  localparam TVALID_DIS = 1'b0;
  localparam TVALID_EN  = 1'b1;

//Declarations
  reg [SGL_TAIL_PTR_WIDTH-1:0]      sgl_tail_ptr;
  wire                              sgl_hd_ptr_neq_tail_ptr;
  reg                               sgl_data_push;

  wire [AXI_REQ_FIFO_WIDTH-1:0]     axi_req_fifo_data_in;
  wire [AXI_LEN_FIFO_WIDTH-1:0]     axi_len_fifo_data_in;
  wire [HDR_REQ_FIFO_WIDTH-1:0]     hdr_req_fifo_data_in;
  wire [AXIS_DATA_FIFO_WIDTH-1+32:0]   axis_data_fifo_data_in;

  wire [AXI_REQ_FIFO_WIDTH-1:0]     axi_req_fifo_data_out;
  wire [AXI_LEN_FIFO_WIDTH-1:0]     axi_len_fifo_data_out;
  wire [HDR_REQ_FIFO_WIDTH-1:0]     hdr_req_fifo_data_out;
  wire [AXIS_DATA_FIFO_WIDTH-1+32:0]   axis_data_fifo_data_out;

  wire                              axi_req_fifo_push;
  wire                              axi_len_fifo_push;
  wire                              hdr_req_fifo_push;
  wire                              axis_data_fifo_push;

  reg                               axi_req_fifo_pop;
  wire                              axi_len_fifo_pop;
  wire                              hdr_req_fifo_pop;
  reg                               axis_data_fifo_pop;

  wire                              axi_req_fifo_full;
  wire                              axi_len_fifo_full;
  wire                              hdr_req_fifo_full;
  wire                              axis_data_fifo_prog_full;
  reg [6:0]                         data_count;

  wire                              axi_req_fifo_empty;
  wire                              axi_len_fifo_empty;
  wire                              hdr_req_fifo_empty;
  wire                              axis_data_fifo_empty;
  reg                               hdr_req_fifo_empty_reg;

  wire                              axi_req_fifo_wr_rst_busy;
  wire                              axi_len_fifo_wr_rst_busy;
  wire                              hdr_req_fifo_wr_rst_busy;
  wire                              axis_data_fifo_wr_rst_busy;

  wire                              axi_req_fifo_rd_rst_busy;
  wire                              axi_len_fifo_rd_rst_busy;
  wire                              hdr_req_fifo_rd_rst_busy;
  wire                              axis_data_fifo_rd_rst_busy;

  wire                              hdr_wr_en;
  reg                               axis_hdr_push;
  reg                               stg_val;
  reg [576:0]                       stg_data;
  wire [63:0]                       axis_hdr_data_tkeep;
  wire [63:0]                       axis_payld_data_tkeep;
  wire                              axis_hdr_data_tlast;
  wire                              axis_payld_data_tlast;
  reg [1:0]                         axis_data_ctrl_ps;
  reg [1:0]                         axis_data_ctrl_ns;
  wire [HDR_REQ_FIFO_LEN_W:0]       hdr_len;
  wire                              hdr_len_or_bit_7_8;
  wire [HDR_REQ_FIFO_LEN_W:0]       hdr_len_r;
  wire                              hdr_len_or_bit_7_8_r;
  reg                               hdr_data_ps;
  reg                               hdr_data_ns;
  reg [8:0]                         hdr_req_fifo_data_out_r;
  wire                              axi_dma_rlast_int;
  reg                               m_axis_dma_tvalid_int;
  reg                               m_axi_dma_arvalid_int;
  wire [576:0]                      hdr_data;
  wire [31:0]                       curr_pkt_count  ;
  reg  [31:0]                       pkt_count ;
  reg [3:0]                         wr_count;
  reg [31:0]                        rlast_count;

  reg [31:0]                        arvalid_count    ;

////////////////

/////////////////////////////////////
//          SGL Format             //
// EOF   SOF    LEN       ADDR     //
// 81    80     [79:64]   [63:0]   //
/////////////////////////////////////

 always@(posedge core_clk)begin
    if(core_rst)
      arvalid_count <= 32'd0;
    else if (m_axi_dma_arvalid && m_axi_dma_arready)
      arvalid_count <= arvalid_count + 1'b1;
  end

  always@(posedge core_clk)begin
    if(core_rst)
      rlast_count <= 32'd0;
    else if (axi_dma_rlast_int && m_axi_dma_rready)
      rlast_count <= rlast_count + 1'b1;
  end

  always@(posedge core_clk)begin
    if(core_rst)
      wr_count <= 4'h0;
    else begin
      case({hdr_req_fifo_pop,hdr_req_fifo_push})
        2'b01 : wr_count <= wr_count + 1'b1;
        2'b10 : wr_count <= wr_count - 1'b1;
        default : wr_count <= wr_count;
      endcase // case ({hdr_req_fifo_pop,hdr_req_fifo_push})
    end
  end

  assign hdr_req_fifo_full = (wr_count >= 4'hD);

//tail pointer logic
  always@(posedge core_clk)begin
    if(core_rst)
      sgl_tail_ptr <= {SGL_TAIL_PTR_WIDTH{1'b0}};
    else if(sgl_bram_rd_en)begin
      if(sgl_tail_ptr[(SGL_TAIL_PTR_WIDTH-2):0] == (i_reg_tx_sgl_buf_depth - 1'b1))begin
        sgl_tail_ptr[(SGL_TAIL_PTR_WIDTH-2):0] <= {(SGL_TAIL_PTR_WIDTH-1){1'b0}};
        sgl_tail_ptr[SGL_TAIL_PTR_WIDTH-1] <= ~sgl_tail_ptr[SGL_TAIL_PTR_WIDTH-1];
      end
      else
        sgl_tail_ptr[(SGL_TAIL_PTR_WIDTH-2):0] <= sgl_tail_ptr + {{(SGL_TAIL_PTR_WIDTH-2){1'b0}},1'b1};
    end
  end

//SGL BRAM signal Assigments
//SGL head ptr not equal to tail ptr
  assign sgl_hd_ptr_neq_tail_ptr = (sgl_tail_ptr != sgl_head_ptr);
//SGL read enable
  assign sgl_bram_rd_en = sgl_hd_ptr_neq_tail_ptr & (~axi_req_fifo_full) & (~axi_len_fifo_full) & (~hdr_req_fifo_full);
//SGL read address
  assign sgl_bram_rd_addr = sgl_tail_ptr[SGL_BRAM_ADDR_WIDTH-1:0];
//BRAM read en delayed by one cycle to act as valid for read data with BRAM read latency 1.
  always@(posedge core_clk)begin
    if(core_rst)
      sgl_data_push <= 1'b0;
    else
      sgl_data_push <= sgl_bram_rd_en;
  end
//axi request fifo push
  assign axi_req_fifo_push = sgl_data_push & ((~sgl_bram_rd_data[SGL_SOF_LSB])|(sgl_bram_rd_data[SGL_QP1_HDR_VAL_LSB]));
//axi length fifo push
  assign axi_len_fifo_push = axi_req_fifo_push;
  assign hdr_req_fifo_push = sgl_data_push & sgl_bram_rd_data[SGL_SOF_LSB];

//axi request fifo data
  assign axi_req_fifo_data_in = {sgl_bram_rd_data[(SGL_LEN_LSB+SGL_LEN_WIDTH-4):(SGL_LEN_LSB)],sgl_bram_rd_data[SGL_ADDR_LSB+:C_M_AXI_ADDR_WIDTH]};

//axi length fifo data
  assign axi_len_fifo_data_in = {sgl_bram_rd_data[SGL_EOF_LSB],sgl_bram_rd_data[SGL_LEN_LSB+:6]};

  assign hdr_req_fifo_data_in = {sgl_bram_rd_data[SGL_QP1_HDR_VAL_LSB],sgl_bram_rd_data[SGL_EOF_LSB],
                                 (|sgl_bram_rd_data[(SGL_LEN_LSB+8):(SGL_LEN_LSB+7)]),sgl_bram_rd_data[SGL_LEN_LSB+:7],
                                 sgl_bram_rd_data[(SGL_ADDR_LSB+6)+:(C_HDR_BUF_ADDR_WIDTH+1)]};

//axi request fifo pop
//axi length fifo pop
  assign axi_len_fifo_pop = (axis_data_ctrl_ps == WRITE_DATA) && axi_dma_rlast_int && (!axis_data_fifo_prog_full) && (!hdr_wr_en);
  assign hdr_req_fifo_pop = (!hdr_req_fifo_empty)    ? (((axis_data_ctrl_ps == WRITE_HDR_1) && (( hdr_len <= 7'd64) && (!hdr_len_or_bit_7_8)
                                                      && hdr_req_fifo_data_out[HDR_REQ_FIFO_EOF_LSB]) && (!axis_data_fifo_prog_full)
                                                      && (!hdr_req_fifo_data_out[HDR_QP1_HDR_VAL_LSB]))
                                                     ||((axis_data_ctrl_ps == WRITE_HDR_2) && (!axis_data_fifo_prog_full)
                                                        && hdr_req_fifo_data_out[HDR_REQ_FIFO_EOF_LSB])
                                                     ||((axis_data_ctrl_ps == WRITE_DATA) && axi_dma_rlast_int && (!hdr_wr_en) && (!axis_data_fifo_prog_full)))
                                                     : 1'b0;

  assign hdr_len = hdr_req_fifo_data_out[HDR_REQ_FIFO_LEN_LSB+:(HDR_REQ_FIFO_LEN_W+1)];
  assign hdr_len_or_bit_7_8 = hdr_req_fifo_data_out[HDR_REQ_FIFO_LEN_LSB+HDR_REQ_FIFO_LEN_W+1];

  always@(posedge core_clk)begin
    if(core_rst)begin
      data_count <= 7'd0;
    end
    else begin
      case({axis_data_fifo_pop,axis_data_fifo_push})
        2'b01 : data_count <= data_count + 1'b1;
        2'b10 : data_count <= data_count - 1'b1;
        default:data_count <= data_count;
      endcase // case (axis_data_fifo_pop,axis_data_fifo_push)
    end
  end

  assign axis_data_fifo_prog_full =  data_count >= 7'd125;

always@(posedge core_clk)
  if(core_rst)
    hdr_req_fifo_data_out_r <= 9'd0;
  else
    hdr_req_fifo_data_out_r <= hdr_req_fifo_data_out[HDR_REQ_FIFO_LEN_LSB+:(HDR_REQ_FIFO_LEN_W+3)];

  assign hdr_len_r = hdr_req_fifo_data_out_r[0+:7];
  assign hdr_len_or_bit_7_8_r = hdr_req_fifo_data_out_r[7];

//Axi-4 read interface signals
  //static assignments
  assign m_axi_dma_arid    = {C_M_AXI_ID_WIDTH{1'b0}};
  assign m_axi_dma_arsize  = 3'b110;
  assign m_axi_dma_arlock  = 1'b0;
  assign m_axi_dma_arburst = 2'b01;
  assign m_axi_dma_arcache = 4'h3;
  assign m_axi_dma_arprot  = 3'b000;
  assign axi_dma_rlast_int = m_axi_dma_rvalid ? m_axi_dma_rlast : 1'b0;

  //Dynamic assignments

  always@(*)begin
      m_axi_dma_araddr = axi_req_fifo_data_out[SGL_ADDR_LSB+:C_M_AXI_ADDR_WIDTH];
      m_axi_dma_arlen  = {1'b0,axi_req_fifo_data_out[(C_M_AXI_ADDR_WIDTH+6)+:7]} - {{7{1'b0}},(~|axi_req_fifo_data_out[C_M_AXI_ADDR_WIDTH+:6])};
  end

  always@(*)begin
    if(((!m_axi_dma_arvalid_int) && (!axi_req_fifo_empty)))
      axi_req_fifo_pop = 1'b1;
    else if (m_axi_dma_arvalid_int && m_axi_dma_arready && (!axi_req_fifo_empty))
      axi_req_fifo_pop = 1'b1;
    else
      axi_req_fifo_pop = 1'b0;
  end

  always@(posedge core_clk)begin
    if(core_rst)begin
      m_axi_dma_arvalid_int <= 1'b0;
    end
    else if ((!axi_req_fifo_empty) && ((!m_axi_dma_arvalid_int) || (m_axi_dma_arvalid_int && m_axi_dma_arready)))begin
      m_axi_dma_arvalid_int <= 1'b1;
    end
    else if(m_axi_dma_arvalid_int && m_axi_dma_arready)begin
      m_axi_dma_arvalid_int <= 1'b0;
    end
  end
  assign m_axi_dma_arvalid = m_axi_dma_arvalid_int;

  assign m_axi_dma_rready = (~axis_data_fifo_prog_full) & (~hdr_wr_en);

//Axi stream signal assignments
///////////////////////////////////////////////
//      AXI stream fifo bit arrangements     //
//  576     [575:512]  [511:0]               //
///////////////////////////////////////////////

  always@(*)begin
      m_axis_dma_tdata  = axis_data_fifo_data_out[AXIS_FIFO_TDATA_LSB+:AXIS_FIFO_TDATA_W];
      m_axis_dma_tkeep  = axis_data_fifo_data_out[AXIS_FIFO_TKEEP_LSB+:AXIS_FIFO_TKEEP_W];
      m_axis_dma_tlast  = axis_data_fifo_data_out[AXIS_FIFO_TLAST_LSB];
  end

  always@(*)begin
    if(((!m_axis_dma_tvalid_int) && (!axis_data_fifo_empty)))
      axis_data_fifo_pop = 1'b1;
    else if (m_axis_dma_tvalid_int && m_axis_dma_tready && (!axis_data_fifo_empty))
      axis_data_fifo_pop = 1'b1;
    else
      axis_data_fifo_pop = 1'b0;
  end

  always@(posedge core_clk)begin
    if(core_rst)begin
      m_axis_dma_tvalid_int<= 1'b0;
    end
    else if ((!axis_data_fifo_empty) && ((!m_axis_dma_tvalid_int) || (m_axis_dma_tvalid_int && m_axis_dma_tready)))begin
      m_axis_dma_tvalid_int <= 1'b1;
    end
    else if(m_axis_dma_tvalid_int && m_axis_dma_tready)begin
      m_axis_dma_tvalid_int <= 1'b0;
    end
  end

  assign m_axis_dma_tvalid = m_axis_dma_tvalid_int;

//Axi read transactions fifo

//Fifo comprising of axi address and length
//32(ADDR)+8(LEN)+SOF_EOF= 42
  generate
    if(C_VIVADO_VER == 1'b1) begin : XPM_16_3_0
      xpm_fifo_sync #(
                      .FIFO_MEMORY_TYPE          ("auto"),           //string; "auto", "block", "distributed", or "ultra";
                      .ECC_MODE                  ("no_ecc"),         //string; "no_ecc" or "en_ecc";
                      .FIFO_WRITE_DEPTH          (16),             //positive integer
                      .WRITE_DATA_WIDTH          (AXI_REQ_FIFO_WIDTH),               //positive integer
                      .WR_DATA_COUNT_WIDTH       (5),               //positive integer
                      .PROG_FULL_THRESH          (11),               //positive integer
                      .FULL_RESET_VALUE          (0),                //positive integer; 0 or 1
                      .READ_MODE                 ("std"),            //string; "std" or "fwft";
                      .FIFO_READ_LATENCY         (1),                //positive integer;
                      .READ_DATA_WIDTH           (AXI_REQ_FIFO_WIDTH),               //positive integer
                      .RD_DATA_COUNT_WIDTH       (5),               //positive integer
                      .PROG_EMPTY_THRESH         (5),               //positive integer
                      .DOUT_RESET_VALUE          ("0"),              //string
                      .WAKEUP_TIME               (0)                 //positive integer; 0 or 2;
                      )
      axi_req_fifo (
                    .sleep            (1'b0),
                    .rst              (core_rst),
                    .wr_clk           (core_clk),
                    .wr_en            (axi_req_fifo_push),
                    .din              (axi_req_fifo_data_in),
                    .full             (axi_req_fifo_full),
                    .prog_full        (),
                    .wr_data_count    (),
                    .overflow         (),
                    .wr_rst_busy      (axi_req_fifo_wr_rst_busy),
                    .rd_en            (axi_req_fifo_pop),
                    .dout             (axi_req_fifo_data_out),
                    .empty            (axi_req_fifo_empty),
                    .prog_empty       (),
                    .rd_data_count    (),
                    .underflow        (),
                    .rd_rst_busy      (axi_req_fifo_rd_rst_busy),
                    .injectsbiterr    (1'b0),
                    .injectdbiterr    (1'b0),
                    .sbiterr          (),
                    .dbiterr          ()
                    );
    end
    else begin //2016.1 version
      xpm_fifo_sync # (
                       .FIFO_MEMORY_TYPE          ("auto"),           //string; "auto", "bram", "lutram", "uram" or "builtin";
                       .FIFO_WRITE_DEPTH          (16),                //positive integer
                       .WRITE_DATA_WIDTH          (AXI_REQ_FIFO_WIDTH),   //positive integer
                       .READ_MODE                 ("std"),           //string; "std" or "fwft";
                       .FIFO_READ_LATENCY         (1),                //positive integer; 0 or 1;
                       .READ_DATA_WIDTH           (AXI_REQ_FIFO_WIDTH),   //positive integer
                       .WRCOUNT_TYPE              ("disable_wr_dc"),  //do not change
                       .PROG_FULL_THRESH          (11),               //do not change
                       .PROG_EMPTY_THRESH         (5),               //do not change
                       .DOUT_RESET_VALUE          ("0"),              //do not change
                       .ECC_MODE                  ("no_ecc"),         //do not change
                       .EN_ECC_PIPE               (0),                //do not change
                       .WAKEUP_TIME               (0),                //do not change
                       .AUTO_SLEEP_TIME           (0)                 //do not change
                       )
      axi_req_fifo (

                     .rst              (core_rst),
                     .wr_clk           (core_clk),
                     .wr_en            (axi_req_fifo_push),
                     .din              (axi_req_fifo_data_in),
                     .full             (axi_req_fifo_full),
                     .overflow         (),
                     .wr_rst_busy      (axi_req_fifo_wr_rst_busy),
                     .rd_en            (axi_req_fifo_pop),
                     .dout             (axi_req_fifo_data_out),
                     .empty            (axi_req_fifo_empty),
                     .underflow        (),
                     .rd_rst_busy      (axi_req_fifo_rd_rst_busy),
                     .prog_full        (),             // do not change
                     .wr_data_count    (),             // do not change
                     .prog_empty       (),             // do not change
                     .rd_data_count    (),             // do not change
                     .sleep            (1'b0),         // do not change
                     .injectsbiterr    (1'b0),         // do not change
                     .injectdbiterr    (1'b0),         // do not change
                     .sbiterr          (),             // do not change
                     .dbiterr          ()              // do not change
                     );
    end // else: !if(C_VIVADO_VER == 1'b1)
  endgenerate

//axi read data fifo(depth 2x64--512 width) to store atleast two axi 4K transactions

//Width = 512(DATA)+64(TKEEP)+1(TLAST) = 577
  generate
    if(C_VIVADO_VER == 1'b1) begin : XPM_16_3_1
  xpm_fifo_sync #(
                  .FIFO_MEMORY_TYPE          ("auto"),          //string; "auto", "block", "distributed", or "ultra";
                  .ECC_MODE                  ("no_ecc"),        //string; "no_ecc" or "en_ecc";
                  .FIFO_WRITE_DEPTH          (128),             //positive integer
                  .WRITE_DATA_WIDTH          (AXIS_DATA_FIFO_WIDTH+32),             //positive integer
                  .WR_DATA_COUNT_WIDTH       (8),               //positive integer
                  .PROG_FULL_THRESH          (123),             //positive integer
                  .FULL_RESET_VALUE          (0),                //positive integer; 0 or 1
                  .READ_MODE                 ("std"),            //string; "std" or "fwft";
                  .FIFO_READ_LATENCY         (1),                //positive integer;
                  .READ_DATA_WIDTH           (AXIS_DATA_FIFO_WIDTH+32),               //positive integer
                  .RD_DATA_COUNT_WIDTH       (8),               //positive integer
                  .PROG_EMPTY_THRESH         (5),               //positive integer
                  .DOUT_RESET_VALUE          ("0"),              //string
                  .WAKEUP_TIME               (0)                 //positive integer; 0 or 2;
                  )
  axis_data_fifo (
                  .sleep            (1'b0),
                  .rst              (core_rst),
                  .wr_clk           (core_clk),
                  .wr_en            (axis_data_fifo_push),
                  .din              (axis_data_fifo_data_in),
                  .full             (),
                  .prog_full        (),
                  .wr_data_count    (),
                  .overflow         (),
                  .wr_rst_busy      (axis_data_fifo_wr_rst_busy),
                  .rd_en            (axis_data_fifo_pop),
                  .dout             (axis_data_fifo_data_out),
                  .empty            (axis_data_fifo_empty),
                  .prog_empty       (),
                  .rd_data_count    (),
                  .underflow        (),
                  .rd_rst_busy      (axis_data_fifo_rd_rst_busy),
                  .injectsbiterr    (1'b0),
                  .injectdbiterr    (1'b0),
                  .sbiterr          (),
                  .dbiterr          ()
                  );
    end // block: XPM_16_3_1
    else begin
      xpm_fifo_sync # (
                       .FIFO_MEMORY_TYPE          ("auto"),           //string; "auto", "bram", "lutram", "uram" or "builtin";
                       .FIFO_WRITE_DEPTH          (128),                //positive integer
                       .WRITE_DATA_WIDTH          (AXIS_DATA_FIFO_WIDTH+32),   //positive integer
                       .READ_MODE                 ("std"),           //string; "std" or "fwft";
                       .FIFO_READ_LATENCY         (1),                //positive integer; 0 or 1;
                       .READ_DATA_WIDTH           (AXIS_DATA_FIFO_WIDTH+32),   //positive integer
                       .WRCOUNT_TYPE              ("disable_wr_dc"),  //do not change
                       .PROG_FULL_THRESH          (123),               //do not change
                       .PROG_EMPTY_THRESH         (5),               //do not change
                       .DOUT_RESET_VALUE          ("0"),              //do not change
                       .ECC_MODE                  ("no_ecc"),         //do not change
                       .EN_ECC_PIPE               (0),                //do not change
                       .WAKEUP_TIME               (0),                //do not change
                       .AUTO_SLEEP_TIME           (0)                 //do not change
                       )
      axis_data_fifo (

                     .rst              (core_rst),
                     .wr_clk           (core_clk),
                     .wr_en            (axis_data_fifo_push),
                     .din              (axis_data_fifo_data_in),
                     .full             (),
                     .overflow         (),
                     .wr_rst_busy      (axis_data_fifo_wr_rst_busy),
                     .rd_en            (axis_data_fifo_pop),
                     .dout             (axis_data_fifo_data_out),
                     .empty            (axis_data_fifo_empty),
                     .underflow        (),
                     .rd_rst_busy      (axis_data_fifo_rd_rst_busy),
                     .prog_full        (),             // do not change
                     .wr_data_count    (),             // do not change
                     .prog_empty       (),             // do not change
                     .rd_data_count    (),             // do not change
                     .sleep            (1'b0),         // do not change
                     .injectsbiterr    (1'b0),         // do not change
                     .injectdbiterr    (1'b0),         // do not change
                     .sbiterr          (),             // do not change
                     .dbiterr          ()              // do not change
                     );
    end // else: !if(C_VIVADO_VER == 1'b1)
  endgenerate

//axi stream interface logic
 //derive tkeep from residue length on the last beat of the AXI-4 transaction.

//Fifo comprising of axi length which will be used to calculate the AXIS interface
//64 beats are at max possible for 512 bit wide data bus to be within 4K range.
//The bits [5:0] of the length will represent the valid data bytes in last beat
//ehich will be used to generate the appropriate TKEEP.

//width = 6(LEN) + 1(EOF)= 7
  generate
    if(C_VIVADO_VER == 1'b1) begin : XPM_16_3_2
  xpm_fifo_sync #(
                  .FIFO_MEMORY_TYPE          ("auto"),           //string; "auto", "block", "distributed", or "ultra";
                  .ECC_MODE                  ("no_ecc"),         //string; "no_ecc" or "en_ecc";
                  .FIFO_WRITE_DEPTH          (16),             //positive integer
                  .WRITE_DATA_WIDTH          (AXI_LEN_FIFO_WIDTH), //positive integer
                  .WR_DATA_COUNT_WIDTH       (5),               //positive integer
                  .PROG_FULL_THRESH          (11),               //positive integer
                  .FULL_RESET_VALUE          (0),                //positive integer; 0 or 1
                  .READ_MODE                 ("fwft"),            //string; "std" or "fwft";
                  .FIFO_READ_LATENCY         (0),                //positive integer;
                  .READ_DATA_WIDTH           (AXI_LEN_FIFO_WIDTH),               //positive integer
                  .RD_DATA_COUNT_WIDTH       (5),               //positive integer
                  .PROG_EMPTY_THRESH         (5),               //positive integer
                  .DOUT_RESET_VALUE          ("0"),              //string
                  .WAKEUP_TIME               (0)                 //positive integer; 0 or 2;
                  )
  axi_len_fifo (
                .sleep            (1'b0),
                .rst              (core_rst),
                .wr_clk           (core_clk),
                .wr_en            (axi_len_fifo_push),
                .din              (axi_len_fifo_data_in),
                .full             (axi_len_fifo_full),
                .prog_full        (),
                .wr_data_count    (),
                .overflow         (),
                .wr_rst_busy      (axi_len_fifo_wr_rst_busy),
                .rd_en            (axi_len_fifo_pop),
                .dout             (axi_len_fifo_data_out),
                .empty            (axi_len_fifo_empty),
                .prog_empty       (),
                .rd_data_count    (),
                .underflow        (),
                .rd_rst_busy      (axi_len_fifo_rd_rst_busy),
                .injectsbiterr    (1'b0),
                .injectdbiterr    (1'b0),
                .sbiterr          (),
                .dbiterr          ()
                );
    end // block: XPM_16_3_2
    else begin
      xpm_fifo_sync # (
                       .FIFO_MEMORY_TYPE          ("auto"),           //string; "auto", "bram", "lutram", "uram" or "builtin";
                       .FIFO_WRITE_DEPTH          (16),                //positive integer
                       .WRITE_DATA_WIDTH          (AXI_LEN_FIFO_WIDTH),   //positive integer
                       .READ_MODE                 ("fwft"),           //string; "std" or "fwft";
                       .FIFO_READ_LATENCY         (0),                //positive integer; 0 or 1;
                       .READ_DATA_WIDTH           (AXI_LEN_FIFO_WIDTH),   //positive integer
                       .WRCOUNT_TYPE              ("disable_wr_dc"),  //do not change
                       .PROG_FULL_THRESH          (11),               //do not change
                       .PROG_EMPTY_THRESH         (5),               //do not change
                       .DOUT_RESET_VALUE          ("0"),              //do not change
                       .ECC_MODE                  ("no_ecc"),         //do not change
                       .EN_ECC_PIPE               (0),                //do not change
                       .WAKEUP_TIME               (0),                //do not change
                       .AUTO_SLEEP_TIME           (0)                 //do not change
                       )
      axi_len_fifo (

                     .rst              (core_rst),
                     .wr_clk           (core_clk),
                     .wr_en            (axi_len_fifo_push),
                     .din              (axi_len_fifo_data_in),
                     .full             (axi_len_fifo_full),
                     .overflow         (),
                     .wr_rst_busy      (axi_len_fifo_wr_rst_busy),
                     .rd_en            (axi_len_fifo_pop),
                     .dout             (axi_len_fifo_data_out),
                     .empty            (axi_len_fifo_empty),
                     .underflow        (),
                     .rd_rst_busy      (axi_len_fifo_rd_rst_busy),
                     .prog_full        (),             // do not change
                     .wr_data_count    (),             // do not change
                     .prog_empty       (),             // do not change
                     .rd_data_count    (),             // do not change
                     .sleep            (1'b0),         // do not change
                     .injectsbiterr    (1'b0),         // do not change
                     .injectdbiterr    (1'b0),         // do not change
                     .sbiterr          (),             // do not change
                     .dbiterr          ()              // do not change
                     );
    end // else: !if(C_VIVADO_VER == 1'b1)
  endgenerate

  // C_HDR_BUF_ADDR_WIDTH + 8(LEN) + 1(EOF)
  generate
    if(C_VIVADO_VER == 1'b1) begin : XPM_16_3_3
  xpm_fifo_sync #(
                  .FIFO_MEMORY_TYPE          ("auto"),           //string; "auto", "block", "distributed", or "ultra";
                  .ECC_MODE                  ("no_ecc"),         //string; "no_ecc" or "en_ecc";
                  .FIFO_WRITE_DEPTH          (16),             //positive integer
                  .WRITE_DATA_WIDTH          (HDR_REQ_FIFO_WIDTH),               //positive integer
                  .WR_DATA_COUNT_WIDTH       (5),               //positive integer
                  .PROG_FULL_THRESH          (11),               //positive integer
                  .FULL_RESET_VALUE          (0),                //positive integer; 0 or 1
                  .READ_MODE                 ("fwft"),            //string; "std" or "fwft";
                  .FIFO_READ_LATENCY         (0),                //positive integer;
                  .READ_DATA_WIDTH           (HDR_REQ_FIFO_WIDTH), //positive integer
                  .RD_DATA_COUNT_WIDTH       (5),               //positive integer
                  .PROG_EMPTY_THRESH         (5),               //positive integer
                  .DOUT_RESET_VALUE          ("0"),              //string
                  .WAKEUP_TIME               (0)                 //positive integer; 0 or 2;
                  )
  hdr_req_fifo (
                .sleep            (1'b0),
                .rst              (core_rst),
                .wr_clk           (core_clk),
                .wr_en            (hdr_req_fifo_push),
                .din              (hdr_req_fifo_data_in),
                .full             (),
                .prog_full        (),
                .wr_data_count    (),
                .overflow         (),
                .wr_rst_busy      (hdr_req_fifo_wr_rst_busy),
                .rd_en            (hdr_req_fifo_pop),
                .dout             (hdr_req_fifo_data_out),
                .empty            (hdr_req_fifo_empty),
                .prog_empty       (),
                .rd_data_count    (),
                .underflow        (),
                .rd_rst_busy      (hdr_req_fifo_rd_rst_busy),
                .injectsbiterr    (1'b0),
                .injectdbiterr    (1'b0),
                .sbiterr          (),
                .dbiterr          ()
                );
    end // block: XPM_16_3_3
    else begin
      xpm_fifo_sync # (
                       .FIFO_MEMORY_TYPE          ("auto"),           //string; "auto", "bram", "lutram", "uram" or "builtin";
                       .FIFO_WRITE_DEPTH          (16),                //positive integer
                       .WRITE_DATA_WIDTH          (HDR_REQ_FIFO_WIDTH),   //positive integer
                       .READ_MODE                 ("fwft"),           //string; "std" or "fwft";
                       .FIFO_READ_LATENCY         (0),                //positive integer; 0 or 1;
                       .READ_DATA_WIDTH           (HDR_REQ_FIFO_WIDTH),   //positive integer
                       .WRCOUNT_TYPE              ("disable_wr_dc"),  //do not change
                       .PROG_FULL_THRESH          (11),               //do not change
                       .PROG_EMPTY_THRESH         (5),               //do not change
                       .DOUT_RESET_VALUE          ("0"),              //do not change
                       .ECC_MODE                  ("no_ecc"),         //do not change
                       .EN_ECC_PIPE               (0),                //do not change
                       .WAKEUP_TIME               (0),                //do not change
                       .AUTO_SLEEP_TIME           (0)                 //do not change
                       )
      hdr_req_fifo (

                     .rst              (core_rst),
                     .wr_clk           (core_clk),
                     .wr_en            (hdr_req_fifo_push),
                     .din              (hdr_req_fifo_data_in),
                     .full             (),
                     .overflow         (),
                     .wr_rst_busy      (hdr_req_fifo_wr_rst_busy),
                     .rd_en            (hdr_req_fifo_pop),
                     .dout             (hdr_req_fifo_data_out),
                     .empty            (hdr_req_fifo_empty),
                     .underflow        (),
                     .rd_rst_busy      (hdr_req_fifo_rd_rst_busy),
                     .prog_full        (),             // do not change
                     .wr_data_count    (),             // do not change
                     .prog_empty       (),             // do not change
                     .rd_data_count    (),             // do not change
                     .sleep            (1'b0),         // do not change
                     .injectsbiterr    (1'b0),         // do not change
                     .injectdbiterr    (1'b0),         // do not change
                     .sbiterr          (),             // do not change
                     .dbiterr          ()              // do not change
                     );
    end // else: !if(C_VIVADO_VER == 1'b1)
  endgenerate

//AXIS data write control FSM

  always@(posedge core_clk)begin
    if(core_rst)
      axis_data_ctrl_ps <= WRITE_HDR_1;
    else if((!axis_data_fifo_prog_full))
      axis_data_ctrl_ps <= axis_data_ctrl_ns;
  end

  always@(*)begin
    case(axis_data_ctrl_ps)
      WRITE_HDR_1 : begin
        if(!hdr_req_fifo_empty)begin
          if(((hdr_len > 7'd64) || hdr_len_or_bit_7_8) && (!hdr_req_fifo_data_out[HDR_QP1_HDR_VAL_LSB]))
          axis_data_ctrl_ns = WRITE_HDR_2;
          else if(hdr_req_fifo_data_out[HDR_REQ_FIFO_EOF_LSB] && (!hdr_req_fifo_data_out[HDR_QP1_HDR_VAL_LSB]))
          axis_data_ctrl_ns = WRITE_HDR_1;
          else
          axis_data_ctrl_ns = WRITE_DATA;
        end
        else
          axis_data_ctrl_ns = WRITE_HDR_1;
      end
      WRITE_HDR_2 : begin
        if(hdr_req_fifo_data_out[HDR_REQ_FIFO_EOF_LSB])
          axis_data_ctrl_ns = WRITE_HDR_1;
        else
          axis_data_ctrl_ns = WRITE_DATA;
      end
      WRITE_DATA : begin
        if(axi_dma_rlast_int && (!hdr_wr_en))begin
//          if(!hdr_req_fifo_empty)begin
//            if((hdr_len > 7'd64) || hdr_len_or_bit_7_8)
//              axis_data_ctrl_ns = WRITE_HDR_2;
              axis_data_ctrl_ns = WRITE_HDR_1;
//            else
//              axis_data_ctrl_ns = WRITE_DATA;
//          end
//          else
//            axis_data_ctrl_ns = WRITE_HDR_1;
        end
        else
          axis_data_ctrl_ns = WRITE_DATA;
      end
      default:begin
        axis_data_ctrl_ns = WRITE_HDR_1;
      end
    endcase // case (axis_data_ctrl_ps)
  end

  assign hdr_wr_en = ((axis_data_ctrl_ps == WRITE_HDR_1)&&(!hdr_req_fifo_data_out[HDR_QP1_HDR_VAL_LSB])) || (axis_data_ctrl_ps == WRITE_HDR_2) || axis_hdr_push;

  always@(posedge core_clk)begin
    if(core_rst)
      axis_hdr_push <= 1'b0;
    else
      axis_hdr_push <= hdr_bram_rd_en;
  end

  assign axis_data_fifo_push = ((~axis_data_fifo_prog_full) & m_axi_dma_rvalid & (~hdr_wr_en))| axis_hdr_push;

  assign hdr_bram_rd_en =  (!axis_data_fifo_prog_full) && (!hdr_req_fifo_empty) && (!stg_val) && (!hdr_req_fifo_data_out[HDR_QP1_HDR_VAL_LSB])
                           && ((axis_data_ctrl_ps == WRITE_HDR_1) || (axis_data_ctrl_ps == WRITE_HDR_2)); //|| ((axis_data_ctrl_ps == WRITE_DATA) && axi_dma_rlast_int && (!hdr_wr_en)));

  assign hdr_bram_rd_addr = {hdr_req_fifo_data_out[C_HDR_BUF_ADDR_WIDTH:1],(axis_data_ctrl_ps == WRITE_HDR_2)};

  always@(posedge core_clk)begin
    if(core_rst)begin
      hdr_bram_pop <= 1'b0;
    end
    else begin
      hdr_bram_pop <= hdr_bram_rd_en && ((axis_data_ctrl_ps == WRITE_HDR_2) || (( hdr_len <= 7'd64) && (!hdr_len_or_bit_7_8)));
    end
  end

  always@(posedge core_clk)begin
    if(core_rst)begin
      stg_val <= 1'b0;
      stg_data <= {577{1'b0}};
    end
    else if((!axis_data_fifo_prog_full) && stg_val)begin
      stg_val <= 1'b0;
      stg_data <= {577{1'b0}};
    end
    else if(axis_data_fifo_prog_full && hdr_bram_rd_en)begin
      stg_val <= 1'b1;
      stg_data <= {axis_hdr_data_tlast,axis_hdr_data_tkeep,hdr_data};//hdr_bram_rd_data;
    end
  end

always@(posedge core_clk)
  if(core_rst)
    hdr_data_ps <= 1'b0;
  else
    hdr_data_ps <= hdr_data_ns;

  always@(*)begin
    case(hdr_data_ps)
      1'b0 : begin
        if(axis_hdr_push && ((hdr_len_r > 7'd64)||hdr_len_or_bit_7_8_r))
          hdr_data_ns = 1'b1;
        else
          hdr_data_ns = 1'b0;
      end
      1'b1: begin
        if(axis_hdr_push)
          hdr_data_ns = 1'b0;
        else
          hdr_data_ns = 1'b1;
      end
    endcase // case (hdr_data_ps)
  end

always@(posedge core_clk)
  if(core_rst)
    pkt_count <= 32'd0;
  else if(axis_data_fifo_push)
    pkt_count <= pkt_count + 1'b1;

  genvar i;

  generate
    for(i=0;i<64;i=i+1)begin :loop1
      assign axis_hdr_data_tkeep[i] = ((!hdr_data_ps) && ((hdr_len_r > 7'd64)||hdr_len_or_bit_7_8_r)) ? 1'b1 :((hdr_len_r[5:0] >= (i+1)) || (~|hdr_len_r[5:0])) ? 1'b1 : 1'b0;
      assign axis_payld_data_tkeep[i] = axi_dma_rlast_int ? ((axi_len_fifo_data_out[5:0] >= (i+1))|| (~|axi_len_fifo_data_out[5:0]))? 1'b1 : 1'b0 : 1'b1;
    end
  endgenerate

  assign hdr_data = {axis_hdr_data_tlast,axis_hdr_data_tkeep,hdr_bram_rd_data};

  assign axis_hdr_data_tlast = (((!hdr_data_ps) && (!((hdr_len_r > 7'd64)||hdr_len_or_bit_7_8_r))) || hdr_data_ps) ? hdr_req_fifo_data_out_r[8] : 1'b0;
  assign axis_payld_data_tlast = axi_len_fifo_data_out[AXI_LEN_FIFO_EOF_LSB] & axi_dma_rlast_int;
  assign axis_data_fifo_data_in = (hdr_wr_en) ? {pkt_count,hdr_data}
                                  : {pkt_count,axis_payld_data_tlast,axis_payld_data_tkeep,m_axi_dma_rdata};
  assign curr_pkt_count = axis_data_fifo_data_out[AXIS_DATA_FIFO_WIDTH+:32];

always@(posedge core_clk)begin
  if(core_rst)
    hdr_req_fifo_empty_reg <= 1'b0;
  else
    hdr_req_fifo_empty_reg <= hdr_req_fifo_empty;
end
always@(posedge core_clk)begin
  if(core_rst)
    o_dma_in_idle <= 1'b1;
  else if(sgl_hd_ptr_neq_tail_ptr)
    o_dma_in_idle <= 1'b0;
  else if((!sgl_hd_ptr_neq_tail_ptr) && (!hdr_req_fifo_empty_reg) && hdr_req_fifo_empty)
    o_dma_in_idle <= 1'b1;
end

endmodule // wqe_proc_dma

