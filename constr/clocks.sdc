# 12 MHz external osc on sys_clk
create_clock -name sys_clk -period 83.333 [get_ports {sys_clk}]

# Treat SCLK as an async external clock domain
create_clock -name sclk -period 1000.0 [get_ports {sclk}]

# Tell STA they’re asynchronous to each other
set_clock_groups -asynchronous -group {sys_clk} -group {sclk}
