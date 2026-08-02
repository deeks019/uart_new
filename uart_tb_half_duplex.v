`timescale 1ns/1ps
module uart_tb;
parameter TX_DATA1 = 8'hA5;  // The data to be sent from Device 1 to Device 2
parameter TX_DATA2 = 8'h3C;  // The data to be sent from Device 2 to Device 1

reg clk;                     // Common clock for both devices
reg reset;                   // Reset signal for both devices
reg tx_start1;               // Starts transmission from Device 1
reg tx_start2;               // Starts transmission from Device 2
reg [1:0] baud_select;       // Baud rate selection

wire tx_active1;             // HIGH while Device 1 is transmitting
wire tx_done1;               // HIGH when Device 1 finishes transmission
wire serial_tx1;             // Serial output from Device 1
wire [7:0] rx_data1;         // Data received by Device 1
wire rx_valid1;              // HIGH when Device 1 has received valid data

wire tx_active2;             // HIGH while Device 2 is transmitting
wire tx_done2;               // HIGH when Device 2 finishes transmission
wire serial_tx2;             // Serial output from Device 2
wire [7:0] rx_data2;         // Data received by Device 2
wire rx_valid2;              // HIGH when Device 2 has received valid data


// Device 1
device d1 (
    .clk(clk),
    .reset(reset),
    .baud_select(baud_select),
    .tx_start(tx_start1),
    .tx_data(TX_DATA1),
    .tx_active(tx_active1),
    .tx_done(tx_done1), 
    .serial_tx(serial_tx1), // Device 1 serial output
    .serial_rx(serial_tx2), // Device 1 receives the serial output from Device 2
    .rx_data(rx_data1),
    .rx_valid(rx_valid1)
);


// Device 2
device d2(
    .clk(clk),
    .reset(reset),
    .baud_select(baud_select),
    .tx_start(tx_start2),
    .tx_data(TX_DATA2),
    .tx_active(tx_active2),
    .tx_done(tx_done2),
    .serial_tx(serial_tx2), // Device 2 serial output
    .serial_rx(serial_tx1), // Device 2 receives the serial output from Device 1
    .rx_data(rx_data2),
    .rx_valid(rx_valid2)
);

// Generate clock
initial begin
    clk = 0;                    // Clock starts from LOW
    forever #5 clk = ~clk;      // Change the clock value every 5 ns
end

initial begin
    $dumpfile("uart.vcd");       // Create a waveform file
    $dumpvars(0, uart_tb);       // Store all testbench signal values in the waveform file
    reset = 1;                   // Reset both devices
    tx_start1 = 0;               // Device 1 transmission is not started
    tx_start2 = 0;               // Device 2 transmission is not started
    baud_select = 2'b11;    //115200 baud
    #10;                          // Wait for 10 ns
    reset = 0;                   // Remove reset so the devices can start working
    @(posedge clk);              // Wait for the next positive edge of the clock
    
    // Device 1 starts transmitting
    tx_start1 = 1;   
    #1;            // Tell Device 1 to start transmission
    @(posedge clk);              // Wait for the next positive edge of the clock
    tx_start1 = 0;               // Make the start signal LOW again
    // Wait until Device 2 receives the data
    wait(rx_valid2);             // Wait until Device 2 says that received data is valid
    $display("Device 1 transmitted = %h", TX_DATA1); // Display data sent by Device 1
    $display("Device 2 received    = %h", rx_data2); // Display data received by Device 2
    baud_select = 2'b00;
    @(posedge clk);              // Wait for the next positive edge of the clock
    
    // Device 2 starts transmitting
    tx_start2 = 1;   
    #1;            // Tell Device 2 to start transmission
    @(posedge clk);              // Wait for the next positive edge of the clock
    tx_start2 = 0;               // Make the start signal LOW again
    // Wait until Device 1 receives the data
    wait(rx_valid1);             // Wait until Device 1 says that received data is valid
    $display("Device 2 transmitted = %h", TX_DATA2); // Display data sent by Device 2
    $display("Device 1 received    = %h", rx_data1); // Display data received by Device 1
    #100;                        // Wait for 100 ns before ending the simulation
    $finish;                     // End the simulation
end
endmodule
