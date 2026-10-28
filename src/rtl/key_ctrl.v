//  键 A（KEY_A）
//      短按（松手时仍 < 1 s）：**恢复上电默认状态**（低通 + 100 kHz + 关噪声）并软复位
//                              —— 灯效会立刻回到"低通 + 100k 全亮"，演示时好用
//      长按 >= 1 s          ：循环切换滤波模式 低通 -> 高通 -> 带通 -> 低通
//                             **只在越过 1 s 的那一瞬间切一次**，一直按住不会连切
//  键 B（KEY_B）
//      短按：循环切换频率档位 100 kHz -> 300 kHz -> 600 kHz -> 100 kHz
//      长按 >= 1 s：切换噪声开关（纯正弦 <-> 叠加噪声），同样只切一次
//
//  注意：所有时间常数按 13.5 MHz 计算（clk 是二分频后的时钟）
`timescale 1ns / 1ps

module key_ctrl(
    input               clk,
    input               rst_n,
    input               key_a,        // 已消抖
    input               key_b,        // 已消抖
    output reg          sys_rst_n,    // 低有效软复位（只复位 DDS/FIR）
    output reg [1:0]    freq_sel,     // 00=100k 01=300k 10=600k
    output reg [1:0]    filter_sel,   // 00=低通 01=高通 10=带通
    output reg          noise_en      // 1=叠加噪声 0=纯正弦（上电默认 0）
);

    parameter [23:0] LONG_PRESS_CNT = 24'd13_500_000;   // 1 s @ 13.5 MHz
    parameter [7:0]  RST_PULSE_CNT  = 8'd64;            // 复位脉冲宽度 64 拍 = 4.7 us

    reg key_a_d = 1'b1;
    reg key_b_d = 1'b1;
    reg long_a  = 1'b0;
    reg long_b  = 1'b0;
    reg long_a_d = 1'b0;
    reg long_b_d = 1'b0;
    reg [23:0] cnt_a = 24'd0;
    reg [23:0] cnt_b = 24'd0;
    reg [7:0]  rst_cnt = 8'd0;

    wire a_down  = ~key_a &  key_a_d;      // 按下
    wire a_up    =  key_a & ~key_a_d;      // 松开
    wire b_up    =  key_b & ~key_b_d;
    wire lp_a    = long_a & ~long_a_d;     // 长按触发：单拍脉冲
    wire lp_b    = long_b & ~long_b_d;     // 长按 B：切换噪声开关
    wire rst_req = a_up & ~long_a;         // 短按松手：请求软复位

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_a_d  <= 1'b1;
            key_b_d  <= 1'b1;
            long_a   <= 1'b0;
            long_b   <= 1'b0;
            long_a_d <= 1'b0;
            long_b_d <= 1'b0;
            cnt_a    <= 24'd0;
            cnt_b    <= 24'd0;
            rst_cnt  <= 8'd0;
            sys_rst_n  <= 1'b0;
            freq_sel   <= 2'd0;     // 上电默认 100 kHz（通带，灯亮）
            filter_sel <= 2'd0;     // 上电默认低通
            noise_en   <= 1'b0;     // 上电默认不叠加噪声
        end else begin
            key_a_d  <= key_a;
            key_b_d  <= key_b;
            long_a_d <= long_a;
            long_b_d <= long_b;

            //长按计时
            if (a_down) begin
                cnt_a  <= 24'd0;
                long_a <= 1'b0;
            end else if (~key_a) begin
                if (cnt_a < LONG_PRESS_CNT) cnt_a  <= cnt_a + 24'd1;
                else                        long_a <= 1'b1;
            end else begin
                cnt_a  <= 24'd0;
                long_a <= 1'b0;
            end

            if (~key_b) begin
                if (cnt_b < LONG_PRESS_CNT) cnt_b  <= cnt_b + 24'd1;
                else                        long_b <= 1'b1;
            end else begin
                cnt_b  <= 24'd0;
                long_b <= 1'b0;
            end

            //软复位脉冲
            if (rst_req) begin
                sys_rst_n <= 1'b0;
                rst_cnt   <= RST_PULSE_CNT;
            end else if (rst_cnt != 8'd0) begin
                rst_cnt   <= rst_cnt - 8'd1;
                sys_rst_n <= (rst_cnt == 8'd1);
            end else begin
                sys_rst_n <= 1'b1;
            end

            //模式 / 档位
            // 短按 A 优先：恢复上电默认状态（低通 + 100 kHz + 关噪声）
            if (rst_req) begin
                filter_sel <= 2'd0;
                freq_sel   <= 2'd0;
                noise_en   <= 1'b0;
            end else begin
                // 长按 A：切模式
                if (lp_a)
                    filter_sel <= (filter_sel == 2'd2) ? 2'd0 : filter_sel + 2'd1;

                // 长按 B：切换噪声开关（按满 1 秒切一次）
                if (lp_b)
                    noise_en <= ~noise_en;

                // 短按 B：切频率
                if (b_up && ~long_b)
                    freq_sel <= (freq_sel == 2'd2) ? 2'd0 : freq_sel + 2'd1;
            end
        end
    end

endmodule
