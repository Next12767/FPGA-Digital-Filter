//  两级流水 + 1 拍排空（乘法器单独占一级，累加器占另一级）：
//      cnt :  0     1     2   ...  7     8
//      1 级:  P0    P1    P2  ...  P7    -      <- 13x10 乘法
//      2 级:  -    +P0   +P1  ...  +P6   +P7    <- 25 位累加
//      种子: 帧首预置 256（Q9，实现四舍五入）
//
//  滤波器结构：
//    15 阶（奇数，Type I）
//        h[k]    = c[k]      k = 0..6
//        h[7]    = c[7]      （中心抽头）
//        h[14-k] = c[k]
//    8 个独立系数、1 个乘法器。
//
//  系数设计条件：Fs = 1.5 MHz，Hamming 窗
//        LPF  fc = 300 kHz        HPF  fc = 300 kHz
//        BPF  250 kHz ~ 600 kHz
//
//  三档频率的灯效（蓝灯占空比）：
//        LPF: 100k 亮   / 300k 半亮 / 600k 灭
//        HPF: 100k 灭   / 300k 半亮 / 600k 亮
//        BPF: 100k 灭   / 300k 亮   / 600k 半亮
`timescale 1ns / 1ps

module fir_3mode(
    input                       clk,
    input                       rst_n,
    input       [1:0]           filter_sel,   // 00=低通 01=高通 10=带通
    input  signed [11:0]        data_in,      // 12 bit 有符号
    output reg signed [11:0]    data_out      // 12 bit 有符号，已饱和
);

    // 3 = 跟随 filter_sel；0/1/2 = 固定模式
    parameter [1:0] FORCE_MODE = 2'd3;

    localparam [1:0] MODE_LP = 2'd0;
    localparam [1:0] MODE_HP = 2'd1;
    localparam [1:0] MODE_BP = 2'd2;

    // 系数表（Q9，十进制，负数直接写负号）
    wire signed [9:0] c_lp [0:7];
    assign c_lp[0] =  10'sd1;
    assign c_lp[1] =  10'sd3;
    assign c_lp[2] =  10'sd0;
    assign c_lp[3] = -10'sd17;
    assign c_lp[4] = -10'sd20;
    assign c_lp[5] =  10'sd39;
    assign c_lp[6] =  10'sd147;
    assign c_lp[7] =  10'sd206;

    wire signed [9:0] c_hp [0:7];
    assign c_hp[0] = -10'sd1;
    assign c_hp[1] = -10'sd3;
    assign c_hp[2] =  10'sd0;
    assign c_hp[3] =  10'sd17;
    assign c_hp[4] =  10'sd20;
    assign c_hp[5] = -10'sd39;
    assign c_hp[6] = -10'sd147;
    assign c_hp[7] =  10'sd306;

    wire signed [9:0] c_bp [0:7];
    assign c_bp[0] = -10'sd3;
    assign c_bp[1] =  10'sd2;
    assign c_bp[2] =  10'sd7;
    assign c_bp[3] =  10'sd5;
    assign c_bp[4] =  10'sd34;
    assign c_bp[5] = -10'sd124;
    assign c_bp[6] = -10'sd44;
    assign c_bp[7] =  10'sd242;

    // 15 级移位寄存器 + 9 拍帧计数器
    reg signed [11:0] sr [0:14];
    reg [3:0]         cnt;          // 0..8
    reg [1:0]         mode_lat;     // 帧边界锁存模式，避免半帧换系数
    reg signed [9:0]  curr_coeff;
    reg signed [12:0] add_val;
    reg signed [22:0] prod_r;       // 1 级：乘积（13x10 -> 23）
    reg signed [24:0] acc;          // 2 级：累加
    integer i;

    wire [2:0] cidx = cnt[2:0];     // cnt=8 时不会用到有效系数

    // FORCE_MODE = 3 表示跟随 filter_sel，0/1/2 表示固定低通/高通/带通。
    wire [1:0] mode_sel = (FORCE_MODE == 2'd3) ? mode_lat : FORCE_MODE;

    always @(*) begin
        case (mode_sel)
            MODE_HP: curr_coeff = c_hp[cidx];
            MODE_BP: curr_coeff = c_bp[cidx];
            default: curr_coeff = c_lp[cidx];
        endcase
    end

    always @(*) begin
        case (cidx)
            3'd0:    add_val = sr[0] + sr[14];
            3'd1:    add_val = sr[1] + sr[13];
            3'd2:    add_val = sr[2] + sr[12];
            3'd3:    add_val = sr[3] + sr[11];
            3'd4:    add_val = sr[4] + sr[10];
            3'd5:    add_val = sr[5] + sr[9];
            3'd6:    add_val = sr[6] + sr[8];
            default: add_val = sr[7];               // 中心抽头
        endcase
    end

    // 乘累加：acc 右移 9 位（Q9）后要能放进 12 bit
    wire signed [22:0] prod    = add_val * curr_coeff;      // 13 x 10 -> 23
    wire signed [24:0] prod_ex = {{2{prod_r[22]}}, prod_r};
    wire signed [24:0] acc_nx  = acc + prod_ex;

    // acc[24:21] 全 0 或全 1 才不溢出，输出取 acc[20:9]
    wire ovf = (acc_nx[24:21] != 4'h0) && (acc_nx[24:21] != 4'hF);
    wire signed [11:0] out_sat = ovf ? (acc_nx[24] ? 12'sh800 : 12'sh7FF)
                                     : acc_nx[20:9];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt      <= 4'd0;
            mode_lat <= MODE_LP;
            acc      <= 25'sd0;
            prod_r   <= 23'sd0;
            data_out <= 12'sd0;
            for (i = 0; i < 15; i = i + 1)
                sr[i] <= 12'sd0;
        end else begin
            //1 级流水：乘积（第 9 拍没有有效乘积）
            if (cnt == 4'd8)
                prod_r <= 23'sd0;
            else
                prod_r <= prod;

            //2 级流水：累加 
            if (cnt == 4'd0)
                acc <= 25'sd256;                // 帧首预置半 LSB（Q9 四舍五入）
            else
                acc <= acc_nx;

            //帧控制：第 9 拍移入新样本、锁存模式
            if (cnt == 4'd8) begin
                cnt <= 4'd0;
                sr[0] <= data_in;
                for (i = 1; i < 15; i = i + 1)
                    sr[i] <= sr[i-1];
                mode_lat <= filter_sel;
            end else begin
                cnt <= cnt + 4'd1;
            end

            //输出：帧首拍寄存上一帧的最终和
            if (cnt == 4'd0)
                data_out <= out_sat;
        end
    end

endmodule
