// wqe_proc_hdr_gen.v
// 文件名          : wqe_proc_hdr_gen.v
// 版本            : v1.0
// 描述            : WQE 包头生成模块，根据寄存器配置和 WQE 内容组装 RoCEv2 数据包
//                   生成 ETH/IP/UDP/BTH/RETH 等协议头部，拼接 Payload 数据
// Verilog 标准    : Verilog'2001

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
`timescale 1ps/1ps

(* DowngradeIPIdentifiedWarnings="yes" *)
module wqe_proc_hdr_gen
#(
    parameter C_MAX_QP = 8,
    parameter C_MAX_QID_WIDTH = 3,
    parameter C_MAX_WRDATA_BUF_NUM = 128,
    parameter C_OS_Q_INDX_WIDTH = 3,
    parameter C_EN_DEBUG = 0,
    parameter C_EN_WR_RETRY_DATA_BUF = 1
 ) (
    input                    core_clk,
    input                    core_rst,

    input                                       i_qpm_fifo_empty,
    input      [511:0]                          i_qpm_wqe_data,
    output reg                                  o_qpm_wqe_pop,
    input                                       i_wqe_halt,
    input      [C_MAX_QID_WIDTH -1 :0]          i_wqe_halted_qpid,
    output reg                                  o_wqe_halted,

    output reg                                  o_reg_rd_en,
    output reg                                  o_reg_rd_en_s,
    input                                       i_reg_info_val,
    input                                       i_reg_psn_val,
    output reg                                  o_reg_wr_en,
    output reg [C_MAX_QID_WIDTH-1:0]            o_qp_id,
    input      [15:0]                           i_reg_pkey,
    input      [2:0]                            i_reg_pmtu,
    input      [23:0]                           i_reg_dest_qpid,
    input      [23:0]                           i_reg_sq_psn,
    output reg [23:0]                           o_reg_sq_psn,
    input      [23:0]                           i_reg_sq_msn,
    output reg [23:0]                           o_reg_sq_msn,
    input      [7:0]                            i_reg_max_rd_atomic,
    input      [47:0]                           i_reg_mac_dest_addr,
    input      [31:0]                           i_reg_ip_dest_addr,
    input      [15:0]                           i_reg_udp_src_port,
    input      [7:0]                            i_reg_ttl,
    input      [5:0]                            i_reg_dscp,
    input                                       i_reg_exp_ack,
    input      [31:0]                           i_reg_wrdata_buf_ba,
    input      [15:0]                           i_reg_wrdata_num_bufs,
    input      [15:0]                           i_reg_wrdata_buf_sz,
    input                                       i_freeup_data_buf,
    input      [14:0]                           i_freeup_data_bufid,
    input      [4:0]                            i_reg_qp_to,

    input      [47:0]                           i_reg_mac_src_addr,
    input      [31:0]                           i_reg_ipv4_src_addr,
    input      [127:0]                          i_reg_ipv6_src_addr,
    input                                       i_reg_rdma_en,
    input                                       i_reg_ip_ver,

    input                                       i_buf_mngr_rdy,
    output reg [1023:0]                         o_hdr_data,
    output reg [7:0]                            o_hdr_len,
    output reg                                  o_hdr_valid,
    output reg                                  o_hdr_ip_ver,

   (* mark_debug = "true" *) output reg                                  o_wqp_req,
   (* mark_debug = "true" *) input                                       i_wqp_resp,
    output reg [C_MAX_QID_WIDTH-1:0]            o_wqe_qpid,
    output reg [7:0]                            o_wqe_opcode,
    output reg [15:0]                           o_wqe_wrid,
    output reg [23:0]                           o_wqe_send_psn,
    output reg [14:0]                           o_wqe_data_bufid,
    output reg [4:0]                            o_wqe_qp_to,
    output reg                                  o_wqe_retried,
    output reg [23:0]                           o_wqe_send_first_psn,
    output reg [23:0]                           o_wqe_send_msn,
    output reg                                  o_wqe_explicit_ack_req,
   (* mark_debug = "true" *) input     [C_MAX_QP-1:0]                    i_wqe_os_fifo_full,

    output reg                                  o_hdr_gen_rdy,
    input                                       i_aeth_valid,
    input      [31:0]                           i_aeth_hdr,
    input      [C_MAX_QID_WIDTH-1:0]            i_aeth_qpid,
    input      [23:0]                           i_aeth_psn,

    output reg                                  wqe_opcode_err,
    output reg [7:0]                            err_opcode,
    output     [11:0]                           wqe_status_out,
    output reg [31:0]                           o_last_out_pkt_info,
    output reg [15:0]                           o_out_rw_pkt_cnt,
    output reg [15:0]                           o_out_ack_pkt_cnt,
    output reg [15:0]                           o_out_mad_pkt_cnt,
    input      [C_OS_Q_INDX_WIDTH : 0]          os_num_vld_entries,
    input      [C_MAX_QP - 1 : 0]               i_osq_nacked,
    input      [C_MAX_QP - 1 : 0]               i_qp_fatal,
    input                                       i_qp_recovery,
    output reg [C_MAX_QP - 1 : 0]               o_osq_nacked_resp,
    output reg                                  o_data_buf_fifo_wr_en,
    output reg [31:0]                           o_data_buf_fifo_data,
    input                                       i_data_buf_fifo_empty,
    input                                       dma_in_idle,
    output                                      o_dma_in_idle,

    input                                       i_debug_cnt_en,
    input                                       i_debug_cnt_clr,
    output reg [15:0]                           o_wqe_proc_idle_cnt,
    output reg [15:0]                           o_wqe_proc_rd_wqe_cnt,
    output reg [15:0]                           o_wqe_proc_rd_q_info_cnt,
    output reg [15:0]                           o_wqe_proc_wait0_cnt,
    output reg [15:0]                           o_wqe_proc_ip_chksum_cnt,
    output reg [15:0]                           o_wqe_proc_hdr_gen_cnt,
    output reg [15:0]                           o_wqe_proc_hdr_sto_cnt

);

   `include "rdma_macros.vh"

    localparam IDLE = 3'b000;
    localparam RD_WQE = 3'b001;
    localparam RD_Q_INFO = 3'b010;
    localparam WAIT0 = 3'b011;
    localparam IP_CHKSUM = 3'b100;
    localparam HDR_GEN = 3'b101;
    localparam HDR_STO = 3'b110;
    localparam ILL_OPCODE = 3'b111;
    localparam OS_TH_ENTRIES = 3;
    localparam DATA_BUF_ID_WIDTH = clog2(C_MAX_WRDATA_BUF_NUM);

    reg  [111:0]    eth_hdr;
    reg  [319:0]    ip_hdr;
    reg  [63:0]     udp_hdr;
    reg  [95:0]     bth_hdr;
    reg  [127:0]    reth_hdr;
    reg  [31:0]     aeth_hdr;
   (* mark_debug = "true" *) reg  [2:0]      hdr_gen_cs;
    reg  [19:0]     ip_hdr_chksum;
    reg  [31:0]     rem_len;
    reg  [31:0]     dma_len;
   (* mark_debug = "true" *) reg  [7:0]      wqe_opcode;
    reg             first_trans;
    reg  [15:0]     payload_len;
    reg             reth_present;
    reg  [63:0]     local_offset;
    reg  [63:0]     remote_offset;
    reg  [31:0]     r_key;
   (* mark_debug = "true" *) reg             wqe_push_pending;
    reg             aeth_pkt;
    reg             chksum_cal_start;
    reg  [127:0]    nvme_comp_data;
    reg             completion_data_present;
    reg  [12:0]     max_pmtu;
    reg  [23:0]     dest_qpid;
    wire [15:0]     q_id;
    wire [15:0]     ipv6_len;
    wire [15:0]     ipv4_len;
    reg  [47:0]     mac_dest_addr;
    reg  [31:0]     ip_dest_addr;
    reg             ip_ver;
    reg             exp_ack;
    reg             wqe_os_fifo_full;
    reg [15:0]      ipv4_identification;
    reg             push_to_os_buf;
    //Added for performance update. FSM will proceed to the next header generation logic
    //and waits in HDR_GEN state until this signal is de-asserted
    reg             buf_mgr_busy;
    reg [4:0]       reg_qp_to;
    reg             wait_for_dma_idle;
    reg             qp_fatal_detected;

    reg                            retried;
    wire [DATA_BUF_ID_WIDTH-1 : 0] data_bufid;
    reg  [DATA_BUF_ID_WIDTH-1 : 0] retried_buf_id;
    reg                            get_data_buf;
    wire [31:0]                    data_buf_addr;
    wire                           no_data_buf_left;
    integer i;

    assign q_id = {{16-C_MAX_QID_WIDTH{1'b0}},o_qp_id};
    assign ipv6_len = (8'h18 + payload_len + {reth_present,1'b0,aeth_pkt,2'b00});
    assign ipv4_len = (8'h2C + payload_len + {reth_present,1'b0,aeth_pkt,2'b00});
    assign wqe_status_out = {5'h00,buf_mgr_busy,i_data_buf_fifo_empty,no_data_buf_left,wqe_push_pending,hdr_gen_cs};

//////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////// Debug counters logic //////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////
    generate if(C_EN_DEBUG == 1) begin:DEBUG_EN
        always @(posedge core_clk)
        begin
            if(core_rst) begin
                o_wqe_proc_idle_cnt <= 16'h0000;
            end else begin
                if(i_debug_cnt_clr) begin
                    o_wqe_proc_idle_cnt <= 16'h0000;
                end else if (i_debug_cnt_en && (hdr_gen_cs == IDLE)) begin
                    o_wqe_proc_idle_cnt <= o_wqe_proc_idle_cnt + 1'b1;
                end
            end
        end
        always @(posedge core_clk)
        begin
            if(core_rst) begin
                o_wqe_proc_rd_wqe_cnt <= 16'h0000;
            end else begin
                if(i_debug_cnt_clr) begin
                    o_wqe_proc_rd_wqe_cnt <= 16'h0000;
                end else if (i_debug_cnt_en && ((hdr_gen_cs == IDLE) && i_qpm_fifo_empty) ) begin
                    o_wqe_proc_rd_wqe_cnt <= o_wqe_proc_rd_wqe_cnt + 1'b1;
                end
            end
        end
        always @(posedge core_clk)
        begin
            if(core_rst) begin
                o_wqe_proc_rd_q_info_cnt <= 16'h0000;
            end else begin
                if(i_debug_cnt_clr) begin
                    o_wqe_proc_rd_q_info_cnt <= 16'h0000;
                end else if (i_debug_cnt_en && (hdr_gen_cs == RD_Q_INFO) ) begin
                    o_wqe_proc_rd_q_info_cnt <= o_wqe_proc_rd_q_info_cnt + 1'b1;
                end
            end
        end
        always @(posedge core_clk)
        begin
            if(core_rst) begin
                o_wqe_proc_wait0_cnt <= 16'h0000;
            end else begin
                if(i_debug_cnt_clr) begin
                    o_wqe_proc_wait0_cnt <= 16'h0000;
                end else if (i_debug_cnt_en && (hdr_gen_cs == WAIT0)) begin
                    o_wqe_proc_wait0_cnt <= o_wqe_proc_wait0_cnt + 1'b1;
                end
            end
        end
        always @(posedge core_clk)
        begin
            if(core_rst) begin
                o_wqe_proc_ip_chksum_cnt <= 16'h0000;
            end else begin
                if(i_debug_cnt_clr) begin
                    o_wqe_proc_ip_chksum_cnt <= 16'h0000;
                end else if (i_debug_cnt_en && (hdr_gen_cs == IP_CHKSUM)) begin
                    o_wqe_proc_ip_chksum_cnt <= o_wqe_proc_ip_chksum_cnt + 1'b1;
                end
            end
        end
        always @(posedge core_clk)
        begin
            if(core_rst) begin
                o_wqe_proc_hdr_gen_cnt <= 16'h0000;
            end else begin
                if(i_debug_cnt_clr) begin
                    o_wqe_proc_hdr_gen_cnt <= 16'h0000;
                end else if (i_debug_cnt_en && (hdr_gen_cs == HDR_GEN)) begin
                    o_wqe_proc_hdr_gen_cnt <= o_wqe_proc_hdr_gen_cnt + 1'b1;
                end
            end
        end
        //begin
        //    if(core_rst) begin
        //        o_wqe_proc_hdr_sto_cnt <= 16'h0000;
        //        if(i_debug_cnt_clr) begin
        //            o_wqe_proc_hdr_sto_cnt <= 16'h0000;
        //        //end else if (i_debug_cnt_en && (hdr_gen_cs == HDR_STO)) begin
        //            o_wqe_proc_hdr_sto_cnt <= o_wqe_proc_hdr_sto_cnt + 1'b1;
        //        end
        //    end
        //end
    end else begin
        always @(*) begin
            o_wqe_proc_idle_cnt = 16'h0000;
            o_wqe_proc_rd_wqe_cnt = 16'h0000;
            o_wqe_proc_rd_q_info_cnt = 16'h0000;
            o_wqe_proc_wait0_cnt = 16'h0000;
            o_wqe_proc_ip_chksum_cnt = 16'h0000;
            o_wqe_proc_hdr_gen_cnt = 16'h0000;
            o_wqe_proc_hdr_sto_cnt = 16'h0000;
        end
    end
    endgenerate

always@(posedge core_clk)
begin
    if(core_rst) begin
        eth_hdr <= 'd0;
        ip_hdr <= 'd0;
        udp_hdr <= 'd0;
        bth_hdr <= 'd0;
        reth_hdr <= 'd0;
        aeth_hdr <= 'd0;
        o_hdr_data <= 'd0;
        o_hdr_valid <= 1'b0;
        o_hdr_ip_ver <= 1'b0;
        o_hdr_len <= 8'h00;
        o_qpm_wqe_pop <= 1'b0;
        o_qp_id <= {C_MAX_QID_WIDTH{1'b0}};
        o_reg_rd_en <= 1'b0;
        o_reg_rd_en_s <= 1'b0;
        hdr_gen_cs <= IDLE;
        ip_hdr_chksum <= 20'd0;
        rem_len <= 32'd0;
        dma_len <= 32'd0;
        first_trans <= 1'b0;
        payload_len <= 16'h0000;
        reth_present <= 1'b0;
        remote_offset <= 64'd00;
        local_offset <= 64'd00;
        aeth_pkt <= 1'b0;
        wqe_opcode <= 8'h00;
        r_key <= 32'd0;
        chksum_cal_start <= 1'b0;
        nvme_comp_data <= 128'd0000;
        completion_data_present <= 1'b0;
        o_reg_wr_en <= 1'b0;
        wqe_opcode_err <= 1'b0;
        err_opcode <= 8'h00;
        dest_qpid <= 24'd0;
        o_hdr_gen_rdy <= 1'b0;
        o_reg_sq_psn <= 24'd0;
        o_wqe_send_first_psn <= 24'd0;
        o_reg_sq_msn <= 24'd0;
        o_wqe_wrid <= 16'h0000;
        mac_dest_addr <= 'd0;
        ip_dest_addr <= 'd0;
        ip_ver <= 1'b0;
        exp_ack <= 1'b0;
        o_out_rw_pkt_cnt <= 16'h0000;
        o_out_ack_pkt_cnt <= 16'h0000;
        o_out_mad_pkt_cnt <= 16'h0000;
        o_wqe_halted <= 1'b0;
        wqe_os_fifo_full <= 1'b0;
        ipv4_identification <= 16'h0000;
        retried <= 1'b0;
        get_data_buf <= 1'b0;
        o_data_buf_fifo_data <= 32'd0;
        o_data_buf_fifo_wr_en <= 1'b0;
        o_osq_nacked_resp <= 'd0;
        push_to_os_buf <= 1'b0;
        buf_mgr_busy <= 1'b0;
        reg_qp_to <= 5'h00;
        wait_for_dma_idle <= 1'b0;
        qp_fatal_detected<= 1'b0;
    end else begin
        qp_fatal_detected<= |i_qp_fatal;
        if(~wqe_push_pending && (hdr_gen_cs == HDR_STO || hdr_gen_cs == ILL_OPCODE)) begin
            o_hdr_valid <= 1'b1;
            o_hdr_ip_ver <= ip_ver;
        end else if(i_buf_mngr_rdy) begin
            o_hdr_valid <= 1'b0;
        end
        if(o_hdr_valid && ~i_buf_mngr_rdy) begin
            buf_mgr_busy <= 1'b1;
        end else if(i_buf_mngr_rdy) begin
            buf_mgr_busy <= 1'b0;
        end
        if(hdr_gen_cs == IDLE && i_wqe_halt && ~o_reg_wr_en) begin
            o_wqe_halted <= 1'b1;
        end else if(~i_wqe_halt) begin
            o_wqe_halted <= 1'b0;
        end
        if(|i_qp_fatal && ~qp_fatal_detected) begin
            wait_for_dma_idle <= 1'b1;
        end else if(dma_in_idle) begin
            wait_for_dma_idle <= 1'b0;
        end

        case (hdr_gen_cs)
            IDLE: begin
                push_to_os_buf <= 1'b0;
                retried <= 1'b0;
                get_data_buf <= 1'b0;
                o_data_buf_fifo_wr_en <= 1'b0;
                o_hdr_gen_rdy <= 1'b0;
                o_osq_nacked_resp <= i_osq_nacked;
                if(i_reg_psn_val) begin
                    o_reg_wr_en <= 1'b0;
                end
                if((i_aeth_valid) && ~o_reg_wr_en) begin
                    hdr_gen_cs <= RD_Q_INFO;
                    o_qp_id <= i_aeth_qpid;
                    o_reg_rd_en <= 1'b1;
                    o_reg_rd_en_s <= 1'b1;
                    aeth_pkt <= 1'b1;
                    aeth_hdr <= i_aeth_hdr;
                end else if(~i_qpm_fifo_empty && ~o_reg_wr_en && ~i_wqe_halt && ~wait_for_dma_idle) begin
                    o_qpm_wqe_pop <= 1'b1;
                    hdr_gen_cs <= RD_WQE;
`ifdef SIMULATION
                    $display("[%0t] HDR_GEN: IDLE -> RD_WQE (fifo_empty=%b reg_wr=%b halt=%b dma_wait=%b)",
                             $time, i_qpm_fifo_empty, o_reg_wr_en, i_wqe_halt, wait_for_dma_idle);
`endif
                end else begin
                    o_reg_rd_en <= 1'b0;
                    o_reg_rd_en_s <= 1'b0;
`ifdef SIMULATION
                    if($time > 5000 && qp_fatal_detected)
                        $display("[%0t] HDR_GEN: IDLE stall (fifo_empty=%b reg_wr=%b halt=%b dma_wait=%b fatal=%b)",
                                 $time, i_qpm_fifo_empty, o_reg_wr_en, i_wqe_halt, wait_for_dma_idle, qp_fatal_detected);
`endif
                end
            end
            RD_WQE: begin
                o_qpm_wqe_pop <= 1'b0;
                if(o_qpm_wqe_pop == 1'b0) begin
                    o_wqe_wrid <= i_qpm_wqe_data[15:0];
                    o_qp_id <= i_qpm_wqe_data[136+C_MAX_QID_WIDTH-1 : 136];
                    dma_len <= i_qpm_wqe_data[127:96];
                    rem_len <= i_qpm_wqe_data[127:96];
                    wqe_opcode <= i_qpm_wqe_data[135:128];
                    local_offset <= i_qpm_wqe_data[95:32];
                    remote_offset <= i_qpm_wqe_data[223:160];
                    r_key <= i_qpm_wqe_data[255:224];
                    nvme_comp_data <= i_qpm_wqe_data[129] ? i_qpm_wqe_data[383:256] : 128'd0000;
                    completion_data_present <= (i_qpm_wqe_data[130:128] == 3'b010) && ~(i_qpm_wqe_data[127:96] > 32'h00000010);
                    o_reg_rd_en <= 1'b1;
                    o_reg_rd_en_s <= 1'b1;
                    hdr_gen_cs <= RD_Q_INFO;
                    first_trans <= 1'b1;
                    retried_buf_id <= i_qpm_wqe_data[17+:DATA_BUF_ID_WIDTH];
                    retried <= i_qpm_wqe_data[16];
`ifdef SIMULATION
                    $display("[%0t] HDR_GEN: RD_WQE -> RD_Q_INFO: opcode=%h dma_len=%h local_off=%h remote_off=%h rkey=%h wrid=%h",
                             $time, i_qpm_wqe_data[135:128], i_qpm_wqe_data[127:96], i_qpm_wqe_data[95:32],
                             i_qpm_wqe_data[223:160], i_qpm_wqe_data[255:224], i_qpm_wqe_data[15:0]);
`endif
                end
            end
            RD_Q_INFO: begin
                if(i_reg_info_val) begin
                    if(o_qp_id == 1) begin
                        hdr_gen_cs <= HDR_GEN;
                        payload_len <= rem_len;
                        rem_len <= 32'd0;
                    end else if((i_osq_nacked[o_qp_id] || i_qp_fatal[o_qp_id] || i_qp_recovery || (i_wqe_halt && (i_wqe_halted_qpid == o_qp_id)))  && ~aeth_pkt) begin
                        hdr_gen_cs <= IDLE;
                        push_to_os_buf <= (i_qp_fatal[o_qp_id] || i_qp_recovery) ? 1'b1 : 1'b0;
                        o_reg_rd_en <= 1'b0;
                        first_trans <= 1'b0;
                        completion_data_present <= 1'b0;
                        o_osq_nacked_resp <= i_osq_nacked;
                    end else if(wqe_opcode != 8'h00) begin
                        hdr_gen_cs <= ILL_OPCODE;
                    end else begin
                        hdr_gen_cs <= WAIT0;
                    end
                    exp_ack <= i_reg_exp_ack;
                    o_reg_rd_en_s <= 1'b0;
                    dest_qpid <= i_reg_dest_qpid;
                    mac_dest_addr <= i_reg_mac_dest_addr;
                    ip_dest_addr <= i_reg_ip_dest_addr;
                    ip_ver <= i_reg_ip_ver;
                    o_reg_sq_psn <= i_reg_sq_psn;
                    o_wqe_send_first_psn <= i_reg_sq_psn;
                    o_reg_sq_msn <= i_reg_sq_msn+1'b1;
                    reg_qp_to <= i_reg_qp_to;
                end
                //for (i = 0; i < C_MAX_QP; i = i+1) begin
                //     if(o_qp_id == i) begin
                //         wqe_os_fifo_full <= i_wqe_os_fifo_full[i];
                //     end
                //end
                wqe_os_fifo_full <= (os_num_vld_entries >= OS_TH_ENTRIES);

                case(i_reg_pmtu)
                    3'b000: begin
                        max_pmtu <= 13'h0100;
                    end
                    3'b001: begin
                        max_pmtu <= 13'h0200;
                    end
                    3'b010: begin
                        max_pmtu <= 13'h0400;
                    end
                    3'b011: begin
                        max_pmtu <= 13'h0800;
                    end
                    3'b100: begin
                        max_pmtu <= 13'h1000;
                    end
                    default: begin
                        max_pmtu <= 13'h100;
                    end
                endcase
            end

            WAIT0: begin
                get_data_buf <= 1'b0;
                o_data_buf_fifo_wr_en <= 1'b0;
                push_to_os_buf <= 1'b0;
                if(i_reg_psn_val) begin
                    o_reg_wr_en <= 1'b0;
                end
                if(ip_ver && ~o_reg_wr_en) begin
                    hdr_gen_cs <= HDR_GEN;
                end else if(~ip_ver && ~o_reg_wr_en)begin
                    hdr_gen_cs <= IP_CHKSUM;
                    ipv4_identification <= ipv4_identification + 1'b1;
                end

                if(~o_reg_wr_en) begin
                    if(aeth_pkt) begin
                        payload_len <= 32'd0;
                        rem_len <= 32'd0;
                        reth_present <= 1'b0;
                    end else if((({19'd0,max_pmtu} < rem_len) || first_trans) && (wqe_opcode == 8'h00)) begin
                        payload_len <= ({19'd0,max_pmtu} < rem_len) ? max_pmtu : rem_len;
                        rem_len <= ({19'd0,max_pmtu} < rem_len) ? rem_len - {19'd0,max_pmtu} : 32'd0;
                        reth_present <= first_trans;
                    end else if((({19'd0,max_pmtu} < rem_len) || first_trans) && (wqe_opcode == 8'h02)) begin
                        payload_len <= ({19'd0,max_pmtu} < rem_len) ? max_pmtu : rem_len;
                        rem_len <= ({19'd0,max_pmtu} < rem_len) ? rem_len - {19'd0,max_pmtu} : 32'd0;
                        reth_present <= 1'b0;
                    end else if (wqe_opcode == 8'h04) begin
                        payload_len <= 32'd0;
                        rem_len <= rem_len;
                        reth_present <= 1'b1;
                    end else begin
                        payload_len <= rem_len;
                        rem_len <= 32'd0;
                        reth_present <= 1'b0;
                    end
                end
            end
            IP_CHKSUM: begin
                if(~chksum_cal_start) begin
                    ip_hdr_chksum <= 16'h4500 +  ipv4_len[15:0] + ipv4_identification[15:0] + 16'h4000 + { i_reg_ttl,8'h11} +
                                    i_reg_ipv4_src_addr[31:16] + i_reg_ipv4_src_addr[15:0] +
                                    ip_dest_addr[31:16] + ip_dest_addr[15:0];
                    chksum_cal_start <= 1'b1;
                end else begin
                    if(|ip_hdr_chksum[19:16]) begin
                        ip_hdr_chksum <= ip_hdr_chksum[15:0] + ip_hdr_chksum[19:16];
                    end else begin
                        chksum_cal_start <= 1'b0;
                        hdr_gen_cs <= HDR_GEN;
                    end
                end
            end
            HDR_GEN: begin
                if(~no_data_buf_left && ~buf_mgr_busy && ((wqe_opcode != 8'h00) || (~retried || i_data_buf_fifo_empty))) begin
                    wqe_opcode_err <= 1'b0;
                    eth_hdr <= {(ip_ver ? 16'hDD86 : 16'h0008), i_reg_mac_src_addr[7:0], i_reg_mac_src_addr[15:8], i_reg_mac_src_addr[23:16], i_reg_mac_src_addr[31:24], i_reg_mac_src_addr[39:32], i_reg_mac_src_addr[47:40],
                                 mac_dest_addr[7:0], mac_dest_addr[15:8], mac_dest_addr[23:16], mac_dest_addr[31:24], mac_dest_addr[39:32], mac_dest_addr[47:40]};
                    if(ip_ver) begin
                        ip_hdr <= {96'd0, ip_dest_addr[7:0], ip_dest_addr[15:8], ip_dest_addr[23:16], ip_dest_addr[31:24],
                                   i_reg_ipv6_src_addr[7:0], i_reg_ipv6_src_addr[15:8], i_reg_ipv6_src_addr[23:16], i_reg_ipv6_src_addr[31:24], i_reg_ipv6_src_addr[39:32], i_reg_ipv6_src_addr[47:40], i_reg_ipv6_src_addr[55:48], i_reg_ipv6_src_addr[63:56], i_reg_ipv6_src_addr[71:64], i_reg_ipv6_src_addr[79:72], i_reg_ipv6_src_addr[87:80], i_reg_ipv6_src_addr[95:88], i_reg_ipv6_src_addr[103:96], i_reg_ipv6_src_addr[111:104], i_reg_ipv6_src_addr[119:112], i_reg_ipv6_src_addr[127:120],
                                   i_reg_ttl, 8'h11, ipv6_len[7:0], ipv6_len[15:8], q_id[7:0], q_id[15:8], {i_reg_dscp[1:0],2'b00, 4'h0}, {4'h6,i_reg_dscp[5:2]}};
                    end else begin
                        ip_hdr[159:96] <= {ip_dest_addr[7:0],ip_dest_addr[15:8],ip_dest_addr[23:16],ip_dest_addr[31:24], i_reg_ipv4_src_addr[7:0],i_reg_ipv4_src_addr[15:8],i_reg_ipv4_src_addr[23:16],i_reg_ipv4_src_addr[31:24]};
                        ip_hdr[95:80] <= {~ip_hdr_chksum[7:0],~ip_hdr_chksum[15:8]};
                        ip_hdr[79:0] <= {8'h11,i_reg_ttl,16'h0040,ipv4_identification[7:0], ipv4_identification[15:8],ipv4_len[7:0], ipv4_len[15:8], 16'h0045};
                    end
                    udp_hdr <= {16'h0000, ipv6_len[7:0],ipv6_len[15:8], 16'hB712, i_reg_udp_src_port[7:0], i_reg_udp_src_port[15:8]};   //Need to check that UDP destination port is decimal or hexa, considering it as decimal 4791 for now
                    if(aeth_pkt) begin
                        bth_hdr[95:72] <= {i_aeth_psn[7:0], i_aeth_psn[15:8], i_aeth_psn[23:16]};
                        bth_hdr[70:32] <= {7'h00,  dest_qpid[7:0], dest_qpid[15:8], dest_qpid[23:16], 8'h00};
                    end else begin
                        //bth_hdr[95:32] <= {o_reg_sq_psn[7:0], o_reg_sq_psn[15:8], o_reg_sq_psn[23:16], (exp_ack || wqe_os_fifo_full), 7'h00,  dest_qpid[7:0], dest_qpid[15:8], dest_qpid[23:16], 8'h00};
                        bth_hdr[95:72] <= {o_reg_sq_psn[7:0], o_reg_sq_psn[15:8], o_reg_sq_psn[23:16]};
                        bth_hdr[70:32] <= {7'h00,  dest_qpid[7:0], dest_qpid[15:8], dest_qpid[23:16], 8'h00};
                    end
                    bth_hdr[31:16] <= {i_reg_pkey[7:0],i_reg_pkey[15:8]};
                    bth_hdr[14:8] <= {1'b0,2'b00,4'h0};
                    if((|rem_len && (wqe_opcode == 8'h00)) || aeth_pkt) begin
                        bth_hdr[15] <= 1'b0;
                    end else begin
                        bth_hdr[15] <= 1'b1;
                    end
                    if(aeth_pkt) begin
                        bth_hdr[7:0] <= 8'h11;
                        bth_hdr[71] <= 1'b0;
                    end else if(wqe_opcode == 8'h00) begin
                        o_out_rw_pkt_cnt <= o_out_rw_pkt_cnt + 1'b1;
                        bth_hdr[71] <= (~|rem_len);
                        if(first_trans && |rem_len) begin
                            bth_hdr[7:0] <= 8'h06;  //WRITE_FIRST
                            push_to_os_buf <= 1'b1;
                        end else if (first_trans && ~|rem_len) begin
                            bth_hdr[7:0] <= 8'h0A;  //WRITE_ONLY
                            push_to_os_buf <= 1'b1;
                        end else if (~first_trans && |rem_len) begin
                            bth_hdr[7:0] <= 8'h07;  //WRITE_MIDDLE
                            push_to_os_buf <= 1'b0;
                        end else if (~first_trans && ~|rem_len) begin
                            bth_hdr[7:0] <= 8'h08;  //WRITE_LAST
                            push_to_os_buf <= 1'b0;
                        end
                    end else begin
                        bth_hdr[7:0] <= 8'h04;
                        bth_hdr[71] <= 1'b0;
                        push_to_os_buf <= 1'b0;
                    end
                    o_reg_sq_psn <= o_reg_sq_psn + (aeth_pkt ? 1'b0 : 1'b1);
                    o_out_ack_pkt_cnt <= o_out_ack_pkt_cnt + (aeth_pkt ? 1'b1 : 1'b0);
                    o_out_mad_pkt_cnt <= o_out_mad_pkt_cnt + (q_id == 16'h0001 ? 1'b1 : 1'b0);
                    local_offset <= local_offset + payload_len;
                    remote_offset <= remote_offset + payload_len;
                    reth_hdr <= {dma_len[7:0],dma_len[15:8],dma_len[23:16],dma_len[31:24],r_key[7:0],r_key[15:8],r_key[23:16],r_key[31:24],remote_offset[7:0],remote_offset[15:8],remote_offset[23:16],remote_offset[31:24],remote_offset[39:32],remote_offset[47:40],remote_offset[55:48],remote_offset[63:56]};
                    o_hdr_data[1023:944] <= {payload_len,local_offset[47:0],completion_data_present,q_id[14:0]};
                    o_hdr_gen_rdy <= aeth_pkt;
                    if(aeth_pkt || (~(i_wqe_halt && (i_wqe_halted_qpid == o_qp_id))/* && ~(i_osq_nacked[o_qp_id])*/)) begin
                        hdr_gen_cs <= HDR_STO;
                        //if(wqe_opcode == 8'h00 && first_trans && ~aeth_pkt) begin
                        //    get_data_buf <= ~retried;
                        //    get_data_buf <= 1'b0;
                        //end
                    end else begin
                        //o_osq_nacked_resp <= i_osq_nacked;
                        hdr_gen_cs <= IDLE;
                        ipv4_identification <= ipv4_identification - 1'b1;
                    end
                end
            end
            HDR_STO: begin
                //get_data_buf <= 1'b0;
                o_data_buf_fifo_data <= {data_buf_addr[31:1],(retried || (q_id == 16'h0001))};
                o_hdr_gen_rdy <= 1'b0;
                if(~wqe_push_pending) begin
                    o_hdr_data[111:0] <= eth_hdr;
                    if(ip_ver) begin
                        o_hdr_data[431:112] <= ip_hdr;
                        o_hdr_data[495:432] <= udp_hdr;
                        o_hdr_data[591:496] <= bth_hdr;
                        if(reth_present) begin
                            o_hdr_data[719:592] <= reth_hdr;
                            o_hdr_len <= 8'h5A;  //90B header
                        end else if(aeth_pkt) begin
                            o_hdr_data[623:592] <= {aeth_hdr[7:0],aeth_hdr[15:8],aeth_hdr[23:16],aeth_hdr[31:24]};
                            o_hdr_len <= 8'h4E;  //78B header
                        end else if(completion_data_present) begin
                            o_hdr_data[719:592] <= nvme_comp_data;
                            o_hdr_len <= 8'h5A;  //90B header
                        end else begin
                            o_hdr_data[719:592] <= 128'd0000;
                            o_hdr_len <= 8'h4A; //74B header
                        end
                    end else begin
                        o_hdr_data[271:112] <= ip_hdr[159:0];
                        o_hdr_data[335:272] <= udp_hdr;
                        o_hdr_data[431:336] <= bth_hdr;
                        if(reth_present) begin
                            o_hdr_data[559:432] <= reth_hdr;
                            o_hdr_len <= 8'h46;  //70B header
                        end else if(aeth_pkt) begin
                            o_hdr_data[463:432] <= {aeth_hdr[7:0],aeth_hdr[15:8],aeth_hdr[23:16],aeth_hdr[31:24]};
                            o_hdr_len <= 8'h3A;  //58B header
                        end else if(completion_data_present) begin
                            o_hdr_data[559:432] <= nvme_comp_data;
                            o_hdr_len <= 8'h46;  //70B header
                        end else begin
                            o_hdr_data[559:432] <= 128'd0000;
                            o_hdr_len <= 8'h36; //54B header
                        end
                    end
                    if(wqe_opcode == 8'h00 && first_trans && ~aeth_pkt) begin
                        o_data_buf_fifo_wr_en <= 1'b1;
                        get_data_buf <= ~retried;
                    end else begin
                        o_data_buf_fifo_wr_en <= 1'b0;
                        get_data_buf <= 1'b0;
                    end
                    push_to_os_buf <= 1'b0;
                    first_trans <= 1'b0;
                    o_reg_wr_en <= ~aeth_pkt;
                    if(wqe_opcode == 8'h00 && |rem_len) begin
                        hdr_gen_cs <= WAIT0;
                    end else if(wqe_opcode == 8'h02 && |rem_len) begin
                        hdr_gen_cs <= WAIT0;
                    end else begin
                        hdr_gen_cs <= IDLE;
                        o_reg_rd_en <= 1'b0;
                    end
                    aeth_pkt <= 1'b0;
                    reth_present <= 1'b0;
                end
            end
            ILL_OPCODE: begin
                o_hdr_gen_rdy <= 1'b0;
                if(~wqe_push_pending) begin
                    o_hdr_data[511:0] <= {128'd0,nvme_comp_data,16'h0000,q_id,r_key,remote_offset,wqe_opcode,dma_len,local_offset,o_wqe_wrid};
                    o_hdr_len <= 8'h00;
                    hdr_gen_cs <= IDLE;
                    o_reg_rd_en <= 1'b0;
                    o_reg_wr_en <= ~aeth_pkt;
                    aeth_pkt <= 1'b0;
                    wqe_opcode_err <= 1'b1;
                end
            end
            default: begin
            end
        endcase
    end
end

always @(posedge core_clk)
begin
    if(core_rst) begin
        o_wqp_req <= 1'b0;
        o_wqe_qpid <= {C_MAX_QID_WIDTH{1'b0}};
        wqe_push_pending <= 1'b0;
        o_wqe_opcode <= 8'h00;
        o_wqe_send_psn <= 24'd0;
        o_wqe_send_msn <= 24'd0;
        o_wqe_explicit_ack_req <= 1'b0;
        o_wqe_retried <= 1'b0;
        o_last_out_pkt_info <= 32'd0;
        o_wqe_data_bufid <= 15'h0000;
        o_wqe_qp_to <= 5'h00;
    end else begin
        if(hdr_gen_cs == RD_Q_INFO) begin
            if (retried)
                o_wqe_data_bufid <= retried_buf_id;
            else
                o_wqe_data_bufid <= {{(14-DATA_BUF_ID_WIDTH){1'b0}}, data_bufid};
        end

        if(push_to_os_buf && ~wqe_push_pending &&  ~(i_wqe_halt && (i_wqe_halted_qpid == o_qp_id))) begin
            o_wqp_req <= ~aeth_pkt && push_to_os_buf;
            wqe_push_pending <= 1'b1;
            o_wqe_qpid <= o_qp_id;
            o_wqe_qp_to <= reg_qp_to;
            o_wqe_retried <= retried;
            o_wqe_opcode <= wqe_opcode;   //bth_hdr[7:0];
            o_wqe_explicit_ack_req <= bth_hdr[71];
            //Work request is getting pushed to outstanding buffer while sending the first transaction
            //WRITE_ONLY, WRITE_FIRST, SEND_ONLY, or SEND_FIRST
            //hence need to calculate the last PSN used for this work request depending on PMTU value
            if (wqe_opcode == 8'h00) begin
                case(max_pmtu[12:8])
                    5'h01: begin
                        o_wqe_send_psn <= o_reg_sq_psn + dma_len[31:8] + |(dma_len[7:0]) - 'h2;
                    end
                    5'h02: begin
                        o_wqe_send_psn <= o_reg_sq_psn + dma_len[31:9] + |(dma_len[8:0]) - 'h2;
                    end
                    5'h04: begin
                        o_wqe_send_psn <= o_reg_sq_psn + dma_len[31:10] + |(dma_len[9:0]) - 'h2;
                    end
                    5'h08: begin
                        o_wqe_send_psn <= o_reg_sq_psn + dma_len[31:11] + |(dma_len[10:0]) - 'h2;
                    end
                    5'h10: begin
                        o_wqe_send_psn <= o_reg_sq_psn + dma_len[31:12] + |(dma_len[11:0]) - 'h2;
                    end
                    default: begin
                        o_wqe_send_psn <= o_reg_sq_psn + dma_len[31:8] + |(dma_len[8:0]) - 'h2;
                    end
                endcase
            end else begin
                o_wqe_send_psn <= o_reg_sq_psn - 1'b1;
            end
            o_wqe_send_msn <= o_reg_sq_msn;
            o_last_out_pkt_info <= ~aeth_pkt ? {(o_reg_sq_psn[15:0] - 1'b1),o_qp_id,wqe_opcode} : o_last_out_pkt_info;
        end else if(i_wqp_resp) begin
            wqe_push_pending <= 1'b0;
            o_wqp_req <= 1'b0;
        end

    end
end

generate
    if (C_EN_WR_RETRY_DATA_BUF)
	begin
	rdma_blk_allocator
	#(
	    .C_NUM_BLK({1'b1, {DATA_BUF_ID_WIDTH{1'b0}}}),                  // Number of blocks to be allocated
	    .C_BLK_PTR_WIDTH(DATA_BUF_ID_WIDTH),                            // Width for block number
	    .C_BRAM_N_FLOP(1)
	) inst_data_buf_blk_alloc
	(
	    .core_clk                           (core_clk),
	    .core_rst                           (core_rst),                 // Active high core reset

	    // Configuration
	    .i_num_blocks_enabled               (i_reg_wrdata_num_bufs[DATA_BUF_ID_WIDTH:0]),    // Have the maxs blocks as specified by ptr width
	    .i_blk_size                         (i_reg_wrdata_buf_sz),      // Block size in bytes // max size 64KB
	    .i_blk_base_addr                    (i_reg_wrdata_buf_ba),                         // Since internal BRAM block, so keeping BA to 0
	    .o_fifo_busy                        (),                         // Busy with initialization

	    // Free block interface
	    .i_push_free_block                  (i_freeup_data_buf),        // whenever the DCMD tbl entry is read by SSD CQ mgr, it is freed up
	    .i_push_free_block_num              (i_freeup_data_bufid[DATA_BUF_ID_WIDTH -1:0]),   // Data to be pushed
	    .i_pop_free_block                   (get_data_buf),             // Pop enable for a queue
	    .o_free_block_num                   (data_bufid),               // Popped Data
	    .o_free_block_addr                  (data_buf_addr),            // Address of the free block - unconnected
	    .o_no_free_blocks_left              (no_data_buf_left),         // No more free blocks left to be allocted
	    .o_num_valid_entries                ()                          // Number of valid blocks left - unconnected
	);
	end
     else
	begin
	assign no_data_buf_left=1'b0;
	assign data_buf_addr=32'b0;
	assign data_bufid={DATA_BUF_ID_WIDTH{1'b0}};
	end
endgenerate
assign o_dma_in_idle = ~wait_for_dma_idle;
endmodule

