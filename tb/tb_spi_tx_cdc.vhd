library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_spi_tx_cdc is
end entity;

architecture sim of tb_spi_tx_cdc is

  -- Clocks / reset
  signal sys_clk   : std_logic := '0';
  signal sclk      : std_logic := '0';
  signal sys_rst_n : std_logic := '0';

  -- DUT ports
  signal par_tx_byte   : std_logic_vector(7 downto 0) := (others => '0');
  signal par_tx_valid  : std_logic := '0';
  signal par_tx_ready  : std_logic;

  signal phy_tx_ready  : std_logic := '0';
  signal phy_tx_byte   : std_logic_vector(7 downto 0);
  signal phy_tx_valid  : std_logic;

  constant C_SYSCLK_PERIOD : time := 10 ns;
  constant C_SCLK_PERIOD   : time := 37 ns;

  -- Expected bytes from parser to PHY
  type t_byte_array is array (natural range <>) of std_logic_vector(7 downto 0);
  constant C_NUM_BYTES   : integer := 2;
  constant C_EXP_BYTES   : t_byte_array(0 to C_NUM_BYTES-1) :=
    (x"AA", x"BB");

  signal sent_index  : integer := 0;
  signal seen_index  : integer := 0;
  signal error_count : integer := 0;

begin

  ---------------------------------------------------------------------------
  -- DUT
  ---------------------------------------------------------------------------
  dut : entity work.spi_tx_cdc
    port map (
      sys_clk      => sys_clk,
      sys_rst_n    => sys_rst_n,
      par_tx_byte  => par_tx_byte,
      par_tx_valid => par_tx_valid,
      par_tx_ready => par_tx_ready,
      sclk         => sclk,
      phy_tx_ready => phy_tx_ready,
      phy_tx_byte  => phy_tx_byte,
      phy_tx_valid => phy_tx_valid
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
  -- Monitor in SCLK domain: edge-detect phy_tx_valid
  ---------------------------------------------------------------------------
  monitor_sclk : process(sclk, sys_rst_n)
    variable prev_valid : std_logic := '0';
  begin
    if sys_rst_n = '0' then
      seen_index  <= 0;
      error_count <= 0;
      prev_valid  := '0';
    elsif rising_edge(sclk) then
      -- rising edge of valid = new byte
      if (phy_tx_valid = '1') and (prev_valid = '0') then
        if seen_index >= C_NUM_BYTES then
          error_count <= error_count + 1;
          report "TX_CDC: extra byte observed at PHY" severity error;
        elsif phy_tx_byte /= C_EXP_BYTES(seen_index) then
          error_count <= error_count + 1;
          report "TX_CDC: byte mismatch at index " &
                 integer'image(seen_index) severity error;
        else
          seen_index <= seen_index + 1;
        end if;
      end if;
      prev_valid := phy_tx_valid;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- PHY side: emulate tx_ready behaviour (byte windows)
  ---------------------------------------------------------------------------
  phy_behaviour : process
  begin
    -- keep ready low during reset
    phy_tx_ready <= '0';
    wait for 5*C_SCLK_PERIOD;

    -- Loop for each expected byte:
    for i in 0 to C_NUM_BYTES-1 loop
      -- idle a bit
      wait for 3*C_SCLK_PERIOD;

      -- assert ready for a "byte window"
      phy_tx_ready <= '1';
      wait for 4*C_SCLK_PERIOD;
      phy_tx_ready <= '0';
    end loop;

    -- after last byte, stay not ready
    wait;
  end process;

  ---------------------------------------------------------------------------
  -- SYS side: drive parser-like handshake
  ---------------------------------------------------------------------------
  stim_sys : process
  begin
    -- Reset
    sys_rst_n    <= '0';
    par_tx_valid <= '0';
    par_tx_byte  <= (others => '0');
    wait for 5*C_SYSCLK_PERIOD;
    wait until rising_edge(sys_clk);
    sys_rst_n <= '1';

    -- Wait a bit after reset
    wait for 5*C_SYSCLK_PERIOD;

    -- Send C_NUM_BYTES bytes using ready/valid
    for i in 0 to C_NUM_BYTES-1 loop
      -- wait until CDC reports ready=1
      wait until rising_edge(sys_clk);
      while par_tx_ready = '0' loop
        wait until rising_edge(sys_clk);
      end loop;

      -- drive byte + valid
      par_tx_byte  <= C_EXP_BYTES(i);
      par_tx_valid <= '1';

      -- hold valid until ready drops (meaning PHY started consuming)
      loop
        wait until rising_edge(sys_clk);
        exit when par_tx_ready = '0';
      end loop;

      par_tx_valid <= '0';
      sent_index   <= sent_index + 1;
    end loop;

    -- allow some time for last byte to propagate
    wait for 20*C_SYSCLK_PERIOD;

    -- Final checks (read-only access to error_count / seen_index)
    if seen_index /= C_NUM_BYTES then
      report "TX_CDC: expected " & integer'image(C_NUM_BYTES) &
             " bytes at PHY, got " & integer'image(seen_index) severity error;
    end if;

    if (error_count = 0) and (seen_index = C_NUM_BYTES) then
      report "TX_CDC: ALL TESTS PASSED" severity note;
    else
      report "TX_CDC: TESTS FAILED, error_count=" &
             integer'image(error_count) severity error;
    end if;

    wait;
  end process;

end architecture sim;
