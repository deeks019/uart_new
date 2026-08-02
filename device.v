module device(
    input clk,              // Common clock used by both transmitter and receiver
    input reset,            // Resets the transmitter and receiver
    input [1:0] baud_select, // To select the baud rate

    input tx_start,         // Signal used to start transmission
    input [7:0] tx_data,    // 8-bit data that has to be transmitted
    output reg tx_active,   // tx_active is high while transmission is happening
    output reg tx_done,     // High for one clock cycle when transmission is complete
    output reg serial_tx,   // Serial output from the transmitter

    input serial_rx,        // Serial input to the receiver
    output reg [7:0] rx_data, // 8-bit data received by the receiver
    output reg rx_valid       // High for one clock cycle when received data is valid
);


// Different states used by the transmitter and receiver FSM
parameter IDLE  = 0;        // Waiting for transmission/reception to start
parameter START = 1;        // Start bit has been sent
parameter DATA  = 2;        // Sending or receiving the 8 data bits
parameter PARITY = 3;       // Sending or receiving parity bit
parameter STOP = 4;         // Sending or detecting the stop bit
parameter DONE  = 5;        // Transmission/reception is complete


reg [2:0] tx_state;         // Stores the current transmitter state
reg [2:0] rx_state;         // Stores the current receiver state
reg [2:0] tx_bit;           // Counts the transmitted data bits
reg [2:0] rx_bit;           // Counts the received data bits
reg [7:0] tx_reg;           // Stores tx_data while it is being transmitted
reg [7:0] rx_reg;           // Stores the received bits
reg tx_parity;              //Stores the Tx parity bit
reg rx_parity;              // Stores the Rx parity bit

reg [15:0] tx_clk_count;    // Counts clock cycles for transmission
reg [15:0] rx_clk_count;    // Counts clock cycles for reception
reg [15:0] CLKS_PER_BIT;    // For different clks_per_bit

always @(*) begin
    case (baud_select)
        2'b00: CLKS_PER_BIT = 1; //9600 baud (10 MHz clock)
        2'b01: CLKS_PER_BIT = 2;  //19200 baud
        2'b10: CLKS_PER_BIT = 3;  //57600 baud
        2'b11: CLKS_PER_BIT = 4;   //115200 baud
        default: CLKS_PER_BIT = 5;
    endcase
end


// TRANSMITTER

always @(posedge clk or posedge reset) begin
    if (reset) begin        // Reset the transmitter
        tx_state <= IDLE;   // Go back to IDLE state
        tx_bit <= 0;        // Clear the bit counter
        tx_reg <= 0;        // Clear the transmit register
        tx_active <= 0;     // Transmission is not active
        tx_done <= 0;       // Transmission is not complete
        serial_tx <= 1;     // UART line stays HIGH when idle
        tx_clk_count <= 0;
    end

    else begin
        tx_done <= 0;       // Keep tx_done LOW unless transmission finishes
            
        case (tx_state)
            IDLE: begin
                tx_active <= 0;     // No transmission is happening
                serial_tx <= 1;     // UART line is HIGH when idle
                tx_bit <= 0;        // Reset the bit counter
                tx_clk_count <= 0;

                if (tx_start) begin
                    tx_reg <= tx_data;   // Store the data that has to be transmitted
                    tx_parity <= ^tx_data;
                    tx_active <= 1;      // Transmission starts
                    serial_tx <= 0;      // Send the start bit (LOW)
                    tx_state <= START;   // Move to START state
                end
            end


            START: begin

                if (tx_clk_count == CLKS_PER_BIT - 1) begin
                    tx_clk_count <= 0;
                    serial_tx <= tx_reg[0]; // Send the first data bit (LSB)
                    tx_reg <= tx_reg >> 1;  // Shift right to get the next bit ready
                    tx_bit <= 1;            // First data bit has been sent
                    tx_state <= DATA;       // Move to DATA state
                end

                else begin
                    tx_clk_count <= tx_clk_count + 1;
                end
            end


            DATA: begin

                if (tx_clk_count == CLKS_PER_BIT - 1) begin
                    tx_clk_count <= 0;

                    serial_tx <= tx_reg[0]; // Send the next data bit
                    tx_reg <= tx_reg >> 1;  // Shift right for the next data bit

                    if (tx_bit == 7) begin
                        tx_state <= PARITY;    // All 8 data bits have now been sent
                    end

                    else begin
                        tx_bit <= tx_bit + 1; // Increase the data bit counter
                    end
                end

                else begin
                    tx_clk_count <= tx_clk_count + 1;
                end

            end
            
            PARITY: begin
              
               if(tx_clk_count == CLKS_PER_BIT-1) begin
               tx_clk_count<=0;
               serial_tx <= tx_parity; //Send the parity bit (even parity)
               tx_state <= STOP;       //Move to STOP state
               end
               
               else begin
               tx_clk_count <= tx_clk_count+1; 
               end
               end
               
               
            STOP: begin

                if (tx_clk_count == CLKS_PER_BIT - 1) begin
                    tx_clk_count <= 0;
                    serial_tx <= 1;         // Send the stop bit (HIGH)
                    tx_state <= DONE;        // Move to DONE state
                end

                else begin
                    tx_clk_count <= tx_clk_count + 1;
                end
            end


            DONE: begin
                tx_active <= 0;          // Transmission is no longer active
                tx_done <= 1;            // Show that transmission is complete
                tx_state <= IDLE;        // Go back to IDLE and wait for new data
            end


            default: begin
                tx_state <= IDLE;        // Go to IDLE if an unknown state occurs
            end
        endcase
    end
