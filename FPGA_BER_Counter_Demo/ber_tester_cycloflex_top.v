// ============================================================================
// BER Tester - CycloFlex Cyclone 10 Top Level
// ============================================================================
// Ported from DE1/DE2 Cyclone II design to EarthPeople CycloFlex board.
// FPGA: 10CL016E144C8 (Cyclone 10 LP, 16K LEs, 144-pin EQFP)
//
// HARDCODED CONFIGURATION:
//   Edit the localparams below and recompile to change test settings.
//   No PLL used - runs at 50 MHz from on-board oscillator.
//   To use higher frequencies, regenerate PLL IP for Cyclone 10 LP.
//
// CONNECTOR USAGE:
//   J13 - BER test signals (data TX, data RX, clock TX, scope taps)
//   J8  - Noise generator outputs (optional, accent pins 49=RGB_GREEN)
//   J11 - 7-Seg Display 1 (error count LSB hex digit)
//   J6  - 7-Seg Display 2 (error count mid hex digit)
//   J9/J10 - 7-Seg Display 3 (error count MSB hex digit)
//
// ACTIVE BUG FIXES from original:
//   - error_counter saturation expression corrected
//   - toggle_detector stray '.' removed (module not used in this version)
//   - Clock mux eliminated (hardcoded frequency, no glitch risk)
// ============================================================================

module ber_tester_cycloflex_top (
    // ---- Clock ----
    input wire clk_50,              // 50 MHz on-board oscillator

    // ---- Pushbuttons (active low, hardware debounced) ----
    input wire pb_switch_1,         // SW1, pin 126 - RESET
    input wire pb_switch_2,         // SW2, pin 91  - spare (active low)

    // ---- User LEDs (active high) ----
    output wire [7:0] user_leds,    // D2-D7,D9,D10,D15

    // ---- RGB LED (active high) ----
    output wire led_red,            // pin 43
    output wire led_blue,           // pin 44
    output wire led_green,          // pin 49

    // ---- 7-Segment Display 1 - Error Count [3:0] ----
    output wire disp1_a,           // pin 142
    output wire disp1_b,           // pin 141
    output wire disp1_c,           // pin 135
    output wire disp1_d,           // pin 137
    output wire disp1_e,           // pin 136
    output wire disp1_f,           // pin 143
    output wire disp1_g,           // pin 144
    output wire disp1_dp,          // pin 133

    // ---- 7-Segment Display 2 - Error Count [7:4] ----
    output wire disp2_a,           // pin 72
    output wire disp2_b,           // pin 71
    output wire disp2_c,           // pin 69
    output wire disp2_d,           // pin 68
    output wire disp2_e,           // pin 67
    output wire disp2_f,           // pin 132
    output wire disp2_g,           // pin 66
    output wire disp2_dp,          // pin 65

    // ---- 7-Segment Display 3 - Error Count [11:8] ----
    output wire disp3_a,           // pin 105
    output wire disp3_b,           // pin 100
    output wire disp3_c,           // pin 99
    output wire disp3_d,           // pin 101
    output wire disp3_e,           // pin 103
    output wire disp3_f,           // pin 111
    output wire disp3_g,           // pin 119
    output wire disp3_dp,          // pin 98

    // ---- BER Test Signals on J13 ----
    output wire data_pattern_tx,   // J13-1, pin 52  - PRBS TX data to DUT
    input  wire data_pattern_rx,   // J13-2, pin 53  - Received data from DUT
    output wire clock_pattern_tx,  // J13-3, pin 54  - Clock output to DUT
    output wire data_tx_scope,     // J13-4, pin 55  - Delayed TX ref (scope)
    output wire data_rx_scope,     // J13-5, pin 88  - Synced RX data (scope)
	 

    // ---- Noise Generator Outputs on J8 ----
    output wire noise_1,           // J8-1, pin 61
    output wire noise_2,           // J8-2, pin 60
    output wire noise_3,           // J8-3, pin 59
    output wire noise_4,           // J8-4, pin 58
    output wire noise_5,           // J8-5, pin 51
    output wire noise_6            // J8-6, pin 50
);


