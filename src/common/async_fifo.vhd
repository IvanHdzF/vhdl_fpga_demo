-- async_fifo.vhd
--
-- Dual-clock (asynchronous) FIFO
--   - Separate write and read clock domains
--   - Gray-coded pointers for CDC
--   - Registered full/empty flags (no combinational loops)
--
-- Assumptions:
--   - g_DEPTH >= 4
--   - g_DEPTH preferably a power of two

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity async_fifo is
  generic (
    g_WIDTH : natural := 8;    -- Data width in bits
    g_DEPTH : natural := 16    -- FIFO depth (prefer power-of-two)
  );
  port (
    --------------------------------------------------------------------
    -- Write interface (SYS clock domain)
    --------------------------------------------------------------------
    wr_clk    : in  std_logic;
    wr_rst_n  : in  std_logic;  -- Active-low reset, synchronous to wr_clk

    wr_en     : in  std_logic;  -- Write request
    wr_data   : in  std_logic_vector(g_WIDTH-1 downto 0);
    wr_full   : out std_logic;  -- FIFO is full (do not write when '1')

    --------------------------------------------------------------------
    -- Read interface (SCLK clock domain)
    --------------------------------------------------------------------
    rd_clk    : in  std_logic;
    rd_rst_n  : in  std_logic;  -- Active-low reset, synchronous to rd_clk

    rd_en     : in  std_logic;  -- Read request
    rd_data   : out std_logic_vector(g_WIDTH-1 downto 0);
    rd_empty  : out std_logic   -- FIFO is empty (do not read when '1')
  );
end entity async_fifo;

