`default_nettype none

module tt_um_advaittej_stopwatch #(
    parameter CLOCKS_PER_SECOND = 24'd9_999_999, // 10 MHz clock = 1 sec
    parameter CLOCKS_PER_BAUD   = 12'd1041       // 10 MHz / 9600 baud = ~1042
)(
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // ==========================================
    // 1. PIN ALIASING & SETUP
    // ==========================================
    wire reset_active = !rst_n;
    
    // uio_oe: 1 = Output, 0 = Input. 
    // uio_out[0] is UART TX. uio_out[7:4] will display Lap 1 memory.
    assign uio_oe = 8'b1111_0001; 
    assign uio_out[3:1] = 3'b0; // Tie off unused outputs
    
    wire [6:0] led_segments;
    assign uo_out[6:0] = led_segments;

    // ==========================================
    // 2. HARDWARE DEBOUNCERS
    // ==========================================
    reg [7:0] btn_start_shift;
    reg [7:0] btn_lap_shift;
    reg       start_pause_btn;
    reg       lap_btn;
    reg       lap_btn_prev;

    always @(posedge clk or posedge reset_active) begin
        if (reset_active) begin
            btn_start_shift <= 8'b0;
            btn_lap_shift   <= 8'b0;
            start_pause_btn <= 1'b0;
            lap_btn         <= 1'b0;
            lap_btn_prev    <= 1'b0;
        end else begin
            btn_start_shift <= {btn_start_shift[6:0], ui_in[0]}; // Start/Stop
            btn_lap_shift   <= {btn_lap_shift[6:0],   ui_in[1]}; // Lap

            if (btn_start_shift == 8'hFF) start_pause_btn <= 1'b1;
            else if (btn_start_shift == 8'h00) start_pause_btn <= 1'b0;

            if (btn_lap_shift == 8'hFF) lap_btn <= 1'b1;
            else if (btn_lap_shift == 8'h00) lap_btn <= 1'b0;
            
            lap_btn_prev <= lap_btn;
        end
    end

    wire lap_trigger_pulse = (lap_btn && !lap_btn_prev);

    // ==========================================
    // 3. STOPWATCH & LAP MEMORY
    // ==========================================
    reg [23:0] clock_counter;
    wire one_second_pulse = (clock_counter == CLOCKS_PER_SECOND);
    
    reg [3:0] current_digit;
    reg [3:0] lap_1, lap_2, lap_3; // 3-Deep Lap Memory

    // Expose Lap 1 to the bidirectional pins for testing
    assign uio_out[7:4] = lap_1;

    always @(posedge clk or posedge reset_active) begin
        if (reset_active) begin
            clock_counter <= 0;
            current_digit <= 0;
            lap_1 <= 0; lap_2 <= 0; lap_3 <= 0;
        end else begin
            // Handle Counting
            if (start_pause_btn) begin
                if (one_second_pulse) begin
                    clock_counter <= 0;
                    if (current_digit == 9) current_digit <= 0;
                    else current_digit <= current_digit + 1;
                end else begin
                    clock_counter <= clock_counter + 1;
                end
            end
            
            // Handle Lap Memory (Shift Register Style)
            if (lap_trigger_pulse) begin
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
            4'd0: decoded_leds = 7'b0111111;
            4'd1: decoded_leds = 7'b0000110;
            4'd2: decoded_leds = 7'b1011011;
            4'd3: decoded_leds = 7'b1001111;
            4'd4: decoded_leds = 7'b1100110;
            4'd5: decoded_leds = 7'b1101101;
            4'd6: decoded_leds = 7'b1111101;
            4'd7: decoded_leds = 7'b0000111;
            4'd8: decoded_leds = 7'b1111111;
            4'd9: decoded_leds = 7'b1101111;
            default: decoded_leds = 7'b0000000;
        endcase
    end

    // ==========================================
    // 4. ALARM COMPARATOR
    // ==========================================
    wire [3:0] target_time = ui_in[7:4]; 
    wire alarm_match = (current_digit == target_time);

    // Decimal point lights up solid when target is reached
    assign uo_out[7] = alarm_match;

    // Edge detector for the alarm (triggers UART exactly once per match)
    reg alarm_match_prev;
    always @(posedge clk or posedge reset_active) begin
        if (reset_active) alarm_match_prev <= 1'b0;
        else alarm_match_prev <= alarm_match;
    end
    wire alarm_trigger_pulse = (alarm_match && !alarm_match_prev);

    // ==========================================
    // 5. AUTONOMOUS UART TRANSMITTER
    // ==========================================
    reg [11:0] baud_counter;
    reg [3:0]  tx_bit_idx;     
    reg [3:0]  char_idx;       
    reg [7:0]  tx_shift_reg;   
    reg        tx_active;
    reg        tx_pin_reg;
    
    assign uio_out[0] = tx_pin_reg;
    wire baud_tick = (baud_counter == CLOCKS_PER_BAUD);

    // String ROM: "VIT Vellore\r\n"
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
            baud_counter <= 0;
            tx_bit_idx   <= 0;
            char_idx     <= 0;
            tx_active    <= 0;
            tx_pin_reg   <= 1'b1; 
        end else begin
            // Trigger transmission when Stopwatch matches switches
            if (alarm_trigger_pulse && !tx_active) begin
                tx_active    <= 1'b1;
                char_idx     <= 0;
                tx_bit_idx   <= 0;
                baud_counter <= 0;
                tx_shift_reg <= 8'h56; 
            end

            if (tx_active) begin
                if (baud_tick) begin
                    baud_counter <= 0;
                    
                    if (tx_bit_idx == 0) begin
                        tx_pin_reg <= 1'b0; // Start Bit
                        tx_bit_idx <= tx_bit_idx + 1;
                    end else if (tx_bit_idx <= 8) begin
                        tx_pin_reg <= tx_shift_reg[0]; // Data
                        tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
                        tx_bit_idx <= tx_bit_idx + 1;
                    end else if (tx_bit_idx == 9) begin
                        tx_pin_reg <= 1'b1; // Stop Bit
                        
                        if (char_idx == 4'd12) begin
                            tx_active <= 1'b0; 
                        end else begin
                            char_idx <= char_idx + 1;
                            tx_bit_idx <= 0; 
                        end
                    end
                end else begin
                    baud_counter <= baud_counter + 1;
                    if (tx_bit_idx == 0 && baud_counter == 1) begin
                        tx_shift_reg <= char_to_send;
                    end
                end
            end
        end
    end

endmodule
