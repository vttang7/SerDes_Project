# ==============================================================================
# CycloFlex BER Tester - SDC Timing Constraints
# ==============================================================================

# 50 MHz input clock (20 ns period)
create_clock -name clk_50 -period 20.000 [get_ports {clk_50}]

# Constrain asynchronous inputs (pushbuttons, data_pattern_rx)
# These are asynchronous - use false path to prevent over-constraining
set_false_path -from [get_ports {pb_switch_1}] -to *
set_false_path -from [get_ports {pb_switch_2}] -to *

# The data_pattern_rx input is synchronized by a 2-FF synchronizer,
# so the first FF capture is inherently asynchronous
set_false_path -from [get_ports {data_pattern_rx}] -to *

# Output delays are not critical for this test design
set_false_path -from * -to [get_ports {user_leds[*]}]
set_false_path -from * -to [get_ports {led_red}]
set_false_path -from * -to [get_ports {led_blue}]
set_false_path -from * -to [get_ports {led_green}]
set_false_path -from * -to [get_ports {disp*}]
set_false_path -from * -to [get_ports {noise_*}]
set_false_path -from * -to [get_ports {data_tx_scope}]
set_false_path -from * -to [get_ports {data_rx_scope}]
