`timescale 1ns / 1ps
`default_nettype wire

/*
 msx_system.v

 The MSX1 part of the three tops: the machine (msx1 of MiSTer MSX1, rtl/msx), the SRAM, the
 loaders of the mcu, the keyboard and the joysticks. Also the unit the simulation runs.

 Loading (all of it through the firmware, no loader in the core):
 - the ROM loader (the roms of core.json, at core start): rom_addr is the SRAM byte address
   (000000 the BIOS, 008000 the ROM of slot 0 page 2: C-BIOS main and logo), the machine is held
   in reset while rom_active;
 - the file loader (FL items, ioctl, one write per byte): file_slot 0 = cartridge A (slot 1 of the
   MSX), 1 = cartridge B (slot 2), 2 = a BIOS file of up to 48 KB (32 KB BIOS + 16 KB of slot 0
   page 2; a file of 32 KB or less switches page 2 off, the logo ROM of C-BIOS would answer there).
   The machine is in reset while a file loads, as MiSTer has it. A cartridge is on from its load
   until eject.
 The mapper of a cartridge: mapper_a / mapper_b, the values of MiSTer (0 auto, 1 none,
 2 Game Master 2, 3 Konami, 4 Konami SCC, 5 ASCII 8, 6 ASCII 16, 7 linear 64K, 8 R-Type; the OSD offers 0-7, eight options at most); a change
 resets the machine.

 clk is 42.857 MHz (12 x 3.57 MHz): ce_10m7 is every fourth clock, as in MiSTer (42.95 MHz there).
*/

module msx_system (
	input wire clk,
	input wire reset,          // the reset switch, the mcu busy

	// the ROM loader of the mcu
	input wire rom_active,
	input wire [31:0] rom_addr,
	input wire [7:0] rom_data,
	input wire rom_wr,

	// the file loader of the mcu (FL items)
	input wire file_active,
	input wire [7:0] file_slot,
	input wire [31:0] file_addr,
	input wire [7:0] file_data,
	input wire file_wr,

	// settings (soft switches)
	input wire [3:0] mapper_a,
	input wire [3:0] mapper_b,
	input wire pal,
	input wire joy_swap,
	input wire eject,          // the cartridges off (a reset as well)

	// input
	input wire [7:0] kb_scancode,
	input wire kb_scancode_upd,
	input wire [12:0] joy_l,   // kg_mcu: 1 up, 2 down, 3 left, 4 right, 6 A, 7 B
	input wire [12:0] joy_r,

	// video of the VDP for msx_video
	output wire [3:0] vdp_col,
	output wire vdp_ce_pix,
	output wire vdp_hor_active,
	output wire vdp_vert_active,

	output wire [15:0] audio,  // two's complement

	// SRAM
	output wire [20:0] MA,
	inout wire [15:0] MD,
	output wire [1:0] MWR_N
);

// ------------------------------------------------------------------ clock enable

reg [1:0] div = 2'd0;
reg ce_10m7 = 1'b0;
always @(posedge clk) begin
	div <= div + 2'd1;
	ce_10m7 <= div == 2'd0;
end

// ------------------------------------------------------------------ loads

wire ioctl_isROMA = file_active && file_slot == 8'd0;
wire ioctl_isROMB = file_active && file_slot == 8'd1;
wire ioctl_isBIOS = file_active && file_slot == 8'd2;
wire ioctl_download = ioctl_isROMA || ioctl_isROMB || ioctl_isBIOS;

reg [1:0] rom_enabled = 2'b00;
reg fw_rom_en = 1'b1;
reg bios_d = 1'b0;
always @(posedge clk) begin
	bios_d <= ioctl_isBIOS;
	if (ioctl_isROMA)
		rom_enabled[0] <= 1'b1;
	if (ioctl_isROMB)
		rom_enabled[1] <= 1'b1;
	if (eject)
		rom_enabled <= 2'b00;
	// a BIOS file: page 2 of slot 0 only with a file over 32 KB
	if (ioctl_isBIOS && !bios_d)
		fw_rom_en <= 1'b0;
	if (ioctl_isBIOS && file_wr && file_addr[15])
		fw_rom_en <= 1'b1;
