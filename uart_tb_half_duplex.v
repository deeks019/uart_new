`timescale 1ns/1ps                    // Set simulation time unit and precision

module uart_tb;                       // Testbench module
parameter TX_DATA1 = 8'hA5;            // Data sent by Device 1
parameter TX_DATA2 = 8'h3C;            // Data sent by Device 2

reg clk;                              // Clock signal
reg reset;                            // Reset signal
reg tx_start1;                        // Starts TX of Device 1
reg tx_start2;                        // Starts TX of Device 2
reg [1:0] baud_select;                // Selects baud rate
reg [1:0] data_length;                // Selects number of data bits

wire tx_active1;                      // TX active signal of Device 1
wire tx_done1;                        // TX done signal of Device 1
wire serial_tx1;                      // Serial output of Device 1
wire [7:0] rx_data1;                  // Data received by Device 1
wire rx_valid1;                       // RX valid signal of Device 1

wire tx_active2;                      // TX active signal of Device 2
wire tx_done2;                        // TX done signal of Device 2
wire serial_tx2;                      // Serial output of Device 2
wire [7:0] rx_data2;                  // Data received by Device 2
wire rx_valid2;                       // RX valid signal of Device 2


device d1 (                            // Create Device 1
    .clk(clk),                        // Connect clock
    .reset(reset),                    // Connect reset
    .baud_select(baud_select),        // Connect baud selection
    .data_length(data_length),        // Connect data length
    .tx_start(tx_start1),              // Connect TX start
    .tx_data(TX_DATA1),                // Connect TX data
    .tx_active(tx_active1),            // Connect TX active
    .tx_done(tx_done1),                // Connect TX done
    .serial_tx(serial_tx1),            // Connect serial TX
    .serial_rx(serial_tx2),            // Receive data from Device 2
    .rx_data(rx_data1),                // Connect received data
    .rx_valid(rx_valid1)               // Connect RX valid
);

device d2 (                            // Create Device 2
    .clk(clk),                        // Connect clock
    .reset(reset),                    // Connect reset
    .baud_select(baud_select),        // Connect baud selection
    .data_length(data_length),        // Connect data length
    .tx_start(tx_start2),              // Connect TX start
    .tx_data(TX_DATA2),                // Connect TX data
    .tx_active(tx_active2),            // Connect TX active
    .tx_done(tx_done2),                // Connect TX done
    .serial_tx(serial_tx2),            // Connect serial TX
    .serial_rx(serial_tx1),            // Receive data from Device 1
    .rx_data(rx_data2),                // Connect received data
    .rx_valid(rx_valid2)               // Connect RX valid
);

initial begin                          // Start clock generation
    clk = 0;                           // Start clock at 0
    forever #5 clk = ~clk;             // Toggle clock every 5 ns
end

initial begin                          // Start testbench
    $dumpfile("uart.vcd");             // Create VCD waveform file
    $dumpvars(0, uart_tb);             // Save testbench signals
    reset = 1;                         // Apply reset
    tx_start1 = 0;                     // Keep Device 1 TX off
    tx_start2 = 0;                     // Keep Device 2 TX off
    baud_select = 2'b00;               // Select baud setting 4
    data_length = 2'b11;               // Select 8-bit mode
    repeat(2) @(posedge clk);           // Wait for 2 clock edges
    reset = 0;                         // Remove reset
    @(posedge clk);                    // Wait for one clock edge

    // 5-bit Mode
    data_length = 2'b00;               // Select 5-bit data
    baud_select = 2'b00;               // Select baud setting 4
    @(posedge clk);                    // Wait for one clock edge
    tx_start1 = 1;                     // Start Device 1 transmission
    #1;                                // Wait 1 ns
    @(posedge clk);                    // Wait for next clock edge
    tx_start1 = 0;                     // Stop TX start signal
    wait(rx_valid2);                   // Wait until Device 2 receives data
    $display("\n----- 5-bit Mode ----"); // Display test name
    $display("Device 1 transmitted = %h", TX_DATA1); // Display sent data
    $display("Device 2 received    = %h", rx_data2); // Display received data
    @(posedge clk);                    // Wait for one clock edge

    // 6-bit Mode
    data_length = 2'b01;               // Select 6-bit data
    baud_select = 2'b01;               // Select baud setting 2
    @(posedge clk);                    // Wait for one clock edge
    tx_start2 = 1;                     // Start Device 2 transmission
    #1;                                // Wait 1 ns
    @(posedge clk);                    // Wait for next clock edge
    tx_start2 = 0;                     // Stop TX start signal
    wait(rx_valid1);                   // Wait until Device 1 receives data
    $display("\n----- 6-bit Mode ----"); // Display test name
    $display("Device 2 transmitted = %h", TX_DATA2); // Display sent data
    $display("Device 1 received    = %h", rx_data1); // Display received data
    @(posedge clk);                    // Wait for one clock edge

    // 7-bit Mode
    data_length = 2'b10;               // Select 7-bit data
    baud_select = 2'b10;               // Select baud setting 3
    @(posedge clk);                    // Wait for one clock edge
    tx_start1 = 1;                     // Start Device 1 transmission
    #1;                                // Wait 1 ns
    @(posedge clk);                    // Wait for next clock edge
    tx_start1 = 0;                     // Stop TX start signal
    wait(rx_valid2);                   // Wait until Device 2 receives data
    $display("\n----- 7-bit Mode ----"); // Display test name
    $display("Device 1 transmitted = %h", TX_DATA1); // Display sent data
    $display("Device 2 received    = %h", rx_data2); // Display received data
    @(posedge clk);                    // Wait for one clock edge

    // 8-bit Mode
    data_length = 2'b11;               // Select 8-bit data
    baud_select = 2'b11;               // Select baud setting 1
    @(posedge clk);                    // Wait for one clock edge
    tx_start2 = 1;                     // Start Device 2 transmission
    #1;                                // Wait 1 ns
    @(posedge clk);                    // Wait for next clock edge
    tx_start2 = 0;                     // Stop TX start signal
    wait(rx_valid1);                   // Wait until Device 1 receives data

    $display("\n----- 8-bit Mode ----"); // Display test name
    $display("Device 2 transmitted = %h", TX_DATA2); // Display sent data
    $display("Device 1 received    = %h", rx_data1); // Display received data
    #100;                              // Wait 100 ns
    $finish;                           // End simulation
end
endmodule                              // End testbench
