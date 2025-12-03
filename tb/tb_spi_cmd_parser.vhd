library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_spi_cmd_parser is
end entity tb_spi_cmd_parser;

architecture sim of tb_spi_cmd_parser is

  signal sys_clk   : std_logic := '0';
  signal sys_rst_n : std_logic := '0';

  signal rx_byte   : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_valid  : std_logic := '0';

  signal tx_byte   : std_logic_vector(7 downto 0);
  signal tx_valid  : std_logic;
  signal tx_ready  : std_logic := '0';

  signal reg_wr_en : std_logic;
  signal reg_addr  : unsigned(6 downto 0);
  signal reg_wdata : std_logic_vector(31 downto 0);
  signal reg_rdata : std_logic_vector(31 downto 0) := (others => '0');

  constant C_SYSCLK_PERIOD : time := 10 ns;

begin

  ---------------------------------------------------------------------------
  -- DUT
  ---------------------------------------------------------------------------
  dut : entity work.spi_cmd_parser
    generic map (
      G_ADDR_WIDTH => 7,
      G_DATA_WIDTH => 32
    )
    port map (
      sys_clk   => sys_clk,
      sys_rst_n => sys_rst_n,
      rx_byte   => rx_byte,
      rx_valid  => rx_valid,
      tx_byte   => tx_byte,
      tx_valid  => tx_valid,
      tx_ready  => tx_ready,
      reg_wr_en => reg_wr_en,
      reg_addr  => reg_addr,
      reg_wdata => reg_wdata,
      reg_rdata => reg_rdata
    );

  ---------------------------------------------------------------------------
  -- sys_clk generator
  ---------------------------------------------------------------------------
  clk_gen : process
  begin
    while true loop
      sys_clk <= '0';
      wait for C_SYSCLK_PERIOD/2;
      sys_clk <= '1';
      wait for C_SYSCLK_PERIOD/2;
    end loop;
  end process;

  ---------------------------------------------------------------------------
  -- Stimulus
  ---------------------------------------------------------------------------
  stim : process

    procedure send_rx_byte(constant b : std_logic_vector(7 downto 0)) is
    begin
      rx_byte  <= b;
      rx_valid <= '1';
      wait until rising_edge(sys_clk);
      rx_valid <= '0';
      wait until rising_edge(sys_clk);  -- small gap
    end procedure;

    variable error_count : integer := 0;
    variable tx_buf      : std_logic_vector(31 downto 0);
    variable i           : integer;
    variable wr_seen     : boolean;

  begin
    -------------------------------------------------------------------------
    -- Reset
    -------------------------------------------------------------------------
    sys_rst_n <= '0';
    rx_valid  <= '0';
    tx_ready  <= '0';
    wait for 5*C_SYSCLK_PERIOD;
    wait until rising_edge(sys_clk);
    sys_rst_n <= '1';
    wait for 2*C_SYSCLK_PERIOD;

    -------------------------------------------------------------------------
    -- Test 1: WRITE transaction
    -- cmd = 0x00 | addr (RW=0), data = 0xDEADBEEF MSB-first
    -------------------------------------------------------------------------
    report "Test 1: WRITE transaction" severity note;

    -- Command byte: RW=0, addr = 0x12
    send_rx_byte(x"12");

    -- Data bytes: 0xDE, 0xAD, 0xBE, 0xEF
    send_rx_byte(x"DE");
    send_rx_byte(x"AD");
    send_rx_byte(x"BE");
    send_rx_byte(x"EF");

    -- Look for reg_wr_en pulse over a small window
    wr_seen := false;
    for i in 0 to 5 loop
      if reg_wr_en = '1' then
        wr_seen := true;
        exit;
      end if;
      wait until rising_edge(sys_clk);
    end loop;

    -- Individual checks so we see exactly what failed
    if not wr_seen then
      error_count := error_count + 1;
      report "Test 1 FAILED: reg_wr_en pulse not seen" severity error;
    end if;

    if reg_addr /= to_unsigned(16#12#, 7) then
      error_count := error_count + 1;
      report "Test 1 FAILED: reg_addr mismatch, got " &
             integer'image(to_integer(reg_addr)) &
             " expected 18" severity error;
    end if;

    if reg_wdata /= x"DEADBEEF" then
      error_count := error_count + 1;
      -- avoid to_integer overflow, just print the vector shape
      report "Test 1 FAILED: reg_wdata mismatch" severity error;
    end if;

    if (error_count = 0) then
      report "Test 1 PASSED" severity note;
    end if;

    -------------------------------------------------------------------------
    -- Test 2: READ transaction
    -- cmd = 0x80 | addr (RW=1), reg_rdata = 0xCAFEBABE
    -- Expect: bytes 0xCA, 0xFE, 0xBA, 0xBE on tx_byte when tx_valid && tx_ready
    -------------------------------------------------------------------------
    report "Test 2: READ transaction" severity note;

    -- preload register data
    reg_rdata <= x"CAFEBABE";

    -- Command byte: RW=1, addr=0x34
    send_rx_byte(x"80" or x"34");  -- 0xB4: bit7=1, addr=0x34

    -- Now drive tx_ready and capture 4 bytes
    tx_ready <= '1';
    tx_buf   := (others => '0');

    for idx in 0 to 3 loop
      -- wait until we see a valid byte
      -- (simple polling, assuming parser will respond quickly)
      for i in 0 to 20 loop
        wait until rising_edge(sys_clk);
        exit when tx_valid = '1';
      end loop;

      case idx is
        when 0 => tx_buf(31 downto 24) := tx_byte;
        when 1 => tx_buf(23 downto 16) := tx_byte;
        when 2 => tx_buf(15 downto 8)  := tx_byte;
        when 3 => tx_buf(7 downto 0)   := tx_byte;
        when others => null;
      end case;
    end loop;

    tx_ready <= '0';
    wait until rising_edge(sys_clk);

    if tx_buf /= x"CAFEBABE" then
      error_count := error_count + 1;
      report "Test 2 FAILED: tx_buf=" &
             integer'image(to_integer(unsigned(tx_buf)))
        severity error;
    else
      report "Test 2 PASSED" severity note;
    end if;

    -------------------------------------------------------------------------
    -- Summary
    -------------------------------------------------------------------------
    if error_count = 0 then
      report "All spi_cmd_parser tests PASSED" severity note;
    else
      report "spi_cmd_parser TESTBENCH FAILED, error_count=" &
             integer'image(error_count)
        severity error;
    end if;

    wait for 10*C_SYSCLK_PERIOD;
    wait;
  end process;

end architecture sim;
