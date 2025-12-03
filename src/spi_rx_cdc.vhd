library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_rx_cdc is
  port (
    -- SCLK domain
    sclk         : in  std_logic;
    phy_rx_byte  : in  std_logic_vector(7 downto 0);
    phy_rx_valid : in  std_logic;

    -- SYS domain
    sys_clk      : in  std_logic;
    sys_rst_n    : in  std_logic;
    par_rx_byte  : out std_logic_vector(7 downto 0);
    par_rx_valid : out std_logic
  );
end entity;

architecture rtl of spi_rx_cdc is
  signal rx_data_sclk    : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_req_tgl_sclk : std_logic := '0';
  signal rx_req_sync_sys : std_logic_vector(1 downto 0) := (others => '0');
  signal par_rx_byte_i   : std_logic_vector(7 downto 0) := (others => '0');
  signal par_rx_valid_i  : std_logic := '0';
begin
  par_rx_byte  <= par_rx_byte_i;
  par_rx_valid <= par_rx_valid_i;

  -- SCLK domain: capture byte + toggle
  process(sclk)
  begin
    if rising_edge(sclk) then
      if phy_rx_valid = '1' then
        rx_data_sclk   <= phy_rx_byte;
        rx_req_tgl_sclk <= not rx_req_tgl_sclk;
      end if;
    end if;
  end process;

  -- SYS domain: detect toggle, generate 1-cycle pulse
  process(sys_clk, sys_rst_n)
  begin
    if sys_rst_n = '0' then
      rx_req_sync_sys <= (others => '0');
      par_rx_valid_i  <= '0';
      par_rx_byte_i   <= (others => '0');
    elsif rising_edge(sys_clk) then
      par_rx_valid_i <= '0';

      rx_req_sync_sys(0) <= rx_req_tgl_sclk;
      rx_req_sync_sys(1) <= rx_req_sync_sys(0);

      if rx_req_sync_sys(1) /= rx_req_sync_sys(0) then
        par_rx_byte_i  <= rx_data_sclk;
        par_rx_valid_i <= '1';
      end if;
    end if;
  end process;
end architecture;
