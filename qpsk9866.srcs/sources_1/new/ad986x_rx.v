`timescale 1ns / 1ps
// 全双工接收：FIFO保持12位，AD9865样本放在[9:0]，高2位补0。
// 配合ctrl的0D=03，芯片下降沿更新数据，本模块上升沿采集。
// RX FIFO的wr_clk接ad986x_clk，直接使用原生FIFO IP。
module ad986x_rx #(
    parameter integer sample_bits = 10  // 芯片有效位数：AD9865为10，AD9866为12
)(
    input wire ad986x_clk,             // 芯片收发接口时钟
    input wire ad986x_rst_n,           // 接收通路复位，低有效
    input wire [5:0] ad986x_rx_data,   // 芯片输出的分段数据
    input wire ad986x_rx_sync,         // 分段标志：0高位段，1低位段
    input wire rx_full,               // FIFO满，高有效
    input wire rx_fifo_wr_rst_busy,   // FIFO写端复位忙，高有效
    input wire rx_fifo_rd_rst_busy,   // FIFO读端复位忙，高有效
    output reg [11:0] rx_fifo_data,   // 拼接后的样本，有效数据右对齐
    output reg rx_fifo_wr_en,          // FIFO写使能，每个完整样本写一次
    output reg rx_init_done            // 接收通路就绪，高有效
);
    // 1. 等待FIFO两端复位结束；读端状态需要跨时钟同步。
    (* ASYNC_REG = "TRUE" *) reg [1:0] rx_fifo_rd_busy_sync;  // 读端复位忙同步寄存器
    wire rx_fifo_ready;                                      // FIFO两端均已退出复位

    assign rx_fifo_ready = !rx_fifo_rd_busy_sync[1] && !rx_fifo_wr_rst_busy;

    always @(posedge ad986x_clk or negedge ad986x_rst_n) begin
        if (!ad986x_rst_n)
            rx_fifo_rd_busy_sync <= 2'b11;
        else
            rx_fifo_rd_busy_sync <= {rx_fifo_rd_busy_sync[0], rx_fifo_rd_rst_busy};
    end

    always @(posedge ad986x_clk or negedge ad986x_rst_n) begin
        if (!ad986x_rst_n)
            rx_init_done <= 1'b0;
        else
            rx_init_done <= rx_fifo_ready;
    end

    // 2. 先保存高6位，再接收对应的低位段；完整样本才允许写FIFO。
    reg [5:0] rx_high_data;  // 当前样本已接收的高6位
    reg rx_high_received;   // 已收到高6位，等待对应的低位段

    always @(posedge ad986x_clk or negedge ad986x_rst_n) begin
        if (!ad986x_rst_n) begin
            rx_fifo_data <= 12'd0;

            rx_high_data <= 6'd0;
            rx_high_received <= 1'b0;
        end else if (!rx_fifo_ready || !rx_init_done) begin
            rx_fifo_data <= 12'd0;

            rx_high_data <= 6'd0;
            rx_high_received <= 1'b0;
        end else begin

            if (!ad986x_rx_sync) begin
                rx_high_data <= ad986x_rx_data;
                rx_high_received <= 1'b1;
            end else if (rx_high_received) begin
                rx_high_received <= 1'b0;
                // 满时丢弃当前样本；不满则在下一个上升沿写入FIFO。
                if (!rx_full) begin
                    if (sample_bits == 10)
                        rx_fifo_data <= {2'b00, rx_high_data, ad986x_rx_data[5:2]};
                    else
                        rx_fifo_data <= {rx_high_data, ad986x_rx_data};

                end
            end
        end
    end
    // FIFO使能使用同步复位，避免异步复位直接驱动块RAM控制端。
    // 通路异步复位期间，FIFO自身的rst负责禁止读写。
    always @(posedge ad986x_clk) begin
        if (!ad986x_rst_n || !rx_fifo_ready || !rx_init_done)
            rx_fifo_wr_en <= 1'b0;
        else
            rx_fifo_wr_en <= ad986x_rx_sync && rx_high_received && !rx_full;
    end
    // 与RX FIFO的din、wr_en直接对应，在实际写入沿观察。
    (* MARK_DEBUG = "TRUE" *) wire [11:0] adc_sample;  // 待写入FIFO的12位样本
    (* MARK_DEBUG = "TRUE" *) wire adc_sample_valid;   // 对应FIFO写使能，高有效
    assign adc_sample = rx_fifo_data;
    assign adc_sample_valid = rx_fifo_wr_en;
endmodule
