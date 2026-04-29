/******************************************************************************
 * blk_mem_gen_wrapper - Behavioral model for Xilinx Block Memory Generator
 *
 * Simple Dual Port RAM wrapper mapping to xpm_memory_sdpram behavioral model.
 * Supports SDP mode (c_mem_type=1) with configurable output registers.
 ******************************************************************************/
module blk_mem_gen_wrapper #(
    parameter c_mem_type              = 1,
    parameter c_byte_size             = 8,
    parameter c_has_mem_output_regs_a = 0,
    parameter c_has_mem_output_regs_b = 0,
    parameter c_write_width_a         = 32,
    parameter c_write_depth_a         = 256,
    parameter c_read_width_a          = 32,
    parameter c_read_depth_a          = 256,
    parameter c_addra_width           = 8,
    parameter c_write_width_b         = 32,
    parameter c_write_depth_b         = 256,
    parameter c_read_width_b          = 32,
    parameter c_read_depth_b          = 256,
    parameter c_addrb_width           = 8,
    parameter c_write_mode_a          = "WRITE_FIRST",
    parameter c_write_mode_b          = "WRITE_FIRST"
)(
    // Port A - Write port
    input  wire                        clka,
    input  wire                        ssra,
    input  wire [c_write_width_a-1:0]  dina,
    input  wire [c_addra_width-1:0]    addra,
    input  wire                        ena,
    input  wire                        regcea,
    input  wire                        wea,
    output wire [c_read_width_a-1:0]   douta,

    // Port B - Read port
    input  wire                        clkb,
    input  wire                        ssrb,
    input  wire [c_write_width_b-1:0]  dinb,
    input  wire [c_addrb_width-1:0]    addrb,
    input  wire                        enb,
    input  wire                        regceb,
    input  wire                        web,
    output wire [c_read_width_b-1:0]   doutb,

    output wire                        dbiterr,
    output wire                        sbiterr
);

    assign dbiterr = 1'b0;
    assign sbiterr = 1'b0;

    localparam READ_LATENCY_B = c_has_mem_output_regs_b ? 2 : 1;

    xpm_memory_sdpram #(
        .ADDR_WIDTH_A(c_addra_width),
        .ADDR_WIDTH_B(c_addrb_width),
        .WRITE_DATA_WIDTH_A(c_write_width_a),
        .READ_DATA_WIDTH_B(c_read_width_b),
        .READ_RESET_VALUE_B("0"),
        .READ_LATENCY_B(READ_LATENCY_B),
        .WRITE_MODE_A(c_write_mode_a),
        .MEMORY_SIZE(c_write_depth_a * c_write_width_a),
        .MEMORY_PRIMITIVE("auto")
    ) inst_sdpram (
        // Port A - Write
        .clka       (clka),
        .ena        (ena),
        .wea        (wea),
        .addra      (addra),
        .dina       (dina),
        .injectsbiterra(1'b0),
        .injectdbiterra(1'b0),

        // Port B - Read
        .clkb       (clkb),
        .enb        (enb),
        .rstb       (ssrb),
        .regceb     (regceb),
        .addrb      (addrb),
        .doutb      (doutb),

        // Sleep
        .sleep      (1'b0)
    );

    // douta is not used in SDP mode
    assign douta = {c_read_width_a{1'b0}};

endmodule
