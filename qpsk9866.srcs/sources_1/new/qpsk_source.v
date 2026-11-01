`timescale 1ns / 1ps
// 6 MHz QPSK，19.2 MSPS；分数符号定时2 Msymbol/s，4 Mbps。
module qpsk_source #(
    parameter integer sample_bits = 10  // 有效位数，接口固定12位
)(
    input wire sys_clk,                 // 系统时钟
    input wire sys_rst_n,               // 低有效复位
    input wire [1:0] symbol_data,       // 两位符号，bit1控制I，bit0控制Q
    input wire symbol_valid,           // 输入符号有效
    output wire symbol_ready,          // 可以接收一个符号
    input wire sample_en,              // 当前样点实际写入FIFO
    output wire sample_valid,          // 当前样点有效
    output wire [11:0] sample          // AD9865高两位补零
);
    reg [1:0] current_symbol, next_symbol; // 当前和预取符号
    reg current_valid, next_valid;     // 符号有效标志
    reg [5:0] symbol_phase;            // 每样点加5，模48，对应2/19.2
    reg [3:0] carrier_phase;           // 每样点加5，模16，对应6/19.2
    reg signed [11:0] carrier_i, carrier_q; // 正交载波Q10，幅度由成形系数控制
    reg shaped_valid, product_valid, output_valid;
    wire pipeline_step = !output_valid || sample_en;
    wire symbol_end = pipeline_step && current_valid && symbol_phase >= 43;
    wire load_symbol = !current_valid || symbol_end;
    assign symbol_ready = !next_valid || load_symbol;
    assign sample_valid = output_valid;
    reg [1:0] symbol_history[0:7];      // 前8个符号，成形跨帧连续
    reg [7:0] history_valid;            // 启动前历史用零填充
    integer history_index;
    integer tap_index;
    reg signed [19:0] shaped_i, shaped_q; // I/Q成形结果，Q8
    reg signed [15:0] tap_value;        // 当前相位的脉冲系数
    reg [1:0] tap_symbol;              // 当前累加符号
    reg tap_valid;
    reg signed [19:0] shaped_i_reg, shaped_q_reg; // 成形流水级
    reg signed [11:0] carrier_i_reg, carrier_q_reg; // 对齐载波
    reg signed [31:0] product_i, product_q; // 乘法流水级
    reg [11:0] output_sample;              // 量化流水级

    wire signed [32:0] mixed_sample = $signed({product_i[31],product_i}) - $signed({product_q[31],product_q});
    wire signed [32:0] rounded_sample = mixed_sample < 0 ?
        -(((-mixed_sample) + 33'sd131072) >>> 18) :
        ((mixed_sample + 33'sd131072) >>> 18);
    wire signed [9:0] limited_sample = rounded_sample > 511 ? 10'sd511 :
        (rounded_sample < -512 ? -10'sd512 : rounded_sample[9:0]);
    assign sample = output_sample;
    // 统一时钟使能冻结全部流水级，反压时不丢样、不错位。
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            shaped_i_reg <= 0; shaped_q_reg <= 0;
            carrier_i_reg <= 0; carrier_q_reg <= 0;
            product_i <= 0; product_q <= 0;
            shaped_valid <= 0; product_valid <= 0; output_valid <= 0;
            output_sample <= 0;
        end else if (pipeline_step) begin
            shaped_valid <= current_valid;
            shaped_i_reg <= shaped_i; shaped_q_reg <= shaped_q;
            carrier_i_reg <= carrier_i; carrier_q_reg <= carrier_q;
            product_valid <= shaped_valid;
            product_i <= shaped_i_reg * carrier_i_reg;
            product_q <= shaped_q_reg * carrier_q_reg;
            output_valid <= product_valid;
            if (product_valid)
                output_sample <= sample_bits == 10 ? {2'b00,limited_sample} : {limited_sample,2'b00};
            else output_sample <= 0;
        end
    end
    // 根升余弦：rolloff=0.35，跨度8符号，48分数相位；系数含幅度缩放。
    always @* begin
        shaped_i = 0; shaped_q = 0;
        tap_value = 0; tap_symbol = 0; tap_valid = 0;
        for (tap_index = 0; tap_index < 9; tap_index = tap_index + 1) begin
            tap_value = pulse_coefficient(symbol_phase * 9 + tap_index);
            if (tap_index == 0) begin
                tap_symbol = current_symbol; tap_valid = current_valid;
            end else begin
                tap_symbol = symbol_history[tap_index-1];
                tap_valid = history_valid[tap_index-1];
            end
            if (tap_valid) begin
                if (tap_symbol[1]) shaped_i = shaped_i - tap_value;
                else shaped_i = shaped_i + tap_value;
                if (tap_symbol[0]) shaped_q = shaped_q - tap_value;
                else shaped_q = shaped_q + tap_value;
            end
        end
    end
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            current_symbol <= 0; next_symbol <= 0;
            current_valid <= 0; next_valid <= 0;
            symbol_phase <= 0; carrier_phase <= 0;
            history_valid <= 0;
            for (history_index = 0; history_index < 8; history_index = history_index + 1)
                symbol_history[history_index] <= 0;
        end else begin
            if (pipeline_step && current_valid) begin
                carrier_phase <= carrier_phase + 4'd5;
                if (symbol_phase >= 43) symbol_phase <= symbol_phase - 6'd43;
                else symbol_phase <= symbol_phase + 6'd5;
            end
            if (symbol_end) begin
                for (history_index = 7; history_index > 0; history_index = history_index - 1)
                    symbol_history[history_index] <= symbol_history[history_index-1];
                symbol_history[0] <= current_symbol;
                history_valid <= {history_valid[6:0],current_valid};
            end
            if (load_symbol) begin
                if (next_valid) begin
                    current_symbol <= next_symbol; current_valid <= 1;
                    next_valid <= 0;
                    if (symbol_valid && symbol_ready) begin
                        next_symbol <= symbol_data; next_valid <= 1;
                    end
                end else if (symbol_valid && symbol_ready) begin
                    current_symbol <= symbol_data; current_valid <= 1;
                end else current_valid <= 0;
            end else if (symbol_valid && symbol_ready) begin
                next_symbol <= symbol_data; next_valid <= 1;
            end
        end
    end
    // 正交载波Q10，样点接受后才推进相位；不在符号边界重置。
    always @* begin
        case (carrier_phase)
            4'd0: begin carrier_i = 12'sh400; carrier_q = 12'sh000; end
            4'd1: begin carrier_i = 12'sh3b2; carrier_q = 12'sh188; end
            4'd2: begin carrier_i = 12'sh2d4; carrier_q = 12'sh2d4; end
            4'd3: begin carrier_i = 12'sh188; carrier_q = 12'sh3b2; end
            4'd4: begin carrier_i = 12'sh000; carrier_q = 12'sh400; end
            4'd5: begin carrier_i = 12'she78; carrier_q = 12'sh3b2; end
            4'd6: begin carrier_i = 12'shd2c; carrier_q = 12'sh2d4; end
            4'd7: begin carrier_i = 12'shc4e; carrier_q = 12'sh188; end
            4'd8: begin carrier_i = 12'shc00; carrier_q = 12'sh000; end
            4'd9: begin carrier_i = 12'shc4e; carrier_q = 12'she78; end
            4'd10: begin carrier_i = 12'shd2c; carrier_q = 12'shd2c; end
            4'd11: begin carrier_i = 12'she78; carrier_q = 12'shc4e; end
            4'd12: begin carrier_i = 12'sh000; carrier_q = 12'shc00; end
            4'd13: begin carrier_i = 12'sh188; carrier_q = 12'shc4e; end
            4'd14: begin carrier_i = 12'sh2d4; carrier_q = 12'shd2c; end
            4'd15: begin carrier_i = 12'sh3b2; carrier_q = 12'she78; end
            default: begin carrier_i = 0; carrier_q = 0; end
        endcase
    end
    function signed [15:0] pulse_coefficient;
        input integer address;
        begin
            case (address)
                0: pulse_coefficient = 16'sh000e;
                1: pulse_coefficient = 16'shff48;
                2: pulse_coefficient = 16'sh019c;
                3: pulse_coefficient = 16'shfd9e;
                4: pulse_coefficient = 16'sh1ede;
                5: pulse_coefficient = 16'shfd9e;
                6: pulse_coefficient = 16'sh019c;
                7: pulse_coefficient = 16'shff48;
                8: pulse_coefficient = 16'sh000e;
                9: pulse_coefficient = 16'sh0018;
                10: pulse_coefficient = 16'shff46;
                11: pulse_coefficient = 16'sh0180;
                12: pulse_coefficient = 16'shfe1c;
                13: pulse_coefficient = 16'sh1ed6;
                14: pulse_coefficient = 16'shfd2a;
                15: pulse_coefficient = 16'sh01b4;
                16: pulse_coefficient = 16'shff4c;
                17: pulse_coefficient = 16'sh0000;
                18: pulse_coefficient = 16'sh0020;
                19: pulse_coefficient = 16'shff44;
                20: pulse_coefficient = 16'sh0160;
                21: pulse_coefficient = 16'shfea2;
                22: pulse_coefficient = 16'sh1ec0;
                23: pulse_coefficient = 16'shfcc0;
                24: pulse_coefficient = 16'sh01ca;
                25: pulse_coefficient = 16'shff52;
                26: pulse_coefficient = 16'sh0000;
                27: pulse_coefficient = 16'sh0028;
                28: pulse_coefficient = 16'shff46;
                29: pulse_coefficient = 16'sh013c;
                30: pulse_coefficient = 16'shff34;
                31: pulse_coefficient = 16'sh1e9c;
                32: pulse_coefficient = 16'shfc5e;
                33: pulse_coefficient = 16'sh01da;
                34: pulse_coefficient = 16'shff58;
                35: pulse_coefficient = 16'sh0000;
                36: pulse_coefficient = 16'sh0030;
                37: pulse_coefficient = 16'shff48;
                38: pulse_coefficient = 16'sh0114;
                39: pulse_coefficient = 16'shffd0;
                40: pulse_coefficient = 16'sh1e6a;
                41: pulse_coefficient = 16'shfc08;
                42: pulse_coefficient = 16'sh01e8;
                43: pulse_coefficient = 16'shff60;
                44: pulse_coefficient = 16'sh0000;
                45: pulse_coefficient = 16'sh0038;
                46: pulse_coefficient = 16'shff4a;
                47: pulse_coefficient = 16'sh00e8;
                48: pulse_coefficient = 16'sh0074;
                49: pulse_coefficient = 16'sh1e2a;
                50: pulse_coefficient = 16'shfbbc;
                51: pulse_coefficient = 16'sh01f2;
                52: pulse_coefficient = 16'shff6a;
                53: pulse_coefficient = 16'sh0000;
                54: pulse_coefficient = 16'sh0040;
                55: pulse_coefficient = 16'shff50;
                56: pulse_coefficient = 16'sh00ba;
                57: pulse_coefficient = 16'sh0120;
                58: pulse_coefficient = 16'sh1ddc;
                59: pulse_coefficient = 16'shfb7a;
                60: pulse_coefficient = 16'sh01f8;
                61: pulse_coefficient = 16'shff74;
                62: pulse_coefficient = 16'sh0000;
                63: pulse_coefficient = 16'sh0046;
                64: pulse_coefficient = 16'shff58;
                65: pulse_coefficient = 16'sh0088;
                66: pulse_coefficient = 16'sh01d6;
                67: pulse_coefficient = 16'sh1d80;
                68: pulse_coefficient = 16'shfb42;
                69: pulse_coefficient = 16'sh01fa;
                70: pulse_coefficient = 16'shff7e;
                71: pulse_coefficient = 16'sh0000;
                72: pulse_coefficient = 16'sh004e;
                73: pulse_coefficient = 16'shff60;
                74: pulse_coefficient = 16'sh0052;
                75: pulse_coefficient = 16'sh0294;
                76: pulse_coefficient = 16'sh1d16;
                77: pulse_coefficient = 16'shfb12;
                78: pulse_coefficient = 16'sh01f8;
                79: pulse_coefficient = 16'shff8a;
                80: pulse_coefficient = 16'sh0000;
                81: pulse_coefficient = 16'sh0052;
                82: pulse_coefficient = 16'shff6a;
                83: pulse_coefficient = 16'sh001a;
                84: pulse_coefficient = 16'sh0358;
                85: pulse_coefficient = 16'sh1ca0;
                86: pulse_coefficient = 16'shfaec;
                87: pulse_coefficient = 16'sh01f4;
                88: pulse_coefficient = 16'shff94;
                89: pulse_coefficient = 16'sh0000;
                90: pulse_coefficient = 16'sh0058;
                91: pulse_coefficient = 16'shff78;
                92: pulse_coefficient = 16'shffde;
                93: pulse_coefficient = 16'sh0426;
                94: pulse_coefficient = 16'sh1c1e;
                95: pulse_coefficient = 16'shfad0;
                96: pulse_coefficient = 16'sh01ee;
                97: pulse_coefficient = 16'shffa2;
                98: pulse_coefficient = 16'sh0000;
                99: pulse_coefficient = 16'sh005c;
                100: pulse_coefficient = 16'shff86;
                101: pulse_coefficient = 16'shffa0;
                102: pulse_coefficient = 16'sh04fa;
                103: pulse_coefficient = 16'sh1b90;
                104: pulse_coefficient = 16'shfabc;
                105: pulse_coefficient = 16'sh01e4;
                106: pulse_coefficient = 16'shffae;
                107: pulse_coefficient = 16'sh0000;
                108: pulse_coefficient = 16'sh0060;
                109: pulse_coefficient = 16'shff96;
                110: pulse_coefficient = 16'shff60;
                111: pulse_coefficient = 16'sh05d4;
                112: pulse_coefficient = 16'sh1af6;
                113: pulse_coefficient = 16'shfab0;
                114: pulse_coefficient = 16'sh01d8;
                115: pulse_coefficient = 16'shffbc;
                116: pulse_coefficient = 16'sh0000;
                117: pulse_coefficient = 16'sh0062;
                118: pulse_coefficient = 16'shffa6;
                119: pulse_coefficient = 16'shff1e;
                120: pulse_coefficient = 16'sh06b4;
                121: pulse_coefficient = 16'sh1a52;
                122: pulse_coefficient = 16'shfaac;
                123: pulse_coefficient = 16'sh01c8;
                124: pulse_coefficient = 16'shffc8;
                125: pulse_coefficient = 16'sh0000;
                126: pulse_coefficient = 16'sh0064;
                127: pulse_coefficient = 16'shffba;
                128: pulse_coefficient = 16'shfedc;
                129: pulse_coefficient = 16'sh079a;
                130: pulse_coefficient = 16'sh19a2;
                131: pulse_coefficient = 16'shfab0;
                132: pulse_coefficient = 16'sh01b6;
                133: pulse_coefficient = 16'shffd6;
                134: pulse_coefficient = 16'sh0000;
                135: pulse_coefficient = 16'sh0066;
                136: pulse_coefficient = 16'shffce;
                137: pulse_coefficient = 16'shfe96;
                138: pulse_coefficient = 16'sh0884;
                139: pulse_coefficient = 16'sh18ea;
                140: pulse_coefficient = 16'shfabc;
                141: pulse_coefficient = 16'sh01a4;
                142: pulse_coefficient = 16'shffe2;
                143: pulse_coefficient = 16'sh0000;
                144: pulse_coefficient = 16'sh0066;
                145: pulse_coefficient = 16'shffe4;
                146: pulse_coefficient = 16'shfe50;
                147: pulse_coefficient = 16'sh0972;
                148: pulse_coefficient = 16'sh1828;
                149: pulse_coefficient = 16'shfad0;
                150: pulse_coefficient = 16'sh018e;
                151: pulse_coefficient = 16'shfff0;
                152: pulse_coefficient = 16'sh0000;
                153: pulse_coefficient = 16'sh0066;
                154: pulse_coefficient = 16'shfffc;
                155: pulse_coefficient = 16'shfe0a;
                156: pulse_coefficient = 16'sh0a64;
                157: pulse_coefficient = 16'sh175c;
                158: pulse_coefficient = 16'shfaea;
                159: pulse_coefficient = 16'sh0176;
                160: pulse_coefficient = 16'shfffc;
                161: pulse_coefficient = 16'sh0000;
                162: pulse_coefficient = 16'sh0064;
                163: pulse_coefficient = 16'sh0014;
                164: pulse_coefficient = 16'shfdc4;
                165: pulse_coefficient = 16'sh0b58;
                166: pulse_coefficient = 16'sh168a;
                167: pulse_coefficient = 16'shfb0a;
                168: pulse_coefficient = 16'sh015e;
                169: pulse_coefficient = 16'sh0008;
                170: pulse_coefficient = 16'sh0000;
                171: pulse_coefficient = 16'sh0060;
                172: pulse_coefficient = 16'sh002e;
                173: pulse_coefficient = 16'shfd7e;
                174: pulse_coefficient = 16'sh0c4e;
                175: pulse_coefficient = 16'sh15b0;
                176: pulse_coefficient = 16'shfb2e;
                177: pulse_coefficient = 16'sh0144;
                178: pulse_coefficient = 16'sh0014;
                179: pulse_coefficient = 16'sh0000;
                180: pulse_coefficient = 16'sh005e;
                181: pulse_coefficient = 16'sh0048;
                182: pulse_coefficient = 16'shfd38;
                183: pulse_coefficient = 16'sh0d44;
                184: pulse_coefficient = 16'sh14d0;
                185: pulse_coefficient = 16'shfb5a;
                186: pulse_coefficient = 16'sh012a;
                187: pulse_coefficient = 16'sh0020;
                188: pulse_coefficient = 16'sh0000;
                189: pulse_coefficient = 16'sh0058;
                190: pulse_coefficient = 16'sh0064;
                191: pulse_coefficient = 16'shfcf4;
                192: pulse_coefficient = 16'sh0e3c;
                193: pulse_coefficient = 16'sh13ea;
                194: pulse_coefficient = 16'shfb8a;
                195: pulse_coefficient = 16'sh010e;
                196: pulse_coefficient = 16'sh002a;
                197: pulse_coefficient = 16'sh0000;
                198: pulse_coefficient = 16'sh0052;
                199: pulse_coefficient = 16'sh0080;
                200: pulse_coefficient = 16'shfcb0;
                201: pulse_coefficient = 16'sh0f34;
                202: pulse_coefficient = 16'sh1300;
                203: pulse_coefficient = 16'shfbbe;
                204: pulse_coefficient = 16'sh00f2;
                205: pulse_coefficient = 16'sh0034;
                206: pulse_coefficient = 16'sh0000;
                207: pulse_coefficient = 16'sh004c;
                208: pulse_coefficient = 16'sh009c;
                209: pulse_coefficient = 16'shfc70;
                210: pulse_coefficient = 16'sh102a;
                211: pulse_coefficient = 16'sh1212;
                212: pulse_coefficient = 16'shfbf6;
                213: pulse_coefficient = 16'sh00d6;
                214: pulse_coefficient = 16'sh003c;
                215: pulse_coefficient = 16'sh0000;
                216: pulse_coefficient = 16'sh0046;
                217: pulse_coefficient = 16'sh00b8;
                218: pulse_coefficient = 16'shfc32;
                219: pulse_coefficient = 16'sh1120;
                220: pulse_coefficient = 16'sh1120;
                221: pulse_coefficient = 16'shfc32;
                222: pulse_coefficient = 16'sh00b8;
                223: pulse_coefficient = 16'sh0046;
                224: pulse_coefficient = 16'sh0000;
                225: pulse_coefficient = 16'sh003c;
                226: pulse_coefficient = 16'sh00d6;
                227: pulse_coefficient = 16'shfbf6;
                228: pulse_coefficient = 16'sh1212;
                229: pulse_coefficient = 16'sh102a;
                230: pulse_coefficient = 16'shfc70;
                231: pulse_coefficient = 16'sh009c;
                232: pulse_coefficient = 16'sh004c;
                233: pulse_coefficient = 16'sh0000;
                234: pulse_coefficient = 16'sh0034;
                235: pulse_coefficient = 16'sh00f2;
                236: pulse_coefficient = 16'shfbbe;
                237: pulse_coefficient = 16'sh1300;
                238: pulse_coefficient = 16'sh0f34;
                239: pulse_coefficient = 16'shfcb0;
                240: pulse_coefficient = 16'sh0080;
                241: pulse_coefficient = 16'sh0052;
                242: pulse_coefficient = 16'sh0000;
                243: pulse_coefficient = 16'sh002a;
                244: pulse_coefficient = 16'sh010e;
                245: pulse_coefficient = 16'shfb8a;
                246: pulse_coefficient = 16'sh13ea;
                247: pulse_coefficient = 16'sh0e3c;
                248: pulse_coefficient = 16'shfcf4;
                249: pulse_coefficient = 16'sh0064;
                250: pulse_coefficient = 16'sh0058;
                251: pulse_coefficient = 16'sh0000;
                252: pulse_coefficient = 16'sh0020;
                253: pulse_coefficient = 16'sh012a;
                254: pulse_coefficient = 16'shfb5a;
                255: pulse_coefficient = 16'sh14d0;
                256: pulse_coefficient = 16'sh0d44;
                257: pulse_coefficient = 16'shfd38;
                258: pulse_coefficient = 16'sh0048;
                259: pulse_coefficient = 16'sh005e;
                260: pulse_coefficient = 16'sh0000;
                261: pulse_coefficient = 16'sh0014;
                262: pulse_coefficient = 16'sh0144;
                263: pulse_coefficient = 16'shfb2e;
                264: pulse_coefficient = 16'sh15b0;
                265: pulse_coefficient = 16'sh0c4e;
                266: pulse_coefficient = 16'shfd7e;
                267: pulse_coefficient = 16'sh002e;
                268: pulse_coefficient = 16'sh0060;
                269: pulse_coefficient = 16'sh0000;
                270: pulse_coefficient = 16'sh0008;
                271: pulse_coefficient = 16'sh015e;
                272: pulse_coefficient = 16'shfb0a;
                273: pulse_coefficient = 16'sh168a;
                274: pulse_coefficient = 16'sh0b58;
                275: pulse_coefficient = 16'shfdc4;
                276: pulse_coefficient = 16'sh0014;
                277: pulse_coefficient = 16'sh0064;
                278: pulse_coefficient = 16'sh0000;
                279: pulse_coefficient = 16'shfffc;
                280: pulse_coefficient = 16'sh0176;
                281: pulse_coefficient = 16'shfaea;
                282: pulse_coefficient = 16'sh175c;
                283: pulse_coefficient = 16'sh0a64;
                284: pulse_coefficient = 16'shfe0a;
                285: pulse_coefficient = 16'shfffc;
                286: pulse_coefficient = 16'sh0066;
                287: pulse_coefficient = 16'sh0000;
                288: pulse_coefficient = 16'shfff0;
                289: pulse_coefficient = 16'sh018e;
                290: pulse_coefficient = 16'shfad0;
                291: pulse_coefficient = 16'sh1828;
                292: pulse_coefficient = 16'sh0972;
                293: pulse_coefficient = 16'shfe50;
                294: pulse_coefficient = 16'shffe4;
                295: pulse_coefficient = 16'sh0066;
                296: pulse_coefficient = 16'sh0000;
                297: pulse_coefficient = 16'shffe2;
                298: pulse_coefficient = 16'sh01a4;
                299: pulse_coefficient = 16'shfabc;
                300: pulse_coefficient = 16'sh18ea;
                301: pulse_coefficient = 16'sh0884;
                302: pulse_coefficient = 16'shfe96;
                303: pulse_coefficient = 16'shffce;
                304: pulse_coefficient = 16'sh0066;
                305: pulse_coefficient = 16'sh0000;
                306: pulse_coefficient = 16'shffd6;
                307: pulse_coefficient = 16'sh01b6;
                308: pulse_coefficient = 16'shfab0;
                309: pulse_coefficient = 16'sh19a2;
                310: pulse_coefficient = 16'sh079a;
                311: pulse_coefficient = 16'shfedc;
                312: pulse_coefficient = 16'shffba;
                313: pulse_coefficient = 16'sh0064;
                314: pulse_coefficient = 16'sh0000;
                315: pulse_coefficient = 16'shffc8;
                316: pulse_coefficient = 16'sh01c8;
                317: pulse_coefficient = 16'shfaac;
                318: pulse_coefficient = 16'sh1a52;
                319: pulse_coefficient = 16'sh06b4;
                320: pulse_coefficient = 16'shff1e;
                321: pulse_coefficient = 16'shffa6;
                322: pulse_coefficient = 16'sh0062;
                323: pulse_coefficient = 16'sh0000;
                324: pulse_coefficient = 16'shffbc;
                325: pulse_coefficient = 16'sh01d8;
                326: pulse_coefficient = 16'shfab0;
                327: pulse_coefficient = 16'sh1af6;
                328: pulse_coefficient = 16'sh05d4;
                329: pulse_coefficient = 16'shff60;
                330: pulse_coefficient = 16'shff96;
                331: pulse_coefficient = 16'sh0060;
                332: pulse_coefficient = 16'sh0000;
                333: pulse_coefficient = 16'shffae;
                334: pulse_coefficient = 16'sh01e4;
                335: pulse_coefficient = 16'shfabc;
                336: pulse_coefficient = 16'sh1b90;
                337: pulse_coefficient = 16'sh04fa;
                338: pulse_coefficient = 16'shffa0;
                339: pulse_coefficient = 16'shff86;
                340: pulse_coefficient = 16'sh005c;
                341: pulse_coefficient = 16'sh0000;
                342: pulse_coefficient = 16'shffa2;
                343: pulse_coefficient = 16'sh01ee;
                344: pulse_coefficient = 16'shfad0;
                345: pulse_coefficient = 16'sh1c1e;
                346: pulse_coefficient = 16'sh0426;
                347: pulse_coefficient = 16'shffde;
                348: pulse_coefficient = 16'shff78;
                349: pulse_coefficient = 16'sh0058;
                350: pulse_coefficient = 16'sh0000;
                351: pulse_coefficient = 16'shff94;
                352: pulse_coefficient = 16'sh01f4;
                353: pulse_coefficient = 16'shfaec;
                354: pulse_coefficient = 16'sh1ca0;
                355: pulse_coefficient = 16'sh0358;
                356: pulse_coefficient = 16'sh001a;
                357: pulse_coefficient = 16'shff6a;
                358: pulse_coefficient = 16'sh0052;
                359: pulse_coefficient = 16'sh0000;
                360: pulse_coefficient = 16'shff8a;
                361: pulse_coefficient = 16'sh01f8;
                362: pulse_coefficient = 16'shfb12;
                363: pulse_coefficient = 16'sh1d16;
                364: pulse_coefficient = 16'sh0294;
                365: pulse_coefficient = 16'sh0052;
                366: pulse_coefficient = 16'shff60;
                367: pulse_coefficient = 16'sh004e;
                368: pulse_coefficient = 16'sh0000;
                369: pulse_coefficient = 16'shff7e;
                370: pulse_coefficient = 16'sh01fa;
                371: pulse_coefficient = 16'shfb42;
                372: pulse_coefficient = 16'sh1d80;
                373: pulse_coefficient = 16'sh01d6;
                374: pulse_coefficient = 16'sh0088;
                375: pulse_coefficient = 16'shff58;
                376: pulse_coefficient = 16'sh0046;
                377: pulse_coefficient = 16'sh0000;
                378: pulse_coefficient = 16'shff74;
                379: pulse_coefficient = 16'sh01f8;
                380: pulse_coefficient = 16'shfb7a;
                381: pulse_coefficient = 16'sh1ddc;
                382: pulse_coefficient = 16'sh0120;
                383: pulse_coefficient = 16'sh00ba;
                384: pulse_coefficient = 16'shff50;
                385: pulse_coefficient = 16'sh0040;
                386: pulse_coefficient = 16'sh0000;
                387: pulse_coefficient = 16'shff6a;
                388: pulse_coefficient = 16'sh01f2;
                389: pulse_coefficient = 16'shfbbc;
                390: pulse_coefficient = 16'sh1e2a;
                391: pulse_coefficient = 16'sh0074;
                392: pulse_coefficient = 16'sh00e8;
                393: pulse_coefficient = 16'shff4a;
                394: pulse_coefficient = 16'sh0038;
                395: pulse_coefficient = 16'sh0000;
                396: pulse_coefficient = 16'shff60;
                397: pulse_coefficient = 16'sh01e8;
                398: pulse_coefficient = 16'shfc08;
                399: pulse_coefficient = 16'sh1e6a;
                400: pulse_coefficient = 16'shffd0;
                401: pulse_coefficient = 16'sh0114;
                402: pulse_coefficient = 16'shff48;
                403: pulse_coefficient = 16'sh0030;
                404: pulse_coefficient = 16'sh0000;
                405: pulse_coefficient = 16'shff58;
                406: pulse_coefficient = 16'sh01da;
                407: pulse_coefficient = 16'shfc5e;
                408: pulse_coefficient = 16'sh1e9c;
                409: pulse_coefficient = 16'shff34;
                410: pulse_coefficient = 16'sh013c;
                411: pulse_coefficient = 16'shff46;
                412: pulse_coefficient = 16'sh0028;
                413: pulse_coefficient = 16'sh0000;
                414: pulse_coefficient = 16'shff52;
                415: pulse_coefficient = 16'sh01ca;
                416: pulse_coefficient = 16'shfcc0;
                417: pulse_coefficient = 16'sh1ec0;
                418: pulse_coefficient = 16'shfea2;
                419: pulse_coefficient = 16'sh0160;
                420: pulse_coefficient = 16'shff44;
                421: pulse_coefficient = 16'sh0020;
                422: pulse_coefficient = 16'sh0000;
                423: pulse_coefficient = 16'shff4c;
                424: pulse_coefficient = 16'sh01b4;
                425: pulse_coefficient = 16'shfd2a;
                426: pulse_coefficient = 16'sh1ed6;
                427: pulse_coefficient = 16'shfe1c;
                428: pulse_coefficient = 16'sh0180;
                429: pulse_coefficient = 16'shff46;
                430: pulse_coefficient = 16'sh0018;
                431: pulse_coefficient = 16'sh0000;
                default: pulse_coefficient = 0;
            endcase
        end
    endfunction
endmodule
