// UART device module
module device(
    input clk,
    input reset,
    input [1:0] baud_select,
    input [1:0] data_length,
    // Choose parity: 00 = none, 01 = even, 10 = odd
    input [1:0] parity_select,          // 00 = none, 01 = even, 10 = odd
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

    // Parity mode names
    parameter PARITY_NONE = 2'b00;
    parameter PARITY_EVEN = 2'b01;
    parameter PARITY_ODD  = 2'b10;

    reg [7:0] tx_fifo [0:15];
    reg [7:0] rx_fifo [0:15];

    reg [3:0] tx_wr_ptr, tx_rd_ptr;
    reg [3:0] rx_wr_ptr, rx_rd_ptr;

    reg [4:0] tx_count, rx_count;

    assign rx_valid = (rx_count != 0);
    assign rx_data = (rx_count != 0) ? rx_fifo[rx_rd_ptr] : 8'h00;

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

    reg [3:0] rx_oversample_count;
    reg [4:0] rx_sample_ones;

    // 16x RX oversampling is possible at the slowest baud setting.
    // At 100 MHz, baud_select 2'b11 gives 16 clock cycles per UART bit.
    // The RX uses those 16 clocks as 16 sample positions.
    wire rx_oversampling_active = (baud_select == 2'b11);

    reg [7:0] baud_count;
    reg baud_tick;

    always @(*) begin
        // Select how many data bits are used: 5, 6, 7, or 8
        case (data_length)
            2'b00: num_data_bits = 5;
            2'b01: num_data_bits = 6;
            2'b10: num_data_bits = 7;
            2'b11: num_data_bits = 8;
            default: num_data_bits = 8;
        endcase
    end

    // Make a baud tick after a fixed number of clocks
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            baud_count <= 0;
            baud_tick  <= 0;
        end
        else begin
            baud_tick <= 0;

            // Select how often baud_tick is generated
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

    // Transmitter: sends data one bit at a time
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

            // Put new TX data into the FIFO when requested
            if (tx_start && (tx_count < 16)) begin
                tx_fifo[tx_wr_ptr] <= tx_data;
                tx_wr_ptr <= tx_wr_ptr + 1'b1;
            end

            if ((tx_state == IDLE) && baud_tick && (tx_count != 0)) begin
                tx_reg <= tx_fifo[tx_rd_ptr];
                tx_rd_ptr <= tx_rd_ptr + 1'b1;

                // Calculate the parity bit for the data being sent.
                case (parity_select)
                    PARITY_EVEN: begin
                        case (num_data_bits)
                            5: tx_parity <= ^tx_fifo[tx_rd_ptr][4:0];
                            6: tx_parity <= ^tx_fifo[tx_rd_ptr][5:0];
                            7: tx_parity <= ^tx_fifo[tx_rd_ptr][6:0];
                            default: tx_parity <= ^tx_fifo[tx_rd_ptr][7:0];
                        endcase
                    end

                    PARITY_ODD: begin
                        case (num_data_bits)
                            5: tx_parity <= ~(^tx_fifo[tx_rd_ptr][4:0]);
                            6: tx_parity <= ~(^tx_fifo[tx_rd_ptr][5:0]);
                            7: tx_parity <= ~(^tx_fifo[tx_rd_ptr][6:0]);
                            default: tx_parity <= ~(^tx_fifo[tx_rd_ptr][7:0]);
                        endcase
                    end

                    default: tx_parity <= 0;  // No parity
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

                    // Send the start bit first, then begin sending data.
                    START: begin
                        serial_tx <= tx_reg[0];
                        tx_reg <= tx_reg >> 1;
                        tx_bit <= 1;
                        tx_state <= DATA;
                    end

                    // Send the data bits one by one.
                    DATA: begin                        serial_tx <= tx_reg[0];
                        tx_reg <= tx_reg >> 1;

                        if (tx_bit == num_data_bits - 1) begin
                            if (parity_select == PARITY_NONE)
                                tx_state <= STOP;
                            else
                                tx_state <= PARITY;
                        end
                        else begin
                            tx_bit <= tx_bit + 1;
                        end
                    end

                    // Send the calculated parity bit.
                    PARITY: begin                        serial_tx <= tx_parity;
                        tx_state <= STOP;
                    end

                    // Stop bit is always high.
                    STOP: begin                        serial_tx <= 1;
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

            case ({(tx_start && (tx_count < 16)),
                   ((tx_state == IDLE) && baud_tick && (tx_count != 0))})
                2'b10: tx_count <= tx_count + 1'b1;
                2'b01: tx_count <= tx_count - 1'b1;
                default: tx_count <= tx_count;
            endcase
        end
    end

    // Receiver: reads data one bit at a time
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            rx_wr_ptr <= 0;
            rx_rd_ptr <= 0;
            rx_count  <= 0;

            rx_state  <= IDLE;
            rx_bit    <= 0;
            rx_reg    <= 0;
            rx_oversample_count <= 0;
            rx_sample_ones <= 0;

            parity_error  <= 0;
            framing_error <= 0;
            overrun_error <= 0;
        end
        else begin
            // Move to the next RX FIFO entry when data is read.
            if (rx_read && (rx_count != 0))
                rx_rd_ptr <= rx_rd_ptr + 1'b1;

            // New RX path: sample the middle of every UART bit using 16x timing.
            // The existing receiver below is kept unchanged for the other baud settings.
            if (rx_oversampling_active) begin
                case (rx_state)

                    IDLE: begin
                        // Detect a possible start bit and wait 8 clocks for its center.
                        if (serial_rx == 0) begin
                            rx_reg <= 0;
                            rx_bit <= 0;
                            rx_oversample_count <= 0;
                            rx_sample_ones <= 0;
                            rx_state <= START;
                        end
                    end

                    START: begin
                        rx_sample_ones <= rx_sample_ones + serial_rx;

                        if (rx_oversample_count == 4'd15) begin
                            // Start bit is still low at its center, so it is valid.
                            if ((rx_sample_ones + serial_rx) < 5'd8) begin
                                rx_oversample_count <= 0;
                                rx_sample_ones <= 0;
                                rx_bit <= 0;
                                rx_state <= DATA;
                            end
                            else begin
                                // The low pulse was too short, so ignore it as a false start.
                                rx_state <= IDLE;
                                rx_oversample_count <= 0;
                                rx_sample_ones <= 0;
                            end
                        end
                        else begin
                            rx_oversample_count <= rx_oversample_count + 1'b1;
                        end
                    end

                    DATA: begin
                        rx_sample_ones <= rx_sample_ones + serial_rx;

                        if (rx_oversample_count == 4'd15) begin
                            // Sample each data bit at the center of its bit period.
                            if ((rx_sample_ones + serial_rx) >= 5'd8)
                                rx_reg[rx_bit] <= 1'b1;
                            else
                                rx_reg[rx_bit] <= 1'b0;

                            rx_oversample_count <= 0;
                            rx_sample_ones <= 0;

                            if (rx_bit == num_data_bits - 1) begin
                                if (parity_select == PARITY_NONE)
                                    rx_state <= STOP;
                                else
                                    rx_state <= PARITY;
                            end
                            else begin
                                rx_bit <= rx_bit + 1'b1;
                            end
                        end
                        else begin
                            rx_oversample_count <= rx_oversample_count + 1'b1;
                        end
                    end

                    PARITY: begin
                        rx_sample_ones <= rx_sample_ones + serial_rx;

                        if (rx_oversample_count == 4'd15) begin
                            // Check parity at the center of the parity bit.
                            case (parity_select)
                                PARITY_EVEN: begin
                                    case (num_data_bits)
                                        5: if (((rx_sample_ones + serial_rx) >= 5'd8) == (^rx_reg[4:0]))
                                               rx_state <= STOP;
                                           else begin
                                               parity_error <= 1;
                                               rx_state <= IDLE;
                                           end

                                        6: if (((rx_sample_ones + serial_rx) >= 5'd8) == (^rx_reg[5:0]))
                                               rx_state <= STOP;
                                           else begin
                                               parity_error <= 1;
                                               rx_state <= IDLE;
                                           end

                                        7: if (((rx_sample_ones + serial_rx) >= 5'd8) == (^rx_reg[6:0]))
                                               rx_state <= STOP;
                                           else begin
                                               parity_error <= 1;
                                               rx_state <= IDLE;
                                           end

                                        default: if (((rx_sample_ones + serial_rx) >= 5'd8) == (^rx_reg[7:0]))
                                                     rx_state <= STOP;
                                                 else begin
                                                     parity_error <= 1;
                                                     rx_state <= IDLE;
                                                 end
                                    endcase
                                end

                                PARITY_ODD: begin
                                    case (num_data_bits)
                                        5: if (((rx_sample_ones + serial_rx) >= 5'd8) == (~(^rx_reg[4:0])))
                                               rx_state <= STOP;
                                           else begin
                                               parity_error <= 1;
                                               rx_state <= IDLE;
                                           end

                                        6: if (((rx_sample_ones + serial_rx) >= 5'd8) == (~(^rx_reg[5:0])))
                                               rx_state <= STOP;
                                           else begin
                                               parity_error <= 1;
                                               rx_state <= IDLE;
                                           end

                                        7: if (((rx_sample_ones + serial_rx) >= 5'd8) == (~(^rx_reg[6:0])))
                                               rx_state <= STOP;
                                           else begin
                                               parity_error <= 1;
                                               rx_state <= IDLE;
                                           end

                                        default: if (((rx_sample_ones + serial_rx) >= 5'd8) == (~(^rx_reg[7:0])))
                                                     rx_state <= STOP;
                                                 else begin
                                                     parity_error <= 1;
                                                     rx_state <= IDLE;
                                                 end
                                    endcase
                                end

                                default: begin
                                    rx_state <= STOP;
                                end
                            endcase

                            rx_oversample_count <= 0;
                            rx_sample_ones <= 0;
                        end
                        else begin
                            rx_oversample_count <= rx_oversample_count + 1'b1;
                        end
                    end

                    STOP: begin
                        rx_sample_ones <= rx_sample_ones + serial_rx;

                        if (rx_oversample_count == 4'd15) begin
                            // The stop bit must be high at its center.
                            if ((rx_sample_ones + serial_rx) >= 5'd8) begin
                                if (rx_count < 16) begin
                                    rx_fifo[rx_wr_ptr] <= rx_reg;
                                    rx_wr_ptr <= rx_wr_ptr + 1'b1;
                                end
                                else begin
                                    overrun_error <= 1;
                                end
                            end
                            else begin
                                framing_error <= 1;
                            end

                            rx_state <= IDLE;
                            rx_oversample_count <= 0;
                            rx_sample_ones <= 0;
                        end
                        else begin
                            rx_oversample_count <= rx_oversample_count + 1'b1;
                        end
                    end

                    default: begin
                        rx_state <= IDLE;
                        rx_oversample_count <= 0;
                        rx_sample_ones <= 0;
                    end

                endcase
            end
            else if (baud_tick) begin
                // Original RX path: unchanged for baud settings where 16x
                // sampling cannot be performed with the existing 100 MHz clock.
                case (rx_state)

                    IDLE: begin
                        // A low signal means a start bit was detected.
                        if (serial_rx == 0) begin
                            rx_reg <= 0;
                            rx_bit <= 0;
                            rx_state <= START;
                        end
                    end

                    START: begin
                        rx_reg[0] <= serial_rx;

                        if (num_data_bits == 1) begin
                            rx_bit <= 0;
                            if (parity_select == PARITY_NONE)
                                rx_state <= STOP;
                            else
                                rx_state <= PARITY;
                        end
                        else begin
                            rx_bit <= 1;
                            rx_state <= DATA;
                        end
                    end

                    // Store each received data bit in the correct position.
                    DATA: begin
                        rx_reg[rx_bit] <= serial_rx;

                        if (rx_bit == num_data_bits - 1) begin
                            if (parity_select == PARITY_NONE)
                                rx_state <= STOP;
                            else
                                rx_state <= PARITY;
                        end
                        else begin
                            rx_bit <= rx_bit + 1'b1;
                        end
                    end

                    // Check whether the received parity bit is correct.
                    PARITY: begin
                        case (parity_select)
                            PARITY_EVEN: begin
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

                            PARITY_ODD: begin
                                case (num_data_bits)
                                    5: if (serial_rx == ~(^rx_reg[4:0]))
                                           rx_state <= STOP;
                                       else begin
                                           parity_error <= 1;
                                           rx_state <= IDLE;
                                       end

                                    6: if (serial_rx == ~(^rx_reg[5:0]))
                                           rx_state <= STOP;
                                       else begin
                                           parity_error <= 1;
                                           rx_state <= IDLE;
                                       end

                                    7: if (serial_rx == ~(^rx_reg[6:0]))
                                           rx_state <= STOP;
                                       else begin
                                           parity_error <= 1;
                                           rx_state <= IDLE;
                                       end

                                    default: if (serial_rx == ~(^rx_reg[7:0]))
                                                 rx_state <= STOP;
                                             else begin
                                                 parity_error <= 1;
                                                 rx_state <= IDLE;
                                             end
                                endcase
                            end

                            default: begin
                                rx_state <= STOP;
                            end
                        endcase
                    end

                    // Check that the stop bit is high.
                    STOP: begin
                        if (serial_rx == 1) begin
                            if (rx_count < 16) begin
                                rx_fifo[rx_wr_ptr] <= rx_reg;
                                rx_wr_ptr <= rx_wr_ptr + 1'b1;
                            end
                            else begin
                                overrun_error <= 1;
                            end
                        end
                        else begin
                            framing_error <= 1;
                        end

                        rx_state <= IDLE;
                    end

                    default: rx_state <= IDLE;

                endcase
            end

            case ({((rx_state == STOP) &&
                    (((!rx_oversampling_active) && baud_tick) ||
                     (rx_oversampling_active && (rx_oversample_count == 0))) &&
                    (serial_rx == 1) && (rx_count < 16)),
                   (rx_read && (rx_count != 0))})
                2'b10: rx_count <= rx_count + 1'b1;
                2'b01: rx_count <= rx_count - 1'b1;
                default: rx_count <= rx_count;
            endcase
        end
    end

endmodule

