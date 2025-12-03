library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_spi_rx_cdc is
end entity;

architecture sim of tb_spi_rx_cdc is

  -- Clocks / reset
  signal sys_clk   : std_logic := '0';
  signal sclk      : std_logic := '0';
  signal sys_rst_n : std_logic := '0';

  -- DUT ports
  signal phy_rx_byte  : std_logic_vector(7 downto 0) := (others => '0');
  signal phy_rx_valid : std_logic := '0';
  signal par_rx_byte  : std_logic_vector(7 downto 0);
  signal par_rx_valid : std_logic;

  constant C_SYSCLK_PERIOD : time := 10 ns;
  constant C_SCLK_PERIOD   : time := 37 ns;  -- intentionally async

  -- Test data
  type t_byte_array is array (natural range <>) of std_logic_vector(7 downto 0);
  constant C_NUM_BYTES  : integer := 4;
  constant C_TX_BYTES   : t_byte_array(0 to C_NUM_BYTES-1) :=
    (x"11", x"22", x"33", x"44");

  signal recv_count  : integer := 0;
  signal error_count : integer := 0;

begin

  ---------------------------------------------------------------------------
  -- DUT
  ---------------------------------------------------------------------------
  dut : entity work.spi_rx_cdc
    port map (
      sclk         => sclk,
      phy_rx_byte  => phy_rx_byte,
      phy_rx_valid => phy_rx_valid,
      sys_clk      => sys_clk,
      sys_rst_n    => sys_rst_n,
      par_rx_byte  => par_rx_byte,
      par_rx_valid => par_rx_valid
    );

  ---------------------------------------------------------------------------
  -- Clock generators
  ---------------------------------------------------------------------------
  sys_clk_gen : process
  begin
    while true loop
      sys_clk <= '0'; wait for C_SYSCLK_PERIOD/2;
      sys_clk <= '1'; wait for C_SYSCLK_PERIOD/2;
    end loop;
  end process;

  sclk_gen : process
  begin
    while true loop
      sclk <= '0'; wait for C_SCLK_PERIOD/2;
      sclk <= '1'; wait for C_SCLK_PERIOD/2;
    end loop;
  end process;

  ---------------------------------------------------------------------------
  -- Monitor in SYS domain: count / check received bytes
  ---------------------------------------------------------------------------
  monitor_sys : process(sys_clk, sys_rst_n)
  begin
    if sys_rst_n = '0' then
      recv_count  <= 0;
      error_count <= 0;
    elsif rising_edge(sys_clk) then
      if par_rx_valid = '1' then
        if recv_count >= C_NUM_BYTES then
          error_count <= error_count + 1;
          report "RX_CDC: extra par_rx_valid pulse" severity error;
        elsif par_rx_byte /= C_TX_BYTES(recv_count) then
          error_count <= error_count + 1;
          report "RX_CDC: byte mismatch at index " &
                 integer'image(recv_count) severity error;
        end if;
        recv_count <= recv_count + 1;
      end if;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- Stimulus in SCLK domain: send C_TX_BYTES as pulses on phy_rx_valid
  ---------------------------------------------------------------------------
  stim : process

    procedure send_byte(constant b : std_logic_vector(7 downto 0)) is
    begin
      -- Align to SCLK edge
      wait until rising_edge(sclk);
      phy_rx_byte  <= b;
      phy_rx_valid <= '1';
      wait until rising_edge(sclk);   -- 1 SCLK pulse
      phy_rx_valid <= '0';
      -- gap of a few SCLKs
      wait until rising_edge(sclk);
      wait until rising_edge(sclk);
    end procedure;

  begin
    -- Reset
    sys_rst_n    <= '0';
    phy_rx_valid <= '0';
    wait for 5*C_SYSCLK_PERIOD;
    wait until rising_edge(sys_clk);
    sys_rst_n <= '1';

    -- Give some time after reset
    wait for 5*C_SYSCLK_PERIOD;

    -- Drive bytes
    for i in 0 to C_NUM_BYTES-1 loop
      send_byte(C_TX_BYTES(i));
    end loop;

    -- Wait for all bytes to cross
    wait for 20*C_SYSCLK_PERIOD;

    -- Final checks (READ ONLY: no assignments to error_count here)
    if recv_count /= C_NUM_BYTES then
      report "RX_CDC: expected " & integer'image(C_NUM_BYTES) &
             " bytes, got " & integer'image(recv_count) severity error;
    end if;

    if error_count = 0 and recv_count = C_NUM_BYTES then
      report "RX_CDC: ALL TESTS PASSED" severity note;
    else
      report "RX_CDC: TESTS FAILED, error_count=" &
             integer'image(error_count) severity error;
    end if;

    wait;
  end process;

end architecture sim;