// ============================================================================
// HARDCODED CONFIGURATION - Edit these and recompile to change settings
// ============================================================================
localparam ENABLE_CLOCK_TX  = 1'b1;    // 1 = drive clock out on clock_pattern_tx
localparam ENABLE_DATA_TX   = 1'b1;    // 1 = enable PRBS TX + error counter
localparam ENABLE_NOISE_1_4 = 1'b1;    // 1 = enable noise generators 1 & 4
localparam ENABLE_NOISE_2_3 = 1'b0;    // 1 = enable noise generators 2 & 3
localparam ENABLE_NOISE_5_6 = 1'b0;    // 1 = enable noise generators 5 & 6
localparam [1:0] DELAY_SEL  = 2'b00;   // 00=3cyc, 01=4cyc, 10=5cyc, 11=6cyc
localparam HALF_PERIOD      = 1'b1;    // 0=posedge sample, 1=negedge sample

// ============================================================================
// Internal signals
// ============================================================================
wire global_clk;
wire sync_reset;
wire error_flag;
wire [11:0] errors;

wire data_tx_raw;                       // PRBS output before delay
wire data_tx_delayed;                   // PRBS output after delay (reference)
wire sync_data_rx;                      // Synchronized received data
wire async_data_rx;                     // Muxed posedge/negedge sampled RX

reg [1:0] data_rx_sample;              // Posedge and negedge sampled RX
reg [25:0] inject_counter;
wire inject_error;
// 7-segment display buses
wire [6:0] hex_digit0;                 // Errors [3:0]
wire [6:0] hex_digit1;                 // Errors [7:4]
wire [6:0] hex_digit2;                 // Errors [11:8]
wire [6:0] hex_digit3;                 // Unused (would need 4th display)

// ============================================================================
// Clock - Direct 50 MHz, no PLL
// ============================================================================
// To use a different frequency, regenerate a PLL IP core for Cyclone 10 LP
// in Quartus IP Catalog and assign the desired output to global_clk.
assign global_clk = clk_50;

// ============================================================================
// Reset synchronizer
// ============================================================================
// pb_switch_1 is active-low (pressed = 0), invert for active-high reset
reset_synchroniser global_reset_sync (
    .clk        (global_clk),
    .async_reset(~pb_switch_1),
    .sync_reset (sync_reset)
);

// ============================================================================
// PRBS Data Pattern Generator (TX)
// ============================================================================
PRBS #(.LFSR_WIDTH(14)) data_prbs (
    .clock  (global_clk),
    .reset  (sync_reset),
    .enable (ENABLE_DATA_TX),
    .prbs   (data_tx_raw)
);

assign data_pattern_tx = data_tx_raw;

// ============================================================================
// Clock Pattern TX
// ============================================================================
// Drive clock out when enabled, high-Z when disabled
assign clock_pattern_tx = ENABLE_CLOCK_TX ? global_clk : 1'bz;

// ============================================================================
// TX Delay Line (reference path for error comparison)
// ============================================================================
delay delay_inst (
    .delay_select (DELAY_SEL),
    .signal_in    (data_tx_raw),
    .signal_out   (data_tx_delayed),
    .clk          (global_clk),
    .reset        (sync_reset),
    .enable       (ENABLE_DATA_TX)
);

// ============================================================================
// RX Input Sampling and Synchronization
// ============================================================================
// Sample incoming data on both clock edges
always @(posedge global_clk or posedge sync_reset) begin
    if (sync_reset)
        data_rx_sample[0] <= 1'b0;
    else
        data_rx_sample[0] <= data_tx_raw ^ inject_error;
end

always @(negedge global_clk or posedge sync_reset) begin
    if (sync_reset)
        data_rx_sample[1] <= 1'b0;
    else
        data_rx_sample[1] <= data_tx_raw;
end

// Select sampling edge based on HALF_PERIOD setting
assign async_data_rx = HALF_PERIOD ? data_rx_sample[0] : data_rx_sample[1];

// 2-FF synchronizer for metastability protection
signal_synchroniser #(.width(1)) rx_sync (
    .clk                (global_clk),
    .reset              (sync_reset),
    .asynchron_signal_in(async_data_rx),
    .synchron_signal_out(sync_data_rx)
);

// ============================================================================
// Error Counter
// ============================================================================
error_counter data_error_counter (
    .pattern1   (sync_data_rx),
    .pattern2   (data_tx_delayed),
    .clock      (global_clk),
    .reset      (sync_reset),
    .enable     (ENABLE_DATA_TX),
    .errors     (errors),
    .error_flag (error_flag)
);

