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
  signal regs : t_reg_array := (others => (others => '0'));

begin
  process(clk, rst_n)
  begin
    if rst_n = '0' then
      regs <= (others => (others => '0'));
    elsif rising_edge(clk) then
      if wr_en = '1' then
        regs(to_integer(addr)) <= wdata;
      end if;
    end if;
  end process;

  -- simple async read
  rdata <= regs(to_integer(addr)) when rst_n = '1'
           else (others => '0');

end architecture;
