module tape (
	clk,
	ce_5m3,
	play,
	rewind,
	ram_a,
	ram_di,
	ram_rd,
	buff_mem_ready,
	cas_out
);
	input clk;
	input ce_5m3;
	input play;
	input rewind;
	output reg [26:0] ram_a;
	input [7:0] ram_di;
	output reg ram_rd;
	input buff_mem_ready;
	output wire cas_out;
	reg [31:0] state = 32'd0;
	wire [63:0] cas_sig = 64'h1fa6debacc137d74;
	wire [63:0] sig_pos = cas_sig >> (8'd56 - (ram_a[2:0] << 3));
	reg output_bit;
	reg output_on = 0;
	assign cas_out = output_bit & output_on;
	reg sig_ok;
	always @(posedge clk) begin : sv2v_autoblock_1
		reg sig_temp_ok;
		if (buff_mem_ready && ~ram_rd) begin
			if (ram_a[2:0] == 0) begin
				sig_temp_ok <= sig_pos[7:0] == ram_di;
				sig_ok <= 0;
			end
			else begin
				sig_ok <= 0;
				if (~(sig_pos[7:0] == ram_di))
					sig_temp_ok <= 0;
				else if (ram_a[2:0] == 3'h7)
					sig_ok <= sig_temp_ok & (sig_pos[7:0] == ram_di);
			end
		end
	end
	reg header;
	reg [10:0] counter;
	reg [3:0] byte_pos = 0;
	reg ce_baud;
	always @(posedge clk) begin
		if (buff_mem_ready)
			ram_rd <= 0;
		case (state)
			32'd0:
				;
			32'd1:
				if (buff_mem_ready && ~ram_rd) begin
					ram_a <= 0;
					output_on <= 0;
					state <= 32'd2;
					ram_rd <= 1;
				end
			32'd2:
				if (sig_ok) begin
					state <= 32'd3;
					counter <= 1000;
				end
				else if (buff_mem_ready && ~ram_rd) begin
					ram_a <= ram_a + 1'd1;
					ram_rd <= 1;
				end
			32'd3:
				if (ce_baud) begin
					counter <= counter - 1'b1;
					if (counter == 0) begin
						state <= 32'd4;
						counter <= 1454;
					end
				end
			32'd4: begin
				if (counter == 0) begin
					state <= 32'd5;
					header <= 0;
				end
				else
					header <= 1;
				if (byte_pos == 0) begin
					output_on <= 1;
					counter <= counter - 1'b1;
				end
			end
			32'd5:
				if (sig_ok) begin
					state <= 32'd4;
					counter <= 1454;
					if (buff_mem_ready && ~ram_rd) begin
						ram_a <= ram_a + 1'd1;
						ram_rd <= 1;
					end
				end
				else if (byte_pos == 0) begin
					if (buff_mem_ready && ~ram_rd) begin
						ram_a <= ram_a + 1'd1;
						ram_rd <= 1;
					end
				end
		endcase
		if (rewind)
			state <= 32'd1;
	end
	reg [7:0] send_byte;
	reg [1:0] cnt = 2'h0;
	reg send_bit;
	always @(posedge clk) begin : sv2v_autoblock_2
		reg [10:0] byte_out;
		if (byte_pos == 0) begin
			byte_out = (header ? 11'b11111111111 : {2'b11, ram_di, 1'b0});
			byte_pos = 4'd11;
		end
		if (cnt == 0) begin
			send_bit = byte_out[0];
			if (ce_baud) begin
				byte_out = {1'b0, byte_out[10:1]};
				byte_pos = byte_pos - 1'b1;
			end
		end
	end
	always @(posedge clk) begin : sv2v_autoblock_3
		reg bit_out;
		if (ce_baud) begin
			if (cnt == 2'h0) begin
				output_bit = 1;
				bit_out = send_bit;
			end
			else
				output_bit = (bit_out & ~cnt[0]) | (~bit_out & ~cnt[1]);
		end
	end
	always @(posedge clk) begin : sv2v_autoblock_4
		reg [10:0] baud_div;
		ce_baud = 0;
		if (ce_5m3 && play) begin
			if (baud_div == 11'h000) begin
				ce_baud = 1;
				baud_div = 11'd559;
				cnt = cnt + 1'b1;
			end
			else
				baud_div = baud_div - 1'b1;
		end
	end
endmodule
