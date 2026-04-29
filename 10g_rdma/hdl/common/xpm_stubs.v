// Xilinx XPM IP stubs for iverilog simulation only
// Port names match Xilinx XPM library (Vivado 202x)
// Width warnings are expected - real XPM used in Vivado synthesis

module xpm_fifo_sync #(
  parameter DOUT_RESET_VALUE = "0",
  parameter ECC_MODE = "no_ecc",
  parameter FIFO_MEMORY_TYPE = "auto",
  parameter FIFO_READ_LATENCY = 1,
  parameter FIFO_WRITE_DEPTH = 2048,
  parameter FULL_RESET_VALUE = 0,
  parameter PROG_EMPTY_THRESH = 10,
  parameter PROG_FULL_THRESH = 10,
  parameter RD_DATA_COUNT_WIDTH = 1,
  parameter READ_DATA_WIDTH = 32,
  parameter READ_MODE = "std",
  parameter SIM_ASSERT_CHK = 0,
  parameter USE_ADV_FEATURES = "0707",
  parameter WAKEUP_TIME = 0,
  parameter WRITE_DATA_WIDTH = 32,
  parameter WR_DATA_COUNT_WIDTH = 1
)(
  input wire sleep,
  input wire rst,
  input wire wr_clk,
  input wire wr_en,
  input wire [WRITE_DATA_WIDTH-1:0] din,
  input wire rd_en,
  output wire [READ_DATA_WIDTH-1:0] dout,
  output wire full,
  output wire prog_full,
  output wire wr_ack,
  output wire overflow,
  output wire almost_full,
  output wire wr_data_count,
  output wire empty,
  output wire prog_empty,
  output wire valid,
  output wire underflow,
  output wire almost_empty,
  output wire rd_data_count,
  output wire sbiterr,
  output wire dbiterr,
  input wire injectsbiterr,
  input wire injectdbiterr,
  output wire wr_rst_busy,
  output wire rd_rst_busy
);
  reg [READ_DATA_WIDTH-1:0] mem [0:FIFO_WRITE_DEPTH-1];
  reg [$clog2(FIFO_WRITE_DEPTH):0] wr_ptr = 0;
  reg [$clog2(FIFO_WRITE_DEPTH):0] rd_ptr = 0;

  assign wr_rst_busy = 1'b0;
  assign rd_rst_busy = 1'b0;
  assign full = 1'b0;
  assign prog_full = 1'b0;
  assign wr_ack = 1'b1;
  assign overflow = 1'b0;
  assign almost_full = 1'b0;
  assign wr_data_count = 1'b0;
  assign empty = (wr_ptr == rd_ptr);
  assign prog_empty = 1'b0;
  assign valid = (wr_ptr != rd_ptr);
  assign underflow = 1'b0;
  assign almost_empty = 1'b0;
  assign rd_data_count = 1'b0;
  assign sbiterr = 1'b0;
  assign dbiterr = 1'b0;

  assign dout = mem[rd_ptr[$clog2(FIFO_WRITE_DEPTH)-1:0]];

  always @(posedge wr_clk) begin
    if (rst) begin
      wr_ptr <= 0;
      rd_ptr <= 0;
    end else begin
      if (wr_en && !full) begin
        mem[wr_ptr[$clog2(FIFO_WRITE_DEPTH)-1:0]] <= din;
        wr_ptr <= wr_ptr + 1;
      end
      if (rd_en && !empty) begin
        rd_ptr <= rd_ptr + 1;
      end
    end
  end
endmodule

