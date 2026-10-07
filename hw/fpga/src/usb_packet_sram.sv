// SPDX-License-Identifier: Apache-2.0

module usb_packet_sram #(
    parameter int ADDR_WIDTH = 13
) (
    input  logic                  clk,
    input  logic                  cs,
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic                  we_n,
    input  logic [63:0]           bsel,
    input  logic [63:0]           wdata,
    output wire  [63:0]           rdata
);
    for (genvar lane = 0; lane < 8; lane++) begin : g_lane
        (* ram_style = "block" *) logic [7:0] ram [0:(1 << ADDR_WIDTH)-1];
        logic [7:0] read_data;
        wire [7:0] lane_select = bsel[lane*8 +: 8];

        always_ff @(posedge clk) begin
            if (cs) begin
                read_data <= ram[addr];
                if (!we_n && lane_select == 8'hff)
                    ram[addr] <= wdata[lane*8 +: 8];
`ifndef SYNTHESIS
                if (!we_n)
                    assert (lane_select == 8'h00 || lane_select == 8'hff)
                        else $error("USB SRAM requires whole-byte write masks");
`endif
            end
        end
        assign rdata[lane*8 +: 8] = read_data;
    end
endmodule
