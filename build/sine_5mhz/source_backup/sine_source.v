`timescale 1ns / 1ps
// 64点正弦源；每次FIFO实际接收一个样点后推进相位。
module sine_source #(
    parameter integer sample_bits = 10  // 有效位数：10或12，输出固定12位
)(
    input wire sys_clk,        // 系统时钟
    input wire sys_rst_n,      // 系统复位，低有效
    input wire sample_en,      // 当前样点已被接受，高有效
    output reg [11:0] sample   // 12位样本；AD9865高两位0，10位补码峰值128
);
    reg [11:0] wave_sample;  // 12位正弦查表值，按有效位数缩放
    reg [5:0] phase;           // 正弦相位，0至63
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) phase <= 0;
        else if (sample_en) phase <= phase + 1'b1;
    end
    always @* begin
        case (phase)
            6'd0: wave_sample = 12'h000;
            6'd1: wave_sample = 12'h034;
            6'd2: wave_sample = 12'h064;
            6'd3: wave_sample = 12'h094;
            6'd4: wave_sample = 12'h0c4;
            6'd5: wave_sample = 12'h0f0;
            6'd6: wave_sample = 12'h11c;
            6'd7: wave_sample = 12'h144;
            6'd8: wave_sample = 12'h16c;
            6'd9: wave_sample = 12'h18c;
            6'd10: wave_sample = 12'h1a8;
            6'd11: wave_sample = 12'h1c4;
            6'd12: wave_sample = 12'h1d8;
            6'd13: wave_sample = 12'h1e8;
            6'd14: wave_sample = 12'h1f8;
            6'd15: wave_sample = 12'h1fc;
            6'd16: wave_sample = 12'h200;
            6'd17: wave_sample = 12'h1fc;
            6'd18: wave_sample = 12'h1f8;
            6'd19: wave_sample = 12'h1e8;
            6'd20: wave_sample = 12'h1d8;
            6'd21: wave_sample = 12'h1c4;
            6'd22: wave_sample = 12'h1a8;
            6'd23: wave_sample = 12'h18c;
            6'd24: wave_sample = 12'h16c;
            6'd25: wave_sample = 12'h144;
            6'd26: wave_sample = 12'h11c;
            6'd27: wave_sample = 12'h0f0;
            6'd28: wave_sample = 12'h0c4;
            6'd29: wave_sample = 12'h094;
            6'd30: wave_sample = 12'h064;
            6'd31: wave_sample = 12'h034;
            6'd32: wave_sample = 12'h000;
            6'd33: wave_sample = 12'hfcc;
            6'd34: wave_sample = 12'hf9c;
            6'd35: wave_sample = 12'hf6c;
            6'd36: wave_sample = 12'hf3c;
            6'd37: wave_sample = 12'hf10;
            6'd38: wave_sample = 12'hee4;
            6'd39: wave_sample = 12'hebc;
            6'd40: wave_sample = 12'he94;
            6'd41: wave_sample = 12'he74;
            6'd42: wave_sample = 12'he58;
            6'd43: wave_sample = 12'he3c;
            6'd44: wave_sample = 12'he28;
            6'd45: wave_sample = 12'he18;
            6'd46: wave_sample = 12'he08;
            6'd47: wave_sample = 12'he04;
            6'd48: wave_sample = 12'he00;
            6'd49: wave_sample = 12'he04;
            6'd50: wave_sample = 12'he08;
            6'd51: wave_sample = 12'he18;
            6'd52: wave_sample = 12'he28;
            6'd53: wave_sample = 12'he3c;
            6'd54: wave_sample = 12'he58;
            6'd55: wave_sample = 12'he74;
            6'd56: wave_sample = 12'he94;
            6'd57: wave_sample = 12'hebc;
            6'd58: wave_sample = 12'hee4;
            6'd59: wave_sample = 12'hf10;
            6'd60: wave_sample = 12'hf3c;
            6'd61: wave_sample = 12'hf6c;
            6'd62: wave_sample = 12'hf9c;
            6'd63: wave_sample = 12'hfcc;
            default: wave_sample = 0;
        endcase
        if (sample_bits == 10)
            sample = {2'b00, wave_sample[11:2]};
        else
            sample = wave_sample;
    end
endmodule
