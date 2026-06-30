library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cpu65816_core is
    port (
        nres : in std_logic;
        phi2 : in std_logic;
        rdy  : in std_logic;

        A   : out std_logic_vector(15 downto 0);
        D   : inout std_logic_vector(7 downto 0);
        vda : out std_logic;
        vpa : out std_logic;
        rwb : out std_logic;
        vpb : out std_logic;
        e   : out std_logic;
        mlb : out std_logic
    );
end entity;

architecture behavioral of cpu65816_core is
    type t_state is (S_RESET_LO, S_RESET_HI, S_FETCH);
    signal state : t_state := S_RESET_LO;

    signal pc : unsigned(15 downto 0) := (others => '0');
    signal d_in : std_logic_vector(7 downto 0);
begin
	D <= (others => 'Z') when phi2 = '1'
	     	else x"00";	-- bank zero
    d_in <= D;

    rwb <= '1';
    vda <= '1';
    vpa <= '1';
    e   <= '1';
    mlb <= '1';

    process(phi2, nres)
    begin
        if nres = '0' then
            state <= S_RESET_LO;
            pc <= (others => '0');
            A <= x"FFFC";
            vpb <= '0';
        elsif rising_edge(phi2) then
            if rdy = '1' then
                case state is
                    when S_RESET_LO =>
                        pc(7 downto 0) <= unsigned(d_in);
                        A <= x"FFFD";
                        state <= S_RESET_HI;
                        vpb <= '0';

                    when S_RESET_HI =>
                        pc(15 downto 8) <= unsigned(d_in);
                        A <= d_in & std_logic_vector(pc(7 downto 0));
                        state <= S_FETCH;
                        vpb <= '1';

                    when S_FETCH =>
                        A <= std_logic_vector(pc + 1);
                        pc <= pc + 1;
                        vpb <= '1';
                end case;
            end if;
        end if;
    end process;
end architecture;
