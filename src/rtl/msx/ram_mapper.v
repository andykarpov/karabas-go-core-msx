// karabas: not from the upstream. The memory mapper of the RAM of slot 3 (MSX2 standard, ports
// FC-FF), 512 KB = 32 segments of 16 KB. Port FC is the segment of page 0 (0000-3FFF), FD page 1,
// FE page 2, FF page 3; after a reset 3, 2, 1, 0, which is the plain 64 KB RAM of an MSX1, so a
// BIOS that knows nothing about the mapper sees its RAM. A port reads back the segment with the
// unused bits 1 (as the mappers of the MSX2 / turbo R: a program that masks the read value finds
// the size). en = 0 is the RAM of 64 KB: the ports are ignored and read FF (no device there).
module ram_mapper (
	input wire clk,
	input wire reset,
	input wire en,
	input wire [7:0] io_addr,   // the low byte of the address
	input wire iorq_n,
	input wire m1_n,
	input wire wr_n,
	input wire [7:0] din,
	input wire [1:0] page,      // address bits 15..14 of the memory access
	output wire [4:0] segment,  // of that page
	output wire sel_n,          // a read of the ports FC-FF (the data mux of msx1)
	output wire [7:0] dout
);

reg [4:0] seg0 = 5'd3, seg1 = 5'd2, seg2 = 5'd1, seg3 = 5'd0;

wire io = ~iorq_n & m1_n & io_addr[7:2] == 6'b111111;

always @(posedge clk) begin
	if (reset | ~en) begin
		seg0 <= 5'd3;
		seg1 <= 5'd2;
		seg2 <= 5'd1;
		seg3 <= 5'd0;
	end else if (io & ~wr_n) begin
		case (io_addr[1:0])
			2'd0: seg0 <= din[4:0];
			2'd1: seg1 <= din[4:0];
			2'd2: seg2 <= din[4:0];
			2'd3: seg3 <= din[4:0];
		endcase
	end
end

assign segment = page == 2'd0 ? seg0 :
                 page == 2'd1 ? seg1 :
                 page == 2'd2 ? seg2 : seg3;

wire [4:0] rd_seg = io_addr[1:0] == 2'd0 ? seg0 :
                    io_addr[1:0] == 2'd1 ? seg1 :
                    io_addr[1:0] == 2'd2 ? seg2 : seg3;

assign sel_n = ~(io & en);
assign dout = {3'b111, rd_seg};

endmodule
