// karabas: the 74LS74 of MiSTer (ls74.sv) on the system clock. Upstream it is clocked by the clock
// enable (clk = clk_en_3m58_p), with an asynchronous clear and preset: a clock from logic, which
// XST and the timing analysis do not take. Here clk is the system clock and ce the former clock:
// d is taken at the clk edge where ce is 1, i.e. the same value the rising ce took (d changes on
// clk edges only), and q changes one clk later than upstream. clr / pre act at once on q (a
// combinational override, as the asynchronous inputs did) and are taken into the register, so q
// keeps their value after they end until the next ce, as a real flip-flop does.
module ls74 (
	input wire clk,
	input wire ce,
	input wire clr,
	input wire pre,
	input wire d,
	output wire q
);

reg q_r = 1'b0;

always @(posedge clk)
	if (!clr)
		q_r <= 1'b0;
	else if (!pre)
		q_r <= 1'b1;
	else if (ce)
		q_r <= d;

assign q = !clr ? 1'b0 : !pre ? 1'b1 : q_r;

endmodule
