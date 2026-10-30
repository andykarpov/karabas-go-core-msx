module ls74 (
	clr,
	pre,
	clk,
	d,
	q
);
	input clr;
	input pre;
	input clk;
	input d;
	output reg q;
	always @(posedge clk or negedge clr or negedge pre)
		if (!clr)
			q <= 1'b0;
		else if (!pre)
			q <= 1'b1;
		else
			q <= d;
endmodule
