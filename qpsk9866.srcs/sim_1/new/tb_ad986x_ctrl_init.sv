`timescale 1ns/1ps
// Initialization and readback-failure test of the actual controller.
module tb_ad986x_ctrl_init;
    reg clk=0,rst_n=0,corrupt=0;
    always #10 clk=~clk;
    reg [5:0] gain=12;
    wire sclk,cs,mosi,reset_n,done,mode;
    wire [5:0] pga;
    reg miso=0;
    reg [7:0] regs[0:31];
    reg [15:0] captured;
    reg [7:0] instruction;
    integer bits=0,frames=0,i;
    ad986x_ctrl dut (
        .sys_clk(clk),.sys_rst_n(rst_n),.ad986x_rx_pga(gain),
        .ad986x_clkout1(1'b0),.ad986x_conf_miso(miso),
        .ad986x_conf_clk(sclk),.ad986x_conf_cs(cs),.ad986x_conf_mosi(mosi),
        .ad986x_reset_n(reset_n),.ad986x_mode(mode),.ad986x_pga(pga),.ad986x_conf_done(done)
    );
    time spi_edge_time;
    always @(negedge cs) spi_edge_time=$time;
    always @(sclk) if(rst_n && reset_n && !cs) begin
        if($time-spi_edge_time!=500) $fatal(1,"SPI edge interval is not 500 ns");
        spi_edge_time=$time;
    end
    always @(posedge clk) if(rst_n && !dut.reset_done) begin
        if(!cs || sclk || done) $fatal(1,"Controller active before reset_done");
    end
    function automatic [15:0] expected(input integer n);
        case(n)
            0:expected=16'h0080;1:expected=16'h8000;
            2:expected=16'h0419;3:expected=16'h8400;
            4:expected=16'h0500;5:expected=16'h8500;
            6:expected=16'h0b20;7:expected=16'h8b00;
            8:expected=16'h0c01;9:expected=16'h8c00;
            10:expected=16'h0d03;11:expected=16'h8d00;
            default:expected=0;
        endcase
    endfunction
    always @(negedge reset_n) begin
        for(i=0;i<32;i=i+1) regs[i]=0;
        bits=0;frames=0;miso=0;
    end
    always @(negedge cs) begin bits=0;captured=0;instruction=0;end
    always @(posedge sclk) if(!cs) begin
        captured={captured[14:0],mosi};bits=bits+1;
        if(bits==8) instruction=captured[7:0];
        if(bits==16 && !instruction[7]) regs[instruction[4:0]]=captured[7:0];
    end
    always @(negedge sclk) if(!cs && bits>=8 && bits<16) begin
        #14;
        if(instruction[7]) miso=corrupt ? 1'b1 : regs[instruction[4:0]][15-bits];
    end
    always @(posedge cs) if(reset_n && rst_n) begin
        if(bits!=16 || captured!==expected(frames)) $fatal(1,"Initialization frame mismatch %0d: %h",frames,captured);
        frames=frames+1;
    end
    initial begin
        #200;rst_n=1;
        wait(done);#1;
        if(frames!=12 || pga!=12 || mode!==1) $fatal(1,"Incomplete configuration");
        @(negedge clk);gain=20;#1;
        if(pga!=20) $fatal(1,"External RxPGA control failed");
        repeat(100) @(posedge clk);
        if(frames!=12 || !cs || sclk) $fatal(1,"Unexpected SPI after initialization");
        @(negedge clk);rst_n=0;corrupt=1;
        #100;rst_n=1;
        wait(frames==2);
        // Allow a complete SPI bit period for CS gap and failure handling.
        repeat(100) @(posedge clk);
        if(done || reset_n || !cs || sclk) $fatal(1,"Bad readback accepted");
        $display("CTRL_TEST_PASS: six configurations/readbacks, dynamic PGA, failure blocks startup");
        $finish;
    end
    initial begin #30000000;$fatal(1,"Control initialization timeout");end
endmodule
