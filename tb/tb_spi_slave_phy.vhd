library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_spi_slave_phy is
end entity tb_spi_slave_phy;

architecture sim of tb_spi_slave_phy is

  -- DUT ports
  signal sclk    : std_logic := '0';
  signal cs_n    : std_logic := '1';
  signal mosi    : std_logic := '0';
  signal miso    : std_logic;

  signal rx_byte  : std_logic_vector(7 downto 0);
  signal rx_valid : std_logic;
  signal tx_byte  : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_valid : std_logic := '0';
  signal tx_ready : std_logic;

  constant C_SCLK_PERIOD : time := 20 ns;

begin

  ---------------------------------------------------------------------------
  -- Instantiate DUT
  ---------------------------------------------------------------------------
  dut : entity work.spi_slave_phy
    generic map (
      G_CPOL => '0',
      G_CPHA => '0'
    )
    port map (
      sclk     => sclk,
      cs_n     => cs_n,
      mosi     => mosi,
      miso     => miso,
      rx_byte  => rx_byte,
      rx_valid => rx_valid,
      tx_byte  => tx_byte,
      tx_valid => tx_valid,
      tx_ready => tx_ready
    );

  ---------------------------------------------------------------------------
  -- Generate SCLK
  ---------------------------------------------------------------------------
  sclk_gen : process
  begin
    while true loop
      sclk <= '0';
      wait for C_SCLK_PERIOD/2;
      sclk <= '1';
      wait for C_SCLK_PERIOD/2;
    end loop;
  end process;

  ---------------------------------------------------------------------------
  -- Stimulus process
  ---------------------------------------------------------------------------
  stim : process
    procedure spi_send_byte(constant b : std_logic_vector(7 downto 0)) is
    begin
      -- MSB first, change MOSI on falling, sample on rising (mode 0)
      for i in 7 downto 0 loop
        wait until falling_edge(sclk);
        mosi <= b(i);
        wait until rising_edge(sclk);
      end loop;
    end procedure;

    -- local variables
    variable tx_sampled  : std_logic_vector(7 downto 0);
    variable error_count : integer := 0;

  begin
    -- Initial idle
    cs_n    <= '1';
    mosi    <= '0';
    tx_byte <= (others => '0');
    tx_valid<= '0';
    wait for 5*C_SCLK_PERIOD;

    -------------------------------------------------------------------------
    -- Test 1: RX only, send 0xA5 from master to slave
    -------------------------------------------------------------------------
    report "Test 1: RX path, sending 0xA5" severity note;
    cs_n <= '0';
    spi_send_byte(x"A5");

    -- Wait for full byte
    wait until rx_valid = '1';
    wait until falling_edge(sclk);  -- settle

    if rx_byte /= x"A5" then
      error_count := error_count + 1;
      report "Test 1 FAILED. rx_byte dec=" &
             integer'image(to_integer(unsigned(rx_byte)))
        severity error;
    else
      report "Test 1 PASSED" severity note;
    end if;

    wait until rising_edge(sclk);
    cs_n <= '1';
    wait for C_SCLK_PERIOD;  -- CS high ≥ 1 SCLK
    wait for C_SCLK_PERIOD;

    mosi <= '0';

    -------------------------------------------------------------------------
    -- Test 2: TX path, have slave transmit 0x5A while master clocks
    -------------------------------------------------------------------------
    report "Test 2: TX path, transmitting 0x5A" severity note;
    tx_byte  <= x"5A";
    tx_valid <= '1';  -- DUT will sample when tx_ready='1'

    tx_sampled := (others => '0');

    cs_n <= '0';
    -- Slave updates MISO on falling; master samples on rising
    for i in 7 downto 0 loop
      wait until falling_edge(sclk);
      
      wait until rising_edge(sclk);
      tx_sampled(i) := miso;
      report "MISO bit index " & integer'image(i) &
             " = " & std_logic'image(miso)
        severity note;
    end loop;
    cs_n <= '1';
    tx_valid <= '0';

    if tx_sampled /= x"5A" then
      error_count := error_count + 1;
      report "Test 2 FAILED. tx_sampled dec=" &
             integer'image(to_integer(unsigned(tx_sampled)))
        severity error;
    else
      report "Test 2 PASSED" severity note;
    end if;

    -------------------------------------------------------------------------
    -- Summary
    -------------------------------------------------------------------------
    if error_count = 0 then
      report "All tests PASSED" severity note;
    else
      report "TESTBENCH FAILED, error_count=" &
             integer'image(error_count)
        severity error;
    end if;

    wait for 5*C_SCLK_PERIOD;
    wait;
  end process;

end architecture sim;
