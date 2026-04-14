`default_nettype none

module tt_um_advaittej_stopwatch #(
    parameter CLOCKS_PER_SECOND = 24'd9_999_999
)(
    // DO NOT CHANGE THESE NAMES!!
    // The factory tools require these exact port definitions
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // Intuitive aliasing ie translating TT to readable names
    assign uio_out = 8'b0; // Tie off unused pins to prevent errors
    assign uio_oe  = 8'b0;

    // Inverting active-low reset so 1 means reset now for our logic
    wire reset_active = !rst_n;       
    
    // Pin 0 of input block is button
    wire start_pause_btn = ui_in[0];  
    
    // Internal wire for 7-segment data
    wire [6:0] led_segments;          

    // Drive physical output pins with our internal data
    assign uo_out[6:0] = led_segments; 
    assign uo_out[7]   = 1'b0; // Decimal point off

    // CLOCK DIVIDER
    reg [23:0] clock_counter;
    wire one_second_pulse = (clock_counter == CLOCKS_PER_SECOND);

    always @(posedge clk or posedge reset_active) begin
        if (reset_active) begin
            clock_counter <= 0;
        end else if (start_pause_btn) begin
            if (one_second_pulse) begin
                clock_counter <= 0;
            end else begin
                clock_counter <= clock_counter + 1;
            end
        end
    end

    // DIGIT COUNTER: counts 0 to 9
    reg [3:0] current_digit;

    always @(posedge clk or posedge reset_active) begin
        if (reset_active) begin
            current_digit <= 0;
        end else if (start_pause_btn && one_second_pulse) begin
            if (current_digit == 9) begin
                current_digit <= 0;
            end else begin
                current_digit <= current_digit + 1;
            end
        end
    end

    // 7-SEGMENT DECODER: translates to LEDs
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

endmodule
