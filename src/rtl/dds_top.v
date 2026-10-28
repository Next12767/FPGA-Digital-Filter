//  时钟：板载 27 MHz -> 二分频得到 13.5 MHz（clk_half），全设计单时钟域
//  采样率：13.5 MHz / 9 拍 = 1.5 MSPS
//  三档频率：100 kHz（通带）/ 300 kHz（截止）/ 600 kHz（深阻带）
//
//  数据流：
//     27 MHz ─► 二分频 ─► DDS_II (25 bit 相位 / 10 bit 正弦)
//            ─► 12 bit 符号扩展 ─► 叠加噪声(可关) ─► 15 阶 FIR (1.5 MSPS)
//            ─► 12 bit 饱和 ─► 峰值检测 + PWM ─► 蓝灯
//     红灯 = 固定 ~20% 占空比，作亮度参考
//
//  按键：
//     A 短按 = 恢复默认（低通 + 100 kHz + 关噪声）并复位
//     A 长按 >= 1 s = 循环切换滤波模式（低通/高通/带通），按住只切一次
//     B 短按 = 循环切换频率档位（100k / 300k / 600k）
//     B 长按 >= 1 s = 噪声开关（纯正弦 <-> 带噪），按住只切一次
//
//  参数：
//     DDS_SIGNED  DDS 输出格式。1 = 二进制补码（高云 DDS II 默认），
//                 0 = 无符号偏移码 0..1023
//     NOISE_SHIFT 噪声幅度，越大噪声越小（默认 4 -> ±128，约 9 dB 信噪比）
//     FORCE_MODE  3 = 三模式跟随按键；0/1/2 = 固定模式
`timescale 1ns / 1ps

module dds_top(
    input           clk,        // 板载 27 MHz
    input           key_a,      // KEY_A，低有效
    input           key_b,      // KEY_B，低有效
    output          led_r,      // 红灯：固定亮度参考
    output          led_b       // 蓝灯：滤波后幅度
);

    parameter        DDS_SIGNED  = 1'b1;
    parameter        NOISE_EN    = 1'b0;    // 1 = 综合噪声叠加通路，0 = 纯正弦
    parameter [3:0]  NOISE_SHIFT = 4'd4;    // 噪声幅度：越大噪声越小（4 -> ±128）
    // 3 = 三模式可切换（正常演示）；0/1/2 = 固定低通/高通/带通
    parameter [1:0]  FORCE_MODE  = 2'd3;
    //  0. 27 MHz -> 13.5 MHz（二分频，全设计单时钟域）
    reg clk_half = 1'b0;

    always @(posedge clk)
        clk_half <= ~clk_half;

    //  1. 上电复位（16 拍 @13.5 MHz）
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

    //  2. 按键消抖 + 按键控制
    wire       key_a_deb;
    wire       key_b_deb;
    wire [1:0] freq_sel;
    wire [1:0] filter_sel;
    wire       soft_rst_n;
    wire       noise_en;

    key_debounce u_deb_key_a(
        .clk     (clk_half),
        .rst_n   (por_rst_n),
        .key_in  (key_a),
        .key_out (key_a_deb)
    );

    key_debounce u_deb_key_b(
        .clk     (clk_half),
        .rst_n   (por_rst_n),
        .key_in  (key_b),
        .key_out (key_b_deb)
    );

    key_ctrl u_key_ctrl(
        .clk        (clk_half),
        .rst_n      (por_rst_n),
        .key_a      (key_a_deb),
        .key_b      (key_b_deb),
        .sys_rst_n  (soft_rst_n),
        .freq_sel   (freq_sel),
        .filter_sel (filter_sel),
        .noise_en   (noise_en)
    );

    wire rst_n = por_rst_n & soft_rst_n;

    //  3. DDS：25 bit 相位累加，f_out = INC * 13.5 MHz / 2^25
    //     100 kHz -> 0x03CAE7   300 kHz -> 0x0B60B6   600 kHz -> 0x16C16C
    localparam [24:0] INC_100K = 25'h03CAE7;
    localparam [24:0] INC_300K = 25'h0B60B6;
    localparam [24:0] INC_600K = 25'h16C16C;

    wire [24:0] phase_inc = (freq_sel == 2'd0) ? INC_100K :
                            (freq_sel == 2'd1) ? INC_300K : INC_600K;

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

    // 10 bit -> 12 bit 有符号
    wire signed [11:0] sine_s;
    generate
        if (DDS_SIGNED) begin : g_dds_signed
            assign sine_s = {{2{dds_sine[9]}}, dds_sine};
        end else begin : g_dds_offset
            assign sine_s = $signed({1'b0, dds_sine}) - 12'sd512;
        end
    endgenerate

    //  4. 噪声叠加
    //     NOISE_EN = 1 时综合该通路，运行时由长按 B 控制开关；
    //     NOISE_EN = 0 时该通路不参与综合，滤波器直接使用正弦信号。
    wire signed [11:0] fir_in;

    generate
        if (NOISE_EN) begin : g_noise
            wire signed [11:0] noise_s;
            wire signed [12:0] mix;
            noise_gen #(.SHIFT(NOISE_SHIFT)) u_noise (
                .clk     (clk_half),
                .rst_n   (rst_n),
                .noise_o (noise_s)
            );
            assign mix    = {sine_s[11], sine_s} + (noise_en ? noise_s : 13'sd0);
            assign fir_in = mix[11:0];
        end else begin : g_clean
            assign fir_in = sine_s;
        end
    endgenerate

    //  5. 15 阶三模式 FIR（1.5 MSPS）
    wire signed [11:0] fir_out;

    fir_3mode #(.FORCE_MODE(FORCE_MODE)) u_fir (
        .clk        (clk_half),
        .rst_n      (rst_n),
        .filter_sel (filter_sel),
        .data_in    (fir_in),
        .data_out   (fir_out)
    );

    //  6. LED
    reg [9:0] pwm_cnt;

    always @(posedge clk_half or negedge rst_n) begin
        if (!rst_n)
            pwm_cnt <= 10'd0;
        else
            pwm_cnt <= pwm_cnt + 10'd1;     
    end

    // 红灯：约 25% 固定占空比（共阳，低电平点亮）
    // 用计数器的高两位做占空比
    assign led_r = ~(pwm_cnt[9] & pwm_cnt[8]);

    led_amplitude_drv u_led (
        .clk       (clk_half),
        .rst_n     (rst_n),
        .signal_in (fir_out),
        .led_out   (led_b),
        .pwm_cnt   (pwm_cnt)
    );

endmodule
