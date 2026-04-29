// rx_pkt_handler.v
// 文件名          : rx_pkt_handler.v
// 版本            : v1.0
// 描述            : RX 包处理顶层模块，解析接收到的 RoCEv2 数据包
//                   区分请求包与响应包，提取 BTH/RETH/AETH 等头部信息
// Verilog 标准    : Verilog'2001

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
`timescale 1 ps / 1 ps

module rx_pkt_handler #(
  parameter C_SIM_DEBUG = 0,
  parameter C_M_AXI_ADDR_WIDTH =  32,
  parameter C_NUM_QP = 256,
  parameter C_QP_INDX_WIDTH = 8,
  parameter C_OSQ_PSN_WIDTH	= 8,
  parameter C_EN_DEBUG_PORTS = 0
) (
  // System Clock & Reset
  input  wire                                core_clk,
  input  wire                                core_rst_n,

  // Ethernet controller interface
  input  wire                                s_axis_tvalid,
  input  wire [511:0]                        s_axis_tdata,
  input  wire [ 63:0]                        s_axis_tkeep,
  input  wire                                s_axis_tlast,
  input  wire [  0:0]                        s_axis_tuser,

  // RDMA register interface
  input  wire                                i_rdma_en,                  // RDMA interface enable from RDMA registers
  input  wire [C_QP_INDX_WIDTH-1:0]          i_num_qp_enabled,             // Number of QPs enabled

  input  wire [ 47:0]                        i_mac_node_addr,
  input  wire [ 31:0]                        i_ipv4_node_addr,
  input  wire [127:0]                        i_ipv6_node_addr,

  input  wire [  4:0]                        i_rnr_nak_tval,
  input  wire [  2:0]                        i_rnr_nak_rst_val,

  input  wire [  1:0]                        i_flow_credits,

  input  wire                                i_depkt_bypass_en,           // RDMA interface bypass feature enable
  input  wire [C_M_AXI_ADDR_WIDTH-1:0]       i_bypass_buf_ba,             // Bypass packet queue base address
  input  wire [15:0]                         i_bypass_num_bufs,           // Bypass packet queue depth
  input  wire [15:0]                         i_bypass_buffer_sz,          // Bypass queue element buffer size in bytes
  output wire [15:0]                         o_bypass_buf_wrptr,          // Bypass packet queue current write index

  input  wire                                i_req_err_buf_en,            // Enables writes to error buffer in all cases
  input  wire                                i_req_err_buf_ovr_wr_en,     // Enables the error buffer overwriting
  input  wire [C_M_AXI_ADDR_WIDTH-1:0]       i_req_err_pkt_buf_ba,        // Error logging queue base address
  input  wire [15:0]                         i_req_err_num_bufs,          // Error logging queue depth
  input  wire [15:0]                         i_req_err_buffer_sz,         // Error logging queue element buffer size in bytes
  input  wire                                i_rsp_err_buf_en,            // Enables writes to error buffer in all cases
  input  wire                                i_rsp_err_buf_ovr_wr_en,     // Enables the error buffer overwriting
  input  wire [C_M_AXI_ADDR_WIDTH-1:0]       i_rsp_err_pkt_buf_ba,        // Error logging queue base address
  input  wire [15:0]                         i_rsp_err_num_bufs,          // Error logging queue depth
  input  wire [15:0]                         i_rsp_err_buffer_sz,         // Error logging queue element buffer size in bytes
  input  wire [C_M_AXI_ADDR_WIDTH-1:0]       i_in_errsts_q_ba,
  input  wire [15:0]                         i_in_errsts_q_sz,
  output wire [15:0]                         o_in_errsts_q_wrptr,

  output wire [15:0]                         o_inc_send_cnt,              // Incoming send request packets count
  output wire [15:0]                         o_inc_acknak_cnt,            // Incoming acknowledgement packets count
  output wire [15:0]                         o_inc_rresp_cnt,             // Incoming read response packets count
  output wire [15:0]                         o_inc_mad_cnt,               // Incoming QP1 packet count
  output reg  [15:0]                         o_inc_inv_pkt_cnt,           // Incoming invalid packet count
  output wire [15:0]                         o_inc_dup_pkt_cnt,           // Incoming duplicate packet count
  output wire [15:0]                         o_inc_nack_pkt_cnt,          // Incoming NAK packet count
  output wire [15:0]                         o_out_nack_pkt_cnt,          // Outgoing NAK packet count
  output wire [31:0]                         pkt_all_cnt,                 // all packet count
  output wire [31:0]                         pkt_disc_cnt,                // discarded packet count

  output wire [ 7:0]                         o_last_in_req_pkt_opcode,
  output wire [ 7:0]                         o_last_in_req_pkt_qpid,
  output wire [15:0]                         o_last_in_req_pkt_psn,

  output wire [ 7:0]                         o_last_in_rsp_pkt_opcode,
  output wire [ 7:0]                         o_last_in_rsp_pkt_qpid,
  output wire [15:0]                         o_last_in_rsp_pkt_psn,

  output wire [ 7:0]                         o_last_in_pkt_opcode,
  output wire [ 7:0]                         o_last_in_pkt_qpid,
  output wire [15:0]                         o_last_in_pkt_psn,

  output wire [C_NUM_QP-1:0]                 o_rq_full,                   // Receive request packet queue full
  output wire [C_NUM_QP-1:0]                 o_qp_fatal,                  // QPs those are stalled due to fatal error
  input  wire [C_NUM_QP-1:0]                 i_clr_qp_fatal,              // removes stall condition on QPs

  input  wire [15:0]                         i_rq_pi_db_hw_hndshk,          // RQ PI Door Bell
  input  wire [ 9:0]                         i_connect_io_qp_rq_pi_db_wptr, // Connect IO QP DB address
  input  wire                                i_hw_hndshk_disable_to_0,      // pulse indicates HWHNDSHK_DIS set 0
  output wire                                o_connect_io_qp_rq_pi_db_rdy,  // Ready indicates can accept another

  // Side-band RQ DB interface
  output wire [31:0]                         o_rq_db_data,
  output wire [ 9:0]                         o_rq_db_addr,
  output wire                                o_rq_db_data_valid,
  input  wire                                i_rq_db_data_ack,

  // Interrupt controller interface
  input  wire                                i_pkt_valdn_err_intr_en,     // Enable for Inbound packet header validation interrupt
  output wire                                o_pkt_valdn_err_intr,        // Inbound packet header validation error interrupt
  output wire                                o_pkt_valdn_err_intr_sts,    // Inbound packet header validation error interrupt status flag
  input  wire                                i_clr_pkt_valdn_err_intr,    // Clear Inbound packet header validation error interrupt

  input  wire                                i_mad_pkt_rcvd_intr_en,      // Enable to MAD packet received interrupt
  output wire                                o_mad_pkt_rcvd_intr,         // MAD packet received interrupt
  output wire                                o_mad_pkt_rcvd_intr_sts,     // MAD packet received interrupt status flag
  input  wire                                i_clr_mad_pkt_rcvd_intr,     // Clear MAD packet received interrupt

  input  wire                                i_bypass_pkt_rcvd_intr_en,   // Enable to bypass packet received interrupt
  output wire                                o_bypass_pkt_rcvd_intr,      // Incoming bypass packet received interrupt
  output wire                                o_bypass_pkt_rcvd_intr_sts,  // Incoming bypass packet received interrupt status flag
  input  wire                                i_clr_bypass_pkt_rcvd_intr,  // Clear Incoming bypass packet received interrupt

  input  wire                                i_rnr_nack_gen_intr_en,
  output wire                                o_rnr_nack_gen_intr,
  output wire                                o_rnr_nack_gen_intr_sts,
  input  wire                                i_clr_rnr_nack_gen_intr,

  input  wire                                i_fatal_err_intr_en,
  output wire                                o_fatal_err_intr,
  output wire                                o_fatal_err_intr_sts,
  input  wire                                i_clr_fatal_err_intr,

  input  wire                                i_qp_pkt_rcvd_intr_en,       // Interrupt enable for qp_pkt_rcvd_intr
  output wire                                o_qp_pkt_rcvd_intr,          // Interrupt to assert when admin qp packet received
  output wire [C_NUM_QP-1:0]                 o_qp_pkt_rcvd_intr_sts,      // qp_pkt_rcvd_intr interrupt status bit
  input  wire [C_NUM_QP-1:0]                 i_clr_qp_pkt_rcvd_intr,      // Clear for qp_pkt_rcvd_intr

  // Response Handler interface
  output wire [C_QP_INDX_WIDTH-1:0]          o_qp_index_mpsnbuf,          // Max PSN queue (QP) index

  output wire                                o_max_epsn_req,
  input  wire                                i_max_epsn_vld,

  input  wire [C_NUM_QP-1:0]                 i_mpsnbuf_empty,             // Max PSN queue empty
  input  wire [C_NUM_QP-1:0]                 i_qp_retried,
  output wire                                o_mpsnbuf_pop,               // Pop first element of Max PSN queue

  input  wire [C_OSQ_PSN_WIDTH-1:0]          i_os_rdma_rd_resp_psn_7_0,   // PSN of expecting RDMA Read response
  input  wire [C_M_AXI_ADDR_WIDTH-1:0]       i_os_rdma_rd_resp_dest_addr, // Destination address of expected RDMA Read response
  input  wire [31:0]                         i_os_rdma_rd_resp_length,    // Length of expected RDMA read response

  output wire [C_QP_INDX_WIDTH-1:0]          o_qp_index_acknack,          // QP Id for which ACKNOWLEDGE received
  output wire                                o_acknack_valid,             // valid pulse for this group of signals
  output wire [23:0]                         o_acknacked_psn,             // BTH.PSN in ACKNOWLEDGE (one minus for read-first/middle)
  output wire [ 7:0]                         o_acknacked_syndrome,        // AETH.Syndrome in ACKNOWLEDGE
  output wire [23:0]                         o_acknacked_msn,             // AETH.MSN in ACKNOWLEDGE
  output wire [ 1:0]                         o_acknacked_opcode,          // 01:read-first/10:read-middle/11:read-last/only/00-acknowledge
  output wire [31:0]                         o_qp_timeout_per_qp,

  input  wire [C_NUM_QP -1: 0]               i_osq_empty,
  input  wire [C_NUM_QP -1: 0]               i_osq_nacked,

  output wire                                o_rd_rsp_wr_cmpltd,
  output wire [C_QP_INDX_WIDTH-1:0]          o_rsp_qp_id,

  output wire [C_QP_INDX_WIDTH-1:0]          o_ob_rsp_qpid,               // Destination QP ID for which response packet is targetted
  output wire [23:0]                         o_ob_rsp_psn,                // BTH.PSN to embed in response packet
  output wire [7:0]                          o_ob_rsp_aeth_syndrome,      // AETH.Syndrome to embed in response packet
  output wire [23:0]                         o_ob_rsp_aeth_msn,           // AETH.MSN to embed in response packet
  output wire                                o_ob_rsp_expl_ack,
  output wire                                o_ob_rsp_vld,                // Indicates the response signals are valid
  input  wire                                ob_rsp_fifo_full,            // Indicates the response FIFO is full

  output wire [C_QP_INDX_WIDTH-1:0]          o_qp_req_conf_idx,

  input  wire [31:0]                         i_qp_req_conf,
  input  wire                                qp_req_conf_vld,
  output wire                                qp_req_conf_en,

  input  wire [C_M_AXI_ADDR_WIDTH-9:0]       i_rq_buf_ba,
  output wire                                rq_buf_ba_en,

  input  wire [C_M_AXI_ADDR_WIDTH-9:0]       i_rq_buf_ca,
  output wire [C_M_AXI_ADDR_WIDTH-9:0]       o_rq_buf_ca,
  output wire                                rq_buf_ca_en,
  output wire                                rq_buf_ca_we,

  input  wire [C_M_AXI_ADDR_WIDTH-1:0]       i_rq_wrptr_db_addr,
  output wire                                rq_wrptr_db_addr_en,

  input  wire [15:0]                         i_q_depth,
  output wire                                q_depth_en,

  input  wire [15:0]                         i_rq_ci_db,
  output wire                                rq_ci_db_en,

  input  wire [31:0]                         i_last_rq_req,
  output wire [31:0]                         o_last_rq_req,
  output wire                                last_rq_req_en,
  output wire                                last_rq_req_we,

  input  wire [23:0]                         i_stat_qp_msn,
  output wire [23:0]                         o_stat_qp_msn,
  output wire                                stat_qp_msn_en,
  output wire                                stat_qp_msn_we,

  input  wire [47:0]                         i_qp_req_remote_qp_mac_addr,
  output wire                                qp_req_remote_qp_mac_addr_en,

  input  wire [31:0]                         i_qp_req_remote_qp_ip_addr,
  output wire                                qp_req_remote_qp_ip_addr_en,

  input  wire [15:0]                         i_rq_wrptr_db,
  output wire [15:0]                         o_rq_wrptr_db,
  output wire                                rq_wrptr_db_en,
  output wire                                rq_wrptr_db_we,

  output wire [C_QP_INDX_WIDTH-1:0]          o_qp_rsp_conf_idx,

  input  wire [31:0]                         i_qp_rsp_conf,
  input  wire                                qp_rsp_conf_vld,
  output wire                                qp_rsp_conf_en,

  input  wire [ 9:0]                         i_stat_nak,
  output wire                                stat_nak_en,
  output wire                                stat_nak_we,
  output wire [ 9:0]                         o_stat_nak,

  input  wire [23:0]                         i_stat_resp_psn,
  output wire                                stat_resp_psn_en,
  output wire                                stat_resp_psn_we,
  output wire [23:0]                         o_stat_resp_psn,

  input  wire [23:0]                         i_sq_psn,
  output wire                                sq_psn_en,

  input  wire [47:0]                         i_qp_rsp_remote_qp_mac_addr,
  output wire                                qp_rsp_remote_qp_mac_addr_en,

  input  wire [31:0]                         i_qp_rsp_remote_qp_ip_addr,
  output wire                                qp_rsp_remote_qp_ip_addr_en,

  input wire  [31:0]                         i_qp_timeout,

  // Debug signals
  input  wire [31:0]                         debug_ctrl_in,
  output reg  [31:0]                         debug_sts_out,

  input  wire                                i_global_dbg_cnt_en,
  input  wire                                i_global_dbg_cnt_clr
);

  localparam C_REQ_BUF_ADDR_WIDTH =  9;   // 32 KBytes, approx. 256 SEND packets
  localparam C_RSP_BUF_ADDR_WIDTH = 10;   // 64 KBytes
  localparam C_HDR_BUF_ADDR_WIDTH =  9;   // 32 KBytes, 256 packets
  localparam PKT_DESC_FIFO_DATA_WIDTH = C_SIM_DEBUG ? (C_RSP_BUF_ADDR_WIDTH+48) : (C_RSP_BUF_ADDR_WIDTH+16);
  localparam REQ_BUF_MEM_SZ_IN_BITS = (2**C_REQ_BUF_ADDR_WIDTH)*512;
  localparam RSP_BUF_MEM_SZ_IN_BITS = (2**C_RSP_BUF_ADDR_WIDTH)*512;
  localparam HDR_BUF_MEM_SZ_IN_BITS = (2**C_HDR_BUF_ADDR_WIDTH)*512;

  wire core_rst;

  wire incr_inv_req_pkt_cnt;
  wire incr_inv_rsp_pkt_cnt;

  wire [C_QP_INDX_WIDTH-1:0] qp_req_fatal_idx;
  wire set_qp_req_fatal;
  wire [C_QP_INDX_WIDTH-1:0] qp_rsp_fatal_idx;
  wire set_qp_rsp_fatal;

  wire [C_NUM_QP-1:0] qp_req_fatal_bitmap;
  wire [C_NUM_QP-1:0] qp_rsp_fatal_bitmap;

  reg [C_NUM_QP-1:0] qp_fatal;

  wire [15:0] rq_db_data;
  wire [ 9:0] rq_db_addr;
  wire rq_db_data_valid;


  wire set_req_pkt_valdn_err_intr;
  wire set_rsp_pkt_valdn_err_intr;
  wire set_pkt_valdn_err_intr;
  wire set_mad_pkt_rcvd_intr;
  wire set_bypass_pkt_rcvd_intr;
  wire set_rnr_nack_gen_intr;
  wire set_fatal_err_intr;
  wire [C_QP_INDX_WIDTH-1:0] pkt_rcvd_qpid_1;
  wire set_qp_pkt_rcvd_intr_1;
  wire [C_QP_INDX_WIDTH-1:0] pkt_rcvd_qpid_2;
  wire set_qp_pkt_rcvd_intr_2;

  wire [31:0] req_pkt_id;
  wire [ 2:0] req_pkt_type;
  wire [C_M_AXI_ADDR_WIDTH-1:0] req_dest_addr;
  wire [C_REQ_BUF_ADDR_WIDTH-1:0] req_buf_addr_offset;
  wire [12:0] req_pkt_len;
  wire [39:0] req_imm_data;
  wire req_tnfr_vld;
  wire rdy_to_req_tnfr;


  wire [31:0] o_rsp_pkt_id;
  wire [ 2:0] o_rsp_pkt_type;
  wire [C_M_AXI_ADDR_WIDTH-1:0] o_rsp_dest_addr;
  wire [C_RSP_BUF_ADDR_WIDTH-1:0] o_rsp_buf_addr_offset;
  wire [12:0] o_rsp_pkt_len;
  wire [31:0] o_rsp_imm_data;
  wire o_rsp_tnfr_vld;
  wire i_rdy_to_rsp_tnfr;

  wire req_err_tnfr_vld;
  wire rdy_to_req_err_tnfr;

  wire [31:0] rsp_pkt_id;
  wire [ 2:0] rsp_pkt_type;
  wire [C_M_AXI_ADDR_WIDTH-1:0] rsp_dest_addr;
  wire [C_RSP_BUF_ADDR_WIDTH-1:0] rsp_buf_addr_offset;
  wire [12:0] rsp_pkt_len;
  wire [31:0] rsp_imm_data;
  wire rsp_tnfr_vld;
  wire rdy_to_rsp_tnfr;

  wire [C_REQ_BUF_ADDR_WIDTH-1:0] req_pkt_buf_addra;
  wire req_pkt_buf_ena;
  wire [63:0] req_pkt_buf_wea;
  wire [511:0] req_pkt_buf_dina;
  wire [C_REQ_BUF_ADDR_WIDTH-1:0] req_pkt_buf_addrb;
  wire req_pkt_buf_enb;

  wire [C_HDR_BUF_ADDR_WIDTH-1:0] req_hdr_buf_addra;
  wire req_hdr_buf_ena;
  wire [63:0] req_hdr_buf_wea;
  wire [511:0] req_hdr_buf_dina;
  wire [C_HDR_BUF_ADDR_WIDTH-1:0] req_hdr_buf_addrb;
  wire req_hdr_buf_enb;

  wire [C_RSP_BUF_ADDR_WIDTH-1:0] rsp_pkt_buf_addra;
  wire rsp_pkt_buf_ena;
  wire [63:0] rsp_pkt_buf_wea;
  wire [511:0] rsp_pkt_buf_dina;
  wire [C_RSP_BUF_ADDR_WIDTH-1:0] rsp_pkt_buf_addrb;
  wire rsp_pkt_buf_enb;
  wire [511:0] rsp_pkt_buf_doutb;

  wire [C_HDR_BUF_ADDR_WIDTH-1:0] rsp_hdr_buf_addra;
  wire rsp_hdr_buf_ena;
  wire [63:0] rsp_hdr_buf_wea;
  wire [511:0] rsp_hdr_buf_dina;
  wire [C_HDR_BUF_ADDR_WIDTH-1:0] rsp_hdr_buf_addrb;
  wire rsp_hdr_buf_enb;
  wire [511:0] rsp_hdr_buf_doutb;

  wire [PKT_DESC_FIFO_DATA_WIDTH-1:0] req_pkt_desc_fifo_dout;
  wire req_pkt_desc_fifo_empty;
  wire rd_req_pkt_desc_fifo;

  wire [PKT_DESC_FIFO_DATA_WIDTH-1:0] rsp_pkt_desc_fifo_dout;
  wire rsp_pkt_desc_fifo_empty;
  wire rd_rsp_pkt_desc_fifo;

  wire [C_REQ_BUF_ADDR_WIDTH:0] req_pkt_buf_sz;
  wire [C_RSP_BUF_ADDR_WIDTH:0] rsp_pkt_buf_sz;

  reg req_pkt_buf_almost_full;
  reg rsp_pkt_buf_almost_full;

  reg [5:0] rdma_en_reg;
  wire rdma_en_pulse;

  reg [31:0] free_run_cnt;

  wire pkt_discarded;

  reg pkt_valdn_err_sticky;

  wire [31:0] debug_sts_reg [0:12];

  wire [15:0]  o_rx_rsp_axi_wvalid_cnt;
  wire [15:0]  o_rx_rsp_axi_wchnl_wait_st_cnt;

  // Other miscellanous logic & internal signals
  assign core_rst = ~core_rst_n;

  wire clr_debug_sts = debug_ctrl_in[31];

  always @(posedge core_clk)
    if (core_rst)
      o_inc_inv_pkt_cnt <= 16'd0;
    else
      o_inc_inv_pkt_cnt <= o_inc_inv_pkt_cnt + incr_inv_req_pkt_cnt + incr_inv_rsp_pkt_cnt;

  assign qp_req_fatal_bitmap = {{(C_NUM_QP-1){1'b0}}, set_qp_req_fatal} << qp_req_fatal_idx;
  assign qp_rsp_fatal_bitmap = {{(C_NUM_QP-1){1'b0}}, set_qp_rsp_fatal} << qp_rsp_fatal_idx;

  always @(posedge core_clk)
    if (core_rst)
      qp_fatal <= {(C_NUM_QP){1'b0}};
    else if (|{i_clr_qp_fatal, set_qp_req_fatal, set_qp_rsp_fatal})
      qp_fatal <= (qp_fatal & ~i_clr_qp_fatal) | qp_req_fatal_bitmap | qp_rsp_fatal_bitmap;

  assign o_qp_fatal = qp_fatal;

  assign o_rq_db_data[31:16] = 16'd0;

  assign set_pkt_valdn_err_intr = set_req_pkt_valdn_err_intr | set_rsp_pkt_valdn_err_intr;

  assign req_pkt_buf_sz = {1'b1, {(C_REQ_BUF_ADDR_WIDTH){1'b0}}};
  assign rsp_pkt_buf_sz = {1'b1, {(C_RSP_BUF_ADDR_WIDTH){1'b0}}};

  always @(posedge core_clk)
    if (core_rst)
      req_pkt_buf_almost_full <= 1'b0;
    else if (req_pkt_buf_addra >= req_pkt_buf_addrb)
    begin
      if ((req_pkt_buf_sz-req_pkt_buf_addra+req_pkt_buf_addrb) < 'd70)
        req_pkt_buf_almost_full <= 1'b1;
      else
        req_pkt_buf_almost_full <= 1'b0;
    end
    else if (req_pkt_buf_addrb-req_pkt_buf_addra < 'd70)
      req_pkt_buf_almost_full <= 1'b1;
    else
      req_pkt_buf_almost_full <= 1'b0;

  always @(posedge core_clk)
    if (core_rst)
      rsp_pkt_buf_almost_full <= 1'b0;
    else if (rsp_pkt_buf_addra >= rsp_pkt_buf_addrb)
    begin
      if ((rsp_pkt_buf_sz-rsp_pkt_buf_addra+rsp_pkt_buf_addrb) < 'd70)
        rsp_pkt_buf_almost_full <= 1'b1;
      else
        rsp_pkt_buf_almost_full <= 1'b0;
    end
    else if (rsp_pkt_buf_addrb-rsp_pkt_buf_addra < 'd70)
      rsp_pkt_buf_almost_full <= 1'b1;
    else
      rsp_pkt_buf_almost_full <= 1'b0;

  always @(posedge core_clk)
    if (core_rst)
      rdma_en_reg <= {6{1'b0}};
    else
      rdma_en_reg <= {rdma_en_reg[5:0], i_rdma_en};

  assign rdma_en_pulse = ~rdma_en_reg[5] & rdma_en_reg[1];

  always @(posedge core_clk)
    if (core_rst)
      free_run_cnt <= 32'd0;
    else
      free_run_cnt <= free_run_cnt + 'd1;

  cmac_rx_intf #(
    .C_SIM_DEBUG (C_SIM_DEBUG),
    .PKT_DESC_FIFO_DATA_WIDTH (PKT_DESC_FIFO_DATA_WIDTH),
    .C_REQ_BUF_ADDR_WIDTH (C_REQ_BUF_ADDR_WIDTH),
    .C_RSP_BUF_ADDR_WIDTH (C_RSP_BUF_ADDR_WIDTH),
    .C_HDR_BUF_ADDR_WIDTH (C_HDR_BUF_ADDR_WIDTH)
  ) u_cmac_rx_intf (
    .clk                     (core_clk),
    .reset                   (core_rst),
    .s_axis_tvalid           (s_axis_tvalid),
    .s_axis_tdata            (s_axis_tdata),
    .s_axis_tkeep            (s_axis_tkeep),
    .s_axis_tlast            (s_axis_tlast),
    .s_axis_tuser            (s_axis_tuser),
    .rdma_en                (i_rdma_en),
    .bypass_en               (i_depkt_bypass_en),
    .o_inc_all_pkt_cnt       (pkt_all_cnt),
    .o_inc_drop_pkt_cnt      (pkt_disc_cnt),
    .o_last_in_pkt_opcode    (o_last_in_pkt_opcode),
    .o_last_in_pkt_qpid      (o_last_in_pkt_qpid),
    .o_last_in_pkt_psn       (o_last_in_pkt_psn),
    .req_pkt_buf_almost_full (req_pkt_buf_almost_full),
    .rsp_pkt_buf_almost_full (rsp_pkt_buf_almost_full),
    .pkt_discarded_to_req_hv (pkt_discarded),
    .req_pkt_desc_fifo_dout  (req_pkt_desc_fifo_dout),
    .rd_req_pkt_desc_fifo    (rd_req_pkt_desc_fifo),
    .rsp_pkt_desc_fifo_dout  (rsp_pkt_desc_fifo_dout),
    .rd_rsp_pkt_desc_fifo    (rd_rsp_pkt_desc_fifo),
    .req_pkt_buf_addra       (req_pkt_buf_addra),
    .req_pkt_buf_ena         (req_pkt_buf_ena),
    .req_pkt_buf_wea         (req_pkt_buf_wea),
    .req_pkt_buf_dina        (req_pkt_buf_dina),
    .req_hdr_buf_addra       (req_hdr_buf_addra),
    .req_hdr_buf_ena         (req_hdr_buf_ena),
    .req_hdr_buf_wea         (req_hdr_buf_wea),
    .req_hdr_buf_dina        (req_hdr_buf_dina),
    .rsp_pkt_buf_addra       (rsp_pkt_buf_addra),
    .rsp_pkt_buf_ena         (rsp_pkt_buf_ena),
    .rsp_pkt_buf_wea         (rsp_pkt_buf_wea),
    .rsp_pkt_buf_dina        (rsp_pkt_buf_dina),
    .rsp_hdr_buf_addra       (rsp_hdr_buf_addra),
    .rsp_hdr_buf_ena         (rsp_hdr_buf_ena),
    .rsp_hdr_buf_wea         (rsp_hdr_buf_wea),
    .rsp_hdr_buf_dina        (rsp_hdr_buf_dina),
    .i_clr_debug_sts                  (clr_debug_sts),
    .pkt_dropped_sticky               (debug_sts_reg[0][0]),
    .req_pkt_buf_almost_full_sticky   (debug_sts_reg[0][1]),
    .rsp_pkt_buf_almost_full_sticky   (debug_sts_reg[0][2]),
    .pkt_desc_fifo_1_unoccupied_r     (debug_sts_reg[1][15:0]),
    .pkt_desc_fifo_1_full_sticky      (debug_sts_reg[0][3]),
    .req_pkt_desc_fifo_unoccupied_r   (debug_sts_reg[2][15:0]),
    .req_pkt_desc_fifo_full_sticky    (debug_sts_reg[0][4]),
    .rsp_pkt_desc_fifo_unoccupied_r   (debug_sts_reg[2][31:16]),
    .rsp_pkt_desc_fifo_full_sticky    (debug_sts_reg[0][5]),
    .pkt_desc_fifo_3_empty            (debug_sts_reg[0][16]),
    .req_pkt_desc_fifo_empty          (req_pkt_desc_fifo_empty),
    .rsp_pkt_desc_fifo_empty          (rsp_pkt_desc_fifo_empty),
    .pkt_fcs_err_sticky      (debug_sts_reg[0][29]),
    .pkt_crc_err_sticky      (debug_sts_reg[0][28])
  );

  assign debug_sts_reg[0][17] = req_pkt_desc_fifo_empty;
  assign debug_sts_reg[0][18] = rsp_pkt_desc_fifo_empty;


  // [Removed: xpm_req_pkt_buf]

  // [Removed: xpm_req_hdr_buf]
  xpm_memory_sdpram # (  // Common module parameters
    .MEMORY_SIZE        (RSP_BUF_MEM_SZ_IN_BITS), //positive integer
    .MEMORY_PRIMITIVE   ("auto"),                 //string; "auto", "distributed", "block" or "ultra";
    .CLOCKING_MODE      ("common_clock"),         //string; "common_clock", "independent_clock"
    .ECC_MODE           ("no_ecc"),               //do not change
    .MEMORY_INIT_FILE   ("none"),                 //string; "none" or "<filename>.mem"
    .MEMORY_INIT_PARAM  (""    ),                 //string;
    .WAKEUP_TIME        ("disable_sleep"),        //string; "disable_sleep" or "use_sleep_pin"
    .MESSAGE_CONTROL    (0),

    // Port A module parameters
    .WRITE_DATA_WIDTH_A (512),                    //positive integer
    .BYTE_WRITE_WIDTH_A (8),                      //integer; 8, 9, or WRITE_DATA_WIDTH_A value
    .ADDR_WIDTH_A       (C_RSP_BUF_ADDR_WIDTH),   //positive integer

    // Port B module parameters
    .READ_DATA_WIDTH_B  (512),                    //positive integer
    .ADDR_WIDTH_B       (C_RSP_BUF_ADDR_WIDTH),   //positive integer
    .READ_RESET_VALUE_B ("0"),                    //string
    .READ_LATENCY_B     (1),                      //non-negative integer
    .WRITE_MODE_B       ("read_first")            //string; "write_first", "read_first", "no_change"
  ) xpm_rsp_pkt_buf (
    // Common module ports
    .sleep          (1'b0),  //do not change

    // Port A module ports
    .clka           (core_clk),
    .ena            (rsp_pkt_buf_ena),
    .wea            (rsp_pkt_buf_wea),
    .addra          (rsp_pkt_buf_addra),
    .dina           (rsp_pkt_buf_dina),
    .injectsbiterra (1'b0),  //do not change
    .injectdbiterra (1'b0),  //do not change

    // Port B module ports
    .clkb           (core_clk),
    .rstb           (1'b0),
    .enb            (rsp_pkt_buf_enb),
    .regceb         (1'b1),
    .addrb          (rsp_pkt_buf_addrb),
    .doutb          (rsp_pkt_buf_doutb),
    .sbiterrb       (),      //do not change
    .dbiterrb       ()       //do not change
  );

  xpm_memory_sdpram # (
    // Common module parameters
    .MEMORY_SIZE        (HDR_BUF_MEM_SZ_IN_BITS), //positive integer
    .MEMORY_PRIMITIVE   ("auto"),                 //string; "auto", "distributed", "block" or "ultra";
    .CLOCKING_MODE      ("common_clock"),         //string; "common_clock", "independent_clock"
    .ECC_MODE           ("no_ecc"),               //do not change
    .MEMORY_INIT_FILE   ("none"),                 //string; "none" or "<filename>.mem"
    .MEMORY_INIT_PARAM  (""    ),                 //string;
    .WAKEUP_TIME        ("disable_sleep"),        //string; "disable_sleep" or "use_sleep_pin"
    .MESSAGE_CONTROL    (0),

    // Port A module parameters
    .WRITE_DATA_WIDTH_A (512),                    //positive integer
    .BYTE_WRITE_WIDTH_A (512),                    //integer; 8, 9, or WRITE_DATA_WIDTH_A value
    .ADDR_WIDTH_A       (C_HDR_BUF_ADDR_WIDTH),   //positive integer

    // Port B module parameters
    .READ_DATA_WIDTH_B  (512),                    //positive integer
    .ADDR_WIDTH_B       (C_HDR_BUF_ADDR_WIDTH),   //positive integer
    .READ_RESET_VALUE_B ("0"),                    //string
    .READ_LATENCY_B     (1),                      //non-negative integer
    .WRITE_MODE_B       ("read_first")            //string; "write_first", "read_first", "no_change"

  ) xpm_rsp_hdr_buf (
    // Common module ports
    .sleep          (1'b0),  //do not change

    // Port A module ports
    .clka           (core_clk),
    .ena            (rsp_hdr_buf_ena),
    .wea            (rsp_hdr_buf_wea[0]),
    .addra          (rsp_hdr_buf_addra),
    .dina           (rsp_hdr_buf_dina),
    .injectsbiterra (1'b0),  //do not change
    .injectdbiterra (1'b0),  //do not change

    // Port B module ports
    .clkb           (core_clk),
    .rstb           (1'b0),
    .enb            (rsp_hdr_buf_enb),
    .regceb         (1'b1),
    .addrb          (rsp_hdr_buf_addrb),
    .doutb          (rsp_hdr_buf_doutb),
    .sbiterrb       (),      //do not change
    .dbiterrb       ()       //do not change
  );


  // [Removed: rx_req_hdr_val]

  // [Removed: u_reg_pipe_1]

  // [Removed: rx_req_axi_mstr]
  rx_rsp_hdr_val #(
    .C_SIM_DEBUG (C_SIM_DEBUG),
    .C_M_AXI_ADDR_WIDTH (C_M_AXI_ADDR_WIDTH),
    .C_QP_INDX_WIDTH (C_QP_INDX_WIDTH),
    .C_NUM_QP (C_NUM_QP),
    .PKT_DESC_FIFO_DATA_WIDTH (PKT_DESC_FIFO_DATA_WIDTH),
    .C_HDR_BUF_ADDR_WIDTH (C_HDR_BUF_ADDR_WIDTH),
    .C_RSP_BUF_ADDR_WIDTH (C_RSP_BUF_ADDR_WIDTH),
    .C_OSQ_PSN_WIDTH (C_OSQ_PSN_WIDTH)
  ) u_rx_rsp_hdr_val (
    .clk                     (core_clk),
    .reset                   (core_rst),
    .rsp_pkt_desc_fifo_dout  (rsp_pkt_desc_fifo_dout),
    .rsp_pkt_desc_fifo_empty (rsp_pkt_desc_fifo_empty),
    .rd_rsp_pkt_desc_fifo    (rd_rsp_pkt_desc_fifo),
    .rsp_hdr_buf_addrb       (rsp_hdr_buf_addrb),
    .rsp_hdr_buf_enb         (rsp_hdr_buf_enb),
    .rsp_hdr_buf_doutb       (rsp_hdr_buf_doutb),
    .i_err_buf_en            (i_rsp_err_buf_en),
    .i_mac_node_addr         (i_mac_node_addr),
    .i_ipv4_node_addr        (i_ipv4_node_addr),
    .i_ipv6_node_addr        (i_ipv6_node_addr),
    .i_num_qp_enabled        (i_num_qp_enabled),
    .i_rnr_nak_rst_val       (i_rnr_nak_rst_val),
    .o_acknack_pkt_cnt       (o_inc_acknak_cnt),
    .o_inc_nack_pkt_cnt      (o_inc_nack_pkt_cnt),
    .o_last_in_rsp_pkt_opcode (o_last_in_rsp_pkt_opcode),
    .o_last_in_rsp_pkt_qpid  (o_last_in_rsp_pkt_qpid),
    .o_last_in_rsp_pkt_psn   (o_last_in_rsp_pkt_psn),
    .o_qp_conf_idx           (o_qp_rsp_conf_idx),
    .i_qp_conf               (i_qp_rsp_conf),
    .qp_conf_vld             (qp_rsp_conf_vld),
    .qp_conf_en              (qp_rsp_conf_en),
    .i_stat_nak              (i_stat_nak),
    .stat_nak_en             (stat_nak_en),
    .stat_nak_we             (stat_nak_we),
    .o_stat_nak              (o_stat_nak),
    .i_stat_resp_psn         (i_stat_resp_psn),
    .stat_resp_psn_en        (stat_resp_psn_en),
    .stat_resp_psn_we        (stat_resp_psn_we),
    .o_stat_resp_psn         (o_stat_resp_psn),
    .i_sq_psn                (i_sq_psn),
    .sq_psn_en               (sq_psn_en),
    .i_remote_qp_mac_addr    (i_qp_rsp_remote_qp_mac_addr),
    .remote_qp_mac_addr_en   (qp_rsp_remote_qp_mac_addr_en),
    .i_remote_qp_ip_addr     (i_qp_rsp_remote_qp_ip_addr),
    .remote_qp_ip_addr_en    (qp_rsp_remote_qp_ip_addr_en),
    .i_qp_timeout            (i_qp_timeout),
    .i_qp_fatal              (qp_fatal),
    .o_qp_fatal_idx          (qp_rsp_fatal_idx),
    .set_qp_fatal            (set_qp_rsp_fatal),
    .o_qp_mpsnbuf_idx        (o_qp_index_mpsnbuf),
    .mpsnbuf_en              (o_max_epsn_req),
    .mpsnbuf_vld             (i_max_epsn_vld),
    .i_mpsnbuf_empty         (i_mpsnbuf_empty),
    .i_qp_retried            (i_qp_retried),
    .i_osq_empty             (i_osq_empty),
    .i_osq_nacked            (i_osq_nacked),
    .o_mpsnbuf_pop           (o_mpsnbuf_pop),
    .i_os_rd_req_psn_7_0     (i_os_rdma_rd_resp_psn_7_0),
    .i_os_rd_req_dest_addr   (i_os_rdma_rd_resp_dest_addr),
    .i_os_rd_req_resp_len    (i_os_rdma_rd_resp_length),
    .o_qp_acknack_idx        (o_qp_index_acknack),
    .o_acknack_vld           (o_acknack_valid),
    .o_acknack_psn           (o_acknacked_psn),
    .o_acknack_syndr         (o_acknacked_syndrome),
    .o_acknack_msn           (o_acknacked_msn),
    .o_acknack_opcode        (o_acknacked_opcode),
    .o_qp_timeout_per_qp     (o_qp_timeout_per_qp),
    .rsp_pkt_id              (rsp_pkt_id),
    .rsp_pkt_type            (rsp_pkt_type),
    .rsp_dest_addr           (rsp_dest_addr),
    .rsp_buf_addr_offset     (rsp_buf_addr_offset),
    .rsp_pkt_len             (rsp_pkt_len),
    .rsp_imm_data            (rsp_imm_data),
    .rsp_tnfr_vld            (rsp_tnfr_vld),
    .rdy_to_rsp_tnfr         (rdy_to_rsp_tnfr),
    .req_tnfr_vld            (req_err_tnfr_vld),
    .rdy_to_req_tnfr         (rdy_to_req_err_tnfr),
    .i_clr_debug_sts         (clr_debug_sts),
    .qp_fatal_rsp_hv_sticky  (debug_sts_reg[0][14]),
    .resp_drop_cnt           (debug_sts_reg[12])
  );

  reg_pipe #(.C_DATA_WIDTH(C_M_AXI_ADDR_WIDTH+C_RSP_BUF_ADDR_WIDTH+80))
    u_reg_pipe_2 (
    .clk      (core_clk),
    .reset    (core_rst),
    .din      ({rsp_pkt_id, rsp_pkt_type, rsp_dest_addr, rsp_buf_addr_offset, rsp_pkt_len, rsp_imm_data}),
    .vld_in   (rsp_tnfr_vld),
    .rdy_out  (rdy_to_rsp_tnfr),
    .dout     ({o_rsp_pkt_id, o_rsp_pkt_type, o_rsp_dest_addr, o_rsp_buf_addr_offset, o_rsp_pkt_len, o_rsp_imm_data}),
    .vld_out  (o_rsp_tnfr_vld),
    .rdy_in   (i_rdy_to_rsp_tnfr)
  );


  // [Removed: rx_rsp_axi_mstr]
  rx_pkt_intr_ctrl #(
  .C_NUM_QP             (C_NUM_QP          ),
  .C_QP_INDX_WIDTH      (C_QP_INDX_WIDTH   )
  ) u_rx_pkt_intr_ctrl (
    .clk                        (core_clk  ),
    .rst_n                      (core_rst_n),
    .rdma_enabled              (rdma_en_pulse),
    .pkt_valdn_err_intr_en      (i_pkt_valdn_err_intr_en),
    .pkt_valdn_err_intr         (o_pkt_valdn_err_intr),
    .pkt_valdn_err_intr_sts     (o_pkt_valdn_err_intr_sts),
    .clr_pkt_valdn_err_intr     (i_clr_pkt_valdn_err_intr),
    .mad_pkt_rcvd_intr_en       (i_mad_pkt_rcvd_intr_en),
    .mad_pkt_rcvd_intr          (o_mad_pkt_rcvd_intr),
    .mad_pkt_rcvd_intr_sts      (o_mad_pkt_rcvd_intr_sts),
    .clr_mad_pkt_rcvd_intr      (i_clr_mad_pkt_rcvd_intr),
    .bypass_pkt_rcvd_intr_en    (i_bypass_pkt_rcvd_intr_en),
    .bypass_pkt_rcvd_intr       (o_bypass_pkt_rcvd_intr),
    .bypass_pkt_rcvd_intr_sts   (o_bypass_pkt_rcvd_intr_sts),
    .clr_bypass_pkt_rcvd_intr   (i_clr_bypass_pkt_rcvd_intr),
    .rnr_nack_gen_intr_en       (i_rnr_nack_gen_intr_en),
    .rnr_nack_gen_intr          (o_rnr_nack_gen_intr),
    .rnr_nack_gen_intr_sts      (o_rnr_nack_gen_intr_sts),
    .clr_rnr_nack_gen_intr      (i_clr_rnr_nack_gen_intr),
    .fatal_err_intr_en          (i_fatal_err_intr_en),
    .fatal_err_intr             (o_fatal_err_intr),
    .fatal_err_intr_sts         (o_fatal_err_intr_sts),
    .clr_fatal_err_intr         (i_clr_fatal_err_intr),
    .qp_pkt_rcvd_intr_en        (i_qp_pkt_rcvd_intr_en),
    .qp_pkt_rcvd_intr           (o_qp_pkt_rcvd_intr),
    .qp_pkt_rcvd_intr_sts       (o_qp_pkt_rcvd_intr_sts),
    .clr_qp_pkt_rcvd_intr       (i_clr_qp_pkt_rcvd_intr),
    .set_pkt_valdn_err_intr     (set_pkt_valdn_err_intr),
    .set_mad_pkt_rcvd_intr      (set_mad_pkt_rcvd_intr),
    .set_bypass_pkt_rcvd_intr   (set_bypass_pkt_rcvd_intr),
    .set_rnr_nack_gen_intr      (set_rnr_nack_gen_intr),
    .set_fatal_err_intr         (set_fatal_err_intr),
    .pkt_rcvd_qpid_1            (pkt_rcvd_qpid_1),
    .set_qp_pkt_rcvd_intr_1     (set_qp_pkt_rcvd_intr_1),
    .pkt_rcvd_qpid_2            (pkt_rcvd_qpid_2),
    .set_qp_pkt_rcvd_intr_2     (set_qp_pkt_rcvd_intr_2)
  );

  // =====================================================================
  // Debug Logic
  // =====================================================================

  reg [15:0] req_pkt_buf_remain;
  reg [15:0] req_pkt_buf_unoccupied_min;
  reg [15:0] rsp_pkt_buf_remain;
  reg [15:0] rsp_pkt_buf_unoccupied_min;

  always @(posedge core_clk)
    if (core_rst)
    begin
      req_pkt_buf_remain <= {1'b1,{(C_REQ_BUF_ADDR_WIDTH){1'b0}}};
      req_pkt_buf_unoccupied_min <= {1'b1,{(C_REQ_BUF_ADDR_WIDTH){1'b0}}};
    end
    else if (clr_debug_sts)
    begin
      req_pkt_buf_remain <= {1'b1,{(C_REQ_BUF_ADDR_WIDTH){1'b0}}};
      req_pkt_buf_unoccupied_min <= {1'b1,{(C_REQ_BUF_ADDR_WIDTH){1'b0}}};
    end
    else
    begin
      if (req_pkt_buf_addra < req_pkt_buf_addrb)
        req_pkt_buf_remain <= {1'b1,{(C_REQ_BUF_ADDR_WIDTH){1'b0}}} - {1'b1, req_pkt_buf_addra} + req_pkt_buf_addrb;
      else
        req_pkt_buf_remain <= {1'b1,{(C_REQ_BUF_ADDR_WIDTH){1'b0}}} - req_pkt_buf_addra + req_pkt_buf_addrb;

      if (req_pkt_buf_unoccupied_min > req_pkt_buf_remain)
        req_pkt_buf_unoccupied_min <= req_pkt_buf_remain;
    end

  always @(posedge core_clk)
    if (core_rst)
    begin
      rsp_pkt_buf_remain <= {1'b1,{(C_RSP_BUF_ADDR_WIDTH){1'b0}}};
      rsp_pkt_buf_unoccupied_min <= {1'b1,{(C_RSP_BUF_ADDR_WIDTH){1'b0}}};
    end
    else if (clr_debug_sts)
    begin
      rsp_pkt_buf_remain <= {1'b1,{(C_RSP_BUF_ADDR_WIDTH){1'b0}}};
      rsp_pkt_buf_unoccupied_min <= {1'b1,{(C_RSP_BUF_ADDR_WIDTH){1'b0}}};
    end
    else
    begin
      if (rsp_pkt_buf_addra < rsp_pkt_buf_addrb)
        rsp_pkt_buf_remain <= {1'b1,{(C_RSP_BUF_ADDR_WIDTH){1'b0}}} - {1'b1, rsp_pkt_buf_addra} + rsp_pkt_buf_addrb;
      else
        rsp_pkt_buf_remain <= {1'b1,{(C_RSP_BUF_ADDR_WIDTH){1'b0}}} - rsp_pkt_buf_addra + rsp_pkt_buf_addrb;

      if (rsp_pkt_buf_unoccupied_min > rsp_pkt_buf_remain)
        rsp_pkt_buf_unoccupied_min <= rsp_pkt_buf_remain;
    end

  always @(posedge core_clk)
    if (core_rst)
    begin
      pkt_valdn_err_sticky <= 1'b0;
    end
    else if (clr_debug_sts)
      pkt_valdn_err_sticky <= 1'b0;
    else if (set_pkt_valdn_err_intr)
      pkt_valdn_err_sticky <= 1'b1;

  always @(*)
  begin
    case (debug_ctrl_in[3:0])
      4'd1    : debug_sts_out = debug_sts_reg[ 1];
      4'd2    : debug_sts_out = debug_sts_reg[ 2];
      4'd3    : debug_sts_out = debug_sts_reg[ 3];
      4'd4    : debug_sts_out = debug_sts_reg[ 4];
      4'd5    : debug_sts_out = debug_sts_reg[ 5];
      4'd6    : debug_sts_out = debug_sts_reg[ 6];
      4'd7    : debug_sts_out = debug_sts_reg[ 7];
      4'd8    : debug_sts_out = debug_sts_reg[ 8];
      4'd9    : debug_sts_out = debug_sts_reg[ 9];
      4'd10   : debug_sts_out = debug_sts_reg[10];
      4'd11   : debug_sts_out = debug_sts_reg[11];
      4'd12   : debug_sts_out = debug_sts_reg[12];
      4'd13   : debug_sts_out = pkt_disc_cnt;
      4'd14   : debug_sts_out = pkt_all_cnt;
      4'd15   : debug_sts_out = {o_rx_rsp_axi_wchnl_wait_st_cnt, o_rx_rsp_axi_wvalid_cnt};
      default : debug_sts_out = debug_sts_reg[ 0];
    endcase
  end

  assign debug_sts_reg[0][26] = 1'b0;
  assign debug_sts_reg[0][27] = 1'b0;
  assign debug_sts_reg[0][30] = pkt_valdn_err_sticky;
  assign debug_sts_reg[0][31] = 1'b0;
  assign debug_sts_reg[9][15:0] = req_pkt_buf_unoccupied_min;
  assign debug_sts_reg[9][31:16] = rsp_pkt_buf_unoccupied_min;

  assign o_rx_rsp_axi_wvalid_cnt = 16'd0;
  assign o_rx_rsp_axi_wchnl_wait_st_cnt = 16'd0;


  //-------------------------------------------------------
  // Assign unused outputs to 0 (RDMA Write-Only mode)
  //-------------------------------------------------------
  assign rd_req_pkt_desc_fifo = 1'b0;
  assign req_hdr_buf_addrb = 'd0;
  assign req_hdr_buf_enb = 1'b0;
  assign o_inc_dup_pkt_cnt = {16{1'b0}};
  assign o_out_nack_pkt_cnt = {16{1'b0}};
  assign o_last_in_req_pkt_opcode = {8{1'b0}};
  assign o_last_in_req_pkt_qpid = {8{1'b0}};
  assign o_last_in_req_pkt_psn = {16{1'b0}};
  assign o_rq_full = 'd0;
  assign o_qp_conf_idx = 'd0;
  assign qp_conf_en = 1'b0;
  assign rq_buf_ba_en = 1'b0;
  assign o_rq_buf_ca = 'd0;
  assign rq_buf_ca_en = 1'b0;
  assign rq_buf_ca_we = 1'b0;
  assign rq_wrptr_db_addr_en = 1'b0;
  assign q_depth_en = 1'b0;
  assign rq_ci_db_en = 1'b0;
  assign o_last_rq_req = {32{1'b0}};
  assign last_rq_req_en = 1'b0;
  assign last_rq_req_we = 1'b0;
  assign o_stat_qp_msn = {24{1'b0}};
  assign stat_qp_msn_en = 1'b0;
  assign stat_qp_msn_we = 1'b0;
  assign remote_qp_mac_addr_en = 1'b0;
  assign remote_qp_ip_addr_en = 1'b0;
  assign o_rq_wrptr_db = {16{1'b0}};
  assign rq_wrptr_db_en = 1'b0;
  assign rq_wrptr_db_we = 1'b0;
  assign o_qp_fatal_idx = 'd0;
  assign set_qp_fatal = 1'b0;
  assign set_rnr_nack_gen_intr = 1'b0;
  assign o_ob_rsp_qpid = 'd0;
  assign o_ob_rsp_psn = {24{1'b0}};
  assign o_ob_rsp_aeth_syndrome = {8{1'b0}};
  assign o_ob_rsp_aeth_msn = {24{1'b0}};
  assign o_ob_rsp_expl_ack = 1'b0;
  assign o_ob_rsp_vld = 1'b0;
  assign req_pkt_id = {32{1'b0}};
  assign req_pkt_type = {3{1'b0}};
  assign req_dest_addr = 'd0;
  assign req_buf_addr_offset = 'd0;
  assign req_pkt_len = {13{1'b0}};
  assign req_imm_data = {40{1'b0}};
  assign req_tnfr_vld = 1'b0;
  assign rq_buf_full_sticky = 1'b0;
  assign qp_fatal_req_hv_sticky = 1'b0;
  assign rq_buf_full_event_cnt = {32{1'b0}};
  assign rnr_window_cnt = {32{1'b0}};
  assign rdy_to_req_tnfr = 1'b0;
  assign rdy_to_rsp_tnfr = 1'b0;
  assign o_bypass_buf_ca = 'd0;
  assign o_bypass_buf_wrptr = {16{1'b0}};
  assign o_err_buf_ca = 'd0;
  assign o_err_buf_wrptr = {16{1'b0}};
  assign o_in_err_sts_q_ca = 'd0;
  assign o_in_err_sts_q_wrptr = {16{1'b0}};
  assign o_bypass_pkt_cnt = {16{1'b0}};
  assign incr_inv_pkt_cnt = 1'b0;
  assign o_mad_pkt_cnt = {16{1'b0}};
  assign o_send_req_cnt = {16{1'b0}};
  assign o_send_pkt_cnt = {16{1'b0}};
  assign set_bypass_pkt_rcvd_intr = 1'b0;
  assign set_pkt_valdn_err_intr = 1'b0;
  assign set_mad_pkt_rcvd_intr = 1'b0;
  assign set_qp_req_rcvd_intr_1 = 1'b0;
  assign intr_qp_indx_1 = 'd0;
  assign set_qp_req_rcvd_intr_2 = 1'b0;
  assign intr_qp_indx_2 = 'd0;
  assign set_qp_fatal_intr = 1'b0;
  assign req_pkt_buf_enb = 1'b0;
  assign req_pkt_buf_addrb = 'd0;
  assign rq_db_data_valid = 1'b0;
  assign rq_db_addr = {10{1'b0}};
  assign rq_db_data = {16{1'b0}};
  assign m_axi_awid = {1{1'b0}};
  assign m_axi_awaddr = 'd0;
  assign m_axi_awlen = {8{1'b0}};
  assign m_axi_awsize = {3{1'b0}};
  assign m_axi_awburst = {2{1'b0}};
  assign m_axi_awcache = {4{1'b0}};
  assign m_axi_awprot = {3{1'b0}};
  assign m_axi_awvalid = 1'b0;
  assign m_axi_wdata = {512{1'b0}};
  assign m_axi_wstrb = {64{1'b0}};
  assign m_axi_wlast = 1'b0;
  assign m_axi_wvalid = 1'b0;
  assign m_axi_awlock = 1'b0;
  assign m_axi_bready = 1'b0;
  assign m_axi_arid = {1{1'b0}};
  assign m_axi_araddr = {32{1'b0}};
  assign m_axi_arlen = {8{1'b0}};
  assign m_axi_arsize = {3{1'b0}};
  assign m_axi_arburst = {2{1'b0}};
  assign m_axi_arcache = {4{1'b0}};
  assign m_axi_arprot = {3{1'b0}};
  assign m_axi_arvalid = 1'b0;
  assign m_axi_rready = 1'b0;
  assign m_axi_arlock = 1'b0;
  assign o_connect_io_qp_rq_pi_db_rdy = 1'b0;
  assign axi_awchnl_fifo_unoccupied_r = {16{1'b0}};
  assign axi_awchnl_max_wait_st = {16{1'b0}};
  assign axi_wchnl_fifo_unoccupied_r = {16{1'b0}};
  assign axi_wchnl_max_wait_st = {16{1'b0}};
  assign post_axi_tnfr_fifo_unoccupied_r = {16{1'b0}};
  assign db_fifo_unoccupied_r = {16{1'b0}};
  assign axi_bresp_max_wait_st = {16{1'b0}};
  assign axi_awchnl_fifo_empty = 1'b0;
  assign axi_awchnl_fifo_full_sticky = 1'b0;
  assign axi_wchnl_fifo_empty = 1'b0;
  assign axi_wchnl_fifo_full_sticky = 1'b0;
  assign post_axi_tnfr_fifo_empty = 1'b0;
  assign post_axi_tnfr_fifo_full_sticky = 1'b0;
  assign db_fifo_empty = 1'b0;
  assign db_fifo_full_sticky = 1'b0;
  assign rdy_to_tnfr = 1'b0;
  assign o_err_buf_ca = 'd0;
  assign o_err_buf_wrptr = {16{1'b0}};
  assign o_rd_req_pkt_cnt = {16{1'b0}};
  assign o_rd_rsp_pkt_cnt = {16{1'b0}};
  assign incr_inv_pkt_cnt = 1'b0;
  assign set_pkt_valdn_err_intr = 1'b0;
  assign rsp_pkt_buf_enb = 1'b0;
  assign rsp_pkt_buf_addrb = 'd0;
  assign o_rd_rsp_wr_cmpltd = 1'b0;
  assign o_rsp_qp_id = 'd0;
  assign m_axi_awid = 'd0;
  assign m_axi_awaddr = 'd0;
  assign m_axi_awlen = {8{1'b0}};
  assign m_axi_awsize = {3{1'b0}};
  assign m_axi_awburst = {2{1'b0}};
  assign m_axi_awcache = {4{1'b0}};
  assign m_axi_awprot = {3{1'b0}};
  assign m_axi_awvalid = 1'b0;
  assign m_axi_wdata = {512{1'b0}};
  assign m_axi_wstrb = {64{1'b0}};
  assign m_axi_wlast = 1'b0;
  assign m_axi_wvalid = 1'b0;
  assign m_axi_awlock = 1'b0;
  assign m_axi_bready = 1'b0;
  assign m_axi_arid = 'd0;
  assign m_axi_araddr = {32{1'b0}};
  assign m_axi_arlen = {8{1'b0}};
  assign m_axi_arsize = {3{1'b0}};
  assign m_axi_arburst = {2{1'b0}};
  assign m_axi_arcache = {4{1'b0}};
  assign m_axi_arprot = {3{1'b0}};
  assign m_axi_arvalid = 1'b0;
  assign m_axi_rready = 1'b0;
  assign m_axi_arlock = 1'b0;
  assign axi_awchnl_fifo_unoccupied_r = {16{1'b0}};
  assign axi_awchnl_max_wait_st = {16{1'b0}};
  assign axi_wchnl_fifo_unoccupied_r = {16{1'b0}};
  assign axi_wchnl_max_wait_st = {16{1'b0}};
  assign axi_awchnl_fifo_empty = 1'b0;
  assign axi_awchnl_fifo_full_sticky = 1'b0;
  assign axi_wchnl_fifo_empty = 1'b0;
  assign axi_wchnl_fifo_full_sticky = 1'b0;
  assign post_axi_tnfr_fifo_unoccupied_r = {16{1'b0}};
  assign post_axi_tnfr_fifo_empty = 1'b0;
  assign post_axi_tnfr_fifo_full_sticky = 1'b0;
  assign axi_bresp_max_wait_st = {16{1'b0}};

endmodule

