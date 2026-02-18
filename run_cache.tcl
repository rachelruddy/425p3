vlib work
vcom memory.vhd
vcom cache.vhd
vcom cache_tb.vhd

vsim -voptargs=+acc cache_tb

add wave -r /*

run 2000 ns