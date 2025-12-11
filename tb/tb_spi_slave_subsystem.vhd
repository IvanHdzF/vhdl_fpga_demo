library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_spi_slave_subsystem is
end entity;

architecture sim of tb_spi_slave_subsystem is

  -- clocks / reset
  signal sys_clk   : std_logic := '0';
  signal sys_rst_n : std_logic := '0';

  signal sclk      : std_logic := '0';
  signal cs_n      : std_logic := '1';
  signal mosi      : std_logic := '0';
  signal miso      : std_logic;

  constant C_SYSCLK_PERIOD : time := 10 ns;
  constant C_SCLK_PERIOD   : time := 100 ns;  -- SPI clock

begin

  ---------------------------------------------------------------------------
  -- DUT (adjust port map if needed)
  ---------------------------------------------------------------------------
  dut : entity work.spi_slave_subsystem
    port map (
      sclk      => sclk,
      cs_n      => cs_n,
      mosi      => mosi,
      miso      => miso,
      sys_clk   => sys_clk,
      sys_rst_n => sys_rst_n
    );

  ---------------------------------------------------------------------------
  -- sys_clk generator
  ---------------------------------------------------------------------------
  sys_clk_gen : process
  begin
    while true loop
      sys_clk <= '0'; wait for C_SYSCLK_PERIOD/2;
      sys_clk <= '1'; wait for C_SYSCLK_PERIOD/2;
    end loop;
  end process;

  ---------------------------------------------------------------------------
  -- Stimulus + local SPI helper
  ---------------------------------------------------------------------------
  stim : process

    -- simple SPI master byte transfer (mode 0, MSB first)
    procedure spi_transfer_byte(
      constant tx_b : in  std_logic_vector(7 downto 0);
      variable rx_b : out std_logic_vector(7 downto 0)
    ) is
    begin
      for i in 7 downto 0 loop
        -- set MOSI while SCLK low
        sclk <= '0';
        mosi <= tx_b(i);
        wait for C_SCLK_PERIOD/2;

        -- rising edge: sample MISO in middle of high phase
        sclk <= '1';
        wait for C_SCLK_PERIOD/4;
        rx_b(i) := miso;
        wait for C_SCLK_PERIOD/4;
      end loop;

      -- return SCLK low between calls
      sclk <= '0';
      wait for C_SCLK_PERIOD/2;
    end procedure;

    type t_byte_array is array (natural range <>) of std_logic_vector(7 downto 0);
    variable rx_bytes    : t_byte_array(0 to 3);
    variable rd_word     : std_logic_vector(31 downto 0);
    variable error_count : integer := 0;

  begin
    -------------------------------------------------------------------------
    -- Reset
    -------------------------------------------------------------------------
    sys_rst_n <= '0';
    cs_n      <= '1';
    sclk      <= '0';
    mosi      <= '0';

    wait for 5*C_SYSCLK_PERIOD;
    wait until rising_edge(sys_clk);
    sys_rst_n <= '1';
    wait for 5*C_SYSCLK_PERIOD;

    -------------------------------------------------------------------------
    -- Test 1: WRITE 0xDEADBEEF to addr 0x12
    -------------------------------------------------------------------------
    report "Test 1: WRITE 0xDEADBEEF to addr 0x12" severity note;

    cs_n <= '0';
    wait for C_SCLK_PERIOD;

    -- cmd: RW=0, addr=0x12 => 0x12
    spi_transfer_byte(x"12", rx_bytes(0));  -- ignore readback

    -- data bytes MSB-first: DE AD BE EF
    spi_transfer_byte(x"DE", rx_bytes(0));
    spi_transfer_byte(x"AD", rx_bytes(1));
    spi_transfer_byte(x"BE", rx_bytes(2));
    spi_transfer_byte(x"EF", rx_bytes(3));

    cs_n <= '1';
    sclk <= '0';
    wait for 5*C_SCLK_PERIOD;

    -------------------------------------------------------------------------
    -- Test 2: READ from addr 0x12 with PAUSE after command
    -------------------------------------------------------------------------
    report "Test 2: READ back from addr 0x12 with SCLK pause" severity note;

    cs_n <= '0';
    wait for C_SCLK_PERIOD;

    -- cmd: RW=1, addr=0x12 => 0x80 | 0x12 = 0x92
    spi_transfer_byte(x"92", rx_bytes(0));  -- ignore readback

    -- *** PAUSE SCLK here to give parser + CDC time to queue DEADBEEF ***
    sclk <= '0';
    wait for 8*C_SCLK_PERIOD;  -- no SCLK edges, CS_n still low

    -- 1st dummy byte: gives parser + FIFO time, discard MISO
    spi_transfer_byte(x"00", rx_bytes(0));   -- MISO here is don't-care

    -- Now clock out 4 dummy bytes while sampling MISO
    spi_transfer_byte(x"00", rx_bytes(0));
    spi_transfer_byte(x"00", rx_bytes(1));
    spi_transfer_byte(x"00", rx_bytes(2));
    spi_transfer_byte(x"00", rx_bytes(3));

    cs_n <= '1';
    sclk <= '0';

    -- assemble readback word
    rd_word := rx_bytes(0) & rx_bytes(1) & rx_bytes(2) & rx_bytes(3);

    if rd_word /= x"DEADBEEF" then
        error_count := error_count + 1;
        report "Test 2 FAILED: read data mismatch" severity error;
        report "rx_bytes(0) = " & integer'image(to_integer(unsigned(rx_bytes(0))));
        report "rx_bytes(1) = " & integer'image(to_integer(unsigned(rx_bytes(1))));
        report "rx_bytes(2) = " & integer'image(to_integer(unsigned(rx_bytes(2))));
        report "rx_bytes(3) = " & integer'image(to_integer(unsigned(rx_bytes(3))));
    else
        report "Test 2 PASSED: read data OK" severity note;
    end if;

    -------------------------------------------------------------------------
    -- Summary
    -------------------------------------------------------------------------
    if error_count = 0 then
      report "spi_slave_subsystem: ALL TESTS PASSED" severity note;
    else
      report "spi_slave_subsystem: TESTS FAILED, error_count=" &
             integer'image(error_count) severity error;
    end if;

    wait;
  end process;

end architecture;
