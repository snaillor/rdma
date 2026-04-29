// rx_rsp_hdr_val.v
// 文件名          : rx_rsp_hdr_val.v
// 版本            : v1.0
// 描述            : 接收响应包头解析模块，解析对端返回的 ACK/NAK 包
//                   提取 AETH 头部信息（PSN、ACK 类型），验证 ICRC 完整性
// Verilog 标准    : Verilog'2001

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
`timescale 1 ps / 1 ps

module rx_rsp_hdr_val #(
  parameter C_SIM_DEBUG = 0,
  parameter C_M_AXI_ADDR_WIDTH = 32,
  parameter C_QP_INDX_WIDTH = 8,
  parameter C_NUM_QP = 256,
  parameter PKT_DESC_FIFO_DATA_WIDTH = 26,
  parameter C_HDR_BUF_ADDR_WIDTH = 9,
  parameter C_RSP_BUF_ADDR_WIDTH = 10,
  parameter C_OSQ_PSN_WIDTH	= 8
) (
  // System level interface
  input  wire                                 clk,
  input  wire                                 reset,

  // req_pkt_desc_fifo interface
  input  wire [PKT_DESC_FIFO_DATA_WIDTH-1:0]  rsp_pkt_desc_fifo_dout,
  input  wire                                 rsp_pkt_desc_fifo_empty,
  output reg                                  rd_rsp_pkt_desc_fifo,

  // rsp_hdr_buf interface
  output reg  [C_HDR_BUF_ADDR_WIDTH-1:0]      rsp_hdr_buf_addrb,
  output reg                                  rsp_hdr_buf_enb,
  input  wire [511:0]                         rsp_hdr_buf_doutb,

  // RDMA register interface
  input  wire                                 i_err_buf_en,
  input  wire [ 47:0]                         i_mac_node_addr,
  input  wire [ 31:0]                         i_ipv4_node_addr,
  input  wire [127:0]                         i_ipv6_node_addr,
  input  wire [C_QP_INDX_WIDTH-1:0]           i_num_qp_enabled,
  input  wire [  2:0]                         i_rnr_nak_rst_val,

  output reg  [15:0]                          o_acknack_pkt_cnt,
  output reg  [15:0]                          o_inc_nack_pkt_cnt,

  output wire [ 7:0]                          o_last_in_rsp_pkt_opcode,
  output wire [ 7:0]                          o_last_in_rsp_pkt_qpid,
  output wire [15:0]                          o_last_in_rsp_pkt_psn,

  output reg  [C_QP_INDX_WIDTH-1:0]           o_qp_conf_idx,

  input  wire [31:0]                          i_qp_conf,
  input  wire                                 qp_conf_vld,
  output reg                                  qp_conf_en,

  input  wire [ 9:0]                          i_stat_nak,
  output reg                                  stat_nak_en,
  output reg                                  stat_nak_we,
  output wire [ 9:0]                          o_stat_nak,

  input  wire [23:0]                          i_stat_resp_psn,
  output reg                                  stat_resp_psn_en,
  output reg                                  stat_resp_psn_we,
  output reg  [23:0]                          o_stat_resp_psn,

  input  wire [23:0]                          i_sq_psn,
  output reg                                  sq_psn_en,

  input  wire [47:0]                          i_remote_qp_mac_addr,
  output reg                                  remote_qp_mac_addr_en,

  input  wire [31:0]                          i_remote_qp_ip_addr,
  output reg                                  remote_qp_ip_addr_en,

  input  wire [31:0]                          i_qp_timeout,

  input  wire [C_NUM_QP-1:0]                  i_qp_fatal,
  output wire [C_QP_INDX_WIDTH-1:0]           o_qp_fatal_idx,
  (* mark_debug = "true" *) output reg        set_qp_fatal,

  // resp_handler interface
  output reg  [C_QP_INDX_WIDTH-1:0]           o_qp_mpsnbuf_idx,
  output reg                                  mpsnbuf_en,
  input  wire                                 mpsnbuf_vld,
  input  wire [C_NUM_QP-1:0]                  i_mpsnbuf_empty,
  input  wire [C_NUM_QP-1:0]                  i_qp_retried,
  input  wire [C_NUM_QP-1:0]                  i_osq_empty,
  input  wire [C_NUM_QP-1:0]                  i_osq_nacked,
  output reg                                  o_mpsnbuf_pop,
  input  wire [C_OSQ_PSN_WIDTH-1:0]           i_os_rd_req_psn_7_0,
  input  wire [C_M_AXI_ADDR_WIDTH-1:0]        i_os_rd_req_dest_addr,
  input  wire [31:0]                          i_os_rd_req_resp_len,

  output wire [C_QP_INDX_WIDTH-1:0]           o_qp_acknack_idx,
  output reg                                  o_acknack_vld,
  output reg  [23:0]                          o_acknack_psn,    // one minus for read-first/middle
  output reg  [ 7:0]                          o_acknack_syndr,
  output wire [23:0]                          o_acknack_msn,    // AETH.MSN in ACKNOWLEDGE
  output reg  [ 1:0]                          o_acknack_opcode, // 01:read-first/10:read-middle/11:read-last/only/00-acknowledge
  output reg  [31:0]                          o_qp_timeout_per_qp,

  // rx_rsp_axi_mstr interface
  output wire [31:0]                          rsp_pkt_id,
  output reg  [ 2:0]                          rsp_pkt_type,
  output reg  [C_M_AXI_ADDR_WIDTH-1:0]        rsp_dest_addr,
  output wire [C_RSP_BUF_ADDR_WIDTH-1:0]      rsp_buf_addr_offset,
  output wire [12:0]                          rsp_pkt_len,
  output reg  [31:0]                          rsp_imm_data,
  output reg                                  rsp_tnfr_vld,
  input  wire                                 rdy_to_rsp_tnfr,

  // rx_req_axi_mstr interface
  output reg                                  req_tnfr_vld,
  input  wire                                 rdy_to_req_tnfr,

  // Debug signals
  input  wire                                 i_clr_debug_sts,
  output reg                                  qp_fatal_rsp_hv_sticky,
  output reg  [31:0]                          resp_drop_cnt
);

  localparam [2:0] PKT_TYPE_ACKNOWLEDGE_ACK         = 3'd0;
  localparam [2:0] PKT_TYPE_ACKNOWLEDGE_RNR_NAK     = 3'd1;
  localparam [2:0] PKT_TYPE_ACKNOWLEDGE_NAK_SEQ_ERR = 3'd2;
  localparam [2:0] PKT_TYPE_ACKNOWLEDGE_NAK_FATAL   = 3'd3;
  localparam [2:0] PKT_TYPE_READ_ONLY               = 3'd4;
  localparam [2:0] PKT_TYPE_READ_FIRST              = 3'd5;
  localparam [2:0] PKT_TYPE_READ_MIDDLE             = 3'd6;
  localparam [2:0] PKT_TYPE_READ_LAST               = 3'd7;

  localparam [2:0] RSP_AXI_TNFR_TYPE_DISCARD                = 3'd0;
  localparam [2:0] RSP_AXI_TNFR_TYPE_ERROR                  = 3'd1;
  localparam [2:0] RSP_AXI_TNFR_TYPE_IPV4_READ_ONLY_OR_LAST = 3'd2;
  localparam [2:0] RSP_AXI_TNFR_TYPE_IPV4_READ_FIRST        = 3'd3;
  localparam [2:0] RSP_AXI_TNFR_TYPE_IPV4_READ_MIDDLE       = 3'd4;
  localparam [2:0] RSP_AXI_TNFR_TYPE_IPV6_READ_ONLY_OR_LAST = 3'd5;
  localparam [2:0] RSP_AXI_TNFR_TYPE_IPV6_READ_FIRST        = 3'd6;
  localparam [2:0] RSP_AXI_TNFR_TYPE_IPV6_READ_MIDDLE       = 3'd7;

  localparam IPv4 = 1'b0;
  localparam IPv6 = 1'b1;

  localparam [4:0] RD_RSP_FIRST  = 5'b01101;
  localparam [4:0] RD_RSP_MIDDLE = 5'b01110;
  localparam [4:0] RD_RSP_LAST   = 5'b01111;
  localparam [4:0] RD_RSP_ONLY   = 5'b10000;
  localparam [4:0] ACKNOWLEDGE   = 5'b10001;

  localparam [1:0] ACK     = 2'b00;
  localparam [1:0] NAK     = 2'b11;
  localparam [1:0] RNR_NAK = 2'b01;

  localparam [4:0] PSN_SEQ_ERR    = 5'b0_0000;
  localparam [4:0] INVLD_REQ      = 5'b0_0001;
  localparam [4:0] REMOTE_ACC_ERR = 5'b0_0010;
  localparam [4:0] REMOTE_OP_ERR  = 5'b0_0011;

  reg  hdr_ftchg_done;
  reg  hv_data_vld;
  reg  [ 511:0] prev_rsp_hdr_buf_doutb;
  wire [1023:0] hdr_data;

  reg  [0:0] hdr_ftchg_fsm_cs;
  reg  [0:0] hdr_ftchg_fsm_ns;

  wire [31:0] pkt_id;
  wire [C_RSP_BUF_ADDR_WIDTH-1:0] pkt_src_addr_offset;
  wire [12:0] actual_pkt_len;
  wire pkt_fcs_err;
  wire ipv4_hdr_chksum_fail;
  wire pkt_crc_err;

  wire [15:0] ether_type;
  wire        ip_ver;
  wire [15:0] ipv4_total_len;
  wire [15:0] ipv4_pyld_len;
  wire [15:0] ipv6_pyld_len;
  wire [15:0] ipv4_udp_dest_port_addr;
  wire [15:0] ipv6_udp_dest_port_addr;
  wire [15:0] ipv4_udp_len;
  wire [15:0] ipv6_udp_len;
  wire [15:0] udp_dest_port_addr;
  wire [15:0] ip_pyld_len;
  wire [15:0] udp_len;
  wire [15:0] total_pkt_len_advt;
  wire [ 3:0] ipv4_bth_tver;
  wire [ 3:0] ipv6_bth_tver;
  wire [23:0] ipv4_bth_qp_dest_addr;
  wire [23:0] ipv6_bth_qp_dest_addr;
  wire [23:0] bth_qp_dest_addr;
  wire [ 7:0] ipv4_bth_opcode;
  wire [ 7:0] ipv6_bth_opcode;
  wire [ 7:0] bth_opcode;
  wire [ 1:0] ipv4_bth_pad_cnt;
  wire [ 1:0] ipv6_bth_pad_cnt;
  wire [ 1:0] bth_pad_cnt;
  wire [23:0] ipv4_bth_psn;
  wire [23:0] ipv6_bth_psn;
  wire [23:0] bth_psn;
  wire [ 7:0] ipv4_aeth_syndr;
  wire [ 7:0] ipv6_aeth_syndr;
  wire [ 7:0] aeth_syndr;
  wire [23:0] ipv4_aeth_msn;
  wire [23:0] ipv6_aeth_msn;
  wire [23:0] aeth_msn;
  wire [23:0] qp_conf_min;
  wire [23:0] qp_conf_max;
  wire [12:0] bth_pyld_len;

  wire mac_dest_addr_chk_fail;
  wire mac_src_addr_chk_fail;
  wire ipv4_ver_chk_fail;
  wire ipv4_ihl_chk_fail;
  wire ipv4_ecn_chk_fail;
  wire ipv4_flg_chk_fail;
  wire ipv4_frag_offset_chk_fail;
  wire ipv4_prot_chk_fail;
  wire ipv4_dest_addr_chk_fail;
  wire ipv4_length_chk_fail;
  wire ipv4_src_addr_chk_fail;
  wire ipv6_ver_chk_fail;
  wire ipv6_ecn_chk_fail;
  wire ipv6_next_hdr_chk_fail;
  wire ipv6_dest_addr_chk_fail;
  wire ipv6_length_chk_fail;
  wire ipv6_src_addr_chk_fail;
  wire ip_src_addr_chk_fail;
  wire udp_dest_port_chk_fail;
  wire udp_length_chk_fail;
  wire pkt_len_chk_fail;
  wire bth_ver_chk_fail;
  wire dest_qp_chk_fail;
  wire bth_pad_cnt_chk_fail;
  reg  aeth_malformed;

  reg mac_dest_addr_chk_fail_r;
  reg ip_ver_chk_fail_r;
  reg ipv4_ihl_chk_fail_r;
  reg ip_ecn_chk_fail_r;
  reg ipv4_flg_chk_fail_r;
  reg ipv4_frag_offset_chk_fail_r;
  reg ip_dest_addr_chk_fail_r;
  reg ipv4_hdr_chksum_fail_r;
  reg ip_length_chk_fail_r;
  reg udp_length_chk_fail_r;
  reg pkt_len_chk_fail_r;
  reg bth_ver_chk_fail_r;
  reg dest_qp_chk_fail_r;
  reg bth_pad_cnt_chk_fail_r;
  reg ip_ver_r;
  reg  [23:0] bth_psn_r;
  reg  [ 7:0] bth_opcode_r;
  reg  [23:0] bth_qp_dest_addr_r;
  reg  [ 7:0] aeth_syndr_r;
  reg  [23:0] aeth_msn_r;
  reg  [31:0] pkt_id_r;
  reg  [C_RSP_BUF_ADDR_WIDTH-1:0] pkt_src_addr_offset_r;
  reg  [12:0] actual_pkt_len_r;

  wire qp_state_fatal;
  reg [12:0] qp_pmtu_decoded;
  wire [23:0] i_last_ob_req_psn;
  wire [ 2:0] i_rnr_nak_cnt;

  reg [12:0] qp_pmtu_decoded_r;
  reg qp_state_fatal_r;
  reg aeth_malformed_r;
  reg ip_src_addr_chk_fail_r;
  reg mac_src_addr_chk_fail_r;
  reg [23:0] stat_resp_psn_r;
  reg [23:0] last_ob_req_psn_r;
  reg [ 2:0] rnr_nak_cnt_r;

  wire [31:0] err_syndr;

  wire [23:0] unack_psn_min_muxed;
  wire [23:0] unack_psn_max_muxed;
  wire [23:0] unack_psn_min;
  wire [23:0] unack_psn_max;

  wire i_mpsnbuf_empty_combo;
  wire i_osq_invld;
  wire i_qp_retried_combo;

  wire [23:0] stat_resp_psn_muxed;
  wire [23:0] rnr_nak_cnt_muxed;
  wire [12:0] qp_pmtu_decoded_muxed;

  reg [23:0] i_os_rd_req_psn;

  reg osq_invld_at_vld;
  wire osq_invld;
  reg is_rsp_in_unack_range_at_vld;
  wire is_rsp_in_unack_range;
  reg is_rd_req_in_unack_range_at_vld;
  wire is_rd_req_in_unack_range;
  reg [23:0] os_rd_req_psn;
  reg [C_M_AXI_ADDR_WIDTH-1:0] os_rd_req_dest_addr;
  reg [31:0] os_rd_req_resp_len;
  reg mpsnbuf_empty_at_vld;
  wire mpsnbuf_empty;
  reg qp_retried;
  reg ack_psn_less_os_rd;
  reg ack_psn_lessorequal_os_rd;
  reg rdrsp_psn_grtr_os_rd;
  reg rdrsp_psn_lessorequal_last_ob_req;

  reg [2:0] pkt_type;

  reg rdrsp_middle_len_chk_fail;
  reg rdrsp_last_len_chk_fail;
  reg rdrsp_first_len_chk_fail;
  reg rdrsp_only_len_chk_fail;


  reg [1:0] acknack_opcode;
  reg [23:0] acknack_psn;
  reg [7:0] acknack_syndr;
  reg acknack_vld;
  reg [2:0] o_rnr_nak_cnt;
  wire [31:0] rdrsp_len_remain;
  reg [23:0] rdrsp_dest_addr_idx;
  wire [C_M_AXI_ADDR_WIDTH-1:0] i_rdrsp_dest_addr;
  reg rdrsp_dest_addr_en;
  reg rdrsp_dest_addr_we;
  wire [C_M_AXI_ADDR_WIDTH-1:0] o_rdrsp_dest_addr;
  reg [23:0] rdrsp_len_remain_idx;
  wire [31:0] i_rdrsp_len_remain;
  reg rdrsp_len_remain_en;
  reg rdrsp_len_remain_we;
  reg [31:0] o_rdrsp_len_remain;
  reg incr_acknack_pkt_cnt;
  reg incr_inc_nack_pkt_cnt;

  reg [C_NUM_QP-1:0] last_rsp_opcode_reg;
  reg last_rsp_opcode_we;
  reg i_last_rsp_opcode;
  reg o_last_rsp_opcode;

  reg [4:0] in_err_sts_code;
  reg [4:0] nxt_in_err_sts_code;

  reg [2:0] rsp_pkt_type_r;
  reg [C_M_AXI_ADDR_WIDTH-1:0] rsp_dest_addr_r;
  reg [31:0] rsp_imm_data_r;

  reg mpsnbuf_pop;
  reg [2:0] hv_fsm_cs;
  reg [2:0] hv_fsm_ns;

  reg hv_fsm_busy;

  // Utility functions
  function automatic is_x_less_y;
    input [23:0] x;
    input [23:0] y;
  begin
    is_x_less_y = 1'b0;
    if (x[23] && ((x < y) || ({1'b0, x[22:0]} >= y)))
      is_x_less_y = 1'b1;
    else if (!x[23] && (x < y) && ({1'b1, x[22:0]} >= y))
      is_x_less_y = 1'b1;
  end
  endfunction

  function automatic is_x_grtr_y;
    input [23:0] x;
    input [23:0] y;
  begin
    is_x_grtr_y = is_x_less_y(y, x);
  end
  endfunction

  function automatic is_x_lessorequal_y;
    input [23:0] x;
    input [23:0] y;
  begin
    is_x_lessorequal_y = !is_x_less_y(y,x);
  end
  endfunction

  function automatic is_x_grtrorequal_y;
    input [23:0] x;
    input [23:0] y;
  begin
    is_x_grtrorequal_y = !is_x_less_y(x,y);
  end
  endfunction

  function automatic is_in_range;
    input [23:0] x;
    input [23:0] y;
    input [23:0] a;
  begin
    is_in_range = 1'b0;
    if (is_x_lessorequal_y(x, y))
    begin
      if ((x > y) && ((a >= x) || (a <= y)))
        is_in_range = 1'b1;
      else if (!(x > y) && (a >= x) && (a <= y))
        is_in_range = 1'b1;
    end
  end
  endfunction

  always @(*)
  begin
    hdr_ftchg_fsm_ns = hdr_ftchg_fsm_cs;
    hdr_ftchg_done   = 1'b0;
    rsp_hdr_buf_enb      = 1'b0;
    rd_rsp_pkt_desc_fifo = 1'b0;
    case (hdr_ftchg_fsm_cs)
      1'b0 :
        if (!rsp_pkt_desc_fifo_empty && !hv_fsm_busy)
        begin
          hdr_ftchg_fsm_ns = 1'b1;
          rsp_hdr_buf_enb = 1'b1;
        end
      1'b1 :
        if (!hv_fsm_busy)
        begin
          hdr_ftchg_fsm_ns = 1'b0;
          hdr_ftchg_done = 1'b1;
          rsp_hdr_buf_enb = 1'b1;
          rd_rsp_pkt_desc_fifo = 1'b1;
        end
    endcase
  end

  always @(posedge clk)
    if (reset)
      hdr_ftchg_fsm_cs <= 1'b0;
    else
      hdr_ftchg_fsm_cs <= hdr_ftchg_fsm_ns;

  always @(posedge clk)
    if (reset)
      hv_data_vld <= 1'b0;
    else if (!hv_fsm_busy)
      hv_data_vld <= hdr_ftchg_done;

  always @(posedge clk)
    if (reset)
      rsp_hdr_buf_addrb <= {(C_HDR_BUF_ADDR_WIDTH){1'b0}};
    else if (rsp_hdr_buf_enb)
      rsp_hdr_buf_addrb <= rsp_hdr_buf_addrb + 'd1;

  always @(posedge clk)
    if (rsp_hdr_buf_enb)
      prev_rsp_hdr_buf_doutb <= rsp_hdr_buf_doutb;

  assign hdr_data = {rsp_hdr_buf_doutb, prev_rsp_hdr_buf_doutb};

   generate if (C_SIM_DEBUG)
    assign pkt_id = rsp_pkt_desc_fifo_dout[(C_RSP_BUF_ADDR_WIDTH+16)+:32];
  else
    assign pkt_id = 32'd0;
  endgenerate

  assign pkt_src_addr_offset  = rsp_pkt_desc_fifo_dout[16+:C_RSP_BUF_ADDR_WIDTH];
  assign actual_pkt_len       = rsp_pkt_desc_fifo_dout[15:3];
  assign pkt_fcs_err          = rsp_pkt_desc_fifo_dout[2];
  assign ipv4_hdr_chksum_fail = rsp_pkt_desc_fifo_dout[1];
  assign pkt_crc_err          = rsp_pkt_desc_fifo_dout[0];

  // ===============================

  //////////// MAC header specific checks //////////////
  assign mac_dest_addr_chk_fail = (i_mac_node_addr != {
    hdr_data[(0*8)+:8], hdr_data[(1*8)+:8], hdr_data[(2*8)+:8],
    hdr_data[(3*8)+:8], hdr_data[(4*8)+:8], hdr_data[(5*8)+:8]
  }) ? 1'b1 : 1'b0;

  assign ether_type = {hdr_data[12*8+:8], hdr_data[13*8+:8]};
  assign ip_ver     = (ether_type == 16'h0800) ? IPv4 : IPv6;

  assign mac_src_addr_chk_fail = (i_remote_qp_mac_addr != {
    hdr_data[( 6*8)+:8], hdr_data[( 7*8)+:8], hdr_data[( 8*8)+:8],
    hdr_data[( 9*8)+:8], hdr_data[(10*8)+:8], hdr_data[(11*8)+:8]
  }) ? 1'b1 : 1'b0;

  //////////// IPv4 header specific checks //////////////
  assign ipv4_ver_chk_fail         = (hdr_data[(14*8+4)+: 4] !=  4'h4 ) ? 1'b1 : 1'b0;
  assign ipv4_ihl_chk_fail         = (hdr_data[(14*8  )+: 4] !=  4'h5 ) ? 1'b1 : 1'b0;
  assign ipv4_ecn_chk_fail         = (hdr_data[(15*8  )+: 2] ==  2'h3 ) ? 1'b1 : 1'b0;
  assign ipv4_flg_chk_fail         = (hdr_data[(20*8+5)+: 3] !=  3'h2 ) ? 1'b1 : 1'b0;
  assign ipv4_frag_offset_chk_fail = ({hdr_data[(20*8)+:5], hdr_data[(21*8)+:8]}  != 13'h0 ) ? 1'b1 : 1'b0;
  assign ipv4_prot_chk_fail        = (hdr_data[(23*8)+:8] != 8'h11 ) ? 1'b1 : 1'b0;
  assign ipv4_dest_addr_chk_fail   = (i_ipv4_node_addr != {hdr_data[(30*8)+:8], hdr_data[(31*8)+:8],
                                      hdr_data[(32*8)+:8], hdr_data[(33*8)+:8]}) ? 1'b1 : 1'b0;
  assign ipv4_total_len            = {hdr_data[16*8+:8], hdr_data[17*8+:8]};
  assign ipv4_pyld_len             = ipv4_total_len - 16'd20;
  assign ipv4_length_chk_fail      = ((ipv4_total_len >= 16'd44) && (ipv4_total_len <= 16'd4144)) ? 1'b0 : 1'b1;
  assign ipv4_src_addr_chk_fail    = (i_remote_qp_ip_addr[31:0] != {hdr_data[(26*8)+:8], hdr_data[(27*8)+:8],
                                     hdr_data[(28*8)+:8], hdr_data[(29*8)+:8]}) ? 1'b1 : 1'b0;

  //////////// IPv6 header specific checks //////////////
  assign ipv6_ver_chk_fail       = (hdr_data[(14*8+4)+:4] !=  4'h6 ) ? 1'b1 : 1'b0;
  assign ipv6_ecn_chk_fail       = (hdr_data[(15*8+4)+:2] ==  2'h3 ) ? 1'b1 : 1'b0;
  assign ipv6_next_hdr_chk_fail  = (hdr_data[(20*8)+:8]   !=  8'h11) ? 1'b1 : 1'b0;
  assign ipv6_dest_addr_chk_fail = (i_ipv6_node_addr != {
                   hdr_data[(38*8)+:8], hdr_data[(39*8)+:8], hdr_data[(40*8)+:8],
                   hdr_data[(41*8)+:8], hdr_data[(42*8)+:8], hdr_data[(43*8)+:8],
                   hdr_data[(44*8)+:8], hdr_data[(45*8)+:8], hdr_data[(46*8)+:8],
                   hdr_data[(47*8)+:8], hdr_data[(48*8)+:8], hdr_data[(49*8)+:8],
                   hdr_data[(50*8)+:8], hdr_data[(51*8)+:8], hdr_data[(52*8)+:8],
                   hdr_data[(53*8)+:8]}) ? 1'b1 : 1'b0;
  assign ipv6_pyld_len           = {hdr_data[18*8+:8], hdr_data[19*8+:8]};
  assign ipv6_length_chk_fail    = ((ipv6_pyld_len >= 16'd16) && (ipv6_pyld_len <= 16'd4124)) ? 1'b0 : 1'b1;
  assign ipv6_src_addr_chk_fail  = ({{96{1'b0}}, i_remote_qp_ip_addr} != {
                   hdr_data[(22*8)+:8], hdr_data[(23*8)+:8], hdr_data[(24*8)+:8],
                   hdr_data[(25*8)+:8], hdr_data[(26*8)+:8], hdr_data[(27*8)+:8],
                   hdr_data[(28*8)+:8], hdr_data[(29*8)+:8], hdr_data[(30*8)+:8],
                   hdr_data[(31*8)+:8], hdr_data[(32*8)+:8], hdr_data[(33*8)+:8],
                   hdr_data[(34*8)+:8], hdr_data[(35*8)+:8], hdr_data[(36*8)+:8],
                   hdr_data[(37*8)+:8]}) ? 1'b1 : 1'b0;

  assign ip_src_addr_chk_fail = (ip_ver == IPv4) ? ipv4_src_addr_chk_fail : ipv6_src_addr_chk_fail;

  //////////// UDP header specific checks //////////////
  assign ipv4_udp_dest_port_addr = {hdr_data[36*8+:8], hdr_data[37*8+:8]};
  assign ipv6_udp_dest_port_addr = {hdr_data[56*8+:8], hdr_data[57*8+:8]};
  assign ipv4_udp_len            = {hdr_data[38*8+:8], hdr_data[39*8+:8]};
  assign ipv6_udp_len            = {hdr_data[58*8+:8], hdr_data[59*8+:8]};
  assign udp_dest_port_addr      = (ip_ver == IPv4) ? ipv4_udp_dest_port_addr : ipv6_udp_dest_port_addr;
  assign ip_pyld_len             = (ip_ver == IPv4) ? ipv4_pyld_len : ipv6_pyld_len;
  assign udp_len                 = (ip_ver == IPv4) ? ipv4_udp_len : ipv6_udp_len;
  assign total_pkt_len_advt      = (ip_ver == IPv4) ? (ipv4_udp_len + 16'd34) : (ipv6_udp_len + 16'd54);
  assign udp_dest_port_chk_fail  = (udp_dest_port_addr != 16'd4791) ? 1'b1 : 1'b0;
  assign udp_length_chk_fail     = (ip_pyld_len != udp_len) ? 1'b1 : 1'b0;
  assign pkt_len_chk_fail        = ((total_pkt_len_advt != {3'b000, actual_pkt_len}) ||
                                   (actual_pkt_len[1:0] != 2'b10)) ? 1'b1 : 1'b0;

  /////////// BTH header specific checks //////////////
  assign ipv4_bth_tver         =  hdr_data[43*8+:4];
  assign ipv6_bth_tver         =  hdr_data[63*8+:4];
  assign ipv4_bth_qp_dest_addr = {hdr_data[47*8+:8], hdr_data[48*8+:8], hdr_data[49*8+:8]};
  assign ipv6_bth_qp_dest_addr = {hdr_data[67*8+:8], hdr_data[68*8+:8], hdr_data[69*8+:8]};
  assign ipv4_bth_opcode       =  hdr_data[42*8+:8];
  assign ipv6_bth_opcode       =  hdr_data[62*8+:8];
  assign ipv4_bth_pad_cnt      =  hdr_data[(43*8+4)+:2];
  assign ipv6_bth_pad_cnt      =  hdr_data[(63*8+4)+:2];
  assign ipv4_bth_psn          = {hdr_data[51*8+:8], hdr_data[52*8+:8], hdr_data[53*8+:8]};
  assign ipv6_bth_psn          = {hdr_data[71*8+:8], hdr_data[72*8+:8], hdr_data[73*8+:8]};
  assign ipv4_aeth_syndr       =  hdr_data[54*8+:8];
  assign ipv6_aeth_syndr       =  hdr_data[74*8+:8];
  assign ipv4_aeth_msn         = {hdr_data[55*8+:8],hdr_data[56*8+:8],hdr_data[57*8+:8]};
  assign ipv6_aeth_msn         = {hdr_data[75*8+:8],hdr_data[76*8+:8],hdr_data[77*8+:8]};

  assign bth_ver               = (ip_ver == IPv4) ? ipv4_bth_tver : ipv6_bth_tver;
  assign bth_qp_dest_addr      = (ip_ver == IPv4) ? ipv4_bth_qp_dest_addr : ipv6_bth_qp_dest_addr;
  assign bth_opcode            = (ip_ver == IPv4) ? ipv4_bth_opcode : ipv6_bth_opcode;
  assign bth_pad_cnt           = (ip_ver == IPv4) ? ipv4_bth_pad_cnt : ipv6_bth_pad_cnt;
  assign bth_psn               = (ip_ver == IPv4) ? ipv4_bth_psn : ipv6_bth_psn;
  assign aeth_syndr            = (ip_ver == IPv4) ? ipv4_aeth_syndr : ipv6_aeth_syndr;
  assign aeth_msn              = (ip_ver == IPv4) ? ipv4_aeth_msn : ipv6_aeth_msn;

  assign bth_ver_chk_fail     = (bth_ver != 4'd0) ? 1'b1 : 1'b0;
  assign bth_pad_cnt_chk_fail = (((bth_opcode[4:0] == RD_RSP_FIRST) || (bth_opcode[4:0] == RD_RSP_MIDDLE)) &&
                                (bth_pad_cnt != 2'd0)) ? 1'b1 : 1'b0;

  assign bth_pyld_len = (ip_ver == IPv4) ? (actual_pkt_len-13'd58) : (actual_pkt_len-13'd78);

  always @(*)
  begin
    aeth_malformed = 1'b0;
    if (bth_opcode[4:0] == ACKNOWLEDGE)
    begin
      if (bth_pyld_len != 'd4)
        aeth_malformed = 1'b1;
      else if ((aeth_syndr[7]) || (aeth_syndr[6:5] == 2'b10))
        aeth_malformed = 1'b1;
      else if ((aeth_syndr[6:5] ==  2'b11) && (aeth_syndr[4:0] > 5'b0_0011))
        aeth_malformed = 1'b1;
    end
    else if ((bth_opcode[4:0] == RD_RSP_ONLY) || (bth_opcode[4:0] == RD_RSP_FIRST) ||
             (bth_opcode[4:0] == RD_RSP_LAST))
    begin
      if (bth_pyld_len <= 'd4)
        aeth_malformed = 1'b1;
      else if ((aeth_syndr[7]) || (aeth_syndr[6:5] == 2'b10))
        aeth_malformed = 1'b1;
      else if ((aeth_syndr[6:5] ==  2'b11) && (aeth_syndr[4:0] > 5'b0_0011))
        aeth_malformed = 1'b1;
    end
  end

  assign qp_conf_min = 24'd1;
  assign qp_conf_max = {{(24-C_QP_INDX_WIDTH){1'b0}}, i_num_qp_enabled};
  assign dest_qp_chk_fail = ((bth_qp_dest_addr < qp_conf_min) || (bth_qp_dest_addr > qp_conf_max)) ? 1'b1 : 1'b0;

  always @(posedge clk)
    if (hv_data_vld)
    begin
      mac_dest_addr_chk_fail_r <= mac_dest_addr_chk_fail;
      ip_ver_chk_fail_r <= (ip_ver == IPv4) ? ipv4_ver_chk_fail : ipv6_ver_chk_fail;
      ipv4_ihl_chk_fail_r <= (ip_ver == IPv4) ? ipv4_ihl_chk_fail : 1'b0;
      ip_ecn_chk_fail_r <= (ip_ver == IPv4) ? ipv4_ecn_chk_fail : ipv6_ecn_chk_fail;
      ipv4_flg_chk_fail_r <= (ip_ver == IPv4) ? ipv4_flg_chk_fail : 1'b0;
      ipv4_frag_offset_chk_fail_r <= (ip_ver == IPv4) ? ipv4_frag_offset_chk_fail : 1'b0;
      ip_dest_addr_chk_fail_r <= (ip_ver == IPv4) ? ipv4_dest_addr_chk_fail : ipv6_dest_addr_chk_fail;
      ipv4_hdr_chksum_fail_r <= (ip_ver == IPv4) ? ipv4_hdr_chksum_fail : 1'b0;
      ip_length_chk_fail_r <= (ip_ver == IPv4) ? ipv4_length_chk_fail : ipv6_length_chk_fail;
      udp_length_chk_fail_r <= udp_length_chk_fail;
      pkt_len_chk_fail_r <= pkt_len_chk_fail;
      bth_ver_chk_fail_r <= bth_ver_chk_fail;
      dest_qp_chk_fail_r <= dest_qp_chk_fail;
      bth_pad_cnt_chk_fail_r <= bth_pad_cnt_chk_fail;
      ip_ver_r <= ip_ver;
      bth_psn_r <= bth_psn;
      bth_opcode_r <= bth_opcode;
      aeth_malformed_r <= aeth_malformed;
      aeth_syndr_r <= aeth_syndr;
      aeth_msn_r <= aeth_msn;
      pkt_id_r <= pkt_id;
      pkt_src_addr_offset_r <= pkt_src_addr_offset;
      actual_pkt_len_r <= actual_pkt_len;
      i_last_rsp_opcode <= last_rsp_opcode_reg[bth_qp_dest_addr[C_QP_INDX_WIDTH-1:0]];
    end

  always @(posedge clk)
    if (reset)
      bth_qp_dest_addr_r <= 24'h00_0000;
    else if(hv_data_vld)
      bth_qp_dest_addr_r <= bth_qp_dest_addr;

  assign qp_state_fatal = (!i_qp_conf[0] || i_qp_fatal[bth_qp_dest_addr[C_QP_INDX_WIDTH-1:0]]) ? 1'b1 : 1'b0;

  always @(*)
    case (i_qp_conf[10:8])
      3'b000  :
        qp_pmtu_decoded = 13'd0256;
      3'b001  :
        qp_pmtu_decoded = 13'd0512;
      3'b010  :
        qp_pmtu_decoded = 13'd1024;
      3'b011  :
        qp_pmtu_decoded = 13'd2048;
      3'b100  :
        qp_pmtu_decoded = 13'd4096;
      default :
        qp_pmtu_decoded = 13'd0256;
    endcase

  assign i_last_ob_req_psn = i_sq_psn - 'd1;
  assign i_rnr_nak_cnt = i_stat_nak[9:7];

  always @(posedge clk)
    if (qp_conf_vld)
    begin
      qp_pmtu_decoded_r <= qp_pmtu_decoded;
      qp_state_fatal_r <= qp_state_fatal;
      ip_src_addr_chk_fail_r <= ip_src_addr_chk_fail;
      mac_src_addr_chk_fail_r <= mac_src_addr_chk_fail;
      stat_resp_psn_r <= i_stat_resp_psn;
      last_ob_req_psn_r <= i_last_ob_req_psn;
      rnr_nak_cnt_r <= i_rnr_nak_cnt;
      o_qp_timeout_per_qp <= i_qp_timeout;
    end

  assign err_syndr = {
    pkt_fcs_err,                 // bit 31
    pkt_crc_err,                 // bit 30
    1'b0,                        // bit 29
    mac_src_addr_chk_fail_r,     // bit 28
    ip_src_addr_chk_fail_r,      // bit 27
    3'b0,                        // bit 24-26
    aeth_malformed_r,            // bit 23
    4'b0,                        // bit 19-22
    bth_pad_cnt_chk_fail_r,      // bit 18
    2'b0,                        // bit 16-17
    qp_state_fatal_r,            // bit 15
    dest_qp_chk_fail_r,          // bit 14
    bth_ver_chk_fail_r,          // bit 13
    pkt_len_chk_fail_r,          // bit 12
    udp_length_chk_fail_r,       // bit 11
    ip_length_chk_fail_r,        // bit 10
    ipv4_hdr_chksum_fail_r,      // bit 9
    ip_dest_addr_chk_fail_r,     // bit 8
    1'b0,                        // bit 7
    ipv4_frag_offset_chk_fail_r, // bit 6
    ipv4_flg_chk_fail_r,         // bit 5
    ip_ecn_chk_fail_r,           // bit 4
    ipv4_ihl_chk_fail_r,         // bit 3
    ip_ver_chk_fail_r,           // bit 2
    1'b0,                        // bit 1
    mac_dest_addr_chk_fail_r     // bit 0
  };

assign unack_psn_min_muxed = stat_resp_psn_muxed + 'd1;
assign unack_psn_max_muxed = qp_conf_vld ? i_last_ob_req_psn : last_ob_req_psn_r;
assign unack_psn_min = stat_resp_psn_r + 'd1;
assign unack_psn_max = last_ob_req_psn_r;

assign i_mpsnbuf_empty_combo = i_mpsnbuf_empty[bth_qp_dest_addr_r[C_QP_INDX_WIDTH-1:0]];

assign i_osq_invld = i_osq_empty[bth_qp_dest_addr_r[C_QP_INDX_WIDTH-1:0]] |
                     i_osq_nacked[bth_qp_dest_addr_r[C_QP_INDX_WIDTH-1:0]];

assign i_qp_retried_combo = i_qp_retried[bth_qp_dest_addr_r[C_QP_INDX_WIDTH-1:0]];

assign stat_resp_psn_muxed = qp_conf_vld ? i_stat_resp_psn : stat_resp_psn_r;
assign rnr_nak_cnt_muxed = qp_conf_vld ? i_rnr_nak_cnt : rnr_nak_cnt_r;
assign qp_pmtu_decoded_muxed = qp_conf_vld ? qp_pmtu_decoded : qp_pmtu_decoded_r;

always @(*)
  if (i_last_rsp_opcode)
  begin
    if (i_os_rd_req_psn_7_0 <= stat_resp_psn_muxed[C_OSQ_PSN_WIDTH-1:0])
      i_os_rd_req_psn = {stat_resp_psn_muxed[23:C_OSQ_PSN_WIDTH], i_os_rd_req_psn_7_0};
    else
      i_os_rd_req_psn = {stat_resp_psn_muxed[23:C_OSQ_PSN_WIDTH], i_os_rd_req_psn_7_0} - {{(23-C_OSQ_PSN_WIDTH){1'b0}}, 1'b1, {(C_OSQ_PSN_WIDTH){1'b0}}};
  end
  else
  begin
    if (i_os_rd_req_psn_7_0 <= stat_resp_psn_muxed[C_OSQ_PSN_WIDTH-1:0])
      i_os_rd_req_psn = {stat_resp_psn_muxed[23:C_OSQ_PSN_WIDTH], i_os_rd_req_psn_7_0} + {{(23-C_OSQ_PSN_WIDTH){1'b0}}, 1'b1, {(C_OSQ_PSN_WIDTH){1'b0}}};
    else
      i_os_rd_req_psn = {stat_resp_psn_muxed[23:C_OSQ_PSN_WIDTH], i_os_rd_req_psn_7_0};
  end

  always @(posedge clk)
    if (mpsnbuf_vld)
    begin
      osq_invld_at_vld <= i_osq_invld;
      is_rsp_in_unack_range_at_vld <= is_in_range(unack_psn_min_muxed, unack_psn_max_muxed, bth_psn_r);
      is_rd_req_in_unack_range_at_vld <= is_in_range(i_os_rd_req_psn, unack_psn_max_muxed, bth_psn_r);
      os_rd_req_psn <= i_os_rd_req_psn;
      os_rd_req_dest_addr <= i_os_rd_req_dest_addr;
      os_rd_req_resp_len <= i_os_rd_req_resp_len;
      mpsnbuf_empty_at_vld <= i_mpsnbuf_empty_combo;
      qp_retried <= i_qp_retried_combo;
      ack_psn_less_os_rd <= is_x_less_y(bth_psn_r, i_os_rd_req_psn);
      ack_psn_lessorequal_os_rd <= is_x_lessorequal_y(bth_psn_r, i_os_rd_req_psn);
      rdrsp_psn_grtr_os_rd <= is_x_grtr_y(bth_psn_r, i_os_rd_req_psn);
      rdrsp_psn_lessorequal_last_ob_req <= is_x_lessorequal_y(bth_psn_r, unack_psn_max);
    end

  assign mpsnbuf_empty = mpsnbuf_empty_at_vld | i_mpsnbuf_empty_combo;
  assign osq_invld = osq_invld_at_vld | i_osq_invld;
  assign is_rsp_in_unack_range = is_rsp_in_unack_range_at_vld & ~i_osq_invld & ~(i_last_rsp_opcode & mpsnbuf_empty);
  assign is_rd_req_in_unack_range = is_rd_req_in_unack_range_at_vld & ~i_osq_invld & ~mpsnbuf_empty;

  always @(posedge clk)
    if (hv_data_vld)
    begin
      case (bth_opcode[4:0])
        RD_RSP_FIRST :
          pkt_type <= PKT_TYPE_READ_FIRST;
        RD_RSP_MIDDLE :
          pkt_type <= PKT_TYPE_READ_MIDDLE;
        RD_RSP_LAST :
          pkt_type <= PKT_TYPE_READ_LAST;
        RD_RSP_ONLY :
          pkt_type <= PKT_TYPE_READ_ONLY;
        ACKNOWLEDGE :
          case (aeth_syndr[6:5])
            2'b00 :
              pkt_type <= PKT_TYPE_ACKNOWLEDGE_ACK;
            2'b01 :
              pkt_type <= PKT_TYPE_ACKNOWLEDGE_RNR_NAK;
            2'b11 :
              pkt_type <= (aeth_syndr[4:0] == 5'd0) ? PKT_TYPE_ACKNOWLEDGE_NAK_SEQ_ERR :
                          PKT_TYPE_ACKNOWLEDGE_NAK_FATAL;
            default :
              pkt_type <= PKT_TYPE_ACKNOWLEDGE_NAK_SEQ_ERR;
          endcase
        default :
          pkt_type <= 3'dx;
      endcase
    end

  always @(posedge clk)
    if (mpsnbuf_vld)
    begin
      rdrsp_first_len_chk_fail <= ((bth_pyld_len != (qp_pmtu_decoded_muxed + 'd4)) || (i_os_rd_req_resp_len <= {19'd0, qp_pmtu_decoded_muxed})) ? 1'b1 : 1'b0;
      rdrsp_middle_len_chk_fail <= ((bth_pyld_len != qp_pmtu_decoded_muxed) || (i_rdrsp_len_remain <= qp_pmtu_decoded_muxed)) ? 1'b1 : 1'b0;
      rdrsp_last_len_chk_fail <= ((bth_pyld_len < 'd5) || (bth_pyld_len > (qp_pmtu_decoded_muxed + 'd4)) || (bth_pyld_len != (i_rdrsp_len_remain+'d4))) ? 1'b1 : 1'b0;
      rdrsp_only_len_chk_fail <= ((bth_pyld_len > (qp_pmtu_decoded_muxed + 'd4)) || (i_os_rd_req_resp_len > {19'd0, qp_pmtu_decoded_muxed})) ? 1'b1 : 1'b0;
    end

  always @(*)
  begin
    case (pkt_type)
      PKT_TYPE_READ_FIRST :
        acknack_opcode = 2'b01;
      PKT_TYPE_READ_MIDDLE :
        acknack_opcode = 2'b10;
      PKT_TYPE_READ_LAST,
      PKT_TYPE_READ_ONLY :
        acknack_opcode = 2'b11;
      default :
        acknack_opcode = 2'b00;
    endcase
  end

  assign o_stat_nak = {o_rnr_nak_cnt, aeth_syndr_r[6:0]};

  assign o_qp_fatal_idx = bth_qp_dest_addr_r[C_QP_INDX_WIDTH-1:0];

  assign o_qp_acknack_idx = bth_qp_dest_addr_r[C_QP_INDX_WIDTH-1:0];
/*
  assign o_acknack_vld = acknack_vld;
  assign o_acknack_psn = acknack_psn;
  assign o_acknack_syndr = acknack_syndr;
*/
  assign o_acknack_msn   = aeth_msn_r;
/*
  assign o_acknack_opcode = acknack_opcode;
*/
  always @(posedge clk)
    if (reset)
      o_acknack_vld <= 1'b0;
    else
      o_acknack_vld <= acknack_vld;

  always @(posedge clk)
    if (acknack_vld)
    begin
      o_acknack_psn <= acknack_psn;
      o_acknack_syndr <= acknack_syndr;
    end

  always @(posedge clk)
    if (reset)
      o_acknack_opcode <= 2'b00;
    else if (acknack_vld)
      o_acknack_opcode <= acknack_opcode;

  always @(posedge clk)
    if (reset)
      o_mpsnbuf_pop <= 1'b0;
    else
      o_mpsnbuf_pop <= mpsnbuf_pop;

  assign o_rdrsp_dest_addr = rsp_dest_addr + qp_pmtu_decoded_r;

/*
  assign rdrsp_len_remain = ((pkt_type == PKT_TYPE_READ_FIRST) || (pkt_type == PKT_TYPE_READ_ONLY)) ?
                           os_rd_req_resp_len : i_rdrsp_len_remain;
  assign o_rdrsp_len_remain = rdrsp_len_remain - qp_pmtu_decoded_r;
*/
  assign rdrsp_len_remain = ((pkt_type == PKT_TYPE_READ_FIRST) || (pkt_type == PKT_TYPE_READ_ONLY)) ?
                           i_os_rd_req_resp_len : i_rdrsp_len_remain;

  always @(posedge clk)
    if (mpsnbuf_vld)
      o_rdrsp_len_remain <= rdrsp_len_remain - qp_pmtu_decoded_r;

  assign rsp_buf_addr_offset = pkt_src_addr_offset_r;
  assign rsp_pkt_len = actual_pkt_len_r;
  assign rsp_pkt_id = pkt_id_r;

  xpm_memory_spram # (                        // Common module parameters
    .MEMORY_SIZE        (C_NUM_QP*C_M_AXI_ADDR_WIDTH), // positive integer
    .MEMORY_PRIMITIVE   ("auto"),             // string; "auto", "distributed", "block" or "ultra";
    .ECC_MODE           ("no_ecc"),           // do not change
    .MEMORY_INIT_FILE   ("none"),             // string; "none" or "<filename>.mem"
    .MEMORY_INIT_PARAM  (""    ),             // string;
    .WAKEUP_TIME        ("disable_sleep"),    // string; "disable_sleep" or "use_sleep_pin"
    .MESSAGE_CONTROL    (0),
                                              // Port A module parameters
    .WRITE_DATA_WIDTH_A (C_M_AXI_ADDR_WIDTH), // positive integer
    .READ_DATA_WIDTH_A  (C_M_AXI_ADDR_WIDTH), // positive integer
    .BYTE_WRITE_WIDTH_A (C_M_AXI_ADDR_WIDTH), // integer; 8, 9, or WRITE_DATA_WIDTH_A value
    .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),    // positive integer
    .READ_RESET_VALUE_A ("0"),                // string
    .READ_LATENCY_A     (1),                  // non-negative integer
    .WRITE_MODE_A       ("write_first")        // string; "write_first", "read_first", "no_change"
  ) xpm_memory_rdrsp_dest_addr (
    // Common module ports
    .sleep          (1'b0),  //do not change
    // Port A module ports
    .clka           (clk),
    .rsta           (1'b0),
    .ena            (rdrsp_dest_addr_en),
    .regcea         (1'b1),
    .wea            (rdrsp_dest_addr_we),
    .addra          (rdrsp_dest_addr_idx[C_QP_INDX_WIDTH-1:0]),
    .dina           (o_rdrsp_dest_addr),
    .injectsbiterra (1'b0),  //do not change
    .injectdbiterra (1'b0),  //do not change
    .douta          (i_rdrsp_dest_addr),
    .sbiterra       (),      //do not change
    .dbiterra       ()       //do not change
  );

  xpm_memory_spram # (                        // Common module parameters
    .MEMORY_SIZE        (C_NUM_QP*32),        // positive integer
    .MEMORY_PRIMITIVE   ("auto"),             // string; "auto", "distributed", "block" or "ultra";
    .ECC_MODE           ("no_ecc"),           // do not change
    .MEMORY_INIT_FILE   ("none"),             // string; "none" or "<filename>.mem"
    .MEMORY_INIT_PARAM  (""    ),             // string;
    .WAKEUP_TIME        ("disable_sleep"),    // string; "disable_sleep" or "use_sleep_pin"
    .MESSAGE_CONTROL    (0),
                                              // Port A module parameters
    .WRITE_DATA_WIDTH_A (32),                 // positive integer
    .READ_DATA_WIDTH_A  (32),                 // positive integer
    .BYTE_WRITE_WIDTH_A (32),                 // integer; 8, 9, or WRITE_DATA_WIDTH_A value
    .ADDR_WIDTH_A       (C_QP_INDX_WIDTH),    // positive integer
    .READ_RESET_VALUE_A ("0"),                // string
    .READ_LATENCY_A     (1),                  // non-negative integer
    .WRITE_MODE_A       ("write_first")       // string; "write_first", "read_first", "no_change"
  ) xpm_memory_rdrsp_len_remain (
    // Common module ports
    .sleep          (1'b0),  //do not change
    // Port A module ports
    .clka           (clk),
    .rsta           (1'b0),
    .ena            (rdrsp_len_remain_en),
    .regcea         (1'b1),
    .wea            (rdrsp_len_remain_we),
    .addra          (rdrsp_len_remain_idx[C_QP_INDX_WIDTH-1:0]),
    .dina           (o_rdrsp_len_remain),
    .injectsbiterra (1'b0),  //do not change
    .injectdbiterra (1'b0),  //do not change
    .douta          (i_rdrsp_len_remain),
    .sbiterra       (),      //do not change
    .dbiterra       ()       //do not change
  );

  always @(posedge clk)
    if (reset)
      last_rsp_opcode_reg <= {(C_NUM_QP) {1'b0}};
    else if (last_rsp_opcode_we)
      last_rsp_opcode_reg[bth_qp_dest_addr_r[C_QP_INDX_WIDTH-1:0]] <= o_last_rsp_opcode;

  always @(posedge clk)
    in_err_sts_code <= nxt_in_err_sts_code;

  always @(posedge clk)
    if (rsp_tnfr_vld)
    begin
      rsp_pkt_type_r <= rsp_pkt_type;
      rsp_dest_addr_r <= rsp_dest_addr;
      rsp_imm_data_r <= rsp_imm_data;
    end

  always @(*)
  begin
    // default values
    hv_fsm_busy = 1'b0;
    hv_fsm_ns = hv_fsm_cs;
    nxt_in_err_sts_code = in_err_sts_code;
    o_qp_conf_idx = bth_qp_dest_addr_r[C_QP_INDX_WIDTH-1:0];
    o_qp_mpsnbuf_idx = bth_qp_dest_addr_r[C_QP_INDX_WIDTH-1:0];
    rdrsp_dest_addr_idx = bth_qp_dest_addr_r[C_QP_INDX_WIDTH-1:0];
    rdrsp_len_remain_idx = bth_qp_dest_addr_r[C_QP_INDX_WIDTH-1:0];
    o_rnr_nak_cnt = rnr_nak_cnt_r;
    qp_conf_en = 1'b0;
    stat_nak_en = 1'b0;
    stat_nak_we = 1'b0;
    o_stat_resp_psn = bth_psn_r;
    stat_resp_psn_en = 1'b0;
    stat_resp_psn_we = 1'b0;
    sq_psn_en = 1'b0;
    remote_qp_mac_addr_en = 1'b0;
    remote_qp_ip_addr_en = 1'b0;
    o_last_rsp_opcode = i_last_rsp_opcode;
    last_rsp_opcode_we = 1'b0;
    mpsnbuf_pop = 1'b0;
    mpsnbuf_en = 1'b0;
    rdrsp_len_remain_en = 1'b0;
    rdrsp_len_remain_we = 1'b0;
    rdrsp_dest_addr_en = 1'b0;
    rdrsp_dest_addr_we = 1'b0;
    rsp_pkt_type = RSP_AXI_TNFR_TYPE_DISCARD;
    rsp_dest_addr = i_rdrsp_dest_addr;
    rsp_imm_data = 32'd0;
    rsp_tnfr_vld = 1'b0;
    req_tnfr_vld = 1'b0;
    acknack_psn = bth_psn_r;
    acknack_syndr = aeth_syndr_r;
    acknack_vld = 1'b0;
    incr_acknack_pkt_cnt = 1'b0;
    incr_inc_nack_pkt_cnt = 1'b0;
    set_qp_fatal = 1'b0;

    case (hv_fsm_cs)
      3'd0 :
      begin
        nxt_in_err_sts_code = 5'd0;

        if (hv_data_vld)
        begin
          o_qp_conf_idx         = bth_qp_dest_addr[C_QP_INDX_WIDTH-1:0];
          qp_conf_en            = 1'b1; // get QP basic configuration
          stat_nak_en           = 1'b1; // get RNR-NAK down counter value
          stat_resp_psn_en      = 1'b1; // get last accepted response PSN
          sq_psn_en             = 1'b1; // get next sending packet PSN
          remote_qp_mac_addr_en = 1'b1; // get associated QP remote node MAC address
          remote_qp_ip_addr_en  = 1'b1; // get associated QP remode node IP address
          o_qp_mpsnbuf_idx      = bth_qp_dest_addr[C_QP_INDX_WIDTH-1:0];
          mpsnbuf_en            = 1'b1; // get MAX PSN buffer entry information
          rdrsp_dest_addr_idx   = bth_qp_dest_addr[C_QP_INDX_WIDTH-1:0];
          rdrsp_len_remain_en   = 1'b1; // get current read request remaining length
          rdrsp_len_remain_idx  = bth_qp_dest_addr[C_QP_INDX_WIDTH-1:0];
          rdrsp_dest_addr_en    = 1'b1; // get current read response destination address

          if ((bth_opcode == ACKNOWLEDGE) && !aeth_malformed)
            incr_acknack_pkt_cnt = 1'b1;

          if ((bth_opcode == ACKNOWLEDGE) && (aeth_syndr[6:5] != 2'b00) && !aeth_malformed)
            incr_inc_nack_pkt_cnt = 1'b1;

          hv_fsm_busy = 1'b1;
          hv_fsm_ns = 3'd1;
        end  // if (hv_data_vld)
      end  // 3'd0

      3'd1 :
      begin
        hv_fsm_busy = 1'b1;
        if (qp_conf_vld)
        begin
          if (mpsnbuf_vld)
          begin
            hv_fsm_ns = 3'd3;
            hv_fsm_busy = 1'b0;
          end
          else
            hv_fsm_ns = 3'd2;
        end  // if (qp_conf_vld)
      end  // 3'd1

      3'd2 :
      begin
        if (mpsnbuf_vld)
          hv_fsm_ns = 2'd3;
        else
          hv_fsm_busy = 1'b1;
      end  // 3'd2

      3'd3 :
      begin
        if (err_syndr != 32'd0)
        begin
          if (i_err_buf_en)
          begin
            rsp_pkt_type = RSP_AXI_TNFR_TYPE_ERROR;
            rsp_imm_data = err_syndr;
            rsp_tnfr_vld = 1'b1;
            if (!rdy_to_rsp_tnfr)
              hv_fsm_busy = 1'b1;
          end
          if (!i_err_buf_en || (i_err_buf_en && rdy_to_rsp_tnfr))
          begin
            hv_fsm_ns = 3'd0;
            if (aeth_malformed_r)
            begin
              o_rnr_nak_cnt = i_rnr_nak_rst_val;
              stat_nak_en = 1'b1;
              stat_nak_we = 1'b1;
            end
          end
        end // if (err_syndr != 32'd0)
        else  // err_syndr == 32'd0
        begin
          case (pkt_type)
            PKT_TYPE_ACKNOWLEDGE_ACK :
            begin
              hv_fsm_ns = 3'd0;

              if (is_rsp_in_unack_range)
              begin
                if (i_last_rsp_opcode)
                begin
                  if (!qp_retried)
                  begin
                    acknack_psn = os_rd_req_psn;
                    acknack_syndr = {1'b0, NAK, PSN_SEQ_ERR};
                    acknack_vld = 1'b1;
                    hv_fsm_ns = 3'd6;
                    hv_fsm_busy = 1'b1;
                  end
                end
                else if ((bth_psn_r == os_rd_req_psn) && !mpsnbuf_empty) // ACK-Fatal case (not full proof)
                begin
                  rsp_pkt_type = RSP_AXI_TNFR_TYPE_ERROR;
                  rsp_imm_data = 32'h0040_0000;
                  rsp_tnfr_vld = 1'b1;
                  hv_fsm_busy = 1'b1;
                  if (rdy_to_rsp_tnfr)
                  begin
                    nxt_in_err_sts_code = 5'b01_100;
                    hv_fsm_ns = 3'd4;
                  end
                end // ACK-Fatal case
                else if (mpsnbuf_empty || (!mpsnbuf_empty && ack_psn_less_os_rd))
                begin
                  acknack_psn = bth_psn_r;
                  acknack_syndr = aeth_syndr_r;
                  acknack_vld = 1'b1;
                  hv_fsm_ns = 3'd6;
                  hv_fsm_busy = 1'b1;

                  o_stat_resp_psn = bth_psn_r;
                  stat_resp_psn_en = 1'b1;
                  stat_resp_psn_we = 1'b1;

                  o_rnr_nak_cnt = i_rnr_nak_rst_val;
                  stat_nak_en = 1'b1;
                  stat_nak_we = 1'b1;
                end // mpsnbuf_empty
                else // bth_psn > os_rd_req_psn
                begin
                  if (unack_psn_min != os_rd_req_psn)
                  begin
                    o_stat_resp_psn = os_rd_req_psn-'d1;
                    stat_resp_psn_en = 1'b1;
                    stat_resp_psn_we = 1'b1;

                    o_rnr_nak_cnt = i_rnr_nak_rst_val;
                    stat_nak_en = 1'b1;
                    stat_nak_we = 1'b1;

                    acknack_psn = os_rd_req_psn;
                    acknack_syndr = {1'b0, NAK, PSN_SEQ_ERR};
                    acknack_vld = 1'b1;
                    hv_fsm_ns = 3'd6;
                    hv_fsm_busy = 1'b1;
                  end
                  else if (!qp_retried)
                  begin
                    acknack_psn = os_rd_req_psn;
                    acknack_syndr = {1'b0, NAK, PSN_SEQ_ERR};
                    acknack_vld = 1'b1;
                    hv_fsm_ns = 3'd6;
                    hv_fsm_busy = 1'b1;
                  end
                end // bth_psn > os_rd_req_psn
              end  // is_rsp_in_unack_range
            end // PKT_TYPE_ACKNOWLEDGE_ACK

            PKT_TYPE_ACKNOWLEDGE_RNR_NAK :
            begin
              hv_fsm_ns = 3'd0;

              if (i_last_rsp_opcode)
              begin
                if (is_rd_req_in_unack_range)
                begin
                  if (bth_psn_r == os_rd_req_psn)
                  begin
                    if (rnr_nak_cnt_r == 3'd0) // RNR down counter expired
                    begin
                      rsp_pkt_type = RSP_AXI_TNFR_TYPE_ERROR;
                      rsp_imm_data = 32'h0040_0000;
                      rsp_tnfr_vld = 1'b1;
                      hv_fsm_busy = 1'b1;
                      if (rdy_to_rsp_tnfr)
                      begin
                        nxt_in_err_sts_code = 5'b01_001;
                        hv_fsm_ns = 3'd4;
                      end
                    end
                    else  // rnr_nak_cnt_r > 3'd0
                    begin
                      acknack_psn = bth_psn_r;
                      acknack_syndr = aeth_syndr_r;
                      acknack_vld = 1'b1;
                      hv_fsm_ns = 3'd6;
                      hv_fsm_busy = 1'b1;

                      if (rnr_nak_cnt_r != 3'd7)
                        o_rnr_nak_cnt = rnr_nak_cnt_r-'d1;
                      else
                        o_rnr_nak_cnt = i_rnr_nak_rst_val;

                      stat_nak_en = 1'b1;
                      stat_nak_we = 1'b1;
                    end  // rnr_nak_cnt_r > 3'd0
                  end  // bth_psn_r == os_rd_req_psn
                end  // is_rd_req_in_unack_range
              end
              else  // !i_last_rsp_opcode
              begin
                if (is_rsp_in_unack_range)
                begin
                  if (bth_psn_r == unack_psn_min)
                  begin
                    if (rnr_nak_cnt_r == 3'd0)
                    begin
                      rsp_pkt_type = RSP_AXI_TNFR_TYPE_ERROR;
                      rsp_imm_data = 32'h0040_0000;
                      rsp_tnfr_vld = 1'b1;
                      hv_fsm_busy = 1'b1;
                      if (rdy_to_rsp_tnfr)
                      begin
                        nxt_in_err_sts_code = 5'b01_001;
                        hv_fsm_ns = 3'd4;
                      end
                    end
                    else  // rnr_nak_cnt_r > 3'd0
                    begin
                      acknack_psn = bth_psn_r;
                      acknack_syndr = aeth_syndr_r;
                      acknack_vld = 1'b1;
                      hv_fsm_ns = 3'd6;
                      hv_fsm_busy = 1'b1;

                      if (rnr_nak_cnt_r != 3'd7)
                        o_rnr_nak_cnt = rnr_nak_cnt_r-'d1;
                      else
                        o_rnr_nak_cnt = i_rnr_nak_rst_val;

                      stat_nak_en = 1'b1;
                      stat_nak_we = 1'b1;
                    end  // rnr_nak_cnt_r > 3'd0
                  end  // bth_psn_r == unack_psn_min
                  else if (mpsnbuf_empty || (!mpsnbuf_empty && ack_psn_lessorequal_os_rd))
                  begin
                    acknack_psn = bth_psn_r;
                    acknack_syndr = aeth_syndr_r;
                    acknack_vld = 1'b1;
                    hv_fsm_ns = 3'd6;
                    hv_fsm_busy = 1'b1;

                    o_stat_resp_psn = bth_psn_r-'d1;
                    stat_resp_psn_en = 1'b1;
                    stat_resp_psn_we = 1'b1;

                    o_rnr_nak_cnt = i_rnr_nak_rst_val;
                    stat_nak_en = 1'b1;
                    stat_nak_we = 1'b1;
                  end
                  else  // bth_psn > os_rd_req_psn
                  begin
                    o_stat_resp_psn = os_rd_req_psn-'d1;
                    stat_resp_psn_en = 1'b1;
                    stat_resp_psn_we = 1'b1;

                    o_rnr_nak_cnt = i_rnr_nak_rst_val;
                    stat_nak_en = 1'b1;
                    stat_nak_we = 1'b1;

                    acknack_psn = os_rd_req_psn;
                    acknack_syndr = {1'b0, NAK, PSN_SEQ_ERR};
                    acknack_vld = 1'b1;
                    hv_fsm_ns = 3'd6;
                    hv_fsm_busy = 1'b1;
                  end  // bth_psn > os_rd_req_psn
                end  // is_rsp_in_unack_range
              end  // !i_last_rsp_opcode
            end

            PKT_TYPE_ACKNOWLEDGE_NAK_SEQ_ERR :
            begin
              hv_fsm_ns = 3'd0;

              if (is_rsp_in_unack_range)
              begin
                if (i_last_rsp_opcode)
                begin
                  if (!qp_retried)
                  begin
                    acknack_psn = os_rd_req_psn;
                    acknack_syndr = {1'b0, NAK, PSN_SEQ_ERR};
                    acknack_vld = 1'b1;
                    hv_fsm_ns = 3'd6;
                    hv_fsm_busy = 1'b1;
                  end
                end
                else if (mpsnbuf_empty || (!mpsnbuf_empty && ack_psn_lessorequal_os_rd))
                begin
                  acknack_psn = bth_psn_r;
                  acknack_syndr = aeth_syndr_r;
                  acknack_vld = 1'b1;
                  hv_fsm_ns = 3'd6;
                  hv_fsm_busy = 1'b1;

                  o_stat_resp_psn = bth_psn_r-'d1;
                  stat_resp_psn_en = 1'b1;
                  stat_resp_psn_we = 1'b1;

                  o_rnr_nak_cnt = i_rnr_nak_rst_val;
                  stat_nak_en = 1'b1;
                  stat_nak_we = 1'b1;
                end
                else // bth_psn > os_rd_req_psn
                begin
                  if (unack_psn_min != os_rd_req_psn)
                  begin
                    o_stat_resp_psn = os_rd_req_psn-'d1;
                    stat_resp_psn_en = 1'b1;
                    stat_resp_psn_we = 1'b1;

                    o_rnr_nak_cnt = i_rnr_nak_rst_val;
                    stat_nak_en = 1'b1;
                    stat_nak_we = 1'b1;

                    acknack_psn = os_rd_req_psn;
                    acknack_syndr = {1'b0, NAK, PSN_SEQ_ERR};
                    acknack_vld = 1'b1;
                    hv_fsm_ns = 3'd6;
                    hv_fsm_busy = 1'b1;
                  end
                  else if (!qp_retried)
                  begin
                    acknack_psn = os_rd_req_psn;
                    acknack_syndr = {1'b0, NAK, PSN_SEQ_ERR};
                    acknack_vld = 1'b1;
                    hv_fsm_ns = 3'd6;
                    hv_fsm_busy = 1'b1;
                  end
                end // bth_psn > os_rd_req_psn
              end  // is_rsp_in_unack_range
            end // PKT_TYPE_ACKNOWLEDGE_NAK_SEQ_ERR

            PKT_TYPE_ACKNOWLEDGE_NAK_FATAL :
            begin
              if (is_rsp_in_unack_range)
              begin
                if (i_last_rsp_opcode)
                begin
                  if (bth_psn_r == unack_psn_min)
                  begin
                    rsp_pkt_type = RSP_AXI_TNFR_TYPE_ERROR;
                    rsp_imm_data = 32'h0040_0000;
                    rsp_tnfr_vld = 1'b1;
                    hv_fsm_busy = 1'b1;
                    if (rdy_to_rsp_tnfr)
                    begin
                      nxt_in_err_sts_code = 5'b01_010;
                      hv_fsm_ns = 3'd4;
                    end
                  end
                  else if (!qp_retried)
                  begin
                    acknack_psn = os_rd_req_psn;
                    acknack_syndr = {1'b0, NAK, PSN_SEQ_ERR};
                    acknack_vld = 1'b1;
                    hv_fsm_ns = 3'd6;
                    hv_fsm_busy = 1'b1;
                  end
                  else
                  begin
                    hv_fsm_ns = 3'd0;
                  end
                end
                else if (mpsnbuf_empty || (!mpsnbuf_empty && ack_psn_lessorequal_os_rd))
                begin
                  rsp_pkt_type = RSP_AXI_TNFR_TYPE_ERROR;
                  rsp_imm_data = 32'h0040_0000;
                  rsp_tnfr_vld = 1'b1;
                  hv_fsm_busy = 1'b1;
                  if (rdy_to_rsp_tnfr)
                  begin
                    nxt_in_err_sts_code = 5'b01_010;
                    hv_fsm_ns = 3'd4;
                  end
                end
                else
                begin
 		  if (mpsnbuf_empty || (!mpsnbuf_empty && ack_psn_lessorequal_os_rd))
                  begin
                    rsp_pkt_type = RSP_AXI_TNFR_TYPE_ERROR;
                    rsp_imm_data = 32'h0040_0000;
                    rsp_tnfr_vld = 1'b1;
                    hv_fsm_busy = 1'b1;
                    if (rdy_to_rsp_tnfr)
                    begin
                      nxt_in_err_sts_code = 5'b01_010;
                      hv_fsm_ns = 3'd4;
                    end
                  end
		  else if (!qp_retried)
                  begin
                    acknack_psn = os_rd_req_psn;
                    acknack_syndr = {1'b0, NAK, PSN_SEQ_ERR};
                    acknack_vld = 1'b1;
                    hv_fsm_ns = 3'd6;
                    hv_fsm_busy = 1'b1;
                  end
                  else
                  begin
                    hv_fsm_ns = 3'd0;
                  end
                end
              end  // is_rsp_in_unack_range
            end // PKT_TYPE_ACKNOWLEDGE_NAK_FATAL

            PKT_TYPE_READ_ONLY :
            begin
              if (!is_rsp_in_unack_range || mpsnbuf_empty)
                hv_fsm_ns = 3'd0;
              else if (i_last_rsp_opcode)
              begin
                if (bth_psn_r == unack_psn_min)
                begin
                  rsp_pkt_type = RSP_AXI_TNFR_TYPE_ERROR;
                  rsp_imm_data = 32'h0040_0000;
                  rsp_tnfr_vld = 1'b1;
                  hv_fsm_busy = 1'b1;
                  if (rdy_to_rsp_tnfr)
                  begin
                    nxt_in_err_sts_code[4:3] = 2'b11;
                    nxt_in_err_sts_code[2] = 1'b1;
                    nxt_in_err_sts_code[1] = 1'b0;
                    nxt_in_err_sts_code[0] = 1'b0;
                    hv_fsm_ns = 3'd4;
                  end
                end
                else
                begin
                  if (!qp_retried)
                  begin
                    acknack_psn = os_rd_req_psn;
                    acknack_syndr = {1'b0, NAK, PSN_SEQ_ERR};
                    acknack_vld = 1'b1;
                    hv_fsm_ns = 3'd6;
                    hv_fsm_busy = 1'b1;
                  end
                  else
                    hv_fsm_ns = 3'd0;
                end
              end
              else if (bth_psn_r == os_rd_req_psn)
              begin
                if (rdrsp_only_len_chk_fail || (aeth_syndr_r[6:5] != 2'b00))
                begin
                  rsp_pkt_type = RSP_AXI_TNFR_TYPE_ERROR;
                  rsp_imm_data = 32'h0040_0000;
                  rsp_tnfr_vld = 1'b1;
                  hv_fsm_busy = 1'b1;
                  if (rdy_to_rsp_tnfr)
                  begin
                    nxt_in_err_sts_code[4:3] = 2'b11;
                    nxt_in_err_sts_code[2] = 1'b0;
                    nxt_in_err_sts_code[1] = rdrsp_only_len_chk_fail;
                    nxt_in_err_sts_code[0] = (aeth_syndr_r[6:5] != 2'b00) ? 1'b1 : 1'b0;
                    hv_fsm_ns = 3'd4;
                  end
                end
                else
                begin
                  rsp_dest_addr = os_rd_req_dest_addr;
                  rsp_pkt_type = (ip_ver_r == IPv4) ? RSP_AXI_TNFR_TYPE_IPV4_READ_ONLY_OR_LAST :
                                RSP_AXI_TNFR_TYPE_IPV6_READ_ONLY_OR_LAST;
                  rsp_imm_data = {{(16-C_QP_INDX_WIDTH){1'b0}}, bth_qp_dest_addr_r[C_QP_INDX_WIDTH-1:0], 16'd0};
                  rsp_tnfr_vld = 1'b1;
                  o_stat_resp_psn = bth_psn_r;
                  stat_resp_psn_en = 1'b1;
                  stat_resp_psn_we = 1'b1;

                  o_last_rsp_opcode = 1'b0;
                  last_rsp_opcode_we = 1'b1;

                  rdrsp_dest_addr_en = 1'b1;
                  rdrsp_dest_addr_we = 1'b1;

                  rdrsp_len_remain_en = 1'b1;
                  rdrsp_len_remain_we = 1'b1;

                  o_rnr_nak_cnt = i_rnr_nak_rst_val;
                  stat_nak_en = 1'b1;
                  stat_nak_we = 1'b1;

                  acknack_psn = bth_psn_r;
                  acknack_syndr = aeth_syndr_r;
                  acknack_vld = 1'b1;
                  mpsnbuf_pop = 1'b1;

                  if (!rdy_to_rsp_tnfr)
                  begin
                    hv_fsm_busy = 1'b1;
                    hv_fsm_ns = 3'd5;
                  end
                  else
                  begin
                    hv_fsm_ns = 3'd6;
                    hv_fsm_busy = 1'b1;
                  end
                end
              end
              else // skip read response case
              begin
                if (unack_psn_min != os_rd_req_psn)
                begin
                  o_stat_resp_psn = os_rd_req_psn-'d1;
                  stat_resp_psn_en = 1'b1;
                  stat_resp_psn_we = 1'b1;

                  o_rnr_nak_cnt = i_rnr_nak_rst_val;
                  stat_nak_en = 1'b1;
                  stat_nak_we = 1'b1;

                  acknack_psn = os_rd_req_psn;
                  acknack_syndr = {1'b0, NAK, PSN_SEQ_ERR};
                  acknack_vld = 1'b1;
                  hv_fsm_ns = 3'd6;
                  hv_fsm_busy = 1'b1;
                end
                else if (!qp_retried)
                begin
                  acknack_psn = os_rd_req_psn;
                  acknack_syndr = {1'b0, NAK, PSN_SEQ_ERR};
                  acknack_vld = 1'b1;
                  hv_fsm_ns = 3'd6;
                  hv_fsm_busy = 1'b1;
                end
                else
                  hv_fsm_ns = 3'd0;
              end // skip read response case
            end // PKT_TYPE_READ_ONLY

            PKT_TYPE_READ_FIRST :
            begin
              if (!is_rsp_in_unack_range || mpsnbuf_empty)
                hv_fsm_ns = 3'd0;
              else if (i_last_rsp_opcode)
              begin
                if (bth_psn_r == unack_psn_min)
                begin
                  rsp_pkt_type = RSP_AXI_TNFR_TYPE_ERROR;
                  rsp_imm_data = 32'h0040_0000;
                  rsp_tnfr_vld = 1'b1;
                  hv_fsm_busy = 1'b1;
                  if (rdy_to_rsp_tnfr)
                  begin
                    nxt_in_err_sts_code[4:3] = 2'b11;
                    nxt_in_err_sts_code[2] = 1'b1;
                    nxt_in_err_sts_code[1] = rdrsp_first_len_chk_fail;
                    nxt_in_err_sts_code[0] = (aeth_syndr_r[6:5] != 2'b00) ? 1'b1 : 1'b0;
                    hv_fsm_ns = 3'd4;
                  end
                end
                else
                begin
                  if (!qp_retried)
                  begin
                    acknack_psn = os_rd_req_psn;
                    acknack_syndr = {1'b0, NAK, PSN_SEQ_ERR};
                    acknack_vld = 1'b1;
                    hv_fsm_ns = 3'd6;
                    hv_fsm_busy = 1'b1;
                  end
                  else
                    hv_fsm_ns = 3'd0;
                end
              end
              else if (bth_psn_r == os_rd_req_psn)
              begin
                if (rdrsp_first_len_chk_fail || (aeth_syndr_r[6:5] != 2'b00))
                begin
                  rsp_pkt_type = RSP_AXI_TNFR_TYPE_ERROR;
                  rsp_imm_data = 32'h0040_0000;
                  rsp_tnfr_vld = 1'b1;
                  hv_fsm_busy = 1'b1;
                  if (rdy_to_rsp_tnfr)
                  begin
                    nxt_in_err_sts_code[4:3] = 2'b11;
                    nxt_in_err_sts_code[2] = 1'b0;
                    nxt_in_err_sts_code[1] = rdrsp_first_len_chk_fail;
                    nxt_in_err_sts_code[0] = (aeth_syndr_r[6:5] != 2'b00) ? 1'b1 : 1'b0;
                    hv_fsm_ns = 3'd4;
                  end
                end
                else
                begin
                  rsp_dest_addr = os_rd_req_dest_addr;
                  rsp_pkt_type = (ip_ver_r == IPv4) ? RSP_AXI_TNFR_TYPE_IPV4_READ_FIRST :
                                RSP_AXI_TNFR_TYPE_IPV6_READ_FIRST;
                  rsp_tnfr_vld = 1'b1;
                  o_stat_resp_psn = bth_psn_r;
                  stat_resp_psn_en = 1'b1;
                  stat_resp_psn_we = 1'b1;

                  o_last_rsp_opcode = 1'b1;
                  last_rsp_opcode_we = 1'b1;

                  rdrsp_dest_addr_en = 1'b1;
                  rdrsp_dest_addr_we = 1'b1;

                  rdrsp_len_remain_en = 1'b1;
                  rdrsp_len_remain_we = 1'b1;

                  o_rnr_nak_cnt = i_rnr_nak_rst_val;
                  stat_nak_en = 1'b1;
                  stat_nak_we = 1'b1;

                  acknack_psn = bth_psn_r-'d1;
                  acknack_syndr = aeth_syndr_r;
                  acknack_vld = 1'b1;

                  if (!rdy_to_rsp_tnfr)
                  begin
                    hv_fsm_busy = 3'd1;
                    hv_fsm_ns = 3'd5;
                  end
                  else
                  begin
                    hv_fsm_ns = 3'd6;
                    hv_fsm_busy = 1'b1;
                  end
                end
              end
              else // skip read response case
              begin
                if (unack_psn_min != os_rd_req_psn)
                begin
                  o_stat_resp_psn = os_rd_req_psn-'d1;
                  stat_resp_psn_en = 1'b1;
                  stat_resp_psn_we = 1'b1;

                  o_rnr_nak_cnt = i_rnr_nak_rst_val;
                  stat_nak_en = 1'b1;
                  stat_nak_we = 1'b1;

                  acknack_psn = os_rd_req_psn;
                  acknack_syndr = {1'b0, NAK, PSN_SEQ_ERR};
                  acknack_vld = 1'b1;
                  hv_fsm_ns = 3'd6;
                  hv_fsm_busy = 1'b1;
                end
                else if (!qp_retried)
                begin
                  acknack_psn = os_rd_req_psn;
                  acknack_syndr = {1'b0, NAK, PSN_SEQ_ERR};
                  acknack_vld = 1'b1;
                  hv_fsm_ns = 3'd6;
                  hv_fsm_busy = 1'b1;
                end
                else
                  hv_fsm_ns = 3'd0;
              end // skip read response case
            end // PKT_TYPE_READ_FIRST

            PKT_TYPE_READ_MIDDLE :
            begin
              if (!is_rsp_in_unack_range || mpsnbuf_empty)
                hv_fsm_ns = 3'd0;
              else if (bth_psn_r == unack_psn_min)
              begin
                if (rdrsp_middle_len_chk_fail || !i_last_rsp_opcode)
                begin
                  rsp_pkt_type = RSP_AXI_TNFR_TYPE_ERROR;
                  rsp_imm_data = 32'h0040_0000;
                  rsp_tnfr_vld = 1'b1;
                  hv_fsm_busy = 1'b1;
                  if (rdy_to_rsp_tnfr)
                  begin
                    nxt_in_err_sts_code[4:3] = 2'b11;
                    nxt_in_err_sts_code[2] = ~i_last_rsp_opcode;
                    nxt_in_err_sts_code[1] = rdrsp_middle_len_chk_fail;
                    nxt_in_err_sts_code[0] = 1'b0;
                    hv_fsm_ns = 3'd4;
                  end
                end
                else
                begin
                  rsp_pkt_type = (ip_ver_r == IPv4) ? RSP_AXI_TNFR_TYPE_IPV4_READ_MIDDLE :
                                RSP_AXI_TNFR_TYPE_IPV6_READ_MIDDLE;
                  rsp_tnfr_vld = 1'b1;

                  o_stat_resp_psn = bth_psn_r;
                  stat_resp_psn_en = 1'b1;
                  stat_resp_psn_we = 1'b1;

                  o_last_rsp_opcode = 1'b1;
                  last_rsp_opcode_we = 1'b1;

                  rdrsp_dest_addr_en = 1'b1;
                  rdrsp_dest_addr_we = 1'b1;

                  rdrsp_len_remain_en = 1'b1;
                  rdrsp_len_remain_we = 1'b1;

                  o_rnr_nak_cnt = i_rnr_nak_rst_val;
                  stat_nak_en = 1'b1;
                  stat_nak_we = 1'b1;

                  acknack_psn = bth_psn_r-'d1;
                  acknack_syndr = 8'd0;
                  acknack_vld = 1'b1;

                  if (!rdy_to_rsp_tnfr)
                  begin
                    hv_fsm_busy = 3'd1;
                    hv_fsm_ns = 3'd5;
                  end
                  else
                  begin
                    hv_fsm_ns = 3'd6;
                    hv_fsm_busy = 1'b1;
                  end
                end
              end
              else if (!i_last_rsp_opcode)
              begin
                if (unack_psn_min != os_rd_req_psn)
                begin
                  o_stat_resp_psn = os_rd_req_psn-'d1;
                  stat_resp_psn_en = 1'b1;
                  stat_resp_psn_we = 1'b1;

                  o_rnr_nak_cnt = i_rnr_nak_rst_val;
                  stat_nak_en = 1'b1;
                  stat_nak_we = 1'b1;

                  acknack_psn = os_rd_req_psn;
                  acknack_syndr = {1'b0, NAK, PSN_SEQ_ERR};
                  acknack_vld = 1'b1;
                  hv_fsm_ns = 3'd6;
                  hv_fsm_busy = 1'b1;
                end
                else if (!qp_retried)
                begin
                  acknack_psn = os_rd_req_psn;
                  acknack_syndr = {1'b0, NAK, PSN_SEQ_ERR};
                  acknack_vld = 1'b1;
                  hv_fsm_ns = 3'd6;
                  hv_fsm_busy = 1'b1;
                end
                else
                begin
                  hv_fsm_ns = 3'd0;
                end
              end
              else
              begin
                if (!qp_retried)
                begin
                  acknack_psn = os_rd_req_psn;
                  acknack_syndr = {1'b0, NAK, PSN_SEQ_ERR};
                  acknack_vld = 1'b1;
                  hv_fsm_ns = 3'd6;
                  hv_fsm_busy = 1'b1;
                end
                else
                begin
                  hv_fsm_ns = 3'd0;
                end
              end
            end // PKT_TYPE_READ_MIDDLE

            PKT_TYPE_READ_LAST :
            begin
              if (!is_rsp_in_unack_range || mpsnbuf_empty)
                hv_fsm_ns = 3'd0;
              else if (bth_psn_r == unack_psn_min)
              begin
                if (rdrsp_last_len_chk_fail || !i_last_rsp_opcode ||(aeth_syndr_r[6:5] != 2'b00))
                begin
                  rsp_pkt_type = RSP_AXI_TNFR_TYPE_ERROR;
                  rsp_imm_data = 32'h0040_0000;
                  rsp_tnfr_vld = 1'b1;
                  hv_fsm_busy = 1'b1;
                  if (rdy_to_rsp_tnfr)
                  begin
                    nxt_in_err_sts_code[4:3] = 2'b11;
                    nxt_in_err_sts_code[2] = ~i_last_rsp_opcode;
                    nxt_in_err_sts_code[1] = rdrsp_last_len_chk_fail;
                    nxt_in_err_sts_code[0] = (aeth_syndr_r[6:5] != 2'b00) ? 1'b1 : 1'b0;
                    hv_fsm_ns = 3'd4;
                  end
                end
                else
                begin
                  rsp_pkt_type = (ip_ver_r == IPv4) ? RSP_AXI_TNFR_TYPE_IPV4_READ_ONLY_OR_LAST :
                                RSP_AXI_TNFR_TYPE_IPV6_READ_ONLY_OR_LAST;
                  rsp_imm_data = {{(16-C_QP_INDX_WIDTH){1'b0}}, bth_qp_dest_addr_r[C_QP_INDX_WIDTH-1:0], 16'd0};
                  rsp_tnfr_vld = 1'b1;

                  o_stat_resp_psn = bth_psn_r;
                  stat_resp_psn_en = 1'b1;
                  stat_resp_psn_we = 1'b1;

                  o_last_rsp_opcode = 1'b0;
                  last_rsp_opcode_we = 1'b1;

                  rdrsp_dest_addr_en = 1'b1;
                  rdrsp_dest_addr_we = 1'b1;

                  rdrsp_len_remain_en = 1'b1;
                  rdrsp_len_remain_we = 1'b1;

                  o_rnr_nak_cnt = i_rnr_nak_rst_val;
                  stat_nak_en = 1'b1;
                  stat_nak_we = 1'b1;

                  acknack_psn = bth_psn_r;
                  acknack_syndr = 8'd0;
                  acknack_vld = 1'b1;
                  mpsnbuf_pop = 1'b1;

                  if (!rdy_to_rsp_tnfr)
                  begin
                    hv_fsm_busy = 3'd1;
                    hv_fsm_ns = 3'd5;
                  end
                  else
                  begin
                    hv_fsm_ns = 3'd6;
                    hv_fsm_busy = 1'b1;
                  end
                end
              end
              else if (!i_last_rsp_opcode)
              begin
                if (unack_psn_min != os_rd_req_psn)
                begin
                  o_stat_resp_psn = os_rd_req_psn-'d1;
                  stat_resp_psn_en = 1'b1;
                  stat_resp_psn_we = 1'b1;

                  o_rnr_nak_cnt = i_rnr_nak_rst_val;
                  stat_nak_en = 1'b1;
                  stat_nak_we = 1'b1;

                  acknack_psn = os_rd_req_psn;
                  acknack_syndr = {1'b0, NAK, PSN_SEQ_ERR};
                  acknack_vld = 1'b1;
                  hv_fsm_ns = 3'd6;
                  hv_fsm_busy = 1'b1;
                end
                else if (!qp_retried)
                begin
                  acknack_psn = os_rd_req_psn;
                  acknack_syndr = {1'b0, NAK, PSN_SEQ_ERR};
                  acknack_vld = 1'b1;
                  hv_fsm_ns = 3'd6;
                  hv_fsm_busy = 1'b1;
                end
                else
                begin
                  hv_fsm_ns = 3'd0;
                end
              end
              else
              begin
                if (!qp_retried)
                begin
                  acknack_psn = os_rd_req_psn;
                  acknack_syndr = {1'b0, NAK, PSN_SEQ_ERR};
                  acknack_vld = 1'b1;
                  hv_fsm_ns = 3'd6;
                  hv_fsm_busy = 1'b1;
                end
                else
                begin
                  hv_fsm_ns = 3'd0;
                end
              end
            end // PKT_TYPE_READ_LAST

          endcase // case(pkt_type)
        end  // err_syndr == 32'd0
      end // 3'd3

      3'd4 :
      begin
        rsp_imm_data = {{(16-C_QP_INDX_WIDTH){1'b0}}, bth_qp_dest_addr_r[C_QP_INDX_WIDTH-1:0], 11'd0, in_err_sts_code};
        req_tnfr_vld = 1'b1;

        if (!rdy_to_req_tnfr)
          hv_fsm_busy = 1'b1;
        else
        begin
          o_last_rsp_opcode = 1'b0;
          last_rsp_opcode_we = 1'b1;
          // update stat_nak (for aeth_syndrome)
          stat_nak_en = 1'b1;
          stat_nak_we = 1'b1;

          // added to know on what PSN QP goes to Fatal state
          o_stat_resp_psn = bth_psn_r;
          stat_resp_psn_en = 1'b1;
          stat_resp_psn_we = 1'b1;

          set_qp_fatal = 1'b1;
          hv_fsm_ns = 3'd0;
        end
      end  // 3'd4

      3'd5 :
      begin
        rsp_pkt_type = rsp_pkt_type_r;
        rsp_dest_addr = rsp_dest_addr_r;
        rsp_imm_data = rsp_imm_data_r;
        rsp_tnfr_vld = 1'b1;

        if (!rdy_to_rsp_tnfr)
          hv_fsm_busy = 1'b1;
        else
          hv_fsm_ns = 3'd0;
      end

      3'd6 :
      begin
        hv_fsm_ns = 3'd0;
      end

      default :
      begin
        hv_fsm_ns = 3'dx;
      end  // default
    endcase  // case (hv_fsm_cs)

  end  // always @(*)

  always @(posedge clk)
    if (reset)
      hv_fsm_cs <= 3'd0;
    else
      hv_fsm_cs <= hv_fsm_ns;

  always @(posedge clk)
    if (reset)
      o_acknack_pkt_cnt <= 16'd0;
    else if (incr_acknack_pkt_cnt)
      o_acknack_pkt_cnt <= o_acknack_pkt_cnt + 'd1;

  always @(posedge clk)
    if (reset)
      o_inc_nack_pkt_cnt <= 16'd0;
    else if (incr_inc_nack_pkt_cnt)
      o_inc_nack_pkt_cnt <= o_inc_nack_pkt_cnt + 'd1;

  assign o_last_in_rsp_pkt_opcode = bth_opcode_r;
  assign o_last_in_rsp_pkt_qpid = bth_qp_dest_addr_r[7:0];
  assign o_last_in_rsp_pkt_psn = bth_psn_r[15:0];

  // =====================================================================
  // Debug Logic
  // =====================================================================
  always @(posedge clk)
    if (reset)
      qp_fatal_rsp_hv_sticky <= 1'b0;
    else if (i_clr_debug_sts)
      qp_fatal_rsp_hv_sticky <= 1'b0;
    else if (set_qp_fatal)
      qp_fatal_rsp_hv_sticky <= 1'b1;

  always @(posedge clk)
    if (reset)
      resp_drop_cnt <= 32'd0;
    else if (i_clr_debug_sts)
      resp_drop_cnt <= 32'd0;
    else if ((hv_fsm_cs == 3'd3) && is_rsp_in_unack_range_at_vld && (osq_invld || (pkt_type[2] || i_last_rsp_opcode) && mpsnbuf_empty))
      resp_drop_cnt <= resp_drop_cnt + 'd1;

endmodule

