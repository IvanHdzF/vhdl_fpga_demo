library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_slave_phy is
  generic (
    G_CPOL : std_logic := '0'; -- currently unused: mode 0 behavior
    G_CPHA : std_logic := '0'  -- currently unused: mode 0 behavior
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

    -- Byte-stream TX (SCLK domain)
    tx_byte  : in  std_logic_vector(7 downto 0);
    tx_valid : in  std_logic;
    tx_ready : out std_logic
  );
end entity spi_slave_phy;

architecture rtl of spi_slave_phy is

  signal bit_cnt     : unsigned(2 downto 0) := (others => '0'); -- 0..7
  signal shift_in    : std_logic_vector(7 downto 0) := (others => '0');
  signal shift_out   : std_logic_vector(7 downto 0) := (others => '0');
  signal miso_reg    : std_logic := '0';
  signal rx_valid_i  : std_logic := '0';
  signal tx_ready_i  : std_logic := '0';

begin

  miso     <= miso_reg when cs_n = '0' else 'Z';
  rx_valid <= rx_valid_i;
  tx_ready <= tx_ready_i;

  spi_shift_proc : process(sclk)
  begin
    if rising_edge(sclk) then
      -- defaults
      rx_valid_i <= '0';

      if cs_n = '1' then
        ----------------------------------------------------------------
        -- CS deasserted: end of frame, reset counters/flags
        ----------------------------------------------------------------
        bit_cnt    <= (others => '0');
        tx_ready_i <= '0';
        -- shift_in is *not* cleared: last byte stays visible on rx_byte

      else
        ----------------------------------------------------------------
        -- CS active: normal SPI operation
        ----------------------------------------------------------------
        -- RX: MSB-first
        shift_in <= mosi & shift_in(7 downto 1);

        if bit_cnt = "111" then
          bit_cnt    <= (others => '0');
          rx_valid_i <= '1';
        else
          bit_cnt <= bit_cnt + 1;
        end if;

        -- TX: MSB-first
        if bit_cnt = "000" then
          -- Request a new byte at start of each byte
          tx_ready_i <= '1';
          if tx_valid = '1' then
            shift_out  <= tx_byte;
            miso_reg   <= tx_byte(7);
            tx_ready_i <= '0';
          end if;
        else
          miso_reg  <= shift_out(6);
          shift_out <= shift_out(6 downto 0) & '0';
        end if;
      end if;
    end if;
  end process;

  rx_byte <= shift_in;

end architecture rtl;
