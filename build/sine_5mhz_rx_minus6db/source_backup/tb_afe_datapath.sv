`timescale 1ns/1ps
// Actual top + actual native FIFO IPs, independent system and AFE clocks.
module tb_afe_datapath;
    reg sys_clk=0,afe_clk=0,rst_n=0;
    always #10 sys_clk=~sys_clk;
    real afe_half_ns, model_dac_hz, model_adc_hz;
    // Derive the clock from SPI clock-register semantics, not a fixed clock assumption.
    always begin
        model_dac_hz = 38400000.0 * (2.0 ** regs[4][1:0]);
        model_adc_hz = regs[4][4] ? model_dac_hz / (2.0 ** regs[4][3:2]) : 38400000.0;
        afe_half_ns = reset_n ? 1.0e9 / (4.0 * model_adc_hz) : 13.021;
        #(afe_half_ns) afe_clk=~afe_clk;
    end
    wire sclk,cs,mosi,reset_n,tx_en,tx_sync,mode;
    wire [5:0] pga,tx_bus;
    reg [5:0] adc_bus=0;
    reg adc_sync=1,miso=0;
    reg [9:0] adc_word=0;
    reg [7:0] regs[0:31];
    reg [15:0] captured;
    reg [7:0] instruction;
    integer bits=0,frames=0,i;
    reg [11:0] expected_tx[0:65535];
    integer tx_sent=0,tx_seen=0,rx_seen=0,backpressure=0;
    reg [5:0] tx_upper;
    reg packet_present=0,have_upper=0;
    reg [11:0] decoded_tx,last_rx;
    reg have_rx=0,check_rx=1;
    reg [11:0] previous_adc_write;
    integer adc_written=0;
    reg previous_accept=0;
    reg [11:0] previous_sample=0;
    integer signed_sample;
    real ideal,error;
    top dut (
        .sys_clk(sys_clk),.sys_rst_n(rst_n),.afe_clkout1(afe_clk),.afe_txrx_clk(afe_clk),
        .afe_rx_sync(adc_sync),.afe_rx_data(adc_bus),.afe_conf_miso(miso),
        .afe_conf_mosi(mosi),.afe_conf_clk(sclk),.afe_conf_cs(cs),
        .afe_tx_en(tx_en),.afe_tx_sync(tx_sync),.afe_tx_data(tx_bus),
        .afe_reset_n(reset_n),.afe_mode(mode),.afe_pga(pga)
    );
    always @(negedge reset_n) begin
        for(i=0;i<32;i=i+1) regs[i]=0;
        regs[4]=8'h01;regs[12]=8'h41;regs[13]=8'h01;
        frames=0;bits=0;miso=0;
    end
    always @(negedge cs) begin bits=0;captured=0;instruction=0;end
    always @(posedge sclk) if(!cs) begin
        captured={captured[14:0],mosi};bits=bits+1;
        if(bits==8) instruction=captured[7:0];
        if(bits==16 && !instruction[7]) regs[instruction[4:0]]=captured[7:0];
    end
    always @(negedge sclk) if(!cs && bits>=8 && bits<16) begin
        #14;if(instruction[7]) miso=regs[instruction[4:0]][15-bits];
    end
    always @(posedge cs) if(reset_n && rst_n) frames=frames+1;
    // 0D=03: chip launches on falling RXCLK. Low nibble is LEFT justified.
    always @(negedge afe_clk) begin
        if(!reset_n) begin adc_sync=1;adc_bus=0;adc_word=0;end
        else begin
            #3;
            if(adc_sync) begin adc_sync=0;adc_bus=adc_word[9:4];end
            else begin
                adc_sync=1;adc_bus={adc_word[3:0],2'b11};adc_word=adc_word+1'b1;
            end
        end
    end
    always @(posedge sys_clk) begin
        if(!rst_n) begin previous_accept=0;previous_sample=0;end
        else begin
            if(!dut.afe_init_done && (!dut.afe_tx_full || !dut.afe_rx_empty || tx_en))
                $fatal(1,"Interfaces active before initialization");
            if(!previous_accept && dut.afe_tx_sample!==previous_sample)
                $fatal(1,"Sine phase advanced without FIFO acceptance");
            if(check_rx && dut.afe_init_done && dut.afe_rx_rd_en!==!dut.afe_rx_empty)
                $fatal(1,"Top must continuously drain every available ADC sample");
            previous_accept=dut.afe_tx_wr_en;previous_sample=dut.afe_tx_sample;
            if(dut.afe_tx_wr_en) begin
                if(dut.afe_tx_full) $fatal(1,"Write while full");
                if(tx_sent>=65536) $fatal(1,"TX scoreboard overflow");
                signed_sample=$signed(dut.afe_tx_sample[9:0]);
                ideal=128.0*$sin(6.283185307179586*((tx_sent*25)%96)/96.0);
                error=signed_sample-ideal;
                if(error>0.51 || error< -0.51 || dut.afe_tx_sample[11:10]!=0)
                    $fatal(1,"Invalid 5 MHz sine waveform");
                expected_tx[tx_sent]=dut.afe_tx_sample;tx_sent=tx_sent+1;
            end
            if(dut.afe_init_done && dut.afe_tx_full) backpressure=backpressure+1;
            if(dut.afe_rx_rd_en) begin
                if(dut.afe_rx_empty) $fatal(1,"Read while empty");
                if(dut.afe_rx_sample[11:10]!=0) $fatal(1,"ADC padding not zero");
                if(check_rx && have_rx && dut.afe_rx_sample!==((last_rx+12'd1)&12'h3ff))
                    $fatal(1,"ADC ordering or 6+4 packing error: %h -> %h",last_rx,dut.afe_rx_sample);
                last_rx=dut.afe_rx_sample;have_rx=1;rx_seen=rx_seen+1;
            end
        end
    end
    // Decode physical DAC pins at the actual chip sampling edge.
    always @(posedge afe_clk) begin
        if(!rst_n) begin have_upper=0;packet_present=0;end
        else begin
            if(!tx_sync) begin
                tx_upper=tx_bus;have_upper=1;
                packet_present=dut.u_afe.tx_fifo_rd_en;
                if(dut.u_afe.u_ad986x_tx.dac_sample_valid!==packet_present)
                    $fatal(1,"DAC probe valid differs from actual FIFO read");
                if(packet_present && dut.u_afe.u_ad986x_tx.dac_sample!==expected_tx[tx_seen])
                    $fatal(1,"DAC probe differs from transmitted sample");
                if(packet_present && tx_bus!==dut.u_afe.u_ad986x_tx.dac_sample[9:4])
                    $fatal(1,"DAC high pins differ from probed word");
            end else if(have_upper) begin
                decoded_tx={2'b00,tx_upper,tx_bus[5:2]};have_upper=0;
                if(packet_present && tx_bus[5:2]!==dut.u_afe.u_ad986x_tx.dac_sample[3:0])
                    $fatal(1,"DAC low pins differ from probed word");
                if(tx_bus[1:0]!==0) $fatal(1,"DAC low padding not zero");
                if(packet_present) begin
                    if(tx_seen>=tx_sent || decoded_tx!==expected_tx[tx_seen])
                        $fatal(1,"DAC order/split error at %0d: %h expected %h",tx_seen,decoded_tx,expected_tx[tx_seen]);
                    tx_seen=tx_seen+1;
                end else if(decoded_tx!==0) $fatal(1,"DAC underflow did not send zero");
            end
            if(dut.u_afe.afe_rst_n) begin
                if($bits(dut.u_afe.u_ad986x_tx.dac_sample)!=12 ||
                   $bits(dut.u_afe.u_ad986x_rx.adc_sample)!=12)
                    $fatal(1,"ILA sample width must remain 12");
                if(dut.u_afe.u_ad986x_rx.adc_sample!==dut.u_afe.rx_fifo_data ||
                   dut.u_afe.u_ad986x_rx.adc_sample_valid!==dut.u_afe.rx_fifo_wr_en)
                    $fatal(1,"ADC probe must match FIFO input and write enable");
                if(dut.u_afe.rx_fifo_wr_en) begin
                    if(dut.u_afe.u_ad986x_rx.adc_sample[11:10]!==0)
                        $fatal(1,"ADC probe high bits not zero");
                    if(check_rx && adc_written>0 &&
                       dut.u_afe.u_ad986x_rx.adc_sample!==((previous_adc_write+12'd1)&12'h3ff))
                        $fatal(1,"ADC FIFO write sample out of order");
                    previous_adc_write=dut.u_afe.u_ad986x_rx.adc_sample;
                    adc_written=adc_written+1;
                end
                if(dut.u_afe.tx_fifo_rd_en && (dut.u_afe.tx_empty || dut.u_afe.tx_fifo_rd_rst_busy))
                    $fatal(1,"TX empty/reset read");
                if(dut.u_afe.rx_fifo_wr_en && (dut.u_afe.rx_full || dut.u_afe.rx_fifo_wr_rst_busy))
                    $fatal(1,"RX full/reset write");
            end
        end
    end
    initial begin
        #200;rst_n=1;
        wait(dut.afe_init_done);#1;
        if(frames!=12 || !tx_en || mode!==1 || pga!=12 || regs[4]!=8'h19 || regs[11]!=8'h20 || regs[12]!=8'h01 || regs[5]!=0 || regs[13]!=8'h03)
            $fatal(1,"Configuration or aggregate startup failed");
        if(regs[12][7:6]!==2'b00 || model_dac_hz<40000000.0 || model_dac_hz>200000000.0 ||
           model_adc_hz<5000000.0 || model_adc_hz>80000000.0 ||
           model_dac_hz/model_adc_hz!=4.0)
            $fatal(1,"Illegal full-duplex interpolation or clock frequencies");
        wait(tx_seen>=4096 && rx_seen>=4096);
        if(backpressure==0) $fatal(1,"TX backpressure not exercised");
        $display("SINE_ADC_TEST_PASS: 5 MHz sine, 4096 physical DAC words, ADC order, 12-bit native FIFOs and backpressure");
        check_rx=0;
        force dut.afe_rx_rd_en=0;
        wait(dut.u_afe.rx_full);
        repeat(20) @(posedge afe_clk);
        release dut.afe_rx_rd_en;
        repeat(4000) @(posedge sys_clk);
        @(negedge sys_clk);rst_n=0;
        #100;
        if(dut.afe_init_done || tx_en || !dut.afe_tx_full || !dut.afe_rx_empty || sclk || !cs)
            $fatal(1,"Reset failed to block all interfaces");
        $display("FULL_AFE_TEST_PASS: full inhibits ADC writes; reset blocks TX/RX; FIFO samples match DAC pins");
        $finish;
    end
    initial begin #20000000;$fatal(1,"Datapath timeout");end
endmodule
