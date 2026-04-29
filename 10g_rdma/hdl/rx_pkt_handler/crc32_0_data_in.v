// crc32_0_data_in.v
// 文件名          : crc32_0_data_in.v
// 版本            : v1.0
// 描述            : CRC32 零数据输入模块，使用指定种子计算全零数据的 CRC
// Verilog 标准    : Verilog'2001

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
`timescale 1 ps / 1 ps

module crc32_0_data_in #(parameter NUM_ZEROS  = 0)
(
  input  wire [31:0] init_seed,
  output reg  [31:0] crc_out
);

  integer i;

  always @(*)
  begin
    crc_out = init_seed;
    for (i=0; i<NUM_ZEROS; i=i+1)
      crc_out = {crc_out[30:0], 1'b0} ^ ({32{crc_out[31]}} & 32'h04C1_1DB7);
  end

endmodule
