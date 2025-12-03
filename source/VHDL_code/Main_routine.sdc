# ------------------------------------------------------------
# Clock definition
# ------------------------------------------------------------
# Main system clock: 50 MHz => period 20 ns
create_clock -name clk -period 20.0 [get_ports clk]

# ------------------------------------------------------------
# Input delays
# ------------------------------------------------------------
# Allow external setup/hold to the FPGA inputs (adjust if needed)
set_input_delay -clock clk 5.0 [get_ports MQ135_DOUT]
set_input_delay -clock clk 5.0 [get_ports RX]
set_input_delay -clock clk 5.0 [get_ports send]
set_input_delay -clock clk 5.0 [get_ports tx_byte]

# ------------------------------------------------------------
# Output delays
# ------------------------------------------------------------
# Expected delays to external devices (servo, UART TX, LEDs, buzzer)
set_output_delay -clock clk 5.0 [get_ports TX]
set_output_delay -clock clk 5.0 [get_ports pwd]
set_output_delay -clock clk 5.0 [get_ports LED_R]
set_output_delay -clock clk 5.0 [get_ports LED_V]
set_output_delay -clock clk 5.0 [get_ports BUZZER]
set_output_delay -clock clk 5.0 [get_ports busy]
set_output_delay -clock clk 5.0 [get_ports data_byte]
set_output_delay -clock clk 5.0 [get_ports data_valid]

# ------------------------------------------------------------
# False paths
# ------------------------------------------------------------
# Asynchronous reset and external sensor inputs
set_false_path -from [get_ports RESET_N]
set_false_path -from [get_ports MQ135_DOUT]
set_false_path -from [get_ports RX]

# ------------------------------------------------------------
# Multi-cycle paths
# ------------------------------------------------------------
# UART RX logic: sampling occurs slower than system clock
# It takes ~1 bit-time = 434 clocks, but within FPGA we just need 2-cycle setup for counter/shift
set_multicycle_path -from [get_registers rx_sync2] -to [get_registers shift_rx[*]] 2

# PWM logic: allow multi-cycle path for combinational assignment of pulse_width
set_multicycle_path -from [get_registers servo] -to [get_registers pulse_width] 2

# MQ135 debounce: counter increments over many cycles, so internal path is multi-cycle
set_multicycle_path -from [get_registers mq135_sync2] -to [get_registers mq135_state] 10

# ------------------------------------------------------------
# Timing exceptions summary
# ------------------------------------------------------------
# - Asynchronous inputs: MQ135_DOUT, RX, RESET_N
# - UART RX and PWM: allow multi-cycle paths to reduce setup pressure
# - Outputs: expected external timing
