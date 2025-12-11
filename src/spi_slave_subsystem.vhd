library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_slave_subsystem is
  port (
    -- SPI pins (slave)
    sclk    : in  std_logic;
    cs_n    : in  std_logic;
    mosi    : in  std_logic;
    miso    : out std_logic;

    -- system domain
    sys_clk   : in  std_logic;
    sys_rst_n : in  std_logic
  );
end entity;

architecture rtl of spi_slave_subsystem is

  ---------------------------------------------------------------------------
  -- PHY <-> CDC signals (SCLK domain)
  ---------------------------------------------------------------------------
  signal phy_rx_byte  : std_logic_vector(7 downto 0);
  signal phy_rx_valid : std_logic;

  ---------------------------------------------------------------------------
  -- TX FIFO signals (SYS -> SCLK)
  ---------------------------------------------------------------------------
  signal tx_fifo_wr_en    : std_logic;
  signal tx_fifo_wr_full  : std_logic;
  signal tx_fifo_din      : std_logic_vector(7 downto 0);

  signal phy_tx_dout      : std_logic_vector(7 downto 0);  -- FIFO -> PHY
  signal phy_tx_empty     : std_logic;                     -- FIFO empty flag
  signal phy_tx_rd_en     : std_logic;                     -- PHY read strobe

  ---------------------------------------------------------------------------
  -- CDC <-> parser signals (SYS domain)
  ---------------------------------------------------------------------------
  signal par_rx_byte   : std_logic_vector(7 downto 0);
  signal par_rx_valid  : std_logic;

  signal par_tx_byte   : std_logic_vector(7 downto 0);
  signal par_tx_valid  : std_logic;
  signal par_tx_ready  : std_logic;

  ---------------------------------------------------------------------------
  -- parser <-> reg_bank (SYS domain)
  ---------------------------------------------------------------------------
  signal reg_wr_en  : std_logic;
  signal reg_addr   : unsigned(6 downto 0);
  signal reg_wdata  : std_logic_vector(31 downto 0);
  signal reg_rdata  : std_logic_vector(31 downto 0);

begin

  ---------------------------------------------------------------------------
  -- SPI PHY (SCLK domain)
  ---------------------------------------------------------------------------
  u_phy : entity work.spi_slave_phy
    generic map (
      G_CPOL => '0',
      G_CPHA => '0'
    )
    port map (
      sclk     => sclk,
      cs_n     => cs_n,
      mosi     => mosi,
      miso     => miso,

      -- RX byte stream (SCLK domain)
      rx_byte  => phy_rx_byte,
      rx_valid => phy_rx_valid,

      -- TX side: direct FIFO-like interface (SCLK domain)
      tx_dout  => phy_tx_dout,
      tx_empty => phy_tx_empty,
      tx_rd_en => phy_tx_rd_en
    );

  ---------------------------------------------------------------------------
  -- RX CDC: SCLK -> SYS
  -- (Your simplified version that syncs phy_rx_valid into sys_clk
  --  and latches phy_rx_byte on its rising edge.)
  ---------------------------------------------------------------------------
  u_rx_cdc : entity work.spi_rx_cdc
    port map (
      sclk         => sclk,
      phy_rx_byte  => phy_rx_byte,
      phy_rx_valid => phy_rx_valid,
      sys_clk      => sys_clk,
      sys_rst_n    => sys_rst_n,
      par_rx_byte  => par_rx_byte,
      par_rx_valid => par_rx_valid
    );

  ---------------------------------------------------------------------------
  -- TX FIFO: SYS (write) -> SCLK (read)
  ---------------------------------------------------------------------------
  u_tx_fifo : entity work.async_fifo
    generic map (
      g_WIDTH => 8,
      g_DEPTH => 32
    )
    port map (
      -- write side (SYS)
      wr_clk   => sys_clk,
      wr_rst_n => sys_rst_n,
      wr_en    => tx_fifo_wr_en,
      wr_data  => tx_fifo_din,
      wr_full  => tx_fifo_wr_full,

      -- read side (SCLK)
      rd_clk   => sclk,
      rd_rst_n => sys_rst_n,
      rd_en    => phy_tx_rd_en,   -- PHY decides when to consume a byte
      rd_data  => phy_tx_dout,    -- byte to send
      rd_empty => phy_tx_empty    -- empty flag for PHY
    );

  -- SYS domain: parser -> FIFO write
  tx_fifo_din   <= par_tx_byte;
  par_tx_ready  <= not tx_fifo_wr_full;
  tx_fifo_wr_en <= par_tx_valid and par_tx_ready;

  ---------------------------------------------------------------------------
  -- Command parser (SYS domain)
  ---------------------------------------------------------------------------
  u_parser : entity work.spi_cmd_parser
    generic map (
      G_ADDR_WIDTH => 7,
      G_DATA_WIDTH => 32
    )
    port map (
      sys_clk   => sys_clk,
      sys_rst_n => sys_rst_n,
      rx_byte   => par_rx_byte,
      rx_valid  => par_rx_valid,
      tx_byte   => par_tx_byte,
      tx_valid  => par_tx_valid,
      tx_ready  => par_tx_ready,
      reg_wr_en => reg_wr_en,
      reg_addr  => reg_addr,
      reg_wdata => reg_wdata,
      reg_rdata => reg_rdata
    );

  ---------------------------------------------------------------------------
  -- Register bank (SYS domain)
  ---------------------------------------------------------------------------
  u_reg_bank : entity work.reg_bank
    generic map (
      G_ADDR_WIDTH => 7,
      G_DATA_WIDTH => 32
    )
    port map (
      clk   => sys_clk,
      rst_n => sys_rst_n,
      wr_en => reg_wr_en,
      addr  => reg_addr,
      wdata => reg_wdata,
      rdata => reg_rdata
    );

end architecture rtl;
