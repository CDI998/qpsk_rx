`timescale 1ns / 1ps
// 独立从设备模型核对四种模式、MSB顺序、整帧锁存、忙时请求及复位。
module spi_master_case #(
    parameter integer width = 16,
    parameter cpol = 0,
    parameter cpha = 0,
    parameter integer speed = 1000000
)(output reg test_done);
    localparam integer half_ns = ((50000000 + 2*speed - 1)/(2*speed))*20;
    reg clk=0,rst_n=0,start=0,miso=0;
    always #10 clk=~clk;
    reg [width-1:0] tx_data=0;
    wire [width-1:0] rx_data;
    wire busy,done,sclk,cs_n,mosi;
    reg [width-1:0] expected_tx,expected_rx,slave_shift,slave_received;
    reg [width-1:0] last_rx=0;
    integer sample_count=0,frames=0,n;
    time last_edge;

    spi_master #(.clk_hz(50000000),.spi_clk_hz(speed),.data_width(width),.cpol(cpol),.cpha(cpha)) dut (
        .clk(clk),.rst_n(rst_n),.start(start),.tx_data(tx_data),.miso(miso),
        .busy(busy),.done(done),.rx_data(rx_data),.sclk(sclk),.cs_n(cs_n),.mosi(mosi)
    );

    always @(negedge cs_n) if(rst_n) begin
        sample_count=0;slave_received=0;last_edge=$time;
        slave_shift=cpha ? expected_rx : (expected_rx<<1);
        miso=cpha ? 1'b0 : expected_rx[width-1];
    end
    always @(sclk) if(rst_n && !cs_n) begin
        if($time-last_edge!=half_ns) $fatal(1,"SPI clock divider/first-edge timing error");
        last_edge=$time;
        // 翻转后的电平：CPHA=0在首沿采样，CPHA=1在第二沿采样。
        if(sclk!=(cpol^cpha)) begin
            slave_received=(slave_received<<1)|mosi;
            sample_count=sample_count+1;
        end else begin
            miso=slave_shift[width-1];
            slave_shift=slave_shift<<1;
        end
    end
    always @(posedge cs_n) if(rst_n) begin
        if(sample_count!=width || slave_received!==expected_tx)
            $fatal(1,"MOSI bit order/data/length mismatch: mode=%0d width=%0d",2*cpol+cpha,width);
        frames=frames+1;
    end
    always @(posedge clk) if(rst_n && busy && rx_data!==last_rx)
        $fatal(1,"rx_data changed before completion");

    task automatic send_word(input [width-1:0] word,input [width-1:0] response);
        integer old_frames;
        begin
            old_frames=frames;
            @(negedge clk);expected_tx=word;expected_rx=response;tx_data=word;start=1;
            @(negedge clk);start=0;tx_data=~word;
            // 忙时再次发请求，必须被忽略；改变输入不得改变已锁存的帧。
            repeat(3) @(posedge clk);
            @(negedge clk);start=1;
            @(negedge clk);start=0;
            wait(done);#1;
            if(busy || !cs_n || sclk!==cpol[0] || rx_data!==response || frames!=old_frames+1)
                $fatal(1,"SPI completion/RX mismatch: mode=%0d width=%0d got=%h expected=%h",2*cpol+cpha,width,rx_data,response);
            last_rx=rx_data;
            @(posedge clk);#1;
            if(done) $fatal(1,"done is not one clk pulse");
            repeat(3) @(posedge clk);
            if(busy || frames!=old_frames+1 || rx_data!==last_rx)
                $fatal(1,"Busy-time request replayed or received result not held");
        end
    endtask

    initial begin
        test_done=0;
        #100;rst_n=1;
        repeat(3) @(posedge clk);
        if(busy || done || !cs_n || sclk!==cpol[0]) $fatal(1,"Incorrect idle levels");
        send_word(0,{width{1'b1}});
        send_word({width{1'b1}},0);
        for(n=0;n<6;n=n+1) send_word($urandom,$urandom);
        // 传输中复位必须立即释放片选、清除结果并停止传输。
        @(negedge clk);expected_tx=0;expected_rx=0;tx_data=0;start=1;
        @(negedge clk);start=0;
        repeat(5) @(posedge clk);
        @(negedge clk);rst_n=0;last_rx=0;
        #1;
        if(busy || done || !cs_n || sclk!==cpol[0] || mosi || rx_data!==0)
            $fatal(1,"SPI reset did not abort transfer");
        repeat(3) @(negedge clk);
        rst_n=1;
        send_word({width{1'b1}},{width{1'b1}});
        $display("SPI_CASE_PASS mode=%0d width=%0d speed_limit=%0d",2*cpol+cpha,width,speed);
        test_done=1;
    end
endmodule

module tb_spi_master;
    wire [9:0] test_done;
    genvar mode;
    generate for(mode=0;mode<4;mode=mode+1) begin: modes
        spi_master_case #(.width(16),.cpol(mode/2),.cpha(mode%2)) word_case(test_done[mode]);
        spi_master_case #(.width(1),.cpol(mode/2),.cpha(mode%2)) bit_case(test_done[mode+4]);
    end endgenerate
    spi_master_case #(.width(8),.cpol(1),.cpha(0)) byte_case(test_done[8]);
    spi_master_case #(.width(16),.cpol(0),.cpha(1),.speed(3000000)) divider_case(test_done[9]);
    initial begin
        wait(&test_done);
        $display("SPI_MASTER_TEST_PASS: all modes, 1/8/16-bit frames, rounded divider, latched TX, RX, busy requests and reset");
        $finish;
    end
    initial begin #1000000;$fatal(1,"SPI test timeout");end
endmodule
