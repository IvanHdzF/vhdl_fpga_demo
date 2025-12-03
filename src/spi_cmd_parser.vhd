library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_cmd_parser is
  generic (
    G_ADDR_WIDTH : natural := 7;   -- 7 bits from command byte
    G_DATA_WIDTH : natural := 32
  );
  port (
    -- System clock domain
    sys_clk   : in  std_logic;
    sys_rst_n : in  std_logic;

    -- Byte-stream from SPI (already CDC'ed to sys_clk domain)
    rx_byte   : in  std_logic_vector(7 downto 0);
    rx_valid  : in  std_logic;

    -- Byte-stream to SPI (sys_clk domain; will go through CDC to SCLK)
    tx_byte   : out std_logic_vector(7 downto 0);
    tx_valid  : out std_logic;
    tx_ready  : in  std_logic;

    -- Register interface
    reg_wr_en : out std_logic;
    reg_addr  : out unsigned(G_ADDR_WIDTH-1 downto 0);
    reg_wdata : out std_logic_vector(G_DATA_WIDTH-1 downto 0);
    reg_rdata : in  std_logic_vector(G_DATA_WIDTH-1 downto 0)
  );
end entity spi_cmd_parser;

architecture rtl of spi_cmd_parser is

  type t_state is (
    ST_IDLE,
    ST_WRITE_B0,
    ST_WRITE_B1,
    ST_WRITE_B2,
    ST_WRITE_B3,
    ST_READ_PREP,
    ST_READ_B0,
    ST_READ_B1,
    ST_READ_B2,
    ST_READ_B3
  );

  signal state      : t_state := ST_IDLE;

  signal cmd_byte   : std_logic_vector(7 downto 0) := (others => '0');
  signal rw_bit     : std_logic := '0';
  signal addr_reg   : unsigned(G_ADDR_WIDTH-1 downto 0) := (others => '0');

  signal wdata_reg  : std_logic_vector(G_DATA_WIDTH-1 downto 0) := (others => '0');
  signal tx_shift   : std_logic_vector(G_DATA_WIDTH-1 downto 0) := (others => '0');

  signal reg_wr_en_i : std_logic := '0';
  signal tx_valid_i  : std_logic := '0';
  signal tx_byte_i   : std_logic_vector(7 downto 0) := (others => '0');

begin

  reg_wr_en <= reg_wr_en_i;
  tx_valid  <= tx_valid_i;
  tx_byte   <= tx_byte_i;
  reg_addr  <= addr_reg;
  reg_wdata <= wdata_reg;

  --------------------------------------------------------------------
  -- Sequential FSM
  --------------------------------------------------------------------
  process(sys_clk, sys_rst_n)
  begin
    if sys_rst_n = '0' then
      state       <= ST_IDLE;
      cmd_byte    <= (others => '0');
      rw_bit      <= '0';
      addr_reg    <= (others => '0');
      wdata_reg   <= (others => '0');
      tx_shift    <= (others => '0');
      reg_wr_en_i <= '0';
      tx_valid_i  <= '0';
      tx_byte_i   <= (others => '0');

    elsif rising_edge(sys_clk) then
      -- defaults
      reg_wr_en_i <= '0';
      tx_valid_i  <= '0';

      case state is

        ----------------------------------------------------------------
        -- IDLE: wait for command byte
        -- cmd[7] = RW (1=read, 0=write)
        -- cmd[6:0] = addr
        ----------------------------------------------------------------
        when ST_IDLE =>
          if rx_valid = '1' then
            cmd_byte <= rx_byte;
            rw_bit   <= rx_byte(7);
            addr_reg <= unsigned(rx_byte(6 downto 0));
            if rx_byte(7) = '0' then
              -- write transaction: next 4 bytes are data
              state <= ST_WRITE_B0;
            else
              -- read transaction: prepare to send data
              state <= ST_READ_PREP;
            end if;
          end if;

        ----------------------------------------------------------------
        -- WRITE path: collect 4 data bytes MSB-first
        ----------------------------------------------------------------
        when ST_WRITE_B0 =>
          if rx_valid = '1' then
            wdata_reg(31 downto 24) <= rx_byte;
            state <= ST_WRITE_B1;
          end if;

        when ST_WRITE_B1 =>
          if rx_valid = '1' then
            wdata_reg(23 downto 16) <= rx_byte;
            state <= ST_WRITE_B2;
          end if;

        when ST_WRITE_B2 =>
          if rx_valid = '1' then
            wdata_reg(15 downto 8) <= rx_byte;
            state <= ST_WRITE_B3;
          end if;

        when ST_WRITE_B3 =>
          if rx_valid = '1' then
            wdata_reg(7 downto 0) <= rx_byte;
            -- full 32-bit word assembled
            reg_wr_en_i <= '1';  -- 1-cycle write strobe
            state       <= ST_IDLE;
          end if;

        ----------------------------------------------------------------
        -- READ path: load reg_rdata, then send 4 bytes MSB-first
        ----------------------------------------------------------------
        when ST_READ_PREP =>
          tx_shift <= reg_rdata;
          state    <= ST_READ_B0;

        when ST_READ_B0 =>
          if tx_ready = '1' then
            tx_byte_i  <= tx_shift(31 downto 24);
            tx_valid_i <= '1';
            state      <= ST_READ_B1;
          end if;

        when ST_READ_B1 =>
          if tx_ready = '1' then
            tx_byte_i  <= tx_shift(23 downto 16);
            tx_valid_i <= '1';
            state      <= ST_READ_B2;
          end if;

        when ST_READ_B2 =>
          if tx_ready = '1' then
            tx_byte_i  <= tx_shift(15 downto 8);
            tx_valid_i <= '1';
            state      <= ST_READ_B3;
          end if;

        when ST_READ_B3 =>
          if tx_ready = '1' then
            tx_byte_i  <= tx_shift(7 downto 0);
            tx_valid_i <= '1';
            state      <= ST_IDLE;
          end if;

        when others =>
          state <= ST_IDLE;

      end case;
    end if;
  end process;

end architecture rtl;
