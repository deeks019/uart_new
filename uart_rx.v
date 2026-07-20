module uart_rx(input clk,input reset,input rx_serial,output reg data_valid, output reg
[7:0] rx_byte);
parameter CLOCKS_PER_BIT=87;
parameter IDLE=2'b00;
parameter DATA=2'b01;
parameter STOP=2'b10;
parameter DONE=2'b11;

reg [1:0]state;
reg [2:0]bit_index;
reg [7:0]data;
reg [15:0]clk_count;
always @(posedge reset or posedge clk)
begin
	if(reset)
	begin
		state<=IDLE;
		bit_index<=0;
		clk_count<=0;
		data<=8'b0;
		rx_byte<=8'b0;
		data_valid<=0;
	end
else
begin
data_valid<=0;

case(state)
IDLE:
begin
clk_count<=0;
if(rx_serial==0) //To detect the start bit
begin
bit_index<=0;
data<=8'b0;
state<=DATA;
end
end

DATA:
begin
if(clk_count<CLOCKS_PER_BIT-1)
begin
clk_count<=clk_count+1;
end
else
begin
clk_count<=0;
data<={rx_serial,data[7:1]};
if(bit_index==7)
state<=STOP;
else
bit_index<=bit_index+1;
end
end

STOP:
begin
	if(clk_count<CLOCKS_PER_BIT-1)
		clk_count<=clk_count+1;
	else
	begin
		clk_count<=0;
		if(rx_serial==1) //The stop bit is detected
			state<=DONE;
		else
			state<=IDLE;
	end
end
DONE:
begin
rx_byte<=data;
data_valid<=1;
state<=IDLE;
end
endcase
end
end
endmodule




