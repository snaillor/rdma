// wqe_proc_top.v
// 文件名          : wqe_proc_top.v
// 版本            : v1.0
// 描述            : WQE 处理顶层模块，负责发送路径的数据包组装
//                   包含 AXI Master/Slave、包头生成、缓冲区管理等子模块
// Verilog 标准    : Verilog'2001

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
`timescale 1ps/1ps

(* DowngradeIPIdentifiedWarnings="yes" *)
module wqe_proc_top
#(
    parameter C_MAX_QP = 8,
    parameter C_MAX_QID_WIDTH = 3,
    parameter C_M_AXI_DATA_WIDTH = 512,
    parameter C_M_AXI_ADDR_WIDTH = 32,
    parameter C_M_AXI_ID_WIDTH = 4,
    parameter C_S_AXI_DATA_WIDTH = 512,
    parameter C_S_AXI_ADDR_WIDTH = 32,
    parameter C_S_AXI_ID_WIDTH = 4,
    parameter C_AXIS_DATA_WIDTH = 512,
    parameter C_AXI_DMA_ADDR = 32'h50024000,
    parameter C_MAX_SGL_DEPTH = 128,
    parameter C_MAX_HDR_DEPTH = 512,
    parameter C_MAX_WRDATA_BUF_NUM = 128,
    parameter C_EN_WR_RETRY_DATA_BUF = 1,
    parameter C_OS_Q_INDX_WIDTH = 3,
    parameter C_VIVADO_VER = 1,
    parameter C_EN_DEBUG = 0,
    parameter C_FAMILY = "virtex7"
 ) (
    input                    core_clk,
    input                    core_rst,

    // AXI Master signals
    output [C_M_AXI_ID_WIDTH-1 :0]          m_axi_awid,
    output [C_M_AXI_ADDR_WIDTH-1:0]         m_axi_awaddr,
    output [7:0]                            m_axi_awlen,
    output [2:0]                            m_axi_awsize,
    output [1:0]                            m_axi_awburst,
    output [3:0]                            m_axi_awcache,
    output [2:0]                            m_axi_awprot,
    output                                  m_axi_awvalid,
    input                                   m_axi_awready,
    output [C_M_AXI_DATA_WIDTH-1:0]         m_axi_wdata,
    output [C_M_AXI_DATA_WIDTH/8-1:0]       m_axi_wstrb,
    output                                  m_axi_wlast,
    output                                  m_axi_wvalid,
    input                                   m_axi_wready,
    output                                  m_axi_awlock,
    input  [C_M_AXI_ID_WIDTH-1 :0]          m_axi_bid,
    input  [1:0]                            m_axi_bresp,
    input                                   m_axi_bvalid,
    output                                  m_axi_bready,
    output [C_M_AXI_ID_WIDTH-1 :0]          m_axi_arid,
    output [C_M_AXI_ADDR_WIDTH-1:0]         m_axi_araddr,
    output [7:0]                            m_axi_arlen,
    output [2:0]                            m_axi_arsize,
    output [1:0]                            m_axi_arburst,
    output [3:0]                            m_axi_arcache,
    output [2:0]                            m_axi_arprot,
    output                                  m_axi_arvalid,
    input                                   m_axi_arready,
    input  [C_M_AXI_ID_WIDTH-1 :0]          m_axi_rid,
    input  [C_M_AXI_DATA_WIDTH-1:0]         m_axi_rdata,
    input  [1:0]                            m_axi_rresp,
    input                                   m_axi_rlast,
    input                                   m_axi_rvalid,
    output                                  m_axi_rready,
    output                                  m_axi_arlock,

    output [C_M_AXI_ID_WIDTH-1 :0]          m_axi_wr_ddr_awid,
    output [C_M_AXI_ADDR_WIDTH-1:0]         m_axi_wr_ddr_awaddr,
    output [7:0]                            m_axi_wr_ddr_awlen,
    output [2:0]                            m_axi_wr_ddr_awsize,
    output [1:0]                            m_axi_wr_ddr_awburst,
    output [3:0]                            m_axi_wr_ddr_awcache,
    output [2:0]                            m_axi_wr_ddr_awprot,
    output                                  m_axi_wr_ddr_awvalid,
    input                                   m_axi_wr_ddr_awready,
    output [C_M_AXI_DATA_WIDTH-1:0]         m_axi_wr_ddr_wdata,
    output [C_M_AXI_DATA_WIDTH/8-1:0]       m_axi_wr_ddr_wstrb,
    output                                  m_axi_wr_ddr_wlast,
    output                                  m_axi_wr_ddr_wvalid,
    input                                   m_axi_wr_ddr_wready,
    output                                  m_axi_wr_ddr_awlock,
    input  [C_M_AXI_ID_WIDTH-1 :0]          m_axi_wr_ddr_bid,
    input  [1:0]                            m_axi_wr_ddr_bresp,
    input                                   m_axi_wr_ddr_bvalid,
    output                                  m_axi_wr_ddr_bready,
    output [C_M_AXI_ID_WIDTH-1 :0]          m_axi_wr_ddr_arid,
    output [C_M_AXI_ADDR_WIDTH-1:0]         m_axi_wr_ddr_araddr,
    output [7:0]                            m_axi_wr_ddr_arlen,
    output [2:0]                            m_axi_wr_ddr_arsize,
    output [1:0]                            m_axi_wr_ddr_arburst,
    output [3:0]                            m_axi_wr_ddr_arcache,
    output [2:0]                            m_axi_wr_ddr_arprot,
    output                                  m_axi_wr_ddr_arvalid,
    input                                   m_axi_wr_ddr_arready,
    input  [C_M_AXI_ID_WIDTH-1 :0]          m_axi_wr_ddr_rid,
    input  [C_M_AXI_DATA_WIDTH-1:0]         m_axi_wr_ddr_rdata,
    input  [1:0]                            m_axi_wr_ddr_rresp,
    input                                   m_axi_wr_ddr_rlast,
    input                                   m_axi_wr_ddr_rvalid,
    output                                  m_axi_wr_ddr_rready,
    output                                  m_axi_wr_ddr_arlock,

    //AXI streaming interface signals
    output     [C_AXIS_DATA_WIDTH-1 : 0]        m_axis_tdata,
    output     [C_AXIS_DATA_WIDTH/8-1:0]        m_axis_tkeep,
    output                                      m_axis_tvalid,
    input                                       m_axis_tready,
    output                                      m_axis_tlast,

   (* mark_debug = "true" *) input                                       i_qpm_fifo_empty,
    input      [511:0]                          i_qpm_wqe_data,
   (* mark_debug = "true" *) output                                      o_qpm_wqe_pop,
   input                                        i_wqe_halt,
   input       [C_MAX_QID_WIDTH -1 :0]          i_wqe_halted_qpid,
   output                                       o_wqe_halted,

   (* mark_debug = "true" *) output                                      o_reg_rd_en,
   (* mark_debug = "true" *) output                                      o_reg_rd_en_s,
   (* mark_debug = "true" *) input                                       i_reg_rdy,
                             input                                       i_reg_psn_val,
   (* mark_debug = "true" *) output                                      o_reg_wr_en,
   (* mark_debug = "true" *) output     [C_MAX_QID_WIDTH-1:0]            o_qp_id,
    input      [15:0]                           i_reg_pkey,
    input      [2:0]                            i_reg_pmtu,
    input      [23:0]                           i_reg_dest_qpid,
    input      [23:0]                           i_reg_sq_psn,
    output     [23:0]                           o_reg_sq_psn,
    input      [23:0]                           i_reg_sq_msn,
    output     [23:0]                           o_reg_sq_msn,
    input                                       i_freeup_data_buf,
    input      [14:0]                           i_freeup_data_bufid,
    input      [4:0]                            i_reg_qp_to,
    input      [7:0]                            i_reg_max_rd_atomic,
    input      [47:0]                           i_reg_mac_dest_addr,
    input      [31:0]                           i_reg_ip_dest_addr,
    input      [15:0]                           i_reg_udp_src_port,
    input      [7:0]                            i_reg_ttl,
    input      [5:0]                            i_reg_dscp,
    input                                       i_reg_exp_ack,

    input      [47:0]                           i_reg_mac_src_addr,
    input      [31:0]                           i_reg_ipv4_src_addr,
    input      [127:0]                          i_reg_ipv6_src_addr,
    input      [31:0]                           i_reg_tx_hdr_buf_ba,
    input      [15:0]                           i_reg_tx_hdr_buf_depth,
    input      [15:0]                           i_reg_tx_hdr_buf_size,
    input      [31:0]                           i_reg_tx_sgl_buf_ba,
    input      [15:0]                           i_reg_tx_sgl_buf_depth,
    input      [15:0]                           i_reg_tx_sgl_buf_size,
    input                                       i_reg_rdma_en,
    input      [1:0]                            i_reg_ack_resp_strategy,
    input                                       i_reg_ip_ver,
    input      [31:0]                           i_reg_wrdata_buf_ba,
    input      [15:0]                           i_reg_wrdata_num_bufs,
    input      [15:0]                           i_reg_wrdata_buf_sz,

    //Response handler ACK interface
   (* mark_debug = "true" *) input                                       i_bres_valid,
   (* mark_debug = "true" *) input                                       i_bres_exp_ack,
    input      [C_MAX_QID_WIDTH-1:0]            i_bres_dest_qpid,
    output                                      o_bres_fifo_full,
    input      [23:0]                           i_res_psn,
   (* mark_debug = "true" *) input      [6:0]                            i_res_aeth_syndrome,
    input      [23:0]                           i_res_msn,

    output                                      o_wqp_req,
    input                                       i_wqp_resp,
    output     [C_MAX_QID_WIDTH-1:0]            o_wqe_qpid,
    output     [7:0]                            o_wqe_opcode,
    output     [15:0]                           o_wqe_wrid,
    output     [23:0]                           o_wqe_send_psn,
    output     [23:0]                           o_wqe_send_first_psn,
    output     [23:0]                           o_wqe_send_msn,
    output     [14:0]                           o_wqe_data_bufid,
    output     [4:0]                            o_wqe_qp_to,
    output                                      o_wqe_retried,
    output                                      o_wqe_explicit_ack_req,
    input      [C_MAX_QP-1:0]                   i_wqe_os_fifo_full,
   (* mark_debug = "true" *) output     [31:0]                           o_wqe_status_out,
    output     [31:0]                           o_last_out_pkt_info,
    output     [15:0]                           o_out_rw_pkt_cnt,
    output     [15:0]                           o_out_ack_pkt_cnt,
    output     [15:0]                           o_out_mad_pkt_cnt,
    output     [15:0]                           o_wqe_proc_idle_cnt,
    output     [15:0]                           o_wqe_proc_rd_wqe_cnt,
    output     [15:0]                           o_wqe_proc_rd_q_info_cnt,
    output     [15:0]                           o_wqe_proc_wait0_cnt,
    output     [15:0]                           o_wqe_proc_ip_chksum_cnt,
    output     [15:0]                           o_wqe_proc_hdr_gen_cnt,
    output     [15:0]                           o_wqe_proc_hdr_sto_cnt,
    output     [15:0]                           o_wqe_proc_hdr_sgl_buf_full_cnt,
    output     [15:0]                           o_wqe_proc_wr_retry_buf_full_cnt,
    input                                       i_debug_cnt_en,
    input                                       i_debug_cnt_clr,

    input      [31:0]                           i_out_errsts_q_ba,
    input      [15:0]                           i_out_errsts_q_sz,
    output     [15:0]                           o_out_errsts_q_wrptr,
    input                                       i_intr_en_ill_opc_in_sq,
    input                                       i_intr_clr_ill_opc_in_sq,
    output                                      o_ill_opc_in_sq_intr,
    input      [C_OS_Q_INDX_WIDTH : 0]          os_num_vld_entries,
    input      [C_MAX_QP - 1 : 0]               i_osq_nacked,
    output                                      o_dma_in_idle,
    input      [C_MAX_QP - 1 : 0]               i_qp_fatal,
    input                                       i_qp_recovery,
    output     [C_MAX_QP - 1 : 0]               o_osq_nacked_resp

 );
`include "rdma_macros.vh"

 localparam HDR_BRAM_ADDR_WIDTH = clog2(C_MAX_HDR_DEPTH);

    wire                            buf_mngr_rdy;
    wire    [1023:0]                hdr_data;
    wire    [7:0]                   hdr_len;
    wire                            hdr_valid;
    wire                            hdr_gen_rdy;
    wire                            aeth_valid;
    wire    [31:0]                  aeth_hdr;
    wire    [C_MAX_QID_WIDTH-1:0]   aeth_qpid;
    wire    [23:0]                  aeth_psn;

    //buffer manager to MAXI signals
    wire    [C_M_AXI_ADDR_WIDTH-1 : 0]          maxi_addr;
    wire                                        maxi_wr_rdn;
    wire                                        maxi_en;
    wire    [7:0]                               maxi_len;
    wire    [C_M_AXI_DATA_WIDTH-1:0]            maxi_rdata;
    wire    [C_M_AXI_DATA_WIDTH-1:0]            maxi_wdata;
    wire                                        maxi_rvalid;
    wire                                        maxi_done;
    wire                                        maxi_busy;
    wire                                        maxi_error;
    wire                                        maxi_wdata_rdy;

    //SGL Buffer signals
    wire    [15:0]                             sgl_head_ptr;
    wire    [14:0]                             sgl_bram_rd_addr;
    wire                                       sgl_bram_rd_en;
    wire    [511:0]                            sgl_bram_rd_data;
    wire    [14:0]                             hdr_bram_rd_addr;
    wire                                       hdr_bram_rd_en;
    wire    [511:0]                            hdr_bram_rd_data;
    wire                                       hdr_bram_pop;
    //Buffer manager to SAXI signals

    wire  [C_AXIS_DATA_WIDTH-1 : 0]  axis_tdata_int;
    wire  [C_AXIS_DATA_WIDTH/8-1:0]  axis_tkeep_int;
    wire                             axis_tvalid_int;
    wire                             axis_tlast_int;
    wire                             axis_tready_int;
    wire  [C_AXIS_DATA_WIDTH-1 : 0]  m_axis_dma_tdata;
    wire  [C_AXIS_DATA_WIDTH/8-1:0]  m_axis_dma_tkeep;
    wire                             m_axis_dma_tvalid;
    wire                             m_axis_dma_tlast;
    wire                             m_axis_dma_tready;
    wire                             wqe_opcode_err;
    wire                             data_ptr_fifo_wr_en;      //Data buffer write enable to fifo in data re-align logic.
    wire  [31:0]                     data_ptr_fifo_data;
    wire                             data_buf_fifo_empty;

    wire    [C_M_AXI_ADDR_WIDTH-1 : 0]          maxi_wr_ddr_addr;
    wire                                        maxi_wr_ddr_wr_rdn;
    wire                                        maxi_wr_ddr_en;
    wire    [15:0]                              maxi_wr_ddr_len;
    wire    [C_M_AXI_DATA_WIDTH-1:0]            maxi_wr_ddr_wdata;
    wire                                        maxi_wr_ddr_done;
    wire                                        maxi_wr_ddr_busy;
    wire                                        maxi_wr_ddr_bvalid;
    wire                                        maxi_wr_ddr_error;
    wire                                        maxi_wr_ddr_wdata_rdy;

