proc AddWaves {} {
	;#Add waves we're interested in to the Wave window
    add wave -position end sim:/cache_tb/clk
    add wave -position end sim:/cache_tb/s_waitrequest
    add wave -position end sim:/cache_tb/s_read
    add wave -position end sim:/cache_tb/s_write
    add wave -position end sim:/cache_tb/s_addr
    add wave -position end sim:/cache_tb/s_writedata
    add wave -position end sim:/cache_tb/s_readdata
    
}

vlib work

;# Compile components if any
vcom cache.vhd
vcom cache_tb.vhd
vcom memory.vhd
vcom memory_tb.vhd

;# Start simulation
vsim cache_tb

;# Generate a clock with 1ns period
force -deposit clk 0 0 ns, 1 0.5 ns -repeat 1 ns

;# Add the waves
AddWaves

;# Running and breakpoints
#bp cache_tb.vhd 266
#bp cache_tb.vhd 123
#bp cache.vhd 187
#bp cache.vhd 200
#run 500 ns
run 542 ns
