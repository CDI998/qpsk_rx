# qpsk9866 V2

只维护当前 qpsk9866.xpr。唯一工程配置入口是 scripts/setup_project.tcl；首次配置或配置变更后执行并保存，日常直接在 Vivado 生成比特流。

- 唯一手写约束：qpsk9866.srcs/constrs_1/new/ax7010.xdc，包含引脚、接口时序和正式 ILA。
- 正式设计源、原生 FIFO IP、仿真源保留在 qpsk9866.srcs。
- TX：2 MHz，19.2 MSPS，96 点表步进 10，幅度约 ±128 码；RX 增益 0 dB。
- 12 位样本与 FIFO；AD9865 有效补码 [9:0]，高两位补零；物理低四位使用 [5:2]。
- SPI：00=80、04=19、05=00、0B=20、0C=01、0D=03；没有临时数字回环或滤波旁路。
- 唯一 ILA u_ila_dac：DAC FIFO 读出样本和读使能、ADC FIFO 写入前样本和写使能、复位、配置完成。
- 顶层在 AFE 就绪且 RX FIFO 非空时持续读取。
- 烧录本次生成的 qpsk9866.runs/impl_1/top.bit 和 debug_nets.ltx。
- 原始测量 CSV 位于 measurements；原有 Visio 位于 doc/design。

Vivado 和厂商 IP 自动生成的 Tcl/XDC 不属于手写维护入口，不手改。旧诊断产物已移出工程归档，不再维护。ADC 异常仍在排查。
