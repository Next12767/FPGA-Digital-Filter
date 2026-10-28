//       FORCE_MODE : 0=低通  1=高通  2=带通
//       FREQ_SEL   : 0=100k  1=300k  2=600k

`timescale 1ns / 1ps

module dds_top_debug(
    input           clk,        // 板载 27 MHz
    input           key_a,      
    input           key_b,      
    output          led_r,
    output          led_b
);

    localparam [1:0] FORCE_MODE = 2'd0;     // 0=低通 1=高通 2=带通
    localparam [1:0] FREQ_SEL   = 2'd0;     // 0=100k 1=300k 2=600k
    // NOISE_ON: 1 = 滤波前叠加白噪声，0 = 纯正弦输入
    // 叠加噪声后分析仪核无法同时放入本器件
    localparam       NOISE_ON   = 1'b0;

    //  0. 27 MHz -> 13.5 MHz
    reg clk_half = 1'b0;

    always @(posedge clk)
        clk_half <= ~clk_half;

    //  1. 上电复位（16 拍）
    reg [3:0] por_cnt   = 4'd0;
    reg       por_rst_n = 1'b0;

    always @(posedge clk_half) begin
        if (por_cnt != 4'd15) begin
            por_cnt   <= por_cnt + 4'd1;
            por_rst_n <= 1'b0;
        end else begin
            por_rst_n <= 1'b1;
        end
    end

    wire rst_n = por_rst_n;

    //  2. DDS
    localparam [24:0] INC_100K = 25'h03CAE7;
    localparam [24:0] INC_300K = 25'h0B60B6;
    localparam [24:0] INC_600K = 25'h16C16C;

    wire [24:0] phase_inc = (FREQ_SEL == 2'd0) ? INC_100K :
                            (FREQ_SEL == 2'd1) ? INC_300K : INC_600K;

    wire [9:0] dds_sine;
    wire       dds_valid;

    DDS_II_Top u_dds (
        .clk_i          (clk_half),
        .rst_n_i        (rst_n),
        .config_valid_i (1'b1),
        .config_inc_i   (phase_inc),
        .sine_o         (dds_sine),
        .data_valid_o   (dds_valid)
    );

    wire signed [11:0] sine_s = {{2{dds_sine[9]}}, dds_sine};

    //  2.5 噪声叠加（NOISE_ON=1 时叠加白噪声）
    wire signed [11:0] noise_s;
    wire signed [12:0] mix;

    noise_gen #(.SHIFT(4'd4)) u_noise (
        .clk     (clk_half),
        .rst_n   (rst_n),
        .noise_o (noise_s)
    );

    assign mix = {sine_s[11], sine_s} + (NOISE_ON ? noise_s : 13'sd0);

    // 叠加结果寄存一拍后送入滤波器，缩短组合路径
    reg signed [11:0] fir_in = 12'sd0;
    always @(posedge clk_half or negedge rst_n) begin
        if (!rst_n) fir_in <= 12'sd0;
        else        fir_in <= mix[11:0];
    end

    //  3. FIR（模式由参数固定）
    wire signed [11:0] fir_out;

    fir_3mode #(.FORCE_MODE(FORCE_MODE)) u_fir (
        .clk        (clk_half),
        .rst_n      (rst_n),
        .filter_sel (2'd0),
        .data_in    (fir_in),
        .data_out   (fir_out)
    );

    //  4. 输出
    //     led_b：异或当假负载，保证 FIR 不被优化掉
    //     led_r：接按键，既给调试反馈，又保住 key 端口不被综合掉
    assign led_b = ^fir_out[11:2];
    assign led_r = key_a & key_b;       // 共阳低电平点亮：按键按下 -> 红灯亮

endmodule
