proc AddWaves {} {
	;#Add wves we're interested in
	add wave -position end sim:/memory_tb/clk
	add wave -position end sim:/memory_tb/address
    	add wave -position end sim:/memory_tb/writedata
    	add wave -position end sim:/memory_tb/readdata
    	add wave -position end sim:/memory_tb/memwrite
    	add wave -position end sim:/memory_tb/memread
    	add wave -position end sim:/memory_tb/waitrequest
}

vlib work

;#compile components
vcom memory.vhd
vcom memory_tb.vhd

;#start sim
vsim memory_tb

;#add waves
AddWaves

;#run until completion
run -all