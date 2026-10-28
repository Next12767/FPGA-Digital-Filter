//  多项式：x^16 + x^14 + x^13 + x^11 + 1（最大长度，周期 65535）
//  幅度：A = 2^(11-SHIFT)，默认 SHIFT = 4，即 ±128
`timescale 1ns / 1ps

module noise_gen #(
    parameter [3:0] SHIFT = 4'd4
)(
    input                       clk,
    input                       rst_n,
    output wire signed [11:0]   noise_o
);

    reg [15:0] lfsr = 16'hACE1;         // 非零初值，避免锁死

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            lfsr <= 16'hACE1;
        else
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    end

    wire                     neg = lfsr[15];                        // 随机符号
    localparam signed [11:0] AMP = 12'sd1 << (11 - SHIFT);          // 噪声幅度

    assign noise_o = neg ? -AMP : AMP;

endmodule
