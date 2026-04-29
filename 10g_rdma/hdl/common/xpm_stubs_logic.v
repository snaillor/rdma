// xpm_stubs_logic.v
// Behavioral logic replacement for Xilinx XPM primitives
// Purpose: iverilog simulation with correct reset/init behavior
//
// Key differences from xpm_stubs.v:
//   - All pointers/flags properly reset on rst
//   - FIFO full/empty/valid flags correctly computed
//   - FWFT (First-Word Fall-Through) mode supported
//   - wr_ack generated on every write acceptance
//   - Memory read latency pipeline properly reset

`timescale 1 ps / 1 ps

// ============================================================================
// xpm_fifo_sync - Synchronous FIFO
// Supports: std mode (valid after rd_en) and fwft mode (dout always shows next)
// ============================================================================
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
  input  wire                         sleep,
  input  wire                         rst,
  input  wire                         wr_clk,
  input  wire                         wr_en,
  input  wire  [WRITE_DATA_WIDTH-1:0]  din,
  input  wire                         rd_en,
  output wire  [READ_DATA_WIDTH-1:0]   dout,
  output wire                          full,
  output wire                          prog_full,
  output wire                          wr_ack,
  output wire                          overflow,
  output wire                          almost_full,
  output wire  [WR_DATA_COUNT_WIDTH-1:0] wr_data_count,
  output wire                          empty,
  output wire                          prog_empty,
  output wire                          valid,
  output wire                          underflow,
  output wire                          almost_empty,
  output wire  [RD_DATA_COUNT_WIDTH-1:0] rd_data_count,
  output wire                          sbiterr,
  output wire                          dbiterr,
  input  wire                          injectsbiterr,
  input  wire                          injectdbiterr,
  output wire                          wr_rst_busy,
  output wire                          rd_rst_busy
);

  localparam DEPTH = FIFO_WRITE_DEPTH;
  localparam ADDR_W = $clog2(DEPTH);

  // Memory
  reg [WRITE_DATA_WIDTH-1:0] mem [0:DEPTH-1];
  integer i;
  initial for (i = 0; i < DEPTH; i = i + 1) mem[i] = {WRITE_DATA_WIDTH{1'b0}};

  // Pointers (one bit wider than needed to distinguish full vs empty)
  reg [ADDR_W:0] wr_ptr;
  reg [ADDR_W:0] rd_ptr;

  // Flags
  reg full_r;
  reg empty_r;
  reg wr_ack_r;
  reg valid_r;
  reg overflow_r;
  reg underflow_r;

  // Reset busy (deasserted after reset)
  reg wr_rst_busy_r;
  reg rd_rst_busy_r;

  // Pipeline for std mode read latency
  reg [READ_DATA_WIDTH-1:0] dout_r;

  // FWFT: state tracking (fwft_loaded, fwft_valid are regs)
  // dout is combinational: directly reads mem[rd_ptr] when data is available
  reg fwft_valid;
  reg fwft_loaded; // whether FIFO has data available for reading

  // Compute fill count
  wire [ADDR_W:0] fill_count = wr_ptr - rd_ptr;
  wire [ADDR_W-1:0] rd_ptr_next = rd_ptr[ADDR_W-1:0] + 1'b1;

  // Data count outputs (approximate)
  assign wr_data_count = fill_count[ADDR_W:ADDR_W-WR_DATA_COUNT_WIDTH+1];
  assign rd_data_count = fill_count[ADDR_W:ADDR_W-RD_DATA_COUNT_WIDTH+1];

  // Prog flags
  assign prog_full  = (fill_count >= PROG_FULL_THRESH);
  assign prog_empty = (fill_count <= PROG_EMPTY_THRESH);
  assign almost_full  = (fill_count >= DEPTH - 2);
  assign almost_empty = (fill_count <= 2);

  // ECC
  assign sbiterr = 1'b0;
  assign dbiterr = 1'b0;

  always @(posedge wr_clk) begin
    if (rst) begin
      wr_ptr        <= {ADDR_W+1{1'b0}};
      rd_ptr        <= {ADDR_W+1{1'b0}};
      full_r        <= 1'b0;
      empty_r       <= 1'b1;
      wr_ack_r      <= 1'b0;
      valid_r       <= 1'b0;
      overflow_r    <= 1'b0;
      underflow_r   <= 1'b0;
      dout_r        <= {READ_DATA_WIDTH{1'b0}};
      wr_rst_busy_r <= 1'b1;
      rd_rst_busy_r <= 1'b1;
      fwft_loaded   <= 1'b0;
      fwft_valid    <= 1'b0;
    end else begin
      wr_rst_busy_r <= 1'b0;
      rd_rst_busy_r <= 1'b0;

      // Default
      wr_ack_r    <= 1'b0;
      overflow_r  <= 1'b0;
      underflow_r <= 1'b0;

      // Write
      if (wr_en && !full_r) begin
        mem[wr_ptr[ADDR_W-1:0]] <= din;
        wr_ptr <= wr_ptr + 1;
        wr_ack_r <= 1'b1;
        if (wr_ptr < 20)
          $display("[%0t] FIFO_WR %m: ptr=%0d din[31:0]=%08h din[543:512]=%08h din[576]=%b", $time, wr_ptr, din[31:0], din[543:512], din[576]);
      end else if (wr_en && full_r) begin
        overflow_r <= 1'b1;
      end

      // Read - in fwft mode, rd_ptr is advanced by fwft logic below
      if (READ_MODE == "std") begin
        if (rd_en && !empty_r) begin
          rd_ptr <= rd_ptr + 1;
        end else if (rd_en && empty_r) begin
          underflow_r <= 1'b1;
        end
      end

      // fwft mode: dout is combinational (mem[rd_ptr]), only track state
      // Use wr_ptr/rd_ptr directly (not empty_r) to avoid 1-cycle lag
      if (READ_MODE == "fwft") begin
        if (!fwft_loaded && (wr_ptr != rd_ptr)) begin
          // Data became available - mark as loaded (dout follows combinationally)
          fwft_loaded <= 1'b1;
          fwft_valid  <= 1'b1;
        end else if (rd_en && fwft_loaded) begin
          // Consume current word, advance rd_ptr
          rd_ptr <= rd_ptr + 1;
          if ((wr_ptr - rd_ptr) > 1) begin
            fwft_valid <= 1'b1;
          end else begin
            fwft_loaded <= 1'b0;
            fwft_valid  <= 1'b0;
          end
        end
      end

      // std mode: valid follows rd_en with latency
      if (READ_MODE == "std") begin
        if (rd_en && !empty_r) begin
          dout_r  <= mem[rd_ptr[ADDR_W-1:0]];
          valid_r <= 1'b1;
        end else begin
          valid_r <= 1'b0;
        end
      end

      // Update flags - use next-cycle rd_ptr for fwft
      begin : flag_update
        reg [ADDR_W:0] rd_ptr_next_cycle;
        if (READ_MODE == "fwft") begin
          // In fwft, rd_ptr advances when pop occurs
          rd_ptr_next_cycle = (rd_en && fwft_loaded) ? (rd_ptr + 1) : rd_ptr;
          empty_r <= (wr_ptr == rd_ptr_next_cycle) && !(wr_en && !full_r);
          full_r  <= (wr_ptr[ADDR_W-1:0] == rd_ptr_next_cycle[ADDR_W-1:0]) &&
                     (wr_ptr[ADDR_W] != rd_ptr_next_cycle[ADDR_W]) && !(rd_en && fwft_loaded) ||
                     (wr_ptr - rd_ptr_next_cycle == DEPTH - 1) && wr_en && !full_r;
        end else begin
          // std mode
          rd_ptr_next_cycle = (rd_en && !empty_r) ? (rd_ptr + 1) : rd_ptr;
          empty_r <= (wr_ptr == rd_ptr_next_cycle) && !(wr_en && !full_r);
          full_r  <= (wr_ptr[ADDR_W-1:0] == rd_ptr_next_cycle[ADDR_W-1:0]) &&
                     (wr_ptr[ADDR_W] != rd_ptr_next_cycle[ADDR_W]) && !(rd_en && !empty_r) ||
                     (wr_ptr - rd_ptr_next_cycle == DEPTH - 1) && wr_en && !full_r;
        end
      end
    end
  end

  // Output mux based on mode
  generate
    if (READ_MODE == "fwft") begin : gen_fwft
      // Combinational output: dout directly reflects mem[rd_ptr] when data available
      // This eliminates the 1-cycle register latency - data appears on dout
      // in the same cycle it becomes available
      assign dout  = fwft_loaded ? mem[rd_ptr[ADDR_W-1:0]] : {READ_DATA_WIDTH{1'b0}};
      assign valid = fwft_valid;
    end else begin : gen_std
      assign dout  = dout_r;
      assign valid = valid_r;
    end
  endgenerate

  assign full          = full_r;
  assign empty         = empty_r;
  assign wr_ack        = wr_ack_r;
  assign overflow      = overflow_r;
  assign underflow     = underflow_r;
  assign wr_rst_busy   = wr_rst_busy_r;
  assign rd_rst_busy   = rd_rst_busy_r;

endmodule

// ============================================================================
// xpm_memory_sdpram - Simple Dual Port RAM
// Port A: Write only
// Port B: Read only with configurable latency
// ============================================================================
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
  input  wire                          clka,
  input  wire                          rsta,
  input  wire                          ena,
  input  wire                          regcea,
  input  wire  [ADDR_WIDTH_A-1:0]      addra,
  input  wire  [WRITE_DATA_WIDTH_A-1:0] dina,
  input  wire                          wea,
  input  wire                          injectsbiterra,
  input  wire                          injectdbiterra,
  output wire                          sbiterra,
  output wire                          dbiterra,
  input  wire                          sleep,
  input  wire                          clkb,
  input  wire                          rstb,
  input  wire                          enb,
  input  wire                          regceb,
  input  wire  [ADDR_WIDTH_B-1:0]      addrb,
  output wire  [READ_DATA_WIDTH_B-1:0]  doutb,
  output wire                          sbiterrb,
  output wire                          dbiterrb
);

  localparam DEPTH = 1 << ADDR_WIDTH_A;

  reg [WRITE_DATA_WIDTH_A-1:0] mem [0:DEPTH-1];
  integer i;
  initial for (i = 0; i < DEPTH; i = i + 1) mem[i] = {WRITE_DATA_WIDTH_A{1'b0}};

  assign sbiterra  = 1'b0;
  assign dbiterra  = 1'b0;
  assign sbiterrb  = 1'b0;
  assign dbiterrb  = 1'b0;

  // Write port - support byte-level wea
  localparam WEA_WIDTH = WRITE_DATA_WIDTH_A / BYTE_WRITE_WIDTH_A;
  reg [WEA_WIDTH-1:0] wea_bus;
  always @(*) begin
    // Default: replicate wea[0] for compatibility with 1-bit wea connections
    if (WEA_WIDTH > 1)
      wea_bus = wea ? {WEA_WIDTH{1'b1}} : {WEA_WIDTH{1'b0}};
    else
      wea_bus = wea;
  end

  // Byte-enable write logic
  // k declared outside always block for Verilog-2001 compatibility
  integer k;
  always @(posedge clka) begin
    if (ena) begin
      if (WEA_WIDTH == 1) begin
        if (wea_bus[0]) mem[addra] <= dina;
      end else begin
        for (k = 0; k < WEA_WIDTH; k = k + 1) begin
          if (wea_bus[k])
            mem[addra][k*BYTE_WRITE_WIDTH_A +: BYTE_WRITE_WIDTH_A] <= dina[k*BYTE_WRITE_WIDTH_A +: BYTE_WRITE_WIDTH_A];
        end
      end
    end
  end

  // Read port with pipeline for latency
  generate
    if (READ_LATENCY_B == 0) begin : gen_no_latency
      assign doutb = mem[addrb];
    end else begin : gen_latency
      reg [READ_DATA_WIDTH_B-1:0] pipe [0:READ_LATENCY_B-1];
      integer j;

      always @(posedge clkb) begin
        if (rstb) begin
          for (j = 0; j < READ_LATENCY_B; j = j + 1)
            pipe[j] <= {READ_DATA_WIDTH_B{1'b0}};
        end else if (enb) begin
          if (addrb < DEPTH)
            pipe[0] <= mem[addrb];
          else begin
            pipe[0] <= {READ_DATA_WIDTH_B{1'b0}};
            if (addrb != {ADDR_WIDTH_B{1'b0}} && addrb != {ADDR_WIDTH_B{1'bx}})
              $display("[%0t] SDPRAM %m: read out of bounds addr=%0d depth=%0d", $time, addrb, DEPTH);
          end
          for (j = 1; j < READ_LATENCY_B; j = j + 1)
            pipe[j] <= pipe[j-1];
        end
      end

      assign doutb = pipe[READ_LATENCY_B-1];
    end
  endgenerate

endmodule

// ============================================================================
// xpm_memory_spram - Single Port RAM
// ============================================================================
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
  input  wire                          clka,
  input  wire                          rsta,
  input  wire                          ena,
  input  wire                          regcea,
  input  wire  [ADDR_WIDTH_A-1:0]      addra,
  input  wire  [WRITE_DATA_WIDTH_A-1:0] dina,
  input  wire                          wea,
  output wire  [READ_DATA_WIDTH_A-1:0]  douta,
  input  wire                          injectsbiterra,
  input  wire                          injectdbiterra,
  output wire                          sbiterra,
  output wire                          dbiterra,
  input  wire                          sleep
);

  localparam DEPTH = 1 << ADDR_WIDTH_A;

  reg [WRITE_DATA_WIDTH_A-1:0] mem [0:DEPTH-1];
  integer i;
  initial for (i = 0; i < DEPTH; i = i + 1) mem[i] = {WRITE_DATA_WIDTH_A{1'b0}};

  assign sbiterra = 1'b0;
  assign dbiterra = 1'b0;

  // Write
  always @(posedge clka) begin
    if (ena && wea)
      mem[addra] <= dina;
  end

  // Read with pipeline
  generate
    if (READ_LATENCY_A == 0) begin : gen_douta_no_lat
      assign douta = mem[addra];
    end else begin : gen_doutb_lat
      reg [READ_DATA_WIDTH_A-1:0] pipe_a [0:READ_LATENCY_A-1];
      integer j;
      always @(posedge clka) begin
        if (rsta) begin
          for (j = 0; j < READ_LATENCY_A; j = j + 1)
            pipe_a[j] <= {READ_DATA_WIDTH_A{1'b0}};
        end else if (ena) begin
          pipe_a[0] <= mem[addra];
          for (j = 1; j < READ_LATENCY_A; j = j + 1)
            pipe_a[j] <= pipe_a[j-1];
        end
      end
      assign douta = pipe_a[READ_LATENCY_A-1];
    end
  endgenerate

endmodule

// ============================================================================
// xpm_memory_tdpram - True Dual Port RAM
// Both ports can read and write independently
// ============================================================================
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
  input  wire                          clka,
  input  wire                          rsta,
  input  wire                          ena,
  input  wire                          regcea,
  input  wire                          wea,
  input  wire  [ADDR_WIDTH_A-1:0]      addra,
  input  wire  [WRITE_DATA_WIDTH_A-1:0] dina,
  input  wire                          injectsbiterra,
  input  wire                          injectdbiterra,
  output wire                          sbiterra,
  output wire                          dbiterra,
  output wire  [READ_DATA_WIDTH_A-1:0]  douta,
  input  wire                          clkb,
  input  wire                          rstb,
  input  wire                          enb,
  input  wire                          regceb,
  input  wire                          web,
  input  wire  [ADDR_WIDTH_B-1:0]      addrb,
  input  wire  [WRITE_DATA_WIDTH_B-1:0] dinb,
  output wire  [READ_DATA_WIDTH_B-1:0]  doutb,
  input  wire                          injectsbiterrb,
  input  wire                          injectdbiterrb,
  output wire                          sbiterrb,
  output wire                          dbiterrb,
  input  wire                          sleep
);

  localparam DEPTH = 1 << ADDR_WIDTH_A;

  // Use wider of the two widths for storage
  reg [WRITE_DATA_WIDTH_A-1:0] mem [0:DEPTH-1];
  integer i;
  initial for (i = 0; i < DEPTH; i = i + 1) mem[i] = {WRITE_DATA_WIDTH_A{1'b0}};

  assign sbiterra  = 1'b0;
  assign dbiterra  = 1'b0;
  assign sbiterrb  = 1'b0;
  assign dbiterrb  = 1'b0;

  // Port A write
  always @(posedge clka) begin
    if (ena && wea)
      mem[addra] <= dina;
  end

  // Port B write
  always @(posedge clkb) begin
    if (enb && web)
      mem[addrb] <= dinb;
  end

  // Port A read with pipeline
  generate
    if (READ_LATENCY_A == 0) begin : gen_douta_no_lat
      assign douta = mem[addra];
    end else begin : gen_douta_lat
      reg [READ_DATA_WIDTH_A-1:0] pipe_a [0:READ_LATENCY_A-1];
      integer j;
      always @(posedge clka) begin
        if (rsta) begin
          for (j = 0; j < READ_LATENCY_A; j = j + 1)
            pipe_a[j] <= {READ_DATA_WIDTH_A{1'b0}};
        end else if (ena) begin
          pipe_a[0] <= mem[addra];
          for (j = 1; j < READ_LATENCY_A; j = j + 1)
            pipe_a[j] <= pipe_a[j-1];
        end
      end
      assign douta = pipe_a[READ_LATENCY_A-1];
    end
  endgenerate

  // Port B read with pipeline
  generate
    if (READ_LATENCY_B == 0) begin : gen_doutb_no_lat
      assign doutb = mem[addrb];
    end else begin : gen_doutb_pipe
      reg [READ_DATA_WIDTH_B-1:0] pipe_b [0:READ_LATENCY_B-1];
      integer j;
      always @(posedge clkb) begin
        if (rstb) begin
          for (j = 0; j < READ_LATENCY_B; j = j + 1)
            pipe_b[j] <= {READ_DATA_WIDTH_B{1'b0}};
        end else if (enb) begin
          pipe_b[0] <= mem[addrb];
          for (j = 1; j < READ_LATENCY_B; j = j + 1)
            pipe_b[j] <= pipe_b[j-1];
        end
      end
      assign doutb = pipe_b[READ_LATENCY_B-1];
    end
  endgenerate

endmodule
