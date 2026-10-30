`timescale 1ns / 1ps
`default_nettype wire

/*
 msx_video.v

 The picture of the TMS9918A (vdp18) through a frame buffer to 640 x 480 at 60 Hz, the standard
 VESA timing on 25.0 MHz (800 x 525; the monitors of the user take only standard timing, see
 docs/PLAN.md). The 15 kHz timing of the VDP (NTSC 60 Hz or PAL 50 Hz) never reaches the output:
 a PAL frame is shown once or twice, as it comes.

 Write side (clk, the machine): at each pixel enable of the VDP (ce_pix, 5.37 MHz) the colour index
 col of an active pixel (hor_active and vert_active, the signals vdp18 selects col_o with) goes to
 x, y of the buffer; x counts from the first active pixel of a line, y from the first active line.
 The text mode has 240 active pixels: the lines shorter than 256 pixels are moved 8 pixels to the
 right, so the 40 columns sit in the middle; the read side shows the border colour at the 8
 pixels on each side (they are not written in the text mode).
 The border colour (register 7 of the VDP) is col at the first pixel after the active part of an
 active line, where vdp18 gives reg_col0.

 The buffer: 256 x 192 x 4 bits in two kg_sdpram (lines 0-127: 32K x 4, lines 128-191: 16K x 4,
 12 RAMB16 together, a buffer of 64K x 4 would take 16).

 Read side (clk_vga, 25.0 MHz): a pixel of the VDP is 2 x 2 pixels of the output, the picture
 512 x 384 in the middle (64 pixels of border at the left and right, 48 lines at the top and the
 bottom). The border colour and the text mode flag cross through kg_sync (five bits, a change is seen within two lines,
 half old for a clock at most). hs / vs are high active here (kg_osd_overlay takes them so); the
 top inverts them for the negative syncs of 640 x 480. rgb, hs, vs and de come out together, three
 clocks after the counters.
*/

module msx_video (
	input wire clk,
	input wire ce_pix,
	input wire hor_active,
	input wire vert_active,
	input wire [3:0] col,

	input wire clk_vga,
	output reg [23:0] rgb = 24'd0,
	output reg hs = 1'b0,
	output reg vs = 1'b0,
	output reg de = 1'b0
);

// ------------------------------------------------------------------ write side (clk)

reg hor_d = 1'b0, vert_d = 1'b0;
reg [8:0] x = 9'd0;
reg [7:0] y = 8'd0;
reg [3:0] border = 4'd0;
reg text = 1'b0;             // the line before was shorter than 256 pixels (the text mode)
reg wr = 1'b0;
reg [15:0] wr_addr = 16'd0;  // {y, x}
reg [3:0] wr_col = 4'd0;

wire act = hor_active && vert_active;

always @(posedge clk) begin
	wr <= 1'b0;
	if (ce_pix) begin
		hor_d <= hor_active;
		vert_d <= vert_active;
		if (vert_active && !vert_d)
			y <= 8'd0;
		if (hor_active && !hor_d)
			x <= 9'd0;
		else if (hor_active)
			x <= x + 9'd1;
		if (!hor_active && hor_d) begin
			// the end of the active part of a line (hor_active comes in the blanked lines too, col is
			// 0 there)
			if (vert_active) begin
				border <= col;
				text <= x < 9'd255;
				y <= y + 8'd1;
			end
		end
		if (act) begin
			wr <= 1'b1;
			wr_col <= col;
			wr_addr <= { y, (hor_active && !hor_d) ? 8'd0 : x[7:0] + 8'd1 } + (text ? 16'd8 : 16'd0);
		end
	end
end

wire wr_ok = wr && wr_addr[15:8] < 8'd192;

wire [3:0] q0, q1;
kg_sdpram #(.DW(4), .AW(15)) fb0 (
	.clka(clk), .wea(wr_ok && !wr_addr[15]), .addra(wr_addr[14:0]), .dina(wr_col),
	.clkb(clk_vga), .enb(1'b1), .addrb(rd_addr[14:0]), .doutb(q0)
);
kg_sdpram #(.DW(4), .AW(14)) fb1 (
	.clka(clk), .wea(wr_ok && wr_addr[15]), .addra(wr_addr[13:0]), .dina(wr_col),
	.clkb(clk_vga), .enb(1'b1), .addrb(rd_addr[13:0]), .doutb(q1)
);

