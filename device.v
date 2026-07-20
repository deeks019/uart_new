module device (
    input clk,
    input reset,
    input tx_start,
    input [7:0] tx_data,
    output reg tx_active,
    output reg tx_done,
    output reg serial_tx,
    input serial_rx,
    output reg [7:0] rx_data,
    output reg rx_valid
);

parameter IDLE = 0;
parameter START = 1;
parameter DATA = 2;
parameter STOP = 3;
parameter DONE = 4;

reg [2:0] tx_state;
reg [2:0] rx_state;
reg [2:0] tx_bit;
reg [2:0] rx_bit;
reg [7:0] tx_reg;
reg [7:0] rx_reg;


always @(posedge clk or posedge reset) begin
    if (reset) begin
        tx_state <= IDLE;
        tx_bit <= 0;
        tx_reg <= 0;
        tx_active <= 0;
        tx_done <= 0;
        serial_tx <= 1;
    end
    else begin
        tx_done <= 0;
            
        case (tx_state)
            IDLE: begin
                tx_active <= 0;
                serial_tx <= 1;//Initial value
                tx_bit <= 0;

                if (tx_start) begin
                    tx_reg <= tx_data;
                    tx_active <= 1;
                    serial_tx <= 0; //The start bit is sent
                    tx_state <= START;
                end
            end

            START: begin
                serial_tx <= tx_reg[0];
                tx_reg <= tx_reg >> 1;
                tx_bit <= 1;
                tx_state <= DATA;
            end

            DATA: begin
                serial_tx <= tx_reg[0];
                tx_reg <= tx_reg >> 1;

                if (tx_bit == 7) begin
                    tx_state <= STOP;
                end
                else begin
                    tx_bit <= tx_bit + 1;
                end
            end

            STOP: begin
                serial_tx <= 1; //The stop bit is sent
                tx_state <= DONE;
            end

            DONE: begin
                tx_active <= 0;
                tx_done <= 1;
                tx_state <= IDLE;
            end

            default: begin
                tx_state <= IDLE;
            end

        endcase
    end
end


always @(posedge clk or posedge reset) begin
    if (reset) begin
        rx_state <= IDLE;
        rx_bit <= 0;
        rx_reg <= 0;
        rx_data <= 0;
        rx_valid <= 0;
    end
    else begin
        rx_valid <= 0;

        case (rx_state)
            IDLE: begin
                rx_bit <= 0;

                if (serial_rx == 0) begin //To check if start bit was received
                    rx_reg <= 0;
                    rx_state <= START;
                end
            end

            START: begin
                rx_reg <= {serial_rx, rx_reg[7:1]};
                rx_bit <= 1;
                rx_state <= DATA;
            end

            DATA: begin
                rx_reg <= {serial_rx, rx_reg[7:1]};

                if (rx_bit == 7) begin
                    rx_state <= STOP;
                end
                else begin
                    rx_bit <= rx_bit + 1;
                end
            end

            STOP: begin
                if (serial_rx == 1) //To check if the stop bit is received
                    rx_state <= DONE;
                else
                    rx_state <= IDLE;
            end

            DONE: begin
                rx_data <= rx_reg;
                rx_valid <= 1;
                rx_state <= IDLE;
            end

            default: begin
                rx_state <= IDLE;
            end

        endcase
    end
end

endmodule
