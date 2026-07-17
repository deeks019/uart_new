`timescale 1ns/1ps
module uart_tb;
reg clk;
reg reset;
reg tx_start;
reg [7:0]tx_byte;

wire tx_serial;
wire tx_active;
wire tx_done;

wire [7:0]rx_byte;
wire data_valid;

uart_tx uut_tx(.clk(clk),.reset(reset),.tx_start(tx_start),.tx_byte(tx_byte),.tx_serial
(tx_serial),.tx_active(tx_active),.tx_done(tx_done));

uart_rx uut_rx(.clk(clk),.reset(reset),.rx_serial(tx_serial),.rx_byte(rx_byte),.data_valid(data_valid)); //Connect tx_serial to rx_serial

always #50 clk=~clk;
initial 
begin
	#500000;
	$display("TIMEOUT-Simulation hung");
	$finish;
end
initial
begin
	$dumpfile("uart.vcd");
	$dumpvars(0,uart_tb);
clk=0;
reset=1;
tx_start=0;
tx_byte=8'h00;
#205;
reset=0;
#505;
tx_byte=8'hA5;
tx_start=1;
#105;
tx_start=0;
@(posedge data_valid);
@(negedge clk);
while(tx_active) @(negedge clk);
#105;
$display("Tx=%h Rx=%h",tx_byte,rx_byte);
if(tx_byte==rx_byte)
	$display("TEST 1 PASSED\n");
else
	$display("TEST 1 FAILED\n");
#505;
tx_byte=8'h3C;
tx_start=1;
#105;
tx_start=0;
@(posedge data_valid);
@(negedge clk);
while(tx_active) @(negedge clk);
#105;
$display("Tx=%h Rx=%h",tx_byte,rx_byte);
if(tx_byte==rx_byte)
	$display("TEST 2 PASSED\n");
else
	$display("TEST 2 FAILED\n");
#505;
tx_byte=8'hF0;
tx_start=1;
#105;
tx_start=0;
@(posedge data_valid);
@(negedge clk);
#105;
$display("Tx=%h Rx=%h",tx_byte,rx_byte);
if(tx_byte==rx_byte)
	$display("TEST 3 PASSED\n");
else
	$display("TEST 3 FAILED\n");
#505;
$finish;
end
endmodule

