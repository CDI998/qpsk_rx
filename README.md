# qpsk9866 V2

只维护当前 qpsk9866.xpr。唯一工程配置入口是 scripts/setup_project.tcl；首次配置或配置变更后执行并保存，日常直接在 Vivado 生成比特流。

- 唯一手写约束：qpsk9866.srcs/constrs_1/new/ax7010.xdc，包含引脚、接口时序和正式 ILA。
- 正式设计源、原生 FIFO IP、仿真源保留在 qpsk9866.srcs。
- TX：6 MHz QPSK，19.2 MSPS，2 Msymbol/s，4 Mbps；RX 增益 0 dB。
- 12 位样本与 FIFO；AD9865 有效补码 [9:0]，高两位补零；物理低四位使用 [5:2]。
- SPI：00=80、04=19、05=00、0B=20、0C=01、0D=03、07=00、08=60；RX低通旁路，保留目标码96，没有数字回环。
- 唯一 ILA u_ila_dac：DAC FIFO 读出样本和读使能、ADC FIFO 写入前样本和写使能、复位、配置完成。
- 顶层在 AFE 就绪且 RX FIFO 非空时持续读取。
- 烧录本次生成的 qpsk9866.runs/impl_1/top.bit 和 debug_nets.ltx。
- 原始测量 CSV 位于 measurements；原有 Visio 位于 doc/design。

Vivado 和厂商 IP 自动生成的 Tcl/XDC 不属于手写维护入口，不手改。旧诊断产物已移出工程归档，不再维护。ADC 异常仍在排查。


RX低通目标码0x60按手册公式外推约7.8MHz，但公式仅在40~80MSPS验证，当前19.2MSPS的实际截止频率需实测确认。配置后沿用1ms稳定等待，覆盖手册小于100us的滤波校准时间。


发送流程参考 lauchinyuan/FPGA_QPSK-modem 的I/Q先成形再正交调制结构：https://github.com/lauchinyuan/FPGA_QPSK-modem/blob/master/rtl/qpsk_mod.v 。本工程自行实现RRC：滚降0.35、跨度8符号、48分数相位、延迟4符号(2us)。保持6MHz载波、2Msymbol/s、19.2MSPS。按系数绝对值和归一化，使10位输出峰值不超过约64码；成形后包络不恒定。未新增IP/系数文件，滤波历史跨帧保留，反压时与载波同步暂停。RX0dB，当前07=00/08=60用于低通旁路对照。

成形、乘载波、量化使用同步反压流水级，保持每时钟可处理一个样点的吞吐能力；流水级仅增加固定计算延迟，输出顺序和符号率不变。

当前发送幅度按原始峰值约128码的1/2设置：RRC系数较上一版整体倍增，输出峰值上限约64码；RX仍为0dB。

当前排查状态：仅将07由01改为00，旁路AD9865内部可编程RX低通；08仍为60，RX增益0dB、19.2MSPS和TX半幅RRC均保持不变。旁路不消除模拟前端自身带宽，也不旁路PGA或ADC，仍逐项读回配置。
