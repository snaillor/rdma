// // nvmof_macros.h
// Filename        : bnvmof_macros.h
// Version         : v1.0
// Description     : Common macros file for nvmof
// Verilog-Standard: Verilog'2001
//-- Structure:
//--               -- top.v

///////////////////////////////////////////////////////////////////////////////
// Macros for Flip Flops
///////////////////////////////////////////////////////////////////////////////

`define MSFF_ARN(q, d, clk, rst_n) \
always @(posedge clk, negedge rst_n) begin \
    if (!rst_n) q <= 'b0; \
    else        q <= (d); \
end

`define MSFF_AR(q, d, clk, rst_p) \
always @(posedge clk, posedge rst_p) begin \
    if (rst_p)  q <= 'b0; \
    else        q <= (d); \
end

`define MSFF_RN(q, d, clk, rst_n) \
always @(posedge clk) begin \
    if (!rst_n) q <= 'b0; \
    else        q <= (d); \
end

`define MSFF_R(q, d, clk, rst_p) \
always @(posedge clk) begin \
    if (rst_p)  q <= 'b0; \
    else        q <= (d); \
end

`define MSFF_RL(q, d, clk, rst_p, rst_load) \
always @(posedge clk) begin \
    if (rst_p)  q <= (rst_load); \
    else        q <= (d); \
end

`define MSFF(q, d, clk) \
always @(posedge clk) begin \
    q <= (d); \
end

// This function returns the integer ceiling of the base 2 logarithm of x,
// i.e., the least integer greater than or equal to log2(x).
// coverage off
  function integer clog2;
    input [31:0] value;
    begin
    for (clog2 = 0; value > 1; clog2 = clog2 + 1)
      value = value >> 1;
    end
  endfunction
// coverage on
`ifdef SIMULATION
// Assertion definitions
`define assert_prop(check, pa, mesg, dc = ~core_rstn, clk = core_clk) \
ERROR_``check``: assert property (@(posedge clk) disable iff (dc) (pa)) else `error({`"``check``: `",mesg})

`define cover_prop(check, pc, dc = ~core_rstn, clk = core_clk) \
``check``: cover property (@(posedge clk) disable iff (dc) (pc))

`define cover_point(check, pc, dc = ~core_rstn) \
``check``: coverpoint (pc) iff (!(dc))
///
`endif

