// tb_rdma_core.v
// Top-level testbench for rdma_core
// Test cases:
//   SW doorbell x5: ring doorbell 5 times, verify TX packet emitted each time

`timescale 1 ps / 1 ps

module tb;

  parameter C_NUM_QP                   = 1;
  parameter C_M_AXI_ADDR_WIDTH         = 32;
  parameter C_M_AXI_ID_WIDTH           = 1;
  parameter C_S_AXI_LITE_ADDR_WIDTH    = 18;
  parameter C_EN_DEBUG_PORTS           = 0;
  parameter C_EN_NVMOF_HW_HNDSHK       = 0;
  parameter C_MAX_SGL_DEPTH            = 128;
  parameter C_MAX_WR_RETRY_DATA_BUF_DEPTH = 128;
  parameter C_EN_WR_RETRY_DATA_BUF     = 0;
  parameter C_OSQ_PSN_WIDTH            = 10;
  parameter CLK_PERIOD                 = 8000; // 125MHz = 8ns
  parameter NUM_SW_DB                  = 5;    // Number of SW doorbell iterations
  parameter NUM_HW_DB                  = 5;    // Number of HW handshake doorbell iterations

  // Clock & Reset
  reg m_axi_aclk;
  reg m_axi_aresetn;
  reg s_axi_lite_aclk;
  reg s_axi_lite_aresetn;
  wire clk = m_axi_aclk;

  // AXI-Stream RX
  reg         rx_pkt_hndler_s_axis_tvalid;
  reg  [511:0] rx_pkt_hndler_s_axis_tdata;
  reg  [63:0]  rx_pkt_hndler_s_axis_tkeep;
  reg          rx_pkt_hndler_s_axis_tlast;
  reg  [0:0]   rx_pkt_hndler_s_axis_tuser;

  // AXI-Stream TX
  wire [511:0] wqe_proc_top_m_axis_tdata;
  wire [63:0]  wqe_proc_top_m_axis_tkeep;
  wire         wqe_proc_top_m_axis_tvalid;
  wire         wqe_proc_top_m_axis_tready;
  wire         wqe_proc_top_m_axis_tlast;

  // AXI Master signals - wqe_proc
  wire [C_M_AXI_ID_WIDTH-1:0]   wqe_proc_top_m_axi_awid;
  wire [C_M_AXI_ADDR_WIDTH-1:0] wqe_proc_top_m_axi_awaddr;
  wire [7:0]  wqe_proc_top_m_axi_awlen;
  wire [2:0]  wqe_proc_top_m_axi_awsize;
  wire [1:0]  wqe_proc_top_m_axi_awburst;
  wire [3:0]  wqe_proc_top_m_axi_awcache;
  wire [2:0]  wqe_proc_top_m_axi_awprot;
  wire        wqe_proc_top_m_axi_awvalid, wqe_proc_top_m_axi_awready;
  wire [511:0] wqe_proc_top_m_axi_wdata;
  wire [63:0]  wqe_proc_top_m_axi_wstrb;
  wire        wqe_proc_top_m_axi_wlast, wqe_proc_top_m_axi_wvalid, wqe_proc_top_m_axi_wready;
  wire        wqe_proc_top_m_axi_awlock;
  wire [C_M_AXI_ID_WIDTH-1:0] wqe_proc_top_m_axi_bid;
  wire [1:0]  wqe_proc_top_m_axi_bresp;
  wire        wqe_proc_top_m_axi_bvalid, wqe_proc_top_m_axi_bready;
  wire [C_M_AXI_ID_WIDTH-1:0] wqe_proc_top_m_axi_arid;
  wire [C_M_AXI_ADDR_WIDTH-1:0] wqe_proc_top_m_axi_araddr;
  wire [7:0]  wqe_proc_top_m_axi_arlen;
  wire [2:0]  wqe_proc_top_m_axi_arsize;
  wire [1:0]  wqe_proc_top_m_axi_arburst;
  wire [3:0]  wqe_proc_top_m_axi_arcache;
  wire [2:0]  wqe_proc_top_m_axi_arprot;
  wire        wqe_proc_top_m_axi_arvalid, wqe_proc_top_m_axi_arready;
  wire [511:0] wqe_proc_top_m_axi_rdata;
  wire [1:0]  wqe_proc_top_m_axi_rresp;
  wire        wqe_proc_top_m_axi_rlast, wqe_proc_top_m_axi_rvalid, wqe_proc_top_m_axi_rready;
  wire        wqe_proc_top_m_axi_arlock;

  // AXI Master signals - wqe_proc_wr_ddr
  wire [C_M_AXI_ID_WIDTH-1:0]   wqe_proc_wr_ddr_m_axi_awid;
  wire [C_M_AXI_ADDR_WIDTH-1:0] wqe_proc_wr_ddr_m_axi_awaddr;
  wire [7:0]  wqe_proc_wr_ddr_m_axi_awlen;
  wire [2:0]  wqe_proc_wr_ddr_m_axi_awsize;
  wire [1:0]  wqe_proc_wr_ddr_m_axi_awburst;
  wire [3:0]  wqe_proc_wr_ddr_m_axi_awcache;
  wire [2:0]  wqe_proc_wr_ddr_m_axi_awprot;
  wire        wqe_proc_wr_ddr_m_axi_awvalid, wqe_proc_wr_ddr_m_axi_awready;
  wire [511:0] wqe_proc_wr_ddr_m_axi_wdata;
  wire [63:0]  wqe_proc_wr_ddr_m_axi_wstrb;
  wire        wqe_proc_wr_ddr_m_axi_wlast, wqe_proc_wr_ddr_m_axi_wvalid, wqe_proc_wr_ddr_m_axi_wready;
  wire        wqe_proc_wr_ddr_m_axi_awlock;
  wire [C_M_AXI_ID_WIDTH-1:0] wqe_proc_wr_ddr_m_axi_bid;
  wire [1:0]  wqe_proc_wr_ddr_m_axi_bresp;
  wire        wqe_proc_wr_ddr_m_axi_bvalid, wqe_proc_wr_ddr_m_axi_bready;
  wire [C_M_AXI_ID_WIDTH-1:0] wqe_proc_wr_ddr_m_axi_arid;
  wire [C_M_AXI_ADDR_WIDTH-1:0] wqe_proc_wr_ddr_m_axi_araddr;
  wire [7:0]  wqe_proc_wr_ddr_m_axi_arlen;
  wire [2:0]  wqe_proc_wr_ddr_m_axi_arsize;
  wire [1:0]  wqe_proc_wr_ddr_m_axi_arburst;
  wire [3:0]  wqe_proc_wr_ddr_m_axi_arcache;
  wire [2:0]  wqe_proc_wr_ddr_m_axi_arprot;
  wire        wqe_proc_wr_ddr_m_axi_arvalid, wqe_proc_wr_ddr_m_axi_arready;
  wire [511:0] wqe_proc_wr_ddr_m_axi_rdata;
  wire [1:0]  wqe_proc_wr_ddr_m_axi_rresp;
  wire        wqe_proc_wr_ddr_m_axi_rlast, wqe_proc_wr_ddr_m_axi_rvalid, wqe_proc_wr_ddr_m_axi_rready;
  wire        wqe_proc_wr_ddr_m_axi_arlock;

  // AXI Master signals - resp_handler
  wire [0:0]  resp_hndler_m_axi_awid, resp_hndler_m_axi_arid;
  wire [31:0] resp_hndler_m_axi_awaddr, resp_hndler_m_axi_araddr;
  wire [7:0]  resp_hndler_m_axi_awlen, resp_hndler_m_axi_arlen;
  wire [2:0]  resp_hndler_m_axi_awsize, resp_hndler_m_axi_arsize;
  wire [1:0]  resp_hndler_m_axi_awburst, resp_hndler_m_axi_arburst;
  wire [3:0]  resp_hndler_m_axi_awcache, resp_hndler_m_axi_arcache;
  wire [2:0]  resp_hndler_m_axi_awprot, resp_hndler_m_axi_arprot;
  wire        resp_hndler_m_axi_awvalid, resp_hndler_m_axi_awready;
  wire [511:0] resp_hndler_m_axi_wdata;
  wire [63:0]  resp_hndler_m_axi_wstrb;
  wire        resp_hndler_m_axi_wlast, resp_hndler_m_axi_wvalid, resp_hndler_m_axi_wready;
  wire        resp_hndler_m_axi_awlock, resp_hndler_m_axi_arlock;
  wire [0:0]  resp_hndler_m_axi_bid;
  wire [1:0]  resp_hndler_m_axi_bresp, resp_hndler_m_axi_rresp;
  wire        resp_hndler_m_axi_bvalid, resp_hndler_m_axi_bready;
  wire        resp_hndler_m_axi_arvalid, resp_hndler_m_axi_arready;
  wire [511:0] resp_hndler_m_axi_rdata;
  wire        resp_hndler_m_axi_rlast, resp_hndler_m_axi_rvalid, resp_hndler_m_axi_rready;

  // AXI Master signals - qp_mgr
  wire [0:0]  qp_mgr_m_axi_awid, qp_mgr_m_axi_arid;
  wire [31:0] qp_mgr_m_axi_awaddr, qp_mgr_m_axi_araddr;
  wire [7:0]  qp_mgr_m_axi_awlen, qp_mgr_m_axi_arlen;
  wire [2:0]  qp_mgr_m_axi_awsize, qp_mgr_m_axi_arsize;
  wire [1:0]  qp_mgr_m_axi_awburst, qp_mgr_m_axi_arburst;
  wire [3:0]  qp_mgr_m_axi_awcache, qp_mgr_m_axi_arcache;
  wire [2:0]  qp_mgr_m_axi_awprot, qp_mgr_m_axi_arprot;
  wire        qp_mgr_m_axi_awvalid, qp_mgr_m_axi_awready;
  wire [511:0] qp_mgr_m_axi_wdata;
  wire [63:0]  qp_mgr_m_axi_wstrb;
  wire        qp_mgr_m_axi_wlast, qp_mgr_m_axi_wvalid, qp_mgr_m_axi_wready;
  wire        qp_mgr_m_axi_awlock, qp_mgr_m_axi_arlock;
  wire [0:0]  qp_mgr_m_axi_bid;
  wire [1:0]  qp_mgr_m_axi_bresp, qp_mgr_m_axi_rresp;
  wire        qp_mgr_m_axi_bvalid, qp_mgr_m_axi_bready;
  wire        qp_mgr_m_axi_arvalid, qp_mgr_m_axi_arready;
  wire [511:0] qp_mgr_m_axi_rdata;
  wire        qp_mgr_m_axi_rlast, qp_mgr_m_axi_rvalid, qp_mgr_m_axi_rready;

  // AXI-Lite Slave
  wire [C_S_AXI_LITE_ADDR_WIDTH-1:0] s_axi_lite_awaddr, s_axi_lite_araddr;
  wire        s_axi_lite_awready, s_axi_lite_awvalid;
  wire        s_axi_lite_arready, s_axi_lite_arvalid;
  wire [31:0] s_axi_lite_wdata;
  wire [3:0]  s_axi_lite_wstrb;
  wire        s_axi_lite_wready, s_axi_lite_wvalid;
  wire [31:0] s_axi_lite_rdata;
  wire [1:0]  s_axi_lite_rresp, s_axi_lite_bresp;
  wire        s_axi_lite_rready, s_axi_lite_rvalid;
  wire        s_axi_lite_bready, s_axi_lite_bvalid;

  // Interrupts & handshake
  wire        rdma_core_intr0, rdma_core_intr1, rdma_core_intr2;
  wire        rdma_core_intr3, rdma_core_intr4, rdma_core_intr5;
  wire        rdma_core_intr6, rdma_core_intr7, rdma_core_intr8;
  wire        o_global_dbg_cnt_en, o_global_dbg_cnt_clr;
  wire        resp_hndler_o_send_cq_db_cnt_valid;
  wire [9:0]  resp_hndler_o_send_cq_db_addr;
  wire [31:0] resp_hndler_o_send_cq_db_cnt;
  wire        resp_hndler_i_send_cq_db_rdy = 1'b0;
  wire [15:0] i_qp_rq_cidb_hndshk = 16'd0;
  wire [31:0] i_qp_rq_cidb_wr_addr_hndshk = 32'd0;
  wire        i_qp_rq_cidb_wr_valid_hndshk = 1'b0;
  wire        o_qp_rq_cidb_wr_rdy;
  reg  [15:0] i_qp_sq_pidb_hndshk;
  reg  [31:0] i_qp_sq_pidb_wr_addr_hndshk;
  reg         i_qp_sq_pidb_wr_valid_hndshk;
  wire        o_qp_sq_pidb_wr_rdy;
  wire [31:0] rx_pkt_hndler_o_rq_db_data;
  wire [9:0]  rx_pkt_hndler_o_rq_db_addr;
  wire        rx_pkt_hndler_o_rq_db_data_valid;
  wire        rx_pkt_hndler_i_rq_db_rdy = 1'b1;

  // ==========================================================================
  // Clock generation
  // ==========================================================================
  initial m_axi_aclk = 0;
  always #(CLK_PERIOD/2) m_axi_aclk = ~m_axi_aclk;
  initial s_axi_lite_aclk = 0;
  always #(CLK_PERIOD/2) s_axi_lite_aclk = ~s_axi_lite_aclk;

  // ==========================================================================
  // DUT
  // ==========================================================================
  rdma_core #(
    .C_NUM_QP(C_NUM_QP), .C_M_AXI_ADDR_WIDTH(C_M_AXI_ADDR_WIDTH),
    .C_M_AXI_ID_WIDTH(C_M_AXI_ID_WIDTH), .C_S_AXI_LITE_ADDR_WIDTH(C_S_AXI_LITE_ADDR_WIDTH),
    .C_EN_DEBUG_PORTS(C_EN_DEBUG_PORTS), .C_EN_NVMOF_HW_HNDSHK(C_EN_NVMOF_HW_HNDSHK),
    .C_MAX_SGL_DEPTH(C_MAX_SGL_DEPTH), .C_MAX_WR_RETRY_DATA_BUF_DEPTH(C_MAX_WR_RETRY_DATA_BUF_DEPTH),
    .C_EN_WR_RETRY_DATA_BUF(C_EN_WR_RETRY_DATA_BUF), .C_OSQ_PSN_WIDTH(C_OSQ_PSN_WIDTH)
  ) u_dut (
    .m_axi_aclk(m_axi_aclk), .m_axi_aresetn(m_axi_aresetn),
    .s_axi_lite_aclk(s_axi_lite_aclk), .s_axi_lite_aresetn(s_axi_lite_aresetn),
    // RX AXI-Stream
    .rx_pkt_hndler_s_axis_tvalid(rx_pkt_hndler_s_axis_tvalid),
    .rx_pkt_hndler_s_axis_tdata(rx_pkt_hndler_s_axis_tdata),
    .rx_pkt_hndler_s_axis_tkeep(rx_pkt_hndler_s_axis_tkeep),
    .rx_pkt_hndler_s_axis_tlast(rx_pkt_hndler_s_axis_tlast),
    .rx_pkt_hndler_s_axis_tuser(rx_pkt_hndler_s_axis_tuser),
    // TX AXI-Stream
    .wqe_proc_top_m_axis_tdata(wqe_proc_top_m_axis_tdata),
    .wqe_proc_top_m_axis_tkeep(wqe_proc_top_m_axis_tkeep),
    .wqe_proc_top_m_axis_tvalid(wqe_proc_top_m_axis_tvalid),
    .wqe_proc_top_m_axis_tready(wqe_proc_top_m_axis_tready),
    .wqe_proc_top_m_axis_tlast(wqe_proc_top_m_axis_tlast),
    // wqe_proc AXI Master
    .wqe_proc_top_m_axi_awid(wqe_proc_top_m_axi_awid), .wqe_proc_top_m_axi_awaddr(wqe_proc_top_m_axi_awaddr),
    .wqe_proc_top_m_axi_awlen(wqe_proc_top_m_axi_awlen), .wqe_proc_top_m_axi_awsize(wqe_proc_top_m_axi_awsize),
    .wqe_proc_top_m_axi_awburst(wqe_proc_top_m_axi_awburst), .wqe_proc_top_m_axi_awcache(wqe_proc_top_m_axi_awcache),
    .wqe_proc_top_m_axi_awprot(wqe_proc_top_m_axi_awprot), .wqe_proc_top_m_axi_awvalid(wqe_proc_top_m_axi_awvalid),
    .wqe_proc_top_m_axi_awready(wqe_proc_top_m_axi_awready),
    .wqe_proc_top_m_axi_wdata(wqe_proc_top_m_axi_wdata), .wqe_proc_top_m_axi_wstrb(wqe_proc_top_m_axi_wstrb),
    .wqe_proc_top_m_axi_wlast(wqe_proc_top_m_axi_wlast), .wqe_proc_top_m_axi_wvalid(wqe_proc_top_m_axi_wvalid),
    .wqe_proc_top_m_axi_wready(wqe_proc_top_m_axi_wready), .wqe_proc_top_m_axi_awlock(wqe_proc_top_m_axi_awlock),
    .wqe_proc_top_m_axi_bid(wqe_proc_top_m_axi_bid), .wqe_proc_top_m_axi_bresp(wqe_proc_top_m_axi_bresp),
    .wqe_proc_top_m_axi_bvalid(wqe_proc_top_m_axi_bvalid), .wqe_proc_top_m_axi_bready(wqe_proc_top_m_axi_bready),
    .wqe_proc_top_m_axi_arid(wqe_proc_top_m_axi_arid), .wqe_proc_top_m_axi_araddr(wqe_proc_top_m_axi_araddr),
    .wqe_proc_top_m_axi_arlen(wqe_proc_top_m_axi_arlen), .wqe_proc_top_m_axi_arsize(wqe_proc_top_m_axi_arsize),
    .wqe_proc_top_m_axi_arburst(wqe_proc_top_m_axi_arburst), .wqe_proc_top_m_axi_arcache(wqe_proc_top_m_axi_arcache),
    .wqe_proc_top_m_axi_arprot(wqe_proc_top_m_axi_arprot), .wqe_proc_top_m_axi_arvalid(wqe_proc_top_m_axi_arvalid),
    .wqe_proc_top_m_axi_arready(wqe_proc_top_m_axi_arready),
    .wqe_proc_top_m_axi_rid(wqe_proc_top_m_axi_rid), .wqe_proc_top_m_axi_rdata(wqe_proc_top_m_axi_rdata),
    .wqe_proc_top_m_axi_rresp(wqe_proc_top_m_axi_rresp), .wqe_proc_top_m_axi_rlast(wqe_proc_top_m_axi_rlast),
    .wqe_proc_top_m_axi_rvalid(wqe_proc_top_m_axi_rvalid), .wqe_proc_top_m_axi_rready(wqe_proc_top_m_axi_rready),
    .wqe_proc_top_m_axi_arlock(wqe_proc_top_m_axi_arlock),
    // wqe_proc_wr_ddr AXI Master
    .wqe_proc_wr_ddr_m_axi_awid(wqe_proc_wr_ddr_m_axi_awid), .wqe_proc_wr_ddr_m_axi_awaddr(wqe_proc_wr_ddr_m_axi_awaddr),
    .wqe_proc_wr_ddr_m_axi_awlen(wqe_proc_wr_ddr_m_axi_awlen), .wqe_proc_wr_ddr_m_axi_awsize(wqe_proc_wr_ddr_m_axi_awsize),
    .wqe_proc_wr_ddr_m_axi_awburst(wqe_proc_wr_ddr_m_axi_awburst), .wqe_proc_wr_ddr_m_axi_awcache(wqe_proc_wr_ddr_m_axi_awcache),
    .wqe_proc_wr_ddr_m_axi_awprot(wqe_proc_wr_ddr_m_axi_awprot), .wqe_proc_wr_ddr_m_axi_awvalid(wqe_proc_wr_ddr_m_axi_awvalid),
    .wqe_proc_wr_ddr_m_axi_awready(wqe_proc_wr_ddr_m_axi_awready),
    .wqe_proc_wr_ddr_m_axi_wdata(wqe_proc_wr_ddr_m_axi_wdata), .wqe_proc_wr_ddr_m_axi_wstrb(wqe_proc_wr_ddr_m_axi_wstrb),
    .wqe_proc_wr_ddr_m_axi_wlast(wqe_proc_wr_ddr_m_axi_wlast), .wqe_proc_wr_ddr_m_axi_wvalid(wqe_proc_wr_ddr_m_axi_wvalid),
    .wqe_proc_wr_ddr_m_axi_wready(wqe_proc_wr_ddr_m_axi_wready), .wqe_proc_wr_ddr_m_axi_awlock(wqe_proc_wr_ddr_m_axi_awlock),
    .wqe_proc_wr_ddr_m_axi_bid(wqe_proc_wr_ddr_m_axi_bid), .wqe_proc_wr_ddr_m_axi_bresp(wqe_proc_wr_ddr_m_axi_bresp),
    .wqe_proc_wr_ddr_m_axi_bvalid(wqe_proc_wr_ddr_m_axi_bvalid), .wqe_proc_wr_ddr_m_axi_bready(wqe_proc_wr_ddr_m_axi_bready),
    .wqe_proc_wr_ddr_m_axi_arid(wqe_proc_wr_ddr_m_axi_arid), .wqe_proc_wr_ddr_m_axi_araddr(wqe_proc_wr_ddr_m_axi_araddr),
    .wqe_proc_wr_ddr_m_axi_arlen(wqe_proc_wr_ddr_m_axi_arlen), .wqe_proc_wr_ddr_m_axi_arsize(wqe_proc_wr_ddr_m_axi_arsize),
    .wqe_proc_wr_ddr_m_axi_arburst(wqe_proc_wr_ddr_m_axi_arburst), .wqe_proc_wr_ddr_m_axi_arcache(wqe_proc_wr_ddr_m_axi_arcache),
    .wqe_proc_wr_ddr_m_axi_arprot(wqe_proc_wr_ddr_m_axi_arprot), .wqe_proc_wr_ddr_m_axi_arvalid(wqe_proc_wr_ddr_m_axi_arvalid),
    .wqe_proc_wr_ddr_m_axi_arready(wqe_proc_wr_ddr_m_axi_arready),
    .wqe_proc_wr_ddr_m_axi_rid(wqe_proc_wr_ddr_m_axi_rid), .wqe_proc_wr_ddr_m_axi_rdata(wqe_proc_wr_ddr_m_axi_rdata),
    .wqe_proc_wr_ddr_m_axi_rresp(wqe_proc_wr_ddr_m_axi_rresp), .wqe_proc_wr_ddr_m_axi_rlast(wqe_proc_wr_ddr_m_axi_rlast),
    .wqe_proc_wr_ddr_m_axi_rvalid(wqe_proc_wr_ddr_m_axi_rvalid), .wqe_proc_wr_ddr_m_axi_rready(wqe_proc_wr_ddr_m_axi_rready),
    .wqe_proc_wr_ddr_m_axi_arlock(wqe_proc_wr_ddr_m_axi_arlock),
    // resp_handler AXI Master
    .resp_hndler_m_axi_awid(resp_hndler_m_axi_awid), .resp_hndler_m_axi_awaddr(resp_hndler_m_axi_awaddr),
    .resp_hndler_m_axi_awlen(resp_hndler_m_axi_awlen), .resp_hndler_m_axi_awsize(resp_hndler_m_axi_awsize),
    .resp_hndler_m_axi_awburst(resp_hndler_m_axi_awburst), .resp_hndler_m_axi_awcache(resp_hndler_m_axi_awcache),
    .resp_hndler_m_axi_awprot(resp_hndler_m_axi_awprot), .resp_hndler_m_axi_awvalid(resp_hndler_m_axi_awvalid),
    .resp_hndler_m_axi_awready(resp_hndler_m_axi_awready),
    .resp_hndler_m_axi_wdata(resp_hndler_m_axi_wdata), .resp_hndler_m_axi_wstrb(resp_hndler_m_axi_wstrb),
    .resp_hndler_m_axi_wlast(resp_hndler_m_axi_wlast), .resp_hndler_m_axi_wvalid(resp_hndler_m_axi_wvalid),
    .resp_hndler_m_axi_wready(resp_hndler_m_axi_wready), .resp_hndler_m_axi_awlock(resp_hndler_m_axi_awlock),
    .resp_hndler_m_axi_bid(resp_hndler_m_axi_bid), .resp_hndler_m_axi_bresp(resp_hndler_m_axi_bresp),
    .resp_hndler_m_axi_bvalid(resp_hndler_m_axi_bvalid), .resp_hndler_m_axi_bready(resp_hndler_m_axi_bready),
    .resp_hndler_m_axi_arid(resp_hndler_m_axi_arid), .resp_hndler_m_axi_araddr(resp_hndler_m_axi_araddr),
    .resp_hndler_m_axi_arlen(resp_hndler_m_axi_arlen), .resp_hndler_m_axi_arsize(resp_hndler_m_axi_arsize),
    .resp_hndler_m_axi_arburst(resp_hndler_m_axi_arburst), .resp_hndler_m_axi_arcache(resp_hndler_m_axi_arcache),
    .resp_hndler_m_axi_arprot(resp_hndler_m_axi_arprot), .resp_hndler_m_axi_arvalid(resp_hndler_m_axi_arvalid),
    .resp_hndler_m_axi_arready(resp_hndler_m_axi_arready),
    .resp_hndler_m_axi_rid(resp_hndler_m_axi_rid), .resp_hndler_m_axi_rdata(resp_hndler_m_axi_rdata),
    .resp_hndler_m_axi_rresp(resp_hndler_m_axi_rresp), .resp_hndler_m_axi_rlast(resp_hndler_m_axi_rlast),
    .resp_hndler_m_axi_rvalid(resp_hndler_m_axi_rvalid), .resp_hndler_m_axi_rready(resp_hndler_m_axi_rready),
    .resp_hndler_m_axi_arlock(resp_hndler_m_axi_arlock),
    // AXI-Lite Slave
    .s_axi_lite_awaddr(s_axi_lite_awaddr), .s_axi_lite_awready(s_axi_lite_awready), .s_axi_lite_awvalid(s_axi_lite_awvalid),
    .s_axi_lite_araddr(s_axi_lite_araddr), .s_axi_lite_arready(s_axi_lite_arready), .s_axi_lite_arvalid(s_axi_lite_arvalid),
    .s_axi_lite_wdata(s_axi_lite_wdata), .s_axi_lite_wstrb(s_axi_lite_wstrb),
    .s_axi_lite_wready(s_axi_lite_wready), .s_axi_lite_wvalid(s_axi_lite_wvalid),
    .s_axi_lite_rdata(s_axi_lite_rdata), .s_axi_lite_rresp(s_axi_lite_rresp),
    .s_axi_lite_rready(s_axi_lite_rready), .s_axi_lite_rvalid(s_axi_lite_rvalid),
    .s_axi_lite_bresp(s_axi_lite_bresp), .s_axi_lite_bready(s_axi_lite_bready), .s_axi_lite_bvalid(s_axi_lite_bvalid),
    // qp_mgr AXI Master
    .qp_mgr_m_axi_awid(qp_mgr_m_axi_awid), .qp_mgr_m_axi_awaddr(qp_mgr_m_axi_awaddr),
    .qp_mgr_m_axi_awlen(qp_mgr_m_axi_awlen), .qp_mgr_m_axi_awsize(qp_mgr_m_axi_awsize),
    .qp_mgr_m_axi_awburst(qp_mgr_m_axi_awburst), .qp_mgr_m_axi_awcache(qp_mgr_m_axi_awcache),
    .qp_mgr_m_axi_awprot(qp_mgr_m_axi_awprot), .qp_mgr_m_axi_awvalid(qp_mgr_m_axi_awvalid),
    .qp_mgr_m_axi_awready(qp_mgr_m_axi_awready),
    .qp_mgr_m_axi_wdata(qp_mgr_m_axi_wdata), .qp_mgr_m_axi_wstrb(qp_mgr_m_axi_wstrb),
    .qp_mgr_m_axi_wlast(qp_mgr_m_axi_wlast), .qp_mgr_m_axi_wvalid(qp_mgr_m_axi_wvalid),
    .qp_mgr_m_axi_wready(qp_mgr_m_axi_wready), .qp_mgr_m_axi_awlock(qp_mgr_m_axi_awlock),
    .qp_mgr_m_axi_bid(qp_mgr_m_axi_bid), .qp_mgr_m_axi_bresp(qp_mgr_m_axi_bresp),
    .qp_mgr_m_axi_bvalid(qp_mgr_m_axi_bvalid), .qp_mgr_m_axi_bready(qp_mgr_m_axi_bready),
    .qp_mgr_m_axi_arid(qp_mgr_m_axi_arid), .qp_mgr_m_axi_araddr(qp_mgr_m_axi_araddr),
    .qp_mgr_m_axi_arlen(qp_mgr_m_axi_arlen), .qp_mgr_m_axi_arsize(qp_mgr_m_axi_arsize),
    .qp_mgr_m_axi_arburst(qp_mgr_m_axi_arburst), .qp_mgr_m_axi_arcache(qp_mgr_m_axi_arcache),
    .qp_mgr_m_axi_arprot(qp_mgr_m_axi_arprot), .qp_mgr_m_axi_arvalid(qp_mgr_m_axi_arvalid),
    .qp_mgr_m_axi_arready(qp_mgr_m_axi_arready),
    .qp_mgr_m_axi_rid(qp_mgr_m_axi_rid), .qp_mgr_m_axi_rdata(qp_mgr_m_axi_rdata),
    .qp_mgr_m_axi_rresp(qp_mgr_m_axi_rresp), .qp_mgr_m_axi_rlast(qp_mgr_m_axi_rlast),
    .qp_mgr_m_axi_rvalid(qp_mgr_m_axi_rvalid), .qp_mgr_m_axi_rready(qp_mgr_m_axi_rready),
    .qp_mgr_m_axi_arlock(qp_mgr_m_axi_arlock),
    // Hardware handshake
    .resp_hndler_o_send_cq_db_cnt_valid(resp_hndler_o_send_cq_db_cnt_valid),
    .resp_hndler_o_send_cq_db_addr(resp_hndler_o_send_cq_db_addr),
    .resp_hndler_o_send_cq_db_cnt(resp_hndler_o_send_cq_db_cnt),
    .resp_hndler_i_send_cq_db_rdy(resp_hndler_i_send_cq_db_rdy),
    .i_qp_rq_cidb_hndshk(i_qp_rq_cidb_hndshk), .i_qp_rq_cidb_wr_addr_hndshk(i_qp_rq_cidb_wr_addr_hndshk),
    .i_qp_rq_cidb_wr_valid_hndshk(i_qp_rq_cidb_wr_valid_hndshk), .o_qp_rq_cidb_wr_rdy(o_qp_rq_cidb_wr_rdy),
    .i_qp_sq_pidb_hndshk(i_qp_sq_pidb_hndshk), .i_qp_sq_pidb_wr_addr_hndshk(i_qp_sq_pidb_wr_addr_hndshk),
    .i_qp_sq_pidb_wr_valid_hndshk(i_qp_sq_pidb_wr_valid_hndshk), .o_qp_sq_pidb_wr_rdy(o_qp_sq_pidb_wr_rdy),
    .rx_pkt_hndler_o_rq_db_data(rx_pkt_hndler_o_rq_db_data),
    .rx_pkt_hndler_o_rq_db_addr(rx_pkt_hndler_o_rq_db_addr),
    .rx_pkt_hndler_o_rq_db_data_valid(rx_pkt_hndler_o_rq_db_data_valid),
    .rx_pkt_hndler_i_rq_db_rdy(rx_pkt_hndler_i_rq_db_rdy),
    // Interrupts
    .rdma_core_intr0(rdma_core_intr0), .rdma_core_intr1(rdma_core_intr1),
    .rdma_core_intr2(rdma_core_intr2), .rdma_core_intr3(rdma_core_intr3),
    .rdma_core_intr4(rdma_core_intr4), .rdma_core_intr5(rdma_core_intr5),
    .rdma_core_intr6(rdma_core_intr6), .rdma_core_intr7(rdma_core_intr7),
    .rdma_core_intr8(rdma_core_intr8),
    .o_global_dbg_cnt_en(o_global_dbg_cnt_en), .o_global_dbg_cnt_clr(o_global_dbg_cnt_clr)
  );

  // ==========================================================================
  // AXI-Lite Master BFM
  // ==========================================================================
  axi_lite_master_bfm #(.ADDR_WIDTH(C_S_AXI_LITE_ADDR_WIDTH)) u_axi_lite_bfm (
    .clk(s_axi_lite_aclk), .rstn(s_axi_lite_aresetn),
    .awaddr(s_axi_lite_awaddr), .awvalid(s_axi_lite_awvalid), .awready(s_axi_lite_awready),
    .wdata(s_axi_lite_wdata), .wstrb(s_axi_lite_wstrb), .wvalid(s_axi_lite_wvalid), .wready(s_axi_lite_wready),
    .rdata(s_axi_lite_rdata), .rresp(s_axi_lite_rresp), .rvalid(s_axi_lite_rvalid), .rready(s_axi_lite_rready),
    .bresp(s_axi_lite_bresp), .bvalid(s_axi_lite_bvalid), .bready(s_axi_lite_bready),
    .araddr(s_axi_lite_araddr), .arvalid(s_axi_lite_arvalid), .arready(s_axi_lite_arready)
  );

  // ==========================================================================
  // AXI Slave Memory Models
  // ==========================================================================
  axi_slave_mem_model #(.ADDR_WIDTH(32), .ID_WIDTH(C_M_AXI_ID_WIDTH), .DATA_WIDTH(512), .MEM_DEPTH(16384))
  u_ddr_wqe_proc (.clk(clk), .rstn(m_axi_aresetn),
    .awid(wqe_proc_top_m_axi_awid), .awaddr(wqe_proc_top_m_axi_awaddr),
    .awlen(wqe_proc_top_m_axi_awlen), .awsize(wqe_proc_top_m_axi_awsize),
    .awvalid(wqe_proc_top_m_axi_awvalid), .awready(wqe_proc_top_m_axi_awready),
    .wdata(wqe_proc_top_m_axi_wdata), .wstrb(wqe_proc_top_m_axi_wstrb),
    .wlast(wqe_proc_top_m_axi_wlast), .wvalid(wqe_proc_top_m_axi_wvalid), .wready(wqe_proc_top_m_axi_wready),
    .bid(wqe_proc_top_m_axi_bid), .bresp(wqe_proc_top_m_axi_bresp),
    .bvalid(wqe_proc_top_m_axi_bvalid), .bready(wqe_proc_top_m_axi_bready),
    .arid(wqe_proc_top_m_axi_arid), .araddr(wqe_proc_top_m_axi_araddr),
    .arlen(wqe_proc_top_m_axi_arlen), .arsize(wqe_proc_top_m_axi_arsize),
    .arvalid(wqe_proc_top_m_axi_arvalid), .arready(wqe_proc_top_m_axi_arready),
    .rid(wqe_proc_top_m_axi_rid), .rdata(wqe_proc_top_m_axi_rdata),
    .rresp(wqe_proc_top_m_axi_rresp), .rlast(wqe_proc_top_m_axi_rlast),
    .rvalid(wqe_proc_top_m_axi_rvalid), .rready(wqe_proc_top_m_axi_rready));

  axi_slave_mem_model #(.ADDR_WIDTH(32), .ID_WIDTH(C_M_AXI_ID_WIDTH), .DATA_WIDTH(512), .MEM_DEPTH(4096))
  u_ddr_wqe_wr (.clk(clk), .rstn(m_axi_aresetn),
    .awid(wqe_proc_wr_ddr_m_axi_awid), .awaddr(wqe_proc_wr_ddr_m_axi_awaddr),
    .awlen(wqe_proc_wr_ddr_m_axi_awlen), .awsize(wqe_proc_wr_ddr_m_axi_awsize),
    .awvalid(wqe_proc_wr_ddr_m_axi_awvalid), .awready(wqe_proc_wr_ddr_m_axi_awready),
    .wdata(wqe_proc_wr_ddr_m_axi_wdata), .wstrb(wqe_proc_wr_ddr_m_axi_wstrb),
    .wlast(wqe_proc_wr_ddr_m_axi_wlast), .wvalid(wqe_proc_wr_ddr_m_axi_wvalid), .wready(wqe_proc_wr_ddr_m_axi_wready),
    .bid(wqe_proc_wr_ddr_m_axi_bid), .bresp(wqe_proc_wr_ddr_m_axi_bresp),
    .bvalid(wqe_proc_wr_ddr_m_axi_bvalid), .bready(wqe_proc_wr_ddr_m_axi_bready),
    .arid(wqe_proc_wr_ddr_m_axi_arid), .araddr(wqe_proc_wr_ddr_m_axi_araddr),
    .arlen(wqe_proc_wr_ddr_m_axi_arlen), .arsize(wqe_proc_wr_ddr_m_axi_arsize),
    .arvalid(wqe_proc_wr_ddr_m_axi_arvalid), .arready(wqe_proc_wr_ddr_m_axi_arready),
    .rid(wqe_proc_wr_ddr_m_axi_rid), .rdata(wqe_proc_wr_ddr_m_axi_rdata),
    .rresp(wqe_proc_wr_ddr_m_axi_rresp), .rlast(wqe_proc_wr_ddr_m_axi_rlast),
    .rvalid(wqe_proc_wr_ddr_m_axi_rvalid), .rready(wqe_proc_wr_ddr_m_axi_rready));

  axi_slave_mem_model #(.ADDR_WIDTH(32), .ID_WIDTH(1), .DATA_WIDTH(512), .MEM_DEPTH(4096))
  u_ddr_resp (.clk(clk), .rstn(m_axi_aresetn),
    .awid(resp_hndler_m_axi_awid), .awaddr(resp_hndler_m_axi_awaddr),
    .awlen(resp_hndler_m_axi_awlen), .awsize(resp_hndler_m_axi_awsize),
    .awvalid(resp_hndler_m_axi_awvalid), .awready(resp_hndler_m_axi_awready),
    .wdata(resp_hndler_m_axi_wdata), .wstrb(resp_hndler_m_axi_wstrb),
    .wlast(resp_hndler_m_axi_wlast), .wvalid(resp_hndler_m_axi_wvalid), .wready(resp_hndler_m_axi_wready),
    .bid(resp_hndler_m_axi_bid), .bresp(resp_hndler_m_axi_bresp),
    .bvalid(resp_hndler_m_axi_bvalid), .bready(resp_hndler_m_axi_bready),
    .arid(resp_hndler_m_axi_arid), .araddr(resp_hndler_m_axi_araddr),
    .arlen(resp_hndler_m_axi_arlen), .arsize(resp_hndler_m_axi_arsize),
    .arvalid(resp_hndler_m_axi_arvalid), .arready(resp_hndler_m_axi_arready),
    .rid(resp_hndler_m_axi_rid), .rdata(resp_hndler_m_axi_rdata),
    .rresp(resp_hndler_m_axi_rresp), .rlast(resp_hndler_m_axi_rlast),
    .rvalid(resp_hndler_m_axi_rvalid), .rready(resp_hndler_m_axi_rready));

  axi_slave_mem_model #(.ADDR_WIDTH(32), .ID_WIDTH(1), .DATA_WIDTH(512), .MEM_DEPTH(16384))
  u_ddr_qp_mgr (.clk(clk), .rstn(m_axi_aresetn),
    .awid(qp_mgr_m_axi_awid), .awaddr(qp_mgr_m_axi_awaddr),
    .awlen(qp_mgr_m_axi_awlen), .awsize(qp_mgr_m_axi_awsize),
    .awvalid(qp_mgr_m_axi_awvalid), .awready(qp_mgr_m_axi_awready),
    .wdata(qp_mgr_m_axi_wdata), .wstrb(qp_mgr_m_axi_wstrb),
    .wlast(qp_mgr_m_axi_wlast), .wvalid(qp_mgr_m_axi_wvalid), .wready(qp_mgr_m_axi_wready),
    .bid(qp_mgr_m_axi_bid), .bresp(qp_mgr_m_axi_bresp),
    .bvalid(qp_mgr_m_axi_bvalid), .bready(qp_mgr_m_axi_bready),
    .arid(qp_mgr_m_axi_arid), .araddr(qp_mgr_m_axi_araddr),
    .arlen(qp_mgr_m_axi_arlen), .arsize(qp_mgr_m_axi_arsize),
    .arvalid(qp_mgr_m_axi_arvalid), .arready(qp_mgr_m_axi_arready),
    .rid(qp_mgr_m_axi_rid), .rdata(qp_mgr_m_axi_rdata),
    .rresp(qp_mgr_m_axi_rresp), .rlast(qp_mgr_m_axi_rlast),
    .rvalid(qp_mgr_m_axi_rvalid), .rready(qp_mgr_m_axi_rready));

  // TX always ready
  assign wqe_proc_top_m_axis_tready = 1'b1;

  // ==========================================================================
  // TX Packet Capture
  // ==========================================================================
  localparam MAX_TX_PKTS = 128;
  reg [511:0] tx_pkt_hdr  [0:MAX_TX_PKTS-1];
  reg [63:0]  tx_pkt_hdr_keep [0:MAX_TX_PKTS-1];
  reg [511:0] tx_pkt_last [0:MAX_TX_PKTS-1];
  reg [63:0]  tx_pkt_last_keep [0:MAX_TX_PKTS-1];
  integer tx_pkt_cnt;
  reg tx_pkt_started;

  // TX first beat debug monitor
  always @(posedge m_axi_aclk) begin
    if (wqe_proc_top_m_axis_tvalid && wqe_proc_top_m_axis_tready) begin
      if (wqe_proc_top_m_axis_tlast) begin
        $display("[%0t] TX_PKT_END: pkt#%0d tdata[63:0]=%h", $time, tx_pkt_cnt, wqe_proc_top_m_axis_tdata[63:0]);
      end
    end
  end

  always @(posedge m_axi_aclk) begin
    if (wqe_proc_top_m_axis_tvalid && wqe_proc_top_m_axis_tready) begin
      if (tx_pkt_cnt < MAX_TX_PKTS) begin
        if (!tx_pkt_started) begin
          tx_pkt_hdr[tx_pkt_cnt] <= wqe_proc_top_m_axis_tdata;
          tx_pkt_hdr_keep[tx_pkt_cnt] <= wqe_proc_top_m_axis_tkeep;
          tx_pkt_started <= 1'b1;
        end
        if (wqe_proc_top_m_axis_tlast) begin
          tx_pkt_last[tx_pkt_cnt] <= wqe_proc_top_m_axis_tdata;
          tx_pkt_last_keep[tx_pkt_cnt] <= wqe_proc_top_m_axis_tkeep;
          tx_pkt_cnt <= tx_pkt_cnt + 1;
          tx_pkt_started <= 1'b0;
        end
      end
    end
  end

  // ==========================================================================
  // Register Addresses
  // ==========================================================================
  localparam [17:0] ADDR_RDMA_CONF_REG   = 18'h00000;
  localparam [17:0] ADDR_ADV_CONF_REG    = 18'h00004;
  localparam [17:0] ADDR_MAC_LSB_REG     = 18'h00010;
  localparam [17:0] ADDR_MAC_MSB_REG     = 18'h00014;
  localparam [17:0] ADDR_IPV4_REG        = 18'h00070;
  localparam [17:0] ADDR_TX_HDR_BUF_BA   = 18'h00030;
  localparam [17:0] ADDR_TX_HDR_BUF_SZ   = 18'h00038;
  localparam [17:0] ADDR_TX_SGL_BUF_BA   = 18'h00040;
  localparam [17:0] ADDR_TX_SGL_BUF_SZ   = 18'h00048;
  localparam [17:0] ADDR_DATA_BUF_BA     = 18'h000A0;
  localparam [17:0] ADDR_DATA_BUF_SZ     = 18'h000A8;
  localparam [17:0] ADDR_ERR_PKT_BUF_BA  = 18'h00060;
  localparam [17:0] ADDR_ERR_PKT_BUF_SZ  = 18'h00068;

  // QP0 registers
  localparam [17:0] QP0_BASE             = 18'h00300;
  localparam [17:0] ADDR_QP0_CONF        = QP0_BASE + 18'h000;
  localparam [17:0] ADDR_QP0_SQ_BA       = QP0_BASE + 18'h010;
  localparam [17:0] ADDR_QP0_CQ_BA       = QP0_BASE + 18'h018;
  localparam [17:0] ADDR_QP0_SQ_PI_DB    = QP0_BASE + 18'h038;
  localparam [17:0] ADDR_QP0_Q_DEPTH     = QP0_BASE + 18'h03C;
  localparam [17:0] ADDR_QP0_SQ_PSN      = QP0_BASE + 18'h040;
  localparam [17:0] ADDR_QP0_TIMEOUT     = QP0_BASE + 18'h04C;
  localparam [17:0] ADDR_QP0_DEST_QP_CONF = QP0_BASE + 18'h048;
  localparam [17:0] ADDR_QP0_MAC_REM_LSB = QP0_BASE + 18'h050;
  localparam [17:0] ADDR_QP0_MAC_REM_MSB = QP0_BASE + 18'h054;
  localparam [17:0] ADDR_QP0_IP_REMOTE1  = QP0_BASE + 18'h060;

  // ==========================================================================
  // Test Configuration
  // ==========================================================================
  localparam [47:0] FPGA_MAC = 48'h001122334455;
  localparam [47:0] PC_MAC   = 48'hAABBCCDDEEFF;
  localparam [31:0] FPGA_IP  = 32'hC0A8010A;  // 192.168.1.10
  localparam [31:0] PC_IP    = 32'hC0A80114;  // 192.168.1.20

  reg [31:0] rd_data;
  integer test_pass, test_fail;

  // WQE construction variable
  reg [511:0] wqe_data;

  // ==========================================================================
  // Main Test Sequence
  // ==========================================================================
  initial begin
    m_axi_aresetn = 0;
    s_axi_lite_aresetn = 0;
    rx_pkt_hndler_s_axis_tvalid = 0;
    rx_pkt_hndler_s_axis_tdata  = 512'd0;
    rx_pkt_hndler_s_axis_tkeep  = 64'd0;
    rx_pkt_hndler_s_axis_tlast  = 0;
    rx_pkt_hndler_s_axis_tuser  = 0;
    tx_pkt_cnt = 0;
    tx_pkt_started = 0;
    test_pass  = 0;
    test_fail  = 0;
    i_qp_sq_pidb_hndshk = 16'd0;
    i_qp_sq_pidb_wr_addr_hndshk = 32'd0;
    i_qp_sq_pidb_wr_valid_hndshk = 1'b0;

    // Reset
    repeat(20) @(posedge m_axi_aclk);
    m_axi_aresetn = 1;
    s_axi_lite_aresetn = 1;
    $display("========================================");
    $display("[%0t] Reset released", $time);
    $display("========================================");
    repeat(50) @(posedge m_axi_aclk);

    // ==================================================================
    // Step 1: Configure global registers
    // ==================================================================
    $display("--- Step 1: Global register config ---");
    u_axi_lite_bfm.axi_lite_write(ADDR_RDMA_CONF_REG, 32'h12B7_0141);
    u_axi_lite_bfm.axi_lite_write(ADDR_ADV_CONF_REG,  32'h0000_0000);
    u_axi_lite_bfm.axi_lite_write(ADDR_MAC_LSB_REG,   32'h2233_4455);
    u_axi_lite_bfm.axi_lite_write(ADDR_MAC_MSB_REG,   32'h0000_0011);
    u_axi_lite_bfm.axi_lite_write(ADDR_IPV4_REG,       32'hC0A8_010A);
    u_axi_lite_bfm.axi_lite_write(ADDR_TX_HDR_BUF_BA, 32'h0001_0000);
    u_axi_lite_bfm.axi_lite_write(ADDR_TX_HDR_BUF_SZ, 32'h0000_1000);
    u_axi_lite_bfm.axi_lite_write(ADDR_TX_SGL_BUF_BA, 32'h0001_1000);
    u_axi_lite_bfm.axi_lite_write(ADDR_TX_SGL_BUF_SZ, 32'h0000_1000);
    u_axi_lite_bfm.axi_lite_write(ADDR_DATA_BUF_BA,   32'h0002_0000);
    u_axi_lite_bfm.axi_lite_write(ADDR_DATA_BUF_SZ,   32'h0000_1000);
    u_axi_lite_bfm.axi_lite_write(ADDR_ERR_PKT_BUF_BA,32'h0003_0000);
    u_axi_lite_bfm.axi_lite_write(ADDR_ERR_PKT_BUF_SZ,32'h0000_1000);

    // ==================================================================
    // Step 2: Configure QP0
    // ==================================================================
    $display("--- Step 2: QP0 config ---");
    u_axi_lite_bfm.axi_lite_write(ADDR_QP0_CONF,        32'h0000_0001);
    u_axi_lite_bfm.axi_lite_write(ADDR_QP0_SQ_BA,       32'h0004_0000);
    u_axi_lite_bfm.axi_lite_write(ADDR_QP0_CQ_BA,       32'h0005_0000);
    u_axi_lite_bfm.axi_lite_write(ADDR_QP0_SQ_PSN,      32'h0000_0000);
    u_axi_lite_bfm.axi_lite_write(ADDR_QP0_DEST_QP_CONF, 32'h0000_0001);
    u_axi_lite_bfm.axi_lite_write(ADDR_QP0_MAC_REM_LSB, 32'hCCDD_EEFF);
    u_axi_lite_bfm.axi_lite_write(ADDR_QP0_MAC_REM_MSB, 32'h0000_AABB);
    u_axi_lite_bfm.axi_lite_write(ADDR_QP0_IP_REMOTE1,  32'hC0A8_0114);
    u_axi_lite_bfm.axi_lite_write(ADDR_QP0_TIMEOUT,     32'h0000_0008);
    u_axi_lite_bfm.axi_lite_write(ADDR_QP0_Q_DEPTH,     32'h0000_0040);

    // ==================================================================
    // Step 3: Pre-load WQE + data into DDR model
    //   WQE位置固定、数据位置固定、大小固定 -> 所有SQ slot写相同的WQE
    //   5次doorbell只有SQ_PI递增，PSN由硬件自增，其余字段完全相同
    // ==================================================================
    $display("--- Step 3: Pre-load WQE and data (fixed position, fixed size) ---");
    begin : build_wqe
      integer slot;
      wqe_data = 512'd0;
      wqe_data[15:0]   = 16'h0001;                      // wrid
      wqe_data[16]     = 1'b0;                           // not retried
      wqe_data[95:32]  = 64'h0000_0000_0002_0000;       // local_offset (DDR数据起始地址, 固定)
      wqe_data[127:96] = 32'h0000_1000;                  // dma_len = 4KB (固定)
      wqe_data[135:128]= 8'h00;                          // opcode = RDMA Write (固定)
      wqe_data[223:160]= 64'h0000_0000_0000_1000;       // remote VA (固定)
      wqe_data[255:224]= 32'h0000_0001;                  // r_key (固定)
      // 所有SQ slot写同一份WQE, 只有PSN不同(硬件自增)
      for (slot = 0; slot < (NUM_SW_DB + NUM_HW_DB); slot = slot + 1) begin
        u_ddr_qp_mgr.write_mem(32'h0004_0000 + slot * 64, wqe_data);
      end
      $display("  WQE loaded x%0d slots at SQ_BASE=0x0040_0000: opcode=0x%02h dma_len=0x%08h local=0x%016h remote=0x%016h rkey=0x%08h",
               NUM_SW_DB, wqe_data[135:128], wqe_data[127:96], wqe_data[95:32],
               wqe_data[223:160], wqe_data[255:224]);
    end

    // Pre-load data at local DMA address 0x0002_0000 (4KB = 64 rows of 64B)
    begin : preload_dma_data
      integer row;
      reg [7:0]  pattern_byte;
      reg [511:0] row_data;
      for (row = 0; row < 64; row = row + 1) begin
        pattern_byte = row[7:0];
        row_data = {64{pattern_byte}};
        u_ddr_wqe_proc.write_mem(32'h0002_0000 + row * 64, row_data);
      end
      $display("  Pre-loaded 4KB DMA data at 0x0002_0000 (64 rows, row-n pattern)");
    end

    // ==================================================================
    // Step 4: SW Doorbell x5
    //   WQE已在Step3一次性写入, 5次doorbell只有SQ_PI递增
    //   PSN由硬件自增, 其余WQE字段完全相同
    // ==================================================================
    begin : sw_doorbell_loop
      integer db_idx;
      integer pkt_cnt_before;
      integer pkt_cnt_after;
      integer wait_cnt;
      integer idle_cnt;
      integer last_pkt_cnt;

      for (db_idx = 1; db_idx <= NUM_SW_DB; db_idx = db_idx + 1) begin

        // Wait for system to be idle (no new TX packets for 200 cycles)
        last_pkt_cnt = tx_pkt_cnt;
        idle_cnt = 0;
        while (idle_cnt < 200) begin
          @(posedge m_axi_aclk);
          if (tx_pkt_cnt != last_pkt_cnt) begin
            last_pkt_cnt = tx_pkt_cnt;
            idle_cnt = 0;
          end else begin
            idle_cnt = idle_cnt + 1;
          end
        end

        $display("");
        $display("--- SW Doorbell #%0d: writing SQ_PI=%0d (system idle, %0d pkts so far) ---",
                 db_idx, db_idx, tx_pkt_cnt);
        pkt_cnt_before = tx_pkt_cnt;

        // Ring doorbell: write SQ_PI (WQE already in DDR, just advance PI)
        u_axi_lite_bfm.axi_lite_write(ADDR_QP0_SQ_PI_DB, db_idx);

        // Wait for TX packet(s) to be emitted (up to 10000 cycles)
        wait_cnt = 0;
        while (tx_pkt_cnt == pkt_cnt_before && wait_cnt < 10000) begin
          @(posedge m_axi_aclk);
          wait_cnt = wait_cnt + 1;
        end

        pkt_cnt_after = tx_pkt_cnt;
        if (pkt_cnt_after > pkt_cnt_before) begin
          $display("[%0t] SW DB #%0d: PASS - %0d TX packet(s) emitted (total: %0d)",
                   $time, db_idx, pkt_cnt_after - pkt_cnt_before, pkt_cnt_after);
          test_pass = test_pass + 1;
        end else begin
          $display("[%0t] SW DB #%0d: FAIL - no TX packet after %0d cycles",
                   $time, db_idx, wait_cnt);
          test_fail = test_fail + 1;
        end
      end
    end

    // ==================================================================
    // Step 5: HW Handshake Doorbell test (5 times)
    //   使用i_qp_sq_pidb_hndshk接口，走Port B写入BRAM
    //   与SW doorbell写Port A效果完全相同
    // ==================================================================
    $display("");
    $display("--- Step 5: HW Handshake Doorbell test (%0d times) ---", NUM_HW_DB);

    begin : hw_hndshk_loop
      integer db_idx;
      integer pkt_cnt_before;
      integer pkt_cnt_after;
      integer wait_cnt;
      integer idle_cnt;
      integer last_pkt_cnt;
      reg [15:0] hw_pi_val;

      // HW handshake uses QP1 offset in wr_addr
      // wr_addr[16:9] = QP index + 1, wr_addr[7:0] = SQ_PI_DB_QPN = 0x38
      // For QP0: wr_addr = (0+1)<<9 | 0x38 = 0x0138
      hw_pi_val = NUM_SW_DB;  // SW已完成NUM_SW_DB次，PI从NUM_SW_DB+1开始

      for (db_idx = 1; db_idx <= NUM_HW_DB; db_idx = db_idx + 1) begin

        // Wait for system to be idle (tx_pkt_cnt stable for 2000 cycles)
        last_pkt_cnt = tx_pkt_cnt;
        idle_cnt = 0;
        while (idle_cnt < 20000) begin
          @(posedge m_axi_aclk);
          if (tx_pkt_cnt != last_pkt_cnt) begin
            last_pkt_cnt = tx_pkt_cnt;
            idle_cnt = 0;
          end else begin
            idle_cnt = idle_cnt + 1;
          end
        end

        $display("");
        $display("--- HW Hndshk DB #%0d: PI=%0d (%0d pkts so far) ---",
                 db_idx, hw_pi_val + 1, tx_pkt_cnt);
        pkt_cnt_before = tx_pkt_cnt;

        // HW handshake doorbell: valid/ready protocol on s_axi_lite_aclk
        hw_pi_val = hw_pi_val + 1;
        i_qp_sq_pidb_hndshk          <= hw_pi_val;
        i_qp_sq_pidb_wr_addr_hndshk  <= 32'h0000_0138;  // QP0 SQ_PI_DB
        @(posedge s_axi_lite_aclk);
        i_qp_sq_pidb_wr_valid_hndshk <= 1'b1;

        // Wait for rdy
        wait_cnt = 0;
        while (!o_qp_sq_pidb_wr_rdy && wait_cnt < 200) begin
          @(posedge s_axi_lite_aclk);
          wait_cnt = wait_cnt + 1;
        end

        @(posedge s_axi_lite_aclk);
        i_qp_sq_pidb_wr_valid_hndshk <= 1'b0;
        i_qp_sq_pidb_hndshk          <= 16'd0;
        i_qp_sq_pidb_wr_addr_hndshk  <= 32'd0;

        // Wait for TX packet(s) (on m_axi_aclk domain)
        wait_cnt = 0;
        while (tx_pkt_cnt == pkt_cnt_before && wait_cnt < 100000) begin
          @(posedge m_axi_aclk);
          wait_cnt = wait_cnt + 1;
        end

        pkt_cnt_after = tx_pkt_cnt;
        if (pkt_cnt_after > pkt_cnt_before) begin
          $display("[%0t] HW Hndshk DB #%0d: PASS - %0d TX packet(s) (total: %0d)",
                   $time, db_idx, pkt_cnt_after - pkt_cnt_before, pkt_cnt_after);
          test_pass = test_pass + 1;
        end else begin
          $display("[%0t] HW Hndshk DB #%0d: FAIL - no TX packet after %0d cycles",
                   $time, db_idx, wait_cnt);
          test_fail = test_fail + 1;
        end
      end
    end

    // ==================================================================
    // Summary
    // ==================================================================
    #2000000;
    $display("");
    $display("========================================");
    $display("[%0t] Test Summary", $time);
    $display("  SW Doorbell iterations:  %0d", NUM_SW_DB);
    $display("  HW Hndshk iterations:    %0d", NUM_HW_DB);
    $display("  PASS: %0d", test_pass);
    $display("  FAIL: %0d", test_fail);
    $display("  Total TX packets: %0d", tx_pkt_cnt);
    $display("========================================");

    if (test_fail == 0 && tx_pkt_cnt > 0) begin
      $display("ALL TESTS PASSED");
    end else begin
      $display("SOME TESTS FAILED - check waveforms");
    end

    $finish;
  end

  // Timeout
  initial begin
    #2_000_000_000;  // 2s
    $display("[%0t] TIMEOUT", $time);
    $finish;
  end

endmodule
