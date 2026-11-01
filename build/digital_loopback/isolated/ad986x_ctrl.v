`timescale 1ns / 1ps
// AD9865初始化：配置并读回确认，完成后接收外部RxPGA设置。
module ad986x_ctrl #(
    parameter integer sys_clk_hz = 50000000  // 系统时钟频率，单位Hz
)(
    input wire sys_clk,              // 系统时钟，默认50 MHz
    input wire sys_rst_n,            // 系统复位，低有效

    input wire [5:0] ad986x_rx_pga,  // RxPGA增益控制码，系统时钟域
    input wire ad986x_clkout1,       // 芯片CLKOUT1输入，保留硬件接口
    input wire ad986x_conf_miso,     // SPI读数据，芯片SDO到FPGA

    output wire ad986x_conf_clk,      // SPI时钟，FPGA到芯片
    output wire ad986x_conf_cs,       // SPI片选，低有效
    output wire ad986x_conf_mosi,     // SPI写数据，FPGA到芯片SDIO

    output reg ad986x_reset_n,       // 芯片硬件复位，低有效
    output wire ad986x_mode,         // 接口模式，固定1为全双工
    output wire [5:0] ad986x_pga,     // 芯片PGA引脚，初始化后控制RxPGA
    output wire ad986x_conf_done      // 所有配置读回正确并稳定后置高
);

    // 1. 芯片复位：保持10 ms，释放后再等1 ms。
    localparam integer reset_hold_cycles = sys_clk_hz / 100;  // 芯片复位保持时间，单位为系统时钟周期
    localparam integer settle_cycles = sys_clk_hz / 1000;     // 芯片稳定等待时间，单位为系统时钟周期

    reg init_failed;              // 初始化失败标志，置高后保持芯片复位，等待系统复位
    reg [31:0] reset_wait_count;  // 芯片复位保持及释放后等待的计数
    reg reset_done;               // 芯片复位和释放后等待均已完成
    
    // 1.0 复位。 sys_rst_n触发复位，持续拉低10ms后释放并等待1ms，复位完成后reset_done为1。
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            reset_wait_count <= 0;
            reset_done <= 0;
            ad986x_reset_n <= 0;
        end else if (init_failed) begin
            reset_wait_count <= 0;
            reset_done <= 0;
            ad986x_reset_n <= 0;
        end else if (!reset_done) begin
            if (reset_wait_count == reset_hold_cycles - 1)
                ad986x_reset_n <= 1;
            if (reset_wait_count == reset_hold_cycles + settle_cycles - 1)
                reset_done <= 1;
            else
                reset_wait_count <= reset_wait_count + 1'b1;
        end
    end

    // 2. 配置表：一行对应一个寄存器，地址在前，配置值在后。
    reg [2:0] config_index;       // 配置表索引，0至5
    reg [15:0] config_addr_data;  // 当前配置项：[15:8]寄存器地址，[7:0]配置值

    always @* begin
        case (config_index)
            0: config_addr_data = 16'h0080; // 四线SPI，MSB先传
            1: config_addr_data = 16'h0419; // PLL乘2，ADC取PLL四分频
            2: config_addr_data = 16'h0500; // 启用内部收发RXCLK
            3: config_addr_data = 16'h0b20; // PGA引脚控制RxPGA
            4: config_addr_data = 16'h0c01; // 四倍插值、补码、高6位先传
            5: config_addr_data = 16'h0d43; // ADC补码、高6位先传、下降沿更新
            default: config_addr_data = 16'h0000;
        endcase
    end

    // 3. 初始化流程：reset_done后，逐项写入、读回、核对。
    localparam [1:0] step_write_config = 0;  // 写当前配置
    localparam [1:0] step_read_config = 1;   // 读当前寄存器
    localparam [1:0] step_check_config = 2;  // 核对读回值，选择下一项
    localparam [1:0] step_wait_stable = 3;   // 全部配置后等待稳定

    reg [1:0] init_step;         // 当前初始化步骤
    reg [31:0] init_wait_count;  // 配置后的稳定等待计数
    reg init_complete;           // 初始化完成标志

    // 初始化与SPI之间只传递请求、完整帧、忙状态和完成结果。
    reg spi_start;           // SPI传输请求，高电平持续一个系统时钟周期
    reg [15:0] spi_tx_data;  // 初始化流程提供的完整16位发送帧
    wire spi_busy;           // SPI正在执行一帧通信，高有效
    wire spi_done;            // SPI传输结束脉冲，一个系统时钟周期
    wire [15:0] spi_rx_data;  // 已完成的一帧接收结果，低8位为寄存器值

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            init_step <= step_write_config;
            config_index <= 0;
            init_wait_count <= 0;
            init_complete <= 0;
            init_failed <= 0;
            spi_start <= 0;
            spi_tx_data <= 0;
        end else if (!reset_done) begin
            spi_start <= 0;
        end else begin
            spi_start <= 0;
            if (!init_failed && !init_complete) begin
                case (init_step)
                    step_write_config: begin
                        if (spi_done) begin
                            init_step <= step_read_config;
                        end else if (!spi_busy && !spi_start) begin
                            spi_tx_data <= config_addr_data;
                            spi_start <= 1;
                        end
                    end
                    step_read_config: begin
                        if (spi_done) begin
                            init_step <= step_check_config;
                        end else if (!spi_busy && !spi_start) begin
                            spi_tx_data <= {3'b100, config_addr_data[12:8], 8'h00};
                            spi_start <= 1;
                        end
                    end
                    step_check_config: begin
                        if (spi_rx_data[7:0] != config_addr_data[7:0]) begin
                            init_failed <= 1;
                        end else if (config_index == 5) begin
                            init_step <= step_wait_stable;
                        end else begin
                            config_index <= config_index + 1'b1;
                            init_step <= step_write_config;
                        end
                    end
                    step_wait_stable: begin
                        if (init_wait_count == settle_cycles - 1)
                            init_complete <= 1;
                        else
                            init_wait_count <= init_wait_count + 1'b1;
                    end
                endcase
            end
        end
    end

    // 4. 通用SPI主机：当前芯片使用16位、1 MHz、模式0。
    spi_master #(
        .clk_hz(sys_clk_hz),
        .spi_clk_hz(1000000),
        .data_width(16),
        .cpol(1'b0),
        .cpha(1'b0)
    ) u_spi_master (
        .clk     (sys_clk),
        .rst_n   (sys_rst_n),
        .start   (spi_start),
        .tx_data (spi_tx_data),
        .miso    (ad986x_conf_miso),
        .busy    (spi_busy),
        .done    (spi_done),
        .rx_data (spi_rx_data),
        .sclk    (ad986x_conf_clk),
        .cs_n    (ad986x_conf_cs),
        .mosi    (ad986x_conf_mosi)
    );

    // 5. 固定输出与PGA：初始化完成后使用外部增益码。
    assign ad986x_mode = 1'b1;
    assign ad986x_conf_done = init_complete;
    assign ad986x_pga = init_complete ? ad986x_rx_pga : 6'd0;
endmodule
