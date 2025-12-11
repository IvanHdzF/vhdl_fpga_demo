library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_slave_phy is
  generic (
    G_CPOL : std_logic := '0'; -- mode 0 only for now
    G_CPHA : std_logic := '0'
  );
  port (
    -- SPI pins (slave)
    sclk    : in  std_logic;
    cs_n    : in  std_logic;
    mosi    : in  std_logic;
    miso    : out std_logic;

    -- Byte-stream RX (SCLK domain)
    rx_byte  : out std_logic_vector(7 downto 0);
    rx_valid : out std_logic;

    -- TX: FIFO-like interface (SCLK domain)
    tx_dout  : in  std_logic_vector(7 downto 0);  -- data from FIFO
    tx_empty : in  std_logic;                     -- FIFO empty flag
    tx_rd_en : out std_logic                      -- pulse: consume one byte
  );
end entity spi_slave_phy;

architecture rtl of spi_slave_phy is

  --------------------------------------------------------------------
  -- RX side
  --------------------------------------------------------------------
  signal rx_bit_cnt  : unsigned(2 downto 0) := (others => '0');
  signal shift_in    : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_byte_reg : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_valid_i  : std_logic := '0';

  --------------------------------------------------------------------
  -- TX side
  --------------------------------------------------------------------
  signal tx_shift_reg : std_logic_vector(7 downto 0) := (others => '0');
  signal miso_reg     : std_logic := '0';

begin

  --------------------------------------------------------------------
  -- Outputs
  --------------------------------------------------------------------
  miso     <= miso_reg when cs_n = '0' else 'Z';
  rx_valid <= rx_valid_i;
  rx_byte  <= rx_byte_reg;

  --------------------------------------------------------------------
  -- RX: sample MOSI on rising edge (mode 0)
  -- rx_bit_cnt is the *global* bit index (0..7) for this byte
  --------------------------------------------------------------------
  rx_proc : process(sclk)
    variable new_shift : std_logic_vector(7 downto 0);
  begin
    if rising_edge(sclk) then
      rx_valid_i <= '0';

      if cs_n = '1' then
        rx_bit_cnt <= (others => '0');
        shift_in   <= (others => '0');
      else
        -- MSB-first, shift left, new bit enters LSB
        new_shift := shift_in(6 downto 0) & mosi;
        shift_in  <= new_shift;

        if rx_bit_cnt = "111" then
          -- last bit of this byte just arrived
          rx_byte_reg <= new_shift;
          rx_valid_i  <= '1';
          rx_bit_cnt  <= (others => '0');  -- wrap for next byte
        else
          rx_bit_cnt <= rx_bit_cnt + 1;
        end if;
      end if;
    end if;
  end process;

  --------------------------------------------------------------------
  -- TX: mode 0, drive MISO on falling edge
  --
  -- Uses show-ahead FIFO:
  --   - tx_empty = '0' => tx_dout already holds next byte
  --   - tx_rd_en pulses once per byte when we commit to consume it
  --
  -- Bit indexing:
  --   rx_bit_cnt sequence (after each rising edge of bit k):
  --     k=0 → 1, k=1 → 2, ..., k=6 → 7, k=7 → 0
  --   We want to transmit MSB-first (7..0). The mapping is:
  --     if rx_bit_cnt = 0  -> idx = 0  (last bit)
  --     else               -> idx = 8 - rx_bit_cnt
  --   So for physical SPI bit k:
  --     k=0: rx_bit_cnt=1 -> idx=7
  --     k=1: rx_bit_cnt=2 -> idx=6
  --     ...
  --     k=7: rx_bit_cnt=0 -> idx=0
  --------------------------------------------------------------------
  tx_proc : process(sclk)
    variable bit_idx : integer range 0 to 7;
  begin
    if falling_edge(sclk) then
      tx_rd_en <= '0';  -- default

      if cs_n = '1' then
        -- End of frame: reset TX
        tx_shift_reg <= (others => '0');
        miso_reg     <= '0';

      else
        if rx_bit_cnt = "111" then
            -- TRUE byte boundary: decide what comes next
            if tx_empty = '0' then
                -- FIFO has data
                tx_shift_reg <= tx_dout;
                tx_rd_en     <= '1';
            else
                -- FIFO empty → dummy byte
                tx_shift_reg <= (others => '0');
            end if;
        end if;

          -- Currently shifting: choose bit to output
          bit_idx := 7 - to_integer(rx_bit_cnt);

          miso_reg <= tx_shift_reg(bit_idx);
      end if;
    end if;
  end process;

end architecture rtl;
