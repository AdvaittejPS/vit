`default_nettype none

module tt_um_advaittej_stopwatch #(
    parameter CLOCKS_PER_SECOND = 24'd9_999_999, // 10 MHz = 1 sec
    parameter CLOCKS_PER_BAUD   = 12'd1041       // 10 MHz / 9600 baud = ~1042
)(
    input  wire [7:0] ui_in,    
    output wire [7:0] uo_out,   
    input  wire [7:0] uio_in,   
    output wire [7:0] uio_out,  
    output wire [7:0] uio_oe,   
    input  wire       ena,      
    input  wire       clk,      
    input  wire       rst_n     
);

    wire reset_active = !rst_n;
    
    // uio_oe: 1 = Output, 0 = Input.
    // uio_in[1] is UART RX (Input). uio_out[0] is UART TX (Output).
    // uio_out[7:4] exposes Lap 1 memory.
    assign uio_oe = 8'b1111_0001; 
    assign uio_out[3:1] = 3'b0; 
    
    wire [6:0] led_segments;
    assign uo_out[6:0] = led_segments;

    // ==========================================
    // 1. UART RX (RECEIVER) & COMMAND DECODER
    // ==========================================
    // Synchronize the async RX line to our clock domain
    reg rx_s1, rx_s2;
    always @(posedge clk or posedge reset_active) begin
        if (reset_active) begin
            rx_s1 <= 1'b1; rx_s2 <= 1'b1;
        end else begin
            rx_s1 <= uio_in[1]; rx_s2 <= rx_s1;
        end
    end

    reg [1:0]  rx_state;
    reg [3:0]  rx_bit_idx;
    reg [11:0] rx_baud_counter;
    reg [7:0]  rx_shift_reg;
    reg [7:0]  rx_data;
    reg        rx_valid;

    always @(posedge clk or posedge reset_active) begin
        if (reset_active) begin
            rx_state <= 0; rx_valid <= 0;
            rx_baud_counter <= 0; rx_bit_idx <= 0;
            rx_shift_reg <= 0; rx_data <= 0;
        end else begin
            rx_valid <= 0; // Pulse for 1 clock when byte received
            case (rx_state)
                0: begin // IDLE
                    if (rx_s2 == 1'b0) begin // Start bit detected
                        rx_state <= 1;
                        rx_baud_counter <= 0;
                    end
                end
                1: begin // START BIT (Wait half a baud period to center)
                    if (rx_baud_counter == CLOCKS_PER_BAUD/2) begin
                        if (rx_s2 == 1'b0) begin
                            rx_state <= 2;
                            rx_baud_counter <= 0;
                            rx_bit_idx <= 0;
                        end else rx_state <= 0; // Glitch, go back to idle
                    end else rx_baud_counter <= rx_baud_counter + 1;
                end
                2: begin // DATA BITS
                    if (rx_baud_counter == CLOCKS_PER_BAUD) begin
                        rx_baud_counter <= 0;
                        rx_shift_reg <= {rx_s2, rx_shift_reg[7:1]};
                        if (rx_bit_idx == 7) rx_state <= 3;
                        else rx_bit_idx <= rx_bit_idx + 1;
                    end else rx_baud_counter <= rx_baud_counter + 1;
                end
                3: begin // STOP BIT
                    if (rx_baud_counter == CLOCKS_PER_BAUD) begin
                        rx_baud_counter <= 0;
                        if (rx_s2 == 1'b1) begin // Valid stop bit
                            rx_data <= rx_shift_reg;
                            rx_valid <= 1'b1;
                        end
                        rx_state <= 0;
                    end else rx_baud_counter <= rx_baud_counter + 1;
                end
            endcase
        end
    end

    // ASCII Command Decoder
    wire cmd_start = rx_valid && (rx_data == 8'h53 || rx_data == 8'h73); // 'S' or 's'
    wire cmd_lap   = rx_valid && (rx_data == 8'h4C || rx_data == 8'h6C); // 'L' or 'l'
    wire cmd_reset = rx_valid && (rx_data == 8'h52 || rx_data == 8'h72); // 'R' or 'r'

    // ==========================================
    // 2. HARDWARE DEBOUNCERS (Physical Buttons)
    // ==========================================
    reg [7:0] btn_start_shift;
    reg [7:0] btn_lap_shift;
    reg       start_btn;
    reg       start_btn_prev;
    reg       lap_btn;
    reg       lap_btn_prev;

    always @(posedge clk or posedge reset_active) begin
        if (reset_active) begin
            btn_start_shift <= 8'b0; btn_lap_shift <= 8'b0;
            start_btn <= 0; start_btn_prev <= 0;
            lap_btn <= 0; lap_btn_prev <= 0;
        end else begin
            btn_start_shift <= {btn_start_shift[6:0], ui_in[0]};
            btn_lap_shift   <= {btn_lap_shift[6:0],   ui_in[1]};

            if (btn_start_shift == 8'hFF) start_btn <= 1'b1;
            else if (btn_start_shift == 8'h00) start_btn <= 1'b0;

            if (btn_lap_shift == 8'hFF) lap_btn <= 1'b1;
            else if (btn_lap_shift == 8'h00) lap_btn <= 1'b0;
            
            start_btn_prev <= start_btn;
            lap_btn_prev <= lap_btn;
        end
    end

    // Merge Physical Buttons with UART Commands
    wire start_trigger = (start_btn && !start_btn_prev) || cmd_start;
    wire lap_trigger   = (lap_btn && !lap_btn_prev)     || cmd_lap;
    wire soft_reset    = cmd_reset;

    // ==========================================
    // 3. STOPWATCH & LAP MEMORY
    // ==========================================
    reg is_running;
    reg [23:0] clock_counter;
    wire one_second_pulse = (clock_counter == CLOCKS_PER_SECOND);
    
    reg [3:0] current_digit;
    reg [3:0] lap_1, lap_2, lap_3; 
    assign uio_out[7:4] = lap_1; // Expose Lap 1 memory

    always @(posedge clk or posedge reset_active) begin
        if (reset_active) begin
            is_running <= 0;
            clock_counter <= 0;
            current_digit <= 0;
            lap_1 <= 0; lap_2 <= 0; lap_3 <= 0;
        end else if (soft_reset) begin
            is_running <= 0;
            clock_counter <= 0;
            current_digit <= 0;
            lap_1 <= 0; lap_2 <= 0; lap_3 <= 0;
        end else begin
            if (start_trigger) is_running <= ~is_running; // Toggle Play/Pause

            if (is_running) begin
                if (one_second_pulse) begin
                    clock_counter <= 0;
                    if (current_digit == 9) current_digit <= 0;
                    else current_digit <= current_digit + 1;
                end else begin
                    clock_counter <= clock_counter + 1;
                end
            end
            
            if (lap_trigger) begin
                lap_3 <= lap_2;
                lap_2 <= lap_1;
                lap_1 <= current_digit;
            end
        end
    end

    // 7-Segment Decoder
    reg [6:0] decoded_leds;
    assign led_segments = decoded_leds;
    always @(*) begin
        case (current_digit)
            4'd0: decoded_leds = 7'b0111111; 4'd1: decoded_leds = 7'b0000110;
            4'd2: decoded_leds = 7'b1011011; 4'd3: decoded_leds = 7'b1001111;
            4'd4: decoded_leds = 7'b1100110; 4'd5: decoded_leds = 7'b1101101;
            4'd6: decoded_leds = 7'b1111101; 4'd7: decoded_leds = 7'b0000111;
            4'd8: decoded_leds = 7'b1111111; 4'd9: decoded_leds = 7'b1101111;
            default: decoded_leds = 7'b0000000;
        endcase
    end

    // ==========================================
    // 4. ALARM & UART TX TRANSMITTER
    // ==========================================
    wire [3:0] target_time = ui_in[7:4]; 
    wire alarm_match = (current_digit == target_time);
    assign uo_out[7] = alarm_match;

    reg alarm_match_prev;
    always @(posedge clk or posedge reset_active) begin
        if (reset_active) alarm_match_prev <= 1'b0;
        else alarm_match_prev <= alarm_match;
    end
    wire alarm_trigger_pulse = (alarm_match && !alarm_match_prev);

    reg [11:0] tx_baud_counter;
    reg [3:0]  tx_bit_idx;     
    reg [3:0]  char_idx;       
    reg [7:0]  tx_shift_reg;   
    reg        tx_active;
    reg        tx_pin_reg;
    
    assign uio_out[0] = tx_pin_reg;
    wire tx_baud_tick = (tx_baud_counter == CLOCKS_PER_BAUD);

    reg [7:0] char_to_send;
    always @(*) begin
        case(char_idx)
            4'd0:  char_to_send = 8'h56; // V
            4'd1:  char_to_send = 8'h49; // I
            4'd2:  char_to_send = 8'h54; // T
            4'd3:  char_to_send = 8'h20; //  
            4'd4:  char_to_send = 8'h56; // V
            4'd5:  char_to_send = 8'h65; // e
            4'd6:  char_to_send = 8'h6C; // l
            4'd7:  char_to_send = 8'h6C; // l
            4'd8:  char_to_send = 8'h6F; // o
            4'd9:  char_to_send = 8'h72; // r
            4'd10: char_to_send = 8'h65; // e
            4'd11: char_to_send = 8'h0D; // \r
            4'd12: char_to_send = 8'h0A; // \n
            default: char_to_send = 8'h00;
        endcase
    end

    always @(posedge clk or posedge reset_active) begin
        if (reset_active) begin
            tx_baud_counter <= 0; tx_bit_idx <= 0; char_idx <= 0;
            tx_active <= 0; tx_pin_reg <= 1'b1; 
        end else begin
            if (alarm_trigger_pulse && !tx_active) begin
                tx_active <= 1'b1; char_idx <= 0; tx_bit_idx <= 0;
                tx_baud_counter <= 0; tx_shift_reg <= 8'h56; 
            end

            if (tx_active) begin
                if (tx_baud_tick) begin
                    tx_baud_counter <= 0;
                    if (tx_bit_idx == 0) begin
                        tx_pin_reg <= 1'b0; tx_bit_idx <= tx_bit_idx + 1;
                    end else if (tx_bit_idx <= 8) begin
                        tx_pin_reg <= tx_shift_reg[0]; 
                        tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
                        tx_bit_idx <= tx_bit_idx + 1;
                    end else if (tx_bit_idx == 9) begin
                        tx_pin_reg <= 1'b1; 
                        if (char_idx == 4'd12) tx_active <= 1'b0; 
                        else begin
                            char_idx <= char_idx + 1; tx_bit_idx <= 0; 
                        end
                    end
                end else begin
                    tx_baud_counter <= tx_baud_counter + 1;
                    if (tx_bit_idx == 0 && tx_baud_counter == 1) tx_shift_reg <= char_to_send;
                end
            end
        end
    end
endmodule
