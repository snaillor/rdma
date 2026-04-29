// rdma_core.v
// 文件名          : rdma_core.v
// 版本            : v1.0
// 描述            : RDMA 核心顶层模块，支持单 QP 的 RoCEv2 协议处理
//                   包含 RX 包解析、TX WQE 处理、QP 管理、响应处理等子系统
// Verilog 标准    : Verilog'2001

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
`timescale 1 ps / 1 ps

module rdma_core
    #(
        parameter C_NUM_QP = 1,
        parameter C_M_AXI_ADDR_WIDTH = 32,
        parameter C_M_AXI_ID_WIDTH = 1,
        parameter C_S_AXI_LITE_ADDR_WIDTH = 18,
        parameter C_EN_DEBUG_PORTS = 0,
        parameter C_EN_NVMOF_HW_HNDSHK    = 1,  // Enabled hardware handshake with NVMoF
        parameter C_MAX_SGL_DEPTH = 128,
        parameter C_MAX_WR_RETRY_DATA_BUF_DEPTH = 128,
        parameter C_EN_WR_RETRY_DATA_BUF = 0,
        parameter C_OSQ_PSN_WIDTH = 10
    )
   (
        input                                      m_axi_aclk,
        input                                      m_axi_aresetn,
        input                                      s_axi_lite_aclk,
        input                                      s_axi_lite_aresetn,

        // AXI Master I/F for rx packet handler for DDR

        // AXI Master I/F for rx packet handler

        // Ethernet controller I/F
        // AXI streaming master feeding to the RX packet handler
        input  wire                                rx_pkt_hndler_s_axis_tvalid,
        input  wire [511:0]                        rx_pkt_hndler_s_axis_tdata,
        input  wire [ 63:0]                        rx_pkt_hndler_s_axis_tkeep,
        input  wire                                rx_pkt_hndler_s_axis_tlast,
        input  wire [  0:0]                        rx_pkt_hndler_s_axis_tuser,

        // AXI Master I/F for wqe_proc engine
        output wire [C_M_AXI_ID_WIDTH-1:0]         wqe_proc_top_m_axi_awid,
        output wire [C_M_AXI_ADDR_WIDTH-1:0]       wqe_proc_top_m_axi_awaddr,
        output wire [7:0]                          wqe_proc_top_m_axi_awlen,
        output wire [2:0]                          wqe_proc_top_m_axi_awsize,
        output wire [1:0]                          wqe_proc_top_m_axi_awburst,
        output wire [3:0]                          wqe_proc_top_m_axi_awcache,
        output wire [2:0]                          wqe_proc_top_m_axi_awprot,
        output wire                                wqe_proc_top_m_axi_awvalid,
        input  wire                                wqe_proc_top_m_axi_awready,
        output wire [511:0]                        wqe_proc_top_m_axi_wdata,
        output wire [ 63:0]                        wqe_proc_top_m_axi_wstrb,
        output wire                                wqe_proc_top_m_axi_wlast,
        output wire                                wqe_proc_top_m_axi_wvalid,
        input  wire                                wqe_proc_top_m_axi_wready,
        output wire                                wqe_proc_top_m_axi_awlock,
        input  wire [C_M_AXI_ID_WIDTH-1 :0]        wqe_proc_top_m_axi_bid,
        input  wire [1:0]                          wqe_proc_top_m_axi_bresp,
        input  wire                                wqe_proc_top_m_axi_bvalid,
        output wire                                wqe_proc_top_m_axi_bready,
        output wire [C_M_AXI_ID_WIDTH-1 :0]        wqe_proc_top_m_axi_arid,
        output wire [C_M_AXI_ADDR_WIDTH-1:0]       wqe_proc_top_m_axi_araddr,
        output wire [7:0]                          wqe_proc_top_m_axi_arlen,
        output wire [2:0]                          wqe_proc_top_m_axi_arsize,
        output wire [1:0]                          wqe_proc_top_m_axi_arburst,
        output wire [3:0]                          wqe_proc_top_m_axi_arcache,
        output wire [2:0]                          wqe_proc_top_m_axi_arprot,
        output wire                                wqe_proc_top_m_axi_arvalid,
        input  wire                                wqe_proc_top_m_axi_arready,
        input  wire [C_M_AXI_ID_WIDTH-1 :0]        wqe_proc_top_m_axi_rid,
        input  wire [511:0]                        wqe_proc_top_m_axi_rdata,
        input  wire [1:0]                          wqe_proc_top_m_axi_rresp,
        input  wire                                wqe_proc_top_m_axi_rlast,
        input  wire                                wqe_proc_top_m_axi_rvalid,
        output wire                                wqe_proc_top_m_axi_rready,
        output wire                                wqe_proc_top_m_axi_arlock,

        // AXI Master I/F for wqe_proc engine
        output wire [C_M_AXI_ID_WIDTH-1:0]         wqe_proc_wr_ddr_m_axi_awid,
        output wire [C_M_AXI_ADDR_WIDTH-1:0]       wqe_proc_wr_ddr_m_axi_awaddr,
        output wire [7:0]                          wqe_proc_wr_ddr_m_axi_awlen,
        output wire [2:0]                          wqe_proc_wr_ddr_m_axi_awsize,
        output wire [1:0]                          wqe_proc_wr_ddr_m_axi_awburst,
        output wire [3:0]                          wqe_proc_wr_ddr_m_axi_awcache,
        output wire [2:0]                          wqe_proc_wr_ddr_m_axi_awprot,
        output wire                                wqe_proc_wr_ddr_m_axi_awvalid,
        input  wire                                wqe_proc_wr_ddr_m_axi_awready,
        output wire [511:0]                        wqe_proc_wr_ddr_m_axi_wdata,
        output wire [ 63:0]                        wqe_proc_wr_ddr_m_axi_wstrb,
        output wire                                wqe_proc_wr_ddr_m_axi_wlast,
        output wire                                wqe_proc_wr_ddr_m_axi_wvalid,
        input  wire                                wqe_proc_wr_ddr_m_axi_wready,
        output wire                                wqe_proc_wr_ddr_m_axi_awlock,
        input  wire [C_M_AXI_ID_WIDTH-1 :0]        wqe_proc_wr_ddr_m_axi_bid,
        input  wire [1:0]                          wqe_proc_wr_ddr_m_axi_bresp,
        input  wire                                wqe_proc_wr_ddr_m_axi_bvalid,
        output wire                                wqe_proc_wr_ddr_m_axi_bready,
        output wire [C_M_AXI_ID_WIDTH-1 :0]        wqe_proc_wr_ddr_m_axi_arid,
        output wire [C_M_AXI_ADDR_WIDTH-1:0]       wqe_proc_wr_ddr_m_axi_araddr,
        output wire [7:0]                          wqe_proc_wr_ddr_m_axi_arlen,
        output wire [2:0]                          wqe_proc_wr_ddr_m_axi_arsize,
        output wire [1:0]                          wqe_proc_wr_ddr_m_axi_arburst,
        output wire [3:0]                          wqe_proc_wr_ddr_m_axi_arcache,
        output wire [2:0]                          wqe_proc_wr_ddr_m_axi_arprot,
        output wire                                wqe_proc_wr_ddr_m_axi_arvalid,
        input  wire                                wqe_proc_wr_ddr_m_axi_arready,
        input  wire [C_M_AXI_ID_WIDTH-1 :0]        wqe_proc_wr_ddr_m_axi_rid,
        input  wire [511:0]                        wqe_proc_wr_ddr_m_axi_rdata,
        input  wire [1:0]                          wqe_proc_wr_ddr_m_axi_rresp,
        input  wire                                wqe_proc_wr_ddr_m_axi_rlast,
        input  wire                                wqe_proc_wr_ddr_m_axi_rvalid,
        output wire                                wqe_proc_wr_ddr_m_axi_rready,
        output wire                                wqe_proc_wr_ddr_m_axi_arlock,

        // AXI slave interface to WQE proc module to have the AXI DMA read the
        // SGLs from the BRAM inside

        //AXI streaming interface signals to and from WQE proc CRC process
        //engine
        output wire [511 : 0]                      wqe_proc_top_m_axis_tdata,
        output wire [63:0]                         wqe_proc_top_m_axis_tkeep,
        output wire                                wqe_proc_top_m_axis_tvalid,
        input  wire                                wqe_proc_top_m_axis_tready,
        output wire                                wqe_proc_top_m_axis_tlast,

    // AXI Master signals from resp_handler module
        output wire   [0:0]                        resp_hndler_m_axi_awid,
        output wire   [31:0]                       resp_hndler_m_axi_awaddr,
        output wire   [7:0]                        resp_hndler_m_axi_awlen,
        output wire   [2:0]                        resp_hndler_m_axi_awsize,
        output wire   [1:0]                        resp_hndler_m_axi_awburst,
        output wire   [3:0]                        resp_hndler_m_axi_awcache,
        output wire   [2:0]                        resp_hndler_m_axi_awprot,
        output wire                                resp_hndler_m_axi_awvalid,
        input  wire                                resp_hndler_m_axi_awready,
        output wire   [511:0]                      resp_hndler_m_axi_wdata,
        output wire   [512/8-1:0]                  resp_hndler_m_axi_wstrb,
        output wire                                resp_hndler_m_axi_wlast,
        output wire                                resp_hndler_m_axi_wvalid,
        input  wire                                resp_hndler_m_axi_wready,
        output wire                                resp_hndler_m_axi_awlock,
        input  wire   [0 :0]                       resp_hndler_m_axi_bid,
        input  wire   [1:0]                        resp_hndler_m_axi_bresp,
        input  wire                                resp_hndler_m_axi_bvalid,
        output wire                                resp_hndler_m_axi_bready,
        output wire   [0:0]                        resp_hndler_m_axi_arid,
        output wire   [31:0]                       resp_hndler_m_axi_araddr,
        output wire   [7:0]                        resp_hndler_m_axi_arlen,
        output wire   [2:0]                        resp_hndler_m_axi_arsize,
        output wire   [1:0]                        resp_hndler_m_axi_arburst,
        output wire   [3:0]                        resp_hndler_m_axi_arcache,
        output wire   [2:0]                        resp_hndler_m_axi_arprot,
        output wire                                resp_hndler_m_axi_arvalid,
        input  wire                                resp_hndler_m_axi_arready,
        input  wire   [0:0]                        resp_hndler_m_axi_rid,
        input  wire   [511:0]                      resp_hndler_m_axi_rdata,
        input  wire   [1:0]                        resp_hndler_m_axi_rresp,
        input  wire                                resp_hndler_m_axi_rlast,
        input  wire                                resp_hndler_m_axi_rvalid,
        output wire                                resp_hndler_m_axi_rready,
        output wire                                resp_hndler_m_axi_arlock,

        // AXI lite interface

        input  wire  [C_S_AXI_LITE_ADDR_WIDTH-1:0] s_axi_lite_awaddr,
        output wire                                s_axi_lite_awready,
        input  wire                                s_axi_lite_awvalid,

        input  wire  [C_S_AXI_LITE_ADDR_WIDTH-1:0] s_axi_lite_araddr,
        output wire                                s_axi_lite_arready,
        input  wire                                s_axi_lite_arvalid,

        input  wire  [31:0]                        s_axi_lite_wdata,
        input  wire  [3:0]                         s_axi_lite_wstrb,
        output wire                                s_axi_lite_wready,
        input  wire                                s_axi_lite_wvalid,

        output wire  [31:0]                        s_axi_lite_rdata,
        output wire  [1:0]                         s_axi_lite_rresp,
        input  wire                                s_axi_lite_rready,
        output wire                                s_axi_lite_rvalid,

        output wire  [1:0]                         s_axi_lite_bresp,
        input  wire                                s_axi_lite_bready,
        output wire                                s_axi_lite_bvalid,

// AXI Master signals
        output wire   [0:0]                        qp_mgr_m_axi_awid,
        output wire   [31:0]                       qp_mgr_m_axi_awaddr,
        output wire   [7:0]                        qp_mgr_m_axi_awlen,
        output wire   [2:0]                        qp_mgr_m_axi_awsize,
        output wire   [1:0]                        qp_mgr_m_axi_awburst,
        output wire   [3:0]                        qp_mgr_m_axi_awcache,
        output wire   [2:0]                        qp_mgr_m_axi_awprot,
        output wire                                qp_mgr_m_axi_awvalid,
        input  wire                                qp_mgr_m_axi_awready,
        output wire   [511:0]                      qp_mgr_m_axi_wdata,
        output wire   [512/8-1:0]                  qp_mgr_m_axi_wstrb,
        output wire                                qp_mgr_m_axi_wlast,
        output wire                                qp_mgr_m_axi_wvalid,
        input  wire                                qp_mgr_m_axi_wready,
        output wire                                qp_mgr_m_axi_awlock,
        input  wire   [0 :0]                       qp_mgr_m_axi_bid,
        input  wire   [1:0]                        qp_mgr_m_axi_bresp,
        input  wire                                qp_mgr_m_axi_bvalid,
        output wire                                qp_mgr_m_axi_bready,
        output wire   [0:0]                        qp_mgr_m_axi_arid,
        output wire   [31:0]                       qp_mgr_m_axi_araddr,
        output wire   [7:0]                        qp_mgr_m_axi_arlen,
        output wire   [2:0]                        qp_mgr_m_axi_arsize,
        output wire   [1:0]                        qp_mgr_m_axi_arburst,
        output wire   [3:0]                        qp_mgr_m_axi_arcache,
        output wire   [2:0]                        qp_mgr_m_axi_arprot,
        output wire                                qp_mgr_m_axi_arvalid,
        input  wire                                qp_mgr_m_axi_arready,
        input  wire   [0:0]                        qp_mgr_m_axi_rid,
        input  wire   [511:0]                      qp_mgr_m_axi_rdata,
        input  wire   [1:0]                        qp_mgr_m_axi_rresp,
        input  wire                                qp_mgr_m_axi_rlast,
        input  wire                                qp_mgr_m_axi_rvalid,
        output wire                                qp_mgr_m_axi_rready,
        output wire                                qp_mgr_m_axi_arlock,

  // Hardware handshake ports for NVMof (only enabled if C_EN_NVMOF_HW_HNDSHK is set to 1)
        output wire                                resp_hndler_o_send_cq_db_cnt_valid,
        output wire [9:0 ]                         resp_hndler_o_send_cq_db_addr,
        output wire [31:0]                         resp_hndler_o_send_cq_db_cnt,
        input  wire                                resp_hndler_i_send_cq_db_rdy,

    input wire  [15:0]                             i_qp_rq_cidb_hndshk,
    input wire  [31:0]                             i_qp_rq_cidb_wr_addr_hndshk,
    input wire                                     i_qp_rq_cidb_wr_valid_hndshk,
    output wire                                    o_qp_rq_cidb_wr_rdy,

    input wire  [15:0]                                i_qp_sq_pidb_hndshk,
    input wire  [31:0]                                i_qp_sq_pidb_wr_addr_hndshk,
    input wire                                        i_qp_sq_pidb_wr_valid_hndshk,
    output wire                                       o_qp_sq_pidb_wr_rdy,

 //rx_pkt_hndler
       output wire [31:0]                         rx_pkt_hndler_o_rq_db_data,
       output wire [9:0]                          rx_pkt_hndler_o_rq_db_addr,
       output wire                                rx_pkt_hndler_o_rq_db_data_valid,
       input wire                                 rx_pkt_hndler_i_rq_db_rdy,

       output wire                                rdma_core_intr0,
       output wire                                rdma_core_intr1,
       output wire                                rdma_core_intr2,
       output wire                                rdma_core_intr3,
       output wire                                rdma_core_intr4,
       output wire                                rdma_core_intr5,
       output wire                                rdma_core_intr6,
       output wire                                rdma_core_intr7,
       output wire                                rdma_core_intr8,

      //Debug counter enablement signals
       output wire                                o_global_dbg_cnt_en,
       output wire                                o_global_dbg_cnt_clr
    );
   `include "rdma_macros.vh"

        localparam C_QP_INDX_WIDTH = (clog2(C_NUM_QP) == 0) ? 1 : clog2(C_NUM_QP);
        localparam OS_Q_DEPTH = 16;
        localparam OS_Q_INDX_WIDTH = 4;
        localparam NUM_CYCLES_4US = 1024;// Number of clock cycles that make 4 us (for 125Mhz clk period it is 512)

  wire                                qp_mgr_o_rdma_en;                      // RDMA interface enable from RDMA registers
  wire                                qp_mgr_o_rdma_adv_conf_errbuf_overwr_en; // Advance config error buffer overwrite enable
  wire [3:0]			      qp_mgr_o_rdma_adv_base_cnt;            // For timeout count for 4us consideration
  wire                                qp_mgr_o_err_buf_en;                    // Enable validaion error packets to go to error buffer
  wire [1:0]                          qp_mgr_o_tx_ack_gen;                    // TX side ack generation setting
  wire                                qp_mgr_o_depkt_bypass_en;               // RDMA interface bypass feature enable
  wire [C_QP_INDX_WIDTH-1:0]          qp_mgr_o_num_qp_en;                      // Number of QPs enabled
  wire [47:0]                         qp_mgr_o_mac_src_addr;                 // Ethernet MAC destination (own) address from RDMA registers
  wire [31:0]                         qp_mgr_o_ipv4_src_addr;                // IPv4 destination (own) address from RDMA registers
  wire [127:0]                        qp_mgr_o_ipv6_src_addr;                // IPv6 destination (own) address form RDMA registers
  wire [31:0]                         qp_mgr_o_data_buf_ba;                  // Write retry buffer base address
  wire [15:0]                         qp_mgr_o_data_buf_sz_num_bufs;         // number of write retry buffers allocated
  wire [15:0]                         qp_mgr_o_data_buf_sz_buf_sz;           // each write retry buffer size

  wire                                rx_pkt_hndler_o_ib_pkt_hdr_valdn_err_intr;     // Inbound packet header validation error interrupt
  wire                                rx_pkt_hndler_o_mad_pkt_rcvd_intr;             // MAD packet received interrupt
  wire                                rx_pkt_hndler_o_bypass_pkt_rcvd_intr;          // Incoming bypass packet received interrupt
  wire                                rx_pkt_hndler_o_rnr_nack_gen_intr;
  wire                                qp_mgr_o_intr_clr_pkt_valdn_err;
  wire                                qp_mgr_o_intr_clr_mad_pkt_rcvd;
  wire                                qp_mgr_o_intr_clr_bypass_pkt_rcvd;
  wire                                qp_mgr_o_intr_clr_rnr_nak_gen;
  wire [C_NUM_QP-1:0]                 rx_pkt_hndler_o_rq_full;                       // Receive Q full for each QP
  wire [C_NUM_QP-1:0]                 rx_pkt_hndler_o_cq_full;                       // Completion Q full for each QP
  wire [C_NUM_QP-1:0]                 rx_pkt_hndler_o_rq_empty;                      // Receive Q empty for each QP
  wire [C_NUM_QP-1:0]                 resp_hndler_o_osq_empty;                      // Outstanding Q empty for each QP
  wire [C_NUM_QP-1:0]                 resp_hndler_o_qp_retried;                     // QP retried for each QP
  wire [31:0]                         qp_mgr_o_bypass_buf_ba;
  wire [15:0]                         qp_mgr_o_bypass_buf_sz_num_bufs;
  wire [15:0]                         qp_mgr_o_bypass_buf_sz_buf_sz;
  wire [15:0]                         rx_pkt_hndler_o_bypass_buf_wrptr;
  wire [31:0]                         qp_mgr_o_err_pkt_buf_ba;
  wire [15:0]                         qp_mgr_o_err_pkt_buf_sz_num_bufs;
  wire [15:0]                         qp_mgr_o_err_pkt_buf_sz_buf_sz;
  wire [15:0]                         rx_pkt_hndler_o_ib_send_pkt_cnt;               // Incoming send request packets count
  wire [15:0]                         rx_pkt_hndler_o_ib_ack_pkt_cnt;                // Incoming acknowledgement packets count
  wire [15:0]                         rx_pkt_hndler_o_ib_rres_pkt_cnt;               // Incoming read response packets count
  wire [15:0]                         rx_pkt_hndler_o_ib_qp1_pkt_cnt;                // Incoming QP1 packet count
  wire [15:0]                         rx_pkt_hndler_o_ib_inv_pkt_cnt;                // Incoming invalid packet count
  wire [15:0]                         rx_pkt_hndler_o_ib_dupl_pkt_cnt;               // Incoming duplicate packet count
  wire [7:0]                          rx_pkt_hndler_o_last_ib_pkt_opcode;            // Last incoming packet OPCODE
  wire [7:0]                          rx_pkt_hndler_o_last_ib_pkt_dest_qpid;         // Last incoming packet DEST_QP
  wire [15:0]                         rx_pkt_hndler_o_last_ib_pkt_psn;               // Last incoming packet PSN
  wire [C_NUM_QP-1:0]                 resp_hndler_o_osq_full;                      // Outstanding entry Q is full for each QP
  wire [C_NUM_QP -1:0]                rx_pkt_hndler_o_qp_pkt_rcvd_intr_sts;
  wire [C_QP_INDX_WIDTH-1:0]          rx_pkt_hndler_o_query_qpid;                    // Index of QP for which information queried
  wire [31:0]                         qp_mgr_o_tx_hdr_buf_ba;
  wire [15:0]                         qp_mgr_o_tx_hdr_buf_sz_num_hdrs;
  wire [15:0]                         qp_mgr_o_tx_hdr_buf_sz_buf_sz;
  wire [31:0]                         qp_mgr_o_tx_sgl_buf_ba;
  wire [15:0]                         qp_mgr_o_tx_sgl_buf_sz_num_sgls;
  wire [15:0]                         qp_mgr_o_tx_sgl_buf_sz_buf_sz;
  wire                                qp_mgr_o_rdma_conf_ipver;
  wire [15:0]                         qp_mgr_o_rdma_udp_src_port;
  wire [C_NUM_QP -1:0]                resp_hndlr_o_qp_rnr_nacked;

  wire                                qp_mgr_o_qp_conf_valid_wqe_proc;
  wire                                qp_mgr_o_qp_conf_valid_rx_pkt;
  wire  [31:0]                        qp_mgr_o_qp_conf;        // QP configuration

  wire                                rx_pkt_hndler_o_qpm_req_rq_buf_ba;
  wire                                qp_mgr_o_qp_rq_ba_valid;
  wire  [23:0]                        qp_mgr_o_qp_rq_ba;

  wire                                resp_hndler_o_qp_cq_ba_req;
  wire                                qp_mgr_o_qp_cq_ba_valid;
  wire  [31:0]                        qp_mgr_o_qp_cq_ba;

  wire                                rx_pkt_hndler_o_qpm_req_rq_wrptr_db_add;
  wire                                qp_mgr_o_qp_rq_wrptrdb_add_valid;
  wire  [31:0]                        qp_mgr_o_qp_rq_wrptrdb_add;

  wire                                resp_hndler_o_qp_cq_hdptr_req;
  wire                                qp_mgr_o_qp_cq_hdptr_valid;
  wire  [15:0]                        qp_mgr_o_qp_cq_hdptr;
  wire  [15:0]                        resp_hndler_o_qp_cq_hdptr;
  wire                                resp_hndler_o_qp_cq_hdptr_wrn;

  wire                                rx_pkt_hndler_o_qpm_req_rq_ci_db;
  wire                                qp_mgr_o_qp_rq_cidb_valid;
  wire  [31:0]                        qp_mgr_o_qp_rq_cidb;

  wire                                rx_pkt_hndler_o_qpm_req_q_depth;
  wire                                qp_mgr_o_qp_rq_depth_valid;
  wire   [15:0]                       qp_mgr_o_qp_rq_depth;

  wire                                rx_pkt_hndler_o_qpm_req_last_rq_req;
  wire                                rx_pkt_hndler_o_qpm_rw_last_rq_req;
  wire [31:0]                         rx_pkt_hndler_o_last_rq_req;
  wire  [31:0]                        qp_mgr_o_qp_last_rq;
  wire                                qp_mgr_o_qp_last_rq_valid;

  wire                                qp_mgr_o_intr_clr_wqe_cmpl;
  wire                                qp_mgr_o_intr_clr_fatal_err;
  wire                                qp_mgr_o_intr_en_wqe_cmpl;
  wire                                resp_hndler_o_intr_wqe_cmpl;

  wire                                rx_pkt_hndler_o_qpm_req_dest_qp_conf;
  wire                                qp_mgr_o_qp_dest_qpid_valid_wqe_proc;
  wire                                qp_mgr_o_qp_dest_qpid_valid_rx_pkt;
  wire  [23:0]                        qp_mgr_o_qp_dest_qpid;

  wire                                rx_pkt_hndler_o_qpm_req_stat_qp_msn;
  wire                                rx_pkt_hndler_o_qpm_rw_stat_qp_msn;
  wire [23:0]                         rx_pkt_hndler_o_stat_qp_msn;                   // last valid inbound request
  wire  [23:0]                        qp_mgr_o_qp_stat_msn; // Expected MSN for Qp incoming messages write data from hdr validation
  wire                                qp_mgr_o_qp_stat_msn_valid;

  wire [31:0]                         rx_pkt_hndler_o_timeout;                       // inbound response current RNR-NAK count, timeout value,
  wire  [31:0]                        qp_mgr_o_qp_timeout;
  wire  [C_NUM_QP-1:0]                qp_mgr_o_qp_disable_pulse;

  wire  [31:0]                        qp_mgr_o_qp_timeout_per_qp;

  wire                                qpm_wqe_fifo_empty;
  wire  [511:0]                       qpm_wqe_data;             //64B of WQE

  // HW Doorbell WQE template wires from qp_mgr (must be declared before use)
  wire [31:0] qp_mgr_o_hw_wqe_remote_addr_lo;
  wire [31:0] qp_mgr_o_hw_wqe_remote_addr_hi;
  wire [31:0] qp_mgr_o_hw_wqe_rkey;
  wire [31:0] qp_mgr_o_hw_wqe_local_addr;
  wire [7:0]  qp_mgr_o_hw_wqe_opcode;
  wire [15:0] qp_mgr_o_hw_wqe_wrid;

  // WQE path: directly from qp_mgr FIFO
  wire [511:0] wqe_data_to_proc = qpm_wqe_data;
  wire         wqe_empty_to_proc = qpm_wqe_fifo_empty;
  wire         wqe_pop_to_proc;
  wire         qpm_wqe_pop_int = wqe_pop_to_proc;

  wire                                qp_mgr_o_qp_mac_remote_addrl_valid;

  wire                                qp_mgr_o_qp_ip_remote_addr1_valid;

  wire                                qp_mgr_o_qp_mac_dest_addrl_valid;
  wire  [31:0]                        qp_mgr_o_qp_mac_dest_addrl;
  wire                                qp_mgr_o_qp_mac_dest_addrm_valid;
  wire  [31:0]                        qp_mgr_o_qp_mac_dest_addrm;
  wire                                qp_mgr_o_qp_ip_dest_addr1_valid;
  wire  [31:0]                        qp_mgr_o_qp_ip_dest_addr1;
  wire                                wqe_proc_top_o_reg_rd_en;
  wire                                wqe_proc_top_o_reg_rd_en_s;
  wire                                wqe_proc_top_o_reg_wr_en;

  wire                                qp_mgr_o_qp_adv_conf_valid;
  wire  [31:0]                        qp_mgr_o_qp_adv_conf;        // QP advance configuration
  wire                                qp_mgr_o_qp_sq_psn_valid;
  wire                                qp_mgr_o_qp_sq_psn_wqe_valid;
  wire  [23:0]                        qp_mgr_o_qp_sq_psn;
  wire  [23:0]                        wqe_proc_top_reg_sq_psn;
  wire  [23:0]                        qp_mgr_o_qp_sq_ssn;
  wire  [23:0]                        wqe_proc_top_reg_sq_ssn;
  wire  [C_NUM_QP -1:0]               wqe_proc_top_o_osq_nacked_resp;
  wire                                rx_pkt_hndler_o_qpm_req_sq_psn;

  wire  [C_QP_INDX_WIDTH-1:0]         rx_pkt_wqe_proc_ob_rsp_qpid;                   // Destination QP ID for which response packet is targetted
  wire  [23:0]                        rx_pkt_wqe_proc_ob_rsp_psn;                    // PSN field value in response packet BTH Header
  wire  [1:0]                         rx_pkt_wqe_proc_ob_rsp_type;                   // 2'b00 - ACK, 2'b01 - RNR-NAK, 2'b10 - rsvd, 2'b11 - NAK
  wire  [4:0]                         rx_pkt_wqe_proc_ob_rsp_crdt_cnt;               // Credit count used to implement End-to-End flow control
  wire  [4:0]                         rx_pkt_wqe_proc_ob_rsp_rnr_nak_tval;           // If resp_type is RNR-NAK, associated time-out vale
  wire  [4:0]                         rx_pkt_wqe_proc_ob_rsp_nak_code;               // If resp_type is NAK, associated NAK code, see table.44
  wire  [23:0]                        rx_pkt_wqe_proc_ob_rsp_msn;                    // MSN field in AETH Header of response packet
  wire                                rx_pkt_wqe_proc_ob_rsp_req;                    // Level to WQE Processor to indicates that new response to schedule
  wire                                rx_pkt_wqe_proc_ob_rsp_expl_ack;               // Level to WQE Processor to indicates that new response to schedule
  wire                                wqe_proc_o_bres_fifo_full;                     // Acknowledgement that new response in schedule queue

  wire  [7:0]                         rx_pkt_wqe_proc_aeth_syndrome;

  wire  [C_QP_INDX_WIDTH-1:0]         wqe_proc_os_wqe_qpid;                      // QP ID of WQE
  wire  [7:0]                         wqe_proc_os_wqe_opcode;                    // BTH.Opcode of outbound request
  wire  [4:0]                         wqe_proc_o_wqe_qp_to;                    // BTH.Opcode of outbound request
  wire  [15:0]                        wqe_proc_os_wqe_wrid;                      // Work request ID of outbound request
  wire  [14:0]                        wqe_proc_os_wqe_data_bufid;                // Data buffer ID for RDMA WRITES
  wire                                wqe_proc_os_wqe_retried;                   // Retried work request
  wire  [23:0]                        wqe_proc_os_wqe_send_psn;                  // PSN of most recent request
  wire  [23:0]                        wqe_proc_os_wqe_send_first_psn;            // PSN of most recent request
  wire  [23:0]                        wqe_proc_os_wqe_send_msn;                  // PSN of most recent request
  wire                                wqe_proc_os_wqe_explicit_ack_req;          // Explicit acknowledgement requirement on outbound requests
  wire                                wqe_proc_os_wqp_req;                       // request from WQE Processor to push WQE
  wire                                wqe_proc_os_wqp_rdy;                       // response to WQE Processor; 0 - busy; 1 - completed
  wire  [C_NUM_QP -1:0]               wqe_proc_os_fifo_full;                     //FIFO full signal from outstanding fifo
  wire                                resp_hndler_freeup_data_buf;               // Freeup RDMA WRITE DATA buffer
  wire  [14:0]                        resp_hndler_freeup_data_bufid;             // BUffer ID to be freed up
  wire  [31:0]                        resp_hndler_o_resp_hndler_sts;
  wire  [31:0]                        resp_hndler_o_stat_retry_count;

  wire  [C_QP_INDX_WIDTH -1: 0]       wqe_proc_top_o_qp_id;  // index to be replaced during WQE proc integration
  wire  [OS_Q_INDX_WIDTH : 0]         os_num_vld_entries;
  wire                                resp_hndler_o_qp_cq_depth_req;
  wire                                qp_mgr_o_qp_cq_depth_valid;
  wire  [15:0]                        qp_mgr_o_qp_cq_depth;
  wire  [C_QP_INDX_WIDTH -1:0]        resp_hndler_o_qp_conf_qp_idx;
  wire  [C_NUM_QP - 1 : 0]            resp_handler_wqe_proc_osq_nacked;
  wire                                resp_handler_o_qp_sq_ba_req;
  wire                                qp_mgr_o_qp_sq_ba_valid;
  wire [31:0]                         qp_mgr_o_qp_sq_ba;

  wire                                resp_hndler_o_qp_sq_cmpldb_addr_req;
  wire                                qp_mgr_o_qp_sq_cmpldb_add_valid;
  wire  [31:0]                        qp_mgr_o_qp_sq_cmpldb_add;

  wire [C_QP_INDX_WIDTH -1 :0]        resp_hndler_o_retransmit_qpid;         // QP id for this retransmission is required
  wire                                resp_hndler_o_retransmit_reqd;         // Retransmission is required
  wire [23:0]                         resp_hndler_o_psn_to_retry;
  wire [23:0]                         resp_hndler_o_ssn_to_retry;
  wire [C_NUM_QP -1:0]                resp_hndler_o_osq_almost_full;

  wire [C_QP_INDX_WIDTH -1: 0]        qp_idx_TBD;

  wire                                rx_pkt_hndler_o_qpm_req_rq_buf_ca;
  wire                                rx_pkt_hndler_o_qpm_rw_rq_buf_ca;
  wire [23:0]                         qp_mgr_o_qp_stat_rq_buf_ca;
  wire                                qp_mgr_o_qp_stat_rq_buf_ca_valid;
  wire [23:0]                         rx_pkt_hndler_o_rq_buf_ca;

  wire [C_QP_INDX_WIDTH -1:0]         rx_pkt_hndler_o_qp_index_mpsnbuf;

  wire                                rx_pkt_hndler_o_max_epsn_req;
  wire                                resp_hndler_o_mpsn_buf_valid;

  wire [C_NUM_QP-1:0]                 resp_hndler_o_mpsnbuf_empty;
  wire                                rx_pkt_hndler_o_mpsnbuf_pop;

  wire [C_OSQ_PSN_WIDTH-1:0]          resp_hndler_o_max_epsn;
  wire [63:0]                         resp_hndler_o_local_addr;
  wire [23:0]                         resp_hndler_o_trnsfr_length;
  wire [15:0]                         resp_hndler_o_inc_nack_cnt;

  wire [C_QP_INDX_WIDTH-1:0]          rx_pkt_hndler_o_qp_index_acknack;
  wire                                rx_pkt_hndler_o_acknack_valid;
  wire [ 7:0]                         rx_pkt_hndler_o_acknacked_syndrome;
  wire [23:0]                         rx_pkt_hndler_o_acknacked_msn;
  wire [ 1:0]                         rx_pkt_hndler_o_acknacked_opcode;
  wire [23:0]                         rx_pkt_hndler_o_acknacked_psn;

  wire [C_NUM_QP-1:0]                 resp_hndler_o_retry_timer_expired;


  wire                                qp_mgr_o_intr_en_pkt_valdn_err;
  wire                                qp_mgr_o_intr_en_mad_pkt_rcvd;
  wire                                qp_mgr_o_intr_en_bypass_pkt_rcvd;
  wire                                qp_mgr_o_intr_clr_qp_pkt_rcvd;
  wire                                qp_mgr_o_intr_en_rnr_nak_gen;

  wire                                rx_pkt_hndler_o_qpm_req_stat_nak;
  wire                                rx_pkt_hndler_o_qpm_rw_stat_nak;
  wire [ 9:0]                         rx_pkt_hndler_o_stat_nak;
  wire                                resp_hndler_o_qp_stat_nak_valid;
  wire  [9:0]                         resp_hndler_o_qp_stat_nak;

  wire                                qp_mgr_o_halt;
  wire [C_QP_INDX_WIDTH -1 :0]        qp_mgr_o_halted_qpid;
  wire                                wqe_proc_i_wqe_halted;

  wire                                rx_pkt_hndler_o_qpm_req_stat_resp_psn;
  wire                                rx_pkt_hndler_o_qpm_rw_stat_resp_psn;
  wire [23:0]                         qp_mgr_o_qp_stat_resp_psn;
  wire [23:0]                         rx_pkt_hndler_o_qp_stat_resp_psn;
  wire                                qp_mgr_o_qp_stat_resp_psn_valid;
  wire [C_NUM_QP -1: 0]               rx_pkt_hndler_o_qp_fatal;
  wire                                rx_pkt_hndler_o_qp_pkt_rcvd_intr;
  wire [C_NUM_QP -1:0]                qp_mgr_o_qp_clr_fatal_err;

  wire [C_M_AXI_ADDR_WIDTH-1:0]       qp_mgr_in_errsts_q_ba;
  wire [15:0]                         qp_mgr_in_errsts_q_sz;
  wire [15:0]                         rx_pkt_hndler_in_errsts_q_wrptr;

  wire [C_M_AXI_ADDR_WIDTH-1:0]       out_errsts_q_ba;
  wire [15:0]                         out_errsts_q_sz;
  wire [15:0]                         out_errsts_q_wrptr;
  wire                                intr_en_ill_opc_in_sq;
  wire                                intr_clr_ill_opc_in_sq;
  wire                                ill_opc_in_sq_intr;
  wire [15:0]                         wqe_out_rdwr_pkt_cnt;
  wire [15:0]                         wqe_out_ack_pkt_cnt;
  wire [15:0]                         wqe_out_mad_pkt_cnt;

  wire                                rx_pkt_hndler_o_fatal_err_intr;
  wire                                qp_mgr_o_intr_en_fatal_err;

  wire                                resp_hndler_o_qp_conf_req;
  wire                                qp_mgr_o_qp_conf_valid_resp_hndl;

  wire [31:0]                         qp_mgr_o_rx_pkt_hndl_dbg_ctrl;
  wire [31:0]                         rx_pkt_hndler_o_debug_bus;
  wire [31:0]                         wqe_proc_status_out;
  wire [31:0]                         last_out_pkt_info;

  wire [C_NUM_QP -1:0]                resp_hndlr_i_qp_wq_cmpl_intr_sts;
  wire [C_NUM_QP -1:0]                qp_mgr_o_rq_intr_sts_clr;
  wire [C_NUM_QP -1:0]                qp_mgr_o_cq_intr_sts_clr;

  wire [1:0]                          qp_mgr_o_flow_credits;

  wire [31:0]                         rx_pkt_hndler_o_pkt_all_cnt;
  wire [31:0]                         rx_pkt_hndler_o_pkt_disc_cnt;

  wire [15:0]                         rx_pkt_hndler_o_inc_nack_cnt;
  wire [15:0]                         rx_pkt_hndler_o_out_nack_cnt;


  wire                                rx_pkt_hndler_o_qpm_req_rq_wrptr_db;
  wire                                rx_pkt_hndler_o_qpm_rw_rq_wrptr_db;
  wire [15:0]                         rx_pkt_hndler_o_rq_wrptr_db;
  wire [15:0]                         qp_mgr_o_rq_pi_db;
  wire                                qp_mgr_o_qp_rq_pi_db_valid;

  wire [15:0] qp_mgr_o_rq_pi_db_hw_hndshk;
  wire [9:0]  qp_mgr_o_connect_io_qp_rq_pi_db_wptr;
  wire        qp_mgr_o_hw_hndshk_disable_to_0;

  wire [23:0] qp_mgr_o_qp_stat_ret_sq_psn;
  wire        qp_mgr_o_qp_stat_ret_sq_psn_valid;

  wire [31:0] rx_pkt_hndler_o_ipg_cntr_min;

  wire [C_QP_INDX_WIDTH-1:0] rx_pkt_hndler_o_qp_req_conf_idx;
  wire [C_QP_INDX_WIDTH-1:0] rx_pkt_hndler_o_qp_rsp_conf_idx;

  wire [31:0] qp_mgr_o_qp_conf_replica;
  wire qp_mgr_o_qp_conf_replica_valid;
  wire rx_pkt_hndler_o_qp_req_conf_en;

  wire rx_pkt_hndler_o_qp_rsp_conf_en;

  wire rx_pkt_hndler_req_remote_qp_mac_addr_en;
  wire rx_pkt_hndler_req_remote_qp_ip_addr_en;

  wire rx_pkt_hndler_rsp_remote_qp_mac_addr_en;
  wire rx_pkt_hndler_rsp_remote_qp_ip_addr_en;

  wire [31:0] qp_mgr_o_qp_mac_remote_addrl_replica;
  wire [31:0] qp_mgr_o_qp_mac_remote_addrm_replica;

  wire [31:0] qp_mgr_o_qp_ip_remote_addr1_replica;

  wire [31:0] qp_mgr_o_resp_err_pkt_buf_ba;
  wire [15:0] qp_mgr_o_resp_err_pkt_buf_sz_num_bufs;
  wire [15:0] qp_mgr_o_resp_err_pkt_buf_sz_buf_sz;
  wire [31:0] rx_pkt_hndler_o_qp_timeout_per_qp;

  wire rx_pkt_hndler_o_connect_io_qp_rq_pi_db_rdy;

  //Debug counter signals
  wire [15:0] wqe_proc_idle_cnt;
  wire [15:0] wqe_proc_rd_wqe_cnt;
  wire [15:0] wqe_proc_rd_q_info_cnt;
  wire [15:0] wqe_proc_wait0_cnt;
  wire [15:0] wqe_proc_ip_chksum_cnt;
  wire [15:0] wqe_proc_hdr_gen_cnt;
  wire [15:0] wqe_proc_hdr_sto_cnt;
  wire [15:0] wqe_proc_hdr_sgl_buf_full_cnt;
  wire [15:0] wqe_proc_wr_retry_buf_full_cnt;

  wire        wqe_proc_dma_in_idle;

  wire [31:0] resp_hndler_o_send_cq_db_addr_int;
  assign resp_hndler_o_send_cq_db_addr = resp_hndler_o_send_cq_db_addr_int [9:0];

  wire                       rx_pkt_hndler_o_rd_rsp_wr_cmpltd;
  wire [C_QP_INDX_WIDTH-1:0] rx_pkt_hndler_o_rsp_qp_id;

  assign rdma_core_intr0 = rx_pkt_hndler_o_ib_pkt_hdr_valdn_err_intr;
  assign rdma_core_intr1 = rx_pkt_hndler_o_mad_pkt_rcvd_intr;
  assign rdma_core_intr2 = rx_pkt_hndler_o_bypass_pkt_rcvd_intr;
  assign rdma_core_intr3 = rx_pkt_hndler_o_rnr_nack_gen_intr;
  assign rdma_core_intr4 = resp_hndler_o_intr_wqe_cmpl;
  assign rdma_core_intr5 = ill_opc_in_sq_intr;
  assign rdma_core_intr6 = rx_pkt_hndler_o_qp_pkt_rcvd_intr;
  assign rdma_core_intr7 = rx_pkt_hndler_o_fatal_err_intr;
  assign rdma_core_intr8 = 1'b0;

