library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_tx_cdc is
  port (
    -- SYS domain (parser)
    sys_clk       : in  std_logic;
    sys_rst_n     : in  std_logic;
    par_tx_byte   : in  std_logic_vector(7 downto 0);
    par_tx_valid  : in  std_logic;
    par_tx_ready  : out std_logic;

    -- SCLK domain (PHY)
    sclk          : in  std_logic;
    phy_tx_ready  : in  std_logic;                     -- from PHY (idle/not busy)
    phy_tx_byte   : out std_logic_vector(7 downto 0);  -- to PHY
    phy_tx_valid  : out std_logic                      -- to PHY
  );
end entity;

architecture rtl of spi_tx_cdc is

  --------------------------------------------------------------------------
  -- FIFO interface signals
  --------------------------------------------------------------------------
  signal fifo_wr_en    : std_logic;
  signal fifo_wr_full  : std_logic;
  signal fifo_rd_en    : std_logic;
  signal fifo_rd_empty : std_logic;
  signal fifo_din      : std_logic_vector(7 downto 0);
  signal fifo_dout     : std_logic_vector(7 downto 0);

  -- internal version of ready on SYS side (can't read out port directly)
  signal par_tx_ready_i : std_logic;

  --------------------------------------------------------------------------
  -- Simple FSM in SCLK domain to handle FIFO read latency
  --------------------------------------------------------------------------
  type sclk_state_t is (S_IDLE, S_READ, S_OUT);
  signal sclk_state : sclk_state_t := S_IDLE;

begin

  --------------------------------------------------------------------------
  -- SYS domain → FIFO write side
  --------------------------------------------------------------------------
  fifo_din        <= par_tx_byte;
  par_tx_ready_i  <= not fifo_wr_full;
  par_tx_ready    <= par_tx_ready_i;

  fifo_wr_en      <= par_tx_valid and par_tx_ready_i;

  u_fifo : entity work.async_fifo
    generic map (
      g_WIDTH => 8,
      g_DEPTH => 32              -- same depth as in your TB
    )
    port map (
      -- write side (SYS)
      wr_clk   => sys_clk,
      wr_rst_n => sys_rst_n,
      wr_en    => fifo_wr_en,
      wr_data  => fifo_din,
      wr_full  => fifo_wr_full,

      -- read side (SCLK)
      rd_clk   => sclk,
      rd_rst_n => sys_rst_n,     -- common reset; OK as long as it's async
      rd_en    => fifo_rd_en,
      rd_data  => fifo_dout,
      rd_empty => fifo_rd_empty
    );

  --------------------------------------------------------------------------
  -- SCLK domain → PHY read side
  --
  -- Contract:
  --   - PHY (spi_slave_phy) runs entirely on sclk.
  --   - phy_tx_ready = 1  → PHY is idle, can accept a new byte.
  --   - We must:
  --       1) Pop from FIFO (rd_en),
  --       2) Wait one SCLK, then
  --       3) Present fifo_dout as phy_tx_byte with phy_tx_valid = 1
  --      so PHY can latch it in its falling-edge TX process.
  --------------------------------------------------------------------------
  process (sclk)
  begin
    if rising_edge(sclk) then
      if sys_rst_n = '0' then
        sclk_state   <= S_IDLE;
        fifo_rd_en   <= '0';
        phy_tx_valid <= '0';
        phy_tx_byte  <= (others => '0');

      else
        case sclk_state is

          ----------------------------------------------------------------
          -- S_IDLE: wait for PHY to be idle and FIFO to have data
          ----------------------------------------------------------------
          when S_IDLE =>
            fifo_rd_en   <= '0';
            phy_tx_valid <= '0';

            if (phy_tx_ready = '1') and (fifo_rd_empty = '0') then
              -- request a byte from FIFO; data will be visible as fifo_dout
              -- after this clock edge
              fifo_rd_en <= '1';
              sclk_state <= S_READ;
            end if;

          ----------------------------------------------------------------
          -- S_READ: rd_en was asserted last cycle
          --         rd_data (fifo_dout) is now valid → drive to PHY
          ----------------------------------------------------------------
          when S_READ =>
            fifo_rd_en   <= '0';             -- only a one-cycle pulse
            phy_tx_byte  <= fifo_dout;       -- present byte to PHY
            phy_tx_valid <= '1';             -- mark it valid for this SCLK
            sclk_state   <= S_OUT;

          ----------------------------------------------------------------
          -- S_OUT: deassert valid, then either fetch next byte immediately
          --        (for back-to-back bytes) or go idle
          ----------------------------------------------------------------
          when S_OUT =>
            phy_tx_valid <= '0';

            if (phy_tx_ready = '1') and (fifo_rd_empty = '0') then
              -- PHY already idle again and FIFO still has data:
              -- start next read immediately
              fifo_rd_en <= '1';
              sclk_state <= S_READ;
            else
              fifo_rd_en <= '0';
              sclk_state <= S_IDLE;
            end if;

        end case;
      end if;
    end if;
  end process;

end architecture rtl;
