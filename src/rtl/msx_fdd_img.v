`timescale 1ns / 1ps
`default_nettype wire

/*
 msx_fdd_img.v

 The sector interface of the MiSTer FDC (wd1793 with RWMODE 1: sd_rd / sd_wr / sd_lba, sd_ack,
 sd_buff_*) on img_sdc of the modules (the file mounter of the mcu, its index 0):

 - a request of the FDC (sd_rd or sd_wr, a level it drops when it sees sd_ack) goes to img_sdc
   as sdc_rd[0] / sdc_wr[0] with the sector, held until img_sdc takes it (sdc_busy with slot 0);
 - sd_ack is up from then until sdc_done: the FDC waits for its fall (it samples sd_ack at the
   CPU clock enable, the request lasts milliseconds);
 - a read: the bytes img_sdc passes on (sdc_byte_in_strobe, already checked against the sum of
   the mcu) are sd_buff_wr with sd_buff_addr / sd_buff_dout into the sector buffer of the FDC;
   a failed read gives 512 zero bytes (img_sdc), the FDC sees a sector of zeros;
 - a write: img_sdc copies the sector out of the buffer of the FDC: sd_buff_addr follows
   sdc_byte_addr, sd_buff_din (one clock of block RAM later) is sdc_byte_out_data.

 While the mcu serves the sector (5-15 ms, up to 3 x 200 ms with retries) the FDC shows BUSY
 without DRQ, as a real drive does while the disk turns to the sector (up to 200 ms at 300 rpm).
*/

module msx_fdd_img (
	input wire clk,
	input wire reset,

	// wd1793
	input wire sd_rd,
	input wire sd_wr,
	input wire [31:0] sd_lba,
	output reg sd_ack = 1'b0,
	output wire [8:0] sd_buff_addr,
	output wire [7:0] sd_buff_dout,
	output wire sd_buff_wr,
	input wire [7:0] sd_buff_din,

	// img_sdc, index 0
	output reg sdc_rd = 1'b0,
	output reg sdc_wr = 1'b0,
	output reg [31:0] sdc_sector = 32'd0,
	input wire sdc_busy,
	input wire sdc_done,
	input wire [2:0] sdc_slot,
	input wire sdc_byte_in_strobe,
	input wire [8:0] sdc_byte_addr,
	input wire [7:0] sdc_byte_in_data,
	output wire [7:0] sdc_byte_out_data
);

localparam S_IDLE = 2'd0, S_REQ = 2'd1, S_XFER = 2'd2;
reg [1:0] state = S_IDLE;

wire mine = sdc_slot == 3'd0;

// the byte of a read goes into the buffer of the FDC in the clock img_sdc gives it, with its address
assign sd_buff_addr = sdc_byte_addr;
assign sd_buff_dout = sdc_byte_in_data;
assign sd_buff_wr = state == S_XFER && sdc_byte_in_strobe && mine;
assign sdc_byte_out_data = sd_buff_din;

always @(posedge clk) begin
	if (reset) begin
		state <= S_IDLE;
		sdc_rd <= 1'b0;
		sdc_wr <= 1'b0;
		sd_ack <= 1'b0;
	end
	else
		case (state)
			S_IDLE:
				if (sd_rd || sd_wr) begin
					sdc_rd <= sd_rd;
					sdc_wr <= !sd_rd && sd_wr;
					sdc_sector <= sd_lba;
					state <= S_REQ;
				end
			S_REQ:
				if (sdc_busy && mine) begin
					sdc_rd <= 1'b0;
					sdc_wr <= 1'b0;
					sd_ack <= 1'b1;
					state <= S_XFER;
				end
			default: begin // S_XFER
				if (sdc_done && mine) begin
					sd_ack <= 1'b0;
					state <= S_IDLE;
				end
			end
		endcase
end

endmodule
