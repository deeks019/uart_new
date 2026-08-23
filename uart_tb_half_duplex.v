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

// TX data inputs can be changed dynamically by testbench for FIFO testing
reg [7:0] tx_data1;
reg [7:0] tx_data2;

wire tx_active1;
wire tx_done1;
wire serial_tx1;
wire [7:0] rx_data1;
wire rx_valid1;
wire parity_error1;
wire framing_error1;
wire overrun_error1;

wire tx_active2;
wire tx_done2;
wire serial_tx2;
wire [7:0] rx_data2;
wire rx_valid2;
wire parity_error2;
wire framing_error2;
wire overrun_error2;

reg loopback_en1;
reg loopback_en2;

// rx_read signal removes one byte from RX FIFO
// Used to test FIFO read pointer behavior and sequential data retrieval
reg rx_read1;
reg rx_read2;

// Error injection controls used to intentionally corrupt signals during tests
// Tests that device properly detects and reports errors
reg parity_inject2;
reg framing_inject2;

wire serial_rx1;
wire serial_rx2;

// Loopback muxes: select whether device receives its own TX or the other device's TX
// Allows testing both loopback and cross-device communication
assign serial_rx1 = loopback_en1 ? serial_tx1 : serial_tx2;
assign serial_rx2 = framing_inject2 ? 1'b0 :
                    parity_inject2  ? ~serial_tx1 :
                    (loopback_en2 ? serial_tx2 : serial_tx1);

// Device 1
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
    .rx_valid(rx_valid1),
    .parity_error(parity_error1),
    .framing_error(framing_error1),
    .overrun_error(overrun_error1)
);

// Device 2
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
    .rx_valid(rx_valid2),
    .parity_error(parity_error2),
    .framing_error(framing_error2),
    .overrun_error(overrun_error2)
);

// Clock generation at 5ns period (100MHz)
initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

// Reset task initializes all control signals to safe state
// Used at start of each test to ensure clean starting condition
task reset_uart;
begin
    reset = 1;
    tx_start1 = 0;
    tx_start2 = 0;
    rx_read1  = 0;
    rx_read2  = 0;
    loopback_en1 = 0;
    loopback_en2 = 0;
    parity_inject2 = 0;
    framing_inject2 = 0;

    repeat(3) @(posedge clk);
    reset = 0;
    @(posedge clk);
end
endtask

// Task to send one byte (not heavily used in FIFO tests)
task send_d1;
input [7:0] data;
begin
    @(negedge clk);
end
endtask

// Task to read one byte from Device 1 RX FIFO and verify correctness
// Waits for data valid, compares against expected value, generates pulse on rx_read
// This tests both data integrity and FIFO read pointer advancement
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

