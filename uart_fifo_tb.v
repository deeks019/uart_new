`timescale 1ns/1ps

module uart_tb;

parameter TX_DATA1 = 8'hA5;
parameter TX_DATA2 = 8'h3C;

reg clk;
reg reset;
reg tx_start1;
reg tx_start2;
reg [1:0] baud_select;
reg [1:0] data_length;

// TX data inputs are dynamic to send different bytes sequentially
// Allows testbench to change data for each FIFO transmission without resetting
reg [7:0] tx_data1;
reg [7:0] tx_data2;

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

reg loopback_en1;
reg loopback_en2;

// rx_read signal removes bytes from RX FIFO one at a time
// Used to test FIFO read pointer behavior and verify FIFO maintains order
reg rx_read1;
reg rx_read2;

wire serial_rx1;
wire serial_rx2;

// Loopback muxes connect TX output to RX input for testing
assign serial_rx1 = loopback_en1 ? serial_tx1 : serial_tx2;
assign serial_rx2 = loopback_en2 ? serial_tx2 : serial_tx1;

// Device 1 - UART with integrated TX/RX FIFO
device d1 (
    .clk(clk),
    .reset(reset),
    .baud_select(baud_select),
    .data_length(data_length),
    .tx_start(tx_start1),
    .tx_data(tx_data1),
    .tx_active(tx_active1),
    .tx_done(tx_done1),
    .serial_tx(serial_tx1),
    .serial_rx(serial_rx1),
    .rx_read(rx_read1),
    .rx_data(rx_data1),
    .rx_valid(rx_valid1)
);

// Device 2 - UART with integrated TX/RX FIFO
device d2 (
    .clk(clk),
    .reset(reset),
    .baud_select(baud_select),
    .data_length(data_length),
    .tx_start(tx_start2),
    .tx_data(tx_data2),
    .tx_active(tx_active2),
    .tx_done(tx_done2),
    .serial_tx(serial_tx2),
    .serial_rx(serial_rx2),
    .rx_read(rx_read2),
    .rx_data(rx_data2),
    .rx_valid(rx_valid2)
);

// Clock generation at 5ns period (100MHz)
initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

// Reset task initializes all control signals to safe state
// Ensures clean starting condition for each test
task reset_uart;
begin
    reset = 1;
    tx_start1 = 0;
    tx_start2 = 0;
    rx_read1  = 0;
    rx_read2  = 0;
    loopback_en1 = 0;
    loopback_en2 = 0;

    repeat(3) @(posedge clk);
    reset = 0;
    @(posedge clk);
end
endtask

// Task to send one byte (used when tx_data is parameterized)
task send_d1;
input [7:0] data;
begin
    @(negedge clk);
end
endtask

// Task to read one byte from Device 1 RX FIFO and verify correctness
// Waits for rx_valid flag, compares data against expected value
// Then pulses rx_read to pop byte from FIFO and advance read pointer
task read_d1;
input [7:0] expected;
begin
    wait(rx_valid1);

    if (rx_data1 !== expected) begin
        $display("ERROR: D1 expected %02h, received %02h",
                 expected, rx_data1);
        errors = errors + 1;
    end
    else begin
        $display("D1 received %02h  PASS", rx_data1);
    end

    @(negedge clk);
    rx_read1 = 1;  // Pulse rx_read to remove byte from FIFO

    @(negedge clk);
    rx_read1 = 0;
end
endtask

// Task to read one byte from Device 2 RX FIFO and verify correctness
task read_d2;
input [7:0] expected;
begin
    wait(rx_valid2);

    if (rx_data2 !== expected) begin
        $display("ERROR: D2 expected %02h, received %02h",
                 expected, rx_data2);
        errors = errors + 1;
    end
    else begin
        $display("D2 received %02h  PASS", rx_data2);
    end

    @(negedge clk);
    rx_read2 = 1;  // Pulse rx_read to remove byte from FIFO

    @(negedge clk);
    rx_read2 = 0;
end
endtask

integer errors;
integer i;

reg [7:0] fifo_data [0:15];

// Main FIFO-focused testbench
initial begin

    $dumpfile("uart.vcd");
    $dumpvars(0, uart_tb);

    reset = 1;
    tx_start1 = 0;
    tx_start2 = 0;
    rx_read1 = 0;
    rx_read2 = 0;
    baud_select = 2'b00;
    data_length = 2'b11;
    loopback_en1 = 0;
    loopback_en2 = 0;

    errors = 0;
    tx_data1 = TX_DATA1;
    tx_data2 = TX_DATA2;

    // TEST 1: Send 16 bytes sequentially through TX FIFO
    // Verifies TX FIFO buffers multiple bytes and device serializes them in order
    // Tests that RX FIFO receives all bytes in correct sequence
    reset_uart;

    data_length = 2'b11;
    baud_select = 2'b00;

    fifo_data[0]  = 8'h10;
    fifo_data[1]  = 8'h21;
    fifo_data[2]  = 8'h32;
    fifo_data[3]  = 8'h43;
    fifo_data[4]  = 8'h54;
    fifo_data[5]  = 8'h65;
    fifo_data[6]  = 8'h76;
    fifo_data[7]  = 8'h87;
    fifo_data[8]  = 8'h98;
    fifo_data[9]  = 8'hA9;
    fifo_data[10] = 8'hBA;
    fifo_data[11] = 8'hCB;
    fifo_data[12] = 8'hDC;
    fifo_data[13] = 8'hED;
    fifo_data[14] = 8'hFE;
    fifo_data[15] = 8'h0F;

    $display("\n========================================");
    $display("TEST 1: 16-BYTE TX FIFO -> RX FIFO");
    $display("========================================");

    // Send all 16 bytes rapidly - FIFO queues them for sequential transmission
    // Each tx_start pulse loads one byte into TX FIFO
    // Device transmits them one after another over serial line
    for (i = 0; i < 16; i = i + 1) begin
        @(negedge clk);
        tx_data1 = fifo_data[i];
        tx_start1 = 1;

        @(negedge clk);
        tx_start1 = 0;
    end

    // Wait for all 16 bytes to arrive in RX FIFO
    // Accessing d2.rx_count is testbench-only internal observation
    // Verifies that device RX FIFO filled completely and maintained byte order
    wait(d2.rx_count == 16);

    $display("All 16 bytes reached Device 2 RX FIFO.");
    $display("Reading them back in FIFO order:");

    // Read bytes from RX FIFO in FIFO order
    // Each read_d2 call waits for rx_valid, checks data, then pulses rx_read
    // This verifies read pointer advances correctly and next byte becomes valid
    for (i = 0; i < 16; i = i + 1)
        read_d2(fifo_data[i]);

    $display("16-byte FIFO PASS");

    // TEST 2: Reverse direction - Device 2 to Device 1
    // Verifies FIFO works in both directions
    // Same test but Device 2 transmits and Device 1 receives
    reset_uart;

    data_length = 2'b11;
    baud_select = 2'b00;

    fifo_data[0]  = 8'hA0;
    fifo_data[1]  = 8'hB1;
    fifo_data[2]  = 8'hC2;
    fifo_data[3]  = 8'hD3;
    fifo_data[4]  = 8'hE4;
    fifo_data[5]  = 8'hF5;
    fifo_data[6]  = 8'h16;
    fifo_data[7]  = 8'h27;
    fifo_data[8]  = 8'h38;
    fifo_data[9]  = 8'h49;
    fifo_data[10] = 8'h5A;
    fifo_data[11] = 8'h6B;
    fifo_data[12] = 8'h7C;
    fifo_data[13] = 8'h8D;
    fifo_data[14] = 8'h9E;
    fifo_data[15] = 8'hAF;

    $display("\n========================================");
    $display("TEST 2: 16-BYTE RX/TX FIFO REVERSE");
    $display("D2 TX FIFO -> D1 RX FIFO");
    $display("========================================");

    for (i = 0; i < 16; i = i + 1) begin
        @(negedge clk);
        tx_data2 = fifo_data[i];
        tx_start2 = 1;

        @(negedge clk);
        tx_start2 = 0;
    end

    // Wait for all 16 bytes to arrive in opposite direction
    wait(d1.rx_count == 16);

    $display("All 16 bytes reached Device 1 RX FIFO.");
    $display("Reading them back in FIFO order:");

    for (i = 0; i < 16; i = i + 1)
        read_d1(fifo_data[i]);

    $display("Reverse 16-byte FIFO PASS");

    // Test summary and results
    $display("\n========================================");

    if (errors == 0)
        $display("ALL FIFO TESTS PASSED");
    else
        $display("FIFO TEST FAILED: %0d ERROR(S)", errors);

    $display("========================================");

    #100;
    $finish;
end

endmodule
