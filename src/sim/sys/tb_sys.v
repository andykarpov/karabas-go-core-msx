`timescale 1ns / 1ps
`default_nettype wire

// msx_system and msx_video with a model of the SRAM (two lanes of 2M x 8, /OE low, written at the
// middle of /WE), driven by sim_sys.cpp: the loaders of the mcu, the switches, the keyboard.
module tb_sys (
	input wire clk,
	input wire clk_vga,
	input wire reset,
	input wire rom_active,
	input wire [31:0] rom_addr,
	input wire [7:0] rom_data,
	input wire rom_wr,
	input wire file_reset,
	input wire file_active,
	input wire [7:0] file_slot,
	input wire [31:0] file_addr,
	input wire [7:0] file_data,
	input wire file_wr,
	input wire [3:0] mapper_a,
	input wire [3:0] mapper_b,
	input wire pal,
	input wire [7:0] kb_scancode,
	input wire kb_scancode_upd,
	input wire [12:0] joy_l,
	input wire fdd,
	input wire tape_rewind,
	input wire [21:0] dbg_sram_addr,   // a byte of the SRAM model for sim_sys (the check of a load)
	output wire [7:0] dbg_sram_q,
	output wire dbg_cas_out,
	output wire dbg_cas_motor,
	input wire fdd_rom_en,
	input wire ram_mapper,
	input wire opll,
	input wire nextor,
	input wire [7:0] img_mounted,
	input wire [63:0] img_size,
	input wire img_data_wr,
	input wire [8:0] img_data_addr,
	input wire [7:0] img_data,
	input wire img_result_wr,
	input wire [7:0] img_result,
	input wire [15:0] img_sum,
	output wire img_q_wr,
	output wire [23:0] img_q_di,
	input wire img_q_ack,
	output wire fdd_active,
	output wire fdd_filling,
	output wire [10:0] fdd_filled,
	output wire [23:0] rgb,
	output wire hs,
	output wire vs,
	output wire de,
	output wire [15:0] audio,
	// the CPU bus for a trace
	output wire [15:0] cpu_a,
	output wire cpu_m1_n,
	output wire [3:0] dbg_border,
	output wire [7:0] dbg_y,
	output wire [10:0] dbg_ps2_key,
	output wire [7:0] dbg_kb,
	output wire [3:0] dbg_kb_row
);

wire [20:0] MA;
wire [15:0] MD;
wire [1:0] MWR_N;
wire [3:0] vdp_col;
wire vdp_ce_pix, vdp_hor_active, vdp_vert_active;

msx_system #(.TAPE_SILENT(100), .TAPE_SYNC(32)) sys (
	.clk(clk), .reset(reset),
	.rom_active(rom_active), .rom_addr(rom_addr), .rom_data(rom_data), .rom_wr(rom_wr),
	.file_reset(file_reset), .file_active(file_active), .file_slot(file_slot), .file_addr(file_addr), .file_data(file_data),
	.file_wr(file_wr),
	.mapper_a(mapper_a), .mapper_b(mapper_b), .pal(pal), .joy_swap(1'b0), .tape_rewind(tape_rewind), .tape_line(1'b0), .tape_in(1'b0), .tape_out(), .eject(1'b0), .fdd(fdd), .fdd_rom_en(fdd_rom_en), .ram_mapper(ram_mapper), .opll(opll), .nextor(nextor),
	.img_mounted(img_mounted), .img_size(img_size), .img_data_wr(img_data_wr), .img_data_addr(img_data_addr),
	.img_data(img_data), .img_result_wr(img_result_wr), .img_result(img_result), .img_sum(img_sum),
	.img_q_wr(img_q_wr), .img_q_di(img_q_di), .img_q_ack(img_q_ack), .fdd_active(fdd_active), .fdd_filling(fdd_filling), .fdd_filled(fdd_filled),
	.kb_scancode(kb_scancode), .kb_scancode_upd(kb_scancode_upd), .joy_l(joy_l), .joy_r(13'd0),
	.vdp_col(vdp_col), .vdp_ce_pix(vdp_ce_pix), .vdp_hor_active(vdp_hor_active),
	.vdp_vert_active(vdp_vert_active),
	.audio(audio),
	.MA(MA), .MD(MD), .MWR_N(MWR_N)
);

msx_video video (
	.clk(clk), .ce_pix(vdp_ce_pix), .hor_active(vdp_hor_active), .vert_active(vdp_vert_active),
	.col(vdp_col),
	.clk_vga(clk_vga), .rgb(rgb), .hs(hs), .vs(vs), .de(de)
);

assign cpu_a = sys.msx1.a;
assign cpu_m1_n = sys.msx1.m1_n;
assign dbg_border = video.border;
assign dbg_y = video.y;
assign dbg_ps2_key = sys.ps2_key;
assign dbg_kb = sys.msx1.d_from_kb;
assign dbg_kb_row = sys.msx1.ppi_out_c[3:0];

// the SRAM
reg [7:0] lo [0:(1<<21)-1];
reg [7:0] hi [0:(1<<21)-1];
integer i;
initial for (i = 0; i < (1<<21); i = i + 1) begin lo[i] = 8'hFF; hi[i] = 8'hFF; end
assign MD = (MWR_N == 2'b11) ? { hi[MA], lo[MA] } : 16'bz;
assign dbg_sram_q = dbg_sram_addr[0] ? hi[dbg_sram_addr[21:1]] : lo[dbg_sram_addr[21:1]];
assign dbg_cas_out = sys.cas_audio;
assign dbg_cas_motor = sys.cas_motor;
// written at the clk edge in the middle of the /WE pulse (msx_sram: from a falling edge to the next)
always @(posedge clk) begin
	if (!MWR_N[0]) lo[MA] <= MD[7:0];
	if (!MWR_N[1]) hi[MA] <= MD[15:8];
end

endmodule