architecture rtl of async_fifo is

  --------------------------------------------------------------------------
  -- Utility: ceiling log2
  --------------------------------------------------------------------------
  function clog2(n : natural) return natural is
    variable v : natural := n - 1;
    variable r : natural := 0;
  begin
    while v > 0 loop
      v := v / 2;
      r := r + 1;
    end loop;
    return r;
  end function;

  constant ADDR_WIDTH : natural := clog2(g_DEPTH);

  --------------------------------------------------------------------------
  -- Memory
  --------------------------------------------------------------------------
  type ram_t is array (0 to g_DEPTH-1) of std_logic_vector(g_WIDTH-1 downto 0);
  signal ram : ram_t := (others => (others => '0'));

  --------------------------------------------------------------------------
  -- Binary/Gray pointer conversion
  --------------------------------------------------------------------------
  function bin2gray(b : unsigned) return unsigned is
    variable g : unsigned(b'range);
  begin
    g := b xor ('0' & b(b'high downto 1));
    return g;
  end function;

  function gray2bin(g : unsigned) return unsigned is
    variable b : unsigned(g'range);
  begin
    b(g'high) := g(g'high);
    for i in g'high-1 downto g'low loop
      b(i) := b(i+1) xor g(i);
    end loop;
    return b;
  end function;

  --------------------------------------------------------------------------
  -- Write-domain pointers and synchronizers
  --------------------------------------------------------------------------
  -- Pointer width = ADDR_WIDTH+1 (extra MSB for full detection)
  signal wr_ptr_bin  : unsigned(ADDR_WIDTH downto 0) := (others => '0');
  signal wr_ptr_gray : unsigned(ADDR_WIDTH downto 0) := (others => '0');

  signal rd_ptr_gray_sync1 : unsigned(ADDR_WIDTH downto 0) := (others => '0');
  signal rd_ptr_gray_sync2 : unsigned(ADDR_WIDTH downto 0) := (others => '0');

  signal wr_full_i : std_logic := '0';

  --------------------------------------------------------------------------
  -- Read-domain pointers and synchronizers
  --------------------------------------------------------------------------
  signal rd_ptr_bin  : unsigned(ADDR_WIDTH downto 0) := (others => '0');
  signal rd_ptr_gray : unsigned(ADDR_WIDTH downto 0) := (others => '0');

  signal wr_ptr_gray_sync1 : unsigned(ADDR_WIDTH downto 0) := (others => '0');
  signal wr_ptr_gray_sync2 : unsigned(ADDR_WIDTH downto 0) := (others => '0');

  signal rd_empty_i : std_logic := '1';

begin

  wr_full  <= wr_full_i;
  rd_empty <= rd_empty_i;

  ----------------------------------------------------------------------------
  -- WRITE-SIDE: pointer, memory and full flag (sequential)
  ----------------------------------------------------------------------------
  write_domain : process (wr_clk)
    variable wr_ptr_bin_next  : unsigned(wr_ptr_bin'range);
    variable wr_ptr_gray_next : unsigned(wr_ptr_gray'range);
  begin
    if rising_edge(wr_clk) then
      if wr_rst_n = '0' then
        wr_ptr_bin  <= (others => '0');
        wr_ptr_gray <= (others => '0');
        wr_full_i   <= '0';
      else
        -- default: no increment
        wr_ptr_bin_next := wr_ptr_bin;

        -- write when enabled and not already full
        if (wr_en = '1') and (wr_full_i = '0') then
          ram(to_integer(wr_ptr_bin(ADDR_WIDTH-1 downto 0))) <= wr_data;
          wr_ptr_bin_next := wr_ptr_bin + 1;
        end if;

        wr_ptr_bin  <= wr_ptr_bin_next;
        wr_ptr_gray <= bin2gray(wr_ptr_bin_next);

        -- compute next-full from candidate pointer vs synced read pointer
        wr_ptr_gray_next := bin2gray(wr_ptr_bin_next);

        -- standard async FIFO full detection:
        -- full when next write Gray == read Gray with MSBs inverted
        if (wr_ptr_gray_next(ADDR_WIDTH downto ADDR_WIDTH-1) =
              not rd_ptr_gray_sync2(ADDR_WIDTH downto ADDR_WIDTH-1)) and
           (wr_ptr_gray_next(ADDR_WIDTH-2 downto 0) =
              rd_ptr_gray_sync2(ADDR_WIDTH-2 downto 0)) then
          wr_full_i <= '1';
        else
          wr_full_i <= '0';
        end if;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- WRITE-SIDE: synchronize read pointer Gray into write domain
  ----------------------------------------------------------------------------
  sync_rd_to_wr : process (wr_clk)
  begin
    if rising_edge(wr_clk) then
      if wr_rst_n = '0' then
        rd_ptr_gray_sync1 <= (others => '0');
        rd_ptr_gray_sync2 <= (others => '0');
      else
        rd_ptr_gray_sync1 <= rd_ptr_gray;
        rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- READ-SIDE: pointer, data and empty flag (sequential)
  ----------------------------------------------------------------------------
    read_domain : process (rd_clk)
    variable rd_ptr_bin_next  : unsigned(rd_ptr_bin'range);
    variable rd_ptr_gray_next : unsigned(rd_ptr_gray'range);
    begin
    if rising_edge(rd_clk) then
        if rd_rst_n = '0' then
        rd_ptr_bin  <= (others => '0');
        rd_ptr_gray <= (others => '0');
        rd_empty_i  <= '1';
        -- rd_data reset no longer needed here
        else
        rd_ptr_bin_next := rd_ptr_bin;

        -- advance pointer only when read & not empty
        if (rd_en = '1') and (rd_empty_i = '0') then
            rd_ptr_bin_next := rd_ptr_bin + 1;
        end if;

        rd_ptr_bin       <= rd_ptr_bin_next;
        rd_ptr_gray_next := bin2gray(rd_ptr_bin_next);
        rd_ptr_gray      <= rd_ptr_gray_next;

        -- EMPTY when updated read Gray equals synchronized write Gray
        if rd_ptr_gray_next = wr_ptr_gray_sync2 then
            rd_empty_i <= '1';
        else
            rd_empty_i <= '0';
        end if;
        end if;
    end if;
    end process;

  ----------------------------------------------------------------------------
  -- READ-SIDE: synchronize write pointer Gray into read domain
  ----------------------------------------------------------------------------
  sync_wr_to_rd : process (rd_clk)
  begin
    if rising_edge(rd_clk) then
      if rd_rst_n = '0' then
        wr_ptr_gray_sync1 <= (others => '0');
        wr_ptr_gray_sync2 <= (others => '0');
      else
        wr_ptr_gray_sync1 <= wr_ptr_gray;
        wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
      end if;
    end if;
  end process;

  rd_data <= ram(to_integer(rd_ptr_bin(ADDR_WIDTH-1 downto 0)));

  
end architecture rtl;
