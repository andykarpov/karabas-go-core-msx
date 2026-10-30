`timescale 1ns / 1ps
`default_nettype wire

/*
 spram.v

 karabas: the spram of the MiSTer bram.vhd (altsyncram, single port) on kg_spram of the modules.
 The same parameters and ports as the instances of the MSX1 core use them; the Altera ports
 enable and cs are not used by any instance and left out. altsyncram has
 read_during_write_mode_port_a NEW_DATA_NO_NBE_READ: a write shows the new word (WRITE_FIRST).
 mem_init_file: a $readmemh file (src/tools/mif2hex.py converts the .mif of the upstream),
 relative to src/ for XST. mem_name named the memory for the In-System Memory Content Editor
 of Quartus; it is kept for the instances and not used.
*/

module spram #(
	parameter addr_width = 8,
	parameter data_width = 8,
	parameter mem_init_file = "",
	parameter mem_name = "MEM"
) (
	input wire clock,
	input wire [addr_width-1:0] address,
	input wire [data_width-1:0] data,
	input wire wren,
	output wire [data_width-1:0] q
);

kg_spram #(
	.DW(data_width),
	.AW(addr_width),
	.WRITE_FIRST(1),
	.INIT_FILE(mem_init_file)
) ram (
	.clk(clock),
	.en(1'b1),
	.we(wren),
	.addr(address),
	.din(data),
	.dout(q)
);

endmodule
