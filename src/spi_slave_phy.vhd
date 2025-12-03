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

    -- Byte-stream TX (SCLK domain)
    tx_byte  : in  std_logic_vector(7 downto 0);
    tx_valid : in  std_logic;
    tx_ready : out std_logic
  );
end entity spi_slave_phy;

architecture rtl of spi_slave_phy is

  -- RX side
  signal rx_bit_cnt  : unsigned(2 downto 0) := (others => '0');
  signal shift_in    : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_byte_reg : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_valid_i  : std_logic := '0';

  -- TX side (as before)
  signal tx_bit_cnt  : unsigned(2 downto 0) := (others => '0');
  signal tx_byte_reg : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_ready_i  : std_logic := '0';
  signal miso_reg    : std_logic := '0';

begin

  miso     <= miso_reg when cs_n = '0' else 'Z';
  rx_valid <= rx_valid_i;
  tx_ready <= tx_ready_i;
  rx_byte  <= rx_byte_reg;

  --------------------------------------------------------------------
  -- RX: sample MOSI on rising edge (mode 0)
  --------------------------------------------------------------------
  rx_proc : process(sclk)
    variable new_shift : std_logic_vector(7 downto 0);
  begin
    if rising_edge(sclk) then
      rx_valid_i <= '0';

      if cs_n = '1' then
        rx_bit_cnt <= (others => '0');
      else
        -- MSB-first, shift left, new bit into LSB
        new_shift := shift_in(6 downto 0) & mosi;
        shift_in  <= new_shift;

        if rx_bit_cnt = "111" then
          rx_bit_cnt  <= (others => '0');
          rx_valid_i  <= '1';
          rx_byte_reg <= new_shift;  -- latch the completed byte
        else
          rx_bit_cnt <= rx_bit_cnt + 1;
        end if;
      end if;
    end if;
  end process;

  --------------------------------------------------------------------
  -- TX: update MISO on falling edge (mode 0)
  --------------------------------------------------------------------
  tx_proc : process(sclk)
    variable bit_idx : integer range 0 to 7;
  begin
    if falling_edge(sclk) then

      if cs_n = '1' then
        -- New frame: request a first byte immediately
        tx_bit_cnt <= (others => '0');
        tx_ready_i <= '1';     -- "hey parser, give me a byte"
        miso_reg   <= '0';

      else
        -- Handshake: if we are ready and parser presents a byte, latch it
        if (tx_ready_i = '1') and (tx_valid = '1') then
          tx_byte_reg <= tx_byte;  -- capture new byte
          tx_ready_i  <= '0';      -- got it, not ready again until end of byte
        end if;

        -- Drive current bit (always from the already-latched byte)
        bit_idx  := 7 - to_integer(tx_bit_cnt);
        miso_reg <= tx_byte_reg(bit_idx);

        -- Bit counter and "request next byte" at byte boundary
        if tx_bit_cnt = "111" then
          tx_bit_cnt <= (others => '0');
          tx_ready_i <= '1';      -- finished this byte, ask for the next
        else
          tx_bit_cnt <= tx_bit_cnt + 1;
        end if;
      end if;
    end if;
  end process;


end architecture rtl;
