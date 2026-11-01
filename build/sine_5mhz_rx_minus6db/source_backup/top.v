`timescale 1ns / 1ps
module top #(
    parameter integer sys_clk_hz = 50000000,    // 系统时钟频率，单位Hz
    parameter [5:0] afe_rx_pga_default = 6'd12  // 系统侧默认RxPGA增益码
)(
    input wire sys_clk,             // 系统时钟，默认50 MHz
    input wire sys_rst_n,           // 系统复位，低有效

    input wire afe_clkout1,         // 芯片CLKOUT1输入，afe对晶振倍频后输出
    input wire afe_txrx_clk,        // 芯片输出的ADC\DAC数据接口时钟
    input wire afe_rx_sync,         // ADC分段标志：0高6位，1低4位
    input wire [5:0] afe_rx_data,   // 芯片ADC的6位分段数据
    input wire afe_conf_miso,       // SPI读数据，芯片SDO到FPGA

    output wire afe_conf_mosi,      // SPI写数据，FPGA到芯片SDIO
    output wire afe_conf_clk,       // SPI时钟，FPGA到芯片
    output wire afe_conf_cs,        // SPI片选，低有效

    output wire afe_tx_en,          // DAC发送允许，高有效
    output wire afe_tx_sync,        // DAC分段标志：0高6位，1低4位
    output wire [5:0] afe_tx_data,  // 送往芯片DAC的6位分段数据

    output wire afe_reset_n,        // 芯片硬件复位，低有效
    output wire afe_mode,           // 接口模式，固定1为全双工
    output wire [5:0] afe_pga       // 芯片PGA控制引脚，配置为控制RxPGA
);

    wire [11:0] afe_tx_sample;  // 正弦样本，有效数据右对齐
    wire [11:0] afe_rx_sample;  // 接收FIFO当前样本，高2位补0
    wire afe_tx_wr_en;          // 发送FIFO实际写使能
    wire afe_rx_rd_en;          // 接收FIFO实际读使能

    wire afe_init_done;                 // AFE整体初始化完成，高有效
    wire afe_tx_full;                   // 发送侧不可写，高有效
    wire afe_rx_empty;          // 接收侧无可读样点，高有效

    wire [5:0] afe_rx_pga = afe_rx_pga_default;  // 传入AFE的RxPGA增益码

    // 查表数据始终就绪；只有FIFO接受当前样本后才推进正弦相位。
    assign afe_tx_wr_en = afe_init_done && !afe_tx_full;
    assign afe_rx_rd_en = afe_init_done && !afe_rx_empty;

    sine_source #(
        .sample_bits(10)
    ) u_sine_source (
        .sys_clk   (sys_clk),
        .sys_rst_n (sys_rst_n),
        .sample_en (afe_tx_wr_en),
        .sample    (afe_tx_sample)
    );

    // ADC恢复普通读取，保留最近样本供后续处理模块使用。
    (* DONT_TOUCH = "TRUE" *) reg [11:0] afe_rx_last_sample;  // 最近读取的ADC样本，高2位补零

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            afe_rx_last_sample <= 12'd0;
        else if (afe_rx_rd_en)
            afe_rx_last_sample <= afe_rx_sample;
    end

    afe #(
        .sys_clk_hz(sys_clk_hz)
    ) u_afe (
        .sys_clk       (sys_clk),
        .sys_rst_n     (sys_rst_n),

        .afe_clkout1   (afe_clkout1),
        .afe_txrx_clk  (afe_txrx_clk),
        .afe_rx_pga    (afe_rx_pga),
        .afe_rx_sync   (afe_rx_sync),
        .afe_rx_data   (afe_rx_data),

        .afe_tx_wr_en  (afe_tx_wr_en),
        .afe_tx_sample (afe_tx_sample),
        .afe_rx_rd_en  (afe_rx_rd_en),
        .afe_conf_miso (afe_conf_miso),

        .afe_conf_clk  (afe_conf_clk),
        .afe_conf_cs   (afe_conf_cs),
        .afe_conf_mosi (afe_conf_mosi),

        .afe_reset_n   (afe_reset_n),
        .afe_mode      (afe_mode),
        .afe_tx_en     (afe_tx_en),
        .afe_pga       (afe_pga),

        .afe_tx_sync   (afe_tx_sync),
        .afe_tx_data   (afe_tx_data),

        .afe_tx_full   (afe_tx_full),
        .afe_rx_empty  (afe_rx_empty),
        .afe_rx_sample (afe_rx_sample),
        .afe_init_done (afe_init_done)
    );

    // 顶层只连接硬件及AFE业务接口。
endmodule
