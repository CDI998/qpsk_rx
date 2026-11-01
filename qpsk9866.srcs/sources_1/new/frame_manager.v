`timescale 1ns / 1ps
// 模拟固定空闲帧：32个符号，00/01/10/11重复8次，无帧间空隙。
module frame_manager (
    input wire sys_clk,               // 系统时钟
    input wire sys_rst_n,             // 低有效复位
    input wire enable,               // AFE初始化完成
    input wire fifo_full,            // FIFO2禁止写入
    input wire symbol_ready,         // QPSK可以接收符号
    output wire [1:0] symbol_data,    // 当前帧的两位数据
    output wire symbol_valid         // 当前数据有效
);
    reg [4:0] symbol_count;           // 当前帧符号编号
    // 满时停止发起新符号，已经发起的符号保持到握手完成。
    reg pending;                     // 待接收符号有效
    assign symbol_data = symbol_count[1:0];
    assign symbol_valid = pending;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin symbol_count <= 0; pending <= 0; end
        else begin
            if (pending && symbol_ready) begin
                symbol_count <= symbol_count + 1'b1;
                pending <= enable && !fifo_full;
            end else if (!pending && enable && !fifo_full) pending <= 1;
        end
    end
endmodule
