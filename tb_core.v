`timescale 1ns / 1ps

module tb_core;
reg clk;
reg rst_n;

wire    [31:0]  iaddr;
wire    [31:0]  idata;
wire    [31:0]  daddr;
wire    [31:0]  drdata;
wire    [31:0]  dwdata;
wire    [3:0]   dwe;

reg [31:0]  tcm    [0:511];

assign idata = tcm[iaddr[31:2]];
assign drdata = tcm[daddr[31:2]];

integer i;
initial begin
    for (i = 0; i < 512; i = i + 1) begin
        tcm[i] = 0;
    end    
    $readmemh("tcm_init.mem", tcm);
end

always @(posedge clk) begin
    if (dwe) begin
        tcm[daddr[31:2]] <= dwdata;
    end
end

core core_i
(
    .clk(clk),
    .rstn(rst_n),
    .iaddr(iaddr),
    .idata(idata),
    .ivalid(1),
    .daddr(daddr),
    .drdata(drdata),
    .drvalid(1),
    .dwdata(dwdata),
    .dwe(dwe)
);

localparam CLK_PERIOD = 10;
always #(CLK_PERIOD/2) clk=~clk;

initial begin
    #1 rst_n<=1'bx;clk<=1'bx;
    #(CLK_PERIOD*3) rst_n<=1;
    #(CLK_PERIOD*3) rst_n<=0;clk<=0;
    repeat(5) @(posedge clk);
    rst_n<=1;
    @(posedge clk);
    repeat(20) @(posedge clk);
    $finish(2);
end

endmodule
