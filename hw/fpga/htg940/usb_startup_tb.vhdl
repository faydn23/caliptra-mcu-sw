-- SPDX-License-Identifier: Apache-2.0
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity usb_startup_tb is
end entity;

architecture test of usb_startup_tb is
  constant force_ulpi_test : boolean := false;
  signal core_clk : std_logic := '0';
  signal raw_phy_clk : std_logic := '0';
  signal phy_clk : std_logic;
  signal reset_n : std_logic := '0';
  signal phy_ready : std_logic := '0';
  signal gate_phy_clock : boolean := false;
  signal omit_rxcmd : boolean := false;
  signal rxcmd_gap : natural := 2;
  signal hub_addr : std_logic_vector(9 downto 2) := (others => '0');
  signal hub_trans : std_logic_vector(1 downto 0) := "00";
  signal hub_write, hub_sel : std_logic := '0';
  signal hub_wdata, hub_rdata : std_logic_vector(31 downto 0) := (others => '0');
  signal hub_ready : std_logic;
  signal hub_resp : std_logic_vector(1 downto 0);
  signal dev_trans : std_logic_vector(1 downto 0) := "00";
  signal dev_write, dev_sel : std_logic := '0';
  signal dev_wdata : std_logic_vector(31 downto 0) := (others => '0');
  signal phy_dir, phy_nxt : std_logic := '0';
  signal phy_data : std_logic_vector(7 downto 0) := (others => '0');
  signal link_data : std_logic_vector(7 downto 0);
  signal link_enable, link_stp : std_logic;
  signal phy_reset_commands, phy_read_commands : natural := 0;
