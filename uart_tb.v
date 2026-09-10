module uart_tb;
    parameter [7:0] TEST_DATA = 8'hA5;
    reg clk, reset;
    reg [1:0] baud_select, data_length, parity_select;
    reg tx_start1, tx_start2;
    reg rx_read1, rx_read2;
    reg [7:0] tx_data1, tx_data2;
    reg flow_control_en;
    wire tx_active1, tx_done1, serial_tx1;
    wire tx_active2, tx_done2, serial_tx2;
    wire [7:0] rx_data1, rx_data2;
    wire rx_valid1, rx_valid2;
    wire rts1, rts2, cts1, cts2;
    wire serial_rx1, serial_rx2;
    integer i;
    integer errors;
    reg expected_parity;
    reg [4:0] tx_count_before_pause;

    assign serial_rx1 = serial_tx2; // Connect TX2 to RX1
    assign serial_rx2 = serial_tx1; // Connect TX1 to RX2
    assign cts1 = flow_control_en ? rts2 : 1'b0; // Set CTS1
    assign cts2 = flow_control_en ? rts1 : 1'b0; // Set CTS2

    device d1 (
        .clk(clk), .reset(reset),
        .baud_select(baud_select),
        .data_length(data_length),
        .parity_select(parity_select),
        .tx_start(tx_start1), .tx_data(tx_data1),
        .cts(cts1), .rts(rts1),
        .tx_active(tx_active1), .tx_done(tx_done1),
        .serial_tx(serial_tx1), .serial_rx(serial_rx1),
        .rx_read(rx_read1), .rx_data(rx_data1),
        .rx_valid(rx_valid1),
        .parity_error(), .framing_error(), .overrun_error()
    );

    device d2 (
        .clk(clk), .reset(reset),
        .baud_select(baud_select),
        .data_length(data_length),
        .parity_select(parity_select),
        .tx_start(tx_start2), .tx_data(tx_data2),
        .cts(cts2), .rts(rts2),
        .tx_active(tx_active2), .tx_done(tx_done2),
        .serial_tx(serial_tx2), .serial_rx(serial_rx2),
        .rx_read(rx_read2), .rx_data(rx_data2),
        .rx_valid(rx_valid2),
        .parity_error(), .framing_error(), .overrun_error()
    );

    initial begin
        clk = 0; // Start clock
        forever #5 clk = ~clk; // Toggle clock
    end

    task reset_uart; // Reset UARTs
    begin
        reset = 1; // Apply reset
        tx_start1 = 0; // Clear TX1 start
        tx_start2 = 0; // Clear TX2 start
        rx_read1 = 0; // Clear RX1 read
        rx_read2 = 0; // Clear RX2 read
        flow_control_en = 0; // Disable flow control
        repeat(3) @(posedge clk); // Wait 3 clocks
        reset = 0; // Release reset
        @(posedge clk); // Wait one clock
    end
    endtask

    task send_byte; // Send test byte
    begin
        tx_data1 = TEST_DATA; // Load test byte
        @(negedge clk); // Wait for falling edge
        tx_start1 = 1; // Start TX
        @(negedge clk); // Wait for falling edge
        tx_start1 = 0; // Stop TX start
    end
    endtask

    initial begin
        errors = 0; // Clear errors
        baud_select = 2'b11; // Set baud rate
        data_length = 2'b11; // Set data length
        parity_select = 2'b00; // Disable parity
        tx_data1 = 0; // Clear TX1 data
        tx_data2 = 0; // Clear TX2 data
        tx_start1 = 0; // Clear TX1 start
        tx_start2 = 0; // Clear TX2 start
        rx_read1 = 0; // Clear RX1 read
        rx_read2 = 0; // Clear RX2 read
        flow_control_en = 0; // Disable flow control
        reset = 1; // Apply reset

        $dumpfile("uart.vcd"); // Create VCD file
        $dumpvars(0, uart_tb); // Save waveforms

        reset_uart; // Reset UARTs
        parity_select = 2'b00; // Use no parity

        $display(""); // Print blank line
        $display("TEST 1: NORMAL 16x OVERSAMPLING"); 
        send_byte; // Send test byte
        wait(rx_valid2); // Wait for RX data
        $display("TX DATA = %h", TEST_DATA); // Print TX data
        $display("RX DATA = %h", rx_data2); // Print RX data

        if(rx_data2 === TEST_DATA) // Check RX data
            $display("NORMAL OVERSAMPLING PASS"); // Print pass
        else begin
            $display("NORMAL OVERSAMPLING FAIL"); // Print fail
            errors = errors + 1; // Add error
        end

        @(negedge clk); // Wait for falling edge
        rx_read2 = 1; // Read RX data
        @(negedge clk); // Wait for falling edge
        rx_read2 = 0; // Stop RX read
        $display("TEST 2: PARITY"); 

        reset_uart; // Reset UARTs
        parity_select = 2'b01; // Select even parity
        expected_parity = ^TEST_DATA; // Calculate even parity

        $display(""); 
        $display("EVEN PARITY"); 
        $display("Expected parity = %b", expected_parity); 

        send_byte; // Send test byte
        wait(d1.tx_state == d1.PARITY); // Wait for parity state
        wait((d1.tx_state == d1.PARITY) &&
             (d1.tx_sample_count == 4'd1)); // Wait for parity bit
        #1; 
        $display("Actual parity   = %b", serial_tx1); 

        if(serial_tx1 === expected_parity) // Check parity
            $display("EVEN PARITY PASS"); // Print pass
        else begin
            $display("EVEN PARITY FAIL"); // Print fail
            errors = errors + 1; // Add error
        end

        wait(rx_valid2); // Wait for RX data
        @(negedge clk); // Wait for falling edge
        rx_read2 = 1; // Read RX data
        @(negedge clk); // Wait for falling edge
        rx_read2 = 0; // Stop RX read

        reset_uart; // Reset UARTs
        parity_select = 2'b10; // Select odd parity
        expected_parity = ~(^TEST_DATA); // Calculate odd parity

        $display(""); // Print blank line
        $display("ODD PARITY"); // Print test name
        $display("Expected parity = %b", expected_parity); // Print expected parity

        send_byte; // Send test byte
        wait(d1.tx_state == d1.PARITY); // Wait for parity state
        wait((d1.tx_state == d1.PARITY) &&
             (d1.tx_sample_count == 4'd1)); // Wait for parity bit
        #1; // Wait one time unit
        $display("Actual parity   = %b", serial_tx1); // Print actual parity

        if(serial_tx1 === expected_parity) // Check parity
            $display("ODD PARITY PASS"); // Print pass
        else begin
            $display("ODD PARITY FAIL"); // Print fail
            errors = errors + 1; // Add error
        end

        wait(rx_valid2); // Wait for RX data
        @(negedge clk); // Wait for falling edge
        rx_read2 = 1; // Read RX data
        @(negedge clk); // Wait for falling edge
        rx_read2 = 0; // Stop RX read

        reset_uart; // Reset UARTs
        parity_select = 2'b00; // Disable parity
        $display("TEST 3: DELIBERATELY BAD OVERSAMPLING"); // Print test name
        $display("Normal RX sample count : 0 to 15"); // Print normal count
        $display("Faulty RX sample count : 0 to 11"); // Print faulty count
        $display("Watch rx_sample_count"); // Print signal name
        $display("and rx_data in GTKWave."); // Print signal name
        $display("========================================"); // Print separator
        tx_data1 = TEST_DATA; // Load test byte
        @(negedge clk); // Wait for falling edge
        tx_start1 = 1; // Start TX
        @(negedge clk); // Wait for falling edge
        tx_start1 = 0; // Stop TX start
        wait(d2.rx_state != d2.IDLE); // Wait for RX start
        $display("Forcing D2 RX sampling counter early..."); // Print force status
        force d2.rx_sample_count = 4'd11; // Force counter to 11
        repeat(20) @(posedge clk); // Hold force
        release d2.rx_sample_count; // Release counter
        $display("Released RX counter force."); // Print release status
        repeat(500) @(posedge clk); // Wait for RX result

        if(rx_valid2) begin // Check RX result
            $display("Faulty RX DATA = %h", rx_data2); // Print RX data
            if(rx_data2 !== TEST_DATA) // Check data mismatch
                $display("EXPECTED: DATA WAS MISREAD"); // Print mismatch
            else
                $display("Data happened to remain correct."); // Print match
        end
        else begin
            $display("RX did not produce valid data."); // Print no data
        end

        reset_uart; // Reset UARTs
        parity_select = 2'b00; // Disable parity
        flow_control_en = 1; // Enable flow control

        $display(""); // Print blank line
        $display("========================================"); // Print separator
        $display("TEST 4: RTS / CTS"); // Print test name
        $display("========================================"); // Print separator

        for(i = 0; i < 16; i = i + 1) begin // Send 16 bytes
            @(negedge clk); // Wait for falling edge
            tx_data1 = 8'hC0 + i; // Load byte
            tx_start1 = 1; // Start TX
            @(negedge clk); // Wait for falling edge
            tx_start1 = 0; // Stop TX start
        end

        wait(d2.rx_count == 15); // Wait for FIFO count
        repeat(20) @(posedge d1.sample_tick); // Wait for flow control
        $display("D2 RX FIFO = %0d", d2.rx_count); // Print RX count
        $display("RTS2       = %b", rts2); // Print RTS
        $display("CTS1       = %b", cts1); // Print CTS

        if(rts2 === 1'b1) // Check RTS
            $display("RTS HIGH PASS"); 
        else begin
            $display("RTS HIGH FAIL");
            errors = errors + 1; // Add error
        end

        if(cts1 === 1'b1) // Check CTS
            $display("CTS HIGH PASS"); // Print pass
        else begin
            $display("CTS HIGH FAIL"); // Print fail
            errors = errors + 1; // Add error
        end

        tx_count_before_pause = d1.tx_count; // Save TX count
        repeat(32) @(posedge d1.sample_tick); // Wait during pause

        if(d1.tx_count === tx_count_before_pause) // Check TX pause
            $display("CTS PAUSE PASS"); // Print pass
        else begin
            $display("CTS PAUSE FAIL"); // Print fail
            errors = errors + 1; // Add error
        end

        @(negedge clk); // Wait for falling edge
        rx_read2 = 1; // Read one byte
        @(negedge clk); // Wait for falling edge
        rx_read2 = 0; // Stop RX read
        @(posedge clk); // Wait one clock

        $display("After reading one byte:"); // Print status
        $display("D2 RX FIFO = %0d", d2.rx_count); // Print RX count
        $display("RTS2       = %b", rts2); // Print RTS
        $display("CTS1       = %b", cts1); // Print CTS

        if(rts2 === 1'b0) // Check RTS low
            $display("RTS LOW PASS"); // Print pass
        else begin
            $display("RTS LOW FAIL"); // Print fail
            errors = errors + 1; // Add error
        end

        if(cts1 === 1'b0) // Check CTS low
            $display("CTS LOW PASS"); // Print pass
        else begin
            $display("CTS LOW FAIL"); // Print fail
            errors = errors + 1; // Add error
        end
        if(errors == 0) // Check errors
            $display("ALL TESTS PASSED"); 
        else
            $display("TESTBENCH FINISHED WITH %0d ERROR(S)", errors);
        #100; // Wait before finish
        $finish; // End simulation
    end
endmodule