module xpm_memory_sdpram #(
  parameter ADDR_WIDTH_A = 6,
  parameter ADDR_WIDTH_B = 6,
  parameter AUTO_SLEEP_TIME = 0,
  parameter BYTE_WRITE_WIDTH_A = 32,
  parameter CASCADE_HEIGHT = 0,
  parameter CLOCKING_MODE = "common_clock",
  parameter ECC_MODE = "no_ecc",
  parameter MEMORY_INIT_FILE = "none",
  parameter MEMORY_INIT_PARAM = "0",
  parameter MEMORY_OPTIMIZATION = "true",
  parameter MEMORY_PRIMITIVE = "auto",
  parameter MEMORY_SIZE = 2048,
  parameter MESSAGE_CONTROL = 0,
  parameter READ_DATA_WIDTH_B = 32,
  parameter READ_LATENCY_B = 2,
  parameter READ_RESET_VALUE_B = "0",
  parameter RST_MODE_A = "SYNC",
  parameter RST_MODE_B = "SYNC",
  parameter SIM_ASSERT_CHK = 0,
  parameter USE_EMBEDDED_CONSTRAINT = 0,
  parameter USE_MEM_INIT = 1,
  parameter WAKEUP_TIME = "disable_sleep",
  parameter WRITE_DATA_WIDTH_A = 32,
  parameter WRITE_MODE_B = "no_change"
)(
  input wire clka,
  input wire rsta,
  input wire ena,
  input wire regcea,
  input wire [ADDR_WIDTH_A-1:0] addra,
  input wire [WRITE_DATA_WIDTH_A-1:0] dina,
  input wire wea,
  input wire injectsbiterra,
  input wire injectdbiterra,
  output wire sbiterra,
  output wire dbiterra,
  input wire sleep,
  input wire clkb,
  input wire rstb,
  input wire enb,
  input wire regceb,
  input wire [ADDR_WIDTH_B-1:0] addrb,
  output wire [READ_DATA_WIDTH_B-1:0] doutb,
  output wire sbiterrb,
  output wire dbiterrb
);
  reg [WRITE_DATA_WIDTH_A-1:0] mem [0:(1<<ADDR_WIDTH_A)-1];

  assign sbiterra = 1'b0;
  assign dbiterra = 1'b0;
  assign sbiterrb = 1'b0;
  assign dbiterrb = 1'b0;

  reg [READ_DATA_WIDTH_B-1:0] dout_pipe [0:READ_LATENCY_B-1];
  integer i;

  always @(posedge clka) begin
    if (ena && wea) begin
      mem[addra] <= dina;
    end
  end

  always @(posedge clkb) begin
    if (enb) begin
      dout_pipe[0] <= mem[addrb];
      for (i = 1; i < READ_LATENCY_B; i = i + 1) begin
        dout_pipe[i] <= dout_pipe[i-1];
      end
    end
  end

  assign doutb = (READ_LATENCY_B > 0) ? dout_pipe[READ_LATENCY_B-1] : mem[addrb];
endmodule

module xpm_memory_spram #(
  parameter ADDR_WIDTH_A = 6,
  parameter AUTO_SLEEP_TIME = 0,
  parameter BYTE_WRITE_WIDTH_A = 32,
  parameter CASCADE_HEIGHT = 0,
  parameter ECC_MODE = "no_ecc",
  parameter MEMORY_INIT_FILE = "none",
  parameter MEMORY_INIT_PARAM = "0",
  parameter MEMORY_OPTIMIZATION = "true",
  parameter MEMORY_PRIMITIVE = "auto",
  parameter MEMORY_SIZE = 2048,
  parameter MESSAGE_CONTROL = 0,
  parameter READ_DATA_WIDTH_A = 32,
  parameter READ_LATENCY_A = 2,
  parameter READ_RESET_VALUE_A = "0",
  parameter RST_MODE_A = "SYNC",
  parameter SIM_ASSERT_CHK = 0,
  parameter USE_EMBEDDED_CONSTRAINT = 0,
  parameter USE_MEM_INIT = 1,
  parameter WAKEUP_TIME = "disable_sleep",
  parameter WRITE_DATA_WIDTH_A = 32,
  parameter WRITE_MODE_A = "read_first"
)(
  input wire clka,
  input wire rsta,
  input wire ena,
  input wire regcea,
  input wire [ADDR_WIDTH_A-1:0] addra,
  input wire [WRITE_DATA_WIDTH_A-1:0] dina,
  input wire wea,
  output wire [READ_DATA_WIDTH_A-1:0] douta,
  input wire injectsbiterra,
  input wire injectdbiterra,
  output wire sbiterra,
  output wire dbiterra,
  input wire sleep
);
  reg [WRITE_DATA_WIDTH_A-1:0] mem [0:(1<<ADDR_WIDTH_A)-1];

  assign sbiterra = 1'b0;
  assign dbiterra = 1'b0;

  reg [READ_DATA_WIDTH_A-1:0] dout_pipe [0:READ_LATENCY_A-1];
  integer i;

  always @(posedge clka) begin
    if (ena) begin
      if (wea) begin
        mem[addra] <= dina;
      end
      dout_pipe[0] <= mem[addra];
      for (i = 1; i < READ_LATENCY_A; i = i + 1) begin
        dout_pipe[i] <= dout_pipe[i-1];
      end
    end
  end

  assign douta = (READ_LATENCY_A > 0) ? dout_pipe[READ_LATENCY_A-1] : mem[addra];
