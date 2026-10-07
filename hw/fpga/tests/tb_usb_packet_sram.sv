// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps

module tb_usb_packet_sram;
    logic clk = 0;
    always #5 clk = ~clk;
    logic cs = 0;
    logic [12:0] addr = 0;
    logic we_n = 1;
    logic [63:0] bsel = 0, wdata = 0;
    wire [63:0] rdata;
    logic [63:0] expected, held;

    usb_packet_sram dut (.*);

    function automatic logic [63:0] pattern(input int index);
        return 64'hfedc_ba98_7654_3210 ^ (64'h0001_0001_0001_0001 * index);
    endfunction

    task automatic cycle;
        @(posedge clk);
        #1;
        @(negedge clk);
    endtask

    initial begin
        @(negedge clk);
        cs = 1;
        we_n = 0;
        bsel = '1;
        for (int index = 0; index < 8192; index++) begin
            addr = 13'(index);
            wdata = pattern(index);
            cycle();
        end
        we_n = 1;
        for (int index = 0; index < 8192; index++) begin
            addr = 13'(index);
            cycle();
            assert (rdata === pattern(index)) else $fatal(1, "Read mismatch at %0d", index);
        end

        addr = 13'h1fff;
        expected = pattern(8191);
        for (int lane = 0; lane < 8; lane++) begin
            we_n = 0;
            bsel = 64'hff << (lane * 8);
            wdata = 64'h0123_4567_89ab_cdef;
            cycle();
            assert (rdata === expected) else $fatal(1, "Write must return previous data");
            expected[lane*8 +: 8] = wdata[lane*8 +: 8];
            we_n = 1;
            cycle();
            assert (rdata === expected) else $fatal(1, "Byte mask mismatch");
        end
        we_n = 0;
        bsel = 0;
        wdata = 0;
        cycle();
        we_n = 1;
        cycle();
        assert (rdata === expected) else $fatal(1, "Zero mask changed memory");

        held = rdata;
        cs = 0;
        addr = 0;
        we_n = 0;
        bsel = '1;
        wdata = 0;
        cycle();
        assert (rdata === held) else $fatal(1, "Disabled SRAM changed read output");
        cs = 1;
        we_n = 1;
        cycle();
        assert (rdata === pattern(0)) else $fatal(1, "Disabled SRAM accepted a write");
        addr = 1;
        #1;
        assert (rdata === pattern(0)) else $fatal(1, "Read must be synchronous");
        cycle();
        assert (rdata === pattern(1)) else $fatal(1, "Registered read mismatch");
        $display("USB_PACKET_SRAM_PASS: 8192 words, byte masks, read-first latency, chip select");
        $finish;
    end
endmodule