end

reg [7:0] mappers_d = 8'd0;
reg mapper_reset = 1'b0;
always @(posedge clk) begin
	mappers_d <= { mapper_b, mapper_a };
	mapper_reset <= mappers_d != { mapper_b, mapper_a };
end

wire msx_reset = reset || rom_active || ioctl_download || mapper_reset || eject;

// ------------------------------------------------------------------ input

wire [10:0] ps2_key;
msx_ps2_key ps2_key_conv (
	.clk(clk),
	.reset(reset),
	.scancode(kb_scancode),
	.scancode_upd(kb_scancode_upd),
	.ps2_key(ps2_key)
);

// the joysticks of MiSTer: 0 right, 1 left, 2 down, 3 up, 4 A, 5 B
wire [5:0] joy_a = { joy_l[7], joy_l[6], joy_l[1], joy_l[2], joy_l[3], joy_l[4] };
wire [5:0] joy_b = { joy_r[7], joy_r[6], joy_r[1], joy_r[2], joy_r[3], joy_r[4] };

// ------------------------------------------------------------------ the machine

wire [21:0] mem_addr;
wire mem_we;
wire [7:0] mem_din, mem_dout;

msx1 msx1 (
	.clk(clk),
	.ce_10m7(ce_10m7),
	.reset(msx_reset),
	.border(1'b1),
	.R(), .G(), .B(),
	.hsync_n(), .vsync_n(), .hblank(), .vblank(),
	.vdp_col(vdp_col),
	.vdp_ce_pix(vdp_ce_pix),
	.vdp_hor_active(vdp_hor_active),
	.vdp_vert_active(vdp_vert_active),
	.vdp_pal(pal),
	.audio(audio),
	.ps2_key(ps2_key),
	.joy0(joy_swap ? joy_b : joy_a),
	.joy1(joy_swap ? joy_a : joy_b),
	.ioctl_download(ioctl_download),
	.ioctl_index(8'd0),
	.ioctl_wr(file_wr),
	.ioctl_addr(file_addr[24:0]),
	.ioctl_dout(file_data),
	.ioctl_isROMA(ioctl_isROMA),
	.ioctl_isROMB(ioctl_isROMB),
	.ioctl_isBIOS(ioctl_isBIOS),
	.ioctl_isFWBIOS(1'b0),
	.ioctl_wait(),
	.rom_enabled(rom_enabled),
	.cas_motor(),
	.cas_audio_in(1'b0),
	.slot_A(mapper_a),
	.slot_B(mapper_b),
	.mapper_info(),
	.mem_addr(mem_addr),
	.mem_we(mem_we),
	.mem_din(mem_din),
	.mem_dout(mem_dout),
	.fw_rom_en(fw_rom_en),
	// the disk drive: Ф2 (img_sdc)
	.img_mounted(1'b0),
	.img_size(32'd0),
	.img_wp(1'b1),
	.sd_lba(),
	.sd_rd(),
	.sd_wr(),
	.sd_ack(1'b0),
	.sd_buff_addr(9'd0),
	.sd_buff_dout(8'd0),
	.sd_buff_din(),
	.sd_buff_wr(1'b0),
	.sd_din_strobe(1'b0)
);

// ------------------------------------------------------------------ SRAM

msx_sram sram (
	.clk(clk),
	.addr(rom_active ? rom_addr[21:0] : mem_addr),
	.we(rom_active ? rom_wr : mem_we),
	.din(rom_active ? rom_data : mem_din),
	.dout(mem_dout),
	.MA(MA),
	.MD(MD),
	.MWR_N(MWR_N)
);

endmodule
