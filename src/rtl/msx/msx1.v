module msx1
(
	input         clk,
	input         ce_10m7,
	input         reset,
	input         border,
	output  [7:0] R,
	output  [7:0] G,
	output  [7:0] B,
	output        hsync_n,
	output        vsync_n,
	output        hblank,
	output        vblank,
	// karabas: for the frame buffer (msx_video): the colour index of the pixel, its enable
	// (5.37 MHz) and the active area of the VDP
	output  [3:0] vdp_col,
	output        vdp_ce_pix,
	output        vdp_hor_active,
	output        vdp_vert_active,
	input         vdp_pal,
	output [15:0] audio,
	input  [10:0] ps2_key,
	input   [5:0] joy0,
	input   [5:0] joy1,
	input         ioctl_download,
	input   [7:0] ioctl_index,
	input         ioctl_wr,
	input  [24:0] ioctl_addr,
	input   [7:0] ioctl_dout,
	input         ioctl_isROMA,
	input         ioctl_isROMB,
	input         ioctl_isBIOS,
	input         ioctl_isFWBIOS,
	output        ioctl_wait,
	input   [1:0] rom_enabled,
	output        cas_motor,
	output        cas_out,      // karabas: the cassette write data (PPI port C bit 5) for TAPE_OUT
	input         cas_audio_in,
	input   [3:0] slot_A,
	input   [3:0] slot_B,
	input         fdd_rom_en,   // karabas: the disk ROM of the VY-0010 on (0 for C-BIOS)
	output  [2:0] mapper_info,
	// karabas: the BIOS, the firmware ROM, the RAM of slot 3 and the cartridges are in the SRAM
	// of the board (msx_sram), not in the block RAM and SDRAM of MiSTer; see the map at slots
	output [21:0] mem_addr,
	output        mem_we,
	output  [7:0] mem_din,
	input   [7:0] mem_dout,
	input         fw_rom_en,
	input         ram_mapper_en, // karabas: the RAM of slot 3 is 512 KB with a memory mapper (ram_mapper.v)
	input         opll_en,       // karabas: the OPLL (MSX-MUSIC, jt2413) at the ports 7C-7D
	// karabas: slot 1 is the SD interface of MSX1FPGA for Nextor (nextor_sd.v) instead of cartridge A
	// and the disk drive; its ROM (fdd_rom_en = 0: FF) and the hard disk image of img_sdc
	input         nextor_en,
	input         ioctl_isNEXTOR,
	input         hd_mounted,
	input  [31:0] hd_size,
	output        hd_rd,
	output        hd_wr,
	output [31:0] hd_lba,
	input         hd_busy,
	input         hd_done,
	input         hd_byte_in_strobe,
	input   [8:0] hd_byte_addr,
	input   [7:0] hd_byte_in_data,
	output  [7:0] hd_byte_out_data,
   
	input         img_mounted,
	input  [31:0] img_size,
	input         img_wp,
	output [31:0] sd_lba,
	output        sd_rd,
	output        sd_wr,
	input         sd_ack,
	input   [8:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din,
	input         sd_buff_wr,
	input         sd_din_strobe
);

// karabas: the wires used before their declaration below (Quartus takes it, XST does not)
wire u1_2_q;
wire vdp_int_n;
wire vdp_n, psg_n, ppi_n, cen_n;
wire [7:0] d_from_kb;
wire [7:0] d_from_psg, psg_ioa, psg_iob;
wire [7:0] d_from_slots;
wire [15:0] sound_slots; 
wire [9:0] ay_ch_mix;
wire [7:0] d_from_vdp;
wire [7:0] d_from_8255;
wire [7:0] ppi_out_a, ppi_out_c;
wire CS1_n, CS01_n, CS12_n, CS2_n;
wire [3:0] SLTSL_n;
wire [3:0] slots_sltsl_n = { SLTSL_n[3:2], SLTSL_n[1] | nextor_en, SLTSL_n[0] }; // karabas: slot 1 off for Nextor
// karabas: the memory of the slots goes to the SRAM (see the map below)
wire [24:0] sdram_addr;
wire        sdram_rd;
wire        ram_we;

//  -----------------------------------------------------------------------------
//  -- Audio MIX
//  -----------------------------------------------------------------------------
wire  [9:0] audioPSG = ay_ch_mix + {keybeep,5'b00000} + {(cas_audio_in & ~cas_motor),4'b0000};                                        
wire [15:0] fm       = {2'b0, audioPSG, 4'b0000};
// karabas: the OPLL is a third term (a note of jt2413 is +-1.4K, a tone of the PSG 0..4K here): one
// bit more, the same clipping at +-2^14 (the case of the array literal of SystemVerilog was on 3
// bits, element 0 of '{...} is the last one)
wire signed [15:0] opll_snd;
wire [17:0] audio_mix = {{2{sound_slots[15]}}, sound_slots} + {{2{fm[15]}}, fm} +
                        (opll_en ? {{2{opll_snd[15]}}, opll_snd} : 18'd0);
reg [15:0] compr;
always @* begin
	case (audio_mix[17:14])
		4'b0000: compr = {1'b0, audio_mix[13:0], 1'b0};
		4'b1111: compr = {1'b1, audio_mix[13:0], 1'b0};
		default: compr = audio_mix[17] ? 16'h8000 : 16'h7FFF;
	endcase
end
assign audio = compr;

//  -----------------------------------------------------------------------------
//  -- Clock generation
//  -----------------------------------------------------------------------------
wire clk_en_3m58_p, clk_en_3m58_n;
cv_clock clock
(
	.clk_i(clk),
	.clk_en_10m7_i(ce_10m7),
	.reset_n_i(~reset),
	.clk_en_3m58_p_o(clk_en_3m58_p),
	.clk_en_3m58_n_o(clk_en_3m58_n)
);

//  -----------------------------------------------------------------------------
//  -- T80 CPU
//  -----------------------------------------------------------------------------
wire [15:0] a;
wire [7:0] d_to_cpu, d_from_cpu;
wire mreq_n, wr_n, m1_n, iorq_n, rd_n, rfrsh_n, wait_n; 
t80pa #(.Mode(0)) T80
(
	.RESET_n(~reset),
	.CLK(clk),
	.CEN_p(clk_en_3m58_p),
	.CEN_n(clk_en_3m58_n),
	.WAIT_n(wait_n),
	.INT_n(vdp_int_n),
	.NMI_n(1),
	.BUSRQ_n(1),
	.M1_n(m1_n),
	.MREQ_n(mreq_n),
	.IORQ_n(iorq_n),
	.RD_n(rd_n),
	.WR_n(wr_n),
	.RFSH_n(rfrsh_n),
	.HALT_n(), // karabas: an output of t80pa, upstream tied it to 1
	.BUSAK_n(),
	.A(a),
	.DI(d_to_cpu),
	.DO(d_from_cpu)
);

//  -----------------------------------------------------------------------------
//  -- WAIT
//  -----------------------------------------------------------------------------
wire exwait_n = 1;
reg wait_n2;
ls74 u1_1
(
   .clr(exwait_n),
   .pre(u1_2_q),
   .clk(clk), // karabas: clk_en_3m58_p was the clock, see ls74.v
   .ce(clk_en_3m58_p),
   .d(m1_n),
   .q(wait_n)
);

ls74 u1_2
(
   .clr(1),
   .pre(exwait_n),
   .clk(clk), // karabas: clk_en_3m58_p was the clock, see ls74.v
   .ce(clk_en_3m58_p),
   .d(wait_n),
   .q(u1_2_q)
);
//  -----------------------------------------------------------------------------
//  -- ROM
//  -----------------------------------------------------------------------------
// karabas: the BIOS (32 KB) and the firmware ROM (16 KB) are in the SRAM, see mem_addr below
// fw_rom_en: the ROM of slot 0 page 2 is there (the logo ROM of C-BIOS, or the last 16 KB of a
// BIOS file of 48 KB); without it the page reads FF, as a BIOS of 32 KB has it
wire [7:0] rom_q = mem_dout;
wire [7:0] fw_rom_q = fw_rom_en ? mem_dout : 8'hFF;

//  -----------------------------------------------------------------------------
//  -- Video RAM 16k
//  -----------------------------------------------------------------------------
wire [13:0] vram_a;
wire [7:0]  vram_do;
wire [7:0]  vram_di;
wire        vram_we;
spram #(.addr_width(14),.mem_name("VRAM")) vram
(
	.clock(clk),
	.address(vram_a),
	.wren(vram_we),
	.data(vram_do),
	.q(vram_di)
);

//  -----------------------------------------------------------------------------
//  -- TMS9928A Video Display Processor
//  -----------------------------------------------------------------------------
vdp18_core #(.compat_rgb_g(0)) vdp18
(
	.clk_i(clk),
	.clk_en_10m7_i(ce_10m7),
	.reset_n_i(~reset),
	.csr_n_i(vdp_n | rd_n),
	.csw_n_i(vdp_n | wr_n),
	.mode_i(a[0]),
	.cd_i(d_from_cpu),
	.cd_o(d_from_vdp),
	.int_n_o(vdp_int_n),
	.vram_we_o(vram_we),
	.vram_a_o(vram_a),
	.vram_d_o(vram_do),
	.vram_d_i(vram_di),
	.border_i(border),
	.rgb_r_o(R),
	.rgb_g_o(G),
	.rgb_b_o(B),
	.hsync_n_o(hsync_n),
	.vsync_n_o(vsync_n),
	.hblank_o(hblank),
	.vblank_o(vblank),
	.is_pal_i(vdp_pal),
	.col_o(vdp_col),                  // karabas: see the ports
	.clk_en_5m37_o(vdp_ce_pix),
	.hor_active_o(vdp_hor_active),
	.vert_active_o(vdp_vert_active)
);

//  -----------------------------------------------------------------------------
//  -- IO Decoder
//  -----------------------------------------------------------------------------
io_decoder io_decoder
(
	.addr(a),
	.iorq_n(iorq_n),
	.m1_n(m1_n),
	.vdp_n(vdp_n),
	.psg_n(psg_n),
	.ppi_n(ppi_n),
	.cen_n(cen_n)
);

//  -----------------------------------------------------------------------------
//  -- 82C55 PPI
//  -----------------------------------------------------------------------------
wire keybeep = ppi_out_c[7];
assign cas_motor =  ppi_out_c[4];
assign cas_out = ppi_out_c[5];  // karabas: see the port
jt8255 PPI
(
	.rst(reset),
	.clk(clk),
	.addr(a[1:0]),
	.din(d_from_cpu),
	.dout(d_from_8255),
	.rdn(rd_n),
	.wrn(wr_n),
	.csn(ppi_n),
	
	.porta_din(8'h0),
	.portb_din(d_from_kb),
	.portc_din(8'h0),

	.porta_dout(ppi_out_a),
	.portb_dout(),
   .portc_dout(ppi_out_c)
 );

//  -----------------------------------------------------------------------------
//  -- Memory mapper
//  -----------------------------------------------------------------------------
memory_mapper memory_mapper
(
	.clk(clk), // karabas
	.reset(reset),
	.addr(a),
	.ppi_n(ppi_n),
	.RAM_CS(ppi_out_a),
	.mreq_n(mreq_n),
	.rfrsh_n(rfrsh_n),
	.rd_n(rd_n),
	.SLTSL_n(SLTSL_n),
	.CS1_n(CS1_n),
	.CS01_n(CS01_n),
	.CS12_n(CS12_n),
	.CS2_n(CS2_n)
); 

//  -----------------------------------------------------------------------------
//  -- karabas: the memory mapper of the RAM of slot 3 (ports FC-FF)
//  -----------------------------------------------------------------------------
wire [4:0] ram_segment;
wire       ram_mapper_n;
wire [7:0] d_from_ram_mapper;
ram_mapper ram_mapper
(
	.clk(clk),
	.reset(reset),
	.en(ram_mapper_en),
	.io_addr(a[7:0]),
	.iorq_n(iorq_n),
	.m1_n(m1_n),
	.wr_n(wr_n),
	.din(d_from_cpu),
	.page(a[15:14]),
	.segment(ram_segment),
	.sel_n(ram_mapper_n),
	.dout(d_from_ram_mapper)
);

//  -----------------------------------------------------------------------------
//  -- karabas: Nextor in slot 1 (the SD interface of MSX1FPGA on a hard disk image)
//  -----------------------------------------------------------------------------
wire       nextor_sel, nextor_mem, nextor_we;
wire [2:0] nextor_bank;
wire [7:0] nextor_q;
nextor_sd nextor
(
	.clk(clk),
	.reset(reset),
	.rom_en(fdd_rom_en),
	.sltsl_n(SLTSL_n[1] | ~nextor_en),
	.addr(a),
	.din(d_from_cpu),
	.rd_n(rd_n),
	.wr_n(wr_n),
	.sel(nextor_sel),
	.dout(nextor_q),
	.mem_sel(nextor_mem),
	.mem_bank(nextor_bank),
	.mem_we(nextor_we),
	.mem_dout(mem_dout),
	.img_mounted(hd_mounted),
	.img_size(hd_size),
	.hd_rd(hd_rd),
	.hd_wr(hd_wr),
	.hd_lba(hd_lba),
	.hd_busy(hd_busy),
	.hd_done(hd_done),
	.hd_byte_in_strobe(hd_byte_in_strobe),
	.hd_byte_addr(hd_byte_addr),
	.hd_byte_in_data(hd_byte_in_data),
	.hd_byte_out_data(hd_byte_out_data)
);

//  -----------------------------------------------------------------------------
//  -- karabas: the OPLL (YM2413, MSX-MUSIC) at the ports 7C (register) and 7D (data), write only
//  -----------------------------------------------------------------------------
wire opll_cs_n = ~(opll_en & ~iorq_n & m1_n & a[7:1] == 7'b0111110);
jt2413 opll
(
	.rst(reset),
	.clk(clk),
	.cen(clk_en_3m58_p),
	.din(d_from_cpu),
	.addr(a[0]),
	.cs_n(opll_cs_n),
	.wr_n(wr_n),
	.snd(opll_snd),
	.sample()
);

// the internal MSX-MUSIC is found by its ROM: "APRLOPLL" at 4018 of a slot. With the OPLL on and no
// cartridge B, page 1 of slot 2 has the header of the MSX-MUSIC ROM of C-BIOS (cbios_music.rom:
// "AB", no init, the name); zeros elsewhere
wire       opll_rom = opll_en & ~rom_enabled[1] & ~SLTSL_n[2] & a[15:14] == 2'b01;
reg  [7:0] opll_rom_q;
always @* begin
	case (a[13:0])
		14'h0000: opll_rom_q = "A";
		14'h0001: opll_rom_q = "B";
		14'h0018: opll_rom_q = "A";
		14'h0019: opll_rom_q = "P";
		14'h001A: opll_rom_q = "R";
		14'h001B: opll_rom_q = "L";
		14'h001C: opll_rom_q = "O";
		14'h001D: opll_rom_q = "P";
		14'h001E: opll_rom_q = "L";
		14'h001F: opll_rom_q = "L";
		default:  opll_rom_q = 8'h00;
	endcase
end

//  -----------------------------------------------------------------------------
//  -- CPU data multiplex
//  ----------------------------------------------------------------------------- 
assign d_to_cpu = ~(CS01_n | SLTSL_n[0]) ? rom_q :
                  ~(CS2_n  | SLTSL_n[0]) ? fw_rom_q :
						nextor_sel             ? nextor_q : // karabas
						~(SLTSL_n[1])          ? d_from_slots:
						opll_rom               ? opll_rom_q : // karabas
						~(SLTSL_n[2])          ? d_from_slots:
						~(SLTSL_n[3])          ? d_from_slots:                 
						~(vdp_n | rd_n)        ? d_from_vdp :
						~(psg_n | rd_n)        ? d_from_psg :
						~(ppi_n | rd_n)        ? d_from_8255 : 
						~(ram_mapper_n | rd_n) ? d_from_ram_mapper : // karabas
						                         8'hFF;

//  -----------------------------------------------------------------------------
//  -- Keyboard decoder
//  -----------------------------------------------------------------------------
keyboard msx_key
(
	.reset_n_i(~reset),
	.clk_i(clk),
	.ps2_code_i(ps2_key),
	.kb_addr_i(ppi_out_c[3:0]),
	.kb_data_o(d_from_kb)
);

//  -----------------------------------------------------------------------------
//  -- Sound AY-3-8910
//  -----------------------------------------------------------------------------
wire [5:0] joy_a = psg_iob[4] ? 6'b111111 : {~joy0[5], ~joy0[4], ~joy0[0], ~joy0[1], ~joy0[2], ~joy0[3]};
wire [5:0] joy_b = psg_iob[5] ? 6'b111111 : {~joy1[5], ~joy1[4], ~joy1[0], ~joy1[1], ~joy1[2], ~joy1[3]};
wire [5:0] joyA = joy_a & {psg_iob[0], psg_iob[1], 4'b1111};
wire [5:0] joyB = joy_b & {psg_iob[2], psg_iob[3], 4'b1111};
assign psg_ioa = {cas_audio_in,1'b0, psg_iob[6] ? joyB : joyA};

wire u21_1_q;
ls74 u21_1
(
   .clr(!psg_n),
   .pre(1),
   .clk(clk), // karabas: clk_en_3m58_p was the clock, see ls74.v
   .ce(clk_en_3m58_p),
   .d(!psg_n),
   .q(u21_1_q)
);

wire u21_2_q;
ls74 u21_2
(
   .clr(!psg_n),
   .pre(1),
   .clk(clk), // karabas: clk_en_3m58_p was the clock, see ls74.v
   .ce(clk_en_3m58_p),
   .d(u21_1_q),
   .q(u21_2_q)
);

wire psg_e = !(!u21_2_q | clk_en_3m58_p) | psg_n;
wire psg_bc   = !(a[0] | psg_e);
wire psg_bdir = !(a[1] | psg_e);
jt49_bus PSG
(
	.rst_n(~reset),
	.clk(clk),
	.clk_en(clk_en_3m58_n),
	.bdir(psg_bdir),
	.bc1(psg_bc),
	.din(d_from_cpu),
	.sel(0),
	.dout(d_from_psg),
	.sound(ay_ch_mix),
	.A(),
	.B(),
	.C(),
	.IOA_in(psg_ioa),
	.IOA_out(),
	.IOB_in(8'hFF),
	.IOB_out(psg_iob)
);

//  -----------------------------------------------------------------------------
//  -- SLOTS
//  -----------------------------------------------------------------------------
slots slots
(
	.clk(clk),
	.clk_en(clk_en_3m58_p),
	.reset(reset),
	.addr(a),
	.wr_n(wr_n),
	.rd_n(rd_n),
	.CS1_n(CS1_n),    
	.CS2_n(CS2_n),
	.CS12_n(CS12_n),
	.SLTSL_n(slots_sltsl_n), // karabas
	.d_from_cpu(d_from_cpu),
	.d_to_cpu(d_from_slots),
	.sound(sound_slots),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_isROMA(ioctl_isROMA),
	.ioctl_isROMB(ioctl_isROMB),
	.ioctl_wait(ioctl_wait),
	.sdram_dout(mem_dout),
	.sdram_din(),
	.sdram_addr(sdram_addr),
	.sdram_we(),
	.sdram_rd(sdram_rd),
	.sdram_ready(1'b1),
	.sdram_size(2'b01),
	.ram_we(ram_we),
	.slot_A(slot_A),
	.slot_B(slot_B),
	.fdd_rom_en(fdd_rom_en),
	.mapper_info(mapper_info),
	.rom_enabled(rom_enabled),
	.img_mounted(img_mounted),
	.img_size(img_size),
	.img_wp(img_wp),
	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.sd_din_strobe(sd_din_strobe)
);

//  -----------------------------------------------------------------------------
//  -- karabas: the SRAM map (byte addresses)
//  -----------------------------------------------------------------------------
// 000000 BIOS 32 KB (slot 0, 0000-7FFF)      080000 RAM 512 KB of slot 3 (ram_mapper, segment n at
// 008000 firmware ROM 16 KB (slot 0, 8000-BFFF)   080000 + n * 16 KB; without the mapper 64 KB, segments 0-3)
// 020000 the Nextor ROM 128 KB (nextor_sd: bank n at 020000 + n * 16 KB, RAM in 7000-7AFF of bank 7)
// 100000 cartridge B, 200000 cartridge A, 1 MB each
// 300000 the disk image (msx_fdd_cache, 768 KB)   3C0000 free (the tape, Ф3)
// The cartridges are at the addresses of the MiSTer SDRAM, bit 22 = slot A; a ROM file over 1 MB
// is cut (the rest is not written). The SRAM is read all the time (msx_sram); a write is a level
// here, msx_sram writes once at its rising edge.
wire [21:0] cart_addr = {sdram_addr[22] ? 2'b10 : 2'b01, sdram_addr[19:0]};
wire        ioctl_cart = ioctl_isROMA | ioctl_isROMB;
// a BIOS file of up to 48 KB: 32 KB of BIOS and 16 KB of the ROM of slot 0 page 2, which follows
// it in the SRAM
wire        ioctl_mem = (ioctl_isBIOS & ioctl_addr < 25'hC000) | ioctl_isFWBIOS | (ioctl_cart & ioctl_addr[24:20] == 5'd0) |
                        (ioctl_isNEXTOR & ioctl_addr[24:17] == 8'd0);

assign mem_addr = ioctl_isBIOS            ? {6'h00, ioctl_addr[15:0]} :
                  ioctl_isFWBIOS          ? {8'h02, ioctl_addr[13:0]} :
                  ioctl_isNEXTOR          ? {5'b00001, ioctl_addr[16:0]} :
                  ioctl_isROMA            ? {2'b10, ioctl_addr[19:0]} :
                  ioctl_isROMB            ? {2'b01, ioctl_addr[19:0]} :
                  ~(CS01_n | SLTSL_n[0])  ? {7'h00, a[14:0]} :
                  ~(CS2_n  | SLTSL_n[0])  ? {8'h02, a[13:0]} :
                  ~SLTSL_n[3]             ? {3'b001, ram_segment, a[13:0]} :
                  nextor_mem              ? {5'b00001, nextor_bank, a[13:0]} :
                                            cart_addr;
assign mem_we  = ioctl_download ? ioctl_wr & ioctl_mem : ram_we | nextor_we;
assign mem_din = ioctl_download ? ioctl_dout : d_from_cpu;

endmodule