//////////////////////////////////////////////////////////////////////////////////
/////// WQE CRC wrapper block instance ///////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////

    wqe_proc_crc_wrap crc_wrap_inst (
        .core_clk(core_clk),
        .core_rst(core_rst),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),

        .s_axis_tdata(axis_tdata_int),
        .s_axis_tkeep(axis_tkeep_int),
        .s_axis_tvalid(axis_tvalid_int),
        .s_axis_tlast(axis_tlast_int),
        .s_axis_tready(axis_tready_int)
);

//////////////////////////////////////////////////////////////////////////////////
/////// WQE data re-alignment block instance /////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////

    wqe_proc_dre
    #(
        .C_AXIS_DATA_WIDTH (512),
        .C_M_AXI_DATA_WIDTH(C_M_AXI_DATA_WIDTH),
        .C_M_AXI_ADDR_WIDTH(C_M_AXI_ADDR_WIDTH),
        .C_M_AXI_ID_WIDTH(C_M_AXI_ID_WIDTH),
        .IP2BUS_LEN_WIDTH(16),
        .C_MAX_WRDATA_BUF_NUM(C_MAX_WRDATA_BUF_NUM),
        .C_EN_WR_RETRY_DATA_BUF(C_EN_WR_RETRY_DATA_BUF),
        .C_EN_DEBUG(C_EN_DEBUG),
        .C_FAMILY(C_FAMILY)
    ) dre_inst (
        .core_clk(core_clk),
        .core_rst(core_rst),
        .m_axis_tdata(axis_tdata_int),
        .m_axis_tkeep(axis_tkeep_int),
        .m_axis_tvalid(axis_tvalid_int),
        .m_axis_tready(axis_tready_int),
        .m_axis_tlast(axis_tlast_int),
        .s_axis_tdata(m_axis_dma_tdata),
        .s_axis_tkeep(m_axis_dma_tkeep),
        .s_axis_tvalid(m_axis_dma_tvalid),
        .s_axis_tlast(m_axis_dma_tlast),
        .s_axis_tready(m_axis_dma_tready),
        .i_data_ptr_fifo_wr_en(data_ptr_fifo_wr_en),
        .i_data_ptr_fifo_data(data_ptr_fifo_data),
        .o_data_buf_fifo_empty(data_buf_fifo_empty),
        .maxi_addr(maxi_wr_ddr_addr),
        .maxi_wr_rdn(maxi_wr_ddr_wr_rdn),
        .maxi_en(maxi_wr_ddr_en),
        .maxi_len(maxi_wr_ddr_len),
        .maxi_wdata_rdy(maxi_wr_ddr_wdata_rdy),
        .maxi_wdata(maxi_wr_ddr_wdata),
        .maxi_done(maxi_wr_ddr_done),
        .maxi_busy(maxi_wr_ddr_busy),
        .maxi_bvalid(maxi_wr_ddr_bvalid),
        .maxi_error(maxi_wr_ddr_error),
        .i_debug_cnt_en(i_debug_cnt_en),
        .i_debug_cnt_clr(i_debug_cnt_clr),
        .o_wqe_proc_wr_retry_buf_full_cnt(o_wqe_proc_wr_retry_buf_full_cnt)
    );

