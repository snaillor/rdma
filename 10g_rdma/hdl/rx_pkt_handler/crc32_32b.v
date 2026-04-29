// crc32_32b.v
// 文件名          : crc32_32b.v
// 版本            : v1.0
// 描述            : 32bit 并行 CRC32 计算模块，初始种子为 0
// Verilog 标准    : Verilog'2001

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
`timescale 1 ps / 1 ps

module crc32_32b #(parameter NUM_ZEROS =0)
(
  input  wire        clk,
  input  wire [31:0] crc_data_in,
  output reg  [31:0] crc_out
);

  integer i;

  wire [NUM_ZEROS+31:0] crc_data_in_extnd = {{(NUM_ZEROS){1'b0}}, crc_data_in};

  reg [31:0] nxt_crc_out;

  always @(*)
  begin
    nxt_crc_out = 32'd0;
    for (i=0; i<(NUM_ZEROS+32); i=i+1)
      nxt_crc_out = {nxt_crc_out[30:0], 1'b0} ^ ({32{nxt_crc_out[31] ^ crc_data_in_extnd[i]}} & 32'h04C1_1DB7);
  end

  always @(posedge clk)
    crc_out <= nxt_crc_out;

endmodule

