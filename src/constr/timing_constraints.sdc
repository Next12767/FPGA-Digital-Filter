//  timing_constraints.sdc  ——  时序约束
//
//  板载 27 MHz 晶振，经片内二分频得到 13.5 MHz 工作时钟。

// 27 MHz 输入时钟，周期 37.037 ns
create_clock -name sys_clk -period 37.037 [get_ports {clk}]

// 二分频产生的工作时钟，周期 74.074 ns
create_generated_clock -name clk_13m5 -source [get_ports {clk}] -divide_by 2 [get_pins {clk_half_s0/Q}]

// 两个时钟域异步
set_clock_groups -asynchronous -group {sys_clk} -group {clk_13m5}

// 分频寄存器本身只做时钟分频，其反馈路径不做时序检查
set_false_path -to [get_pins {clk_half_s0/D}]

// 按键为异步输入，模块内已做两级同步
set_false_path -from [get_ports {key_a}]
set_false_path -from [get_ports {key_b}]
