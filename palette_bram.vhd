----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    22:32:19 08/11/2024 
-- Design Name: 
-- Module Name:    palette_bram - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

-- from https://cse.usf.edu/~haozheng/teach/cda4253/doc/xst-vhdl-ram.pdf
-- page 228f

--
-- Asymmetric port RAM
-- Port A is 256x8-bit read-and-write (no-change synchronization)
-- Port B is 64x32-bit read-and-write (no-change synchronization)
-- Compact description with a for-loop statement
--
-- Download: http://www.xilinx.com/txpatches/pub/documentation/misc/xstug_examples.zip
-- File: HDL_Coding_Techniques/rams/asymmetric_ram_2d.vhd
--

entity palette_bram is

	generic (
		WIDTHA : integer := 8;
		SIZEA : integer := 32;
		ADDRWIDTHA : integer := 5;

		WIDTHB : integer := 8;
		SIZEB : integer := 32;
		ADDRWIDTHB : integer := 5
	);

	port (
		clkA : in std_logic;
		enA : in std_logic;
		weA : in std_logic;
		addrA : in std_logic_vector(ADDRWIDTHA-1 downto 0);
		diA : in std_logic_vector(WIDTHA-1 downto 0);
		doA : out std_logic_vector(WIDTHA-1 downto 0);
		
		clkB : in std_logic;
		enB : in std_logic;
		weB : in std_logic;
		addrB : in std_logic_vector(ADDRWIDTHB-1 downto 0);
		diB : in std_logic_vector(WIDTHB-1 downto 0);
		doB : out std_logic_vector(WIDTHB-1 downto 0)
	);

end palette_bram;

architecture Behavioral of palette_bram is

	function max(L, R: INTEGER) return INTEGER is
	begin
		if L > R then
			return L;
		else
			return R;
		end if;
	end;
	
	function min(L, R: INTEGER) return INTEGER is
	begin
		if L < R then
			return L;
		else
			return R;
		end if;
	end;
	
	function log2 (val: natural) return natural is
		variable res : natural;
	begin
		for i in 30 downto 0 loop
			if (val >= (2**i)) then
				res := i;
				exit;
			end if;
		end loop;
		return res;
	end function log2;
	
	constant minWIDTH : integer := min(WIDTHA,WIDTHB);
	constant maxWIDTH : integer := max(WIDTHA,WIDTHB);
	constant maxSIZE : integer := max(SIZEA,SIZEB);
	constant RATIO : integer := maxWIDTH / minWIDTH;
	
	type ramType is array (0 to maxSIZE-1) of std_logic_vector(minWIDTH-1 downto 0);
	
	--shared variable ram : ramType := (others => (others => '0'));
	shared variable ram : ramType := (
			-- with a 6 bit colour palette the relevant bits 
			-- are RRxGGxBB 
			-- primary palette
			"00000000",	-- "0000" - "00/00/00" black
			"01001001",	-- "0001" - "01/01/01" dark grey
			"00000010",	-- "0010" - "00/00/10" dark blue
			"01001011",	-- "0011" - "01/01/11" light blue
			--palette(4) <= "00010000";	-- "0100" - "00/10/00" dark green
			"00001000",	-- "0100" - "00/10/00" dark green
			"01011001",	-- "0101" - "01/11/01" light green
			--palette(5) <= "00011000";	-- "0101" - "01/11/01" light green
			--palette(6) <= "00010010";	-- "0110" - "00/10/10" dark cyan
			"00001001",	-- "0110" - "00/10/10" dark cyan
			"01011011",	-- "0111" - "01/11/11" light cyan
			--palette(8) <= "10000000";	-- "1000" - "10/00/00" dark red
			"01000000",	-- "1000" - "10/00/00" dark red
			--palette(9) <= "11001001";	-- "1001" - "11/01/01" light red
			"11000000",	-- "1001" - "11/01/01" light red
			--palette(10) <= "10000010";	-- "1010" - "10/00/10" dark purple
			"01000001",	-- "1010" - "10/00/10" dark purple
			"11001011",	-- "1011" - "11/01/11" light purple
			--palette(12) <= "10010000";	-- "1100" - "10/10/00" brown? dark yellow?
			"01001000",	-- "1100" - "10/10/00" brown? dark yellow?
			"11011001",	-- "1101" - "11/11/01" light yellow
			"10010010",	-- "1110" - "10/10/10" light grey
			"11111111",	-- "1111" - "11/11/11" white		
			-- secondary palette
			"00000000",	-- "0000" - "00/00/00" black
			"01001001",	-- "0001" - "01/01/01" dark grey
			"00000010",	-- "0010" - "00/00/10" dark blue
			"01001011",	-- "0011" - "01/01/11" light blue
			--palette(4) <= "00010000";	-- "0100" - "00/10/00" dark green
			"00001000",	-- "0100" - "00/10/00" dark green
			"01011001",	-- "0101" - "01/11/01" light green
			--palette(5) <= "00011000";	-- "0101" - "01/11/01" light green
			--palette(6) <= "00010010";	-- "0110" - "00/10/10" dark cyan
			"00001001",	-- "0110" - "00/10/10" dark cyan
			"01011011",	-- "0111" - "01/11/11" light cyan
			--palette(8) <= "10000000";	-- "1000" - "10/00/00" dark red
			"01000000",	-- "1000" - "10/00/00" dark red
			--palette(9) <= "11001001";	-- "1001" - "11/01/01" light red
			"11000000",	-- "1001" - "11/01/01" light red
			--palette(10) <= "10000010";	-- "1010" - "10/00/10" dark purple
			"01000001",	-- "1010" - "10/00/10" dark purple
			"11001011",	-- "1011" - "11/01/11" light purple
			--palette(12) <= "10010000";	-- "1100" - "10/10/00" brown? dark yellow?
			"01001000",	-- "1100" - "10/10/00" brown? dark yellow?
			"11011001",	-- "1101" - "11/11/01" light yellow
			"10010010",	-- "1110" - "10/10/10" light grey
			"11111111"	-- "1111" - "11/11/11" white		
			);
	
	signal readA : std_logic_vector(WIDTHA-1 downto 0):= (others => '0');
	signal readB : std_logic_vector(WIDTHB-1 downto 0):= (others => '0');
	signal regA : std_logic_vector(WIDTHA-1 downto 0):= (others => '0');
	signal regB : std_logic_vector(WIDTHB-1 downto 0):= (others => '0');

begin
	process (clkA)
	begin
		if rising_edge(clkA) then
			if enA = '1' then
				if weA = '1' then
					ram(conv_integer(addrA)) := diA;
				else
					readA <= ram(conv_integer(addrA));
				end if;
			end if;
			regA <= readA;
		end if;
	end process;
		
	process (clkB)
	begin
		if rising_edge(clkB) then
			if enB = '1' then
				for i in 0 to RATIO-1 loop
					if weB = '1' then
						ram(conv_integer(addrB & conv_std_logic_vector(i,log2(RATIO))))
							:= diB((i+1)*minWIDTH-1 downto i*minWIDTH);
					else
						readB((i+1)*minWIDTH-1 downto i*minWIDTH)
							<= ram(conv_integer(addrB & conv_std_logic_vector(i,log2(RATIO))));
					end if;
				end loop;
			end if;
			regB <= readB;
		end if;
	end process;
	
	doA <= regA;
	doB <= regB;
	
end behavioral;

