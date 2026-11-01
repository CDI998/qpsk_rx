`timescale 1ns / 1ps
// 单片选四线SPI主机：高位先传，发送和接收同时进行。
// start仅在空闲时接受；忙时请求忽略。rx_data保持到下一帧完成。
module spi_master #(
    parameter integer clk_hz = 50000000,     // 工作时钟频率，Hz
    parameter integer spi_clk_hz = 1000000,  // SPI时钟频率上限，Hz
    parameter integer data_width = 16,       // 每帧位数，必须大于0
    parameter cpol = 1'b0,                   // 时钟空闲电平
    parameter cpha = 1'b0                    // 0首个边沿采样，1第二个边沿采样
)(
    input wire clk,                       // 工作时钟
    input wire rst_n,                     // 复位，低有效
    input wire start,                     // 启动请求，一个工作时钟周期
    input wire [data_width-1:0] tx_data,  // 待发送完整帧，接受请求时锁存
    input wire miso,                      // 从设备串行输出
    
    output wire busy,                     // 传输忙，包含片选保持和帧间等待
    output reg done,                      // 完成脉冲，一个工作时钟周期
    output reg [data_width-1:0] rx_data,  // 完整接收结果，done时有效
    output reg sclk,                      // SPI时钟
    output reg cs_n,                      // 从设备片选，低有效
    output reg mosi                       // 主机串行输出
);
    // 分频向上取整，使实际SPI频率不高于设定值。
    localparam integer clk_toggle_count = (clk_hz + 2 * spi_clk_hz - 1) / (2 * spi_clk_hz);

    // 状态机阶段定义
    localparam [1:0] idle = 0;        // 空闲，接受请求
    localparam [1:0] transfer = 1;    // 逐位收发数据
    localparam [1:0] release_cs = 2;  // 最后一位结束后释放片选
    localparam [1:0] wait_gap = 3;    // 保持帧间隔并通知完成

    reg [1:0] state;                           // 当前通信阶段
    reg [31:0] clk_count;                      // 时钟翻转前的等待计数
    reg [$clog2(data_width+1)-1:0] bit_count;  // 当前数据位序号，0至data_width-1
    reg [data_width-1:0] tx_shift;             // 发送移位寄存器
    reg [data_width-1:0] rx_shift;             // 接收移位寄存器

    assign busy = (state != idle);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= idle;
            clk_count <= 0;
            bit_count <= 0;
            tx_shift <= 0;
            rx_shift <= 0;
            rx_data <= 0;
            done <= 0;
            sclk <= cpol;
            cs_n <= 1;
            mosi <= 0;
        end else begin
            done <= 0;
            case (state)
                idle: begin
                    if (start) begin
                        clk_count <= 0;
                        bit_count <= 0;
                        rx_shift <= 0;
                        // CPHA=0时首位在片选后就绪，其余位在发送沿推出。
                        tx_shift <= cpha ? tx_data : (tx_data << 1);
                        mosi <= cpha ? 1'b0 : tx_data[data_width-1];
                        sclk <= cpol;
                        cs_n <= 0;
                        state <= transfer;
                    end
                end
                transfer: begin
                    if (clk_count == clk_toggle_count - 1) begin
                        clk_count <= 0;
                        sclk <= ~sclk;
                        // 使用翻转前的时钟电平区分采样沿和发送沿。
                        if (sclk == (cpol ^ cpha)) begin
                            rx_shift <= (rx_shift << 1) | miso;
                        end else begin
                            mosi <= tx_shift[data_width-1];
                            tx_shift <= tx_shift << 1;
                        end
                        // 每个时钟回到空闲电平时，一位传输结束。
                        if (sclk != cpol) begin
                            if (bit_count == data_width - 1)
                                state <= release_cs;
                            else
                                bit_count <= bit_count + 1'b1;
                        end
                    end else clk_count <= clk_count + 1'b1;
                end
                release_cs: begin
                    if (clk_count == clk_toggle_count - 1) begin
                        clk_count <= 0;
                        cs_n <= 1;
                        mosi <= 0;
                        state <= wait_gap;
                    end else clk_count <= clk_count + 1'b1;
                end
                wait_gap: begin
                    if (clk_count == clk_toggle_count - 1) begin
                        clk_count <= 0;
                        rx_data <= rx_shift;
                        done <= 1;
                        state <= idle;
                    end else clk_count <= clk_count + 1'b1;
                end
            endcase
        end
    end
endmodule