//////////////////////////////////////////////////////////////////////////////////
/////// WQE Header Generation block instance /////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
    wqe_proc_hdr_gen
    #(
        .C_MAX_QP(C_MAX_QP),
        .C_MAX_QID_WIDTH(C_MAX_QID_WIDTH),
        .C_OS_Q_INDX_WIDTH(C_OS_Q_INDX_WIDTH),
        .C_EN_DEBUG(C_EN_DEBUG),
        .C_MAX_WRDATA_BUF_NUM(C_MAX_WRDATA_BUF_NUM),
	.C_EN_WR_RETRY_DATA_BUF(C_EN_WR_RETRY_DATA_BUF)
    ) hdr_gen_inst (
        .core_clk(core_clk),
        .core_rst(core_rst),

        .i_qpm_fifo_empty(i_qpm_fifo_empty),
        .i_qpm_wqe_data(i_qpm_wqe_data),
        .o_qpm_wqe_pop(o_qpm_wqe_pop),
        .i_wqe_halt(i_wqe_halt),
        .i_wqe_halted_qpid(i_wqe_halted_qpid),
        .o_wqe_halted(o_wqe_halted),

        .o_reg_rd_en(o_reg_rd_en),
        .o_reg_rd_en_s(o_reg_rd_en_s),
        .i_reg_info_val(i_reg_rdy),
        .i_reg_psn_val(i_reg_psn_val),
        .o_reg_wr_en(o_reg_wr_en),
        .o_qp_id(o_qp_id),
        .i_reg_pkey(i_reg_pkey),
        .i_reg_qp_to(i_reg_qp_to),
        .i_reg_pmtu(i_reg_pmtu),
        .i_reg_dest_qpid(i_reg_dest_qpid),
        .i_reg_sq_psn(i_reg_sq_psn),
        .o_reg_sq_psn(o_reg_sq_psn),
        .i_reg_sq_msn(i_reg_sq_msn),
        .o_reg_sq_msn(o_reg_sq_msn),
        .i_reg_max_rd_atomic(i_reg_max_rd_atomic),
        .i_reg_mac_dest_addr(i_reg_mac_dest_addr),
        .i_reg_ip_dest_addr(i_reg_ip_dest_addr),
        .i_reg_udp_src_port(i_reg_udp_src_port),
        .i_reg_ttl(i_reg_ttl),
        .i_reg_dscp(i_reg_dscp),
        .i_reg_exp_ack(i_reg_exp_ack),

        .i_reg_mac_src_addr(i_reg_mac_src_addr),
        .i_reg_ipv4_src_addr(i_reg_ipv4_src_addr),
        .i_reg_ipv6_src_addr(i_reg_ipv6_src_addr),
        .i_reg_rdma_en(i_reg_rdma_en),
        .i_reg_ip_ver(i_reg_ip_ver),
        .i_reg_wrdata_buf_ba(i_reg_wrdata_buf_ba),
        .i_reg_wrdata_num_bufs(i_reg_wrdata_num_bufs),
        .i_reg_wrdata_buf_sz(i_reg_wrdata_buf_sz),

        .i_buf_mngr_rdy(buf_mngr_rdy),
        .o_hdr_data(hdr_data),
        .o_hdr_len(hdr_len),
        .o_hdr_valid(hdr_valid),
        .o_hdr_ip_ver(hdr_ip_ver),

        .o_wqp_req(o_wqp_req),
        .i_wqp_resp(i_wqp_resp),
        .o_wqe_qpid(o_wqe_qpid),
        .o_wqe_opcode(o_wqe_opcode),
        .o_wqe_wrid(o_wqe_wrid),
        .o_wqe_send_psn(o_wqe_send_psn),
        .o_wqe_send_first_psn(o_wqe_send_first_psn),
        .o_wqe_send_msn(o_wqe_send_msn),
        .o_wqe_explicit_ack_req(o_wqe_explicit_ack_req),
        .o_wqe_data_bufid(o_wqe_data_bufid),
        .o_wqe_qp_to(o_wqe_qp_to),
        .o_wqe_retried(o_wqe_retried),
        .i_freeup_data_buf(i_freeup_data_buf),
        .i_freeup_data_bufid(i_freeup_data_bufid),
        .i_wqe_os_fifo_full(i_wqe_os_fifo_full),

        .o_data_buf_fifo_wr_en(data_ptr_fifo_wr_en),
        .o_data_buf_fifo_data(data_ptr_fifo_data),
        .i_data_buf_fifo_empty(data_buf_fifo_empty),

        .o_hdr_gen_rdy(hdr_gen_rdy),
        .i_aeth_valid(aeth_valid),
        .i_aeth_hdr(aeth_hdr),
        .i_aeth_qpid(aeth_qpid),
        .i_aeth_psn(aeth_psn),
        .wqe_opcode_err(wqe_opcode_err),
        .wqe_status_out(o_wqe_status_out[11:0]),
        .o_last_out_pkt_info(o_last_out_pkt_info),
        .o_out_rw_pkt_cnt(o_out_rw_pkt_cnt),
        .o_out_ack_pkt_cnt(o_out_ack_pkt_cnt),
        .o_out_mad_pkt_cnt(o_out_mad_pkt_cnt),
        .os_num_vld_entries(os_num_vld_entries),
        .i_osq_nacked(i_osq_nacked),
        .o_osq_nacked_resp(o_osq_nacked_resp),
        .i_debug_cnt_en(i_debug_cnt_en),
        .i_debug_cnt_clr(i_debug_cnt_clr),
        .o_wqe_proc_idle_cnt(o_wqe_proc_idle_cnt),
        .o_wqe_proc_rd_wqe_cnt(o_wqe_proc_rd_wqe_cnt),
        .o_wqe_proc_rd_q_info_cnt(o_wqe_proc_rd_q_info_cnt),
        .o_wqe_proc_wait0_cnt(o_wqe_proc_wait0_cnt),
        .o_wqe_proc_ip_chksum_cnt(o_wqe_proc_ip_chksum_cnt),
        .o_wqe_proc_hdr_gen_cnt(o_wqe_proc_hdr_gen_cnt),
        .o_wqe_proc_hdr_sto_cnt(),
        .i_qp_fatal(i_qp_fatal),
        .i_qp_recovery(i_qp_recovery),
        .o_dma_in_idle(o_dma_in_idle),
        .dma_in_idle(dma_in_idle)
    );

