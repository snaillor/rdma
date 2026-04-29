// axi_bfm.v
// AXI Bus Functional Models for rdma_core simulation
// - AXI-Lite Master BFM (drives config registers)
// - AXI Slave Memory Model (responds to AXI Master read/write)

`timescale 1 ps / 1 ps

// ============================================================================
// AXI-Lite Master BFM
// Drives s_axi_lite interface of rdma_core
// ============================================================================
module axi_lite_master_bfm #(
  parameter ADDR_WIDTH = 18
)(
  input  wire                  clk,
  input  wire                  rstn,

  // AXI-Lite Master outputs
  output reg  [ADDR_WIDTH-1:0] awaddr,
  output reg                   awvalid,
  input  wire                  awready,

  output reg  [31:0]           wdata,
  output reg  [3:0]            wstrb,
  output reg                   wvalid,
  input  wire                  wready,

  input  wire [31:0]           rdata,
  input  wire [1:0]            rresp,
  input  wire                  rvalid,
  output reg                   rready,

  input  wire [1:0]            bresp,
  input  wire                  bvalid,
  output reg                   bready,

  output reg  [ADDR_WIDTH-1:0] araddr,
  output reg                   arvalid,
  input  wire                  arready
);

  // Initialize outputs
  initial begin
    awaddr   = 0;
    awvalid  = 0;
    wdata    = 0;
    wstrb    = 0;
    wvalid   = 0;
    rready   = 0;
    bready   = 0;
    araddr   = 0;
    arvalid  = 0;
  end

  // Write task
  task axi_lite_write;
    input [ADDR_WIDTH-1:0] addr;
    input [31:0]           data;
    reg aw_done, w_done, b_done;
    begin
      aw_done = 0;
      w_done  = 0;
      b_done  = 0;

      // AW + W phases (driven simultaneously, accepted independently)
      @(posedge clk);
      awaddr  <= addr;
      awvalid <= 1'b1;
      wdata   <= data;
      wstrb   <= 4'hF;
      wvalid  <= 1'b1;
      $display("[%0t] AXI-Lite BFM: WRITE addr=0x%0h data=0x%0h awready=%b wready=%b", $time, addr, data, awready, wready);

      while (!aw_done || !w_done) begin
        @(posedge clk);
        if (awready && awvalid && !aw_done) begin
          awvalid <= 1'b0;
          aw_done = 1;
          $display("[%0t] AXI-Lite BFM: AW accepted for addr=0x%0h", $time, addr);
        end
        if (wready && wvalid && !w_done) begin
          wvalid <= 1'b0;
          w_done = 1;
          $display("[%0t] AXI-Lite BFM: W accepted for data=0x%0h", $time, data);
        end
      end

      // B phase
      bready <= 1'b1;
      while (!bvalid) @(posedge clk);
      @(posedge clk);
      bready <= 1'b0;
    end
  endtask

  // Read task
  task axi_lite_read;
    input  [ADDR_WIDTH-1:0] addr;
    output [31:0]           data;
    begin
      // AR phase
      @(posedge clk);
      araddr  <= addr;
      arvalid <= 1'b1;

      while (!arready) @(posedge clk);
      @(posedge clk);
      arvalid <= 1'b0;

      // R phase
      rready <= 1'b1;
      while (!rvalid) @(posedge clk);
      data <= rdata;
      // Hold rready for one more cycle
      @(posedge clk);
      rready <= 1'b0;
    end
  endtask

endmodule

// ============================================================================
// AXI Slave Memory Model (512-bit, 32-bit address)
// Responds to AXI Master read/write requests with a simple BRAM model
// Supports multiple outstanding transactions
// ============================================================================
module axi_slave_mem_model #(
  parameter ADDR_WIDTH = 32,
  parameter ID_WIDTH   = 1,
  parameter DATA_WIDTH = 512,
  parameter MEM_DEPTH  = 16384  // Number of 512-bit words
)(
  input wire clk,
  input wire rstn,

  // AW channel
  input  wire [ID_WIDTH-1:0]   awid,
  input  wire [ADDR_WIDTH-1:0] awaddr,
  input  wire [7:0]            awlen,
  input  wire [2:0]            awsize,
  input  wire                  awvalid,
  output reg                   awready,

  // W channel
  input  wire [DATA_WIDTH-1:0] wdata,
  input  wire [DATA_WIDTH/8-1:0] wstrb,
  input  wire                  wlast,
  input  wire                  wvalid,
  output reg                   wready,

  // B channel
  output reg  [ID_WIDTH-1:0]   bid,
  output reg  [1:0]            bresp,
  output reg                   bvalid,
  input  wire                  bready,

  // AR channel
  input  wire [ID_WIDTH-1:0]   arid,
  input  wire [ADDR_WIDTH-1:0] araddr,
  input  wire [7:0]            arlen,
  input  wire [2:0]            arsize,
  input  wire                  arvalid,
  output reg                   arready,

  // R channel
  output reg  [ID_WIDTH-1:0]   rid,
  output reg  [DATA_WIDTH-1:0] rdata,
  output reg  [1:0]            rresp,
  output reg                   rlast,
  output reg                   rvalid,
  input  wire                  rready
);

  // Memory array - initialized to zero
  reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

  integer init_i;
  initial begin
    for (init_i = 0; init_i < MEM_DEPTH; init_i = init_i + 1)
      mem[init_i] = {DATA_WIDTH{1'b0}};
  end

  // Write path
  reg [ADDR_WIDTH-1:0] wr_addr;
  reg [7:0]            wr_len;
  reg [7:0]            wr_cnt;
  reg                  wr_active;

  always @(posedge clk) begin
    if (!rstn) begin
      awready   <= 1'b1;
      wready    <= 1'b0;
      bvalid    <= 1'b0;
      wr_active <= 1'b0;
      wr_cnt    <= 0;
    end else begin
      if (awvalid && awready) begin
        awready   <= 1'b0;
        wr_addr   <= awaddr;
        wr_len    <= awlen;
        wr_cnt    <= 0;
        wr_active <= 1'b1;
        wready    <= 1'b1;
      end

      if (wvalid && wready) begin
        // Write to memory (byte-enable)
        mem[wr_addr[ADDR_WIDTH-1:6]] <= wdata;
        wr_cnt <= wr_cnt + 1;
        if (wlast) begin
          wready    <= 1'b0;
          wr_active <= 1'b0;
          bvalid    <= 1'b1;
          bid       <= awid;
          bresp     <= 2'b00;
        end
      end

      if (bvalid && bready) begin
        bvalid  <= 1'b0;
        awready <= 1'b1;
      end
    end
  end

  // Read path
  reg [ADDR_WIDTH-1:0] rd_addr;
  reg [7:0]            rd_len;
  reg [7:0]            rd_cnt;
  reg                  rd_active;

  always @(posedge clk) begin
    if (!rstn) begin
      arready   <= 1'b1;
      rvalid    <= 1'b0;
      rd_active <= 1'b0;
      rd_cnt    <= 0;
    end else begin
      if (arvalid && arready) begin
        arready   <= 1'b0;
        rd_addr   <= araddr;
        rd_len    <= arlen;
        rd_cnt    <= 0;
        rd_active <= 1'b1;
        $display("[%0t] AXI_SLAVE_READ: addr=0x%08h len=%0d arid=%0d", $time, araddr, arlen, arid);
      end

      if (rd_active && (!rvalid || rready)) begin
        rdata  <= mem[rd_addr[ADDR_WIDTH-1:6]];
`ifdef SIMULATION
        if (rd_cnt == 0)
          $display("[%0t] DDR_READ: addr=%08h idx=%0d rdata[31:0]=%h [63:32]=%h [127:96]=%h [255:224]=%h",
                   $time, rd_addr, rd_addr[ADDR_WIDTH-1:6],
                   mem[rd_addr[ADDR_WIDTH-1:6]][31:0],
                   mem[rd_addr[ADDR_WIDTH-1:6]][63:32],
                   mem[rd_addr[ADDR_WIDTH-1:6]][127:96],
                   mem[rd_addr[ADDR_WIDTH-1:6]][255:224]);
