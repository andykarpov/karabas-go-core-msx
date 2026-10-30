`timescale 1ns / 1ps
`default_nettype wire

/*
 msx_ps2_key.v

 The PS/2 set 2 scancodes of the mcu (KB_SCANCODE / KB_SCANCODE_UPD of kg_mcu: the firmware sends
 them for every key of the USB keyboard, typematic repeat included) as the ps2_key of MiSTer,
 which keyboard.vhd of the MSX1 core takes unchanged:
   ps2_key[10]  toggles with each key event
   ps2_key[9]   1 = pressed, 0 = released (an F0 before the code)
   ps2_key[8]   extended (an E0 before the code)
   ps2_key[7:0] the code
 E0 and F0 are prefixes of the next code; E1 (Pause) and its bytes are taken as codes that the
 matrix of the MSX does not have. A repeated make code of a held key is an event too, as MiSTer
 gives it; the matrix sets the same bit again.
*/

module msx_ps2_key (
	input wire clk,
	input wire reset,
	input wire [7:0] scancode,
	input wire scancode_upd,    // toggles with each byte
	output reg [10:0] ps2_key = 11'd0
);

reg upd_d = 1'b0;
reg ext = 1'b0, rel = 1'b0;

always @(posedge clk) begin
	upd_d <= scancode_upd;
	if (reset) begin
		ext <= 1'b0;
		rel <= 1'b0;
	end
	else if (scancode_upd != upd_d) begin
		if (scancode == 8'hE0)
			ext <= 1'b1;
		else if (scancode == 8'hF0)
			rel <= 1'b1;
		else begin
			ps2_key <= { ~ps2_key[10], ~rel, ext, scancode };
			ext <= 1'b0;
			rel <= 1'b0;
		end
	end
end

endmodule
