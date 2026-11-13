# Each entry is {instance signal width}; order defines the ILA probe index.
set htg_ulpi_schema {
    {usb_pie_1 phy_start 1}
    {usb_pie_1 reset_n 1}
    {usb_pie_1 phy_address 8}
    {usb_pie_1 phy_write 1}
    {usb_pie_1 htg_ulpi_state 5}
    {usb_pie_1 pie_lowpower_n 1}
    {usb_pie_1 ulpi_xreg_rdata_r 8}
    {usb_pie_1 phy_endtoggle_r 1}
}
set htg_core_schema {
    {u_hub_compound usbreg_phy_addr 8}
    {u_hub_compound usbreg_phy_wdata 8}
    {u_hub_compound usbreg_phy_write 1}
    {u_hub_compound usbreg_phy_start 1}
    {u_hub_compound usbreg_phy_mode 1}
    {u_hub_compound sync_phy_endtoggle 1}
    {u_hub_compound sync_phy_rdata 8}
    {usb_reg_if_1 hresetn 1}
    {u_hub_compound clock_on 1}
}
if {[info exists htgSoftwareUlpiStartup] && $htgSoftwareUlpiStartup} {
    lappend htg_core_schema \
        {u_hub_compound htg_pie_reset_n 1} \
        {u_hub_compound reset_n 1}
}
