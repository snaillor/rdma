// resp_handler_timer.v
// 文件名          : resp_handler_timer.v
// 版本            : v1.0
// 描述            : 响应处理定时器模块，实现基于 PSN 的往返时间测量
//                   计算自适应重传超时时间，支持指数退避
// Verilog 标准    : Verilog'2001

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
`timescale 1ps/1ps

(* DowngradeIPIdentifiedWarnings="yes" *)
module resp_handler_timer
#(
    parameter   C_NUM_QP                = 256,
    parameter   C_QP_INDX_WIDTH         = 8,
    parameter   C_NUM_CYCLES_4US        = 512, // Number of clock cycles that make 4 us (for 125Mhz clk period it is 512)
    parameter   C_OS_Q_INDX_WIDTH       = 3
)
(
  input  wire				     core_clk,
  input  wire				     core_rstn,	    // Active low core reset

  input  wire [3:0]			     i_cfg_base_cnt,
  output wire [C_NUM_QP -1: 0]               o_q_timed_out,
  input  wire [C_NUM_QP -1: 0]               i_timer_en,
  input  wire [C_NUM_QP -1: 0]               i_reload_timer_wqe,
  input  wire [C_NUM_QP -1: 0]               i_reload_timer_acknack,
  input  wire [C_NUM_QP -1: 0]               i_reset_timer_osq_nacked,
  input  wire [C_NUM_QP -1: 0]               i_rnr_nak_rcvd,
  input  wire [4:0]                          i_rnr_nak_timer,
  input  wire [4:0]               	     i_reload_value_wqe,
  input  wire [4:0]               	     i_reload_value_acknack

);
`include "rdma_macros.vh"

localparam BASE_CNT = clog2(C_NUM_CYCLES_4US); // Base count of 512 = 10th bit toggle;  which is equivalent to 4.096 us with 125MHz clock

// The base timer counts upto 4.096 us. This comes out to 512 cycles for
// 125MHz clock. This will require 9 bits. Additionally every number in the
// x 2^(retry_timer). The retry timer count value can be upto 5 bits. so 2^31.
// require 31 bits for this exponential timer count.
// Therefore total number of bits = 9 + 31 = 40
// for 200MHZ clock, it is 41 bits. Keeping 42 to be safe
reg [41:0] global_timer;
reg [41:0] global_timer_ff;
reg  [C_NUM_QP*5 -1:0] qp_timer_count_ff;
wire [41:0] global_timer_toggled;
wire [C_NUM_QP*5 -1:0] qp_timer_count;

genvar i;

// To have en efficient implementation, a global counter is used that keeps
// running. Now, for a timer_count of say 2, we need to count 4 x 4.096 us.
// This comes out to bit 11th bit of the global timer. In other words,
// whenever the 11th bit of the gloabl timer toggles we would have measured
// 4 x 4.096 us. However, since the timer is always running, while the
// timer_count is enabled asynchronously, in the worst case we might have the
// relevant bit toggling in the next clock cycle of the timer being enabled.
// In order to handle this, the design expects 2 subsequent toggles. One
// enables the expiry while the other one triggers it.
// In the meanwhile if the timer is reloaded (an ack is received) the
// expiry_enabled is reset and the process starts again.
reg  [C_NUM_QP -1:0] expiry_enabled_ff;
reg  [C_NUM_QP -1:0] expiry_triggered_ff;
reg  [C_NUM_QP -1:0] reset_enabled_ff;
wire [C_NUM_QP -1:0] expiry_enabled;
wire [C_NUM_QP -1:0] expiry_triggered;
wire [C_NUM_QP -1:0] reset_enabled;

// The RNR NAK syndrome values do not match with the values in the retry
// counters. IN order to use the same counters for both the types of timers,
// a mapping is used. This mapping is given below.
// The requirement for RNR NAK is to wait for "at least" that much time. So,
// the actual time can be more than what is requested. (ms = miliseconds)
// | Binary val	|    |  Timer val	| RNR NAK mapped codes	| RNR NAK mapped values   |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "00001"	| 1  |  0.008	    ms	| 			|     	                  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "00010"	| 2  |  0.016	    ms	| "00001"		|     0.01	      ms  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "00011"	| 3  |  0.032	    ms	| "00010" 	"00011"	|     0.02	0.03  ms  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "00100"	| 4  |  0.064	    ms	| "00100" 	"00101"	|     0.04	0.06  ms  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "00101"	| 5  |  0.128	    ms	| "00110"	"00111"	|     0.08	0.12  ms  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "00110"	| 6  |  0.256	    ms	| "01000"	"01001"	|     0.16	0.24  ms  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "00111"	| 7  |  0.512	    ms	| "01101"	"01011"	|     0.32	0.48  ms  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "01000"	| 8  |  1.024	    ms	| "01100"	"01101"	|     0.64	0.96  ms  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "01001"	| 9  |  2.048	    ms	| "01110	"01111"	|     1.28	1.92  ms  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "01010"	| 10 |	4.096	    ms	| "10000"	"10001"	|     2.56	3.84  ms  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "01011"	| 11 |	8.192	    ms	| "10010	"10011"	|     5.12	7.68  ms  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "01100"	| 12 |	16.384	    ms	| "10100"	"10101"	|     10.24	15.36 ms  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "01101"	| 13 |	32.768	    ms	| "10110"	"10111"	|     20.48	30.72 ms  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "01110"	| 14 |	65.536	    ms	| "11000"	"11001"	|     40.96	61.44 ms  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "01111"	| 15 |	131.072	    ms	| "11010"	"11011"	|     81.92	122.88 ms |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "10000"	| 16 |	262.144	    ms	| "11100"	"11101"	|     163.84	245.76 ms |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "10001"	| 17 |	524.288	    ms	| "11111"	"11110"	|     491.52	327.68 ms |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "10010"	| 18 |	1048.576    ms	| "00000"		|     655.36	      ms  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "10011"	| 19 |	2097.152    ms	| 			|     	                  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "10100"	| 20 |	4194.304    ms	| 			|     	                  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "10101"	| 21 |	8388.608    ms	| 			|     	                  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "10110"	| 22 |	16777.216   ms	| 			|     	                  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "10111"	| 23 |	33554.432   ms	| 			|     	                  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "11000"	| 24 |	67108.864   ms	| 			|     	                  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "11001"	| 25 |	134217.728  ms	| 			|     	                  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "11010"	| 26 |	268435.456  ms	| 			|     	                  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "11011"	| 27 |	536870.912  ms	| 			|     	                  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "11100"	| 28 |	1073741.824 ms	| 			|     	                  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "11101"	| 29 |	2147483.648 ms	| 			|     	                  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "11110"	| 30 |	4294967.296 ms	| 			|     	                  |
//-|------------|----|------------------|-----------------------|-------------------------|
// |  "11111"	| 31 |	8589934.592 ms	| 			|     	                  |
//-|------------|----|------------------|-----------------------|-------------------------|