`endif
        rid    <= arid;
        rresp  <= 2'b00;
        rlast  <= (rd_cnt == rd_len);
        rvalid <= 1'b1;
        rd_cnt <= rd_cnt + 1;
        rd_addr <= rd_addr + (1 << 6);  // 64-byte stride (512-bit)

        if (rd_cnt == rd_len) begin
          rd_active <= 1'b0;
          arready   <= 1'b1;
        end
      end

      if (rvalid && rready && rlast) begin
        rvalid <= 1'b0;
      end
    end
  end

  // Pre-load memory with debug pattern
  integer i;
  initial begin
    for (i = 0; i < MEM_DEPTH; i = i + 1) begin
      mem[i] = {DATA_WIDTH{1'b0}};
    end
  end

  // Task to write a 512-bit word into the memory model (for test setup)
  task write_mem;
    input [ADDR_WIDTH-1:0] addr;
    input [DATA_WIDTH-1:0] data;
    begin
`ifdef SIMULATION
      $display("[%0t] DDR_WRITE: addr=%08h idx=%0d data[31:0]=%h [63:32]=%h [127:96]=%h [255:224]=%h",
               $time, addr, addr[ADDR_WIDTH-1:6],
               data[31:0], data[63:32], data[127:96], data[255:224]);
`endif
      mem[addr[ADDR_WIDTH-1:6]] = data;
    end
  endtask

  // Task to read a 512-bit word from the memory model (for verification)
  task read_mem;
    input  [ADDR_WIDTH-1:0] addr;
    output [DATA_WIDTH-1:0] data;
    begin
      data = mem[addr[ADDR_WIDTH-1:6]];
    end
  endtask

endmodule
