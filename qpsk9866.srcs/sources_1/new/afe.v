`timescale 1ns / 1ps
module afe #(
    parameter integer sys_clk_hz = 50000000, // 系统时钟频率，单位Hz
    parameter integer sample_bits = 10       // 芯片有效位数：10或12，FIFO固定12位
)(
    input wire sys_clk,                // 系统时钟，默认50 MHz
    input wire sys_rst_n,              // 系统复位，低有效

    input wire afe_clkout1,            // 芯片CLKOUT1输入，保留硬件接口
    input wire afe_txrx_clk,           // 芯片输出的收发接口时钟
    input wire [5:0] afe_rx_pga,       // 外部提供的RxPGA增益控制码
    input wire afe_rx_sync,            // ADC分段标志：0高6位，1低4位
    input wire [5:0] afe_rx_data,      // 芯片ADC的6位分段数据

    input wire afe_tx_wr_en,           // 发送FIFO写请求，高有效
    input wire [11:0] afe_tx_sample,   // 待写入发送FIFO的12位样点
    input wire afe_rx_rd_en,           // 接收FIFO读请求，高有效
    input wire afe_conf_miso,          // SPI读数据，芯片SDO到FPGA

    output wire afe_conf_clk,          // SPI时钟，FPGA到芯片
    output wire afe_conf_cs,           // SPI片选，低有效
    output wire afe_conf_mosi,         // SPI写数据，FPGA到芯片SDIO

    output wire afe_reset_n,           // 芯片硬件复位，低有效
    output wire afe_mode,              // 接口模式，固定1为全双工
    output wire afe_tx_en,             // DAC发送允许，高有效
    output wire [5:0] afe_pga,         // 芯片PGA控制引脚，配置为控制RxPGA

    output wire afe_tx_sync,           // DAC分段标志：0高6位，1低4位
    output wire [5:0] afe_tx_data,     // 送往芯片DAC的6位分段数据

    output wire afe_tx_full,           // 发送侧不可写，高有效
    output wire afe_rx_empty,          // 接收侧无可读样点，高有效
    output wire [11:0] afe_rx_sample,  // 接收FIFO当前12位样点，非空时有效
    output wire afe_init_done          // AFE整体初始化完成，高有效
);

    // 1. 系统复位：异步复位，同步释放。
    (* ASYNC_REG = "TRUE" *) reg [1:0] sys_rst_pipe = 2'b00;  // 系统复位释放同步寄存器
    wire sys_rst_sync_n;                                     // 系统内部复位，低有效

    assign sys_rst_sync_n = sys_rst_pipe[1];

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            sys_rst_pipe <= 2'b00;
        else
            sys_rst_pipe <= {sys_rst_pipe[0], 1'b1};
    end

    // 2. 芯片配置：寄存器操作全部由ctrl负责。
    (* MARK_DEBUG = "TRUE" *) wire afe_conf_done;  // 芯片配置完成，高有效

    ad986x_ctrl #(
        .sys_clk_hz(sys_clk_hz)
    ) u_ad986x_ctrl (
        .sys_clk          (sys_clk),
        .sys_rst_n        (sys_rst_sync_n),
        .ad986x_rx_pga    (afe_rx_pga),
        .ad986x_clkout1   (afe_clkout1),
        .ad986x_conf_miso (afe_conf_miso),
        .ad986x_conf_clk  (afe_conf_clk),
        .ad986x_conf_cs   (afe_conf_cs),
        .ad986x_conf_mosi (afe_conf_mosi),
        .ad986x_reset_n   (afe_reset_n),
        .ad986x_mode      (afe_mode),
        .ad986x_pga       (afe_pga),
        .ad986x_conf_done (afe_conf_done)
    );

    // 3. 收发时钟：RCLK接U15（SRCC的N端），仅输入至MMCM允许普通布线。
    // 输入、输出均为38.4MHz；内部VCO为768MHz，不改变样本速率。
    wire afe_clk;              // TX、RX和FIFO芯片侧共用时钟
    wire afe_clk_unbuffered;   // MMCM输出，送全局时钟缓冲
    wire afe_clk_feedback;     // MMCM反馈输出
    wire afe_clk_feedback_buf; // 缓冲后的MMCM反馈
    wire afe_clk_locked;       // MMCM时钟已锁定，高有效

    MMCME2_BASE #(
        .CLKIN1_PERIOD(26.042),
        .CLKFBOUT_MULT_F(20.0),
        .DIVCLK_DIVIDE(1),
        .CLKOUT0_DIVIDE_F(20.0)
    ) u_afe_clk_mmcm (
        .CLKIN1   (afe_txrx_clk),
        .CLKFBIN  (afe_clk_feedback_buf),
        .CLKFBOUT (afe_clk_feedback),
        .CLKOUT0  (afe_clk_unbuffered),
        .LOCKED   (afe_clk_locked),
        .PWRDWN   (1'b0),
        .RST      (!sys_rst_sync_n || !afe_conf_done)
    );

    BUFG u_afe_clk_feedback_bufg (
        .I(afe_clk_feedback),
        .O(afe_clk_feedback_buf)
    );

    BUFG u_afe_clk_bufg (
        .I(afe_clk_unbuffered),
        .O(afe_clk)
    );

    // 配置完成并锁定时钟后，释放TX、RX和两个FIFO的复位。
    wire afe_reset_request_n;                                 // 数据通路复位条件，低有效
    (* ASYNC_REG = "TRUE" *) reg [1:0] afe_rst_pipe = 2'b00;  // AFE复位释放同步寄存器
    (* MARK_DEBUG = "TRUE" *) wire afe_rst_n;                                           // AFE内部复位，低有效
    wire afe_fifo_rst;                                        // 原生FIFO复位，高有效

    assign afe_reset_request_n = sys_rst_sync_n && afe_conf_done && afe_clk_locked;
    assign afe_rst_n = afe_rst_pipe[1];
    assign afe_fifo_rst = !afe_rst_n;

    always @(posedge afe_clk or negedge afe_reset_request_n) begin
        if (!afe_reset_request_n)
            afe_rst_pipe <= 2'b00;
        else
            afe_rst_pipe <= {afe_rst_pipe[0], 1'b1};
    end

    // 4. TX通路：系统时钟写FIFO，AFE时钟读FIFO并发送。
    wire [11:0] tx_fifo_data;  // TX FIFO当前样本
    wire tx_fifo_wr_en;        // 接受外部有效数据后产生的写使能
    wire tx_fifo_rd_en;        // TX模块产生的读使能
    wire tx_fifo_full;         // TX FIFO满，高有效
    wire tx_empty;             // TX FIFO空，高有效
    wire tx_fifo_wr_rst_busy;  // TX FIFO写端复位忙，高有效
    wire tx_fifo_rd_rst_busy;  // TX FIFO读端复位忙，高有效
    wire afe_tx_init_done;     // TX及其FIFO就绪，AFE时钟域

    assign tx_fifo_wr_en = afe_tx_wr_en && !afe_tx_full;

    tx_fifo u_tx_fifo (
        .rst         (afe_fifo_rst),
        .wr_clk      (sys_clk),
        .rd_clk      (afe_clk),
        .din         (afe_tx_sample),
        .wr_en       (tx_fifo_wr_en),
        .rd_en       (tx_fifo_rd_en),
        .dout        (tx_fifo_data),
        .full        (tx_fifo_full),
        .empty       (tx_empty),
        .valid       (),
        .wr_rst_busy (tx_fifo_wr_rst_busy),
        .rd_rst_busy (tx_fifo_rd_rst_busy)
    );

    ad986x_tx #(
        .sample_bits(sample_bits)
    ) u_ad986x_tx (
        .ad986x_clk         (afe_clk),
        .ad986x_rst_n       (afe_rst_n),
        .tx_fifo_data       (tx_fifo_data),
        .tx_empty           (tx_empty),
        .tx_fifo_rd_rst_busy(tx_fifo_rd_rst_busy),
        .tx_fifo_wr_rst_busy(tx_fifo_wr_rst_busy),
        .ad986x_tx_sync     (afe_tx_sync),
        .ad986x_tx_data     (afe_tx_data),
        .tx_fifo_rd_en      (tx_fifo_rd_en),
        .tx_init_done       (afe_tx_init_done)
    );

    // 5. RX通路：AFE时钟拼接样本并写FIFO，系统时钟读FIFO。
    wire [11:0] rx_fifo_data;  // RX模块拼接的完整样本
    wire rx_fifo_wr_en;        // RX模块产生的写使能
    wire rx_fifo_rd_en;        // 外部读请求通过非空检查后的读使能
    wire rx_full;              // RX FIFO满，高有效
    wire rx_fifo_empty;        // RX FIFO空，高有效
    wire rx_fifo_wr_rst_busy;  // RX FIFO写端复位忙，高有效
    wire rx_fifo_rd_rst_busy;  // RX FIFO读端复位忙，高有效
    wire afe_rx_init_done;     // RX及其FIFO就绪，AFE时钟域

    assign rx_fifo_rd_en = afe_rx_rd_en && !afe_rx_empty;

    ad986x_rx #(
        .sample_bits(sample_bits)
    ) u_ad986x_rx (
        .ad986x_clk         (afe_clk),
        .ad986x_rst_n       (afe_rst_n),
        .ad986x_rx_data     (afe_rx_data),
        .ad986x_rx_sync     (afe_rx_sync),
        .rx_full            (rx_full),
        .rx_fifo_wr_rst_busy(rx_fifo_wr_rst_busy),
        .rx_fifo_rd_rst_busy(rx_fifo_rd_rst_busy),
        .rx_fifo_data       (rx_fifo_data),
        .rx_fifo_wr_en      (rx_fifo_wr_en),
        .rx_init_done       (afe_rx_init_done)
    );

    rx_fifo u_rx_fifo (
        .rst         (afe_fifo_rst),
        .wr_clk      (afe_clk),
        .rd_clk      (sys_clk),
        .din         (rx_fifo_data),
        .wr_en       (rx_fifo_wr_en),
        .rd_en       (rx_fifo_rd_en),
        .dout        (afe_rx_sample),
        .full        (rx_full),
        .empty       (rx_fifo_empty),
        .valid       (),
        .wr_rst_busy (rx_fifo_wr_rst_busy),
        .rd_rst_busy (rx_fifo_rd_rst_busy)
    );

    // 6. 对外就绪：同步TX、RX状态，并在系统时钟沿撤销就绪。
    // FIFO自身仍异步复位，避免将异步复位路径直接接入RAM读写使能。
    (* ASYNC_REG = "TRUE" *) reg [1:0] afe_tx_done_sync;  // TX就绪同步到系统时钟域
    (* ASYNC_REG = "TRUE" *) reg [1:0] afe_rx_done_sync;  // RX就绪同步到系统时钟域

    always @(posedge sys_clk) begin
        if (!afe_reset_request_n) begin
            afe_tx_done_sync <= 2'b00;
            afe_rx_done_sync <= 2'b00;
        end else begin
            afe_tx_done_sync <= {afe_tx_done_sync[0], afe_tx_init_done};
            afe_rx_done_sync <= {afe_rx_done_sync[0], afe_rx_init_done};
        end
    end

    assign afe_init_done = afe_tx_done_sync[1] && afe_rx_done_sync[1];
    assign afe_tx_en = afe_init_done;
    assign afe_tx_full = !afe_init_done || tx_fifo_wr_rst_busy || tx_fifo_full;
    assign afe_rx_empty = !afe_init_done || rx_fifo_rd_rst_busy || rx_fifo_empty;
endmodule
