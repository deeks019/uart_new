module device(                              // Main device module
input clk,                                  // Clock input
input reset,                                // Reset input
input [1:0] baud_select,                    // Selects baud rate
input [1:0] data_length,                    // Selects number of data bits
input tx_start,                             // Starts transmission
input [7:0] tx_data,                        // Data to transmit

output reg tx_active,                       // Shows TX is active
output reg tx_done,                         // Shows TX is complete
output reg serial_tx,                       // Serial transmit signal

input serial_rx,                            // Serial receive signal
output reg [7:0] rx_data,                   // Received data
output reg rx_valid                         // Shows RX data is valid
);

parameter IDLE   = 0;                       // Waiting state
parameter START  = 1;                       // Start bit state
parameter DATA   = 2;                       // Data bit state
parameter PARITY = 3;                       // Parity bit state
parameter STOP   = 4;                       // Stop bit state
parameter DONE   = 5;                       // Done state


reg [2:0] tx_state;                         // Stores TX state
reg [2:0] rx_state;                         // Stores RX state
reg [2:0] tx_bit;                           // Counts TX bits
reg [2:0] rx_bit;                           // Counts RX bits
reg [3:0] NUM_DATA_BITS;                    // Stores number of data bits
reg [7:0] tx_reg;                           // Stores data during TX
reg [7:0] rx_reg;                           // Stores data during RX
reg tx_parity;                              // Stores TX parity
reg rx_parity;                              // Stores RX parity
reg [15:0] tx_clk_count;                    // TX clock counter
reg [15:0] rx_clk_count;                    // RX clock counter
reg [15:0] CLKS_PER_BIT;                    // Clock cycles for one bit
always @(*) begin                           // Select number of data bits
    case(data_length)                       // Check data length
        2'b00: NUM_DATA_BITS = 5;           // Select 5 data bits
        2'b01: NUM_DATA_BITS = 6;           // Select 6 data bits
        2'b10: NUM_DATA_BITS = 7;           // Select 7 data bits
        2'b11: NUM_DATA_BITS = 8;           // Select 8 data bits
        default: NUM_DATA_BITS = 8;         // Use 8 bits by default
    endcase                                  // End data length case
end                                         // End data length block


always @(*) begin                           // Select clock cycles per bit
    case (baud_select)                      // Check baud selection
        2'b00: CLKS_PER_BIT = 1;            // Use 1 clock per bit
        2'b01: CLKS_PER_BIT = 1;            // Use 2 clocks per bit
        2'b10: CLKS_PER_BIT = 1;            // Use 3 clocks per bit
        2'b11: CLKS_PER_BIT = 1;            // Use 4 clocks per bit
        default: CLKS_PER_BIT = 1;          // Use 4 clocks by default
    endcase                                  // End baud case
end                                         // End baud selection block

