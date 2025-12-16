library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity reg_bank is
  generic (
    G_ADDR_WIDTH : natural := 7;   -- 128 regs
    G_DATA_WIDTH : natural := 32
  );
  port (
    clk       : in  std_logic;
    rst_n     : in  std_logic;
    wr_en     : in  std_logic;
    addr      : in  unsigned(G_ADDR_WIDTH-1 downto 0);
    wdata     : in  std_logic_vector(G_DATA_WIDTH-1 downto 0);
    rdata     : out std_logic_vector(G_DATA_WIDTH-1 downto 0)
  );
end entity;

architecture rtl of reg_bank is
  constant C_NUM_REGS : integer := 2**G_ADDR_WIDTH;

  type t_reg_array is array (0 to C_NUM_REGS-1) of std_logic_vector(G_DATA_WIDTH-1 downto 0);
  signal regs      : t_reg_array;  -- will map to BRAM
  signal rdata_reg : std_logic_vector(G_DATA_WIDTH-1 downto 0);
begin

  process(clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        -- optional: clear output only; do NOT touch regs
        rdata_reg <= (others => '0');
      else
        -- write port
        if wr_en = '1' then
          regs(to_integer(addr)) <= wdata;
        end if;

        -- synchronous read
        rdata_reg <= regs(to_integer(addr));
      end if;
    end if;
  end process;

  rdata <= rdata_reg;

end architecture;
