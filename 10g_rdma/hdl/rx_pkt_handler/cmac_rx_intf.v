// cmac_rx_intf.v
// 文件名          : cmac_rx_intf.v
// 版本            : v1.0
// 描述            : CMAC RX 接口适配模块，接收 512bit 以太网数据并提取包描述符
//                   完成数据包边界检测和有效数据提取
// Verilog 标准    : Verilog'2001

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
`timescale 1 ps / 1 ps

module cmac_rx_intf #(
  parameter C_SIM_DEBUG = 0,
  parameter PKT_DESC_FIFO_DATA_WIDTH = 26,
  parameter C_REQ_BUF_ADDR_WIDTH = 9,
  parameter C_RSP_BUF_ADDR_WIDTH = 10,
  parameter C_HDR_BUF_ADDR_WIDTH = 9
) (
  // System interface
  input  wire                                 clk,
  input  wire                                 reset,

  // CMAC interface
  input  wire                                 s_axis_tvalid,
  input  wire [511:0]                         s_axis_tdata,
  input  wire [ 63:0]                         s_axis_tkeep,
  input  wire                                 s_axis_tlast,
  input  wire [  0:0]                         s_axis_tuser,

  // RDMA configuration
  input  wire                                 rdma_en,
  input  wire                                 bypass_en,
  output reg  [31:0]                          o_inc_all_pkt_cnt,
  output reg  [31:0]                          o_inc_drop_pkt_cnt,

  output reg  [ 7:0]                          o_last_in_pkt_opcode,
  output reg  [ 7:0]                          o_last_in_pkt_qpid,
  output reg  [15:0]                          o_last_in_pkt_psn,

  // miscellanous inputs/outputs
  input  wire                                 req_pkt_buf_almost_full,
  input  wire                                 rsp_pkt_buf_almost_full,
  output wire                                 pkt_discarded_to_req_hv,

  // req_pkt_desc_fifo interface
  output wire [PKT_DESC_FIFO_DATA_WIDTH-1:0]  req_pkt_desc_fifo_dout,
  input  wire                                 rd_req_pkt_desc_fifo,

  // rsp_pkt_desc_fifo interface
  output wire [PKT_DESC_FIFO_DATA_WIDTH-1:0]  rsp_pkt_desc_fifo_dout,
  input  wire                                 rd_rsp_pkt_desc_fifo,

  // req_pkt_buf interface
  output reg  [C_REQ_BUF_ADDR_WIDTH-1:0]      req_pkt_buf_addra,
  output wire                                 req_pkt_buf_ena,
  output wire [63:0]                          req_pkt_buf_wea,
  output wire [511:0]                         req_pkt_buf_dina,

  // req_hdr_buf interface
  output reg  [C_HDR_BUF_ADDR_WIDTH-1:0]      req_hdr_buf_addra,
  output reg                                  req_hdr_buf_ena,
  output wire [63:0]                          req_hdr_buf_wea,
  output wire [511:0]                         req_hdr_buf_dina,

  // rsp_pkt_buf interface
  output reg  [C_RSP_BUF_ADDR_WIDTH-1:0]      rsp_pkt_buf_addra,
  output wire                                 rsp_pkt_buf_ena,
  output wire [63:0]                          rsp_pkt_buf_wea,
  output wire [511:0]                         rsp_pkt_buf_dina,

  // rsp_hdr_buf interface
  output reg  [C_HDR_BUF_ADDR_WIDTH-1:0]      rsp_hdr_buf_addra,
  output reg                                  rsp_hdr_buf_ena,
  output wire [63:0]                          rsp_hdr_buf_wea,
  output wire [511:0]                         rsp_hdr_buf_dina,

  // Debug signals
  input  wire                                 i_clr_debug_sts,
  output reg                                  pkt_dropped_sticky,
  output reg                                  req_pkt_buf_almost_full_sticky,
  output reg                                  rsp_pkt_buf_almost_full_sticky,
  output reg [15:0]                           pkt_desc_fifo_1_unoccupied_r,
  output reg                                  pkt_desc_fifo_1_full_sticky,
  output reg [15:0]                           req_pkt_desc_fifo_unoccupied_r,
  output reg                                  req_pkt_desc_fifo_full_sticky,
  output reg [15:0]                           rsp_pkt_desc_fifo_unoccupied_r,
  output reg                                  rsp_pkt_desc_fifo_full_sticky,
  output wire                                 pkt_desc_fifo_3_empty,
  output wire                                 req_pkt_desc_fifo_empty,
  output wire                                 rsp_pkt_desc_fifo_empty,
  output reg                                  pkt_fcs_err_sticky,
  output reg                                  pkt_crc_err_sticky
);

  localparam [15:0] ETH_TYPE_IPV4 = 16'h0800;
  localparam [15:0] ETH_TYPE_IPV6 = 16'h86DD;

  localparam PKT_TYPE_REQ = 1'b0;
  localparam PKT_TYPE_RSP = 1'b1;

  localparam PKT_DESC_FIFO_1_DEPTH        = 16;
  localparam PKT_DESC_FIFO_1_DATA_WIDTH   = C_SIM_DEBUG ? (C_RSP_BUF_ADDR_WIDTH+47) : (C_RSP_BUF_ADDR_WIDTH+15);
  localparam PKT_DESC_FIFO_1_WRCNTR_WIDTH = 5;

  localparam PKT_DESC_FIFO_2_DEPTH        = 16;
  localparam PKT_DESC_FIFO_2_DATA_WIDTH   = C_SIM_DEBUG ? 33 : 1;
  localparam PKT_DESC_FIFO_2_WRCNTR_WIDTH = 5;

  localparam PKT_DESC_FIFO_3_DEPTH        = 16;
  localparam PKT_DESC_FIFO_3_DATA_WIDTH   = C_SIM_DEBUG ? 33 : 1;
  localparam PKT_DESC_FIFO_3_WRCNTR_WIDTH = 5;

  localparam PKT_DESC_FIFO_DEPTH          = 256;
  localparam PKT_DESC_FIFO_WRCNTR_WIDTH   = 9;

  integer i;
  genvar gi;

  reg s_axis_tidle;
  wire s_axis_tfirst;
  reg [6:0] s_axis_tbytes;

  reg tvalid;
  reg [511:0] tdata;
  reg [ 63:0] tkeep;
  reg [  0:0] tuser;
  reg tfirst;
  reg tlast;

  wire [ 7:0] ipv4_bth_opcode;
  wire [ 7:0] ipv6_bth_opcode;
  wire [15:0] eth_type;
  wire [ 7:0] bth_opcode;
  wire [23:0] ipv4_bth_qp_dest_addr;
  wire [23:0] ipv6_bth_qp_dest_addr;
  wire [23:0] bth_qp_dest_addr;
  wire [23:0] ipv4_bth_psn;
  wire [23:0] ipv6_bth_psn;
  wire [23:0] bth_psn;

  reg ipv6;

  wire rsp_pkt_rcvd;

  reg pkt_discarded;

  reg pkt_type;
  reg [31:0] pkt_id_1;
  reg [12:0] pkt_len;

  reg [C_REQ_BUF_ADDR_WIDTH-1:0] req_pkt_buf_offset;
  reg [C_RSP_BUF_ADDR_WIDTH-1:0] rsp_pkt_buf_offset;
  wire [C_RSP_BUF_ADDR_WIDTH-1:0] pkt_buf_offset;

  wire [PKT_DESC_FIFO_1_DATA_WIDTH-1:0] pkt_desc_fifo_1_din;
  wire [PKT_DESC_FIFO_1_DATA_WIDTH-1:0] pkt_desc_fifo_1_dout;
  wire wr_pkt_desc_fifo_1;
  wire rd_pkt_desc_fifo_1;
  wire pkt_desc_fifo_1_empty;
  wire pkt_desc_fifo_1_full;
  wire pkt_desc_fifo_1_almost_full;

  reg [17:0] ipv4_hdr_chksum_i1;
  reg [17:0] ipv4_hdr_chksum_i2;
  reg [17:0] ipv4_hdr_chksum_i3;

  reg  [19:0] ipv4_hdr_chksum_ii1;
  wire [16:0] ipv4_hdr_chksum_ii2;
  wire ipv4_hdr_chksum_err;

  wire ipv4_hdr_chk_en;
  reg [1:0] ipv4_hdr_chk_st;

  reg [31:0] pkt_id_2_reg[1:0];
  wire [31:0] pkt_id_2;

  wire [PKT_DESC_FIFO_2_DATA_WIDTH-1:0] pkt_desc_fifo_2_din;
  wire [PKT_DESC_FIFO_2_DATA_WIDTH-1:0] pkt_desc_fifo_2_dout;
  wire wr_pkt_desc_fifo_2;
  wire rd_pkt_desc_fifo_2;

  reg [511:0] crc_data_in;

  wire tvalid_crc;
  wire tfirst_crc;
  wire tlast_crc;
  reg tvalid_crc_d1;
  reg tvalid_crc_d2;
  reg tfirst_crc_d1;
  reg tfirst_crc_d2;
  reg tlast_crc_d1;
  reg tlast_crc_d2;
  reg [31:0] pkt_id_crc_d1;
  reg [31:0] pkt_id_crc_d2;

  reg [5:0] lshift_bytes;
  reg [511:0] crc_data_in_la;
  reg [5:0] invld_crc_bytes;
  reg [2:0] crc_corr_sel;
  reg [5:0] invld_crc_bytes_d1;
  reg [5:0] invld_crc_bytes_d2;
  wire [31:0] dword_crc32 [0:15];
  reg [31:0] crc_corr;
  reg [31:0] line_crc32;
  reg [31:0] nxt_line_crc32;
  wire [31:0] crc_data_out;
  reg [5:0] idx_1;
  reg [31:0] prev_crc_data_out_premux1 [0:7];
  reg [31:0] next_prev_crc_data_out_premux1 [0:7];
  wire [31:0] prev_crc_data_out_premux2 [0:63];
  wire [31:0] prev_crc_data_out;

  wire pkt_crc_err;
  wire crc_calc_done;

  reg  [PKT_DESC_FIFO_3_DATA_WIDTH-1:0] pkt_desc_fifo_3_din;
  wire [PKT_DESC_FIFO_3_DATA_WIDTH-1:0] pkt_desc_fifo_3_dout;
  reg  wr_pkt_desc_fifo_3;
  wire rd_pkt_desc_fifo_3;

  wire [31:0] pkt_id_crc;

  wire [PKT_DESC_FIFO_DATA_WIDTH-1:0] pkt_desc_fifo_din;

  wire wr_req_pkt_desc_fifo;
  wire req_pkt_desc_fifo_full;

  wire wr_rsp_pkt_desc_fifo;
  wire rsp_pkt_desc_fifo_full;

  reg [1:0] req_hdr_buf_fsm_cs;
  reg [1:0] req_hdr_buf_fsm_ns;
  reg [1:0] req_hdr_buf_addra_incr;

  reg [1:0] rsp_hdr_buf_fsm_cs;
  reg [1:0] rsp_hdr_buf_fsm_ns;
  reg [1:0] rsp_hdr_buf_addra_incr;

  always @(posedge clk)
    if (reset)
      s_axis_tidle <= 1'b1;
    else if (s_axis_tvalid)
      s_axis_tidle <= s_axis_tlast;

  assign s_axis_tfirst = s_axis_tidle & s_axis_tvalid;

  always @(posedge clk)
    if (reset)
      tvalid <= 1'b0;
    else
      tvalid <= s_axis_tvalid;

  always @(posedge clk)
    for (i='d0; i<'d64; i=i+1)
      if (s_axis_tvalid && s_axis_tkeep[i])
        tdata[i*8+:8] <= s_axis_tdata[i*8+:8];
      else
        tdata[i*8+:8] <= 8'h00;

  always @(posedge clk)
    if (s_axis_tvalid)
    begin
      tkeep  <= s_axis_tkeep;
      tuser  <= s_axis_tuser;
      tfirst <= s_axis_tidle;
      tlast  <= s_axis_tlast;
    end
    else
    begin
      tkeep  <= { 64{1'b0}};
      tuser  <= 1'b0;
      tfirst <= 1'b0;
      tlast  <= 1'b0;
    end

  assign ipv4_bth_opcode = s_axis_tdata[42*8+:8];
  assign ipv6_bth_opcode = s_axis_tdata[62*8+:8];
  assign eth_type        = {s_axis_tdata[12*8+:8], s_axis_tdata[13*8+:8]};
  assign bth_opcode      = (eth_type == ETH_TYPE_IPV4) ? ipv4_bth_opcode : ipv6_bth_opcode;
  assign ipv4_bth_qp_dest_addr = {s_axis_tdata[47*8+:8], s_axis_tdata[48*8+:8], s_axis_tdata[49*8+:8]};
  assign ipv6_bth_qp_dest_addr = {s_axis_tdata[ 3*8+:8], s_axis_tdata[ 4*8+:8], s_axis_tdata[ 5*8+:8]};
  assign bth_qp_dest_addr = (eth_type == ETH_TYPE_IPV4) ? ipv4_bth_qp_dest_addr : ipv6_bth_qp_dest_addr;
  assign ipv4_bth_psn = {s_axis_tdata[51*8+:8], s_axis_tdata[52*8+:8], s_axis_tdata[53*8+:8]};
  assign ipv6_bth_psn = {s_axis_tdata[ 7*8+:8], s_axis_tdata[ 8*8+:8], s_axis_tdata[ 9*8+:8]};
  assign bth_psn = (eth_type == ETH_TYPE_IPV4) ? ipv4_bth_psn : ipv6_bth_psn;

  assign rsp_pkt_rcvd    = (!bypass_en && (bth_opcode >= 8'b000_01101) &&
                           (bth_opcode <= 8'b000_10001)) ? 1'b1 : 1'b0;

  always @(posedge clk)
    if (s_axis_tfirst)
    begin
      if (rsp_pkt_rcvd)
        pkt_type <= PKT_TYPE_RSP;
      else
        pkt_type <= PKT_TYPE_REQ;
    end

  always @(posedge clk)
    if (reset)
      pkt_id_1 <= 32'hFFFF_FFFF;
    else if (s_axis_tfirst)
      pkt_id_1 <= pkt_id_1 + 'd1;

  always @(*)
  begin
    s_axis_tbytes = 7'd1;
    for (i='d0; i<'d63; i=i+1)
      s_axis_tbytes = s_axis_tbytes + s_axis_tkeep[i+1];
  end

  always @(posedge clk)
    if (s_axis_tvalid)
      pkt_len <= s_axis_tidle ? s_axis_tbytes : (pkt_len + s_axis_tbytes);

  always @(posedge clk)
    if (reset)
    begin
      pkt_discarded <= 1'b1;
      o_inc_drop_pkt_cnt <= 32'd0;
      o_last_in_pkt_opcode <= 8'h00;
      o_last_in_pkt_qpid <= 8'h00;
      o_last_in_pkt_psn <= 16'h0000;
      ipv6 <= 1'b0;
    end
    else if (s_axis_tfirst)
    begin
      if (!rdma_en)
      begin
        pkt_discarded <= 1'b1;
      end
      else if (pkt_desc_fifo_1_almost_full || pkt_desc_fifo_1_full)
      begin
        pkt_discarded <= 1'b1;
        o_inc_drop_pkt_cnt <= o_inc_drop_pkt_cnt + 'd1;
      end
      else if (rsp_pkt_rcvd && rsp_pkt_buf_almost_full)
      begin
        pkt_discarded <= 1'b1;
        o_inc_drop_pkt_cnt <= o_inc_drop_pkt_cnt + 'd1;
      end
      else if (!rsp_pkt_rcvd && req_pkt_buf_almost_full)
      begin
        pkt_discarded <= 1'b1;
        o_inc_drop_pkt_cnt <= o_inc_drop_pkt_cnt + 'd1;
      end
      else
      begin
        pkt_discarded <= 1'b0;
        o_last_in_pkt_opcode <= bth_opcode;
        if (eth_type == ETH_TYPE_IPV4)
        begin
          o_last_in_pkt_qpid <= ipv4_bth_qp_dest_addr[7:0];
          o_last_in_pkt_psn <= ipv4_bth_psn[15:0];
        end
        else
          ipv6 <= 1'b1;
      end
    end
    else if (ipv6 && s_axis_tvalid)
    begin
      ipv6 <= 1'b0;
      o_last_in_pkt_qpid <= ipv6_bth_qp_dest_addr[7:0];
      o_last_in_pkt_psn <= ipv6_bth_psn[15:0];
    end

  assign pkt_discarded_to_req_hv = rdma_en & tfirst & pkt_discarded;

  always @(posedge clk)
    if (reset)
      o_inc_all_pkt_cnt <= 32'd0;
    else if (rdma_en && tlast)
      o_inc_all_pkt_cnt <= o_inc_all_pkt_cnt + 'd1;

  always @(posedge clk)
    if (reset)
    begin
      req_pkt_buf_offset <= {(C_REQ_BUF_ADDR_WIDTH){1'b0}};
      rsp_pkt_buf_offset <= {(C_RSP_BUF_ADDR_WIDTH){1'b0}};
    end
    else if (!pkt_discarded && tlast)
    begin
      if (pkt_type == PKT_TYPE_REQ)
        req_pkt_buf_offset <= req_pkt_buf_addra + 'd1;
      else
        rsp_pkt_buf_offset <= rsp_pkt_buf_addra + 'd1;
    end

  assign pkt_buf_offset = (pkt_type == PKT_TYPE_RSP) ? rsp_pkt_buf_offset :
                          {{(C_RSP_BUF_ADDR_WIDTH-C_REQ_BUF_ADDR_WIDTH){1'b0}}, req_pkt_buf_offset};

  generate if (C_SIM_DEBUG)
    assign pkt_desc_fifo_1_din = {
      pkt_id_1,       // 32
      pkt_type,       // 1
      pkt_buf_offset, // C_RSP_BUF_ADDR_WIDTH
      pkt_len,        // 13
      tuser[0]        // 1
    };
  else
    assign pkt_desc_fifo_1_din = {
      pkt_type,       // 1
      pkt_buf_offset, // C_RSP_BUF_ADDR_WIDTH
      pkt_len,        // 13
      tuser[0]        // 1
    };
  endgenerate

  assign wr_pkt_desc_fifo_1 = ~pkt_discarded & tlast;

  // pkt_desc_fifo_1 (FWFT), Default depth = 8

  reg_fifo_sync #(
    .C_READ_MODE (1'b1),
    .C_FIFO_DEPTH (PKT_DESC_FIFO_1_DEPTH),
    .C_FIFO_WRCNTR_WIDTH (PKT_DESC_FIFO_1_WRCNTR_WIDTH),
    .C_FIFO_DATA_WIDTH(PKT_DESC_FIFO_1_DATA_WIDTH)
  ) pkt_desc_fifo_1 (
    .clk          (clk),
    .reset        (reset),
    .wr_en        (wr_pkt_desc_fifo_1),
    .din          (pkt_desc_fifo_1_din),
    .full         (pkt_desc_fifo_1_full),
    .almost_full  (pkt_desc_fifo_1_almost_full),
    .rd_en        (rd_pkt_desc_fifo_1),
    .dout         (pkt_desc_fifo_1_dout),
    .empty        (pkt_desc_fifo_1_empty)
  );

  always @(posedge clk)
  begin
    ipv4_hdr_chksum_i1  <= {tdata[14*8+:8],tdata[15*8+:8]} +
                           {tdata[16*8+:8],tdata[17*8+:8]} +
                           {tdata[18*8+:8],tdata[19*8+:8]} +
                           {tdata[20*8+:8],tdata[21*8+:8]} ;
    ipv4_hdr_chksum_i2  <= {tdata[22*8+:8],tdata[23*8+:8]} +
                           {tdata[24*8+:8],tdata[25*8+:8]} +
                           {tdata[26*8+:8],tdata[27*8+:8]} +
                           {tdata[28*8+:8],tdata[29*8+:8]};
    ipv4_hdr_chksum_i3  <= {tdata[30*8+:8],tdata[31*8+:8]} +
                           {tdata[32*8+:8],tdata[33*8+:8]};

    ipv4_hdr_chksum_ii1 <= ipv4_hdr_chksum_i1 +
                           ipv4_hdr_chksum_i2 +
                           ipv4_hdr_chksum_i3;
  end

  assign ipv4_hdr_chksum_ii2 = ipv4_hdr_chksum_ii1[15:0] + ipv4_hdr_chksum_ii1[19:16];
  assign ipv4_hdr_chksum_err = (ipv4_hdr_chksum_ii2 != 17'h0_FFFF) ? 1'b1 : 1'b0;

  assign ipv4_hdr_chk_en = ~pkt_discarded & tfirst;

  always @(posedge clk)
    if (reset)
      ipv4_hdr_chk_st <= 2'b00;
    else
      ipv4_hdr_chk_st <= {ipv4_hdr_chk_st[0], ipv4_hdr_chk_en};

  always @(posedge clk)
  begin
    pkt_id_2_reg[1] <= pkt_id_2_reg[0];
    pkt_id_2_reg[0] <= pkt_id_1;
  end

  assign pkt_id_2 = pkt_id_2_reg[1];

  generate if (C_SIM_DEBUG)
    assign pkt_desc_fifo_2_din = {
      pkt_id_2,
      ipv4_hdr_chksum_err
    };
  else
    assign pkt_desc_fifo_2_din = ipv4_hdr_chksum_err;
  endgenerate

  assign wr_pkt_desc_fifo_2 = ipv4_hdr_chk_st[1];

  // pkt_desc_fifo_2 (FWFT), DEPTH = 8
  reg_fifo_sync #(
    .C_READ_MODE (1'b1),
    .C_FIFO_DEPTH (PKT_DESC_FIFO_2_DEPTH),
    .C_FIFO_WRCNTR_WIDTH (PKT_DESC_FIFO_2_WRCNTR_WIDTH),
    .C_FIFO_DATA_WIDTH(PKT_DESC_FIFO_2_DATA_WIDTH)
  ) pkt_desc_fifo_2 (
    .clk          (clk),
    .reset        (reset),
    .wr_en        (wr_pkt_desc_fifo_2),
    .din          (pkt_desc_fifo_2_din),
    .full         (),
    .almost_full  (),
    .rd_en        (rd_pkt_desc_fifo_2),
    .dout         (pkt_desc_fifo_2_dout),
    .empty        ()
  );

/*
  always @(*)
  begin
    if (!s_axis_tvalid)
    begin
      crc_data_in = {512{1'b0}};
    end
    else
    begin
      crc_data_in[7:0] = s_axis_tdata[7:0];

      for (i=1; i<64; i=i+1)
        crc_data_in[8*i+:8] = s_axis_tkeep[i] ? s_axis_tdata[8*i+:8] : 8'h00;

      if (s_axis_tidle)
      begin
        if (eth_type == ETH_TYPE_IPV4)
        begin
          crc_data_in[46*8+: 8]    = { 8{1'b1}};  // BTH RSVD8
          crc_data_in[40*8+:16]    = {16{1'b1}};  // UDP Checksum
          crc_data_in[24*8+:16]    = {16{1'b1}};  // IP Header Checksum
          crc_data_in[22*8+: 8]    = { 8{1'b1}};  // Time to Leave
          crc_data_in[15*8+: 8]    = { 8{1'b1}};  // DSCP, ECN
          crc_data_in[ 6*8+:64]    = {64{1'b1}};  // CA17-22(a)
          crc_data_in[   47: 0]    = {48{1'b0}};
        end
        else
        begin
          crc_data_in[60*8+:16]    = {16{1'b1}};  // UDP Checksum
          crc_data_in[21*8+: 8]    = { 8{1'b1}};  // Hop Limit
          crc_data_in[14*8+: 4]    = {4{1'b1}};
          crc_data_in[15*8+:24]    = {24{1'b1}};
          crc_data_in[ 6*8+:64]    = {64{1'b1}};  // CA17-22(a)
          crc_data_in[   47: 0]    = {48{1'b0}};
        end
      end
      else if (ipv6)
      begin
        crc_data_in[ 2*8+: 8] = 8'hff;
      end
    end
  end

  assign tvalid_crc = ~pkt_discarded & tvalid;
  assign tfirst_crc = ~pkt_discarded & tfirst;
  assign tlast_crc = ~pkt_discarded & tlast;

  always @(posedge clk)
    if (reset)
    begin
      tvalid_crc_d1 <= 1'b0;
      tvalid_crc_d2 <= 1'b0;
      tfirst_crc_d1 <= 1'b0;
      //tfirst_crc_d2 <= 1'b0;
      tlast_crc_d1 <= 1'b0;
      tlast_crc_d2 <= 1'b0;
      pkt_id_crc_d1 <= 32'd0;
      pkt_id_crc_d2 <= 32'd0;
    end
    else
    begin
      tvalid_crc_d1 <= tvalid_crc;
      tvalid_crc_d2 <= tvalid_crc_d1;
      tfirst_crc_d1 <= tfirst_crc;
      //tfirst_crc_d2 <= tfirst_crc_d1;
      tlast_crc_d1 <= tlast_crc;
      tlast_crc_d2 <= tlast_crc_d1;
      pkt_id_crc_d1 <= pkt_id_1;
      pkt_id_crc_d2 <= pkt_id_crc_d1;
    end

  always @(posedge clk)
    if (reset)
      tfirst_crc_d2 <= 1'b0;
    else if (tvalid_crc_d1)
      tfirst_crc_d2 <= tfirst_crc_d1;

  always @(*)
  begin
    lshift_bytes = 6'd0;
    for (i=1; i<64; i=i+1)
      lshift_bytes = lshift_bytes + {5'b0, ~s_axis_tkeep[i]};
  end

  always @(posedge clk)
  begin
    crc_data_in_la <= crc_data_in << {lshift_bytes, 3'b0};
    invld_crc_bytes <= s_axis_tfirst ? (lshift_bytes + 'd6) : lshift_bytes;
    invld_crc_bytes_d1 <= invld_crc_bytes;
    crc_corr_sel <= lshift_bytes[2:0];
  end

  always @(posedge clk)
    if (tvalid_crc_d1)
      invld_crc_bytes_d2 <= invld_crc_bytes_d1;

  generate
    for (gi=0; gi<16; gi=gi+1) begin : L1
      crc32_32b#(.NUM_ZEROS(480-32*gi))
        u_crc32_32b (
        .clk (clk),
        .crc_data_in (crc_data_in_la[32*gi+:32]),
        .crc_out (dword_crc32[gi])
      );
    end
  endgenerate

  always @(posedge clk)
  begin
    if (tfirst_crc)
    begin
      case (crc_corr_sel)
         3'd0:
	   crc_corr <= 32'hc7b9849c;
         3'd1:
	   crc_corr <= 32'hc7847444;
         3'd2:
	   crc_corr <= 32'h6d5aec34;
         3'd3:
	   crc_corr <= 32'h7dbc2377;
         3'd4:
	  crc_corr <= 32'h40493a53;
         3'd5:
	  crc_corr <= 32'h8f110a67;
         default :
	  crc_corr <= 32'd0;
      endcase
    end
    else
    begin
      crc_corr <= 32'd0;
    end
  end

  always @(*)
  begin
    nxt_line_crc32 = crc_corr;
    for (i=0; i<16; i=i+1)
      nxt_line_crc32 = nxt_line_crc32 ^ dword_crc32[i];
  end

  always @(posedge clk)
    if (tvalid_crc_d1)
      line_crc32 <= nxt_line_crc32;

  assign crc_data_out = tfirst_crc_d2 ? line_crc32 : (prev_crc_data_out ^ line_crc32);

  generate
    for (gi=0; gi<64; gi=gi+1)
    begin : L2
      crc32_0_data_in #(.NUM_ZEROS(512-8*gi))
        u_crc32_0_data_in_1 (
          .init_seed (crc_data_out),
          .crc_out (prev_crc_data_out_premux2[gi])
        );
    end
  endgenerate

  always @(*)
    for (i=0; i<8; i=i+1)
    begin
      idx_1 = {i[2:0], invld_crc_bytes_d1[2:0]};
      next_prev_crc_data_out_premux1[i] = prev_crc_data_out_premux2[idx_1];
    end

  always @(posedge clk)
    if (tvalid_crc_d1)
      for (i=0; i<8; i=i+1)
       prev_crc_data_out_premux1[i] <= next_prev_crc_data_out_premux1[i];

  assign prev_crc_data_out = prev_crc_data_out_premux1[invld_crc_bytes_d2[5:3]];

  assign crc_calc_done = tlast_crc_d2;

  assign pkt_crc_err = (crc_data_out != 32'hC704_DD7B) ? 1'b1 : 1'b0;

  generate if (C_SIM_DEBUG)
    assign pkt_desc_fifo_3_din = {
      pkt_id_crc_d2,
      pkt_crc_err
    };
  else
    assign pkt_desc_fifo_3_din = pkt_crc_err;
  endgenerate

  assign wr_pkt_desc_fifo_3 = crc_calc_done;
*/

  icrc_rocev2_512b_rx #(
    .C_SIM_DEBUG(C_SIM_DEBUG)
  ) u_icrc_rocev2_512b_rx (
    .clk              (clk),
    .reset            (reset),
    .i_pkt_discarded  (pkt_discarded),
    .i_pkt_id         (pkt_id_1),
    .s_axis_tvalid    (s_axis_tvalid),
    .s_axis_tdata     (s_axis_tdata),
    .s_axis_tkeep     (s_axis_tkeep),
    .s_axis_tlast     (s_axis_tlast),
    .o_crc_calc_done  (crc_calc_done),
    .o_pkt_id         (pkt_id_crc),
    .o_crc_out        (),
    .o_crc_err        (pkt_crc_err)
  );

  always @(posedge clk)
    if (reset)
      wr_pkt_desc_fifo_3 <= 1'b0;
    else
      wr_pkt_desc_fifo_3 <= crc_calc_done;

  generate if (C_SIM_DEBUG)
    always @(posedge clk)
      pkt_desc_fifo_3_din <= {pkt_id_crc, pkt_crc_err};
  else
    always @(posedge clk)
      pkt_desc_fifo_3_din <= pkt_crc_err;
  endgenerate

  // pkt_desc_fifo_3 (FWFT), DEPTH = 8
  reg_fifo_sync #(
    .C_READ_MODE (1'b1),
    .C_FIFO_DEPTH (PKT_DESC_FIFO_3_DEPTH),
    .C_FIFO_WRCNTR_WIDTH (PKT_DESC_FIFO_3_WRCNTR_WIDTH),
    .C_FIFO_DATA_WIDTH(PKT_DESC_FIFO_3_DATA_WIDTH)
  ) pkt_desc_fifo_3 (
    .clk          (clk),
    .reset        (reset),
    .wr_en        (wr_pkt_desc_fifo_3),
    .din          (pkt_desc_fifo_3_din),
    .full         (),
    .almost_full  (),
    .rd_en        (rd_pkt_desc_fifo_3),
    .dout         (pkt_desc_fifo_3_dout),
    .empty        (pkt_desc_fifo_3_empty)
  );

  generate if (C_SIM_DEBUG)
    assign pkt_desc_fifo_din = {
      pkt_desc_fifo_1_dout[(C_RSP_BUF_ADDR_WIDTH+15)+:32],  // pkt_id
      pkt_desc_fifo_1_dout[14+:C_RSP_BUF_ADDR_WIDTH],  // pkt buffer offset
      pkt_desc_fifo_1_dout[13:1],  // pkt_len
      ~pkt_desc_fifo_1_dout[0],  // FCS error
      pkt_desc_fifo_2_dout[0],  // IPv4 Header checksum error
      pkt_desc_fifo_3_dout[0]  // ICRC error
    };
  else
    assign pkt_desc_fifo_din = {
      pkt_desc_fifo_1_dout[14+:C_RSP_BUF_ADDR_WIDTH],  // pkt buffer offset
      pkt_desc_fifo_1_dout[13:1],  // pkt_len
      ~pkt_desc_fifo_1_dout[0],  // FCS error
      pkt_desc_fifo_2_dout[0],  // IPv4 Header checksum error
      pkt_desc_fifo_3_dout[0]  // ICRC error
    };
  endgenerate

  assign wr_req_pkt_desc_fifo = !pkt_desc_fifo_3_empty && !req_pkt_desc_fifo_full && (
            (pkt_desc_fifo_1_dout[C_RSP_BUF_ADDR_WIDTH+14] == PKT_TYPE_REQ) ? 1'b1 : 1'b0);

  assign wr_rsp_pkt_desc_fifo = !pkt_desc_fifo_3_empty && !rsp_pkt_desc_fifo_full && (
            (pkt_desc_fifo_1_dout[C_RSP_BUF_ADDR_WIDTH+14] == PKT_TYPE_RSP) ? 1'b1 : 1'b0);

  assign rd_pkt_desc_fifo_1 = wr_req_pkt_desc_fifo | wr_rsp_pkt_desc_fifo;
  assign rd_pkt_desc_fifo_2 = rd_pkt_desc_fifo_1;
  assign rd_pkt_desc_fifo_3 = rd_pkt_desc_fifo_1;

  // req_pkt_desc_fifo (STD), DEPTH = 512
  xpm_fifo_sync # (
    .FIFO_MEMORY_TYPE          ("auto"),                     //string; "auto", "block", "distributed", or "ultra";
    .ECC_MODE                  ("no_ecc"),                   //string; "no_ecc" or "en_ecc";
    .FIFO_WRITE_DEPTH          (PKT_DESC_FIFO_DEPTH),        //positive integer
    .WRITE_DATA_WIDTH          (PKT_DESC_FIFO_DATA_WIDTH),   //positive integer
    .WR_DATA_COUNT_WIDTH       (PKT_DESC_FIFO_WRCNTR_WIDTH), //positive integer
    .PROG_FULL_THRESH          (PKT_DESC_FIFO_DEPTH-PKT_DESC_FIFO_1_DEPTH-4), //positive integer
    .FULL_RESET_VALUE          (0),                          //positive integer; 0 or 1
    .READ_MODE                 ("std"),                      //string; "std" or "fwft";
    .FIFO_READ_LATENCY         (1),                          //positive integer;
    .READ_DATA_WIDTH           (PKT_DESC_FIFO_DATA_WIDTH),   //positive integer
    .RD_DATA_COUNT_WIDTH       (PKT_DESC_FIFO_WRCNTR_WIDTH), //positive integer
    .PROG_EMPTY_THRESH         (10),                         //positive integer
    .DOUT_RESET_VALUE          ("0"),                        //string
    .WAKEUP_TIME               (0)                           //positive integer; 0 or 2;
  ) req_pkt_desc_fifo (
    .sleep            (1'b0),
    .rst              (reset),
    .wr_clk           (clk),
    .wr_en            (wr_req_pkt_desc_fifo),
    .din              (pkt_desc_fifo_din),
    .full             (),
    .prog_full        (req_pkt_desc_fifo_full),
    .wr_data_count    (),
    .overflow         (),
    .wr_rst_busy      (),
    .rd_en            (rd_req_pkt_desc_fifo),
    .dout             (req_pkt_desc_fifo_dout),
    .empty            (req_pkt_desc_fifo_empty),
    .prog_empty       (),
    .rd_data_count    (),
    .underflow        (),
    .rd_rst_busy      (),
    .injectsbiterr    (1'b0),
    .injectdbiterr    (1'b0),
    .sbiterr          (),
    .dbiterr          ()
  );

  // rsp_pkt_desc_fifo (STD), DEPTH = 512
  xpm_fifo_sync # (
    .FIFO_MEMORY_TYPE          ("auto"),                     //string; "auto", "block", "distributed", or "ultra";
    .ECC_MODE                  ("no_ecc"),                   //string; "no_ecc" or "en_ecc";
    .FIFO_WRITE_DEPTH          (PKT_DESC_FIFO_DEPTH),        //positive integer
    .WRITE_DATA_WIDTH          (PKT_DESC_FIFO_DATA_WIDTH),   //positive integer
    .WR_DATA_COUNT_WIDTH       (PKT_DESC_FIFO_WRCNTR_WIDTH), //positive integer
    .PROG_FULL_THRESH          (PKT_DESC_FIFO_DEPTH-PKT_DESC_FIFO_1_DEPTH-4), //positive integer
    .FULL_RESET_VALUE          (0),                          //positive integer; 0 or 1
    .READ_MODE                 ("std"),                      //string; "std" or "fwft";
    .FIFO_READ_LATENCY         (1),                          //positive integer;
    .READ_DATA_WIDTH           (PKT_DESC_FIFO_DATA_WIDTH),   //positive integer
    .RD_DATA_COUNT_WIDTH       (PKT_DESC_FIFO_WRCNTR_WIDTH), //positive integer
    .PROG_EMPTY_THRESH         (10),                         //positive integer
    .DOUT_RESET_VALUE          ("0"),                        //string
    .WAKEUP_TIME               (0)                           //positive integer; 0 or 2;
  ) rsp_pkt_desc_fifo (
    .sleep            (1'b0),
    .rst              (reset),
    .wr_clk           (clk),
    .wr_en            (wr_rsp_pkt_desc_fifo),
    .din              (pkt_desc_fifo_din),
    .full             (),
    .prog_full        (rsp_pkt_desc_fifo_full),
    .wr_data_count    (),
    .overflow         (),
    .wr_rst_busy      (),
    .rd_en            (rd_rsp_pkt_desc_fifo),
    .dout             (rsp_pkt_desc_fifo_dout),
    .empty            (rsp_pkt_desc_fifo_empty),
    .prog_empty       (),
    .rd_data_count    (),
    .underflow        (),
    .rd_rst_busy      (),
    .injectsbiterr    (1'b0),
    .injectdbiterr    (1'b0),
    .sbiterr          (),
    .dbiterr          ()
  );

  assign req_pkt_buf_ena = (!pkt_discarded && (pkt_type == PKT_TYPE_REQ) && tvalid) ? 1'b1 : 1'b0;

  always @(posedge clk)
    if (reset)
      req_pkt_buf_addra <= {(C_REQ_BUF_ADDR_WIDTH){1'b0}};
    else if (req_pkt_buf_ena)
      req_pkt_buf_addra <= req_pkt_buf_addra + 'd1;

  assign req_pkt_buf_dina = tdata;
  assign req_pkt_buf_wea  = {64{1'b1}};

  always @(*)
  begin
    req_hdr_buf_ena        = 1'b0;
    req_hdr_buf_addra_incr = 2'd1;
    req_hdr_buf_fsm_ns     = req_hdr_buf_fsm_cs;
    if (!pkt_discarded && (pkt_type == PKT_TYPE_REQ) && tvalid && !bypass_en)
    begin
      case (req_hdr_buf_fsm_cs)
        2'b00 :
        begin
          req_hdr_buf_ena = 1'b1;
          if (tlast)
            req_hdr_buf_addra_incr = 2'd2;
          else
            req_hdr_buf_fsm_ns = 2'b01;
        end
        2'b01 :
        begin
          req_hdr_buf_ena = 1'b1;
          if (tlast)
            req_hdr_buf_fsm_ns = 2'b00;
          else
            req_hdr_buf_fsm_ns = 2'b10;
        end
        2'b10 :
        begin
          if (tlast)
            req_hdr_buf_fsm_ns = 2'b00;
        end
        default :
        begin
          req_hdr_buf_fsm_ns = 2'bx;
        end
      endcase
    end
  end

  always @(posedge clk)
    if (reset)
      req_hdr_buf_fsm_cs <= 2'b00;
    else
      req_hdr_buf_fsm_cs <= req_hdr_buf_fsm_ns;

  always @(posedge clk)
    if (reset)
      req_hdr_buf_addra <= {(C_HDR_BUF_ADDR_WIDTH){1'b0}};
    else if (req_hdr_buf_ena)
      req_hdr_buf_addra <= req_hdr_buf_addra + req_hdr_buf_addra_incr;

  assign req_hdr_buf_dina = tdata;
  assign req_hdr_buf_wea  = {64{1'b1}};

  assign rsp_pkt_buf_ena = (!pkt_discarded && (pkt_type == PKT_TYPE_RSP) && tvalid) ? 1'b1 : 1'b0;

  always @(posedge clk)
    if (reset)
      rsp_pkt_buf_addra <= {(C_RSP_BUF_ADDR_WIDTH){1'b0}};
    else if (rsp_pkt_buf_ena)
      rsp_pkt_buf_addra <= rsp_pkt_buf_addra + 'd1;

  assign rsp_pkt_buf_dina = tdata;
  assign rsp_pkt_buf_wea  = {64{1'b1}};

  always @(*)
  begin
    rsp_hdr_buf_ena        = 1'b0;
    rsp_hdr_buf_addra_incr = 2'd1;
    rsp_hdr_buf_fsm_ns     = rsp_hdr_buf_fsm_cs;
    if (!pkt_discarded && (pkt_type == PKT_TYPE_RSP) && tvalid)
    begin
      case (rsp_hdr_buf_fsm_cs)
        2'b00 :
        begin
          rsp_hdr_buf_ena = 1'b1;
          if (tlast)
            rsp_hdr_buf_addra_incr = 2'd2;
          else
            rsp_hdr_buf_fsm_ns = 2'b01;
        end
        2'b01 :
        begin
          rsp_hdr_buf_ena = 1'b1;
          if (tlast)
            rsp_hdr_buf_fsm_ns = 2'b00;
          else
            rsp_hdr_buf_fsm_ns = 2'b10;
        end
        2'b10 :
        begin
          if (tlast)
            rsp_hdr_buf_fsm_ns = 2'b00;
        end
        default :
        begin
          rsp_hdr_buf_fsm_ns = 2'bx;
        end
      endcase
    end
  end

  always @(posedge clk)
    if (reset)
      rsp_hdr_buf_fsm_cs <= 2'b00;
    else
      rsp_hdr_buf_fsm_cs <= rsp_hdr_buf_fsm_ns;

  always @(posedge clk)
    if (reset)
      rsp_hdr_buf_addra <= {(C_HDR_BUF_ADDR_WIDTH){1'b0}};
    else if (rsp_hdr_buf_ena)
      rsp_hdr_buf_addra <= rsp_hdr_buf_addra + rsp_hdr_buf_addra_incr;

  assign rsp_hdr_buf_dina = tdata;
  assign rsp_hdr_buf_wea  = {64{1'b1}};

  // =====================================================================
  // Debug Logic
  // =====================================================================
  reg [14:0] pkt_desc_fifo_1_wr_cnt;
  reg [14:0] pkt_desc_fifo_1_rd_cnt;
  wire [15:0] pkt_desc_fifo_1_occupied;
  wire [15:0] pkt_desc_fifo_1_unoccupied;

  reg [14:0] req_pkt_desc_fifo_wr_cnt;
  reg [14:0] req_pkt_desc_fifo_rd_cnt;
  wire [15:0] req_pkt_desc_fifo_occupied;
  wire [15:0] req_pkt_desc_fifo_unoccupied;

  reg [14:0] rsp_pkt_desc_fifo_wr_cnt;
  reg [14:0] rsp_pkt_desc_fifo_rd_cnt;
  wire [15:0] rsp_pkt_desc_fifo_occupied;
  wire [15:0] rsp_pkt_desc_fifo_unoccupied;

  always @(posedge clk)
    if (reset)
      pkt_dropped_sticky <= 1'b0;
    else if (i_clr_debug_sts)
      pkt_dropped_sticky <= 1'b0;
    else if (rdma_en && pkt_discarded && tfirst)
      pkt_dropped_sticky <= 1'b1;

  always @(posedge clk)
    if (reset)
      req_pkt_buf_almost_full_sticky <= 1'b0;
    else if (i_clr_debug_sts)
      req_pkt_buf_almost_full_sticky <= 1'b0;
    else if (req_pkt_buf_almost_full)
      req_pkt_buf_almost_full_sticky <= 1'b1;

  always @(posedge clk)
    if (reset)
      rsp_pkt_buf_almost_full_sticky <= 1'b0;
    else if (i_clr_debug_sts)
      rsp_pkt_buf_almost_full_sticky <= 1'b0;
    else if (rsp_pkt_buf_almost_full)
      rsp_pkt_buf_almost_full_sticky <= 1'b1;

  always @(posedge clk)
    if (reset)
      pkt_desc_fifo_1_wr_cnt <= 15'd0;
    else if (i_clr_debug_sts)
      pkt_desc_fifo_1_wr_cnt <= 15'd0;
    else if (wr_pkt_desc_fifo_1)
      pkt_desc_fifo_1_wr_cnt <= pkt_desc_fifo_1_wr_cnt + 'd1;

  always @(posedge clk)
    if (reset)
      pkt_desc_fifo_1_rd_cnt <= 15'd0;
    else if (i_clr_debug_sts)
      pkt_desc_fifo_1_rd_cnt <= 15'd0;
    else if (rd_pkt_desc_fifo_1)
      pkt_desc_fifo_1_rd_cnt <= pkt_desc_fifo_1_rd_cnt + 'd1;

  assign pkt_desc_fifo_1_occupied = (pkt_desc_fifo_1_rd_cnt > pkt_desc_fifo_1_wr_cnt) ? ({1'b1, pkt_desc_fifo_1_wr_cnt} - pkt_desc_fifo_1_rd_cnt) :
                                    (pkt_desc_fifo_1_wr_cnt - pkt_desc_fifo_1_rd_cnt);

  assign pkt_desc_fifo_1_unoccupied = PKT_DESC_FIFO_1_DEPTH - pkt_desc_fifo_1_occupied;

  always @(posedge clk)
    if (reset)
      pkt_desc_fifo_1_unoccupied_r <= PKT_DESC_FIFO_1_DEPTH;
    else if (i_clr_debug_sts)
      pkt_desc_fifo_1_unoccupied_r <= PKT_DESC_FIFO_1_DEPTH;
    else if (pkt_desc_fifo_1_unoccupied_r > pkt_desc_fifo_1_unoccupied)
      pkt_desc_fifo_1_unoccupied_r <= pkt_desc_fifo_1_unoccupied;

  always @(posedge clk)
    if (reset)
      pkt_desc_fifo_1_full_sticky <= 1'b0;
    else if (i_clr_debug_sts)
      pkt_desc_fifo_1_full_sticky <= 1'b0;
    else if (pkt_desc_fifo_1_full)
      pkt_desc_fifo_1_full_sticky <= 1'b1;

  always @(posedge clk)
    if (reset)
      req_pkt_desc_fifo_wr_cnt <= 15'd0;
    else if (i_clr_debug_sts)
      req_pkt_desc_fifo_wr_cnt <= 15'd0;
    else if (wr_req_pkt_desc_fifo)
      req_pkt_desc_fifo_wr_cnt <= req_pkt_desc_fifo_wr_cnt + 'd1;

  always @(posedge clk)
    if (reset)
      req_pkt_desc_fifo_rd_cnt <= 15'd0;
    else if (i_clr_debug_sts)
      req_pkt_desc_fifo_rd_cnt <= 15'd0;
    else if (rd_req_pkt_desc_fifo)
      req_pkt_desc_fifo_rd_cnt <= req_pkt_desc_fifo_rd_cnt + 'd1;

  assign req_pkt_desc_fifo_occupied = (req_pkt_desc_fifo_rd_cnt > req_pkt_desc_fifo_wr_cnt) ? ({1'b1, req_pkt_desc_fifo_wr_cnt} - req_pkt_desc_fifo_rd_cnt) :
                                    (req_pkt_desc_fifo_wr_cnt - req_pkt_desc_fifo_rd_cnt);

  assign req_pkt_desc_fifo_unoccupied = PKT_DESC_FIFO_DEPTH - req_pkt_desc_fifo_occupied;

  always @(posedge clk)
    if (reset)
      req_pkt_desc_fifo_unoccupied_r <= PKT_DESC_FIFO_DEPTH;
    else if (i_clr_debug_sts)
      req_pkt_desc_fifo_unoccupied_r <= PKT_DESC_FIFO_DEPTH;
    else if (req_pkt_desc_fifo_unoccupied_r > req_pkt_desc_fifo_unoccupied)
      req_pkt_desc_fifo_unoccupied_r <= req_pkt_desc_fifo_unoccupied;

  always @(posedge clk)
    if (reset)
      req_pkt_desc_fifo_full_sticky <= 1'b0;
    else if (i_clr_debug_sts)
      req_pkt_desc_fifo_full_sticky <= 1'b0;
    else if (req_pkt_desc_fifo_full)
      req_pkt_desc_fifo_full_sticky <= 1'b1;

  always @(posedge clk)
    if (reset)
      rsp_pkt_desc_fifo_wr_cnt <= 15'd0;
    else if (i_clr_debug_sts)
      rsp_pkt_desc_fifo_wr_cnt <= 15'd0;
    else if (wr_rsp_pkt_desc_fifo)
      rsp_pkt_desc_fifo_wr_cnt <= rsp_pkt_desc_fifo_wr_cnt + 'd1;

  always @(posedge clk)
    if (reset)
      rsp_pkt_desc_fifo_rd_cnt <= 15'd0;
    else if (i_clr_debug_sts)
      rsp_pkt_desc_fifo_rd_cnt <= 15'd0;
    else if (rd_rsp_pkt_desc_fifo)
      rsp_pkt_desc_fifo_rd_cnt <= rsp_pkt_desc_fifo_rd_cnt + 'd1;

  assign rsp_pkt_desc_fifo_occupied = (rsp_pkt_desc_fifo_rd_cnt > rsp_pkt_desc_fifo_wr_cnt) ? ({1'b1, rsp_pkt_desc_fifo_wr_cnt} - rsp_pkt_desc_fifo_rd_cnt) :
                                    (rsp_pkt_desc_fifo_wr_cnt - rsp_pkt_desc_fifo_rd_cnt);

  assign rsp_pkt_desc_fifo_unoccupied = PKT_DESC_FIFO_DEPTH - rsp_pkt_desc_fifo_occupied;

  always @(posedge clk)
    if (reset)
      rsp_pkt_desc_fifo_unoccupied_r <= PKT_DESC_FIFO_DEPTH;
    else if (i_clr_debug_sts)
      rsp_pkt_desc_fifo_unoccupied_r <= PKT_DESC_FIFO_DEPTH;
    else if (rsp_pkt_desc_fifo_unoccupied_r > rsp_pkt_desc_fifo_unoccupied)
      rsp_pkt_desc_fifo_unoccupied_r <= rsp_pkt_desc_fifo_unoccupied;

  always @(posedge clk)
    if (reset)
      rsp_pkt_desc_fifo_full_sticky <= 1'b0;
    else if (i_clr_debug_sts)
      rsp_pkt_desc_fifo_full_sticky <= 1'b0;
    else if (rsp_pkt_desc_fifo_full)
      rsp_pkt_desc_fifo_full_sticky <= 1'b1;

  always @(posedge clk)
    if (reset)
      pkt_fcs_err_sticky <= 1'b0;
    else if (i_clr_debug_sts)
      pkt_fcs_err_sticky <= 1'b0;
    else if (rd_pkt_desc_fifo_1 && !pkt_desc_fifo_1_dout[0])
      pkt_fcs_err_sticky <= 1'b1;

  always @(posedge clk)
    if (reset)
      pkt_crc_err_sticky <= 1'b0;
    else if (i_clr_debug_sts)
      pkt_crc_err_sticky <= 1'b0;
    else if (rd_pkt_desc_fifo_3 && pkt_desc_fifo_3_dout[0])
      pkt_crc_err_sticky <= 1'b1;

endmodule

