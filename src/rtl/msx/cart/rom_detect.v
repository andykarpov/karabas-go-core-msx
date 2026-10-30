module rom_detect
(
    input             clk,
    input             ioctl_isROM,
    input      [24:0] ioctl_addr,
    input       [7:0] ioctl_dout,
    input             rom_we,
    output reg  [2:0] mapper = 3'd0,  // karabas: registered, see the end
    output reg  [3:0] offset = 4'd0,
    output reg [24:0] rom_size
);

reg last_isROM;
reg [7:0]  head  [0:7];
reg [7:0]  head2 [0:7];
reg signed [15:0] asc16, asc8, kon4, kon5;
reg game1, game2;

always @(posedge clk) begin
    last_isROM = ioctl_isROM;
end

reg [7:0] a0,a1,a2; // karabas: out of the always block (XST takes no declarations in an unnamed block)
reg hit = 1'b0;      // karabas: see below
reg [7:0] hit_a2 = 8'd0;
always @(posedge clk) begin

    // karabas: the counters of the match registered at the byte before (see rom_we)
    hit <= 1'b0;
    if (hit) begin
        case (hit_a2)
                8'h60,
                8'h70: begin
                    asc16 <= asc16 + 1'd1;
                    asc8 <= asc8 + 1'd1;
                end
                8'h68,
                8'h78: begin
                    asc8 <= asc8 + 1'd1;
                    asc16 <= asc16 - 1'd1;
                end
        endcase
        case (hit_a2)
                8'h60,
                8'h80,
                8'ha0: begin
                    kon4 <= kon4 + 1'd1;
                end
                8'h50,
                8'h70,
                8'h90,
                8'hb0: begin
                    kon5 <= kon5 + 1'd1;
                end
        endcase
    end

    if (ioctl_isROM && ~last_isROM) begin
        asc16 <= 0;
        asc8  <= 0;
        kon4  <= 0;
        kon5  <= 0;
        game1 <= 0;
        game2 <= 0;
        a0    <= 0;
        a1    <= 0;
        a2    <= 0;
        hit   <= 1'b0; // karabas
    end
    if (rom_we) begin
        rom_size <= ioctl_addr + 1'd1 ;
        if (ioctl_addr[24:7] == 0) begin
            if (ioctl_addr[5:3] == 0) begin
                if (ioctl_addr[6] == 0) begin
                        head  [ioctl_addr[2:0]] <= ioctl_dout;
                        head2 [ioctl_addr[2:0]] <= 0;
                end else begin
                        head2[ioctl_addr[2:0]] <= ioctl_dout;
                end
            end
            if (ioctl_addr[6:1] == 6'b001000) begin
                if (ioctl_addr[0] == 0 && ioctl_dout == "Y")
                        game1 <= 1;
                if (ioctl_addr[0] == 1 && ioctl_dout == "Z")
                        game2 <= 1;
            end
        end
        a0 <= a1;
        a1 <= a2;
        a2 <= ioctl_dout;
        // karabas: the match of the last three bytes is registered, the counters follow a clock
        // later (the compare and the 16-bit counters in one clock were the slowest path of the core;
        // a byte of the loader comes every 10 clocks or less often)
        hit <= ioctl_addr > 2 && a0 == 8'h32 && a1 == 0;
        hit_a2 <= a2;
    end
end

// 0 uknown
// 1 nomaper
// 2 gamemaster2
// 3 konami
// 4 konami SCC
// 5 ASCII 8
// 6 ASCII 16

wire [15:0] kon    = kon4 > kon5 ? kon4 : kon5;
wire [15:0] ascii  = asc8 > asc16 ? asc8 : asc16;
wire  [2:0] mapper_c = rom_size < 25'h2000                        ? 3'd0 :
                     rom_size < 25'h10000                       ? 3'd1 :
                     game1 && game2 && rom_size > 25'h18000     ? 3'd2 :
                     kon > ascii                                ? (kon5 > kon4  ? 3'd4 : 3'd3) :
                                                                  (asc8 > asc16 ? 3'd5 : 3'd6) ;
wire [15:0] start = head[3] << 8 | head[2];
wire [15:0] start4000 = head2[3] << 8 | head2[2];
wire romSig_at_0000 = head [0] == "A" && head [1] == "B";
wire romSig_at_4000 = head2[0] == "A" && head2[1] == "B";

wire [3:0] start_1 = start == 0 ?  ((head[5] & 8'hC0) != 8'h40 ? 4'h8 : 4'h4) : ((start & 16'hC000) == 16'h8000 ? 4'h8 : 4'h4);
wire [3:0] start_2 = (~romSig_at_0000 && romSig_at_4000) ? ((start4000 == 0 && (head2[5] & 8'hC0) == 8'h40) || start4000 < 16'h8000 || start4000 >= 16'hC000) ? 4'h0 : 4'h4 : 4'h4;
wire [3:0] start_3 = (~(romSig_at_0000 && ~romSig_at_4000)) ? 4'h0 : 4'h4;
wire  [3:0] offset_c = rom_size == 16'h1000 ? start_1 :
                rom_size == 16'h2000 ? start_1 :
                rom_size == 16'h4000 ? start_1 :
                rom_size == 16'h8000 ? start_2 :
                rom_size == 16'hC000 ? start_3 : 4'h0;

// karabas: mapper and offset registered: they change only while a ROM loads (the machine is in
// reset then), and the counters compared above to the address and the sound of a cartridge
// (the SCC of mapper 4) to the DAC were the slowest paths of the core
always @(posedge clk) begin
    mapper <= mapper_c;
    offset <= offset_c;
end
endmodule
