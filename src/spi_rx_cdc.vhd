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
  -- SYS domain
  signal v_meta_sys    : std_logic := '0';
  signal v_sync_sys    : std_logic := '0';
  signal v_prev_sys    : std_logic := '0';

  signal par_rx_byte_i : std_logic_vector(7 downto 0) := (others => '0');
  signal par_rx_valid_i: std_logic := '0';
begin
  par_rx_byte  <= par_rx_byte_i;
  par_rx_valid <= par_rx_valid_i;

  -- SYS domain: 2-FF sync + rising-edge detect on phy_rx_valid
  process(sys_clk, sys_rst_n)
  begin
    if sys_rst_n = '0' then
      v_meta_sys     <= '0';
      v_sync_sys     <= '0';
      v_prev_sys     <= '0';
      par_rx_valid_i <= '0';
      par_rx_byte_i  <= (others => '0');

    elsif rising_edge(sys_clk) then
      par_rx_valid_i <= '0';

      v_prev_sys <= v_sync_sys;        -- previous stable value
      v_meta_sys <= phy_rx_valid;      -- first sync FF (metastable)
      v_sync_sys <= v_meta_sys;        -- second sync FF (stable)

      -- rising edge of synced valid
      if (v_prev_sys = '0') and (v_sync_sys = '1') then
        par_rx_byte_i  <= phy_rx_byte; -- sample data bus here
        par_rx_valid_i <= '1';
      end if;
    end if;
  end process;
end architecture;