rx_pkt_handler #(
  .C_SIM_DEBUG (0),
  .C_M_AXI_ADDR_WIDTH (C_M_AXI_ADDR_WIDTH),
  .C_NUM_QP (C_NUM_QP),
  .C_QP_INDX_WIDTH (C_QP_INDX_WIDTH),
  .C_OSQ_PSN_WIDTH (C_OSQ_PSN_WIDTH),
  .C_EN_DEBUG_PORTS (C_EN_DEBUG_PORTS)
) u_rx_pkt_handler (
  .core_clk                      (m_axi_aclk                      ),
  .core_rst_n                    (m_axi_aresetn                   ),
  .s_axis_tvalid                 (rx_pkt_hndler_s_axis_tvalid     ),
  .s_axis_tdata                  (rx_pkt_hndler_s_axis_tdata      ),
  .s_axis_tkeep                  (rx_pkt_hndler_s_axis_tkeep      ),
  .s_axis_tlast                  (rx_pkt_hndler_s_axis_tlast      ),
  .s_axis_tuser                  (rx_pkt_hndler_s_axis_tuser      ),
  .i_num_qp_enabled              (qp_mgr_o_num_qp_en              ),
  .i_mac_node_addr               (qp_mgr_o_mac_src_addr           ),
  .i_ipv4_node_addr              (qp_mgr_o_ipv4_src_addr         ),
  .i_ipv6_node_addr              (qp_mgr_o_ipv6_src_addr          ),
  .i_rnr_nak_tval                (qp_mgr_o_qp_timeout[20:16]      ),
  .i_rnr_nak_rst_val             (qp_mgr_o_qp_timeout[13:11]      ),
  .i_flow_credits                (qp_mgr_o_flow_credits           ),
  .i_depkt_bypass_en             (qp_mgr_o_depkt_bypass_en        ),
  .i_bypass_buf_ba               (qp_mgr_o_bypass_buf_ba          ),
  .i_bypass_num_bufs             (qp_mgr_o_bypass_buf_sz_num_bufs ),
  .i_bypass_buffer_sz            (qp_mgr_o_bypass_buf_sz_buf_sz   ),
  .o_bypass_buf_wrptr            (rx_pkt_hndler_o_bypass_buf_wrptr),
  .i_req_err_buf_en              (qp_mgr_o_err_buf_en             ),
  .i_req_err_buf_ovr_wr_en       (qp_mgr_o_rdma_adv_conf_errbuf_overwr_en),
  .i_req_err_pkt_buf_ba          (qp_mgr_o_err_pkt_buf_ba          ),
  .i_req_err_num_bufs            (qp_mgr_o_err_pkt_buf_sz_num_bufs ),
  .i_req_err_buffer_sz           (qp_mgr_o_err_pkt_buf_sz_buf_sz   ),
  .i_rsp_err_buf_en              (qp_mgr_o_err_buf_en              ),
  .i_rsp_err_buf_ovr_wr_en       (qp_mgr_o_rdma_adv_conf_errbuf_overwr_en),
  .i_rsp_err_pkt_buf_ba          (qp_mgr_o_resp_err_pkt_buf_ba),
  .i_rsp_err_num_bufs            (qp_mgr_o_resp_err_pkt_buf_sz_num_bufs),
  .i_rsp_err_buffer_sz           (qp_mgr_o_resp_err_pkt_buf_sz_buf_sz),
  .i_in_errsts_q_ba              (qp_mgr_in_errsts_q_ba            ),
  .i_in_errsts_q_sz              (qp_mgr_in_errsts_q_sz            ),
  .o_in_errsts_q_wrptr           (rx_pkt_hndler_in_errsts_q_wrptr  ),
  .o_inc_send_cnt                (rx_pkt_hndler_o_ib_send_pkt_cnt  ),
  .o_inc_acknak_cnt              (rx_pkt_hndler_o_ib_ack_pkt_cnt   ),
  .o_inc_rresp_cnt               (rx_pkt_hndler_o_ib_rres_pkt_cnt  ),
  .o_inc_mad_cnt                 (rx_pkt_hndler_o_ib_qp1_pkt_cnt   ),
  .o_inc_inv_pkt_cnt             (rx_pkt_hndler_o_ib_inv_pkt_cnt   ),
  .o_inc_dup_pkt_cnt             (rx_pkt_hndler_o_ib_dupl_pkt_cnt  ),
  .o_inc_nack_pkt_cnt            (rx_pkt_hndler_o_inc_nack_cnt     ),
  .o_out_nack_pkt_cnt            (rx_pkt_hndler_o_out_nack_cnt     ),
  .pkt_all_cnt                   (rx_pkt_hndler_o_pkt_all_cnt      ),
  .pkt_disc_cnt                  (rx_pkt_hndler_o_pkt_disc_cnt     ),
  .o_last_in_req_pkt_opcode      (),
  .o_last_in_req_pkt_qpid        (),
  .o_last_in_req_pkt_psn         (),
  .o_last_in_rsp_pkt_opcode      (),
  .o_last_in_rsp_pkt_qpid        (),
  .o_last_in_rsp_pkt_psn         (),
  .o_last_in_pkt_opcode          (rx_pkt_hndler_o_last_ib_pkt_opcode),
  .o_last_in_pkt_qpid            (rx_pkt_hndler_o_last_ib_pkt_dest_qpid),
  .o_last_in_pkt_psn             (rx_pkt_hndler_o_last_ib_pkt_psn),
  .o_rq_full                     (rx_pkt_hndler_o_rq_full          ),
  .o_qp_fatal                    (rx_pkt_hndler_o_qp_fatal         ),
  .i_clr_qp_fatal                (qp_mgr_o_qp_clr_fatal_err        ),
  .i_rq_pi_db_hw_hndshk          (qp_mgr_o_rq_pi_db_hw_hndshk      ),
  .i_connect_io_qp_rq_pi_db_wptr (qp_mgr_o_connect_io_qp_rq_pi_db_wptr),
  .i_hw_hndshk_disable_to_0      (qp_mgr_o_hw_hndshk_disable_to_0  ),
  .o_connect_io_qp_rq_pi_db_rdy  (rx_pkt_hndler_o_connect_io_qp_rq_pi_db_rdy),
  .o_rq_db_data                  (rx_pkt_hndler_o_rq_db_data       ),
  .o_rq_db_addr                  (rx_pkt_hndler_o_rq_db_addr  ),
  .o_rq_db_data_valid            (rx_pkt_hndler_o_rq_db_data_valid ),
  .i_rq_db_data_ack              (rx_pkt_hndler_i_rq_db_rdy        ),
  .i_pkt_valdn_err_intr_en       (qp_mgr_o_intr_en_pkt_valdn_err   ),
  .o_pkt_valdn_err_intr          (rx_pkt_hndler_o_ib_pkt_hdr_valdn_err_intr),
  .o_pkt_valdn_err_intr_sts      (rx_pkt_hndler_o_ib_pkt_hdr_valdn_err_intr_sts),
  .i_clr_pkt_valdn_err_intr      (qp_mgr_o_intr_clr_pkt_valdn_err      ),
  .i_mad_pkt_rcvd_intr_en        (qp_mgr_o_intr_en_mad_pkt_rcvd        ),
  .o_mad_pkt_rcvd_intr           (rx_pkt_hndler_o_mad_pkt_rcvd_intr    ),
  .o_mad_pkt_rcvd_intr_sts       (rx_pkt_hndler_o_mad_pkt_rcvd_intr_sts),
  .i_clr_mad_pkt_rcvd_intr       (qp_mgr_o_intr_clr_mad_pkt_rcvd       ),
  .i_bypass_pkt_rcvd_intr_en     (qp_mgr_o_intr_en_bypass_pkt_rcvd     ),
  .o_bypass_pkt_rcvd_intr        (rx_pkt_hndler_o_bypass_pkt_rcvd_intr ),
  .o_bypass_pkt_rcvd_intr_sts    (rx_pkt_hndler_o_bypass_pkt_rcvd_intr_sts),
  .i_clr_bypass_pkt_rcvd_intr    (qp_mgr_o_intr_clr_bypass_pkt_rcvd),
  .i_rnr_nack_gen_intr_en        (qp_mgr_o_intr_en_rnr_nak_gen     ),
  .o_rnr_nack_gen_intr           (rx_pkt_hndler_o_rnr_nack_gen_intr),
  .o_rnr_nack_gen_intr_sts       (rx_pkt_hndler_o_rnr_nack_gen_intr_sts),
  .i_clr_rnr_nack_gen_intr       (qp_mgr_o_intr_clr_rnr_nak_gen    ),
  .i_fatal_err_intr_en           (qp_mgr_o_intr_en_fatal_err       ),
  .o_fatal_err_intr              (rx_pkt_hndler_o_fatal_err_intr   ),
  .o_fatal_err_intr_sts          (rx_pkt_hndler_fatal_err_intr_sts ),
  .i_clr_fatal_err_intr          (qp_mgr_o_intr_clr_fatal_err        ),
  .i_qp_pkt_rcvd_intr_en         (qp_mgr_o_intr_en_qp_pkt_rcvd     ),
  .o_qp_pkt_rcvd_intr            (rx_pkt_hndler_o_qp_pkt_rcvd_intr ),
  .o_qp_pkt_rcvd_intr_sts        (rx_pkt_hndler_o_qp_pkt_rcvd_intr_sts ),
  .i_clr_qp_pkt_rcvd_intr        (qp_mgr_o_rq_intr_sts_clr         ),
  .o_qp_index_mpsnbuf            (rx_pkt_hndler_o_qp_index_mpsnbuf ),
  .o_max_epsn_req                (rx_pkt_hndler_o_max_epsn_req     ),
  .i_max_epsn_vld                (resp_hndler_o_mpsn_buf_valid     ),
  .i_mpsnbuf_empty               (resp_hndler_o_mpsnbuf_empty      ),
  .i_qp_retried                  (resp_hndler_o_qp_retried         ),
  .o_mpsnbuf_pop                 (rx_pkt_hndler_o_mpsnbuf_pop      ),
  .i_os_rdma_rd_resp_psn_7_0     (resp_hndler_o_max_epsn           ),
  .i_os_rdma_rd_resp_dest_addr   (resp_hndler_o_local_addr[C_M_AXI_ADDR_WIDTH-1:0]   ),
  .i_os_rdma_rd_resp_length      ({8'h00,resp_hndler_o_trnsfr_length[23:0]}),
  .o_qp_index_acknack            (rx_pkt_hndler_o_qp_index_acknack         ),
  .o_acknack_valid               (rx_pkt_hndler_o_acknack_valid     ),
  .o_acknacked_psn               (rx_pkt_hndler_o_acknacked_psn     ),
  .o_acknacked_syndrome          (rx_pkt_hndler_o_acknacked_syndrome),
  .o_acknacked_msn               (rx_pkt_hndler_o_acknacked_msn     ),
  .o_acknacked_opcode            (rx_pkt_hndler_o_acknacked_opcode  ),
  .o_qp_timeout_per_qp           (rx_pkt_hndler_o_qp_timeout_per_qp ),
  .i_osq_empty                   (resp_hndler_o_osq_empty           ),
  .i_osq_nacked                  (resp_handler_wqe_proc_osq_nacked  ),
  .o_rd_rsp_wr_cmpltd            (rx_pkt_hndler_o_rd_rsp_wr_cmpltd),
  .o_rsp_qp_id                   (rx_pkt_hndler_o_rsp_qp_id),
  .o_ob_rsp_qpid                 (rx_pkt_wqe_proc_ob_rsp_qpid       ),
  .o_ob_rsp_psn                  (rx_pkt_wqe_proc_ob_rsp_psn        ),
  .o_ob_rsp_aeth_syndrome        (rx_pkt_wqe_proc_aeth_syndrome     ),
  .o_ob_rsp_aeth_msn             (rx_pkt_wqe_proc_ob_rsp_msn        ),
  .o_ob_rsp_expl_ack             (rx_pkt_wqe_proc_ob_rsp_expl_ack   ),
  .o_ob_rsp_vld                  (rx_pkt_wqe_proc_ob_rsp_req        ),
  .ob_rsp_fifo_full              (wqe_proc_o_bres_fifo_full         ),

  .o_qp_req_conf_idx             (rx_pkt_hndler_o_qp_req_conf_idx   ),
  .i_qp_req_conf                 (qp_mgr_o_qp_conf_replica          ),      // need revisit
  .qp_req_conf_vld               (qp_mgr_o_qp_conf_replica_valid    ),      // need revisit
  .qp_req_conf_en                (rx_pkt_hndler_o_qp_req_conf_en    ),      // need revisit
  .i_rq_buf_ba                   (qp_mgr_o_qp_rq_ba                 ),
  .rq_buf_ba_en                  (rx_pkt_hndler_o_qpm_req_rq_buf_ba ),
  .i_rq_buf_ca                   (qp_mgr_o_qp_stat_rq_buf_ca        ),
  .o_rq_buf_ca                   (rx_pkt_hndler_o_rq_buf_ca         ),
  .rq_buf_ca_en                  (rx_pkt_hndler_o_qpm_req_rq_buf_ca ),
  .rq_buf_ca_we                  (rx_pkt_hndler_o_qpm_rw_rq_buf_ca  ),
  .i_rq_wrptr_db_addr            (qp_mgr_o_qp_rq_wrptrdb_add        ),
  .rq_wrptr_db_addr_en           (rx_pkt_hndler_o_qpm_req_rq_wrptr_db_add),
  .i_q_depth                     (qp_mgr_o_qp_rq_depth              ),
  .q_depth_en                    (rx_pkt_hndler_o_qpm_req_q_depth   ),
  .i_rq_ci_db                    (qp_mgr_o_qp_rq_cidb[15:0]         ),
  .rq_ci_db_en                   (rx_pkt_hndler_o_qpm_req_rq_ci_db  ),
  .i_last_rq_req                 (qp_mgr_o_qp_last_rq               ),
  .o_last_rq_req                 (rx_pkt_hndler_o_last_rq_req       ),
  .last_rq_req_en                (rx_pkt_hndler_o_qpm_req_last_rq_req),
  .last_rq_req_we                (rx_pkt_hndler_o_qpm_rw_last_rq_req ),
  .i_stat_qp_msn                 (qp_mgr_o_qp_stat_msn               ),
  .o_stat_qp_msn                 (rx_pkt_hndler_o_stat_qp_msn        ),
  .stat_qp_msn_en                (rx_pkt_hndler_o_qpm_req_stat_qp_msn),
  .stat_qp_msn_we                (rx_pkt_hndler_o_qpm_rw_stat_qp_msn ),
  .i_qp_req_remote_qp_mac_addr   ({qp_mgr_o_qp_mac_remote_addrm_replica[15:0], qp_mgr_o_qp_mac_remote_addrl_replica}),  // need revisit
  .qp_req_remote_qp_mac_addr_en  (rx_pkt_hndler_req_remote_qp_mac_addr_en),   // need revisit
  .i_qp_req_remote_qp_ip_addr    (qp_mgr_o_qp_ip_remote_addr1_replica),  // need revisit
  .qp_req_remote_qp_ip_addr_en   (rx_pkt_hndler_req_remote_qp_ip_addr_en),
  .i_rq_wrptr_db                 (qp_mgr_o_rq_pi_db                  ),
  .o_rq_wrptr_db                 (rx_pkt_hndler_o_rq_wrptr_db        ),
  .rq_wrptr_db_en                (rx_pkt_hndler_o_qpm_req_rq_wrptr_db),
  .rq_wrptr_db_we                (rx_pkt_hndler_o_qpm_rw_rq_wrptr_db ),

  .o_qp_rsp_conf_idx             (rx_pkt_hndler_o_qp_rsp_conf_idx    ),
  .i_qp_rsp_conf                 (qp_mgr_o_qp_conf                   ),
  .qp_rsp_conf_vld               (qp_mgr_o_qp_conf_valid_rx_pkt      ),
  .qp_rsp_conf_en                (rx_pkt_hndler_o_qp_rsp_conf_en     ),
  .i_stat_nak                    (resp_hndler_o_qp_stat_nak[9:0]     ),
  .stat_nak_en                   (rx_pkt_hndler_o_qpm_req_stat_nak   ),
  .stat_nak_we                   (rx_pkt_hndler_o_qpm_rw_stat_nak    ),
  .o_stat_nak                    (rx_pkt_hndler_o_stat_nak           ),
  .i_stat_resp_psn               (qp_mgr_o_qp_stat_resp_psn          ),
  .stat_resp_psn_en              (rx_pkt_hndler_o_qpm_req_stat_resp_psn),
  .stat_resp_psn_we              (rx_pkt_hndler_o_qpm_rw_stat_resp_psn),
  .o_stat_resp_psn               (rx_pkt_hndler_o_qp_stat_resp_psn   ),
  .i_sq_psn                      (qp_mgr_o_qp_sq_psn                 ),
  .sq_psn_en                     (rx_pkt_hndler_o_qpm_req_sq_psn     ),
  .i_qp_rsp_remote_qp_mac_addr   ({qp_mgr_o_qp_mac_dest_addrm[15:0] , qp_mgr_o_qp_mac_dest_addrl}),
  .qp_rsp_remote_qp_mac_addr_en  (rx_pkt_hndler_rsp_remote_qp_mac_addr_en),
  .i_qp_rsp_remote_qp_ip_addr    (qp_mgr_o_qp_ip_dest_addr1),
  .qp_rsp_remote_qp_ip_addr_en   (rx_pkt_hndler_rsp_remote_qp_ip_addr_en),
  .i_qp_timeout                  (qp_mgr_o_qp_timeout_per_qp         ),
  .debug_ctrl_in                 (qp_mgr_o_rx_pkt_hndl_dbg_ctrl),
  .debug_sts_out                 (rx_pkt_hndler_o_debug_bus),
  .i_global_dbg_cnt_clr          (o_global_dbg_cnt_clr),
  .i_global_dbg_cnt_en           (o_global_dbg_cnt_en)
);

resp_handler_top
#(
    .C_M_AXI_ADDR_WIDTH             (C_M_AXI_ADDR_WIDTH),
    .C_NUM_QP                       (C_NUM_QP),
    .C_QP_INDX_WIDTH                (C_QP_INDX_WIDTH),
    .C_OS_Q_DEPTH                   (OS_Q_DEPTH),
    .C_OS_Q_INDX_WIDTH              (OS_Q_INDX_WIDTH),
    .C_NUM_CYCLES_4US               (NUM_CYCLES_4US),                           // Number of clock cycles that make 4 us (for 125Mhz clk period it is 512)
    .C_EN_NVMOF_HW_HNDSHK           (C_EN_NVMOF_HW_HNDSHK),
    .STB_WIDTH                      (4),
    .C_OSQ_PSN_WIDTH                (C_OSQ_PSN_WIDTH),
    .C_EN_WR_RETRY_DATA_BUF	    (C_EN_WR_RETRY_DATA_BUF),
    .RESP_WIDTH                     (2)
) inst_resp_handler
(
  .core_clk                         (m_axi_aclk),
  .core_rstn                        (m_axi_aresetn),	                          // Active low core reset

  .i_wqe_qpid                       (wqe_proc_os_wqe_qpid),                      // QP ID of WQE
  .i_wqe_opcode                     (wqe_proc_os_wqe_opcode),                    // BTH.Opcode of outbound request
  .i_wqe_wrid                       (wqe_proc_os_wqe_wrid),
  .i_wqe_data_bufid                 (wqe_proc_os_wqe_data_bufid),
  .i_wqe_retried                    (wqe_proc_os_wqe_retried),
  .i_wqe_send_end_psn               (wqe_proc_os_wqe_send_psn),                  // PSN of most recent request
  .i_wqe_send_start_psn             (wqe_proc_os_wqe_send_first_psn),                  // PSN of most recent request
  .i_wqe_send_msn                   (wqe_proc_os_wqe_send_msn),
  .i_wqe_rdma_rd_rcv_ba             ({C_M_AXI_ADDR_WIDTH{1'b0}}),                // RDMA Read not supported
  .i_wqe_rdma_rd_res_len            (32'd0),                                     // RDMA Read not supported
  .i_wqe_push_req                   (wqe_proc_os_wqp_req),                       // request from WQE Processor to push WQE
  .o_wqe_push_rdy                   (wqe_proc_os_wqp_rdy),                       // response to WQE Processor; 0 - busy; 1 - completed
  .i_wqe_exp_ack_set                (wqe_proc_os_wqe_explicit_ack_req),
  .i_osq_wqe_nack_resp              (wqe_proc_top_o_osq_nacked_resp),
  .o_osq_full                       (wqe_proc_os_fifo_full),                     // Oustanding Q full - 1 bit for each QP
  .o_freeup_data_buf                (resp_hndler_freeup_data_buf),               // Freeup RDMA WRITE DATA buffer
  .o_freeup_data_bufid              (resp_hndler_freeup_data_bufid),             // BUffer ID to be freed up

  .o_resp_hndler_sts                (resp_hndler_o_resp_hndler_sts),
  .o_stat_retry_count               (resp_hndler_o_stat_retry_count),

  .i_qp_disable_pulse               (qp_mgr_o_qp_disable_pulse), // whenever QP_enable bit is written this pulse is generated and used for first_outgoing_pkt_ff signal generation

  .i_bypass_en                      (qp_mgr_o_depkt_bypass_en),
  .i_qp_fatal                       (rx_pkt_hndler_o_qp_fatal),
  .i_dma_in_idle		    (wqe_proc_dma_in_idle),
  .i_cfg_base_cnt		    (qp_mgr_o_rdma_adv_base_cnt),
  .o_num_valid_osq_entries          (os_num_vld_entries),
  .i_qpid_valid_entries             (wqe_proc_top_o_qp_id),
  .o_osq_nacked                     (resp_handler_wqe_proc_osq_nacked),
  .o_qp_rnr_nacked                  (resp_hndlr_o_qp_rnr_nacked),
  // Completion interrupt
  .i_intr_en_wqe_cmpl               (qp_mgr_o_intr_en_wqe_cmpl),
  .i_intr_clr_wqe_cmpl              (qp_mgr_o_intr_clr_wqe_cmpl),
  .o_intr_wqe_cmpl                  (resp_hndler_o_intr_wqe_cmpl),
  .o_intr_wqe_cmpl_sts              (resp_hndlr_i_qp_wq_cmpl_intr_sts),
  .i_clr_wqe_cmpl_sts               (qp_mgr_o_cq_intr_sts_clr),

  .i_qp_index_mpsnbuf               (rx_pkt_hndler_o_qp_index_mpsnbuf),        // QP ID to read the max PSN buffer top entry
  .i_mpsn_buf_req                   (rx_pkt_hndler_o_max_epsn_req),
  .o_mpsn_buf_valid                 (resp_hndler_o_mpsn_buf_valid),
  .o_max_epsn                       (resp_hndler_o_max_epsn),                // Max expected response PSN
  .o_trnsfr_length                  (resp_hndler_o_trnsfr_length),           // Transfer length for the WQE
  .o_local_addr                     (resp_hndler_o_local_addr),               // Local address - relevant only for RDMA READ requests
  .i_mpsnbuf_pop                    (rx_pkt_hndler_o_mpsnbuf_pop),             // Pop the MAX PSN buffer
  .o_mpsnbuf_empty                  (resp_hndler_o_mpsnbuf_empty),               // OSQ is empty - one hot
  .o_retry_counter_expired          (resp_hndler_o_retry_timer_expired),     // Retry timer has expired - one hot

  .i_qp_index_acknack               (rx_pkt_hndler_o_qp_index_acknack),        // QP ID for ack_nack packet PSN
  .i_acknack_valid                  (rx_pkt_hndler_o_acknack_valid),           // Valid signal qualifying the qp_index and acked PSN
  .i_acknacked_psn                  (rx_pkt_hndler_o_acknacked_psn),           // PSN for the packet being acked/nacked
  .i_acknacked_msn                  (rx_pkt_hndler_o_acknacked_msn),           // PSN for the packet being acked/nacked
  .i_acknacked_opcode               (rx_pkt_hndler_o_acknacked_opcode),                // Asserted when the packet is nacked
  .i_pkt_nacksyndrome               (rx_pkt_hndler_o_acknacked_syndrome),        // NACK Syndrome. Valid when the i_pkt_nack is asserted

  .i_rd_rsp_wr_done		    (rx_pkt_hndler_o_rd_rsp_wr_cmpltd),
  .i_rd_rsp_qpid		    (rx_pkt_hndler_o_rsp_qp_id),
  .o_inc_nack_cnt                   (resp_hndler_o_inc_nack_cnt),

  .o_retransmit_qpid                (resp_hndler_o_retransmit_qpid),         // QP id for this retransmission is required
  .o_retransmit_reqd                (resp_hndler_o_retransmit_reqd),         // Retransmission is required
  .i_retransmit_accepted            (qp_mgr_o_retransmit_accepted),         // Ack from QP manager that the retransmission is initiated
  .o_psn_to_retry                   (resp_hndler_o_psn_to_retry),
  .o_ssn_to_retry                   (resp_hndler_o_ssn_to_retry),
  .o_osq_almost_full                (resp_hndler_o_osq_almost_full),
  .o_osq_empty                      (resp_hndler_o_osq_empty),
  .o_qp_retried                     (resp_hndler_o_qp_retried),
  .i_halt                           (qp_mgr_o_halt),
  .i_halted_qpid                    (qp_mgr_o_halted_qpid),

  .o_qp_conf_qp_idx                 (resp_hndler_o_qp_conf_qp_idx),
  .o_qp_cq_ba_req                   (resp_hndler_o_qp_cq_ba_req),
  .i_qp_cq_ba                       (qp_mgr_o_qp_cq_ba),                      // CQ base address
  .i_qp_cq_ba_valid                 (qp_mgr_o_qp_cq_ba_valid),
  .o_qp_cq_depth_req                (resp_hndler_o_qp_cq_depth_req),
  .i_qp_cq_depth_valid              (qp_mgr_o_qp_cq_depth_valid),// CQ depth
  .i_qp_cq_depth                    (qp_mgr_o_qp_cq_depth),
  .o_qp_sq_cmpldb_addr_req          (resp_hndler_o_qp_sq_cmpldb_addr_req),
  .i_qp_sq_cmpldb_addr_valid        (qp_mgr_o_qp_sq_cmpldb_add_valid),       // SQ Completion DB address (points to RDMAif register)
  .i_qp_sq_cmpldb_addr              (qp_mgr_o_qp_sq_cmpldb_add),

  .o_qp_conf_req                    (resp_hndler_o_qp_conf_req),
  .i_qp_conf_valid                  (qp_mgr_o_qp_conf_valid_resp_hndl),
  .i_qp_conf                        (qp_mgr_o_qp_conf),

  .o_qp_cq_hdptr_req                (resp_hndler_o_qp_cq_hdptr_req),
  .i_qp_cq_hdptr_valid              (qp_mgr_o_qp_cq_hdptr_valid),             // CQ head pointer
  .i_qp_cq_hdptr                    (qp_mgr_o_qp_cq_hdptr),
  .o_qp_cq_hdptr                    (resp_hndler_o_qp_cq_hdptr),
  .o_qp_cq_hdptr_wrn                (resp_hndler_o_qp_cq_hdptr_wrn),

  .i_num_elements_enabled           (qp_mgr_o_num_qp_en),
  .i_timer_loadval_wqe              (wqe_proc_o_wqe_qp_to),
  .i_timer_loadval_acknack          (rx_pkt_hndler_o_qp_timeout_per_qp[4:0]),

  .o_send_cq_db_cnt_valid           (resp_hndler_o_send_cq_db_cnt_valid),
  .o_send_cq_db_addr                (resp_hndler_o_send_cq_db_addr_int ),
  .o_send_cq_db_cnt                 (resp_hndler_o_send_cq_db_cnt      ),
  .i_send_cq_db_rdy                 (resp_hndler_i_send_cq_db_rdy      ),

  .o_qp_sq_ba_req                   (resp_handler_o_qp_sq_ba_req),
  .i_qp_sq_ba_valid                 (qp_mgr_o_qp_sq_ba_valid),
  .i_qp_sq_ba                       (qp_mgr_o_qp_sq_ba),

  .i_data_buf_ba                    (qp_mgr_o_data_buf_ba),
  .i_data_buf_sz                    (qp_mgr_o_data_buf_sz_buf_sz),

// AXI Master signals
  .m_axi_awid                       (resp_hndler_m_axi_awid    ),
  .m_axi_awaddr                     (resp_hndler_m_axi_awaddr  ),
  .m_axi_awlen                      (resp_hndler_m_axi_awlen   ),
  .m_axi_awsize                     (resp_hndler_m_axi_awsize  ),
  .m_axi_awburst                    (resp_hndler_m_axi_awburst ),
  .m_axi_awcache                    (resp_hndler_m_axi_awcache ),
  .m_axi_awprot                     (resp_hndler_m_axi_awprot  ),
  .m_axi_awvalid                    (resp_hndler_m_axi_awvalid ),
  .m_axi_awready                    (resp_hndler_m_axi_awready ),

  .m_axi_wdata                      (resp_hndler_m_axi_wdata   ),
  .m_axi_wstrb                      (resp_hndler_m_axi_wstrb   ),
  .m_axi_wlast                      (resp_hndler_m_axi_wlast   ),
  .m_axi_wvalid                     (resp_hndler_m_axi_wvalid  ),
  .m_axi_wready                     (resp_hndler_m_axi_wready  ),
  .m_axi_awlock                     (resp_hndler_m_axi_awlock  ),

  .m_axi_bid                        (resp_hndler_m_axi_bid     ),
  .m_axi_bresp                      (resp_hndler_m_axi_bresp   ),
  .m_axi_bvalid                     (resp_hndler_m_axi_bvalid  ),
  .m_axi_bready                     (resp_hndler_m_axi_bready  ),

  .m_axi_arid                       (resp_hndler_m_axi_arid    ),
  .m_axi_araddr                     (resp_hndler_m_axi_araddr  ),
  .m_axi_arlen                      (resp_hndler_m_axi_arlen   ),
  .m_axi_arsize                     (resp_hndler_m_axi_arsize  ),
  .m_axi_arburst                    (resp_hndler_m_axi_arburst ),
  .m_axi_arcache                    (resp_hndler_m_axi_arcache ),
  .m_axi_arprot                     (resp_hndler_m_axi_arprot  ),
  .m_axi_arvalid                    (resp_hndler_m_axi_arvalid ),
  .m_axi_arready                    (resp_hndler_m_axi_arready ),

  .m_axi_rid                        (resp_hndler_m_axi_rid     ),
  .m_axi_rdata                      (resp_hndler_m_axi_rdata   ),
  .m_axi_rresp                      (resp_hndler_m_axi_rresp   ),
  .m_axi_rlast                      (resp_hndler_m_axi_rlast   ),
  .m_axi_rvalid                     (resp_hndler_m_axi_rvalid  ),
  .m_axi_rready                     (resp_hndler_m_axi_rready  ),
  .m_axi_arlock                     (resp_hndler_m_axi_arlock  )

  );

assign rx_pkt_hndler_o_qpm_req_dest_qp_conf = 1'b0;  // rx_pkt_handler never need of dest_qp_conf

qp_mgr_top
#(
    .C_S_AXI_LITE_ADDR_WIDTH        (C_S_AXI_LITE_ADDR_WIDTH),
    .C_S_AXI_LITE_DATA_WIDTH        (32),
    .C_NUM_QP                       (C_NUM_QP),
    .C_QP_INDX_WIDTH                (C_QP_INDX_WIDTH),
    .STB_WIDTH                      (4),
    .RESP_WIDTH                     (2),
    .C_EN_DEBUG_REGS                (C_EN_DEBUG_PORTS)
) inst_qp_mgr
(
  .s_axi_lite_aclk                  (s_axi_lite_aclk   ),
  .s_axi_lite_aresetn               (s_axi_lite_aresetn),

  .s_axi_lite_awaddr                (s_axi_lite_awaddr ),
  .s_axi_lite_awready               (s_axi_lite_awready),
  .s_axi_lite_awvalid               (s_axi_lite_awvalid),

  .s_axi_lite_araddr                (s_axi_lite_araddr ),
  .s_axi_lite_arready               (s_axi_lite_arready),
  .s_axi_lite_arvalid               (s_axi_lite_arvalid),

  .s_axi_lite_wdata                 (s_axi_lite_wdata  ),
  .s_axi_lite_wstrb                 (s_axi_lite_wstrb  ),
  .s_axi_lite_wready                (s_axi_lite_wready ),
  .s_axi_lite_wvalid                (s_axi_lite_wvalid ),

  .s_axi_lite_rdata                 (s_axi_lite_rdata  ),
  .s_axi_lite_rresp                 (s_axi_lite_rresp  ),
  .s_axi_lite_rready                (s_axi_lite_rready ),
  .s_axi_lite_rvalid                (s_axi_lite_rvalid ),

  .s_axi_lite_bresp                 (s_axi_lite_bresp  ),
  .s_axi_lite_bready                (s_axi_lite_bready ),
  .s_axi_lite_bvalid                (s_axi_lite_bvalid ),

  .core_clk                         (m_axi_aclk),
  .core_rstn                        (m_axi_aresetn),	    // Active high core reset

  .o_wqe                            (qpm_wqe_data),
  .i_wqe_pop                        (qpm_wqe_pop_int),
  .o_wqe_empty                      (qpm_wqe_fifo_empty),
  .o_halt                           (qp_mgr_o_halt),
  .o_halted_qpid                    (qp_mgr_o_halted_qpid),
  .i_wqe_halted                     (wqe_proc_i_wqe_halted),

  // Interrupt signals coming from Header validation module
  .i_pkt_valdn_err_intr             (rx_pkt_hndler_o_ib_pkt_hdr_valdn_err_intr_sts),
  .i_mad_pkt_rcvd_intr              (rx_pkt_hndler_o_mad_pkt_rcvd_intr_sts),
  .i_bypass_pkt_rcvd_intr           (rx_pkt_hndler_o_bypass_pkt_rcvd_intr_sts),
  .i_rnr_nack_gen_intr              (rx_pkt_hndler_o_rnr_nack_gen_intr_sts),
  .i_ill_opc_in_sq_intr             (ill_opc_in_sq_intr),
  .i_qp_pkt_rcvd_intr               (rx_pkt_hndler_o_qp_pkt_rcvd_intr_sts),

  .i_qp_fatal_err                   (rx_pkt_hndler_o_qp_fatal),
  .i_qp_rnr_nacked                  (resp_hndlr_o_qp_rnr_nacked),

  .o_intr_clr_pkt_valdn_err         (qp_mgr_o_intr_clr_pkt_valdn_err),
  .o_intr_clr_mad_pkt_rcvd          (qp_mgr_o_intr_clr_mad_pkt_rcvd),
  .o_intr_clr_bypass_pkt_rcvd       (qp_mgr_o_intr_clr_bypass_pkt_rcvd),
  .o_intr_clr_rnr_nak_gen           (qp_mgr_o_intr_clr_rnr_nak_gen),
  .o_intr_clr_ill_opc_in_sq         (intr_clr_ill_opc_in_sq),
  .o_intr_clr_qp_pkt_rcvd           (qp_mgr_o_intr_clr_qp_pkt_rcvd),
  .o_intr_clr_wqe_cmpl              (qp_mgr_o_intr_clr_wqe_cmpl),
  .o_intr_clr_fatal_err             (qp_mgr_o_intr_clr_fatal_err),
  .o_qp_clr_fatal_err               (qp_mgr_o_qp_clr_fatal_err),

  .o_intr_en_wqe_cmpl               (qp_mgr_o_intr_en_wqe_cmpl),
  .o_intr_en_pkt_valdn_err          (qp_mgr_o_intr_en_pkt_valdn_err  ),
  .o_intr_en_mad_pkt_rcvd           (qp_mgr_o_intr_en_mad_pkt_rcvd   ),
  .o_intr_en_bypass_pkt_rcvd        (qp_mgr_o_intr_en_bypass_pkt_rcvd),
  .o_intr_en_rnr_nak_gen            (qp_mgr_o_intr_en_rnr_nak_gen),
  .o_intr_en_ill_opc_in_sq          (intr_en_ill_opc_in_sq),
  .o_intr_en_fatal_err              (qp_mgr_o_intr_en_fatal_err),
  .o_intr_en_qp_pkt_rcvd            (qp_mgr_o_intr_en_qp_pkt_rcvd),

  .i_qp_wq_cmpl_intr                (resp_hndlr_i_qp_wq_cmpl_intr_sts),
  .o_rq_intr_sts_clr                (qp_mgr_o_rq_intr_sts_clr),
  .o_cq_intr_sts_clr                (qp_mgr_o_cq_intr_sts_clr),

  .o_timeoutreg                     (qp_mgr_o_qp_timeout),
  .o_qp_disable_pulse               (qp_mgr_o_qp_disable_pulse),

  .i_qp_timeout_idx                 (rx_pkt_hndler_o_qp_rsp_conf_idx),    // Index for reading/writing MSN
  .o_qp_timeout                     (qp_mgr_o_qp_timeout_per_qp), // Expected MSN for Qp incoming messages write data from hdr validation

  .o_out_errsts_q_ba                (out_errsts_q_ba),
  .o_out_errsts_q_sz                (out_errsts_q_sz),
  .i_out_errsts_q_wrptr             (out_errsts_q_wrptr),

  .o_in_errsts_q_ba                 (qp_mgr_in_errsts_q_ba),
  .o_in_errsts_q_sz                 (qp_mgr_in_errsts_q_sz),
  .i_in_errsts_q_wrptr              (rx_pkt_hndler_in_errsts_q_wrptr),

  .i_rq_full                        (rx_pkt_hndler_o_rq_full),  // Rcv Q full for QPn
  .i_osq_full                       (wqe_proc_os_fifo_full), // Outstanding Q full for QPn
  .i_cq_full                        (rx_pkt_hndler_o_cq_full),  // completion Q full for QPn
  .i_rq_empty                       (rx_pkt_hndler_o_rq_empty), // Rcv Q empty for QPn
  .i_osq_empty                      (resp_hndler_o_osq_empty),// Outstanding Q empty for QPn
  .i_qp_retried                     (resp_hndler_o_qp_retried),// QP retried for QPn

  .i_qp_stat_msn_idx                (rx_pkt_hndler_o_qp_req_conf_idx),    // Index for reading/writing MSN
  .i_qp_stat_msn                    (rx_pkt_hndler_o_stat_qp_msn), // Expected MSN for Qp incoming messages
  .o_qp_stat_msn                    (qp_mgr_o_qp_stat_msn), // Expected MSN for Qp incoming messages write data from hdr validation
  .i_qp_stat_msn_req                (rx_pkt_hndler_o_qpm_req_stat_qp_msn),
  .i_qp_stat_msn_wrn                (rx_pkt_hndler_o_qpm_rw_stat_qp_msn),
  .o_qp_stat_msn_valid              (qp_mgr_o_qp_stat_msn_valid),

  .i_qp_rq_pi_db_idx                (rx_pkt_hndler_o_qp_req_conf_idx),    // Index for reading/writing MSN
  .i_qp_rq_pi_db                    (rx_pkt_hndler_o_rq_wrptr_db), // Expected MSN for Qp incoming messages
  .o_qp_rq_pi_db                    (qp_mgr_o_rq_pi_db), // Expected MSN for Qp incoming messages write data from hdr validation
  .i_qp_rq_pi_db_req                (rx_pkt_hndler_o_qpm_req_rq_wrptr_db),
  .i_qp_rq_pi_db_wrn                (rx_pkt_hndler_o_qpm_rw_rq_wrptr_db),
  .o_qp_rq_pi_db_valid              (qp_mgr_o_qp_rq_pi_db_valid),

  // Retried SQ PSN for Rx packet handler
  .i_qp_stat_ret_sq_psn_idx         (rx_pkt_hndler_o_qp_rsp_conf_idx),    // Index for reading/writing RQ PI DB
  .o_qp_stat_ret_sq_psn             (qp_mgr_o_qp_stat_ret_sq_psn),
  .i_qp_stat_ret_sq_psn_req         (rx_pkt_hndler_o_qp_rsp_conf_en),
  .o_qp_stat_ret_sq_psn_valid       (qp_mgr_o_qp_stat_ret_sq_psn_valid),

  .i_wqe_proc_sts                   (wqe_proc_status_out),
  .o_rx_pkt_hndl_dbg_ctrl           (qp_mgr_o_rx_pkt_hndl_dbg_ctrl),
  .i_rx_pkt_vld_sts                 (rx_pkt_hndler_o_debug_bus),
  .i_resp_hndler_sts                (resp_hndler_o_resp_hndler_sts),
  .i_stat_retry_cnt                 (resp_hndler_o_stat_retry_count),
  .i_min_ipg_stat                   (rx_pkt_hndler_o_ipg_cntr_min),
  .i_ipg_0_4_cnt                    (32'h0),
  .i_ipg_5_9_cnt                    (32'h0),
  .i_ipg_10_14_cnt                  (32'h0),
  .i_ipg_15_19_cnt                  (32'h0),

  //Configuration outputs going to other modules (generic)
  .o_rdma_en                       (qp_mgr_o_rdma_en       ),
  .o_rdma_adv_conf_errbuf_overwr_en (qp_mgr_o_rdma_adv_conf_errbuf_overwr_en),
  .o_rdma_adv_base_cnt   	    (qp_mgr_o_rdma_adv_base_cnt),
  .o_err_buf_en                     (qp_mgr_o_err_buf_en     ),
  .o_flow_credits                   (qp_mgr_o_flow_credits   ),
  .o_tx_ack_gen                     (qp_mgr_o_tx_ack_gen     ),
  .o_depkt_bypass_en                (qp_mgr_o_depkt_bypass_en),               // RDMA interface bypass feature enable
  .o_num_qp_en                      (qp_mgr_o_num_qp_en      ),                      // Number of QPs enabled
  .o_mac_rdma_addr                 (qp_mgr_o_mac_src_addr  ),                 // Ethernet MAC destination (own) address from RDMA registers
  .o_ipv4_rdma_addr                (qp_mgr_o_ipv4_src_addr ),                // IPv4 destination (own) address from RDMA registers
  .o_ipv6_rdma_addr                (qp_mgr_o_ipv6_src_addr ),                // IPv6 destination (own) address form RDMA registers
  .o_data_buf_ba                    (qp_mgr_o_data_buf_ba   ),
  .o_data_buf_sz_num_bufs           (qp_mgr_o_data_buf_sz_num_bufs),
  .o_data_buf_sz_buf_sz             (qp_mgr_o_data_buf_sz_buf_sz),
  .o_bypass_buf_ba                  (qp_mgr_o_bypass_buf_ba         ),
  .o_bypass_buf_sz_num_bufs         (qp_mgr_o_bypass_buf_sz_num_bufs),
  .o_bypass_buf_sz_buf_sz           (qp_mgr_o_bypass_buf_sz_buf_sz  ),
  .i_bypass_buf_wrptr               (rx_pkt_hndler_o_bypass_buf_wrptr),
  .o_rq_err_pkt_buf_ba              (qp_mgr_o_err_pkt_buf_ba         ),
  .o_rq_err_pkt_buf_sz_num_bufs     (qp_mgr_o_err_pkt_buf_sz_num_bufs),
  .o_rq_err_pkt_buf_sz_buf_sz       (qp_mgr_o_err_pkt_buf_sz_buf_sz  ),
  .o_resp_err_pkt_buf_ba            (qp_mgr_o_resp_err_pkt_buf_ba),
  .o_resp_err_pkt_buf_sz_num_bufs   (qp_mgr_o_resp_err_pkt_buf_sz_num_bufs),
  .o_resp_err_pkt_buf_sz_buf_sz     (qp_mgr_o_resp_err_pkt_buf_sz_buf_sz),
  .i_inc_rresp_pkt_cnt              (rx_pkt_hndler_o_ib_rres_pkt_cnt),
  .i_inc_send_pkt_cnt               (rx_pkt_hndler_o_ib_send_pkt_cnt),
  .i_inc_ack_pkt_cnt                (rx_pkt_hndler_o_ib_ack_pkt_cnt),
  .i_inc_mad_pkt_cnt                (rx_pkt_hndler_o_ib_qp1_pkt_cnt),
  .i_inc_inv_pkt_cnt                (rx_pkt_hndler_o_ib_inv_pkt_cnt),
  .i_inc_dup_pkt_cnt                (rx_pkt_hndler_o_ib_dupl_pkt_cnt),
  .i_inc_all_dropped_cnt            ({rx_pkt_hndler_o_pkt_all_cnt[15:0],rx_pkt_hndler_o_pkt_disc_cnt[15:0]}),
  .i_inc_nack_cnt                   (rx_pkt_hndler_o_inc_nack_cnt),
  .o_tx_hdr_buf_ba                  (qp_mgr_o_tx_hdr_buf_ba),
  .o_tx_hdr_buf_sz_num_hdrs         (qp_mgr_o_tx_hdr_buf_sz_num_hdrs),
  .o_tx_hdr_buf_sz_buf_sz           (qp_mgr_o_tx_hdr_buf_sz_buf_sz),
  .o_tx_sgl_buf_ba                  (qp_mgr_o_tx_sgl_buf_ba),
  .o_tx_sgl_buf_sz_num_sgls         (qp_mgr_o_tx_sgl_buf_sz_num_sgls),
  .o_tx_sgl_buf_sz_buf_sz           (qp_mgr_o_tx_sgl_buf_sz_buf_sz),
  .o_rdma_conf_ipver               (qp_mgr_o_rdma_conf_ipver),
  .o_hw_wqe_remote_addr_lo         (qp_mgr_o_hw_wqe_remote_addr_lo),
  .o_hw_wqe_remote_addr_hi         (qp_mgr_o_hw_wqe_remote_addr_hi),
  .o_hw_wqe_rkey                   (qp_mgr_o_hw_wqe_rkey),
  .o_hw_wqe_local_addr             (qp_mgr_o_hw_wqe_local_addr),
  .o_hw_wqe_opcode                 (qp_mgr_o_hw_wqe_opcode),
  .o_hw_wqe_wrid                   (qp_mgr_o_hw_wqe_wrid),

  .o_rdma_udp_src_port             (qp_mgr_o_rdma_udp_src_port),

  //.o_connect_io_residual_rq         (qp_mgr_o_connect_io_residual_rq     ),
  .o_rq_pi_db_hw_hndshk             (qp_mgr_o_rq_pi_db_hw_hndshk         ),
  .o_connect_io_qp_rq_pi_db_wptr    (qp_mgr_o_connect_io_qp_rq_pi_db_wptr),
  .i_connect_io_qp_rq_pi_db_rdy     (rx_pkt_hndler_o_connect_io_qp_rq_pi_db_rdy),
  .o_hw_hndshk_disable_to_0         (qp_mgr_o_hw_hndshk_disable_to_0     ),

  //.i_out_nack_cnt                   (resp_hndler_o_inc_nack_cnt),
  .i_out_nack_cnt                   (rx_pkt_hndler_o_out_nack_cnt[15:0]),
  .i_out_rdwr_pkt_cnt               (wqe_out_rdwr_pkt_cnt),
  .i_out_send_pkt_cnt               (16'd0),
  .i_out_mad_pkt_cnt                (wqe_out_mad_pkt_cnt),
  .i_out_ack_pkt_cnt                (wqe_out_ack_pkt_cnt),

  //Configuration outputs going to other modules (PER QP)
  .i_qp_conf_req_resp_hndl          (resp_hndler_o_qp_conf_req),
  .i_qp_conf_req_wqe_proc           (wqe_proc_top_o_reg_rd_en_s),
  .i_qp_conf_req_rx_pkt             (rx_pkt_hndler_o_qp_rsp_conf_en),
  .o_qp_conf_valid_resp_hndl        (qp_mgr_o_qp_conf_valid_resp_hndl),
  .o_qp_conf_valid_wqe_proc         (qp_mgr_o_qp_conf_valid_wqe_proc),
  .o_qp_conf_valid_rx_pkt           (qp_mgr_o_qp_conf_valid_rx_pkt),
  .o_qp_conf                        (qp_mgr_o_qp_conf),        // QP configuration
  .i_qp_conf_idx                    (rx_pkt_hndler_o_qp_rsp_conf_en ?  rx_pkt_hndler_o_qp_rsp_conf_idx : (wqe_proc_top_o_reg_rd_en_s ?
                                                                       wqe_proc_top_o_qp_id : resp_hndler_o_qp_conf_qp_idx)),    // Index for reading Qp configuration

  .o_qp_conf_replica                (qp_mgr_o_qp_conf_replica),        // QP configuration REPLICA
  .i_qp_conf_replica_idx            (rx_pkt_hndler_o_qp_req_conf_idx),    // Index for reading Qp configuration REPLICA
  .i_qp_conf_replica_req            (rx_pkt_hndler_o_qp_req_conf_en),
  .o_qp_conf_replica_valid          (qp_mgr_o_qp_conf_replica_valid),

  .i_qp_adv_conf_req                (wqe_proc_top_o_reg_rd_en),
  .o_qp_adv_conf_valid              (qp_mgr_o_qp_adv_conf_valid),
  .o_qp_adv_conf                    (qp_mgr_o_qp_adv_conf),     // QP advance configuration
  .i_qp_adv_conf_idx                (wqe_proc_top_o_qp_id),

  .i_qp_rq_ba_req                   (rx_pkt_hndler_o_qpm_req_rq_buf_ba),
  .o_qp_rq_ba_valid                 (qp_mgr_o_qp_rq_ba_valid),
  .o_qp_rq_ba                       (qp_mgr_o_qp_rq_ba),
  .i_qp_rq_ba_idx                   (rx_pkt_hndler_o_qp_req_conf_idx),   // Index for reading Qp RQ Buffer BA

  .i_qp_cq_ba_req                   (resp_hndler_o_qp_cq_ba_req),
  .o_qp_cq_ba_valid                 (qp_mgr_o_qp_cq_ba_valid),
  .o_qp_cq_ba                       (qp_mgr_o_qp_cq_ba),
  .i_qp_cq_ba_idx                   (resp_hndler_o_qp_conf_qp_idx),   // Index for reading Qp CQ BA

  .i_qp_rq_wrptrdb_add_req          (rx_pkt_hndler_o_qpm_req_rq_wrptr_db_add),
  .o_qp_rq_wrptrdb_add_valid        (qp_mgr_o_qp_rq_wrptrdb_add_valid),
  .o_qp_rq_wrptrdb_add              (qp_mgr_o_qp_rq_wrptrdb_add),
  .i_qp_rq_wrptrdb_add_idx          (rx_pkt_hndler_o_qp_req_conf_idx),   // Index for reading Qp SQ BA

  .i_qp_sq_cmpldb_add_req           (resp_hndler_o_qp_sq_cmpldb_addr_req),
  .o_qp_sq_cmpldb_add_valid         (qp_mgr_o_qp_sq_cmpldb_add_valid),
  .o_qp_sq_cmpldb_add               (qp_mgr_o_qp_sq_cmpldb_add),
  .i_qp_sq_cmpldb_add_idx           (resp_hndler_o_qp_conf_qp_idx),   // Index for reading SQ Completion DB address

  .i_qp_cq_hdptr_req                (resp_hndler_o_qp_cq_hdptr_req),
  .o_qp_cq_hdptr_valid              (qp_mgr_o_qp_cq_hdptr_valid),
  .o_qp_cq_hdptr                    (qp_mgr_o_qp_cq_hdptr),
  .i_qp_cq_hdptr_idx                (resp_hndler_o_qp_conf_qp_idx),   // Index for reading CQ head pointer
  .i_qp_cq_hdptr                    (resp_hndler_o_qp_cq_hdptr),
  .i_qp_cq_hdptr_wrn                (resp_hndler_o_qp_cq_hdptr_wrn),

  .i_qp_rq_cidb_req                 (rx_pkt_hndler_o_qpm_req_rq_ci_db),
  .o_qp_rq_cidb_valid               (qp_mgr_o_qp_rq_cidb_valid),
  .o_qp_rq_cidb                     (qp_mgr_o_qp_rq_cidb),
  .i_qp_rq_cidb_idx                 (rx_pkt_hndler_o_qp_req_conf_idx),   // Index for reading RQ CI DB

  .i_qp_rq_depth_req                (rx_pkt_hndler_o_qpm_req_q_depth),
  .o_qp_rq_depth_valid              (qp_mgr_o_qp_rq_depth_valid),
  .o_qp_rq_depth                    (qp_mgr_o_qp_rq_depth),
  .i_qp_rq_depth_idx                (rx_pkt_hndler_o_qp_req_conf_idx),   // Index for reading Q depth

  .i_qp_sq_psn_req                  (rx_pkt_hndler_o_qpm_req_sq_psn),
  .i_qp_sq_psn_wqe_req              (wqe_proc_top_o_reg_rd_en_s | wqe_proc_top_o_reg_wr_en),
  .o_qp_sq_psn_valid                (qp_mgr_o_qp_sq_psn_valid),
  .o_qp_sq_psn_wqe_valid            (qp_mgr_o_qp_sq_psn_wqe_valid),
  .o_qp_sq_psn                      (qp_mgr_o_qp_sq_psn),
  .i_qp_sq_psn_wrn                  (wqe_proc_top_o_reg_wr_en),
  .i_qp_sq_psn                      (wqe_proc_top_reg_sq_psn),
  .i_qp_sq_psn_idx                  (rx_pkt_hndler_o_qp_rsp_conf_idx),  // Index for reading Q depth
  .i_qp_sq_psn_wqe_idx              (wqe_proc_top_o_qp_id),  // Index for reading Q depth

  .o_qp_last_rq                     (qp_mgr_o_qp_last_rq),
  .i_qp_last_rq_idx                 (rx_pkt_hndler_o_qp_req_conf_idx),   // Index for reading Q depth
  .i_qp_last_rq                     (rx_pkt_hndler_o_last_rq_req),
  .i_qp_last_rq_req                 (rx_pkt_hndler_o_qpm_req_last_rq_req),
  .i_qp_last_rq_wrn                 (rx_pkt_hndler_o_qpm_rw_last_rq_req),
  .o_qp_last_rq_valid               (qp_mgr_o_qp_last_rq_valid),

  .i_qp_dest_qpid_req_wqe_proc      (wqe_proc_top_o_reg_rd_en),  // req from WQE PROC
  .i_qp_dest_qpid_req_rx_pkt        (1'b0), // req from RX pkt handler
  .o_qp_dest_qpid_valid_wqe_proc    (qp_mgr_o_qp_dest_qpid_valid_wqe_proc),
  .o_qp_dest_qpid_valid_rx_pkt      (qp_mgr_o_qp_dest_qpid_valid_rx_pkt),
  .o_qp_dest_qpid                   (qp_mgr_o_qp_dest_qpid),
  .i_qp_dest_qpid_idx               (wqe_proc_top_o_qp_id),   // Index for reading dest QPID

  .i_qp_stat_resp_psn               (rx_pkt_hndler_o_qp_stat_resp_psn),
  .i_qp_stat_resp_psn_wen           (rx_pkt_hndler_o_qpm_rw_stat_resp_psn),
  .i_qp_stat_resp_psn_idx           (rx_pkt_hndler_o_qp_rsp_conf_idx),
  .o_qp_stat_resp_psn_valid         (qp_mgr_o_qp_stat_resp_psn_valid),
  .i_qp_stat_resp_psn_rdreq         (rx_pkt_hndler_o_qpm_req_stat_resp_psn),
  .o_qp_stat_resp_psn               (qp_mgr_o_qp_stat_resp_psn),

  .i_qp_stat_rq_buf_ca              (rx_pkt_hndler_o_rq_buf_ca),
  .i_qp_stat_rq_buf_ca_wen          (rx_pkt_hndler_o_qpm_rw_rq_buf_ca),
  .i_qp_stat_rq_buf_ca_idx          (rx_pkt_hndler_o_qp_req_conf_idx),
  .o_qp_stat_rq_buf_ca_valid        (qp_mgr_o_qp_stat_rq_buf_ca_valid),
  .i_qp_stat_rq_buf_ca_rdreq        (rx_pkt_hndler_o_qpm_req_rq_buf_ca),
  .o_qp_stat_rq_buf_ca              (qp_mgr_o_qp_stat_rq_buf_ca),

  .i_qp_stat_ssn_idx                (wqe_proc_top_o_qp_id),
  .i_qp_stat_ssn                    (wqe_proc_top_reg_sq_ssn),
  .o_qp_stat_ssn                    (qp_mgr_o_qp_sq_ssn),
  .i_qp_stat_ssn_req                (wqe_proc_top_o_reg_rd_en | wqe_proc_top_o_reg_wr_en),
  .i_qp_stat_ssn_wrn                (wqe_proc_top_o_reg_wr_en),
  .o_qp_stat_ssn_valid              (),

  .i_qp_rq_cidb_hndshk              (i_qp_rq_cidb_hndshk),
  .i_qp_rq_cidb_wr_addr_hndshk      (i_qp_rq_cidb_wr_addr_hndshk),
  .i_qp_rq_cidb_wr_valid_hndshk     (i_qp_rq_cidb_wr_valid_hndshk),
  .o_qp_rq_cidb_wr_rdy              (o_qp_rq_cidb_wr_rdy),

  .i_qp_sq_pidb_hndshk              (i_qp_sq_pidb_hndshk),
  .i_qp_sq_pidb_wr_addr_hndshk      (i_qp_sq_pidb_wr_addr_hndshk),
  .i_qp_sq_pidb_wr_valid_hndshk     (i_qp_sq_pidb_wr_valid_hndshk),
  .o_qp_sq_pidb_wr_rdy              (o_qp_sq_pidb_wr_rdy),

  //.i_qp_stat_nak                    ({3'b0, rx_pkt_hndler_o_stat_nak}),
  .i_qp_stat_nak                    (rx_pkt_hndler_o_stat_nak[9:0]),
  .i_qp_stat_nak_wen                (rx_pkt_hndler_o_qpm_rw_stat_nak),
  .i_qp_stat_nak_idx                (rx_pkt_hndler_o_qp_rsp_conf_idx),
  .o_qp_stat_nak_valid              (resp_hndler_o_qp_stat_nak_valid),
  .i_qp_stat_nak_rdreq              (rx_pkt_hndler_o_qpm_req_stat_nak),
  .o_qp_stat_nak                    (resp_hndler_o_qp_stat_nak),

  .i_qp_mac_remote_addrl_req        (rx_pkt_hndler_rsp_remote_qp_mac_addr_en),
  .o_qp_mac_remote_addrl_valid      (qp_mgr_o_qp_mac_remote_addrl_valid),
  .i_qp_mac_remote_addrl_wqe_req    (wqe_proc_top_o_reg_rd_en_s),
  .o_qp_mac_remote_addrl_wqe_valid  (qp_mgr_o_qp_mac_dest_addrl_valid),
  .o_qp_mac_remote_addrl            (qp_mgr_o_qp_mac_dest_addrl),
  .i_qp_mac_remote_addrl_idx        (rx_pkt_hndler_o_qp_rsp_conf_idx),   // Index for reading Q depth
  .i_qp_mac_remote_addrl_wqe_idx    (wqe_proc_top_o_qp_id),   // Index for reading Q depth

  .i_qp_mac_remote_addrl_replica_req(rx_pkt_hndler_req_remote_qp_mac_addr_en),
  .o_qp_mac_remote_addrl_replica    (qp_mgr_o_qp_mac_remote_addrl_replica),
  .i_qp_mac_remote_addrl_replica_idx(rx_pkt_hndler_o_qp_req_conf_idx),
  .o_qp_mac_remote_addrl_replica_valid(),

  .i_qp_mac_remote_addrm_req        (rx_pkt_hndler_rsp_remote_qp_mac_addr_en),
  .o_qp_mac_remote_addrm_valid      (),
  .i_qp_mac_remote_addrm_wqe_req    (wqe_proc_top_o_reg_rd_en_s),
  .o_qp_mac_remote_addrm_wqe_valid  (qp_mgr_o_qp_mac_dest_addrm_valid),
  .o_qp_mac_remote_addrm            (qp_mgr_o_qp_mac_dest_addrm),
  .i_qp_mac_remote_addrm_idx        (rx_pkt_hndler_o_qp_rsp_conf_idx),   // Index for reading Q depth
  .i_qp_mac_remote_addrm_wqe_idx    (wqe_proc_top_o_qp_id),   // Index for reading Q depth

  .o_qp_mac_remote_addrm_replica    (qp_mgr_o_qp_mac_remote_addrm_replica),
  .i_qp_mac_remote_addrm_replica_idx(rx_pkt_hndler_o_qp_req_conf_idx),
  .i_qp_mac_remote_addrm_replica_req(rx_pkt_hndler_req_remote_qp_mac_addr_en),
  .o_qp_mac_remote_addrm_replica_valid(),

  .i_qp_ip_remote_addr1_req         (rx_pkt_hndler_rsp_remote_qp_ip_addr_en),
  .o_qp_ip_remote_addr1_valid       (qp_mgr_o_qp_ip_remote_addr1_valid),
  .i_qp_ip_remote_addr1_wqe_req     (wqe_proc_top_o_reg_rd_en_s),
  .o_qp_ip_remote_addr1_wqe_valid   (qp_mgr_o_qp_ip_dest_addr1_valid),
  .o_qp_ip_remote_addr1             (qp_mgr_o_qp_ip_dest_addr1),
  .i_qp_ip_remote_addr1_idx         (rx_pkt_hndler_o_qp_rsp_conf_idx),   // Index for reading IP ADDR1
  .i_qp_ip_remote_addr1_wqe_idx     (wqe_proc_top_o_qp_id),   // Index for reading IP ADDR1

  .o_qp_ip_remote_addr1_replica     (qp_mgr_o_qp_ip_remote_addr1_replica),
  .i_qp_ip_remote_addr1_replica_idx (rx_pkt_hndler_o_qp_req_conf_idx),
  .i_qp_ip_remote_addr1_replica_req (rx_pkt_hndler_req_remote_qp_ip_addr_en),
  .o_qp_ip_remote_addr1_replica_valid(),


  .i_qp_sq_ba_req                   (resp_handler_o_qp_sq_ba_req),
  .o_qp_sq_ba_valid                 (qp_mgr_o_qp_sq_ba_valid),
  .o_qp_sq_ba                       (qp_mgr_o_qp_sq_ba),
  .i_qp_sq_ba_idx                   (resp_hndler_o_qp_conf_qp_idx),


  .i_qp_cq_depth_req                (resp_hndler_o_qp_cq_depth_req),
  .o_qp_cq_depth_valid              (qp_mgr_o_qp_cq_depth_valid),
  .o_qp_cq_depth                    (qp_mgr_o_qp_cq_depth),
  .i_qp_cq_depth_idx                (resp_hndler_o_qp_conf_qp_idx),

  .o_global_dbg_cnt_value	(),//o_global_dbg_cnt_value     ),
  .o_global_dbg_cnt_clr		(o_global_dbg_cnt_clr),
  .o_global_dbg_cnt_en		(o_global_dbg_cnt_en),
  .i_wqe_fsm_idle_cnt		(wqe_proc_idle_cnt),
  .i_hdr_backpressure_cnt	(wqe_proc_hdr_sgl_buf_full_cnt),
  .i_retry_tx_backpressure_cnt	(wqe_proc_wr_retry_buf_full_cnt),
  .i_wqe_proc_rd_wqe_cnt      (wqe_proc_rd_wqe_cnt),
  .i_wqe_proc_rd_q_info_cnt   (wqe_proc_rd_q_info_cnt),
  .i_wqe_proc_wait0_cnt       (wqe_proc_wait0_cnt),
  .i_wqe_proc_ip_chksum_cnt   (wqe_proc_ip_chksum_cnt),
  .i_wqe_proc_hdr_gen_cnt     (wqe_proc_hdr_gen_cnt),
  .i_wqe_proc_hdr_sto_cnt     (wqe_proc_hdr_sto_cnt),

  .i_last_in_pkt_info               ({rx_pkt_hndler_o_last_ib_pkt_psn, rx_pkt_hndler_o_last_ib_pkt_dest_qpid, rx_pkt_hndler_o_last_ib_pkt_opcode}),
  .i_last_out_pkt_info              (last_out_pkt_info),

  .i_retransmit_qpid                (resp_hndler_o_retransmit_qpid),         // QP id for this retransmission is required
  .i_retransmit_reqd                (resp_hndler_o_retransmit_reqd),         // Retransmission is required
  .o_retransmit_accepted            (qp_mgr_o_retransmit_accepted),         // Ack from QP manager that the retransmission is initiated
  .i_psn_to_retry                   (resp_hndler_o_psn_to_retry),
  .i_ssn_to_retry                   (resp_hndler_o_ssn_to_retry),
  .i_osq_almost_full                (resp_hndler_o_osq_almost_full),

// AXI Master signals
  .m_axi_awid                       (qp_mgr_m_axi_awid   ),
  .m_axi_awaddr                     (qp_mgr_m_axi_awaddr ),
  .m_axi_awlen                      (qp_mgr_m_axi_awlen  ),
  .m_axi_awsize                     (qp_mgr_m_axi_awsize ),
  .m_axi_awburst                    (qp_mgr_m_axi_awburst),
  .m_axi_awcache                    (qp_mgr_m_axi_awcache),
  .m_axi_awprot                     (qp_mgr_m_axi_awprot ),
  .m_axi_awvalid                    (qp_mgr_m_axi_awvalid),
  .m_axi_awready                    (qp_mgr_m_axi_awready),

  .m_axi_wdata                      (qp_mgr_m_axi_wdata  ),
  .m_axi_wstrb                      (qp_mgr_m_axi_wstrb  ),
  .m_axi_wlast                      (qp_mgr_m_axi_wlast  ),
  .m_axi_wvalid                     (qp_mgr_m_axi_wvalid ),
  .m_axi_wready                     (qp_mgr_m_axi_wready ),
  .m_axi_awlock                     (qp_mgr_m_axi_awlock ),

  .m_axi_bid                        (qp_mgr_m_axi_bid    ),
  .m_axi_bresp                      (qp_mgr_m_axi_bresp  ),
  .m_axi_bvalid                     (qp_mgr_m_axi_bvalid ),
  .m_axi_bready                     (qp_mgr_m_axi_bready ),

  .m_axi_arid                       (qp_mgr_m_axi_arid   ),
  .m_axi_araddr                     (qp_mgr_m_axi_araddr ),
  .m_axi_arlen                      (qp_mgr_m_axi_arlen  ),
  .m_axi_arsize                     (qp_mgr_m_axi_arsize ),
  .m_axi_arburst                    (qp_mgr_m_axi_arburst),
  .m_axi_arcache                    (qp_mgr_m_axi_arcache),
  .m_axi_arprot                     (qp_mgr_m_axi_arprot ),
  .m_axi_arvalid                    (qp_mgr_m_axi_arvalid),
  .m_axi_arready                    (qp_mgr_m_axi_arready),

  .m_axi_rid                        (qp_mgr_m_axi_rid    ),
  .m_axi_rdata                      (qp_mgr_m_axi_rdata  ),
  .m_axi_rresp                      (qp_mgr_m_axi_rresp  ),
  .m_axi_rlast                      (qp_mgr_m_axi_rlast  ),
  .m_axi_rvalid                     (qp_mgr_m_axi_rvalid ),
  .m_axi_rready                     (qp_mgr_m_axi_rready ),
  .m_axi_arlock                     (qp_mgr_m_axi_arlock )

  );

  assign qp_idx_TBD = 'b0;

  wqe_proc_top
    #(
        .C_MAX_QP(C_NUM_QP),
        .C_MAX_QID_WIDTH(C_QP_INDX_WIDTH),
        .C_OS_Q_INDX_WIDTH(OS_Q_INDX_WIDTH),
        .C_MAX_WRDATA_BUF_NUM(C_MAX_WR_RETRY_DATA_BUF_DEPTH),
        .C_EN_WR_RETRY_DATA_BUF(C_EN_WR_RETRY_DATA_BUF),
        .C_M_AXI_DATA_WIDTH(512),
        .C_M_AXI_ADDR_WIDTH(C_M_AXI_ADDR_WIDTH),
        .C_M_AXI_ID_WIDTH(C_M_AXI_ID_WIDTH),
        .C_S_AXI_DATA_WIDTH(512),
        .C_S_AXI_ADDR_WIDTH(32),
        .C_S_AXI_ID_WIDTH(1),
        .C_AXI_DMA_ADDR(32'h50040000),
        .C_MAX_SGL_DEPTH(C_MAX_SGL_DEPTH),
        .C_VIVADO_VER (1),
        .C_EN_DEBUG(C_EN_DEBUG_PORTS),
        .C_FAMILY("virtex7")
    ) wqe_proc_top_inst (
        .core_clk(m_axi_aclk),
        .core_rst(~m_axi_aresetn),
        .m_axi_awid(wqe_proc_top_m_axi_awid),
        .m_axi_awaddr(wqe_proc_top_m_axi_awaddr),
        .m_axi_awlen(wqe_proc_top_m_axi_awlen),
        .m_axi_awsize(wqe_proc_top_m_axi_awsize),
        .m_axi_awburst(wqe_proc_top_m_axi_awburst),
        .m_axi_awcache(wqe_proc_top_m_axi_awcache),
        .m_axi_awprot(wqe_proc_top_m_axi_awprot),
        .m_axi_awvalid(wqe_proc_top_m_axi_awvalid),
        .m_axi_awready(wqe_proc_top_m_axi_awready),
        .m_axi_wdata(wqe_proc_top_m_axi_wdata),
        .m_axi_wstrb(wqe_proc_top_m_axi_wstrb),
        .m_axi_wlast(wqe_proc_top_m_axi_wlast),
        .m_axi_wvalid(wqe_proc_top_m_axi_wvalid),
        .m_axi_wready(wqe_proc_top_m_axi_wready),
        .m_axi_awlock(wqe_proc_top_m_axi_awlock),
        .m_axi_bid(wqe_proc_top_m_axi_bid),
        .m_axi_bresp(wqe_proc_top_m_axi_bresp),
        .m_axi_bvalid(wqe_proc_top_m_axi_bvalid),
        .m_axi_bready(wqe_proc_top_m_axi_bready),
        .m_axi_arid(wqe_proc_top_m_axi_arid),
        .m_axi_araddr(wqe_proc_top_m_axi_araddr),
        .m_axi_arlen(wqe_proc_top_m_axi_arlen),
        .m_axi_arsize(wqe_proc_top_m_axi_arsize),
        .m_axi_arburst(wqe_proc_top_m_axi_arburst),
        .m_axi_arcache(wqe_proc_top_m_axi_arcache),
        .m_axi_arprot(wqe_proc_top_m_axi_arprot),
        .m_axi_arvalid(wqe_proc_top_m_axi_arvalid),
        .m_axi_arready(wqe_proc_top_m_axi_arready),
        .m_axi_rid(wqe_proc_top_m_axi_rid),
        .m_axi_rdata(wqe_proc_top_m_axi_rdata),
        .m_axi_rresp(wqe_proc_top_m_axi_rresp),
        .m_axi_rlast(wqe_proc_top_m_axi_rlast),
        .m_axi_rvalid(wqe_proc_top_m_axi_rvalid),
        .m_axi_rready(wqe_proc_top_m_axi_rready),
        .m_axi_arlock(wqe_proc_top_m_axi_arlock),
        .m_axi_wr_ddr_awid(wqe_proc_wr_ddr_m_axi_awid),
        .m_axi_wr_ddr_awaddr(wqe_proc_wr_ddr_m_axi_awaddr),
        .m_axi_wr_ddr_awlen(wqe_proc_wr_ddr_m_axi_awlen),
        .m_axi_wr_ddr_awsize(wqe_proc_wr_ddr_m_axi_awsize),
        .m_axi_wr_ddr_awburst(wqe_proc_wr_ddr_m_axi_awburst),
        .m_axi_wr_ddr_awcache(wqe_proc_wr_ddr_m_axi_awcache),
        .m_axi_wr_ddr_awprot(wqe_proc_wr_ddr_m_axi_awprot),
        .m_axi_wr_ddr_awvalid(wqe_proc_wr_ddr_m_axi_awvalid),
        .m_axi_wr_ddr_awready(wqe_proc_wr_ddr_m_axi_awready),
        .m_axi_wr_ddr_wdata(wqe_proc_wr_ddr_m_axi_wdata),
        .m_axi_wr_ddr_wstrb(wqe_proc_wr_ddr_m_axi_wstrb),
        .m_axi_wr_ddr_wlast(wqe_proc_wr_ddr_m_axi_wlast),
        .m_axi_wr_ddr_wvalid(wqe_proc_wr_ddr_m_axi_wvalid),
        .m_axi_wr_ddr_wready(wqe_proc_wr_ddr_m_axi_wready),
        .m_axi_wr_ddr_awlock(wqe_proc_wr_ddr_m_axi_awlock),
        .m_axi_wr_ddr_bid(wqe_proc_wr_ddr_m_axi_bid),
        .m_axi_wr_ddr_bresp(wqe_proc_wr_ddr_m_axi_bresp),
        .m_axi_wr_ddr_bvalid(wqe_proc_wr_ddr_m_axi_bvalid),
        .m_axi_wr_ddr_bready(wqe_proc_wr_ddr_m_axi_bready),
        .m_axi_wr_ddr_arid(wqe_proc_wr_ddr_m_axi_arid),
        .m_axi_wr_ddr_araddr(wqe_proc_wr_ddr_m_axi_araddr),
        .m_axi_wr_ddr_arlen(wqe_proc_wr_ddr_m_axi_arlen),
        .m_axi_wr_ddr_arsize(wqe_proc_wr_ddr_m_axi_arsize),
        .m_axi_wr_ddr_arburst(wqe_proc_wr_ddr_m_axi_arburst),
        .m_axi_wr_ddr_arcache(wqe_proc_wr_ddr_m_axi_arcache),
        .m_axi_wr_ddr_arprot(wqe_proc_wr_ddr_m_axi_arprot),
        .m_axi_wr_ddr_arvalid(wqe_proc_wr_ddr_m_axi_arvalid),
        .m_axi_wr_ddr_arready(wqe_proc_wr_ddr_m_axi_arready),
        .m_axi_wr_ddr_rid(wqe_proc_wr_ddr_m_axi_rid),
        .m_axi_wr_ddr_rdata(wqe_proc_wr_ddr_m_axi_rdata),
        .m_axi_wr_ddr_rresp(wqe_proc_wr_ddr_m_axi_rresp),
        .m_axi_wr_ddr_rlast(wqe_proc_wr_ddr_m_axi_rlast),
        .m_axi_wr_ddr_rvalid(wqe_proc_wr_ddr_m_axi_rvalid),
        .m_axi_wr_ddr_rready(wqe_proc_wr_ddr_m_axi_rready),
        .m_axi_wr_ddr_arlock(wqe_proc_wr_ddr_m_axi_arlock),
        .m_axis_tdata(wqe_proc_top_m_axis_tdata),
        .m_axis_tkeep(wqe_proc_top_m_axis_tkeep),
        .m_axis_tvalid(wqe_proc_top_m_axis_tvalid),
        .m_axis_tready(wqe_proc_top_m_axis_tready),
        .m_axis_tlast(wqe_proc_top_m_axis_tlast),
        .o_osq_nacked_resp(wqe_proc_top_o_osq_nacked_resp),
        .i_qpm_fifo_empty(wqe_empty_to_proc),
        .i_wqe_halt(qp_mgr_o_halt),
        .i_wqe_halted_qpid(qp_mgr_o_halted_qpid),
        .o_wqe_halted(wqe_proc_i_wqe_halted),
        .i_qpm_wqe_data(wqe_data_to_proc),
        .o_qpm_wqe_pop(wqe_pop_to_proc),
        .o_reg_rd_en(wqe_proc_top_o_reg_rd_en),
        .o_reg_rd_en_s(wqe_proc_top_o_reg_rd_en_s),
        .i_reg_rdy(qp_mgr_o_qp_sq_psn_wqe_valid & qp_mgr_o_qp_mac_dest_addrm_valid),
        .i_reg_psn_val(qp_mgr_o_qp_sq_psn_wqe_valid),
        .o_reg_wr_en(wqe_proc_top_o_reg_wr_en),
        .o_qp_id(wqe_proc_top_o_qp_id),
        .i_reg_pkey(qp_mgr_o_qp_adv_conf[31:16]),
        .i_reg_pmtu(qp_mgr_o_qp_conf[10:8]),  // use relevant qp_conf field
        .i_reg_dest_qpid(qp_mgr_o_qp_dest_qpid), // pls add ready and connect ~rx_pkt_hndler_o_qpm_req_dest_qp_conf
        .i_reg_sq_psn(qp_mgr_o_qp_sq_psn),
        .o_reg_sq_psn(wqe_proc_top_reg_sq_psn),
        .i_reg_sq_msn(qp_mgr_o_qp_sq_ssn),
        .o_reg_sq_msn(wqe_proc_top_reg_sq_ssn),
        .i_reg_max_rd_atomic(qp_mgr_o_qp_conf[23:16]), // use relevant qp_conf field
        .i_reg_mac_dest_addr({qp_mgr_o_qp_mac_dest_addrm[15:0] , qp_mgr_o_qp_mac_dest_addrl}),
        .i_reg_ip_dest_addr(qp_mgr_o_qp_ip_dest_addr1),
        .i_reg_udp_src_port(qp_mgr_o_rdma_udp_src_port), // this is a static value for RoCE
        .i_reg_qp_to(qp_mgr_o_qp_timeout_per_qp[4:0]),
        .i_reg_ttl(qp_mgr_o_qp_adv_conf[15:8]),
        .i_reg_dscp(qp_mgr_o_qp_adv_conf[5:0]),
        .i_reg_exp_ack(~qp_mgr_o_qp_conf[1]),  //needs a register bit
        .i_reg_ack_resp_strategy(qp_mgr_o_tx_ack_gen),
        .i_reg_mac_src_addr(qp_mgr_o_mac_src_addr),
        .i_reg_ipv4_src_addr(qp_mgr_o_ipv4_src_addr), // need ipv4/ipv6
        .i_reg_ipv6_src_addr(qp_mgr_o_ipv6_src_addr), // need ipv4/ipv6
        .i_reg_tx_hdr_buf_ba(qp_mgr_o_tx_hdr_buf_ba),
        .i_reg_tx_hdr_buf_depth(qp_mgr_o_tx_hdr_buf_sz_num_hdrs),
        .i_reg_tx_hdr_buf_size(qp_mgr_o_tx_hdr_buf_sz_buf_sz),
        .i_reg_tx_sgl_buf_ba(qp_mgr_o_tx_sgl_buf_ba),
        .i_reg_tx_sgl_buf_depth(qp_mgr_o_tx_sgl_buf_sz_num_sgls),
        .i_reg_tx_sgl_buf_size(qp_mgr_o_tx_sgl_buf_sz_buf_sz),
        .i_reg_rdma_en(qp_mgr_o_rdma_en),
        .i_reg_ip_ver(qp_mgr_o_qp_conf[7]),
        .i_reg_wrdata_buf_ba(qp_mgr_o_data_buf_ba),
        .i_reg_wrdata_num_bufs(qp_mgr_o_data_buf_sz_num_bufs),
        .i_reg_wrdata_buf_sz(qp_mgr_o_data_buf_sz_buf_sz),
        .i_bres_valid(rx_pkt_wqe_proc_ob_rsp_req),
        .i_bres_exp_ack(rx_pkt_wqe_proc_ob_rsp_expl_ack),
        .i_bres_dest_qpid(rx_pkt_wqe_proc_ob_rsp_qpid),
        .o_bres_fifo_full (wqe_proc_o_bres_fifo_full),
        .i_res_psn(rx_pkt_wqe_proc_ob_rsp_psn),
        .i_res_aeth_syndrome(rx_pkt_wqe_proc_aeth_syndrome[6:0]),
        .i_res_msn(rx_pkt_wqe_proc_ob_rsp_msn),
        .i_freeup_data_buf(resp_hndler_freeup_data_buf),               // Freeup RDMA WRITE DATA buffer
        .i_freeup_data_bufid(resp_hndler_freeup_data_bufid),             // BUffer ID to be freed up
        .o_wqp_req(wqe_proc_os_wqp_req),
        .i_wqp_resp(wqe_proc_os_wqp_rdy),
        .o_wqe_qpid(wqe_proc_os_wqe_qpid),
        .o_wqe_opcode(wqe_proc_os_wqe_opcode),
        .o_wqe_qp_to(wqe_proc_o_wqe_qp_to),
        .o_wqe_wrid(wqe_proc_os_wqe_wrid),
        .o_wqe_retried(wqe_proc_os_wqe_retried),
        .o_wqe_data_bufid(wqe_proc_os_wqe_data_bufid),
        .o_wqe_send_psn(wqe_proc_os_wqe_send_psn),
        .o_wqe_send_first_psn(wqe_proc_os_wqe_send_first_psn),
        .o_wqe_send_msn(wqe_proc_os_wqe_send_msn),
        .o_wqe_explicit_ack_req(wqe_proc_os_wqe_explicit_ack_req),
        .i_wqe_os_fifo_full(resp_hndler_o_osq_almost_full),   //wqe_proc_os_fifo_full),
	    .o_wqe_status_out(wqe_proc_status_out),
        .o_last_out_pkt_info(last_out_pkt_info),
        .o_out_rw_pkt_cnt(wqe_out_rdwr_pkt_cnt),
        .o_out_ack_pkt_cnt(wqe_out_ack_pkt_cnt),
        .o_out_mad_pkt_cnt(wqe_out_mad_pkt_cnt),
        .i_out_errsts_q_ba(out_errsts_q_ba),
        .i_out_errsts_q_sz(out_errsts_q_sz),
        .o_out_errsts_q_wrptr(out_errsts_q_wrptr),
        .i_intr_en_ill_opc_in_sq(intr_en_ill_opc_in_sq),
        .i_intr_clr_ill_opc_in_sq(intr_clr_ill_opc_in_sq),
        .o_ill_opc_in_sq_intr(ill_opc_in_sq_intr),
        .os_num_vld_entries(os_num_vld_entries),
        .i_osq_nacked(resp_handler_wqe_proc_osq_nacked),
        .o_wqe_proc_idle_cnt(wqe_proc_idle_cnt),
        .o_wqe_proc_rd_wqe_cnt(wqe_proc_rd_wqe_cnt),
        .o_wqe_proc_rd_q_info_cnt(wqe_proc_rd_q_info_cnt),
        .o_wqe_proc_wait0_cnt(wqe_proc_wait0_cnt),
        .o_wqe_proc_ip_chksum_cnt(wqe_proc_ip_chksum_cnt),
        .o_wqe_proc_hdr_gen_cnt(wqe_proc_hdr_gen_cnt),
        .o_wqe_proc_hdr_sto_cnt(wqe_proc_hdr_sto_cnt),
        .o_wqe_proc_hdr_sgl_buf_full_cnt(wqe_proc_hdr_sgl_buf_full_cnt),
        .o_wqe_proc_wr_retry_buf_full_cnt(wqe_proc_wr_retry_buf_full_cnt),
        .i_debug_cnt_en(o_global_dbg_cnt_en),
        .i_debug_cnt_clr(o_global_dbg_cnt_clr),
        .i_qp_fatal(rx_pkt_hndler_o_qp_fatal),
        .i_qp_recovery(qp_mgr_o_qp_conf[6]),
        .o_dma_in_idle(wqe_proc_dma_in_idle)
    );

endmodule

