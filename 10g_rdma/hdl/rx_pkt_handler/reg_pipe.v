// reg_pipe.v
// 文件名          : reg_pipe.v
// 版本            : v1.0
// 描述            : AXI4 接口寄存器流水线模块，插入一级寄存器改善时序
// Verilog 标准    : Verilog'2001

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
`timescale 1 ps / 1 ps

module reg_pipe #(
  parameter C_DATA_WIDTH = 32
) (
  input  wire clk,
  input  wire reset,
  input  wire [C_DATA_WIDTH-1:0] din,
  input  wire vld_in,
  output wire rdy_out,
  output reg  [C_DATA_WIDTH-1:0] dout,
  output reg  vld_out,
  input  wire rdy_in
);

  assign rdy_out = rdy_in | ~vld_out;

  always @(posedge clk)
    if (reset)
      vld_out <= 1'b0;
    else if (rdy_out)
      vld_out <= vld_in;

  always @(posedge clk)
    if (rdy_out)
      dout <= din;

endmodule