//////////////////////////////////////////////////////////////////////////////////
/////// WQE buffer Management block instance /////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
    wqe_proc_buf_mgr
    #(
        .C_MAX_QP(C_MAX_QP),
        .C_MAX_QID_WIDTH(C_MAX_QID_WIDTH),
        .C_M_AXI_DATA_WIDTH(C_M_AXI_DATA_WIDTH),
        .C_M_AXI_ADDR_WIDTH(C_M_AXI_ADDR_WIDTH),
        .C_M_AXI_ID_WIDTH(C_M_AXI_ID_WIDTH),
        .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH),
        .C_S_AXI_ID_WIDTH(C_S_AXI_ID_WIDTH),
        .C_AXI_DMA_ADDR(C_AXI_DMA_ADDR),
        .IP2BUS_LEN_WIDTH(8),
        .C_EN_DEBUG(C_EN_DEBUG),
        .C_MAX_SGL_DEPTH(C_MAX_SGL_DEPTH),
        .C_MAX_HDR_DEPTH(C_MAX_HDR_DEPTH)
    ) buf_mgr_inst (
        .core_clk(core_clk),
        .core_rst(core_rst),
        .o_buf_mngr_rdy(buf_mngr_rdy),
        .i_hdr_data(hdr_data),
        .i_hdr_len(hdr_len),
        .i_hdr_valid(hdr_valid),
        .i_reg_tx_hdr_buf_ba(i_reg_tx_hdr_buf_ba),
        .i_reg_tx_hdr_buf_depth(i_reg_tx_hdr_buf_depth),
        .i_reg_tx_hdr_buf_size(i_reg_tx_hdr_buf_size),
        .i_reg_tx_sgl_buf_ba(i_reg_tx_sgl_buf_ba),
        .i_reg_tx_sgl_buf_depth(i_reg_tx_sgl_buf_depth),
        .i_reg_tx_sgl_buf_size(i_reg_tx_sgl_buf_size),
        .i_reg_ip_ver(hdr_ip_ver),
        .maxi_addr(maxi_addr),
        .maxi_wr_rdn(maxi_wr_rdn),
        .maxi_en(maxi_en),
        .maxi_len(maxi_len),
        .maxi_wdata_rdy(maxi_wdata_rdy),
        .maxi_wdata(maxi_wdata),
        .maxi_rdata(maxi_rdata),
        .maxi_rvalid(maxi_rvalid),
        .maxi_done(maxi_done),
        .maxi_busy(maxi_busy),
        .maxi_error(maxi_error),
        .sgl_head_ptr(sgl_head_ptr),
        .sgl_bram_rd_addr(sgl_bram_rd_addr),
        .sgl_bram_rd_en(sgl_bram_rd_en),
        .sgl_bram_rd_data(sgl_bram_rd_data),

        .hdr_bram_rd_addr(hdr_bram_rd_addr),
        .hdr_bram_rd_en(hdr_bram_rd_en),
        .hdr_bram_pop(hdr_bram_pop),
        .hdr_bram_rd_data(hdr_bram_rd_data),
        .buf_mgr_ptr(o_wqe_status_out[31:12]),
        .i_m_axis_bkp_pressure(m_axis_tvalid && !m_axis_tready),
        .wqe_opcode_err(wqe_opcode_err),
        .i_out_errsts_q_ba(i_out_errsts_q_ba),
        .i_out_errsts_q_sz(i_out_errsts_q_sz),
        .o_out_errsts_q_wrptr(o_out_errsts_q_wrptr),
        .i_intr_en_ill_opc_in_sq(i_intr_en_ill_opc_in_sq),
        .i_intr_clr_ill_opc_in_sq(i_intr_clr_ill_opc_in_sq),
        .o_ill_opc_in_sq_intr(o_ill_opc_in_sq_intr),
        .i_debug_cnt_en(i_debug_cnt_en),
        .i_debug_cnt_clr(i_debug_cnt_clr),
        .o_wqe_proc_hdr_sgl_buf_full_cnt(o_wqe_proc_hdr_sgl_buf_full_cnt),
        .o_wqe_proc_maxis_bk_pressure(o_wqe_proc_hdr_sto_cnt)
    );