end



// RECEIVER

always @(posedge clk or posedge reset) begin

    if (reset) begin        // Reset the receiver
        rx_state <= IDLE;   // Go back to IDLE state
        rx_bit <= 0;        // Clear the bit counter
        rx_reg <= 0;        // Clear the receive register
        rx_data <= 0;       // Clear the received output data
        rx_valid <= 0;      // No valid data is available
        rx_clk_count <= 0;
    end

    else begin
        rx_valid <= 0;      // Keep rx_valid LOW unless complete data is received

        case (rx_state)
            IDLE: begin
                rx_bit <= 0;    // Reset the received bit counter
                rx_clk_count <= 0;

                if (serial_rx == 0) begin    // LOW means a start bit is detected
                    rx_reg <= 0;             // Clear old received data
                    rx_state <= START;       // Move to START state
                end
            end


            START: begin

                if (rx_clk_count == CLKS_PER_BIT - 1) begin
                    rx_clk_count <= 0;

                    // Store the first received data bit
                    rx_reg <= {serial_rx, rx_reg[7:1]};
                    rx_bit <= 1;          // First data bit has been received
                    rx_state <= DATA;     // Move to DATA state
                end

                else begin
                    rx_clk_count <= rx_clk_count + 1;
                end
            end


            DATA: begin

                if (rx_clk_count == CLKS_PER_BIT - 1) begin
                    rx_clk_count <= 0;

                    // Store each new received bit in the register
                    rx_reg <= {serial_rx, rx_reg[7:1]};

                    if (rx_bit == 7) begin
                        rx_state <= PARITY;     // All 8 data bits have been received
                    end

                    else begin
                        rx_bit <= rx_bit + 1; // Increase the received bit counter
                    end
                end

                else begin
                    rx_clk_count <= rx_clk_count + 1;
                end
            end
            
            PARITY: begin
             
             if(rx_clk_count == CLKS_PER_BIT-1) begin
             rx_clk_count<=0;
             
             rx_parity <= serial_rx; //Store the parity in the rx line
             
             if(serial_rx == ^rx_reg) //The receiver computes the XOR and matches it with the parity bit received    
              rx_state <= STOP;   //If it matches, move to the STOP state
             else
              rx_state <= IDLE;   //If it does not match, move back to the IDLE state
             end
             
             else begin
             rx_clk_count <= rx_clk_count +1;
             end
             end       
      

            STOP: begin

                if (rx_clk_count == CLKS_PER_BIT - 1) begin
                    rx_clk_count <= 0;

                    if (serial_rx == 1)       // Check if the stop bit is HIGH
                        rx_state <= DONE;     // Correct stop bit, so reception is complete
                    else
                        rx_state <= IDLE;     // Wrong stop bit, go back to IDLE
                end

                else begin
                    rx_clk_count <= rx_clk_count + 1;
                end
            end


            DONE: begin
                rx_data <= rx_reg;        // Copy received data to the output
                rx_valid <= 1;            // Show that valid data is available
                rx_state <= IDLE;         // Go back to IDLE for the next data
            end


            default: begin
                rx_state <= IDLE;         // Go to IDLE if an unknown state occurs
            end
        endcase
    end
end
endmodule
