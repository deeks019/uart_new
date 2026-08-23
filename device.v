module device(
    input clk,
    input reset,
    input [1:0] baud_select,
    input [1:0] data_length,
    input tx_start,
    input [7:0] tx_data,

    output reg tx_active,
    output reg tx_done,
    output reg serial_tx,

    input serial_rx,
    input rx_read,
    output [7:0] rx_data,
    output rx_valid,
    output reg parity_error,
    output reg framing_error,
    output reg overrun_error
);

    reg [7:0] tx_fifo [0:15];
    reg [7:0] rx_fifo [0:15];

    reg [3:0] tx_wr_ptr, tx_rd_ptr;
    reg [3:0] rx_wr_ptr, rx_rd_ptr;

    reg [4:0] tx_count, rx_count;

    assign rx_valid = (rx_count != 0);
    assign rx_data  = (rx_count != 0) ? rx_fifo[rx_rd_ptr] : 8'h00;

    // Using parameter so states can be overridden if needed by external code
    parameter IDLE   = 3'd0;
    parameter START  = 3'd1;
    parameter DATA   = 3'd2;
    parameter PARITY = 3'd3;
    parameter STOP   = 3'd4;

    reg [2:0] tx_state, rx_state;
    reg [2:0] tx_bit, rx_bit;
    reg [3:0] num_data_bits;

    reg [7:0] tx_reg, rx_reg;
    reg tx_parity;

    reg [7:0] baud_count;
    reg baud_tick;

    always @(*) begin
        case (data_length)
            2'b00: num_data_bits = 5;
            2'b01: num_data_bits = 6;
            2'b10: num_data_bits = 7;
            2'b11: num_data_bits = 8;
            default: num_data_bits = 8;
        endcase
    end

    // Baud divider generates tick at different rates based on baud_select
    // Used to synchronize TX/RX timing independent of main clock
    // 00=fastest, 11=slowest
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            baud_count <= 0;
            baud_tick  <= 0;
        end
        else begin
            baud_tick <= 0;

            case (baud_select)
                2'b00: begin
                    if (baud_count == 8'd1) begin
                        baud_count <= 0;
                        baud_tick <= 1;
                    end
                    else
                        baud_count <= baud_count + 1;
                end

                2'b01: begin
                    if (baud_count == 8'd3) begin
                        baud_count <= 0;
                        baud_tick <= 1;
                    end
                    else
                        baud_count <= baud_count + 1;
                end

                2'b10: begin
                    if (baud_count == 8'd7) begin
                        baud_count <= 0;
                        baud_tick <= 1;
                    end
                    else
                        baud_count <= baud_count + 1;
                end

                2'b11: begin
                    if (baud_count == 8'd15) begin
                        baud_count <= 0;
                        baud_tick <= 1;
                    end
                    else
                        baud_count <= baud_count + 1;
                end
            endcase
        end
    end

    // TX FIFO + TX state machine
    // Used to buffer outgoing bytes and send one frame at a time
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            tx_wr_ptr  <= 0;
            tx_rd_ptr  <= 0;
            tx_count   <= 0;

            tx_state   <= IDLE;
            tx_bit     <= 0;
            tx_reg     <= 0;
            tx_parity  <= 0;

            tx_active  <= 0;
            tx_done    <= 0;
            serial_tx  <= 1;
        end
        else begin
            tx_done <= 0;

            // Write data to TX FIFO when tx_start pulsed and FIFO not full
            // Allows buffering multiple bytes for sequential transmission
            if (tx_start && (tx_count < 16)) begin
                tx_fifo[tx_wr_ptr] <= tx_data;
                tx_wr_ptr <= tx_wr_ptr + 1'b1;
            end

            // Start transmitting when idle and data available
            // Takes next byte from FIFO and calculates its parity
            if ((tx_state == IDLE) && baud_tick && (tx_count != 0)) begin
                tx_reg <= tx_fifo[tx_rd_ptr];
                tx_rd_ptr <= tx_rd_ptr + 1'b1;

                case (num_data_bits)
                    5: tx_parity <= ^tx_fifo[tx_rd_ptr][4:0];
                    6: tx_parity <= ^tx_fifo[tx_rd_ptr][5:0];
                    7: tx_parity <= ^tx_fifo[tx_rd_ptr][6:0];
                    default: tx_parity <= ^tx_fifo[tx_rd_ptr][7:0];
                endcase

                tx_bit <= 0;
                tx_active <= 1;
                serial_tx <= 0;
                tx_state <= START;
            end
            else if (baud_tick) begin
                case (tx_state)

                    IDLE: begin
                        tx_active <= 0;
                        serial_tx <= 1;
                    end

                    START: begin
                        // First data bit is sent immediately after start bit
                        serial_tx <= tx_reg[0];
                        tx_reg <= tx_reg >> 1;
                        tx_bit <= 1;
                        tx_state <= DATA;
                    end

                    DATA: begin
                        // Shift and send each data bit one per baud tick
                        serial_tx <= tx_reg[0];
                        tx_reg <= tx_reg >> 1;

                        if (tx_bit == num_data_bits - 1) begin
                            tx_state <= PARITY;
                        end
                        else begin
                            tx_bit <= tx_bit + 1;
                        end
                    end

                    PARITY: begin
                        // Parity bit sent after all data bits for error detection
                        serial_tx <= tx_parity;
                        tx_state <= STOP;
                    end

                    STOP: begin
                        // Stop bit signals end of frame, must be high
                        serial_tx <= 1;
                        tx_state <= IDLE;
                        tx_active <= 0;
                        tx_done <= 1;
                    end

                    default: begin
                        tx_state <= IDLE;
                        tx_active <= 0;
                        serial_tx <= 1;
                    end

                endcase
            end

            // Update TX FIFO count (handles simultaneous read/write)
            // If byte added and removed same clock, count stays same
            case ({(tx_start && (tx_count < 16)),
                   ((tx_state == IDLE) && baud_tick && (tx_count != 0))})
                2'b10: tx_count <= tx_count + 1'b1;
                2'b01: tx_count <= tx_count - 1'b1;
                default: tx_count <= tx_count;
            endcase
        end
    end

    // RX state machine + RX FIFO
    // Used to receive serial frames and buffer incoming bytes
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            rx_wr_ptr <= 0;
            rx_rd_ptr <= 0;
            rx_count  <= 0;

            rx_state  <= IDLE;
            rx_bit    <= 0;
            rx_reg    <= 0;

            parity_error  <= 0;
            framing_error <= 0;
            overrun_error <= 0;

        end
        else begin

            // Remove oldest byte when user reads
            // Prevents re-reading same data
            if (rx_read && (rx_count != 0))
                rx_rd_ptr <= rx_rd_ptr + 1'b1;

            if (baud_tick) begin
                case (rx_state)

                    IDLE: begin
                        // Waiting for start bit (high to low transition on serial_rx)
                        if (serial_rx == 0) begin
                            rx_reg <= 0;
                            rx_bit <= 0;
                            rx_state <= START;
                        end
                    end

                    START: begin
                        // First data bit arrives one baud tick after start bit detected
                        // Store it at position 0 (LSB first in UART)
                        rx_reg[0] <= serial_rx;

                        if (num_data_bits == 1) begin
                            rx_bit <= 0;
                            rx_state <= PARITY;
                        end
                        else begin
                            rx_bit <= 1;
                            rx_state <= DATA;
                        end
                    end

                    DATA: begin
                        // UART sends LSB first, so store at actual bit position
                        // This simplifies reassembly later
                        rx_reg[rx_bit] <= serial_rx;

                        if (rx_bit == num_data_bits - 1)
                            rx_state <= PARITY;
                        else
                            rx_bit <= rx_bit + 1'b1;
                    end

                    PARITY: begin
                        // Parity check verifies data integrity
                        // XOR of data bits should equal received parity bit
                        case (num_data_bits)
                            5: if (serial_rx == ^rx_reg[4:0])
                                   rx_state <= STOP;
                               else begin
                                   parity_error <= 1;
                                   rx_state <= IDLE;
                               end

                            6: if (serial_rx == ^rx_reg[5:0])
                                   rx_state <= STOP;
                               else begin
                                   parity_error <= 1;
                                   rx_state <= IDLE;
                               end

                            7: if (serial_rx == ^rx_reg[6:0])
                                   rx_state <= STOP;
                               else begin
                                   parity_error <= 1;
                                   rx_state <= IDLE;
                               end

                            default: if (serial_rx == ^rx_reg[7:0])
                                         rx_state <= STOP;
                                     else begin
                                         parity_error <= 1;
                                         rx_state <= IDLE;
                                     end
                        endcase
                    end

                    STOP: begin
                        // Valid frame if stop bit is high (normal state)
                        // Low stop bit indicates framing error
                        if (serial_rx == 1) begin
                            if (rx_count < 16) begin
                                rx_fifo[rx_wr_ptr] <= rx_reg;
                                rx_wr_ptr <= rx_wr_ptr + 1'b1;
                            end
                            else begin
                                // FIFO full, data lost - overrun error
                                overrun_error <= 1;
                            end
                        end
                        else begin
                            // Stop bit should be high but was low
                            framing_error <= 1;
                        end

                        rx_state <= IDLE;
                    end

                    default: rx_state <= IDLE;

                endcase
            end

            // Update RX FIFO count (handles simultaneous receive/read)
            // If byte received and read same clock, count stays same
            case ({((rx_state == STOP) && baud_tick &&
                    (serial_rx == 1) && (rx_count < 16)),
                   (rx_read && (rx_count != 0))})
                2'b10: rx_count <= rx_count + 1'b1;
                2'b01: rx_count <= rx_count - 1'b1;
                default: rx_count <= rx_count;
            endcase
        end
    end

endmodule
