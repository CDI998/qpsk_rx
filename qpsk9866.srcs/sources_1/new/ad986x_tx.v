`timescale 1ns / 1ps
// AD9865全双工发送：FIFO为12位FWFT，有效数据右对齐，AD9865只使用[9:0]。
// 下降沿更新芯片数据，上升沿由芯片采样、由FIFO接受读使能。
// TX FIFO的rd_clk接ad986x_clk，不要接反相时钟。
module ad986x_tx #(
    parameter integer sample_bits = 10  // 芯片有效位数：AD9865为10，AD9866为12
)(
    input wire ad986x_clk,             // 芯片收发接口时钟
    input wire ad986x_rst_n,           // 发送通路复位，低有效
    input wire [11:0] tx_fifo_data,    // FIFO当前样本，非空时有效
    input wire tx_empty,              // FIFO空，高有效
    input wire tx_fifo_rd_rst_busy,   // FIFO读端复位忙，高有效
    input wire tx_fifo_wr_rst_busy,   // FIFO写端复位忙，高有效

    output reg ad986x_tx_sync,         // 分段标志：0高位段，1低位段
    output reg [5:0] ad986x_tx_data,   // 发送到芯片的数据

    output reg tx_fifo_rd_en,          // FIFO读使能，每个样本读一次
    output reg tx_init_done            // 发送通路就绪，高有效
);
    // 1. 等待FIFO两端复位结束；写端状态需要跨时钟同步。
    (* ASYNC_REG = "TRUE" *) reg [1:0] tx_fifo_wr_busy_sync;  // 写端复位忙同步寄存器
    wire tx_fifo_ready;                                      // FIFO两端均已退出复位

    assign tx_fifo_ready = !tx_fifo_wr_busy_sync[1] && !tx_fifo_rd_rst_busy;

    
    always @(negedge ad986x_clk or negedge ad986x_rst_n) begin
        if (!ad986x_rst_n)
            tx_fifo_wr_busy_sync <= 2'b11;
        else
            tx_fifo_wr_busy_sync <= {tx_fifo_wr_busy_sync[0], tx_fifo_wr_rst_busy};
    end

    always @(negedge ad986x_clk or negedge ad986x_rst_n) begin
        if (!ad986x_rst_n)
            tx_init_done <= 1'b0;
        else
            tx_init_done <= tx_fifo_ready;
    end

    // 2. 每个样本分两拍发送；读FIFO时锁存完整样本，避免混入下一个样本。
    reg tx_low_phase;        // 0发送高位段，1发送低位段
    reg [11:0] tx_sample_data;  // 从FIFO取出的当前样本，供两拍发送使用

    always @(negedge ad986x_clk or negedge ad986x_rst_n) begin
        if (!ad986x_rst_n) begin
            ad986x_tx_sync <= 1'b0;
            ad986x_tx_data <= 6'd0;

            tx_low_phase <= 1'b0;
            tx_sample_data <= 12'd0;
        end else if (!tx_fifo_ready || !tx_init_done) begin
            ad986x_tx_sync <= 1'b0;
            ad986x_tx_data <= 6'd0;

            tx_low_phase <= 1'b0;
            tx_sample_data <= 12'd0;
        end else if (!tx_low_phase) begin
            // 高位拍：锁存当前样本，读使能在下一个上升沿生效。
            ad986x_tx_sync <= 1'b0;
            tx_low_phase <= 1'b1;

            if (!tx_empty) begin
                tx_sample_data <= tx_fifo_data;
                if (sample_bits == 10) begin
                    ad986x_tx_data <= tx_fifo_data[9:4];
                end else begin
                    ad986x_tx_data <= tx_fifo_data[11:6];
                end
            end else begin
                ad986x_tx_data <= 6'd0;
                tx_sample_data <= 12'd0;
            end
        end else begin
            // 低位拍：AD9865使用引脚[5:2]，AD9866使用[5:0]。
            ad986x_tx_sync <= 1'b1;
            if (sample_bits == 10)
                ad986x_tx_data <= {tx_sample_data[3:0], 2'b00};
            else
                ad986x_tx_data <= tx_sample_data[5:0];

            tx_low_phase <= 1'b0;
        end
    end
    // FIFO使能使用同步复位，避免异步复位直接驱动块RAM控制端。
    // 通路异步复位期间，FIFO自身的rst负责禁止读写。
    always @(negedge ad986x_clk) begin
        if (!ad986x_rst_n || !tx_fifo_ready || !tx_init_done)
            tx_fifo_rd_en <= 1'b0;
        else
            tx_fifo_rd_en <= !tx_low_phase && !tx_empty;
    end
    // 从FIFO读出并锁存的完整12位样本；AD9865高两位为0。
    (* MARK_DEBUG = "TRUE" *) wire [11:0] dac_sample;  // FIFO读出的待发送样本
    (* MARK_DEBUG = "TRUE" *) wire dac_sample_valid;   // 对应FIFO读使能，高有效
    assign dac_sample = tx_sample_data;
    assign dac_sample_valid = tx_fifo_rd_en;
endmodule
