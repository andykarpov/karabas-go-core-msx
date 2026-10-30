`timescale 1ns / 1ps
`default_nettype wire

/*
 msx_sram.v

 The SRAM of the board (two byte lanes of 2M x 8, 10 ns, asynchronous) as one byte port of the
 machine: a byte address of 22 bits (MA = addr[21:1], the lane by addr[0]: MWR_N[0] / MD[7:0] for
 even bytes, as the NES core has it). /OE (MRD_N) is tied low by the top.

 Slots of two clocks (clk 42.857 MHz: one clock, 23.3 ns, is less than the address out, tAA and
 the data in; two are 46.7 ns, TS_SRAM_OUT / TS_SRAM_IN of the ucf bound the pads):
 - the first edge of a slot takes the address (and a pending write) into the address registers;
 - a read slot takes MD at the first edge of the next slot (two clocks after the address), dout
   is the byte of its lane one clock later;
 - a write slot pulls /WE low and drives MD from the falling edge of its first clock to the
   falling edge of its second clock, so the address is stable half a clock before and after /WE.
 The SRAM is read all the time at addr: dout follows a change of addr within six clocks, which
 is far less than the access of the Z80 (an M1 read takes the data two T-states, 24 clocks, after
 the address). The machine and the loaders hold addr while they read.

 we is a level or a pulse: the rising edge requests one write of din at addr (taken at that
 edge; both must hold until then). A write waits for the next slot, at most two clocks; the
 writers here write once in 10 clocks or less often (the loaders of the mcu, the Z80).
*/

module msx_sram (
	input wire clk,

	input wire [21:0] addr,
	input wire we,
	input wire [7:0] din,
	output reg [7:0] dout = 8'hFF,

	output reg [20:0] MA = 21'd0,
	inout wire [15:0] MD,
	output wire [1:0] MWR_N
);

reg phase = 1'b0;    // 0: the first clock of a slot
reg we_d = 1'b0;
reg wr_pend = 1'b0;
reg [21:0] wr_addr = 22'd0;
reg [7:0] wr_data = 8'd0;

reg s_we = 1'b0;     // the slot is a write
reg s_lane = 1'b0;   // addr[0] of the slot
reg s_read = 1'b0;   // the slot is a read
reg [7:0] s_data = 8'd0;  // the byte of a write slot
reg [15:0] md_q = 16'hFFFF;  // MD at the first edge of the next slot (an IOB register)
reg q_valid = 1'b0, q_lane = 1'b0;

always @(posedge clk) begin
	phase <= ~phase;
	we_d <= we;

	// a write request: taken at the rising edge of we
	if (we && !we_d) begin
		wr_pend <= 1'b1;
		wr_addr <= addr;
		wr_data <= din;
	end

	// the byte of the read slot before, one clock after its MD was taken
	if (q_valid)
		dout <= q_lane ? md_q[15:8] : md_q[7:0];
	q_valid <= 1'b0;

	if (!phase) begin
		// the first edge of a slot: MD of the slot before (two clocks after its address)
		md_q <= MD;
		q_valid <= s_read;
		q_lane <= s_lane;
		if (wr_pend && !(we && !we_d)) begin
			MA <= wr_addr[21:1];
			s_lane <= wr_addr[0];
			s_we <= 1'b1;
			s_data <= wr_data;
			s_read <= 1'b0;
			wr_pend <= 1'b0;
		end
		else begin
			MA <= addr[21:1];
			s_lane <= addr[0];
			s_we <= 1'b0;
			s_read <= 1'b1;
		end
	end
end

// /WE and the write data on the falling edges, from the first clock of the slot to the second
reg [1:0] we_n = 2'b11;
reg [15:0] md_out = 16'd0;
always @(negedge clk) begin
	we_n <= 2'b11;
	if (s_we && phase) begin  // phase is 1 in the first clock of a slot
		we_n <= s_lane ? 2'b01 : 2'b10;
		md_out <= {s_data, s_data};
	end
end
assign MWR_N = we_n;
assign MD[7:0] = !we_n[0] ? md_out[7:0] : 8'bz;
assign MD[15:8] = !we_n[1] ? md_out[15:8] : 8'bz;

endmodule
