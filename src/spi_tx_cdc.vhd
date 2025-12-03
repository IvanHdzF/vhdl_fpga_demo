library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity spi_tx_cdc is
  port (
    -- SYS domain (parser)
    sys_clk       : in  std_logic;
    sys_rst_n     : in  std_logic;
    par_tx_byte   : in  std_logic_vector(7 downto 0);
    par_tx_valid  : in  std_logic;
    par_tx_ready  : out std_logic;

    -- SCLK domain (PHY)
    sclk          : in  std_logic;
    phy_tx_ready  : in  std_logic;
    phy_tx_byte   : out std_logic_vector(7 downto 0);
    phy_tx_valid  : out std_logic
  );
end entity;

architecture rtl of spi_tx_cdc is
  -- ready sync into SYS
  signal ready_sync_sys : std_logic_vector(1 downto 0) := (others => '0');
  signal par_tx_ready_i : std_logic := '0';

  -- data/flag in SYS
  signal tx_data_sys    : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_has_data_sys: std_logic := '0';

  -- flag sync into SCLK
  signal has_data_sync_sclk : std_logic_vector(1 downto 0) := (others => '0');
begin
  par_tx_ready <= par_tx_ready_i;

  -- SYS domain
  process(sys_clk, sys_rst_n)
  begin
    if sys_rst_n = '0' then
      ready_sync_sys   <= (others => '0');
      par_tx_ready_i   <= '0';
      tx_data_sys      <= (others => '0');
      tx_has_data_sys  <= '0';
    elsif rising_edge(sys_clk) then
      -- sync ready from PHY
      ready_sync_sys(0) <= phy_tx_ready;
      ready_sync_sys(1) <= ready_sync_sys(0);
      par_tx_ready_i    <= ready_sync_sys(1);

      -- launch new byte if parser drives valid while ready=1
      if (par_tx_valid = '1') and (par_tx_ready_i = '1') then
        tx_data_sys     <= par_tx_byte;
        tx_has_data_sys <= '1';
      end if;

      -- optional: clear flag when not ready (meaning PHY started using it)
      if par_tx_ready_i = '0' then
        tx_has_data_sys <= '0';
      end if;
    end if;
  end process;

  -- SCLK domain: use the latched byte whenever we have_data
  process(sclk)
  begin
    if rising_edge(sclk) then
      has_data_sync_sclk(0) <= tx_has_data_sys;
      has_data_sync_sclk(1) <= has_data_sync_sclk(0);

      if has_data_sync_sclk(1) = '1' then
        phy_tx_byte  <= tx_data_sys;
        phy_tx_valid <= '1';
      else
        phy_tx_valid <= '0';
      end if;
    end if;
  end process;
end architecture;
