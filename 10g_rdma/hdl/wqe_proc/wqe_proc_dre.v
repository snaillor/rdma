// wqe_proc_dre.v
// 文件名          : wqe_proc_dre.v
// 版本            : v1.0
// 描述            : WQE 数据重对齐模块，消除包头与 Payload 之间的空闲周期
//                   实现包头与数据的无缝拼接，提高总线利用率
// Verilog 标准    : Verilog'2001

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
`timescale 1ps/1ps

(* DowngradeIPIdentifiedWarnings="yes" *)
module wqe_proc_dre
#(
    parameter C_AXIS_DATA_WIDTH = 512,
    parameter C_M_AXI_DATA_WIDTH = 512,
    parameter C_M_AXI_ADDR_WIDTH = 32,
    parameter C_M_AXI_ID_WIDTH = 1,
    parameter IP2BUS_LEN_WIDTH = 8,
    parameter C_MAX_WRDATA_BUF_NUM = 128,
    parameter C_EN_WR_RETRY_DATA_BUF = 1,
    parameter C_EN_DEBUG = 0,
    parameter C_FAMILY = "virtexu"
 ) (
    input                    core_clk,
    input                    core_rst,

    //AXI streaming interface signals
    output     [C_AXIS_DATA_WIDTH-1 : 0]        m_axis_tdata,
    output reg [C_AXIS_DATA_WIDTH/8-1:0]        m_axis_tkeep,
    output                                      m_axis_tvalid,
    input                                       m_axis_tready,
    output reg                                  m_axis_tlast,

    input      [C_AXIS_DATA_WIDTH-1 : 0]        s_axis_tdata,
    input      [C_AXIS_DATA_WIDTH/8-1:0]        s_axis_tkeep,
    input                                       s_axis_tvalid,
    input                                       s_axis_tlast,
    output                                      s_axis_tready,
    input                                       i_data_ptr_fifo_wr_en,
    input      [31:0]                           i_data_ptr_fifo_data,
    output                                      o_data_buf_fifo_empty,

    //Axi master interface
    output  reg    [C_M_AXI_ADDR_WIDTH -1 :0 ]  maxi_addr,
    output                                      maxi_wr_rdn,
    output  reg                                 maxi_en,
    output  reg    [IP2BUS_LEN_WIDTH-1:0]       maxi_len,
    input                                       maxi_wdata_rdy,
    output         [C_M_AXI_DATA_WIDTH-1:0]     maxi_wdata,
    input                                       maxi_done,
    input                                       maxi_busy,
    input                                       maxi_bvalid,
    input                                       maxi_error,

    input                                       i_debug_cnt_en,
    input                                       i_debug_cnt_clr,
    output reg  [15:0]                          o_wqe_proc_wr_retry_buf_full_cnt

);

    localparam DATA_PTR_FIFO_DEPTH = C_MAX_WRDATA_BUF_NUM;
    localparam [15:0] ETH_TYPE_IPv4 = 16'h0008;
    localparam [15:0] ETH_TYPE_IPv6 = 16'hdd86;
    localparam RDMA_WRITE_FIRST = 8'b00000110;
    localparam RDMA_WRITE_MIDDLE = 8'b00000111;
    localparam RDMA_WRITE_LAST = 8'b00001000;
    localparam RDMA_WRITE_ONLY = 8'b00001010;
    localparam IDLE = 2'b00;
    localparam START_WR = 2'b01;
    localparam WAIT_ON_AXI_DONE = 2'b10;

    wire         s_axis_stall;
    reg  [511:0] data_buf_din;
    reg          rdma_write;
    reg          data_buf_wr_en;
    reg          data_buf_rd_en;
    wire [511:0] data_buf_dout;
    reg  [15:0]  pkt_len;
    reg  [1:0]   ddr_wr_cs;
    reg          data_ptr_fifo_rd_en;
    wire [C_M_AXI_ADDR_WIDTH - 1 : 0] data_ptr_fifo_rd_data;
    reg  [C_M_AXI_ADDR_WIDTH - 1 : 0] curr_wr_ddr_addr;
    reg          retried_pkt;
    reg  [7:0]   pkt_wr_cnt;
    reg  [7:0]   pkt_rd_cnt;
    reg  [7:0]   pkt_bvalid_cnt;

    reg                             pkt_start;
    reg  [C_AXIS_DATA_WIDTH-1 : 0]  data_d1;
    reg  [C_AXIS_DATA_WIDTH-1 : 0]  data_d2;
    reg [C_AXIS_DATA_WIDTH/8-1:0]   tkeep_d1;
    reg [C_AXIS_DATA_WIDTH/8-1:0]   tkeep_d2;
    reg                             fifo_wr_en;
    reg  [6:0]                      byte_cnt;
    reg                             extra_cycle;
    reg                             extra_cycle_1;
    reg  [63:0]                     last_tkeep;
    wire                            data_buf_fifo_empty;
    wire                            data_ptr_fifo_empty;
    wire                            data_ptr_fifo_full;

    assign fifo_full = s_axis_stall || (fifo_wr_en && ~m_axis_tready);
    assign m_axis_tdata = data_d2;
    assign m_axis_tvalid = fifo_wr_en;
    assign s_axis_tready = (~extra_cycle && ~extra_cycle_1 && ~(s_axis_stall || (fifo_wr_en && ~m_axis_tready)));

//////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////// Debug counters logic //////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////
    generate if(C_EN_DEBUG == 1) begin:DEBUG_EN
        always @(posedge core_clk)
        begin
            if(core_rst) begin
                o_wqe_proc_wr_retry_buf_full_cnt <= 16'h0000;
            end else begin
                if(i_debug_cnt_clr) begin
                    o_wqe_proc_wr_retry_buf_full_cnt <= 16'h0000;
                end else if (i_debug_cnt_en && s_axis_stall) begin
                    o_wqe_proc_wr_retry_buf_full_cnt <= o_wqe_proc_wr_retry_buf_full_cnt + 1'b1;
                end
            end
        end
    end else begin
        always@(*) begin
            o_wqe_proc_wr_retry_buf_full_cnt <= 16'h0000;
        end
    end
    endgenerate

    always@(posedge core_clk)
    begin
        if(core_rst) begin
            data_d1 <= 'd0;
            data_d2 <= 'd0;
            tkeep_d1 <= 'd0;
            tkeep_d2 <= 'd0;
            pkt_start <= 1'b0;
            m_axis_tkeep <= 'd0;
            fifo_wr_en <= 1'b0;
            m_axis_tlast <= 1'b0;
            extra_cycle <= 1'b0;
            extra_cycle_1 <= 1'b0;
            last_tkeep <= 64'd00;
            byte_cnt <= 7'h00;
        end else begin
            if(~pkt_start && s_axis_tvalid && ~fifo_full && ~extra_cycle_1) begin
                if(s_axis_tlast)  begin
                    data_d2 <= {s_axis_tdata};
                    fifo_wr_en <= 1'b1;
                    m_axis_tkeep <= s_axis_tkeep;
                    m_axis_tlast <= 1'b1;
                end else begin
                    m_axis_tlast <= 1'b0;
                    pkt_start <= 1'b1;
                    if(s_axis_tkeep[63]) begin
                       fifo_wr_en <= 1'b1;
                       byte_cnt <= 'd0;
                       data_d2 <= {s_axis_tdata};
                       m_axis_tkeep <= s_axis_tkeep;
                   end else if(~s_axis_tkeep[54]) begin
                       fifo_wr_en <= 1'b0;
                       byte_cnt <= 'd54;
                       last_tkeep <= s_axis_tkeep;
                       data_d1 <= {s_axis_tdata};
                       tkeep_d1 <= {s_axis_tkeep};
                   end else begin
                       fifo_wr_en <= 1'b0;
                   end
               end
           end else if(((pkt_start && s_axis_tvalid) || extra_cycle || extra_cycle_1) && ~fifo_full) begin
                if(s_axis_tlast || extra_cycle || extra_cycle_1) begin
                    if(byte_cnt != 'd0 && ~extra_cycle && ~extra_cycle_1) begin
                        case (byte_cnt)
                           'd6: begin
                               extra_cycle <= s_axis_tkeep[58];
                               extra_cycle_1 <= ~m_axis_tready && ~s_axis_tkeep[58];
                               m_axis_tlast <= ~s_axis_tkeep[58];
                               pkt_start <= (~m_axis_tready && ~s_axis_tkeep[58]) || s_axis_tkeep[58];
                            end
                            'd10: begin
                               extra_cycle <= s_axis_tkeep[54];
                               extra_cycle_1 <= ~m_axis_tready && ~s_axis_tkeep[54];
                               m_axis_tlast <= ~s_axis_tkeep[54];
                               pkt_start <= (~m_axis_tready && ~s_axis_tkeep[54]) || s_axis_tkeep[54];
                            end
                            'd14: begin
                               extra_cycle <= s_axis_tkeep[50];
                               extra_cycle_1 <= ~m_axis_tready && ~s_axis_tkeep[50];
                               m_axis_tlast <= ~s_axis_tkeep[50];
                               pkt_start <= (~m_axis_tready && ~s_axis_tkeep[50]) || s_axis_tkeep[50];
                            end
                            'd26: begin
                               extra_cycle <= s_axis_tkeep[38];
                               extra_cycle_1 <= ~m_axis_tready && ~s_axis_tkeep[38];
                               m_axis_tlast <= ~s_axis_tkeep[38];
                               pkt_start <= (~m_axis_tready && ~s_axis_tkeep[38]) || s_axis_tkeep[38];
                            end
                            'd54: begin
                               extra_cycle <= s_axis_tkeep[10];
                               extra_cycle_1 <= ~m_axis_tready && ~s_axis_tkeep[10];
                               m_axis_tlast <= ~s_axis_tkeep[10];
                               pkt_start <= (~m_axis_tready && ~s_axis_tkeep[10]) || s_axis_tkeep[10];
                            end
                            default: begin
                               extra_cycle <= 1'b0;
                               m_axis_tlast <= 1'b0;
                               pkt_start <= 1'b0;
                            end
                        endcase
                    end else begin
                        pkt_start <= ~m_axis_tready && ~extra_cycle_1;  //1'b0;
                        extra_cycle <= extra_cycle ? ~m_axis_tready : 1'b0;   //~m_axis_tready && ~extra_cycle_1;  // 1'b0;
                        m_axis_tlast <= ~extra_cycle_1;
                        extra_cycle_1 <= ~m_axis_tready && ~m_axis_tvalid && s_axis_tready && s_axis_tvalid && s_axis_tlast; //1'b0;
                    end
                end
                case (byte_cnt)
                   'd0: begin
                        data_d1 <= {s_axis_tdata};
                        if(~s_axis_tkeep[6] && ~s_axis_tlast) begin
                            byte_cnt <= 'd6;
                            fifo_wr_en <= 1'b0;
                            last_tkeep <= s_axis_tkeep;
                        end else if (~s_axis_tkeep[10] && ~s_axis_tlast) begin
                            byte_cnt <= 'd10;
                            fifo_wr_en <= 1'b0;
                            last_tkeep <= s_axis_tkeep;
                        end else if (~s_axis_tkeep[14] && ~s_axis_tlast) begin
                            byte_cnt <= 'd14;
                            fifo_wr_en <= 1'b0;
                            last_tkeep <= s_axis_tkeep;
                        end else if(~s_axis_tkeep[26] && ~s_axis_tlast) begin
                            byte_cnt <= 'd26;
                            fifo_wr_en <= 1'b0;
                            last_tkeep <= s_axis_tkeep;
                        end else begin
                            //fifo_wr_en <= 1'b1;
                            //fifo_wr_en <= ~extra_cycle_1;
                            fifo_wr_en <= ~(m_axis_tvalid && m_axis_tready && m_axis_tlast);
                            data_d2 <= {s_axis_tdata};
                            m_axis_tkeep <= s_axis_tkeep;
                        end
                    end
                   'd6: begin
                       data_d2[511:48] <= s_axis_tdata[463:0];
                       data_d2[47:0] <= data_d1[47:0];
                       data_d1[47:0] <= s_axis_tdata[511:464];
                       //fifo_wr_en <= 1'b1;
                       fifo_wr_en <=  ~(m_axis_tvalid && m_axis_tlast);  //~extra_cycle_1;
                       m_axis_tkeep <= extra_cycle ? last_tkeep : {s_axis_tkeep[57:0],last_tkeep[5:0]};
                       last_tkeep[5:0] <= s_axis_tkeep[63:58];
                    end
                    'd10: begin
                       data_d2[511:80] <= s_axis_tdata[431:0];
                       data_d2[79:0] <= data_d1[79:0];
                       data_d1[79:0] <= s_axis_tdata[511:432];
                       //fifo_wr_en <= 1'b1;
                       fifo_wr_en <=  ~(m_axis_tvalid && m_axis_tlast);  //~extra_cycle_1;
                       m_axis_tkeep <= extra_cycle ? last_tkeep : {s_axis_tkeep[53:0],last_tkeep[9:0]};
                       last_tkeep[9:0] <= s_axis_tkeep[63:54];
                    end
                    'd14: begin
                       data_d2[511:112] <= s_axis_tdata[399:0];
                       data_d2[111:0] <= data_d1[111:0];
                       data_d1[111:0] <= s_axis_tdata[511:400];
                       //fifo_wr_en <= 1'b1;
                       fifo_wr_en <=  ~(m_axis_tvalid && m_axis_tlast);  //~extra_cycle_1;
                       m_axis_tkeep <= extra_cycle ? last_tkeep : {s_axis_tkeep[49:0],last_tkeep[13:0]};
                       last_tkeep[13:0] <= s_axis_tkeep[63:50];
                    end
                    'd26: begin
                       data_d2[511:208] <= s_axis_tdata[303:0];
                       data_d2[207:0] <= data_d1[207:0];
                       data_d1[207:0] <= s_axis_tdata[511:304];
                       //fifo_wr_en <= 1'b1;
                       fifo_wr_en <= ~(m_axis_tvalid && m_axis_tlast);  // ~extra_cycle_1;
                       m_axis_tkeep <= extra_cycle ? last_tkeep : {s_axis_tkeep[37:0],last_tkeep[25:0]};
                       last_tkeep[25:0] <= s_axis_tkeep[63:38];
                    end
                    'd54: begin
                       data_d2[511:432] <= s_axis_tdata[79:0];
                       data_d2[431:0] <= data_d1[431:0];
                       data_d1[431:0] <= s_axis_tdata[511:80];
                       //fifo_wr_en <= 1'b1;
                       fifo_wr_en <= ~(m_axis_tvalid && m_axis_tlast); //~extra_cycle_1 && m_axis_tlast;
                       m_axis_tkeep <= extra_cycle ? last_tkeep : {s_axis_tkeep[9:0],last_tkeep[53:0]};
                       last_tkeep[53:0] <= s_axis_tkeep[63:10];
                    end
                    default: begin
                        fifo_wr_en <= 1'b0;
                    end
                endcase
            end else begin
                if(m_axis_tready) begin
                    fifo_wr_en <= 1'b0;
                    m_axis_tlast <= 1'b0;
                    pkt_start <= (m_axis_tvalid && m_axis_tlast) ? 1'b0 : pkt_start;
                    extra_cycle_1 <= 1'b0;
                end else if(~extra_cycle_1) begin
                    extra_cycle_1 <= (m_axis_tvalid && m_axis_tlast) ? 1'b1 : extra_cycle_1;
                end
            end
        end
    end

////////////////////////////////////////////////////////////////////////////////////////
////////////////// Logic to write the data to BRAM /////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////
generate if(C_EN_WR_RETRY_DATA_BUF == 1) begin: WR_DATA_BUF
    assign maxi_wdata = data_buf_dout;
    assign maxi_wr_rdn = 1'b1;

always @(posedge core_clk)
begin
    if(core_rst) begin
        data_buf_din <= 'd0;
        rdma_write <= 1'b0;
        data_buf_wr_en <= 1'b0;
        data_ptr_fifo_rd_en <= 1'b0;
        curr_wr_ddr_addr <= 'd0;
        pkt_len <= 16'h0000;
        retried_pkt <= 1'b0;
        pkt_wr_cnt <= 8'h00;
    end else begin
        if(~pkt_start && s_axis_tvalid && ~fifo_full && ~extra_cycle_1) begin
            if((s_axis_tdata[111:96] == ETH_TYPE_IPv4) && ((s_axis_tdata[343:336] ==RDMA_WRITE_FIRST) ||
                (s_axis_tdata[343:336] ==RDMA_WRITE_ONLY))) begin
                rdma_write <= ~data_ptr_fifo_rd_data[0];
                pkt_len <= {s_axis_tdata[311:304],s_axis_tdata[319:312]} - 16'h28;
                retried_pkt <= data_ptr_fifo_rd_data[0];
                curr_wr_ddr_addr <= {data_ptr_fifo_rd_data[C_M_AXI_ADDR_WIDTH - 1 : 1], 1'b0};
                data_ptr_fifo_rd_en <= 1'b1;
                data_buf_din <= {{432{1'b0}},data_ptr_fifo_rd_data,({s_axis_tdata[311:304],s_axis_tdata[319:312]} - 16'h28)};
                data_buf_wr_en <= ~data_ptr_fifo_rd_data[0];
            end else if((s_axis_tdata[111:96] == ETH_TYPE_IPv4) && ((s_axis_tdata[343:336] ==RDMA_WRITE_MIDDLE) ||
                        (s_axis_tdata[343:336] ==RDMA_WRITE_LAST))) begin
                rdma_write <= ~retried_pkt;
                pkt_len <= {s_axis_tdata[311:304],s_axis_tdata[319:312]} - 16'h18;
                data_ptr_fifo_rd_en <= 1'b0;
                curr_wr_ddr_addr <= curr_wr_ddr_addr + pkt_len;
                data_buf_din <= {{496{1'b0}},(curr_wr_ddr_addr+pkt_len),({s_axis_tdata[311:304],s_axis_tdata[319:312]} - 16'h18)};
                data_buf_wr_en <= ~retried_pkt;
            end else if((s_axis_tdata[111:96] == ETH_TYPE_IPv6) && ((s_axis_tdata[503:496] ==RDMA_WRITE_FIRST) ||
                (s_axis_tdata[503:496] ==RDMA_WRITE_ONLY))) begin
                rdma_write <= ~data_ptr_fifo_rd_data[0];
                retried_pkt <= data_ptr_fifo_rd_data[0];
                pkt_len <= {s_axis_tdata[471:464],s_axis_tdata[479:472]} - 16'h28;
                data_ptr_fifo_rd_en <= 1'b1;
                curr_wr_ddr_addr <= {data_ptr_fifo_rd_data[C_M_AXI_ADDR_WIDTH - 1 : 1], 1'b0};
                data_buf_din <= {{495{1'b0}},data_ptr_fifo_rd_data,({s_axis_tdata[471:464],s_axis_tdata[479:472]} - 16'h28)};
                data_buf_wr_en <= ~data_ptr_fifo_rd_data[0];
            end else if((s_axis_tdata[111:96] == ETH_TYPE_IPv6) && ((s_axis_tdata[503:496] ==RDMA_WRITE_MIDDLE) ||
                (s_axis_tdata[503:496] ==RDMA_WRITE_LAST))) begin
                rdma_write <= ~retried_pkt;
                pkt_len <= {s_axis_tdata[471:464],s_axis_tdata[479:472]} - 16'h18;
                data_ptr_fifo_rd_en <= 1'b0;
                curr_wr_ddr_addr <= curr_wr_ddr_addr + pkt_len;
                data_buf_din <= {{496{1'b0}},(curr_wr_ddr_addr+pkt_len),({s_axis_tdata[471:464],s_axis_tdata[479:472]} - 16'h18)};
                data_buf_wr_en <= ~retried_pkt;
            end else begin
                rdma_write <= 1'b0;
                data_ptr_fifo_rd_en <= 1'b0;
                data_buf_wr_en <= 1'b0;
            end
        end else if((pkt_start && s_axis_tvalid && s_axis_tready) && ~fifo_full) begin
            data_ptr_fifo_rd_en <= 1'b0;
            if((byte_cnt != 0) && rdma_write) begin
                data_buf_din <= s_axis_tdata;
                data_buf_wr_en <= 1'b1;
                rdma_write <= ~s_axis_tlast;
                pkt_wr_cnt <= pkt_wr_cnt + (s_axis_tlast ? 1'b1 : 1'b0);
            end else begin
                data_buf_wr_en <= 1'b0;
                rdma_write <= rdma_write ? ~s_axis_tlast : 1'b0;
            end
        end else begin
            data_buf_wr_en <= 1'b0;
            data_ptr_fifo_rd_en <= 1'b0;
        end
    end
end

always @(posedge core_clk)
begin
    if(core_rst) begin
        data_buf_rd_en <= 1'b0;
        ddr_wr_cs <= IDLE;
        pkt_rd_cnt <= 8'h00;
        maxi_en <= 1'b0;
        maxi_len <= 'd0;
        maxi_addr <= 'd0;
        pkt_bvalid_cnt <= 8'h00;
    end else begin
        if(maxi_bvalid) begin
           pkt_bvalid_cnt <= pkt_bvalid_cnt + 8'h01;
        end
        case (ddr_wr_cs)
            IDLE: begin
                if((pkt_wr_cnt != pkt_rd_cnt) && ~data_buf_fifo_empty) begin
                    ddr_wr_cs <= START_WR;
                    maxi_addr <= data_buf_dout[47:16];
                    maxi_len <= data_buf_dout[15:0];
                    data_buf_rd_en <= 1'b1;
                end
            end
            START_WR: begin
                data_buf_rd_en <= 1'b0;
                maxi_en <= 1'b1;
                ddr_wr_cs <= WAIT_ON_AXI_DONE;
            end
            WAIT_ON_AXI_DONE: begin
                maxi_en <= 1'b0;
                if(maxi_done) begin
                    ddr_wr_cs <= IDLE;
                    pkt_rd_cnt <= pkt_rd_cnt + 1'b1;
                end
            end
        endcase
    end
end

    assign o_data_buf_fifo_empty = data_buf_fifo_empty && (pkt_bvalid_cnt == pkt_wr_cnt) && data_ptr_fifo_empty && ~rdma_write; //(ddr_wr_cs == IDLE);

////////////////////////////////////////////////////////////////////////////////////////
////////////////// Write retry data buffer address fifo ////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////

           sync_fifo_fg
    #(
        .C_FAMILY(C_FAMILY), // new for FIFO Gen
        .C_DCOUNT_WIDTH(6),
        .C_ENABLE_RLOCS(0), // not supported in sync fifo
        .C_HAS_DCOUNT(0),
        .C_HAS_RD_ACK(0),
        .C_HAS_RD_ERR(0),
        .C_HAS_WR_ACK(0),
        .C_HAS_WR_ERR(0),
        .C_HAS_ALMOST_FULL(1),
        .C_MEMORY_TYPE(1),  // 0 = distributed RAM, 1 = BRAM
        .C_PORTS_DIFFER(0),
        .C_RD_ACK_LOW(0),
        .C_USE_EMBEDDED_REG(0),
        .C_READ_DATA_WIDTH(512),
        .C_READ_DEPTH(128),
        .C_RD_ERR_LOW(0),
        .C_WR_ACK_LOW(0),
        .C_WR_ERR_LOW(0),
        .C_PRELOAD_REGS(1),  // 1 = first word fall through
        .C_PRELOAD_LATENCY(0),  // 0 = first word fall through
        .C_WRITE_DATA_WIDTH(512),
        .C_WRITE_DEPTH(128),
        .C_SYNCHRONIZER_STAGE(3)    // Valid values are 0 to 8
    ) wr_retry_data_buf_fifo (
        .Clk          (core_clk),
        .Sinit        (core_rst),
        .Din          (data_buf_din),
        .Wr_en        (data_buf_wr_en),
        .Rd_en        (data_buf_rd_en || maxi_wdata_rdy),
        .Dout         (data_buf_dout),
        .Almost_full  (s_axis_stall),
        .Full         (),
        .Empty        (data_buf_fifo_empty),
        .Rd_ack       (),
        .Wr_ack       (),
        .Rd_err       (),
        .Wr_err       (),
        .Data_count   ()
    );

    sync_fifo_fg
    #(
        .C_FAMILY(C_FAMILY), // new for FIFO Gen
        .C_DCOUNT_WIDTH(6),
        .C_ENABLE_RLOCS(0), // not supported in sync fifo
        .C_HAS_DCOUNT(0),
        .C_HAS_RD_ACK(0),
        .C_HAS_RD_ERR(0),
        .C_HAS_WR_ACK(0),
        .C_HAS_WR_ERR(0),
        .C_HAS_ALMOST_FULL(0),
        .C_MEMORY_TYPE(1),  // 0 = distributed RAM, 1 = BRAM
        .C_PORTS_DIFFER(0),
        .C_RD_ACK_LOW(0),
        .C_USE_EMBEDDED_REG(0),
        .C_READ_DATA_WIDTH(C_M_AXI_ADDR_WIDTH),
        .C_READ_DEPTH(DATA_PTR_FIFO_DEPTH),
        .C_RD_ERR_LOW(0),
        .C_WR_ACK_LOW(0),
        .C_WR_ERR_LOW(0),
        .C_PRELOAD_REGS(1),  // 1 = first word fall through
        .C_PRELOAD_LATENCY(0),  // 0 = first word fall through
        .C_WRITE_DATA_WIDTH(C_M_AXI_ADDR_WIDTH),
        .C_WRITE_DEPTH(DATA_PTR_FIFO_DEPTH),
        .C_SYNCHRONIZER_STAGE(3)    // Valid values are 0 to 8
    ) wr_retry_data_ptr_fifo (
        .Clk          (core_clk),
        .Sinit        (core_rst),
        .Din          (i_data_ptr_fifo_data),
        .Wr_en        (i_data_ptr_fifo_wr_en),
        .Rd_en        (data_ptr_fifo_rd_en),
        .Dout         (data_ptr_fifo_rd_data),
        .Almost_full  (),
        .Full         (data_ptr_fifo_full),
        .Empty        (data_ptr_fifo_empty),
        .Rd_ack       (),
        .Wr_ack       (),
        .Rd_err       (),
        .Wr_err       (),
        .Data_count   ()
    );

end else begin: NO_WR_DATA_BUF
    assign o_data_buf_fifo_empty = 1'b1;
    assign s_axis_stall = 1'b0;
    always@(posedge core_clk) begin
        maxi_en <= 1'b0;
    end
end
endgenerate

endmodule

