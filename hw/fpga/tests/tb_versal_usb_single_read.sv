`timescale 1ns/1ps
// SPDX-License-Identifier: Apache-2.0
module tb_versal_usb_single_read;
    logic clk = 0, phy_clk = 0;
    always #12.5 clk = ~clk;
    always #8.333333 phy_clk = ~phy_clk;
    logic host_reset_n = 0, memory_reset = 1, host_active = 1;
    logic rom_en = 0, otp_en = 0, otp_we = 0;
    logic [3:0] rom_we = 0;
    logic [31:0] rom_addr = 0, rom_data = 0, rom_q;
    logic core_rom_en = 0;
    logic [3:0] core_rom_we = 0;
    logic [14:0] core_rom_addr = 0;
    logic [31:0] core_rom_data = 0, core_rom_q;
    logic [31:0] otp_addr = 0, otp_data = 0;
    logic phy_reset_n = 0;
    tri [7:0] phy_data;
    wire phy_dir, phy_nxt, phy_stp;
    wire [31:0] mcu_pc;
    wire [3:0] boot_state;
    integer vendor_reads, extended_reads, phy_resets;
    logic [63:0] rom_image [0:16383];
    logic [63:0] core_rom_image [0:12287];
    logic [21:0] otp_image [0:8191];
    string rom_file, otp_file, line = "";
    integer requests = 0, completions = 0;
    bit firmware_pass = 0;
    bit final_rom_init = 0, images_loaded = 0;
    string core_rom_file, core_line = "";

    `include "versal_usb_e2e_bindings.svh"

    usb3320_register_model phy (
        .clk(phy_clk), .reset_n(phy_reset_n), .data(phy_data),
        .dir(phy_dir), .nxt(phy_nxt), .stp(phy_stp),
        .vendor_reads(vendor_reads), .extended_reads(extended_reads),
        .phy_resets(phy_resets)
    );

    // This serial test fabric models routing/width conversion, not SmartConnect.
    // It preserves real MCU transactions and never synthesizes register results.
    function automatic integer target(input logic [31:0] address);
        if (address >= 32'hB0040000 && address < 32'hB0060000) return 0;
        if (address >= 32'hA8000000 && address < 32'hA9000000) return 1;
        if (address >= 32'hA4200000 && address < 32'hA4300000) return 2;
        if (address >= 32'hA4060000 && address < 32'hA4062000) return 3;
        if (address >= 32'hA4040000 && address < 32'hA4042000) return 4;
        if (address >= 32'hA4100000 && address < 32'hA4200000) return 5;
        if (address >= 32'hA4030000 && address < 32'hA4032000) return 6;
        if (address >= 32'hA4010000 && address < 32'hA4014000) return 7;
        return -1;
    endfunction

    integer read_master = 0, read_target = 0, write_master = 0, write_target = 0;
    integer selected_read, selected_write, next_read_target, next_write_target;
    bit read_busy = 0, write_busy = 0, aw_pending = 0;
    logic [31:0] read_addr = 0, write_addr = 0;
    logic [18:0] read_id = 0, write_id = 0;
    logic [31:0] write_user = 0;
    logic [7:0] write_len = 0;
    logic [2:0] write_size = 0;
    logic [1:0] write_burst = 0;
    logic write_lock = 0;

    always_comb begin
        selected_read = -1;
        selected_write = -1;
        for (int i = 2; i >= 0; i--) begin
            if (m_arvalid[i]) selected_read = i;
            if (m_awvalid[i]) selected_write = i;
        end
        next_read_target = -1;
        next_write_target = -1;
        m_awready = '0; m_wready = '0; m_bvalid = '0; m_bresp = '0; m_bid = '0;
        m_arready = '0; m_rvalid = '0; m_rresp = '0;
        m_rdata = '0; m_rid = '0; m_rlast = '0;
        s_awaddr = '0; s_awburst = '0; s_awsize = '0; s_awlen = '0;
        s_awuser = '0; s_awid = '0; s_awlock = '0; s_awvalid = '0;
        s_wdata = '0; s_wstrb = '0; s_wvalid = '0; s_wlast = '0; s_bready = '0;
        s_araddr = '0; s_arburst = '0; s_arsize = '0; s_arlen = '0;
        s_aruser = '0; s_arid = '0; s_arlock = '0; s_arvalid = '0; s_rready = '0;
        if (!read_busy && selected_read >= 0 && host_reset_n) begin
            next_read_target = target(m_araddr[selected_read]);
            if (next_read_target >= 0) begin
                s_araddr[next_read_target] = m_araddr[selected_read];
                s_arburst[next_read_target] = m_arburst[selected_read];
                s_arsize[next_read_target] = m_arsize[selected_read];
                s_arlen[next_read_target] = m_arlen[selected_read];
                s_aruser[next_read_target] = m_aruser[selected_read];
                s_arid[next_read_target] = m_arid[selected_read];
                s_arlock[next_read_target] = m_arlock[selected_read];
                s_arvalid[next_read_target] = m_arvalid[selected_read];
                m_arready[selected_read] = s_arready[next_read_target];
            end
        end
        if (read_busy) begin
            m_rvalid[read_master] = s_rvalid[read_target];
            m_rresp[read_master] = s_rresp[read_target];
            m_rid[read_master] = read_id;
            m_rlast[read_master] = s_rlast[read_target];
            if (read_target == 0) m_rdata[read_master] = s_rdata[read_target];
            else if (read_addr[2])
                m_rdata[read_master] = {s_rdata[read_target][31:0], 32'b0};
            else m_rdata[read_master] = {32'b0, s_rdata[read_target][31:0]};
            s_rready[read_target] = m_rready[read_master];
        end
        if (!write_busy && selected_write >= 0 && host_reset_n) begin
            next_write_target = target(m_awaddr[selected_write]);
            if (next_write_target >= 0) m_awready[selected_write] = 1;
        end
        if (write_busy) begin
            s_awaddr[write_target] = write_addr;
            s_awburst[write_target] = write_burst;
            s_awsize[write_target] = write_size;
            s_awlen[write_target] = write_len;
            s_awuser[write_target] = write_user;
            s_awid[write_target] = write_id;
            s_awlock[write_target] = write_lock;
            s_awvalid[write_target] = aw_pending;
            s_wdata[write_target] = write_target == 0 ? m_wdata[write_master] :
                (write_addr[2] ? {32'b0, m_wdata[write_master][63:32]} :
                                 {32'b0, m_wdata[write_master][31:0]});
            s_wstrb[write_target] = write_target == 0 ? m_wstrb[write_master] :
                (write_addr[2] ? {4'b0, m_wstrb[write_master][7:4]} :
                                 {4'b0, m_wstrb[write_master][3:0]});
            s_wvalid[write_target] = m_wvalid[write_master];
            s_wlast[write_target] = m_wlast[write_master];
            m_wready[write_master] = s_wready[write_target];
            m_bvalid[write_master] = s_bvalid[write_target];
            m_bresp[write_master] = s_bresp[write_target];
            m_bid[write_master] = write_id;
            s_bready[write_target] = m_bready[write_master];
        end
    end

    always @(posedge clk) begin
        if (host_reset_n) begin
            if (!read_busy && selected_read >= 0) begin
                if (next_read_target < 0)
                    $fatal(1, "Unmapped MCU read: %08x", m_araddr[selected_read]);
                if (next_read_target != 0 &&
                    (m_arlen[selected_read] != 0 || m_arsize[selected_read] > 2))
                    $fatal(1, "Unsupported CSR read burst/width");
                if (m_arready[selected_read]) begin
                    read_busy <= 1;
                    read_master <= selected_read;
                    read_target <= next_read_target;
                    read_addr <= m_araddr[selected_read];
                    read_id <= m_arid[selected_read];
                end
            end
            if (read_busy && s_rvalid[read_target] && s_rready[read_target]) begin
                if (s_rresp[read_target] != 0) $fatal(1, "AXI read error at %08x", read_addr);
                if (read_target != 7 && s_rid[read_target][7:0] != read_id[7:0])
                    $fatal(1, "AXI read ID mismatch");
                if (read_target == 2 && read_addr == 32'hA420003c &&
                    requests == 1 && !s_rdata[2][25]) begin
                    if (s_rdata[2][23:16] !== 8'h24) $fatal(1, "Wrong PHY read value");
                    completions++;
                    $display("VERSAL_USB_COMPLETION: ULPIDEBUG=%08x", s_rdata[2][31:0]);
                end
                if (s_rlast[read_target]) read_busy <= 0;
            end
            if (!write_busy && selected_write >= 0) begin
                if (next_write_target < 0)
                    $fatal(1, "Unmapped MCU write: %08x", m_awaddr[selected_write]);
                if (m_awlen[selected_write] != 0 || m_awsize[selected_write] > 2)
                    $fatal(1, "Unsupported diagnostic write burst/width");
                write_busy <= 1;
                aw_pending <= 1;
                write_master <= selected_write;
                write_target <= next_write_target;
                write_addr <= m_awaddr[selected_write];
                write_id <= m_awid[selected_write];
                write_user <= m_awuser[selected_write];
                write_len <= m_awlen[selected_write];
                write_size <= m_awsize[selected_write];
                write_burst <= m_awburst[selected_write];
                write_lock <= m_awlock[selected_write];
            end
            if (write_busy && aw_pending && s_awready[write_target]) aw_pending <= 0;
            if (write_busy && s_wvalid[write_target] && s_wready[write_target]) begin
                if (!s_wlast[write_target]) $fatal(1, "Diagnostic write missing WLAST");
                if (write_target == 2) begin
                    $display("VERSAL_USB_WRITE: addr=%08x data=%08x", write_addr, s_wdata[2][31:0]);
                    if (!final_rom_init && write_addr == 32'hA4200000 && s_wdata[2][7])
                        $fatal(1, "DEV_EN set by firmware");
                    if (!final_rom_init && write_addr == 32'hA420003c) begin
                        if (s_wdata[2][31:0] != 32'h80000000 &&
                            s_wdata[2][31:0] != 32'h82000000)
                            $fatal(1, "Unexpected ULPIDEBUG descriptor");
                        if (s_wdata[2][25]) begin
                            requests++;
                            if (requests != 1) $fatal(1, "Firmware retried PHY read");
                        end
                    end
                end
            end
            if (write_busy && s_bvalid[write_target] && s_bready[write_target]) begin
                if (s_bresp[write_target] != 0) $fatal(1, "AXI write error at %08x", write_addr);
                if (write_target != 7 && s_bid[write_target][7:0] != write_id[7:0])
                    $fatal(1, "AXI write ID mismatch");
                write_busy <= 0;
            end
        end
    end

    task automatic host_write(input logic [31:0] address, value);
        @(negedge clk);
        host_awaddr = address; host_awvalid = 1;
        host_wdata = value; host_wstrb = 4'hf; host_wvalid = 1;
        fork
            begin
                do @(posedge clk); while (!host_awready);
                @(negedge clk); host_awvalid = 0;
            end
            begin
                do @(posedge clk); while (!host_wready);
                @(negedge clk); host_wvalid = 0;
            end
        join
        do @(posedge clk); while (!host_bvalid);
        if (host_bresp != 0) $fatal(1, "Host configuration write failed at %08x", address);
        @(negedge clk);
    endtask

    initial begin
        host_awvalid = 0; host_awaddr = 0; host_awprot = 0;
        host_wvalid = 0; host_wdata = 0; host_wstrb = 0; host_bready = 1;
        host_arvalid = 0; host_araddr = 0; host_arprot = 0; host_rready = 1;
        if (!$value$plusargs("MCU_ROM=%s", rom_file)) $fatal(1, "MCU_ROM required");
        if (!$value$plusargs("OTP_IMAGE=%s", otp_file)) $fatal(1, "OTP_IMAGE required");
        final_rom_init = $test$plusargs("FINAL_ROM_INIT");
        if (final_rom_init) begin
            if (!$value$plusargs("CORE_ROM=%s", core_rom_file)) $fatal(1, "CORE_ROM required");
            $readmemh(core_rom_file, core_rom_image);
        end
        $readmemh(rom_file, rom_image);
        $readmemh(otp_file, otp_image);
        repeat (8) @(negedge clk);
        host_reset_n = 1; memory_reset = 0; phy_reset_n = 1;
        repeat (8) @(negedge clk);
        rom_en = 1; rom_we = 4'hf;
        for (int i = 0; i < 32768; i++) begin
            rom_addr = i;
            rom_data = i[0] ? rom_image[i/2][63:32] : rom_image[i/2][31:0];
            if ($isunknown(rom_data)) $fatal(1, "Unknown ROM word %0d", i);
            @(negedge clk);
        end
        rom_we = 0;
        for (int i = 0; i < 32768; i++) begin
            rom_addr = i;
            repeat (3) @(negedge clk);
            if (rom_q !== (i[0] ? rom_image[i/2][63:32] : rom_image[i/2][31:0]))
                $fatal(1, "ROM backdoor readback mismatch at word %0d", i);
        end
        rom_en = 0;
        if (final_rom_init) begin
            core_rom_en = 1; core_rom_we = 4'hf;
            for (int i = 0; i < 24576; i++) begin
                core_rom_addr = i;
                core_rom_data = i[0] ? core_rom_image[i/2][63:32] : core_rom_image[i/2][31:0];
                if ($isunknown(core_rom_data)) $fatal(1, "Unknown core ROM word %0d", i);
                @(negedge clk);
            end
            core_rom_we = 0;
            for (int i = 0; i < 24576; i++) begin
                core_rom_addr = i;
                repeat (3) @(negedge clk);
                if (core_rom_q !== (i[0] ? core_rom_image[i/2][63:32] : core_rom_image[i/2][31:0]))
                    $fatal(1, "Core ROM backdoor readback mismatch at word %0d", i);
            end
            core_rom_en = 0;
            $display("VERSAL_CORE_ROM_LOADED: full 96 KiB backdoor readback verified");
        end
        otp_en = 1; otp_we = 1;
        for (int i = 0; i < 4096; i++) begin
            otp_addr = i;
            otp_data = {otp_image[2*i+1][15:0], otp_image[2*i][15:0]};
            if ($isunknown(otp_data)) $fatal(1, "Unknown OTP word %0d", i);
            @(negedge clk);
        end
        otp_we = 0; otp_en = 0;
        images_loaded = 1;
        $display("VERSAL_IMAGES_LOADED: ROM backdoor readback verified, OTP fixture loaded");
        host_write(32'hA4010114, 32'hB0040000);
        host_write(32'hA4010008, final_rom_init ? 32'h00000001 : 32'h00000081);
        repeat (10) @(negedge clk);
        host_write(32'hA4010008, final_rom_init ? 32'h00000003 : 32'h00000083);
        host_active = 0;
        $display("VERSAL_RESET_RELEASED: using wrapper configuration registers");
    end

    always @(posedge clk) begin
        if (dut.regs.field_combo.fifo_regs.dbg_fifo_push.in_data.load_next) begin
            automatic logic [7:0] character =
                dut.regs.field_combo.fifo_regs.dbg_fifo_push.in_data.next[7:0];
            if (character == 10) begin
                $display("MCU_LOG %s", line);
                if (final_rom_init &&
                    (line == "[usb] Waiting for USB bus reset" ||
                     line == "[mcu-rom] Waiting for MCU firmware to be ready")) begin
                    if (!images_loaded || dut.cptra_ss_mcu_rst_b !== 1 || phy_resets == 0)
                        $fatal(1, "Initialization marker without ROM/MCU/PHY evidence");
                    $display("VERSAL_FINAL_ROM_INIT_PASS: checkpoint=%s", line);
                    $display("LIMIT: no host enumeration, recovery image transfer, or runtime boot verified");
                    $finish;
                end
                if (line == "[usb-single] PASS: register 00 returned 0x24") firmware_pass = 1;
                if (line == "[usb-single] HALTED: inspect ILA; reset/reprogram to run again") begin
                    if (!firmware_pass || requests != 1 || completions == 0 ||
                        vendor_reads != 1 || extended_reads != 1 || phy_resets == 0)
                        $fatal(1, "Firmware halt without required MCU/AXI/PHY evidence");
                    $display("VERSAL_USB_E2E_PASS: real MCU ROM, DEV_EN=0, one read, PHY=24, access cleared");
                    $finish;
                end

                if (line.substr(0, 17) == "[usb-single] FAIL:" ||
                    line.substr(0, 20) == "[usb-single] TIMEOUT:")
                    $fatal(1, "Firmware diagnostic failed: %s", line);
                line = "";
            end else if (character != 13) line = {line, character};
        end
    end

    always @(posedge clk) begin
        if (final_rom_init && dut.fifo_write_en) begin
            if (dut.fifo_char[7:0] == 10) begin
                $display("CALIPTRA_LOG %s", core_line);
                core_line = "";
            end else if (dut.fifo_char[7:0] != 13)
                core_line = {core_line, dut.fifo_char[7:0]};
        end
    end

    always @(posedge phy_clk) begin
        #1;
        if (phy_reset_n && phy_dir && dut.usb_ulpi_txenable !== 1'b0)
            $fatal(1, "FPGA drives DATA while PHY owns it");
    end
    initial begin
        forever begin
            #250_000;
            $display("VERSAL_PROGRESS: t=%0t PC=%08x MCU_RSTN=%b BOOT=%x starts=%0d completions=%0d PHY=%0d",
                     $time, mcu_pc, dut.cptra_ss_mcu_rst_b, boot_state, requests, completions, vendor_reads);
        end
    end
    initial begin
        #20_000_000;
        $fatal(1, "Bounded smoke watchdog: no requested checkpoint; final_rom_init=%0d PC=%08x",
               final_rom_init, mcu_pc);
    end
endmodule