endmodule

module xpm_memory_tdpram #(
  parameter ADDR_WIDTH_A = 6,
  parameter ADDR_WIDTH_B = 6,
  parameter AUTO_SLEEP_TIME = 0,
  parameter BYTE_WRITE_WIDTH_A = 32,
  parameter BYTE_WRITE_WIDTH_B = 32,
  parameter CASCADE_HEIGHT = 0,
  parameter CLOCKING_MODE = "common_clock",
  parameter ECC_MODE = "no_ecc",
  parameter MEMORY_INIT_FILE = "none",
  parameter MEMORY_INIT_PARAM = "0",
  parameter MEMORY_OPTIMIZATION = "true",
  parameter MEMORY_PRIMITIVE = "auto",
  parameter MEMORY_SIZE = 2048,
  parameter MESSAGE_CONTROL = 0,
  parameter READ_DATA_WIDTH_A = 32,
  parameter READ_DATA_WIDTH_B = 32,
  parameter READ_LATENCY_A = 2,
  parameter READ_LATENCY_B = 2,
  parameter READ_RESET_VALUE_A = "0",
  parameter READ_RESET_VALUE_B = "0",
  parameter RST_MODE_A = "SYNC",
  parameter RST_MODE_B = "SYNC",
  parameter SIM_ASSERT_CHK = 0,
  parameter USE_EMBEDDED_CONSTRAINT = 0,
  parameter USE_MEM_INIT = 1,
  parameter WAKEUP_TIME = "disable_sleep",
  parameter WRITE_DATA_WIDTH_A = 32,
  parameter WRITE_DATA_WIDTH_B = 32,
  parameter WRITE_MODE_A = "no_change",
  parameter WRITE_MODE_B = "no_change"
)(
  input wire clka,
  input wire rsta,
  input wire ena,
  input wire regcea,
  input wire wea,
  input wire [ADDR_WIDTH_A-1:0] addra,
  input wire [WRITE_DATA_WIDTH_A-1:0] dina,
  input wire injectsbiterra,
  input wire injectdbiterra,
  output wire sbiterra,
  output wire dbiterra,
  output wire [READ_DATA_WIDTH_A-1:0] douta,
  input wire clkb,
  input wire rstb,
  input wire enb,
  input wire regceb,
  input wire web,
  input wire [ADDR_WIDTH_B-1:0] addrb,
  input wire [WRITE_DATA_WIDTH_B-1:0] dinb,
  output wire [READ_DATA_WIDTH_B-1:0] doutb,
  input wire injectsbiterrb,
  input wire injectdbiterrb,
  output wire sbiterrb,
  output wire dbiterrb,
  input wire sleep
);
  reg [WRITE_DATA_WIDTH_A-1:0] mem [0:(1<<ADDR_WIDTH_A)-1];

  assign sbiterra = 1'b0;
  assign dbiterra = 1'b0;
  assign sbiterrb = 1'b0;
  assign dbiterrb = 1'b0;

  reg [READ_DATA_WIDTH_A-1:0] douta_pipe [0:READ_LATENCY_A-1];
  reg [READ_DATA_WIDTH_B-1:0] doutb_pipe [0:READ_LATENCY_B-1];
  integer i;

  always @(posedge clka) begin
    if (ena) begin
      if (wea) begin
        mem[addra] <= dina;
      end
      douta_pipe[0] <= mem[addra];
      for (i = 1; i < READ_LATENCY_A; i = i + 1) begin
        douta_pipe[i] <= douta_pipe[i-1];
      end
    end
  end

  always @(posedge clkb) begin
    if (enb) begin
      if (web) begin
        mem[addrb] <= dinb;
      end
      doutb_pipe[0] <= mem[addrb];
      for (i = 1; i < READ_LATENCY_B; i = i + 1) begin
        doutb_pipe[i] <= doutb_pipe[i-1];
      end
    end
  end

  assign douta = (READ_LATENCY_A > 0) ? douta_pipe[READ_LATENCY_A-1] : mem[addra];
  assign doutb = (READ_LATENCY_B > 0) ? doutb_pipe[READ_LATENCY_B-1] : mem[addrb];
endmodule
