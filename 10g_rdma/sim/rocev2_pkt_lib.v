// rocev2_pkt_lib.v
// RoCEv2 packet construction and parsing library for simulation
// All tasks operate on 512-bit AXI-Stream tdata + 64-bit tkeep
//
// Packet layout (IPv4 path, 512-bit aligned):
//   [111:0]    = Ethernet Header (14 bytes)
//   [271:112]  = IPv4 Header (20 bytes)
//   [335:272]  = UDP Header (8 bytes)
//   [431:336]  = BTH (12 bytes)
//   [559:432]  = RETH (16 bytes) for RDMA Write
//   [767:560]  = Payload (first ~26 bytes, rest in subsequent beats)
//   ... ICRC at the end
//
// Note: All header fields are byte-swapped (little-endian on wire)

`timescale 1 ps / 1 ps

// BTH Opcodes - defined as localparam in the module below

module rocev2_pkt_lib;

  // BTH Opcodes
  localparam [7:0] OPC_WRITE_FIRST = 8'h06;
  localparam [7:0] OPC_WRITE_MIDDLE = 8'h07;
  localparam [7:0] OPC_WRITE_LAST  = 8'h08;
  localparam [7:0] OPC_WRITE_ONLY  = 8'h0A;
  localparam [7:0] OPC_ACK         = 8'h11;
  localparam [7:0] OPC_NAK_PSN     = 8'h12;
  localparam [7:0] OPC_NAK_SEQ     = 8'h13;

  // ========================================================================
  // Parse TX packet: extract RoCEv2 header fields from 512-bit tdata
  // ========================================================================
  task automatic parse_tx_pkt;
    input  [511:0] tdata;
    input  [63:0]  tkeep;
    input          tlast;

    // Output fields
    output [47:0]  eth_dst;
    output [47:0]  eth_src;
    output [15:0]  eth_type;
    output [7:0]   ip_version;
    output [15:0]  ip_length;
    output [31:0]  ip_src;
    output [31:0]  ip_dst;
    output [15:0]  udp_src_port;
    output [15:0]  udp_dst_port;
    output [15:0]  udp_length;
    output [7:0]   bth_opcode;
    output         bth_se;
    output [23:0]  bth_psn;
    output [23:0]  bth_qpn;
    output [15:0]  bth_pkey;
    output [63:0]  reth_va;
    output [31:0]  reth_rkey;
    output [31:0]  reth_dma_len;
    output [31:0]  payload_bytes;  // computed from tkeep
    begin
      // Ethernet: bytes 0-13, in tdata[111:0] (byte-swapped)
      eth_dst  = {tdata[7:0], tdata[15:8], tdata[23:16], tdata[31:24], tdata[39:32], tdata[47:40]};
      eth_src  = {tdata[55:48], tdata[63:56], tdata[71:64], tdata[79:72], tdata[87:80], tdata[95:88]};
      eth_type = {tdata[103:96], tdata[111:104]};

      // IPv4: bytes 14-33, in tdata[271:112]
      ip_version = tdata[119:112];  // version + IHL byte
      ip_length  = {tdata[127:120], tdata[135:128]};
      ip_src     = {tdata[207:200], tdata[215:208], tdata[223:216], tdata[231:224]};
      ip_dst     = {tdata[239:232], tdata[247:240], tdata[255:248], tdata[263:256]};

      // UDP: bytes 34-41, in tdata[335:272]
      udp_src_port = {tdata[279:272], tdata[287:280]};
      udp_dst_port = {tdata[295:288], tdata[303:296]};
      udp_length   = {tdata[311:304], tdata[319:312]};

      // BTH: bytes 42-53, in tdata[431:336]
      bth_opcode = tdata[343:336];
      bth_se     = tdata[367];         // Solicited Event bit
      bth_psn    = {tdata[431:424], tdata[423:416], tdata[415:408]};
      bth_qpn    = {tdata[383:376], tdata[391:384], tdata[399:392]};
      bth_pkey   = {tdata[367:360], tdata[359:352]};

      // RETH: bytes 54-69, in tdata[559:432] (only for Write opcodes)
      reth_va     = {tdata[439:432], tdata[447:440], tdata[455:448], tdata[463:456],
                     tdata[471:464], tdata[479:472], tdata[487:480], tdata[495:488]};
      reth_rkey   = {tdata[503:496], tdata[511:504], tdata[519:512], tdata[527:520]};
      reth_dma_len = {tdata[535:528], tdata[543:536], tdata[551:544], tdata[559:552]};

      // Payload size: count set bits in tkeep * 8
      payload_bytes = 0;
      begin : count_keep
        integer i;
        for (i = 0; i < 64; i = i + 1) begin
          if (tkeep[i]) payload_bytes = payload_bytes + 1;
        end
      end
      payload_bytes = payload_bytes * 8;
    end
  endtask

  // ========================================================================
  // Construct RX ACK packet for injection on RX AXI-Stream
  // ========================================================================
  task automatic build_ack_pkt;
    input  [47:0] dst_mac;     // FPGA MAC
    input  [47:0] src_mac;     // PC MAC
    input  [31:0] src_ip;      // PC IP
    input  [31:0] dst_ip;      // FPGA IP
    input  [23:0] ack_psn;     // ACK PSN (MSN)
    input  [23:0] dest_qpn;    // Destination QPN
    input  [15:0] p_key;       // P_Key
    input  [31:0] aeth;        // AETH: syndrome[7:0] + MSN[23:8]
    output [511:0] tdata;
    output [63:0]  tkeep;
    output         tlast;
    begin
      // ACK packet: 64 bytes
      tkeep = 64'hFFFF_FFFF_FFFF_FFFF;

      // Clear
      tdata = 512'd0;

      // Ethernet (14 bytes) [111:0]
      tdata[7:0]   = dst_mac[47:40]; tdata[15:8]  = dst_mac[39:32];
      tdata[23:16] = dst_mac[31:24]; tdata[31:24] = dst_mac[23:16];
      tdata[39:32] = dst_mac[15:8];  tdata[47:40] = dst_mac[7:0];
      tdata[55:48] = src_mac[47:40]; tdata[63:56] = src_mac[39:32];
      tdata[71:64] = src_mac[31:24]; tdata[79:72] = src_mac[23:16];
      tdata[87:80] = src_mac[15:8];  tdata[95:88] = src_mac[7:0];
      tdata[103:96] = 8'h08;         tdata[111:104] = 8'h00; // EtherType=0x0800

      // IPv4 (20 bytes) [271:112]
      tdata[119:112] = 8'h45;  // Version=4, IHL=5
      tdata[135:128] = 8'h00; tdata[143:136] = 8'h40;  // IP total = 64
      tdata[183:176] = 8'h40;  // TTL=64
      tdata[191:184] = 8'h11;  // Protocol=UDP
      tdata[215:208] = src_ip[31:24]; tdata[223:216] = src_ip[23:16];
      tdata[231:224] = src_ip[15:8];  tdata[239:232] = src_ip[7:0];
      tdata[247:240] = dst_ip[31:24]; tdata[255:248] = dst_ip[23:16];
      tdata[263:256] = dst_ip[15:8];  tdata[271:264] = dst_ip[7:0];

      // UDP (8 bytes) [335:272]
      tdata[279:272] = 8'h12; tdata[287:280] = 8'hB7;  // Src port = 4791
      tdata[295:288] = 8'h12; tdata[303:296] = 8'hB7;  // Dst port = 4791

      // BTH (12 bytes) [431:336]
      tdata[343:336] = 8'h11;  // Opcode = ACK
      tdata[351:344] = ack_psn[7:0];
      tdata[375:368] = ack_psn[15:8];
      tdata[383:376] = ack_psn[23:16];
      tdata[399:392] = dest_qpn[7:0];
      tdata[407:400] = dest_qpn[15:8];
      tdata[415:408] = dest_qpn[23:16];

      // AETH (4 bytes) [495:432]
      tdata[447:440] = 8'h00;  // syndrome=0 (ACK)
      tdata[455:448] = ack_psn[23:16];  // MSN
      tdata[463:456] = ack_psn[15:8];
      tdata[471:464] = ack_psn[7:0];

      tlast = 1'b1;
    end
  endtask

endmodule