//////////////////////////////////////////////////////////////////////////////////
/////// WQE DMA logic ////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
wqe_proc_dma
  #(
    .C_M_AXI_DATA_WIDTH(C_M_AXI_DATA_WIDTH),
    .C_M_AXI_ADDR_WIDTH(C_M_AXI_ADDR_WIDTH),
    .C_M_AXI_ID_WIDTH(C_M_AXI_ID_WIDTH),
    .C_AXIS_DATA_WIDTH(C_AXIS_DATA_WIDTH),
    .C_MAX_SGL_DEPTH(C_MAX_SGL_DEPTH),
    .C_SGL_DATA_WIDTH(512),    //C_SGL_DATA_WIDTH),
    .C_HDR_BUF_ADDR_WIDTH(HDR_BRAM_ADDR_WIDTH),
    .C_HDR_BUF_DEPTH(C_MAX_HDR_DEPTH),
    .C_VIVADO_VER (C_VIVADO_VER),
    .C_FAMILY(C_FAMILY)
    ) dma_inst (

    .core_clk(core_clk),
    .core_rst(core_rst),

    .m_axi_dma_arid(m_axi_arid),
    .m_axi_dma_araddr(m_axi_araddr),
    .m_axi_dma_arlen(m_axi_arlen),
    .m_axi_dma_arsize(m_axi_arsize),
    .m_axi_dma_arburst(m_axi_arburst),
    .m_axi_dma_arcache(m_axi_arcache),
    .m_axi_dma_arprot(m_axi_arprot),
    .m_axi_dma_arvalid(m_axi_arvalid),
    .m_axi_dma_arready(m_axi_arready),
    .m_axi_dma_rid(m_axi_rid),
    .m_axi_dma_rdata(m_axi_rdata),
    .m_axi_dma_rresp(m_axi_rresp),
    .m_axi_dma_rlast(m_axi_rlast),
    .m_axi_dma_rvalid(m_axi_rvalid),
    .m_axi_dma_rready(m_axi_rready),
    .m_axi_dma_arlock(m_axi_arlock),

    .m_axis_dma_tdata(m_axis_dma_tdata),
    .m_axis_dma_tkeep(m_axis_dma_tkeep),
    .m_axis_dma_tvalid(m_axis_dma_tvalid),
    .m_axis_dma_tready(m_axis_dma_tready),
    .m_axis_dma_tlast(m_axis_dma_tlast),

    .sgl_head_ptr(sgl_head_ptr),
    .sgl_bram_rd_addr(sgl_bram_rd_addr),
    .sgl_bram_rd_en(sgl_bram_rd_en),
    .sgl_bram_rd_data(sgl_bram_rd_data),

    .hdr_bram_rd_addr(hdr_bram_rd_addr),
    .hdr_bram_rd_en(hdr_bram_rd_en),
    .hdr_bram_rd_data(hdr_bram_rd_data),
    .hdr_bram_pop(hdr_bram_pop),

    .i_reg_tx_sgl_buf_depth(i_reg_tx_sgl_buf_depth),
    .o_dma_in_idle(dma_in_idle)
   );

