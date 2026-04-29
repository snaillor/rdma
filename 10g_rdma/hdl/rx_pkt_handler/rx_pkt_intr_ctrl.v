// rx_pkt_intr_ctrl.v
// 描述            : RX 包中断控制模块，聚合各类中断事件并生成中断输出
//                   支持包校验错误、MAD 包接收、Bypass 包、RNR NAK 等中断源
`timescale 1ps/1ps
module rx_pkt_intr_ctrl #(
  parameter C_NUM_QP        = 256,
  parameter C_QP_INDX_WIDTH =   8
) (
  // System level inputs & outputs
  input  wire                       clk,
  input  wire                       rst_n,

  input  wire                       rdma_enabled,

  input  wire                       pkt_valdn_err_intr_en,
  output wire                       pkt_valdn_err_intr,
  output reg                        pkt_valdn_err_intr_sts,
  input  wire                       clr_pkt_valdn_err_intr,

  input  wire                       mad_pkt_rcvd_intr_en,
  output wire                       mad_pkt_rcvd_intr,
  output reg                        mad_pkt_rcvd_intr_sts,
  input  wire                       clr_mad_pkt_rcvd_intr,

  input  wire                       bypass_pkt_rcvd_intr_en,
  output wire                       bypass_pkt_rcvd_intr,
  output reg                        bypass_pkt_rcvd_intr_sts,
  input  wire                       clr_bypass_pkt_rcvd_intr,

  input  wire                       rnr_nack_gen_intr_en,  // connect to o_intr_en_rnr_nak_gen
  output wire                       rnr_nack_gen_intr,     //
  output reg                        rnr_nack_gen_intr_sts, // connect to i_rnr_nack_gen_intr
  input  wire                       clr_rnr_nack_gen_intr, // connect to o_intr_clr_rnr_nak_gen

  input  wire                       fatal_err_intr_en,     // connect to qp_mgr_o_intr_en_fatal_err
  output wire                       fatal_err_intr,        // connect to rx_pkt_hndler_o_fatal_err_intr
  (* mark_debug = "true" *) output reg                        fatal_err_intr_sts,    //
  input  wire                       clr_fatal_err_intr,    // connect to qp_mgr_o_qp_clr_fatal_err

  input  wire                       qp_pkt_rcvd_intr_en,
  output wire                       qp_pkt_rcvd_intr,
  output reg  [C_NUM_QP-1:0]        qp_pkt_rcvd_intr_sts,
  input  wire [C_NUM_QP-1:0]        clr_qp_pkt_rcvd_intr,

  input  wire                       set_pkt_valdn_err_intr,
  input  wire                       set_mad_pkt_rcvd_intr,
  input  wire                       set_bypass_pkt_rcvd_intr,
  input  wire                       set_rnr_nack_gen_intr,
  input  wire                       set_fatal_err_intr,

  input  wire [C_QP_INDX_WIDTH-1:0] pkt_rcvd_qpid_1,
  input  wire                       set_qp_pkt_rcvd_intr_1,

  input  wire [C_QP_INDX_WIDTH-1:0] pkt_rcvd_qpid_2,
  input  wire                       set_qp_pkt_rcvd_intr_2
);

  wire                pkt_valdn_err_intr_sts_en;
  wire                mad_pkt_rcvd_intr_sts_en;
  wire                bypass_pkt_rcvd_intr_sts_en;
  wire [C_NUM_QP-1:0] set_qp_pkt_rcvd_intr_i;
  wire [C_NUM_QP-1:0] qp_pkt_rcvd_intr_sts_en;
  wire                rnr_nack_gen_intr_sts_en;
  wire                fatal_err_intr_sts_en;

  genvar i;

  assign pkt_valdn_err_intr_sts_en   = set_pkt_valdn_err_intr   | clr_pkt_valdn_err_intr;
  assign mad_pkt_rcvd_intr_sts_en    = set_mad_pkt_rcvd_intr    | clr_mad_pkt_rcvd_intr;
  assign bypass_pkt_rcvd_intr_sts_en = set_bypass_pkt_rcvd_intr | clr_bypass_pkt_rcvd_intr;
  assign rnr_nack_gen_intr_sts_en    = set_rnr_nack_gen_intr    | clr_rnr_nack_gen_intr;
  assign fatal_err_intr_sts_en       = set_fatal_err_intr       | clr_fatal_err_intr;

  generate for (i=0; i<C_NUM_QP;  i=i+1)
  begin : gen_qp_pkt_rcvd_intr_sts
    assign set_qp_pkt_rcvd_intr_i[i]  = ((i == pkt_rcvd_qpid_1) ? set_qp_pkt_rcvd_intr_1 : 1'b0) ||
                                        ((i == pkt_rcvd_qpid_2) ? set_qp_pkt_rcvd_intr_2 : 1'b0);
    assign qp_pkt_rcvd_intr_sts_en[i] = set_qp_pkt_rcvd_intr_i[i] | clr_qp_pkt_rcvd_intr[i];

    always @(posedge clk)
      if (!rst_n || rdma_enabled)
        qp_pkt_rcvd_intr_sts[i] <= 1'b0;
      else if (qp_pkt_rcvd_intr_sts_en[i])
        qp_pkt_rcvd_intr_sts[i] <= set_qp_pkt_rcvd_intr_i[i];
  end
  endgenerate

  always @(posedge clk)
    if (!rst_n || rdma_enabled)
    begin
      pkt_valdn_err_intr_sts   <= 1'b0;
      mad_pkt_rcvd_intr_sts    <= 1'b0;
      bypass_pkt_rcvd_intr_sts <= 1'b0;
      //in_errsts_intr_sts       <= 1'b0;
      rnr_nack_gen_intr_sts    <= 1'b0;
      fatal_err_intr_sts       <= 1'b0;
    end
    else
    begin
      if(pkt_valdn_err_intr_sts_en)
       pkt_valdn_err_intr_sts <= set_pkt_valdn_err_intr;

      if(mad_pkt_rcvd_intr_sts_en)
       mad_pkt_rcvd_intr_sts  <= set_mad_pkt_rcvd_intr;

      if(bypass_pkt_rcvd_intr_sts_en)
        bypass_pkt_rcvd_intr_sts <= set_bypass_pkt_rcvd_intr;

      //if(in_errsts_intr_sts_en)
      // in_errsts_intr_sts  <= set_in_errsts_intr;

      if (rnr_nack_gen_intr_sts_en)
        rnr_nack_gen_intr_sts <= set_rnr_nack_gen_intr;

      if (fatal_err_intr_sts_en)
        fatal_err_intr_sts <= set_fatal_err_intr;
    end

  assign pkt_valdn_err_intr   = pkt_valdn_err_intr_en   & pkt_valdn_err_intr_sts;
  assign mad_pkt_rcvd_intr    = mad_pkt_rcvd_intr_en    & mad_pkt_rcvd_intr_sts;
  assign bypass_pkt_rcvd_intr = bypass_pkt_rcvd_intr_en & bypass_pkt_rcvd_intr_sts;
  assign qp_pkt_rcvd_intr     = qp_pkt_rcvd_intr_en     & |(qp_pkt_rcvd_intr_sts);
  assign rnr_nack_gen_intr    = rnr_nack_gen_intr_en    & rnr_nack_gen_intr_sts;
  assign fatal_err_intr       = fatal_err_intr_en       & fatal_err_intr_sts;

endmodule