begin
  core_clk <= not core_clk after 8.333 ns;
  raw_phy_clk <= not raw_phy_clk after 8.333 ns;
  phy_clk <= raw_phy_clk when not gate_phy_clock or phy_ready = '1' else '0';

  dut : entity work.ip_xxx_3511_hs_mem_compound
    generic map (
      C_HUB_FIFO_SIZE => 196,
      C_ULPI_SUPPORT => true,
      C_UTMI_SUPPORT => false,
      C_EXTEND_TX_DELAY => true
    )
    port map (
-- DUT_PORT_MAP
    );

  -- Transaction-level model, not a USB3320 electrical/timing model.
  phy : process
    procedure tick is
    begin
      wait until falling_edge(phy_clk);
    end procedure;
    variable command, value : std_logic_vector(7 downto 0);
  begin
    phy_dir <= '0';
    phy_nxt <= '0';
    phy_data <= x"00";
    wait until phy_ready = '1';
    loop
      tick;
      exit when phy_ready = '0';
      if link_enable = '1' and link_data(7 downto 6) = "10" then
        command := link_data;
        phy_nxt <= '1';
        tick;
        value := link_data;
        tick;
        phy_nxt <= '0';
        if command = x"85" and value = x"20" then
          phy_reset_commands <= phy_reset_commands + 1;
          report "PHY_MODEL reset command accepted";
          phy_dir <= '1';
          phy_nxt <= '1';
          for i in 1 to 8 loop tick; end loop;
          phy_dir <= '0';
          phy_nxt <= '0';
          for i in 1 to rxcmd_gap loop tick; end loop;
          if not omit_rxcmd then
            phy_dir <= '1';
            phy_data <= x"0C";
            for i in 1 to 3 loop tick; end loop;
            phy_dir <= '0';
            phy_data <= x"00";
            report "PHY_MODEL post-reset RXCMD sent";
          else
            report "PHY_MODEL deliberately withholding post-reset RXCMD";
          end if;
        end if;
      elsif link_enable = '1' and link_data = x"EF" then
        phy_nxt <= '1';
        tick;
        command := link_data;
        tick;
        phy_nxt <= '0';
        -- Turnaround cycle, followed by the PHY register response.
        phy_dir <= '1';
        phy_data <= x"00";
        tick;
        case command is
          when x"00" => phy_data <= x"24";
          when x"01" => phy_data <= x"04";
          when x"02" => phy_data <= x"07";
          when others => phy_data <= x"00";
        end case;
        tick;
        phy_dir <= '0';
        phy_data <= x"00";
        phy_read_commands <= phy_read_commands + 1;
        report "PHY_MODEL identity read " & to_hstring(command);
        tick;
      end if;
    end loop;
  end process;

  stimulus : process
    procedure cycles(count : positive) is
    begin
      for i in 1 to count loop wait until falling_edge(core_clk); end loop;
    end procedure;
    procedure write_hub(word_address : natural; value : std_logic_vector) is
    begin
      wait until falling_edge(core_clk);
      hub_addr <= std_logic_vector(to_unsigned(word_address, hub_addr'length));
      hub_trans <= "10";
      hub_write <= '1';
      hub_sel <= '1';
      wait until falling_edge(core_clk);
      hub_trans <= "00";
      hub_sel <= '0';
      hub_write <= '0';
      hub_wdata <= value;
      wait until falling_edge(core_clk);
      assert hub_ready = '1' and hub_resp = "00"
        report "AHB write failed" severity failure;
    end procedure;
    procedure read_hub(word_address : natural; variable value : out std_logic_vector) is
    begin
      wait until falling_edge(core_clk);
      hub_addr <= std_logic_vector(to_unsigned(word_address, hub_addr'length));
      hub_trans <= "10";
      hub_sel <= '1';
      wait until falling_edge(core_clk);
      hub_trans <= "00";
      hub_sel <= '0';
      assert hub_ready = '1' and hub_resp = "00"
        report "AHB read failed" severity failure;
      value := hub_rdata;
    end procedure;
    variable value : std_logic_vector(31 downto 0);
    variable request : unsigned(31 downto 0);
    variable completed : boolean;
    variable reads_before, resets_before : natural;
    type id_bytes is array (0 to 3) of std_logic_vector(7 downto 0);
    constant expected : id_bytes := (x"24", x"04", x"07", x"00");
  begin
    for scenario in 0 to 4 loop
      report "SCENARIO " & integer'image(scenario) & " starting";
      resets_before := phy_reset_commands;
      reset_n <= '0';
      phy_ready <= '0';
      gate_phy_clock <= scenario = 2;
      omit_rxcmd <= scenario = 4;
      if scenario = 3 then rxcmd_gap <= 1; else rxcmd_gap <= 2; end if;
      cycles(20);
      reset_n <= '1';
      -- Match ROM disconnect/clock-retention setup before PHY access.
      write_hub(12, x"00000001");
      dev_trans <= "10";
      dev_write <= '1';
      dev_sel <= '1';
      cycles(1);
      dev_trans <= "00";
      dev_write <= '0';
      dev_sel <= '0';
      dev_wdata <= x"00000200";
      cycles(1);
      -- Scaled board PHY hold interval; mode can be selected before PHY is ready.
      if scenario = 1 or scenario = 2 then
        if not force_ulpi_test then write_hub(15, x"80000000"); end if;
      end if;
      cycles(400);
      phy_ready <= '1';
      cycles(40 + scenario);
      if scenario /= 1 and scenario /= 2 then
        if not force_ulpi_test then write_hub(15, x"80000000"); end if;
      end if;
      read_hub(15, value);
      if force_ulpi_test then
        assert value(31) = '0' report "Forced test must leave software PHY mode zero" severity failure;
      else
        assert value(31) = '1' report "ULPI mode not selected" severity failure;
      end if;
      reads_before := phy_read_commands;
      for address in 0 to 3 loop
        request := x"80000000" + to_unsigned(address, 32);
        if force_ulpi_test then request(31) := '0'; end if;
        write_hub(15, std_logic_vector(request));
        write_hub(15, std_logic_vector(request or x"02000000"));
        completed := false;
        for poll in 1 to 400 loop
          read_hub(15, value);
          if value(25) = '0' then completed := true; exit; end if;
        end loop;
        if scenario = 4 then
          assert not completed and
            ((not force_ulpi_test and value = x"82000000") or
             (force_ulpi_test and value = x"02000000"))
            report "Missing RXCMD did not reproduce pending first read" severity failure;
          assert phy_read_commands = reads_before
            report "Read unexpectedly reached PHY without startup RXCMD" severity failure;
          report "SCENARIO 4 PASS: missing RXCMD leaves first read pending";
          exit;
        end if;
        assert completed report "PHY read timed out in scenario " &
          integer'image(scenario) & " register " & integer'image(address) &
          " ULPIDEBUG=" & to_hstring(value) severity failure;
        assert value(23 downto 16) = expected(address)
          report "Wrong PHY ID byte: " & to_hstring(value) severity failure;
        report "ID_PASS address=" & integer'image(address) &
          " data=" & to_hstring(value(23 downto 16));
      end loop;
      if scenario /= 4 then
        assert phy_read_commands = reads_before + 4
          report "Expected four physical PHY read transactions" severity failure;
        report "SCENARIO " & integer'image(scenario) & " PASS";
      end if;
      assert phy_reset_commands = resets_before + 1
        report "Expected exactly one accepted PHY reset command per scenario"
        severity failure;
      phy_ready <= '0';
      cycles(20);
    end loop;
    report "USB_STARTUP_ALL_PASS";
    finish;
  end process;

  watchdog : process
  begin
    wait for 1 ms;
    assert false report "Startup testbench watchdog expired" severity failure;
  end process;
end architecture;
