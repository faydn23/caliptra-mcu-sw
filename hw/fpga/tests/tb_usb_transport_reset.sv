// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps

module tb_usb_transport_reset;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst = 1;
    logic req = 0;
    logic is_wr = 0;
    logic [31:0] wr_data = 0;
    mci_reg_pkg::mci_reg__in_t hwif_in;
    mci_reg_pkg::mci_reg__out_t usb_out, i3c_out;

    for (genvar transport = 0; transport < 2; transport++) begin : g_transport
        mci_reg #(.STREAMING_BOOT_SELECT_RESET(2'(transport))) dut (
            .clk(clk), .rst(rst),
            .s_cpuif_req(req), .s_cpuif_req_is_wr(is_wr),
            .s_cpuif_addr(13'h0), .s_cpuif_wr_data(wr_data),
            .s_cpuif_wr_biten(32'h0000_0003),
            .s_cpuif_req_stall_wr(), .s_cpuif_req_stall_rd(),
            .s_cpuif_rd_ack(), .s_cpuif_rd_err(), .s_cpuif_rd_data(),
            .s_cpuif_wr_ack(), .s_cpuif_wr_err(),
            .hwif_in(hwif_in),
            .hwif_out()
        );
    end
    assign usb_out = g_transport[0].dut.hwif_out;
    assign i3c_out = g_transport[1].dut.hwif_out;

    initial begin
        hwif_in = '0;
        hwif_in.axi_mcu_req_or_mci_soc_config_req__cap_unlock = 1;
        repeat (2) @(negedge clk);
        assert (usb_out.HW_CAPABILITIES.STREAMING_BOOT_SELECT.value === 2'h0)
            else $fatal(1, "USB profile reset value mismatch");
        assert (i3c_out.HW_CAPABILITIES.STREAMING_BOOT_SELECT.value === 2'h1)
            else $fatal(1, "No-card profile must report I3C");
        rst = 0;
        hwif_in.mci_rst_b = 1;
        req = 1;
        is_wr = 1;
        wr_data = 0;
        @(negedge clk);
        req = 0;
        repeat (4) @(negedge clk);
        assert (usb_out.HW_CAPABILITIES.STREAMING_BOOT_SELECT.value === 2'h0 &&
                i3c_out.HW_CAPABILITIES.STREAMING_BOOT_SELECT.value === 2'h0)
            else $fatal(1, "Software transport selection changed behavior");
        rst = 1;
        hwif_in.mci_rst_b = 0;
        repeat (2) @(negedge clk);
        assert (usb_out.HW_CAPABILITIES.STREAMING_BOOT_SELECT.value === 2'h0 &&
                i3c_out.HW_CAPABILITIES.STREAMING_BOOT_SELECT.value === 2'h1)
            else $fatal(1, "Transport reset was not restored");
        $display("USB_TRANSPORT_RESET_PASS: USB/I3C reset values and software override");
        $finish;
    end
endmodule
