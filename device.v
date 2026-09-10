// UART device
// Uses 16x oversampling for all baud settings.
module device(
    input clk,
    input reset,
    input [1:0] baud_select,
    input [1:0] data_length,
    input [1:0] parity_select,       // 00=none, 01=even, 10=odd
    input tx_start,
    input [7:0] tx_data,
    input cts,                        // active-low: 0=may send
    output rts,                       // active-low: 0=receiver ready
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

    parameter PARITY_NONE = 2'b00;
    parameter PARITY_EVEN = 2'b01;
    parameter PARITY_ODD  = 2'b10;

    parameter IDLE   = 3'd0;
    parameter START  = 3'd1;
    parameter DATA   = 3'd2;
    parameter PARITY = 3'd3;
    parameter STOP   = 3'd4;

    // FIFO memory for transmit and receive data.
    reg [7:0] tx_fifo [0:15];
    reg [7:0] rx_fifo [0:15];

    reg [3:0] tx_wr_ptr, tx_rd_ptr;
    reg [3:0] rx_wr_ptr, rx_rd_ptr;
    reg [4:0] tx_count, rx_count;

    assign rx_valid = (rx_count != 0);                     // RX has at least one byte.
    assign rx_data  = (rx_count != 0) ? rx_fifo[rx_rd_ptr] : 8'h00; // Show front RX byte.

    assign rts = (rx_count < 5'd15) ? 1'b0 : 1'b1;        // Stop sender when RX is nearly full.

    // Holds how many data bits to send/receive.
    reg [3:0] num_data_bits;

    always @(*) begin
        case (data_length)
            2'b00: num_data_bits = 5;                      // 5-bit data
            2'b01: num_data_bits = 6;                      // 6-bit data
            2'b10: num_data_bits = 7;                      // 7-bit data
            default: num_data_bits = 8;                    // 8-bit data
        endcase
    end

    // Generates the 16x sample tick.
    reg [7:0] baud_count;
    reg sample_tick;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            baud_count <= 0;                               // Clear divider counter.
            sample_tick <= 0;                              // No tick during reset.
        end
        else begin
            sample_tick <= 0;                              // Default tick low.

            case (baud_select)
                2'b00: begin
                    if (baud_count == 8'd1) begin
                        baud_count <= 0;                   // Restart counter.
                        sample_tick <= 1;                  // Create sample tick.
                    end
                    else baud_count <= baud_count + 1'b1;  // Keep counting.
                end

                2'b01: begin
                    if (baud_count == 8'd3) begin
                        baud_count <= 0;                   // Restart counter.
                        sample_tick <= 1;                  // Create sample tick.
                    end
                    else baud_count <= baud_count + 1'b1;  // Keep counting.
                end

                2'b10: begin
                    if (baud_count == 8'd7) begin
                        baud_count <= 0;                   // Restart counter.
                        sample_tick <= 1;                  // Create sample tick.
                    end
                    else baud_count <= baud_count + 1'b1;  // Keep counting.
                end

                2'b11: begin
                    if (baud_count == 8'd15) begin
                        baud_count <= 0;                   // Restart counter.
                        sample_tick <= 1;                  // Create sample tick.
                    end
                    else baud_count <= baud_count + 1'b1;  // Keep counting.
                end

                default: begin
                    baud_count <= 0;                       // Safe fallback.
                end
            endcase
        end
    end

    // Transmitter state and working registers.
    reg [2:0] tx_state;
    reg [2:0] tx_bit;
    reg [7:0] tx_reg;
    reg tx_parity;
    reg [3:0] tx_sample_count;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            tx_wr_ptr <= 0;                                // Reset TX write pointer.
            tx_rd_ptr <= 0;                                // Reset TX read pointer.
            tx_count <= 0;                                 // TX FIFO empty.
            tx_state <= IDLE;                              // TX idle.
            tx_bit <= 0;                                   // Clear bit index.
            tx_reg <= 0;                                   // Clear shift register.
            tx_parity <= 0;                                // Clear parity bit.
            tx_sample_count <= 0;                          // Clear sample counter.
            tx_active <= 0;                                // TX not busy.
            tx_done <= 0;                                  // No done pulse.
            serial_tx <= 1'b1;                             // UART line idle high.
        end
        else begin
            tx_done <= 0;                                  // Done is only a pulse.

            if (tx_start && (tx_count < 16)) begin
                tx_fifo[tx_wr_ptr] <= tx_data;             // Push new byte into TX FIFO.
                tx_wr_ptr <= tx_wr_ptr + 1'b1;             // Move write pointer.
            end

            if (sample_tick) begin
                case (tx_state)

                    IDLE: begin
                        serial_tx <= 1'b1;                 // Keep line idle high.
                        tx_active <= 1'b0;                 // Not transmitting.
                        tx_sample_count <= 0;              // Clear sample counter.

                        if ((tx_count != 0) && (cts == 1'b0)) begin
                            tx_reg <= tx_fifo[tx_rd_ptr];  // Load next byte.
                            tx_rd_ptr <= tx_rd_ptr + 1'b1; // Move read pointer.

                            case (parity_select)
                                PARITY_EVEN: begin
                                    case (num_data_bits)
                                        5: tx_parity <= ^tx_fifo[tx_rd_ptr][4:0];   // Even parity for 5 bits.
                                        6: tx_parity <= ^tx_fifo[tx_rd_ptr][5:0];   // Even parity for 6 bits.
                                        7: tx_parity <= ^tx_fifo[tx_rd_ptr][6:0];   // Even parity for 7 bits.
                                        default: tx_parity <= ^tx_fifo[tx_rd_ptr][7:0]; // Even parity for 8 bits.
                                    endcase
                                end

                                PARITY_ODD: begin
                                    case (num_data_bits)
                                        5: tx_parity <= ~(^tx_fifo[tx_rd_ptr][4:0]);   // Odd parity for 5 bits.
                                        6: tx_parity <= ~(^tx_fifo[tx_rd_ptr][5:0]);   // Odd parity for 6 bits.
                                        7: tx_parity <= ~(^tx_fifo[tx_rd_ptr][6:0]);   // Odd parity for 7 bits.
                                        default: tx_parity <= ~(^tx_fifo[tx_rd_ptr][7:0]); // Odd parity for 8 bits.
                                    endcase
                                end

                                default: tx_parity <= 1'b0; // No parity used.
                            endcase

                            serial_tx <= 1'b0;             // Send start bit.
                            tx_active <= 1'b1;             // Mark TX busy.
                            tx_bit <= 0;                   // Start from bit 0.
                            tx_sample_count <= 0;          // Reset sample counter.
                            tx_state <= START;             // Go to START state.
                        end
                    end

                    START: begin
                        serial_tx <= 1'b0;                 // Hold start bit low.

                        if (tx_sample_count == 4'd15) begin
                            serial_tx <= tx_reg[0];        // Put first data bit on line.
                            tx_sample_count <= 0;          // Reset counter for next state.
                            tx_bit <= 0;                   // Still on first data bit.
                            tx_state <= DATA;              // Go to DATA state.
                        end
                        else begin
                            tx_sample_count <= tx_sample_count + 1'b1; // Keep waiting.
                        end
                    end

                    DATA: begin
                        serial_tx <= tx_reg[0];            // Drive current data bit.

                        if (tx_sample_count == 4'd15) begin
                            tx_sample_count <= 0;          // Finished one bit time.
                            tx_reg <= tx_reg >> 1;         // Shift to next bit.

                            if (tx_bit == num_data_bits - 1) begin
                                if (parity_select == PARITY_NONE)
                                    tx_state <= STOP;      // No parity, go to stop.
                                else
                                    tx_state <= PARITY;    // Send parity next.
                            end
                            else begin
                                tx_bit <= tx_bit + 1'b1;   // Move to next data bit.
                            end
                        end
                        else begin
                            tx_sample_count <= tx_sample_count + 1'b1; // Stay on this bit.
                        end
                    end

                    PARITY: begin
                        serial_tx <= tx_parity;            // Drive parity bit.

                        if (tx_sample_count == 4'd15) begin
                            tx_sample_count <= 0;          // Done with parity bit.
                            tx_state <= STOP;              // Move to stop bit.
                        end
                        else begin
                            tx_sample_count <= tx_sample_count + 1'b1; // Keep parity on line.
                        end
                    end

                    STOP: begin
                        serial_tx <= 1'b1;                 // Drive stop bit high.

                        if (tx_sample_count == 4'd15) begin
                            tx_sample_count <= 0;          // Stop bit finished.
                            tx_state <= IDLE;              // Return to idle.
                            tx_active <= 1'b0;             // TX no longer busy.
                            tx_done <= 1'b1;               // Pulse done.
                        end
                        else begin
                            tx_sample_count <= tx_sample_count + 1'b1; // Keep stop bit high.
                        end
                    end

                    default: begin
                        tx_state <= IDLE;                  // Recover to idle state.
                        tx_active <= 1'b0;                 // Clear busy flag.
                        serial_tx <= 1'b1;                 // Keep UART line idle.
                        tx_sample_count <= 0;              // Reset counter.
                    end
                endcase
            end

            case ({
                (tx_start && (tx_count < 16)),
                ((tx_state == IDLE) && sample_tick &&
                 (tx_count != 0) && (cts == 1'b0))
            })
                2'b10: tx_count <= tx_count + 1'b1;       // FIFO push only.
                2'b01: tx_count <= tx_count - 1'b1;       // FIFO pop only.
                default: tx_count <= tx_count;            // No count change.
            endcase
        end
    end

    // Receiver state and working registers.
    reg [2:0] rx_state;
    reg [2:0] rx_bit;
    reg [7:0] rx_reg;
    reg [3:0] rx_sample_count;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            rx_wr_ptr <= 0;                                // Reset RX write pointer.
            rx_rd_ptr <= 0;                                // Reset RX read pointer.
            rx_count <= 0;                                 // RX FIFO empty.
            rx_state <= IDLE;                              // RX idle.
            rx_bit <= 0;                                   // Clear bit index.
            rx_reg <= 0;                                   // Clear receive register.
            rx_sample_count <= 0;                          // Clear sample counter.
            parity_error <= 0;                             // Clear parity error.
            framing_error <= 0;                            // Clear framing error.
            overrun_error <= 0;                            // Clear overrun error.
        end
        else begin
            if (rx_read && (rx_count != 0)) begin
                rx_rd_ptr <= rx_rd_ptr + 1'b1;             // Pop one RX byte.
            end

            if (sample_tick) begin
                case (rx_state)

                    IDLE: begin
                        rx_sample_count <= 0;              // Reset counter while idle.

                        if (serial_rx == 1'b0) begin
                            rx_reg <= 0;                   // Clear old data.
                            rx_bit <= 0;                   // Start at bit 0.
                            rx_sample_count <= 0;          // Start counting samples.
                            rx_state <= START;             // Possible start bit seen.
                        end
                    end

                    START: begin
                        if (rx_sample_count == 4'd7) begin
                            if (serial_rx == 1'b0) begin
                                rx_sample_count <= 0;      // Valid start bit.
                                rx_bit <= 0;               // Prepare for data bits.
                                rx_state <= DATA;          // Move to data receive.
                            end
                            else begin
                                rx_sample_count <= 0;      // Noise or false start.
                                rx_state <= IDLE;          // Go back idle.
                            end
                        end
                        else begin
                            rx_sample_count <= rx_sample_count + 1'b1; // Wait to center of start bit.
                        end
                    end

                    DATA: begin
                        if (rx_sample_count == 4'd15) begin
                            rx_reg[rx_bit] <= serial_rx;   // Sample one data bit.
                            rx_sample_count <= 0;          // Reset for next bit.

                            if (rx_bit == num_data_bits - 1) begin
                                if (parity_select == PARITY_NONE)
                                    rx_state <= STOP;      // No parity, next is stop.
                                else
                                    rx_state <= PARITY;    // Check parity next.
                            end
                            else begin
                                rx_bit <= rx_bit + 1'b1;   // Move to next bit.
                            end
                        end
                        else begin
                            rx_sample_count <= rx_sample_count + 1'b1; // Wait full bit time.
                        end
                    end

                    PARITY: begin
                        if (rx_sample_count == 4'd15) begin
                            rx_sample_count <= 0;          // Parity bit time reached.

                            case (parity_select)
                                PARITY_EVEN: begin
                                    case (num_data_bits)
                                        5: begin
                                            if (serial_rx == ^rx_reg[4:0])
                                                rx_state <= STOP;      // Parity correct.
                                            else begin
                                                parity_error <= 1'b1;  // Parity failed.
                                                rx_state <= IDLE;      // Drop frame.
                                            end
                                        end
                                        6: begin
                                            if (serial_rx == ^rx_reg[5:0])
                                                rx_state <= STOP;      // Parity correct.
                                            else begin
                                                parity_error <= 1'b1;  // Parity failed.
                                                rx_state <= IDLE;      // Drop frame.
                                            end
                                        end
                                        7: begin
                                            if (serial_rx == ^rx_reg[6:0])
                                                rx_state <= STOP;      // Parity correct.
                                            else begin
                                                parity_error <= 1'b1;  // Parity failed.
                                                rx_state <= IDLE;      // Drop frame.
                                            end
                                        end
                                        default: begin
                                            if (serial_rx == ^rx_reg[7:0])
                                                rx_state <= STOP;      // Parity correct.
                                            else begin
                                                parity_error <= 1'b1;  // Parity failed.
                                                rx_state <= IDLE;      // Drop frame.
                                            end
                                        end
                                    endcase
                                end

                                PARITY_ODD: begin
                                    case (num_data_bits)
                                        5: begin
                                            if (serial_rx == ~(^rx_reg[4:0]))
                                                rx_state <= STOP;      // Parity correct.
                                            else begin
                                                parity_error <= 1'b1;  // Parity failed.
                                                rx_state <= IDLE;      // Drop frame.
                                            end
                                        end
                                        6: begin
                                            if (serial_rx == ~(^rx_reg[5:0]))
                                                rx_state <= STOP;      // Parity correct.
                                            else begin
                                                parity_error <= 1'b1;  // Parity failed.
                                                rx_state <= IDLE;      // Drop frame.
                                            end
                                        end
                                        7: begin
                                            if (serial_rx == ~(^rx_reg[6:0]))
                                                rx_state <= STOP;      // Parity correct.
                                            else begin
                                                parity_error <= 1'b1;  // Parity failed.
                                                rx_state <= IDLE;      // Drop frame.
                                            end
                                        end
                                        default: begin
                                            if (serial_rx == ~(^rx_reg[7:0]))
                                                rx_state <= STOP;      // Parity correct.
                                            else begin
                                                parity_error <= 1'b1;  // Parity failed.
                                                rx_state <= IDLE;      // Drop frame.
                                            end
                                        end
                                    endcase
                                end

                                default: rx_state <= STOP; // No parity mode safety path.
                            endcase
                        end
                        else begin
                            rx_sample_count <= rx_sample_count + 1'b1; // Wait to parity sample point.
                        end
                    end

                    STOP: begin
                        if (rx_sample_count == 4'd15) begin
                            rx_sample_count <= 0;          // Stop bit time reached.

                            if (serial_rx == 1'b1) begin
                                if (rx_count < 16) begin
                                    rx_fifo[rx_wr_ptr] <= rx_reg;      // Store received byte.
                                    rx_wr_ptr <= rx_wr_ptr + 1'b1;     // Move write pointer.
                                end
                                else begin
                                    overrun_error <= 1'b1;             // RX FIFO full.
                                end
                            end
                            else begin
                                framing_error <= 1'b1;                 // Stop bit was bad.
                            end

                            rx_state <= IDLE;                          // Done with frame.
                        end
                        else begin
                            rx_sample_count <= rx_sample_count + 1'b1; // Wait to stop sample point.
                        end
                    end

                    default: begin
                        rx_state <= IDLE;                  // Recover to idle.
                        rx_sample_count <= 0;              // Reset counter.
                    end
                endcase
            end

            case ({
                ((rx_state == STOP) && sample_tick &&
                 (rx_sample_count == 4'd15) &&
                 (serial_rx == 1'b1) && (rx_count < 16)),
                (rx_read && (rx_count != 0))
            })
                2'b10: rx_count <= rx_count + 1'b1;       // FIFO push only.
                2'b01: rx_count <= rx_count - 1'b1;       // FIFO pop only.
                default: rx_count <= rx_count;            // No count change.
            endcase
        end
    end

endmodule

