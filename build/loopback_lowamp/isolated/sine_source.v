`timescale 1ns / 1ps
// 5 MHz正弦源：19.2 MSPS，每次FIFO接受样本后相位前进25/96周期。
module sine_source #(
    parameter integer sample_bits = 10  // 有效位数：10或12，输出固定12位
)(
    input wire sys_clk,        // 系统时钟
    input wire sys_rst_n,      // 系统复位，低有效
    input wire sample_en,      // 当前样点已被接受，高有效
    output reg [11:0] sample   // 12位样本；AD9865高两位0，10位补码峰值128
);
    reg [11:0] wave_sample;  // 12位正弦查表值，按有效位数缩放
    reg [6:0] phase;           // 查找表相位索引，0～95
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) phase <= 0;
        else if (sample_en) begin
            if (phase >= 7'd71) phase <= phase - 7'd71;
            else phase <= phase + 7'd25;
        end
    end
    always @* begin
        case (phase)
            7'd0: wave_sample = 12'h000;
            7'd1: wave_sample = 12'h008;
            7'd2: wave_sample = 12'h011;
            7'd3: wave_sample = 12'h019;
            7'd4: wave_sample = 12'h021;
            7'd5: wave_sample = 12'h029;
            7'd6: wave_sample = 12'h031;
            7'd7: wave_sample = 12'h039;
            7'd8: wave_sample = 12'h040;
            7'd9: wave_sample = 12'h047;
            7'd10: wave_sample = 12'h04e;
            7'd11: wave_sample = 12'h054;
            7'd12: wave_sample = 12'h05b;
            7'd13: wave_sample = 12'h060;
            7'd14: wave_sample = 12'h066;
            7'd15: wave_sample = 12'h06a;
            7'd16: wave_sample = 12'h06f;
            7'd17: wave_sample = 12'h073;
            7'd18: wave_sample = 12'h076;
            7'd19: wave_sample = 12'h079;
            7'd20: wave_sample = 12'h07c;
            7'd21: wave_sample = 12'h07e;
            7'd22: wave_sample = 12'h07f;
            7'd23: wave_sample = 12'h080;
            7'd24: wave_sample = 12'h080;
            7'd25: wave_sample = 12'h080;
            7'd26: wave_sample = 12'h07f;
            7'd27: wave_sample = 12'h07e;
            7'd28: wave_sample = 12'h07c;
            7'd29: wave_sample = 12'h079;
            7'd30: wave_sample = 12'h076;
            7'd31: wave_sample = 12'h073;
            7'd32: wave_sample = 12'h06f;
            7'd33: wave_sample = 12'h06a;
            7'd34: wave_sample = 12'h066;
            7'd35: wave_sample = 12'h060;
            7'd36: wave_sample = 12'h05b;
            7'd37: wave_sample = 12'h054;
            7'd38: wave_sample = 12'h04e;
            7'd39: wave_sample = 12'h047;
            7'd40: wave_sample = 12'h040;
            7'd41: wave_sample = 12'h039;
            7'd42: wave_sample = 12'h031;
            7'd43: wave_sample = 12'h029;
            7'd44: wave_sample = 12'h021;
            7'd45: wave_sample = 12'h019;
            7'd46: wave_sample = 12'h011;
            7'd47: wave_sample = 12'h008;
            7'd48: wave_sample = 12'h000;
            7'd49: wave_sample = 12'hff8;
            7'd50: wave_sample = 12'hfef;
            7'd51: wave_sample = 12'hfe7;
            7'd52: wave_sample = 12'hfdf;
            7'd53: wave_sample = 12'hfd7;
            7'd54: wave_sample = 12'hfcf;
            7'd55: wave_sample = 12'hfc7;
            7'd56: wave_sample = 12'hfc0;
            7'd57: wave_sample = 12'hfb9;
            7'd58: wave_sample = 12'hfb2;
            7'd59: wave_sample = 12'hfac;
            7'd60: wave_sample = 12'hfa5;
            7'd61: wave_sample = 12'hfa0;
            7'd62: wave_sample = 12'hf9a;
            7'd63: wave_sample = 12'hf96;
            7'd64: wave_sample = 12'hf91;
            7'd65: wave_sample = 12'hf8d;
            7'd66: wave_sample = 12'hf8a;
            7'd67: wave_sample = 12'hf87;
            7'd68: wave_sample = 12'hf84;
            7'd69: wave_sample = 12'hf82;
            7'd70: wave_sample = 12'hf81;
            7'd71: wave_sample = 12'hf80;
            7'd72: wave_sample = 12'hf80;
            7'd73: wave_sample = 12'hf80;
            7'd74: wave_sample = 12'hf81;
            7'd75: wave_sample = 12'hf82;
            7'd76: wave_sample = 12'hf84;
            7'd77: wave_sample = 12'hf87;
            7'd78: wave_sample = 12'hf8a;
            7'd79: wave_sample = 12'hf8d;
            7'd80: wave_sample = 12'hf91;
            7'd81: wave_sample = 12'hf96;
            7'd82: wave_sample = 12'hf9a;
            7'd83: wave_sample = 12'hfa0;
            7'd84: wave_sample = 12'hfa5;
            7'd85: wave_sample = 12'hfac;
            7'd86: wave_sample = 12'hfb2;
            7'd87: wave_sample = 12'hfb9;
            7'd88: wave_sample = 12'hfc0;
            7'd89: wave_sample = 12'hfc7;
            7'd90: wave_sample = 12'hfcf;
            7'd91: wave_sample = 12'hfd7;
            7'd92: wave_sample = 12'hfdf;
            7'd93: wave_sample = 12'hfe7;
            7'd94: wave_sample = 12'hfef;
            7'd95: wave_sample = 12'hff8;
            default: wave_sample = 0;
        endcase
        if (sample_bits == 10)
            sample = {2'b00, wave_sample[11:2]};
        else
            sample = wave_sample;
    end
endmodule