// ------------------------------------------------------------------ read side (clk_vga)

localparam H_ACTIVE = 640, H_FP = 16, H_SYNC = 96, H_TOTAL = 800;
localparam V_ACTIVE = 480, V_FP = 10, V_SYNC = 2, V_TOTAL = 525;
localparam PIC_X0 = 64, PIC_X1 = 64 + 512, PIC_Y0 = 48, PIC_Y1 = 48 + 384;

reg [9:0] hc = 10'd0, vc = 10'd0;
always @(posedge clk_vga) begin
	if (hc == H_TOTAL - 1) begin
		hc <= 10'd0;
		vc <= (vc == V_TOTAL - 1) ? 10'd0 : vc + 10'd1;
	end
	else
		hc <= hc + 10'd1;
end

wire [3:0] border_vga;
wire text_vga;
kg_sync #(.W(5)) border_sync (.clk(clk_vga), .d({text, border}), .q({text_vga, border_vga}));

// stage 1: the address of the buffer and what the pixel is
wire [9:0] px = hc - PIC_X0;
wire [9:0] py = vc - PIC_Y0;
wire [15:0] rd_addr = { py[8:1], px[8:1] };
reg s1_pic = 1'b0, s1_hi = 1'b0, s1_de = 1'b0, s1_hs = 1'b0, s1_vs = 1'b0;
always @(posedge clk_vga) begin
	// the 8 columns at each side of the 40 columns of the text mode are not written: border
	s1_pic <= hc >= PIC_X0 && hc < PIC_X1 && vc >= PIC_Y0 && vc < PIC_Y1 &&
		!(text_vga && (px[8:1] < 8'd8 || px[8:1] >= 8'd248));
	s1_hi <= rd_addr[15];
	s1_de <= hc < H_ACTIVE && vc < V_ACTIVE;
	s1_hs <= hc >= H_ACTIVE + H_FP && hc < H_ACTIVE + H_FP + H_SYNC;
	s1_vs <= vc >= V_ACTIVE + V_FP && vc < V_ACTIVE + V_FP + V_SYNC;
end

// stage 2: the colour index (the buffer word is there now)
reg [3:0] s2_col = 4'd0;
reg s2_de = 1'b0, s2_hs = 1'b0, s2_vs = 1'b0;
always @(posedge clk_vga) begin
	s2_col <= s1_pic ? (s1_hi ? q1 : q0) : border_vga;
	s2_de <= s1_de;
	s2_hs <= s1_hs;
	s2_vs <= s1_vs;
end

// stage 3: the palette of vdp18 (full_rgb_table_c of vdp18_col_pack-p.vhd)
function [23:0] palette;
	input [3:0] c;
	case (c)
		4'd0:  palette = 24'h000000; // transparent
		4'd1:  palette = 24'h000000; // black
		4'd2:  palette = {8'd33,  8'd200, 8'd66};
		4'd3:  palette = {8'd94,  8'd220, 8'd120};
		4'd4:  palette = {8'd84,  8'd85,  8'd237};
		4'd5:  palette = {8'd125, 8'd118, 8'd252};
		4'd6:  palette = {8'd212, 8'd82,  8'd77};
		4'd7:  palette = {8'd66,  8'd235, 8'd245};
		4'd8:  palette = {8'd252, 8'd85,  8'd84};
		4'd9:  palette = {8'd255, 8'd121, 8'd120};
		4'd10: palette = {8'd212, 8'd193, 8'd84};
		4'd11: palette = {8'd230, 8'd206, 8'd128};
		4'd12: palette = {8'd33,  8'd176, 8'd59};
		4'd13: palette = {8'd201, 8'd91,  8'd186};
		4'd14: palette = {8'd204, 8'd204, 8'd204};
		default: palette = 24'hFFFFFF;
	endcase
endfunction

always @(posedge clk_vga) begin
	rgb <= s2_de ? palette(s2_col) : 24'd0;
	de <= s2_de;
	hs <= s2_hs;
	vs <= s2_vs;
end

endmodule