// Main testbench starts here
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
    parity_inject2 = 0;
    framing_inject2 = 0;

    errors = 0;
    tx_data1 = TX_DATA1;
    tx_data2 = TX_DATA2;

    // TEST 1: Device 1 transmits and receives its own data
    // Verifies basic TX and RX functionality in same device
    reset_uart;

    loopback_en1 = 1;
    loopback_en2 = 0;
    data_length = 2'b11;
    baud_select = 2'b11;

    @(posedge clk);
    tx_start1 = 1;
    wait(tx_active1);
    tx_start1 = 0;

    wait(rx_valid1);

    $display("\n----- Loopback Mode -----");
    $display("Device 1 transmitted = %h", TX_DATA1);
    $display("Device 1 received    = %h", rx_data1);

    if (rx_data1 !== TX_DATA1) begin
        $display("ERROR: Device 1 loopback failed");
        errors = errors + 1;
    end
    else
        $display("Device 1 loopback PASS");

    @(negedge clk);
    rx_read1 = 1;
    @(negedge clk);
    rx_read1 = 0;

    loopback_en1 = 0;
    loopback_en2 = 0;

    // TEST 2: Device 2 loopback test
    // Same as TEST 1 but for device 2
    reset_uart;

    loopback_en1 = 0;
    loopback_en2 = 1;
    data_length = 2'b11;
    baud_select = 2'b11;

    @(posedge clk);
    tx_start2 = 1;
    wait(tx_active2);
    tx_start2 = 0;

    wait(rx_valid2);

    $display("\n----- Loopback Mode -----");
    $display("Device 2 transmitted = %h", TX_DATA2);
    $display("Device 2 received    = %h", rx_data2);

    if (rx_data2 !== TX_DATA2) begin
        $display("ERROR: Device 2 loopback failed");
        errors = errors + 1;
    end
    else
        $display("Device 2 loopback PASS");

    @(negedge clk);
    rx_read2 = 1;
    @(negedge clk);
    rx_read2 = 0;

    loopback_en1 = 0;
    loopback_en2 = 0;

    // TEST 3: 5-bit mode
    // Verifies that only 5 least significant bits are transmitted and received
    reset_uart;

    data_length = 2'b00;
    baud_select = 2'b00;

    @(posedge clk);
    tx_start1 = 1;
    wait(tx_active1);
    tx_start1 = 0;

    wait(rx_valid2);

    $display("\n----- 5-bit Mode -----");
    $display("Device 1 transmitted = %h", TX_DATA1);
    $display("Device 2 received    = %h", rx_data2);

    // A5 (10100101) -> lower 5 bits = 00101 = 05
    if (rx_data2 !== 8'h05) begin
        $display("ERROR: 5-bit mode failed");
        errors = errors + 1;
    end
    else
        $display("5-bit mode PASS");

    @(negedge clk);
    rx_read2 = 1;
    @(negedge clk);
    rx_read2 = 0;

    // TEST 4: 6-bit mode
    reset_uart;

    data_length = 2'b01;
    baud_select = 2'b01;

    @(posedge clk);
    tx_start2 = 1;
    wait(tx_active2);
    tx_start2 = 0;

    wait(rx_valid1);

    $display("\n----- 6-bit Mode -----");
    $display("Device 2 transmitted = %h", TX_DATA2);
    $display("Device 1 received    = %h", rx_data1);

    // 3C (00111100) -> lower 6 bits = 111100 = 3C
    if (rx_data1 !== 8'h3C) begin
        $display("ERROR: 6-bit mode failed");
        errors = errors + 1;
    end
    else
        $display("6-bit mode PASS");

    @(negedge clk);
    rx_read1 = 1;
    @(negedge clk);
    rx_read1 = 0;

    // TEST 5: 7-bit mode
    reset_uart;

    data_length = 2'b10;
    baud_select = 2'b10;

    @(posedge clk);
    tx_start1 = 1;
    wait(tx_active1);
    tx_start1 = 0;

    wait(rx_valid2);

    $display("\n----- 7-bit Mode -----");
    $display("Device 1 transmitted = %h", TX_DATA1);
    $display("Device 2 received    = %h", rx_data2);

    // A5 (10100101) -> lower 7 bits = 0100101 = 25
    if (rx_data2 !== 8'h25) begin
        $display("ERROR: 7-bit mode failed");
        errors = errors + 1;
    end
    else
        $display("7-bit mode PASS");

    @(negedge clk);
    rx_read2 = 1;
    @(negedge clk);
    rx_read2 = 0;

    // TEST 6: 8-bit mode
    reset_uart;

    data_length = 2'b11;
    baud_select = 2'b11;

    @(posedge clk);
    tx_start2 = 1;
    wait(tx_active2);
    tx_start2 = 0;

    wait(rx_valid1);

    $display("\n----- 8-bit Mode -----");
    $display("Device 2 transmitted = %h", TX_DATA2);
    $display("Device 1 received    = %h", rx_data1);

    if (rx_data1 !== TX_DATA2) begin
        $display("ERROR: 8-bit mode failed");
        errors = errors + 1;
    end
    else
        $display("8-bit mode PASS");

    @(negedge clk);
    rx_read1 = 1;
    @(negedge clk);
    rx_read1 = 0;

    // TEST 7: FIFO test - send 16 bytes sequentially
    // Verifies TX and RX FIFOs buffer multiple bytes and maintain order
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
    $display("TEST 7: 16-BYTE TX FIFO -> RX FIFO");
    $display("========================================");

    // Send all 16 bytes quickly using FIFO buffering
    // TX FIFO queues them and device transmits one after another
    for (i = 0; i < 16; i = i + 1) begin
        @(negedge clk);
        tx_data1 = fifo_data[i];
        tx_start1 = 1;

        @(negedge clk);
        tx_start1 = 0;
    end

    // Wait for all bytes to be received and stored in RX FIFO
    // This checks both TX buffering and RX buffering capability
    wait(d2.rx_count == 16);

    $display("All 16 bytes reached Device 2 RX FIFO.");
    $display("Reading them back in FIFO order:");

    for (i = 0; i < 16; i = i + 1)
        read_d2(fifo_data[i]);

    $display("16-byte FIFO PASS");

    // TEST 8: FIFO reverse direction (Device 2 to Device 1)
    // Verifies FIFO works in both directions
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
    $display("TEST 8: 16-BYTE RX/TX FIFO REVERSE");
    $display("D2 TX FIFO -> D1 RX FIFO");
    $display("========================================");

    for (i = 0; i < 16; i = i + 1) begin
        @(negedge clk);
        tx_data2 = fifo_data[i];
        tx_start2 = 1;

        @(negedge clk);
        tx_start2 = 0;
    end

    wait(d1.rx_count == 16);

    $display("All 16 bytes reached Device 1 RX FIFO.");
    $display("Reading them back in FIFO order:");

    for (i = 0; i < 16; i = i + 1)
        read_d1(fifo_data[i]);

    $display("Reverse 16-byte FIFO PASS");

    // TEST 9: Parity error detection
    // Injects bit error in parity field to verify device detects corruption
    reset_uart;

    data_length = 2'b11;
    baud_select = 2'b00;

    $display("\n========================================");
    $display("TEST 9: PARITY ERROR");
    $display("========================================");

    @(posedge clk);
    tx_start1 = 1;
    wait(tx_active1);
    tx_start1 = 0;

    // Wait until receiver is in parity state before corrupting signal
    wait(d2.rx_state == 3'd3);

    // Flip parity bit by inverting the signal line
    parity_inject2 = 1;
    @(posedge clk);
    parity_inject2 = 0;

    repeat(3) @(posedge clk);

    if (parity_error2) begin
        $display("Parity error detected PASS");
    end
    else begin
        $display("ERROR: Parity error NOT detected");
        errors = errors + 1;
    end

    // TEST 10: Framing error detection
    // Injects error in stop bit to verify device detects invalid frame
    reset_uart;

    data_length = 2'b11;
    baud_select = 2'b00;

    $display("\n========================================");
    $display("TEST 10: FRAMING ERROR");
    $display("========================================");

    @(posedge clk);
    tx_start1 = 1;
    wait(tx_active1);
    tx_start1 = 0;

    // Wait until receiver is in stop bit state before corrupting signal
    wait(d2.rx_state == 3'd4);

    // Force stop bit to 0 (should be 1)
    // This violates UART frame format
    framing_inject2 = 1;
    @(posedge clk);
    framing_inject2 = 0;

    repeat(3) @(posedge clk);

    if (framing_error2) begin
        $display("Framing error detected PASS");
    end
    else begin
        $display("ERROR: Framing error NOT detected");
        errors = errors + 1;
    end

    // TEST 11: RX FIFO overrun detection
    // Sends 17 bytes to 16-byte FIFO without reading
    // Verifies overrun_error flag is set when FIFO fills
    reset_uart;

    data_length = 2'b11;
    baud_select = 2'b00;

    $display("\n========================================");
    $display("TEST 11: RX FIFO OVERRUN");
    $display("========================================");

    // Send 17 bytes to Device 2 RX FIFO (capacity 16)
    // First 16 fit, 17th should trigger overrun error
    for (i = 0; i < 17; i = i + 1) begin

        @(negedge clk);
        tx_data1 = i + 8'h10;
        tx_start1 = 1;

        @(negedge clk);
        tx_start1 = 0;

        wait(tx_done1);

    end

    repeat(5) @(posedge clk);

    if (overrun_error2) begin
        $display("RX FIFO overrun detected PASS");
    end
    else begin
        $display("ERROR: RX FIFO overrun NOT detected");
        errors = errors + 1;
    end

    // Summary of all test results
    $display("\n========================================");

    if (errors == 0)
        $display("ALL UART FEATURES PASSED");
    else
        $display("UART TEST FAILED: %0d ERROR(S)", errors);

    $display("========================================");

    #100;
    $finish;
end

endmodule