// ============================================================================
// 7-Segment HEX Display (3 digits, 12-bit error count)
// ============================================================================
// Pad to 16 bits for the existing HEX_display module (digit3 unused)
HEX_display hex_disp (
    .digit0 (hex_digit0),
    .digit1 (hex_digit1),
    .digit2 (hex_digit2),
    .digit3 (hex_digit3),
    .data   ({4'b0, errors[11:0]})
);

// Display 1 segments (errors [3:0]) - active low for current-sink LEDs
assign disp1_a  = hex_digit2[0];
assign disp1_b  = hex_digit2[1];
assign disp1_c  = hex_digit2[2];
assign disp1_d  = hex_digit2[3];
assign disp1_e  = hex_digit2[4];
assign disp1_f  = hex_digit2[5];
assign disp1_g  = hex_digit2[6];
assign disp1_dp = 1'b1;                // Decimal point off (active low)

// Display 2 segments (errors [7:4])
assign disp2_a  = hex_digit1[0];
assign disp2_b  = hex_digit1[1];
assign disp2_c  = hex_digit1[2];
assign disp2_d  = hex_digit1[3];
assign disp2_e  = hex_digit1[4];
assign disp2_f  = hex_digit1[5];
assign disp2_g  = hex_digit1[6];
assign disp2_dp = 1'b1;

// Display 3 segments (errors [11:8])
assign disp3_a  = hex_digit0[0];
assign disp3_b  = hex_digit0[1];
assign disp3_c  = hex_digit0[2];
assign disp3_d  = hex_digit0[3];
assign disp3_e  = hex_digit0[4];
assign disp3_f  = hex_digit0[5];
assign disp3_g  = hex_digit0[6];
assign disp3_dp = 1'b1;

// ============================================================================
// Noise Generators (optional crosstalk injection)
// ============================================================================
PRBS #(.LFSR_WIDTH(10)) noise1_prbs (
    .clock(global_clk), .reset(sync_reset),
    .enable(ENABLE_NOISE_1_4), .prbs(noise_1)
);
PRBS #(.LFSR_WIDTH(11)) noise2_prbs (
    .clock(global_clk), .reset(sync_reset),
    .enable(ENABLE_NOISE_2_3), .prbs(noise_2)
);
PRBS #(.LFSR_WIDTH(12)) noise3_prbs (
    .clock(global_clk), .reset(sync_reset),
    .enable(ENABLE_NOISE_2_3), .prbs(noise_3)
);
PRBS #(.LFSR_WIDTH(13)) noise4_prbs (
    .clock(global_clk), .reset(sync_reset),
    .enable(ENABLE_NOISE_1_4), .prbs(noise_4)
);
PRBS #(.LFSR_WIDTH(15)) noise5_prbs (
    .clock(global_clk), .reset(sync_reset),
    .enable(ENABLE_NOISE_5_6), .prbs(noise_5)
);
PRBS #(.LFSR_WIDTH(16)) noise6_prbs (
    .clock(global_clk), .reset(sync_reset),
    .enable(ENABLE_NOISE_5_6), .prbs(noise_6)
);

// ============================================================================
// Scope Tap Outputs
// ============================================================================
assign data_tx_scope = data_tx_delayed;    // Delayed TX reference
assign data_rx_scope = sync_data_rx;       // Synchronized RX data

// ============================================================================
// LED Assignments
// ============================================================================
assign user_leds[0] = ~sync_reset;         // Lit when NOT in reset
assign user_leds[1] = ENABLE_DATA_TX;      // TX enabled indicator
assign user_leds[2] = ENABLE_CLOCK_TX;     // Clock TX enabled indicator
assign user_leds[3] = error_flag;          // Error counter saturated
assign user_leds[4] = data_tx_raw;         // Live TX data activity
assign user_leds[5] = sync_data_rx;        // Live RX data activity
assign user_leds[6] = 1'b0;               // Spare
assign user_leds[7] = 1'b0;               // Spare

// RGB LED - Red when errors detected, Green when running error-free
assign led_red   = error_flag;
assign led_green  = ENABLE_DATA_TX & ~error_flag;
assign led_blue  = 1'b0;

// Error injection for testing
always @(posedge global_clk or posedge sync_reset) begin
    if (sync_reset)
        inject_counter <= 26'b0;
    else
        inject_counter <= inject_counter + 1'b1;
end

assign inject_error = (inject_counter == 26'd0) & noise_1;  // one error pulse every ~1.3 seconds


endmodule