// TRANSMITTER
always @(posedge clk or posedge reset) begin // TX runs on clock or reset
    if (reset) begin                        // Check for reset
        tx_state <= IDLE;                   // Go to idle state
        tx_bit <= 0;                        // Reset TX bit counter
        tx_reg <= 0;                        // Clear TX register
        tx_active <= 0;                     // TX is not active
        tx_done <= 0;                       // Clear TX done signal
        serial_tx <= 1;                     // Keep serial line high
        tx_clk_count <= 0;                  // Reset TX clock counter
    end
    else begin                              // Normal operation
        tx_done <= 0;                       // Clear done signal

        case (tx_state)                     // Check current TX state
            IDLE: begin                     // Wait for transmission
                tx_active <= 0;              // TX is not active
                serial_tx <= 1;              // Keep line high
                tx_bit <= 0;                 // Reset bit counter
                tx_clk_count <= 0;           // Reset clock counter
                if (tx_start) begin         // Start when tx_start is high

                    case (NUM_DATA_BITS)     // Check number of data bits
                        5: tx_reg <= {3'b000, tx_data[4:0]}; // Store 5 bits
                        6: tx_reg <= {2'b00, tx_data[5:0]};   // Store 6 bits
                        7: tx_reg <= {1'b0, tx_data[6:0]};   // Store 7 bits
                        8: tx_reg <= tx_data;                // Store 8 bits
                    endcase                  // End data bits case

                    case(NUM_DATA_BITS)      // Calculate parity
                        5: tx_parity <= ^tx_data[4:0];       // Parity for 5 bits
                        6: tx_parity <= ^tx_data[5:0];       // Parity for 6 bits
                        7: tx_parity <= ^tx_data[6:0];       // Parity for 7 bits
                        8: tx_parity <= ^tx_data[7:0];       // Parity for 8 bits
                        default: tx_parity <= ^tx_data;       // Default parity
                    endcase                  // End parity case

                    tx_active <= 1;          // TX is now active
                    serial_tx <= 0;          // Send start bit
                    tx_state <= START;       // Go to start state
                end
            end

            START: begin                     // Send start bit
                if (tx_clk_count == CLKS_PER_BIT - 1) begin // Wait one bit time
                    tx_clk_count <= 0;       // Reset clock counter
                    serial_tx <= tx_reg[0];  // Send first data bit
                    tx_reg <= tx_reg >> 1;   // Shift data right
                    tx_bit <= 1;             // Set bit counter
                    tx_state <= DATA;        // Go to data state
                end
                else begin
                    tx_clk_count <= tx_clk_count + 1; // Count clock cycles
                end
            end

            DATA: begin                      // Send data bits
                if (tx_clk_count == CLKS_PER_BIT - 1) begin // Wait one bit time
                    tx_clk_count <= 0;       // Reset clock counter
                    serial_tx <= tx_reg[0];  // Send current data bit
                    tx_reg <= tx_reg >> 1;   // Shift to next bit
                    if (tx_bit == NUM_DATA_BITS - 1) begin // Check last bit
                        tx_state <= PARITY;   // Go to parity state
                    end
                    else begin
                        tx_bit <= tx_bit + 1; // Move to next bit
                    end
                end

                else begin
                    tx_clk_count <= tx_clk_count + 1; // Count clock cycles
                end
            end

            PARITY: begin                    // Send parity bit
                if(tx_clk_count == CLKS_PER_BIT - 1) begin // Wait one bit time
                    tx_clk_count <= 0;       // Reset clock counter
                    serial_tx <= tx_parity; // Send parity bit
                    tx_state <= STOP;        // Go to stop state
                end

                else begin
                    tx_clk_count <= tx_clk_count + 1; // Count clock cycles
                end
            end


            STOP: begin                      // Send stop bit
                if (tx_clk_count == CLKS_PER_BIT - 1) begin // Wait one bit time
                    tx_clk_count <= 0;       // Reset clock counter
                    serial_tx <= 1;          // Send stop bit
                    tx_state <= DONE;       // Go to done state
                end

                else begin
                    tx_clk_count <= tx_clk_count + 1; // Count clock cycles
                end
            end


            DONE: begin                      // Transmission is complete
                tx_active <= 0;              // TX is no longer active
                tx_done <= 1;                // Tell that TX is complete
                tx_state <= IDLE;            // Go back to idle
            end


            default: begin                   // If state is invalid
                tx_state <= IDLE;            // Go back to idle
            end
        endcase                              // End TX state case
    end
end

always @(posedge clk or posedge reset) begin // RX runs on clock or reset
    if (reset) begin                        // Check for reset
        rx_state <= IDLE;                   // Go to idle state
        rx_bit <= 0;                        // Reset RX bit counter
        rx_reg <= 0;                        // Clear RX register
        rx_data <= 0;                       // Clear received data
        rx_valid <= 0;                      // Clear valid signal
        rx_clk_count <= 0;                  // Reset RX clock counter
    end

    else begin                              // Normal operation
        rx_valid <= 0;                      // Clear valid signal
        case (rx_state)                     // Check current RX state
            IDLE: begin                     // Wait for start bit
                rx_bit <= 0;                 // Reset bit counter
                rx_clk_count <= 0;           // Reset clock counter
                if (serial_rx == 0) begin   // Check for start bit
                    rx_reg <= 0;             // Clear RX register
                    rx_state <= START;      // Go to start state
                end
            end


            START: begin                    // Receive start bit
                if (rx_clk_count == CLKS_PER_BIT - 1) begin // Wait one bit time
                    rx_clk_count <= 0;      // Reset clock counter
                    rx_reg <= {rx_reg[6:0], serial_rx}; // Store received bit
                    rx_bit <= 1;            // Set bit counter
                    rx_state <= DATA;       // Go to data state
                end

                else begin
                    rx_clk_count <= rx_clk_count + 1; // Count clock cycles
                end
            end

            DATA: begin                     // Receive data bits
                if (rx_clk_count == CLKS_PER_BIT - 1) begin // Wait one bit time
                    rx_clk_count <= 0;      // Reset clock counter
                    rx_reg <= {rx_reg[6:0], serial_rx}; // Store received bit
                    if (rx_bit == NUM_DATA_BITS - 1) begin // Check last bit
                        rx_state <= PARITY;  // Go to parity state
                    end

                    else begin
                        rx_bit <= rx_bit + 1; // Move to next bit
                    end
                end

                else begin
                    rx_clk_count <= rx_clk_count + 1; // Count clock cycles
                end
            end

            PARITY: begin                   // Receive parity bit
                if (rx_clk_count == CLKS_PER_BIT - 1) begin // Wait one bit time
                    rx_clk_count <= 0;      // Reset clock counter
                    rx_parity <= serial_rx; // Store received parity
                    case (NUM_DATA_BITS)    // Check number of data bits
                        5: begin             // For 5 data bits
                            if (serial_rx == ^rx_reg[4:0]) // Check parity
                                rx_state <= STOP;         // Parity is correct
                            else
                                rx_state <= IDLE;         // Parity is wrong
                        end

                        6: begin             // For 6 data bits
                            if (serial_rx == ^rx_reg[5:0]) // Check parity
                                rx_state <= STOP;         // Parity is correct
                            else
                                rx_state <= IDLE;         // Parity is wrong
                        end

                        7: begin             // For 7 data bits
                            if (serial_rx == ^rx_reg[6:0]) // Check parity
                                rx_state <= STOP;          // Parity is correct
                            else
                                rx_state <= IDLE;          // Parity is wrong
                        end

                        8: begin             // For 8 data bits
                            if (serial_rx == ^rx_reg[7:0]) // Check parity
                                rx_state <= STOP;          // Parity is correct
                            else
                                rx_state <= IDLE;          // Parity is wrong
                        end

                        default: rx_state <= IDLE; // Go idle for invalid value
                    endcase                  // End parity check
                end
                
                else begin
                    rx_clk_count <= rx_clk_count + 1; // Count clock cycles
                end
            end

            STOP: begin                     // Receive stop bit
                if (rx_clk_count == CLKS_PER_BIT - 1) begin // Wait one bit time
                    rx_clk_count <= 0;      // Reset clock counter
                    if (serial_rx == 1)     // Check stop bit
                        rx_state <= DONE;   // Stop bit is correct
                    else
                        rx_state <= IDLE;   // Stop bit is wrong
                end

                else begin
                    rx_clk_count <= rx_clk_count + 1; // Count clock cycles
                end
            end

            DONE: begin                     // Reception is complete
                case(NUM_DATA_BITS)         // Check number of data bits
                    5: rx_data <= {3'b000, rx_reg[0], rx_reg[1], rx_reg[2], rx_reg[3], rx_reg[4]};
                    // Put 5 received bits into rx_data
                    6: rx_data <= {2'b00, rx_reg[0], rx_reg[1], rx_reg[2], rx_reg[3], rx_reg[4], rx_reg[5]};
                    // Put 6 received bits into rx_data
                    7: rx_data <= {1'b0, rx_reg[0], rx_reg[1], rx_reg[2], rx_reg[3], rx_reg[4], rx_reg[5], rx_reg[6]};
                    // Put 7 received bits into rx_data
                    8: rx_data <= {rx_reg[0], rx_reg[1], rx_reg[2], rx_reg[3], rx_reg[4], rx_reg[5], rx_reg[6], rx_reg[7]};
                    // Put 8 received bits into rx_data
                    default: rx_data <= rx_reg; // Use full RX register
                endcase                          // End data case
                rx_valid <= 1;                   // Tell that data is ready
                rx_state <= IDLE;                // Go back to idle
            end

            default: begin                       // If state is invalid
                rx_state <= IDLE;                 // Go back to idle
            end
        endcase                                  // End RX state case
    end
end
endmodule                                       // End of module
