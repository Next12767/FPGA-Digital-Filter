//Copyright (C)2014-2025 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Tool Version: V1.9.11.03 Education
//Part Number: GW1NZ-LV1QN48C6/I5
//Device: GW1NZ-1
//Created Time: Sun Oct 11 15:30:31 2026

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

	DDS_II_5M your_instance_name(
		.clk_i(clk_i), //input clk_i
		.rst_n_i(rst_n_i), //input rst_n_i
		.sine_o(sine_o), //output [11:0] sine_o
		.data_valid_o(data_valid_o) //output data_valid_o
	);

//--------Copy end-------------------
