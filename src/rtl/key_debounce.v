`timescale 1ns / 1ps

module key_debounce(
    input               clk,
    input               rst_n,
    input               key_in,
    output reg          key_out
);

    parameter [19:0] CNT_MAX = 20'd270_000;    // 20 ms @ 13.5 MHz

    reg [19:0] cnt      = 20'd0;
    reg        key_sync1 = 1'b1;
    reg        key_sync2 = 1'b1;

    // 两级同步，避免亚稳态
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_sync1 <= 1'b1;
            key_sync2 <= 1'b1;
        end else begin
            key_sync1 <= key_in;
            key_sync2 <= key_sync1;
        end
    end

    // 电平稳定超过 CNT_MAX 拍才更新输出
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt     <= 20'd0;
            key_out <= 1'b1;
        end else if (key_sync2 != key_out) begin
            if (cnt < CNT_MAX) begin
                cnt <= cnt + 20'd1;
            end else begin
                cnt     <= 20'd0;
                key_out <= key_sync2;
            end
        end else begin
            cnt <= 20'd0;
        end
    end

endmodule
