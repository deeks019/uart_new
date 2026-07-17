module uart_tx(input clk, input [7:0] tx_byte, input tx_start,input reset,
output reg tx_active, output reg tx_done, output reg tx_serial);
parameter CLOCKS_PER_BIT=87;
parameter IDLE=2'b00;
parameter START=2'b01;
parameter DATA=2'b10;
parameter STOP=2'b11;
reg [1:0] state=IDLE;
reg [2:0] bit_index;
reg [7:0] data;
reg [15:0] clk_count;

always @(posedge clk)
begin
	if(reset)
	begin
		state<=IDLE;
		tx_serial<=1;
		tx_active<=0;
		tx_done<=0;
		bit_index<=0;
		clk_count<=0;
		data<=8'b0;
	end
	else
	begin
		tx_done<=0;

case(state)
IDLE:
begin
tx_serial<=1; // tx_serial remains 1 in IDLE state
tx_active<=0;
clk_count<=0;
if(tx_start)
begin
data<=tx_byte; //Load transmit byte onto data
bit_index<=0;
tx_active<=1; // This is to indicate that the transmission is active now
state<=START;
end
end

START:
begin
tx_serial<=0; // This is sent as the start bit
if(clk_count<CLOCKS_PER_BIT-1) 
clk_count<=clk_count+1;
else
begin
clk_count<=0;
state<=DATA;
end
end

DATA:
begin
tx_serial<=data[0]; //Sending LSB first
if(clk_count<CLOCKS_PER_BIT-1)
clk_count<=clk_count+1;
else
begin
clk_count<=0;
data<=data>>1;//Shifting right
if(bit_index==7)
state<=STOP; // Enters stop if 8 bits are sent
else
bit_index<=bit_index+1;
end
end

STOP:
begin
tx_serial<=1; // Send the stop bit
if(clk_count<CLOCKS_PER_BIT-1)
clk_count<=clk_count+1;
else
begin
clk_count<=0;
tx_done<=1;
tx_active<=0;
state<=IDLE; // Goes back to idle state
end
end
endcase
end
end
endmodule
