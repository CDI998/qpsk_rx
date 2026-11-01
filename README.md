# qpsk9866 V2：AD9865

硬件状态：**贴片中；今天上午的软件版本**。

RCLK=H1-15，MODE=H1-17，CLKOUT1=H1-16；RESET=H1-4，PGA/SPI保持旧板分配。

此板RCLK入口需要局部CLOCK_DEDICATED_ROUTE FALSE；只允许输入至原有MMCM这一网络，必须检查接口时序。

本目录源码、原生FIFO IP、XDC、仿真及构建脚本均为独立副本，不引用其他版本或原工程的设计源。
Visio复制自共用架构，具体硬件针号以本版本XDC和下表为准；本次未改图页。

## 本版本引脚

| 顶层端口 | FPGA封装脚 |
|---|---|
| `sys_clk` | U18 |
| `afe_reset_n` | W18 |
| `afe_pga[0]` | P14 |
| `afe_pga[1]` | R14 |
| `afe_pga[2]` | Y16 |
| `afe_pga[3]` | Y17 |
| `afe_pga[4]` | V15 |
| `afe_pga[5]` | W15 |
| `afe_conf_clk` | Y14 |
| `afe_conf_cs` | W14 |
| `afe_conf_mosi` | P18 |
| `afe_conf_miso` | N17 |
| `afe_mode` | P16 |
| `afe_clkout1` | U14 |
| `afe_tx_en` | V18 |
| `afe_txrx_clk` | U15 |
| `afe_rx_sync` | T15 |
| `afe_tx_sync` | T14 |
| `afe_rx_data[0]` | U13 |
| `afe_rx_data[1]` | V13 |
| `afe_rx_data[2]` | V12 |
| `afe_rx_data[3]` | W13 |
| `afe_rx_data[4]` | T12 |
| `afe_rx_data[5]` | U12 |
| `afe_tx_data[0]` | T11 |
| `afe_tx_data[1]` | T10 |
| `afe_tx_data[2]` | B19 |
| `afe_tx_data[3]` | A20 |
| `afe_tx_data[4]` | C20 |
| `afe_tx_data[5]` | B20 |
| `sys_rst_n` | N15 |

保留今天上午已实现的bit/ltx于qpsk9866.runs/impl_1；它们只适用于V2。各XPR沿用源工程配置、使用各版本本地路径，未复制旧运行缓存；V2保留的文件是此前构建交付件。

## 保持的功能与接口

- 所有模块端口名、方向、顺序、位宽及参数保持不变。原生 FIFO IP 仍为独立时钟、12位×1024、FWFT。
- 实际芯片 AD9865；所有完整样本、FIFO 和调试样本均保留12位，[11:10]补0，[9:0]为10位补码。符号位是bit9，不能把零扩展的12位整体解释为有符号数。
- 正弦源被FIFO接受后才推进相位；FIFO满时保持样本，空时DAC发送零。物理接口仍为6+4位，低4位放在总线[5:2]。
- SPI初始化、寄存器配置、MMCM、复位和收发流程不变：复位10ms、释放后等待1ms，1MHz模式0逐项写入并读回00=80、04=19、05=00、0B=20、0C=01、0D=03，再等待1ms。
- OSCIN为38.4MHz；DAC内部76.8MSPS，ADC和TX/RX完整样本率19.2MSPS，RXCLK为38.4MHz，正弦源相位按25/96周期步进，输出5MHz（保持原幅度）。接收RxPGA控制码为6，对应-6dB。
- 顶层持续在初始化完成且接收FIFO非空时读取ADC，并保存到afe_rx_last_sample。没有内部模拟回环。

## 一个 ILA，六个探针

ILA实例保留u_ila_dac，AFE时钟38.4MHz、深度8192；debug hub使用SYS 50MHz。

| 探针 | 信号 | 含义 |
|---|---|---|
| 0 | dac_sample[11:0] | TX从FIFO读出并锁存、待拆分发送的完整样本 |
| 1 | dac_sample_valid | 对应TX FIFO读使能 |
| 2 | adc_sample[11:0] | RX已拼接、准备写入FIFO的完整样本，与FIFO din直接相连 |
| 3 | adc_sample_valid | 对应RX FIFO写使能，与FIFO wr_en直接相连 |
| 4 | afe_rst_n | AFE内部通路复位，1为释放 |
| 5 | afe_conf_done | 芯片寄存器配置及读回确认完成 |

ILA在AFE上升沿同时观察TX FIFO读出样本和RX FIFO写入样本；两个valid分别用于判断各自样本有效。
同时看两路时先保持全速采样，不把一个valid当作另一条通路的有效条件。
样本原始值为12位零扩展；看负半周时可在Vivado中展开低10位并按10位Signed Decimal/Analog显示，或导出后按bit9解释符号。
初始化和AFE时钟启动后再运行ILA；它不能完整捕获AFE时钟尚未运行时的初始化过程。

## 验证和烧录

- 仿真：scripts/verify_afe.tcl，真实top与原生FIFO IP，检查初始化、DAC物理引脚与FIFO样本、ADC写入/读出顺序、高位补0及顶层持续读取。
- 构建：scripts/build_afe.tcl，在原工程运行综合、实现、接口时序、DRC及FIFO偏斜检查，通过后生成位流。
- 烧录文件：qpsk9866.runs/impl_1/top.bit，配套同次生成的top.ltx。
- 报告：build/dac_debug；仿真日志：build/afe_verify。

布局布线和数字仿真不代表已经验证实板模拟波形或板间电气质量。