reg  [4:0] rnr_nak_reload_val;
wire [5:0] cfg_base_cnt = {2'b00, i_cfg_base_cnt};

 always @(*)
 begin
     case(i_rnr_nak_timer)
         5'b00001          :  rnr_nak_reload_val <= 5'b00010;
         5'b00010, 5'b00011: rnr_nak_reload_val <= 5'b00011;
         5'b00100, 5'b00101: rnr_nak_reload_val <= 5'b00100;
         5'b00110, 5'b00111: rnr_nak_reload_val <= 5'b00101;
         5'b01000, 5'b01001: rnr_nak_reload_val <= 5'b00110;
         5'b01010, 5'b01011: rnr_nak_reload_val <= 5'b00111;
         5'b01100, 5'b01101: rnr_nak_reload_val <= 5'b01000;
         5'b01110, 5'b01111: rnr_nak_reload_val <= 5'b01001;
         5'b10000, 5'b10001: rnr_nak_reload_val <= 5'b01010;
         5'b10010, 5'b10011: rnr_nak_reload_val <= 5'b01011;
         5'b10100, 5'b10101: rnr_nak_reload_val <= 5'b01100;
         5'b10110, 5'b10111: rnr_nak_reload_val <= 5'b01101;
         5'b11000, 5'b11001: rnr_nak_reload_val <= 5'b01110;
         5'b11010, 5'b11011: rnr_nak_reload_val <= 5'b01111;
         5'b11100, 5'b11101: rnr_nak_reload_val <= 5'b10000;
         5'b11111, 5'b11110: rnr_nak_reload_val <= 5'b10001;
         5'b00000          : rnr_nak_reload_val <= 5'b10010;
         default           :  rnr_nak_reload_val <= 5'b00010;
     endcase
 end

`MSFF_R(global_timer, (global_timer + 1'b1), core_clk, ~core_rstn)
`MSFF_R(global_timer_ff, (global_timer), core_clk, ~core_rstn)

// Single cycle pulse
assign global_timer_toggled = global_timer ^ global_timer_ff;

generate
for (i=0; i<C_NUM_QP; i= i+1) begin: timer_exp_load
        // enabled when the global timer bit for the count value toggles
        // reloaded
        assign expiry_enabled[i] = reset_enabled_ff[i] ? 1'b0 : (global_timer_toggled[(cfg_base_cnt + qp_timer_count_ff[i*5+:5])] | expiry_enabled_ff[i]);
        assign reset_enabled[i] = (~i_timer_en[i] | i_reload_timer_wqe[i] | i_reload_timer_acknack[i] | i_rnr_nak_rcvd[i] | i_reset_timer_osq_nacked[i]);

        // Trigger expiry when expiry is enabled and global timer bit toggled.
        // Single cycle pulse
        assign expiry_triggered[i] = global_timer_toggled[(cfg_base_cnt + qp_timer_count_ff[i*5+:5])] & expiry_enabled_ff[i] & ~reset_enabled[i];

        assign qp_timer_count[i*5+: 5] =  i_rnr_nak_rcvd[i] ? (rnr_nak_reload_val) :
					(i_reload_timer_wqe[i] ? i_reload_value_wqe :
	       		                (i_reload_timer_acknack[i] ? i_reload_value_acknack : qp_timer_count_ff[i*5+:5]));

end
endgenerate

`MSFF_R(qp_timer_count_ff, qp_timer_count, core_clk, ~core_rstn)
`MSFF_R(expiry_enabled_ff, expiry_enabled, core_clk, ~core_rstn)
`MSFF_R(reset_enabled_ff, reset_enabled, core_clk, ~core_rstn)
`MSFF_R(expiry_triggered_ff, expiry_triggered, core_clk, ~core_rstn)

// QP0 does not exist and QP1 is UD - so no timeout
generate
  if (C_NUM_QP > 2)
    assign o_q_timed_out = {expiry_triggered_ff[C_NUM_QP-1: 2], 2'b0};
  else
    assign o_q_timed_out = {C_NUM_QP{1'b0}};
endgenerate

endmodule

