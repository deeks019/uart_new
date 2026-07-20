`timescale 1ns/1ps

module uart_tb;

parameter BAUD_RATE = 115200;
parameter TX_DATA1 = 8'hA5;
parameter TX_DATA2 = 8'h3C;

reg clk;
reg reset;
reg tx_start1;
reg tx_start2;

wire tx_active1;
wire tx_done1;
wire serial_tx1;
wire [7:0] rx_data1;
wire rx_valid1;

wire tx_active2;
wire tx_done2;
wire serial_tx2;
wire [7:0] rx_data2;
wire rx_valid2;

real HALF_PERIOD;

device d1 (
    .clk(clk),
    .reset(reset),
    .tx_start(tx_start1),
    .tx_data(TX_DATA1),
    .tx_active(tx_active1),
    .tx_done(tx_done1),
    .serial_tx(serial_tx1),
    .serial_rx(serial_tx2),
    .rx_data(rx_data1),
    .rx_valid(rx_valid1)
);

device d2 (
    .clk(clk),
    .reset(reset),
    .tx_start(tx_start2),
    .tx_data(TX_DATA2),
    .tx_active(tx_active2),
    .tx_done(tx_done2),
    .serial_tx(serial_tx2),
    .serial_rx(serial_tx1),
    .rx_data(rx_data2),
    .rx_valid(rx_valid2)
);

initial begin
    clk = 0;
    HALF_PERIOD = 1000000000.0 / (2.0 * BAUD_RATE);

    forever #(HALF_PERIOD) clk = ~clk;
end

initial begin
   $dumpfile("uart.vcd");
   $dumpvars(0, uart_tb);
    reset = 1;
    tx_start1 = 0;
    tx_start2 = 0;

    #100;
    reset = 0;

    @(posedge clk);

    tx_start1 = 1;
    tx_start2 = 1;

    @(posedge clk);

    tx_start1 = 0;
    tx_start2 = 0;

    wait(rx_valid1 && rx_valid2);

    $display("Device 1 transmitted = %h", TX_DATA1);
    $display("Device 2 received    = %h", rx_data2);

    $display("Device 2 transmitted = %h", TX_DATA2);
    $display("Device 1 received    = %h", rx_data1);

    #100;

    $finish;
end

endmodule
