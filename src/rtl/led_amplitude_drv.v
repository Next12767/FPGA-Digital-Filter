`timescale 1ns / 1ps

module led_amplitude_drv #(
    parameter [3:0] GAIN_SHIFT = 4'd2
)(
    input                   clk,
    input                   rst_n,
    input  signed [11:0]    signal_in,
    output reg              led_out,
    input        [9:0]      pwm_cnt
);

    //取绝对值
    wire signed [12:0] x13   = signal_in;
    wire        [12:0] mag13 = x13[12] ? (~x13 + 13'd1) : x13;

    wire [9:0]  mag10 = mag13[10:1];
    wire [13:0] mag_g = {4'd0, mag10} << GAIN_SHIFT;
    wire [9:0]  mag_s = (mag_g > 14'd1023) ? 10'd1023 : mag_g[9:0];

    //峰值检测
    reg [9:0] peak_val  = 10'd0;
    reg [4:0] decay_cnt = 5'd0;

    wire pwm_wrap  = (pwm_cnt == 10'h3FF);
    wire decay_en  = pwm_wrap && (decay_cnt == 5'd26);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            peak_val  <= 10'd0;
            decay_cnt <= 5'd0;
        end else begin
            if (pwm_wrap) begin
                if (decay_cnt == 5'd26) decay_cnt <= 5'd0;
                else                    decay_cnt <= decay_cnt + 5'd1;
            end

            if (mag_s > peak_val)
                peak_val <= mag_s;                     // 上升沿立即跟随
            else if (decay_en && (peak_val != 10'd0))
                peak_val <= peak_val - 10'd1;          // 慢衰减
        end
    end

    //PWM 输出
    always @(*) begin
        led_out = (pwm_cnt >= peak_val);               // 共阳：低电平点亮
    end

endmodule