//////////////////////////////////////////////////////////////////////////////////
/////// WQE Acknowledge buffer block instance ////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
    wqe_proc_ack_buf
    #(  .C_MAX_QID_WIDTH(C_MAX_QID_WIDTH),
        .C_MAX_QP(C_MAX_QP),
        .C_FAMILY (C_FAMILY)
    ) ack_buf_inst (
        .core_clk(core_clk),
        .core_rst(core_rst),
        .i_bres_valid(i_bres_valid),
        .i_bres_exp_ack(i_bres_exp_ack),
        .i_bres_dest_qpid(i_bres_dest_qpid),
        .o_bres_fifo_full(o_bres_fifo_full),
        .i_res_psn(i_res_psn),
        .i_res_aeth_syndrome(i_res_aeth_syndrome),
        .i_res_msn(i_res_msn),
        .i_hdr_gen_rdy(hdr_gen_rdy),
        .o_aeth_valid(aeth_valid),
        .o_aeth_hdr(aeth_hdr),
        .o_aeth_qpid(aeth_qpid),
        .o_aeth_psn(aeth_psn),
        .i_reg_rdma_en(i_reg_rdma_en),
        .ack_resp_strategy(i_reg_ack_resp_strategy)
    );

//////////////////////////////////////////////////////////////////////////////////
/////// RDMA OUT ERROR buffer writing AXI Master interface block instance ///////
//////////////////////////////////////////////////////////////////////////////////
    rdma_axi_master
    #(
       .C_M_AXI_ADDR_WIDTH(C_M_AXI_ADDR_WIDTH),
       .C_M_AXI_DATA_WIDTH(C_M_AXI_DATA_WIDTH),
       .C_M_AXI_THREAD_ID_WIDTH(C_M_AXI_ID_WIDTH),
       .IP2BUS_LEN_WIDTH(8)
     ) axi_master_if
    (
    // AXI System signals
        .m_axi_aclk(core_clk),   //m_axi_aclk),
        .m_axi_aresetn(~core_rst), //m_axi_aresetn),
    // AXI Master signals
        .m_axi_awid(m_axi_awid),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awcache(m_axi_awcache),
        .m_axi_awprot(m_axi_awprot),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_awlock(m_axi_awlock),
        .m_axi_bid(m_axi_bid),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .m_axi_arid(),    //m_axi_arid),
        .m_axi_araddr(),   //m_axi_araddr),
        .m_axi_arlen(),   //m_axi_arlen),
        .m_axi_arsize(),   //m_axi_arsize),
        .m_axi_arburst(),   //m_axi_arburst),
        .m_axi_arcache(),   //m_axi_arcache),
        .m_axi_arprot(),   //m_axi_arprot),
        .m_axi_arvalid(),   //m_axi_arvalid),
        .m_axi_arready(1'b1),   //m_axi_arready),
        .m_axi_rid({C_M_AXI_ID_WIDTH{1'b0}}),   //m_axi_rid),
        .m_axi_rdata(512'd0),   //m_axi_rdata),
        .m_axi_rresp(2'b00),   //m_axi_rresp),
        .m_axi_rlast(1'b0),   //m_axi_rlast),
        .m_axi_rvalid(1'b0),   //m_axi_rvalid),
        .m_axi_rready(),   //m_axi_rready),
        .m_axi_arlock(),   //m_axi_arlock),

        .bus2ip_byte_en(),
        .bus2ip_data(maxi_rdata),
        .bus2ip_dvalid(maxi_rvalid),
        .ip2bus_data(maxi_wdata),
        .bus2ip_data_rdy(maxi_wdata_rdy),
        .axi_m_en(maxi_en),
        .wr_rdn(maxi_wr_rdn),             //1 = write; 0 = read
        .ip2bus_addr(maxi_addr),
        .ip2bus_len(maxi_len),         //length in bytes

        .axi_master_done(maxi_done),
        .axi_master_busy(maxi_busy),
        .axi_master_error(maxi_error)

    );
//////////////////////////////////////////////////////////////////////////////////
/////// Write data to DDR AXI Master interface block instance ////////////////////
//////////////////////////////////////////////////////////////////////////////////
generate if(C_EN_WR_RETRY_DATA_BUF != 0) begin: WR_DATA_BUF
    rdma_axi_master
    #(
       .C_M_AXI_ADDR_WIDTH(C_M_AXI_ADDR_WIDTH),
       .C_M_AXI_DATA_WIDTH(C_M_AXI_DATA_WIDTH),
       .C_M_AXI_THREAD_ID_WIDTH(C_M_AXI_ID_WIDTH),
       .IP2BUS_LEN_WIDTH(16),
       .C_EN_OUTSTANDING_WRITE(1)
     ) axi_master_wr_ddr_if
    (
    // AXI System signals
        .m_axi_aclk(core_clk),   //m_axi_aclk),
        .m_axi_aresetn(~core_rst), //m_axi_aresetn),
    // AXI Master signals
        .m_axi_awid(m_axi_wr_ddr_awid),
        .m_axi_awaddr(m_axi_wr_ddr_awaddr),
        .m_axi_awlen(m_axi_wr_ddr_awlen),
        .m_axi_awsize(m_axi_wr_ddr_awsize),
        .m_axi_awburst(m_axi_wr_ddr_awburst),
        .m_axi_awcache(m_axi_wr_ddr_awcache),
        .m_axi_awprot(m_axi_wr_ddr_awprot),
        .m_axi_awvalid(m_axi_wr_ddr_awvalid),
        .m_axi_awready(m_axi_wr_ddr_awready),
        .m_axi_wdata(m_axi_wr_ddr_wdata),
        .m_axi_wstrb(m_axi_wr_ddr_wstrb),
        .m_axi_wlast(m_axi_wr_ddr_wlast),
        .m_axi_wvalid(m_axi_wr_ddr_wvalid),
        .m_axi_wready(m_axi_wr_ddr_wready),
        .m_axi_awlock(m_axi_wr_ddr_awlock),
        .m_axi_bid(m_axi_wr_ddr_bid),
        .m_axi_bresp(m_axi_wr_ddr_bresp),
        .m_axi_bvalid(m_axi_wr_ddr_bvalid),
        .m_axi_bready(m_axi_wr_ddr_bready),
        .m_axi_arid(m_axi_wr_ddr_arid),
        .m_axi_araddr(m_axi_wr_ddr_araddr),
        .m_axi_arlen(m_axi_wr_ddr_arlen),
        .m_axi_arsize(m_axi_wr_ddr_arsize),
        .m_axi_arburst(m_axi_wr_ddr_arburst),
        .m_axi_arcache(m_axi_wr_ddr_arcache),
        .m_axi_arprot(m_axi_wr_ddr_arprot),
        .m_axi_arvalid(m_axi_wr_ddr_arvalid),
        .m_axi_arready(m_axi_wr_ddr_arready),
        .m_axi_rid(m_axi_wr_ddr_rid),
        .m_axi_rdata(m_axi_wr_ddr_rdata),
        .m_axi_rresp(m_axi_wr_ddr_rresp),
        .m_axi_rlast(m_axi_wr_ddr_rlast),
        .m_axi_rvalid(m_axi_wr_ddr_rvalid),
        .m_axi_rready(m_axi_wr_ddr_rready),
        .m_axi_arlock(m_axi_wr_ddr_arlock),

        .bus2ip_byte_en(),
        .bus2ip_data(),
        .bus2ip_dvalid(),
        .ip2bus_data(maxi_wr_ddr_wdata),
        .bus2ip_data_rdy(maxi_wr_ddr_wdata_rdy),
        .axi_m_en(maxi_wr_ddr_en),
        .wr_rdn(maxi_wr_ddr_wr_rdn),             //1 = write; 0 = read
        .ip2bus_addr(maxi_wr_ddr_addr),
        .ip2bus_len(maxi_wr_ddr_len),         //length in bytes

        .axi_master_done(maxi_wr_ddr_done),
        .axi_master_busy(maxi_wr_ddr_busy),
        .axi_master_bvalid(maxi_wr_ddr_bvalid),
        .axi_master_error(maxi_wr_ddr_error)

    );
end else begin:NO_WR_DATA_BUF

    assign m_axi_wr_ddr_awid = {C_M_AXI_ID_WIDTH{1'b0}};
    assign m_axi_wr_ddr_awaddr = {C_M_AXI_ADDR_WIDTH{1'b0}};
    assign m_axi_wr_ddr_awlen = 8'h00;
    assign m_axi_wr_ddr_awsize = 3'b000;
    assign m_axi_wr_ddr_awburst = 2'b00;
    assign m_axi_wr_ddr_awcache = 4'h0;
    assign m_axi_wr_ddr_awprot = 3'b000;
    assign m_axi_wr_ddr_awvalid = 1'b0;
    assign m_axi_wr_ddr_wdata = {C_M_AXI_DATA_WIDTH{1'b0}};
    assign m_axi_wr_ddr_wstrb = {C_M_AXI_DATA_WIDTH/8{1'b0}};
    assign m_axi_wr_ddr_wlast = 1'b0;
    assign m_axi_wr_ddr_wvalid = 1'b0;
    assign m_axi_wr_ddr_awlock = 1'b0;
    assign m_axi_wr_ddr_bready = 1'b1;
    assign m_axi_wr_ddr_arid = {C_M_AXI_ID_WIDTH{1'b0}};
    assign m_axi_wr_ddr_araddr = {C_M_AXI_ADDR_WIDTH{1'b0}};
    assign m_axi_wr_ddr_arlen = 8'h00;
    assign m_axi_wr_ddr_arsize = 3'b000;
    assign m_axi_wr_ddr_arburst = 2'b00;
    assign m_axi_wr_ddr_arcache = 4'h0;
    assign m_axi_wr_ddr_arprot = 3'b000;
    assign m_axi_wr_ddr_arvalid = 1'b0;
    assign m_axi_wr_ddr_rready = 1'b1;
    assign m_axi_wr_ddr_arlock = 1'b0;
    assign axi_wr_ddr_bvalid = 1'b0;
end
endgenerate

endmodule

