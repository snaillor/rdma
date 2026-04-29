// reg_fifo_sync.v
// 文件名          : reg_fifo_sync.v
// 版本            : v1.0
// 描述            : 寄存器实现的同步 FIFO 模块，纯寄存器结构，适用于小深度场景
// Verilog 标准    : Verilog'2001

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
`timescale 1 ps / 1 ps

module reg_fifo_sync #(
  parameter [0:0] C_READ_MODE = 1'b0,
  parameter C_FIFO_DEPTH = 8,
  parameter C_FIFO_WRCNTR_WIDTH = 4,
  parameter C_FIFO_DATA_WIDTH = 32
) (
  input  wire                         clk,
  input  wire                         reset,
  input  wire                         wr_en,
  input  wire [C_FIFO_DATA_WIDTH-1:0] din,
  output wire                         full,
  output wire                         almost_full,
  input  wire                         rd_en,
  output wire [C_FIFO_DATA_WIDTH-1:0] dout,
  output wire                         empty
);
  reg [C_FIFO_WRCNTR_WIDTH-1:0] i;

  reg [C_FIFO_DATA_WIDTH-1:0] fifo_reg [C_FIFO_DEPTH-1:0];
  reg [C_FIFO_WRCNTR_WIDTH-1:0] wrptr;
  reg [C_FIFO_WRCNTR_WIDTH-1:0] rdptr;

  wire [C_FIFO_DATA_WIDTH-1:0] dout_i;
  reg [C_FIFO_DATA_WIDTH-1:0] dout_r;

  wire [C_FIFO_WRCNTR_WIDTH-1:0] nxt_wrptr;

  assign nxt_wrptr = wrptr + 'd1;

  always @(posedge clk)
    if (reset)
      wrptr <= {(C_FIFO_WRCNTR_WIDTH){1'b0}};
    else if (wr_en)
      wrptr <= nxt_wrptr;

  always @(posedge clk)
    if (reset)
      rdptr <= {(C_FIFO_WRCNTR_WIDTH){1'b0}};
    else if (rd_en)
      rdptr <= rdptr + 'd1;

  always @(posedge clk)
    for (i=0; i<C_FIFO_DEPTH; i=i+1)
    begin
      if (reset)
        fifo_reg[i] <= {(C_FIFO_DATA_WIDTH){1'b0}};
      else if ((i[C_FIFO_WRCNTR_WIDTH-2:0] == wrptr[C_FIFO_WRCNTR_WIDTH-2:0]) && wr_en)
        fifo_reg[i] <= din;
    end

  assign dout_i = fifo_reg[rdptr[C_FIFO_WRCNTR_WIDTH-2:0]];

  always @(posedge clk)
    if (reset)
      dout_r <= {(C_FIFO_DATA_WIDTH){1'b0}};
    else if (rd_en)
      dout_r <= dout_i;

  assign dout = C_READ_MODE ? dout_i : dout_r;

  assign full = ({~wrptr[C_FIFO_WRCNTR_WIDTH-1], wrptr[C_FIFO_WRCNTR_WIDTH-2:0]} == rdptr) ? 1'b1 : 1'b0;
  assign almost_full = ({~nxt_wrptr[C_FIFO_WRCNTR_WIDTH-1], nxt_wrptr[C_FIFO_WRCNTR_WIDTH-2:0]} == rdptr) ? 1'b1 : 1'b0;
  assign empty = (wrptr == rdptr) ? 1'b1 : 1'b0;

endmodule

