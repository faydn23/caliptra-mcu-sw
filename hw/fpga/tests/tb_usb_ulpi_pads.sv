// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps

module tb_usb_ulpi_pads;
    wire [7:0] USB_ULPI_DATA;
    logic [7:0] usb_ulpi_txdata = 0;
    wire [7:0] usb_ulpi_rxdata;
    logic usb_ulpi_txenable = 0;
    logic phy_owns_data = 0;
    logic [7:0] phy_data = 0;
    assign USB_ULPI_DATA = phy_owns_data ? phy_data : 8'hzz;

    // The runner extracts this harness's IOBUF block from the actual wrapper.
    usb_ulpi_pad_harness dut (.*);
    wire [7:0] disabled_data, disabled_rxdata;
    usb_ulpi_pad_harness #(.USB_ENABLE(0)) disabled_dut (
        .usb_ulpi_txdata(usb_ulpi_txdata),
        .usb_ulpi_txenable(usb_ulpi_txenable),
        .USB_ULPI_DATA(disabled_data),
        .usb_ulpi_rxdata(disabled_rxdata)
    );

    initial begin
        #101;
        assert (USB_ULPI_DATA === 8'hzz) else $fatal(1, "Turnaround must release DATA");
        for (int value = 0; value < 256; value++) begin
            phy_owns_data = 1;
            phy_data = 8'(value);
            #1;
            assert (USB_ULPI_DATA === phy_data && usb_ulpi_rxdata === phy_data)
                else $fatal(1, "PHY-owned DATA mismatch");
            phy_owns_data = 0;
            #1;
            assert (USB_ULPI_DATA === 8'hzz) else $fatal(1, "PHY turnaround failed");
            usb_ulpi_txdata = 8'(255 - value);
            usb_ulpi_txenable = 1;
            #1;
            assert (USB_ULPI_DATA === usb_ulpi_txdata && usb_ulpi_rxdata === usb_ulpi_txdata)
                else $fatal(1, "FPGA-owned DATA mismatch");
            assert (disabled_data === 8'hzz && disabled_rxdata === 8'h00)
                else $fatal(1, "Disabled USB must not drive or sample DATA");
            usb_ulpi_txenable = 0;
            #1;
            assert (USB_ULPI_DATA === 8'hzz) else $fatal(1, "FPGA turnaround failed");
        end
        $display("USB_ULPI_PADS_PASS: 256 RX/TX patterns and both turnaround directions");
        $finish;
    end
endmodule
