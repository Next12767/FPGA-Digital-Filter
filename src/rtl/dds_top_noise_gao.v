//  功能：片内产生正弦信号并叠加宽带噪声，滤波前后的数据同时送入片上
//        逻辑分析仪，用于观察噪声被抑制的效果。
//  结构：轻量正弦表（256 点 ROM）-> 叠加噪声 -> 15 阶 FIR -> 分析仪探针
//        分析仪采样时钟 clk_half，同时采集 fir_in 与 data_out 各 12 位
`timescale 1ns / 1ps

module dds_top_noise_gao(
    input           clk,        // 板载 27 MHz 时钟
    input           key_a,      // 备用按键输入
    input           key_b,
    output          led_r,
    output          led_b
);

    localparam [1:0] FORCE_MODE = 2'd0;     // 0=低通 1=高通 2=带通
    localparam [1:0] FREQ_SEL   = 2'd0;     // 0=100k 1=300k 2=600k

    //  0. 27 MHz -> 13.5 MHz
    reg clk_half = 1'b0;

    always @(posedge clk)
        clk_half <= ~clk_half;

    //  1. 上电复位
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

    //  2. 正弦信号发生器（256 点正弦表，16 bit 相位累加）
    //     f_out = INC * 13.5 MHz / 2^16
    //       100 kHz -> 485    300 kHz -> 1456    600 kHz -> 2913
    localparam [15:0] INC_100K = 16'd485;
    localparam [15:0] INC_300K = 16'd1456;
    localparam [15:0] INC_600K = 16'd2913;

    wire [15:0] phase_inc = (FREQ_SEL == 2'd0) ? INC_100K :
                            (FREQ_SEL == 2'd1) ? INC_300K : INC_600K;

    reg  [15:0] phase = 16'd0;
    reg  [9:0]  dds_sine = 10'd0;
    reg  [9:0]  sin_rom [0:255];

    initial begin
        sin_rom[0] = 10'h000;
        sin_rom[1] = 10'h00D;
        sin_rom[2] = 10'h019;
        sin_rom[3] = 10'h026;
        sin_rom[4] = 10'h032;
        sin_rom[5] = 10'h03F;
        sin_rom[6] = 10'h04B;
        sin_rom[7] = 10'h057;
        sin_rom[8] = 10'h064;
        sin_rom[9] = 10'h070;
        sin_rom[10] = 10'h07C;
        sin_rom[11] = 10'h088;
        sin_rom[12] = 10'h094;
        sin_rom[13] = 10'h0A0;
        sin_rom[14] = 10'h0AC;
        sin_rom[15] = 10'h0B8;
        sin_rom[16] = 10'h0C4;
        sin_rom[17] = 10'h0CF;
        sin_rom[18] = 10'h0DA;
        sin_rom[19] = 10'h0E6;
        sin_rom[20] = 10'h0F1;
        sin_rom[21] = 10'h0FC;
        sin_rom[22] = 10'h107;
        sin_rom[23] = 10'h111;
        sin_rom[24] = 10'h11C;
        sin_rom[25] = 10'h126;
        sin_rom[26] = 10'h130;
        sin_rom[27] = 10'h13A;
        sin_rom[28] = 10'h144;
        sin_rom[29] = 10'h14E;
        sin_rom[30] = 10'h157;
        sin_rom[31] = 10'h160;
        sin_rom[32] = 10'h169;
        sin_rom[33] = 10'h172;
        sin_rom[34] = 10'h17B;
        sin_rom[35] = 10'h183;
        sin_rom[36] = 10'h18B;
        sin_rom[37] = 10'h193;
        sin_rom[38] = 10'h19A;
        sin_rom[39] = 10'h1A2;
        sin_rom[40] = 10'h1A9;
        sin_rom[41] = 10'h1B0;
        sin_rom[42] = 10'h1B6;
        sin_rom[43] = 10'h1BD;
        sin_rom[44] = 10'h1C3;
        sin_rom[45] = 10'h1C8;
        sin_rom[46] = 10'h1CE;
        sin_rom[47] = 10'h1D3;
        sin_rom[48] = 10'h1D8;
        sin_rom[49] = 10'h1DD;
        sin_rom[50] = 10'h1E1;
        sin_rom[51] = 10'h1E5;
        sin_rom[52] = 10'h1E9;
        sin_rom[53] = 10'h1EC;
        sin_rom[54] = 10'h1F0;
        sin_rom[55] = 10'h1F3;
        sin_rom[56] = 10'h1F5;
        sin_rom[57] = 10'h1F7;
        sin_rom[58] = 10'h1F9;
        sin_rom[59] = 10'h1FB;
        sin_rom[60] = 10'h1FD;
        sin_rom[61] = 10'h1FE;
        sin_rom[62] = 10'h1FE;
        sin_rom[63] = 10'h1FF;
        sin_rom[64] = 10'h1FF;
        sin_rom[65] = 10'h1FF;
        sin_rom[66] = 10'h1FE;
        sin_rom[67] = 10'h1FE;
        sin_rom[68] = 10'h1FD;
        sin_rom[69] = 10'h1FB;
        sin_rom[70] = 10'h1F9;
        sin_rom[71] = 10'h1F7;
        sin_rom[72] = 10'h1F5;
        sin_rom[73] = 10'h1F3;
        sin_rom[74] = 10'h1F0;
        sin_rom[75] = 10'h1EC;
        sin_rom[76] = 10'h1E9;
        sin_rom[77] = 10'h1E5;
        sin_rom[78] = 10'h1E1;
        sin_rom[79] = 10'h1DD;
        sin_rom[80] = 10'h1D8;
        sin_rom[81] = 10'h1D3;
        sin_rom[82] = 10'h1CE;
        sin_rom[83] = 10'h1C8;
        sin_rom[84] = 10'h1C3;
        sin_rom[85] = 10'h1BD;
        sin_rom[86] = 10'h1B6;
        sin_rom[87] = 10'h1B0;
        sin_rom[88] = 10'h1A9;
        sin_rom[89] = 10'h1A2;
        sin_rom[90] = 10'h19A;
        sin_rom[91] = 10'h193;
        sin_rom[92] = 10'h18B;
        sin_rom[93] = 10'h183;
        sin_rom[94] = 10'h17B;
        sin_rom[95] = 10'h172;
        sin_rom[96] = 10'h169;
        sin_rom[97] = 10'h160;
        sin_rom[98] = 10'h157;
        sin_rom[99] = 10'h14E;
        sin_rom[100] = 10'h144;
        sin_rom[101] = 10'h13A;
        sin_rom[102] = 10'h130;
        sin_rom[103] = 10'h126;
        sin_rom[104] = 10'h11C;
        sin_rom[105] = 10'h111;
        sin_rom[106] = 10'h107;
        sin_rom[107] = 10'h0FC;
        sin_rom[108] = 10'h0F1;
        sin_rom[109] = 10'h0E6;
        sin_rom[110] = 10'h0DA;
        sin_rom[111] = 10'h0CF;
        sin_rom[112] = 10'h0C4;
        sin_rom[113] = 10'h0B8;
        sin_rom[114] = 10'h0AC;
        sin_rom[115] = 10'h0A0;
        sin_rom[116] = 10'h094;
        sin_rom[117] = 10'h088;
        sin_rom[118] = 10'h07C;
        sin_rom[119] = 10'h070;
        sin_rom[120] = 10'h064;
        sin_rom[121] = 10'h057;
        sin_rom[122] = 10'h04B;
        sin_rom[123] = 10'h03F;
        sin_rom[124] = 10'h032;
        sin_rom[125] = 10'h026;
        sin_rom[126] = 10'h019;
        sin_rom[127] = 10'h00D;
        sin_rom[128] = 10'h000;
        sin_rom[129] = 10'h3F3;
        sin_rom[130] = 10'h3E7;
        sin_rom[131] = 10'h3DA;
        sin_rom[132] = 10'h3CE;
        sin_rom[133] = 10'h3C1;
        sin_rom[134] = 10'h3B5;
        sin_rom[135] = 10'h3A9;
        sin_rom[136] = 10'h39C;
        sin_rom[137] = 10'h390;
        sin_rom[138] = 10'h384;
        sin_rom[139] = 10'h378;
        sin_rom[140] = 10'h36C;
        sin_rom[141] = 10'h360;
        sin_rom[142] = 10'h354;
        sin_rom[143] = 10'h348;
        sin_rom[144] = 10'h33C;
        sin_rom[145] = 10'h331;
        sin_rom[146] = 10'h326;
        sin_rom[147] = 10'h31A;
        sin_rom[148] = 10'h30F;
        sin_rom[149] = 10'h304;
        sin_rom[150] = 10'h2F9;
        sin_rom[151] = 10'h2EF;
        sin_rom[152] = 10'h2E4;
        sin_rom[153] = 10'h2DA;
        sin_rom[154] = 10'h2D0;
        sin_rom[155] = 10'h2C6;
        sin_rom[156] = 10'h2BC;
        sin_rom[157] = 10'h2B2;
        sin_rom[158] = 10'h2A9;
        sin_rom[159] = 10'h2A0;
        sin_rom[160] = 10'h297;
        sin_rom[161] = 10'h28E;
        sin_rom[162] = 10'h285;
        sin_rom[163] = 10'h27D;
        sin_rom[164] = 10'h275;
        sin_rom[165] = 10'h26D;
        sin_rom[166] = 10'h266;
        sin_rom[167] = 10'h25E;
        sin_rom[168] = 10'h257;
        sin_rom[169] = 10'h250;
        sin_rom[170] = 10'h24A;
        sin_rom[171] = 10'h243;
        sin_rom[172] = 10'h23D;
        sin_rom[173] = 10'h238;
        sin_rom[174] = 10'h232;
        sin_rom[175] = 10'h22D;
        sin_rom[176] = 10'h228;
        sin_rom[177] = 10'h223;
        sin_rom[178] = 10'h21F;
        sin_rom[179] = 10'h21B;
        sin_rom[180] = 10'h217;
        sin_rom[181] = 10'h214;
        sin_rom[182] = 10'h210;
        sin_rom[183] = 10'h20D;
        sin_rom[184] = 10'h20B;
        sin_rom[185] = 10'h209;
        sin_rom[186] = 10'h207;
        sin_rom[187] = 10'h205;
        sin_rom[188] = 10'h203;
        sin_rom[189] = 10'h202;
        sin_rom[190] = 10'h202;
        sin_rom[191] = 10'h201;
        sin_rom[192] = 10'h201;
        sin_rom[193] = 10'h201;
        sin_rom[194] = 10'h202;
        sin_rom[195] = 10'h202;
        sin_rom[196] = 10'h203;
        sin_rom[197] = 10'h205;
        sin_rom[198] = 10'h207;
        sin_rom[199] = 10'h209;
        sin_rom[200] = 10'h20B;
        sin_rom[201] = 10'h20D;
        sin_rom[202] = 10'h210;
        sin_rom[203] = 10'h214;
        sin_rom[204] = 10'h217;
        sin_rom[205] = 10'h21B;
        sin_rom[206] = 10'h21F;
        sin_rom[207] = 10'h223;
        sin_rom[208] = 10'h228;
        sin_rom[209] = 10'h22D;
        sin_rom[210] = 10'h232;
        sin_rom[211] = 10'h238;
        sin_rom[212] = 10'h23D;
        sin_rom[213] = 10'h243;
        sin_rom[214] = 10'h24A;
        sin_rom[215] = 10'h250;
        sin_rom[216] = 10'h257;
        sin_rom[217] = 10'h25E;
        sin_rom[218] = 10'h266;
        sin_rom[219] = 10'h26D;
        sin_rom[220] = 10'h275;
        sin_rom[221] = 10'h27D;
        sin_rom[222] = 10'h285;
        sin_rom[223] = 10'h28E;
        sin_rom[224] = 10'h297;
        sin_rom[225] = 10'h2A0;
        sin_rom[226] = 10'h2A9;
        sin_rom[227] = 10'h2B2;
        sin_rom[228] = 10'h2BC;
        sin_rom[229] = 10'h2C6;
        sin_rom[230] = 10'h2D0;
        sin_rom[231] = 10'h2DA;
        sin_rom[232] = 10'h2E4;
        sin_rom[233] = 10'h2EF;
        sin_rom[234] = 10'h2F9;
        sin_rom[235] = 10'h304;
        sin_rom[236] = 10'h30F;
        sin_rom[237] = 10'h31A;
        sin_rom[238] = 10'h326;
        sin_rom[239] = 10'h331;
        sin_rom[240] = 10'h33C;
        sin_rom[241] = 10'h348;
        sin_rom[242] = 10'h354;
        sin_rom[243] = 10'h360;
        sin_rom[244] = 10'h36C;
        sin_rom[245] = 10'h378;
        sin_rom[246] = 10'h384;
        sin_rom[247] = 10'h390;
        sin_rom[248] = 10'h39C;
        sin_rom[249] = 10'h3A9;
        sin_rom[250] = 10'h3B5;
        sin_rom[251] = 10'h3C1;
        sin_rom[252] = 10'h3CE;
        sin_rom[253] = 10'h3DA;
        sin_rom[254] = 10'h3E7;
        sin_rom[255] = 10'h3F3;
    end

    always @(posedge clk_half or negedge rst_n) begin
        if (!rst_n) begin
            phase    <= 16'd0;
            dds_sine <= 10'd0;
        end else begin
            phase    <= phase + phase_inc;
            dds_sine <= sin_rom[phase[15:8]];
        end
    end

    wire signed [11:0] sine_s = {{2{dds_sine[9]}}, dds_sine};

    //  3. 噪声叠加（12 bit LFSR，x^12+x^6+x^4+x+1，幅度 ±128）
    reg [11:0] lfsr = 12'hACE;

    always @(posedge clk_half or negedge rst_n) begin
        if (!rst_n) lfsr <= 12'hACE;
        else        lfsr <= {lfsr[10:0], lfsr[11] ^ lfsr[5] ^ lfsr[3] ^ lfsr[0]};
    end

    wire signed [11:0] noise_s = lfsr[11] ? 12'sd128 : -12'sd128;
    wire signed [12:0] mix     = {sine_s[11], sine_s} + noise_s;

    reg signed [11:0] fir_in = 12'sd0;

    always @(posedge clk_half or negedge rst_n) begin
        if (!rst_n) fir_in <= 12'sd0;
        else        fir_in <= mix[11:0];
    end

    //  4. FIR 滤波
    wire signed [11:0] fir_out;

    fir_3mode #(.FORCE_MODE(FORCE_MODE)) u_fir (
        .clk        (clk_half),
        .rst_n      (rst_n),
        .filter_sel (2'd0),
        .data_in    (fir_in),
        .data_out   (fir_out)
    );

    //  5. 输出（分析仪探针为 fir_in 与 fir_out，此处仅保留端口负载）
    assign led_b = ^fir_out[11:2];
    assign led_r = key_a & key_b;

endmodule
