-- tb_async_fifo.vhd
--
-- Testbench for async_fifo
--  - Writes a sequence of bytes on wr_clk domain
--  - Reads them back on rd_clk domain (different frequency)
--  - Checks ordering and basic full/empty behavior

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_async_fifo is
end entity;

architecture sim of tb_async_fifo is

  -- DUT configuration
  constant C_WIDTH      : natural := 8;
  constant C_DEPTH : natural := 8;
  constant C_NUM_WORDS : natural := 16;


  -- Clocks and resets
  signal wr_clk   : std_logic := '0';
  signal rd_clk   : std_logic := '0';
  signal wr_rst_n : std_logic := '0';
  signal rd_rst_n : std_logic := '0';

  -- Write interface
  signal wr_en    : std_logic := '0';
  signal wr_data  : std_logic_vector(C_WIDTH-1 downto 0) := (others => '0');
  signal wr_full  : std_logic;

  -- Read interface
  signal rd_en    : std_logic := '0';
  signal rd_data  : std_logic_vector(C_WIDTH-1 downto 0);
  signal rd_empty : std_logic;

begin

  ---------------------------------------------------------------------------
  -- DUT instantiation
  ---------------------------------------------------------------------------
  dut : entity work.async_fifo
    generic map (
      g_WIDTH => C_WIDTH,
      g_DEPTH => C_DEPTH
    )
    port map (
      wr_clk   => wr_clk,
      wr_rst_n => wr_rst_n,
      wr_en    => wr_en,
      wr_data  => wr_data,
      wr_full  => wr_full,
      rd_clk   => rd_clk,
      rd_rst_n => rd_rst_n,
      rd_en    => rd_en,
      rd_data  => rd_data,
      rd_empty => rd_empty
    );

  ---------------------------------------------------------------------------
  -- Clock generation
  --   wr_clk: 100 MHz (10 ns period)
  --   rd_clk: ~71 MHz (14 ns period) to create true async behavior
  ---------------------------------------------------------------------------
  wr_clk_process : process
  begin
    wr_clk <= '0';
    wait for 5 ns;
    wr_clk <= '1';
    wait for 5 ns;
  end process;

  rd_clk_process : process
  begin
    rd_clk <= '0';
    wait for 7 ns;
    rd_clk <= '1';
    wait for 7 ns;
  end process;

  ---------------------------------------------------------------------------
  -- Reset generation
  ---------------------------------------------------------------------------
  reset_process : process
  begin
    wr_rst_n <= '0';
    rd_rst_n <= '0';
    wait for 40 ns;
    wr_rst_n <= '1';
    rd_rst_n <= '1';
    wait;
  end process;

  ---------------------------------------------------------------------------
  -- Writer process (SYS domain)
  --   Writes C_NUM_WORDS bytes: 0,1,2,... to the FIFO.
  --   Respects wr_full and only asserts wr_en when FIFO is not full.
  ---------------------------------------------------------------------------
  writer_process : process
    variable i          : integer := 0;
    variable full_seen  : boolean := false;
  begin
    -- initial values
    wr_en   <= '0';
    wr_data <= (others => '0');

    -- wait for reset deassertion
    wait until wr_rst_n = '1';
    wait for 20 ns;

    for i in 0 to C_NUM_WORDS - 1 loop
      -- wait for a rising edge where FIFO is not full
      wait until rising_edge(wr_clk);
      while wr_full = '1' loop
        full_seen := true;
        wait until rising_edge(wr_clk);
      end loop;

      -- drive data and wr_en for one wr_clk cycle
      wr_data <= std_logic_vector(to_unsigned(i, C_WIDTH));
      wr_en   <= '1';
      wait until rising_edge(wr_clk);
      wr_en   <= '0';
    end loop;

    -- simple check: full flag must have been seen at least once
    assert full_seen
      report "Writer did not observe wr_full='1' during test (depth not exercised?)"
      severity note;

    wait;
  end process;

  ---------------------------------------------------------------------------
  -- Reader process (SCLK domain)
  --   After some delay, starts reading data whenever FIFO is not empty.
  --   For each successful read, checks that rd_data matches the expected
  --   sequence 0,1,2,... written by the writer.
  ---------------------------------------------------------------------------
    reader_process : process
    variable j : integer := 0;
    begin
    rd_en <= '0';

    -- Wait for reset release
    wait until rd_rst_n = '1';

    -- Let writer push some data
    wait for 200 ns;

    for j in 0 to C_NUM_WORDS - 1 loop

        ------------------------------------------------------------------
        -- 1) Wait for a rising edge where FIFO reports non-empty (cycle A)
        ------------------------------------------------------------------
        loop
        wait until rising_edge(rd_clk);
        exit when rd_empty = '0';
        end loop;

        ------------------------------------------------------------------
        -- 2) Next cycle: assert rd_en (cycle B)
        --    Internally, rd_empty_i used at this edge is the A-cycle value
        ------------------------------------------------------------------
        wait until rising_edge(rd_clk);  -- cycle B
        rd_en <= '1';

        ------------------------------------------------------------------
        -- 3) One more cycle: read completes (cycle C), then check data
        ------------------------------------------------------------------
        wait until rising_edge(rd_clk);  -- cycle C
        rd_en <= '0';

        -- allow FIFO process to update rd_data in this delta
        wait for 0 ns;

        assert rd_data = std_logic_vector(to_unsigned(j, C_WIDTH))
        report "Data mismatch at read index " & integer'image(j) &
                ". Expected " & integer'image(j) &
                ", got " & integer'image(to_integer(unsigned(rd_data)))
        severity error;
    end loop;

    -- Finally wait until FIFO goes empty
    wait until rd_empty = '1';

    report "async_fifo_tb completed successfully!!" severity note;
    end process;

end architecture sim;
