----------------------------------------------------------------------------------
-- Company: n/a
-- Engineer: Andre Fachat
-- 
-- Create Date:    21:29:52 06/19/2020 
-- Design Name: 
-- Module Name:    Video - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- This module creates the VGA timing, as background for the video output
-- This timing is completely determined by the VGA mode used
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
use IEEE.STD_LOGIC_unsigned.ALL;
use ieee.numeric_std.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity Canvas is
    Port ( 
	   qclk: in std_logic;		-- Q clock (50MHz)
	   dotclk: in std_logic_vector(3 downto 0);	-- 25Mhz, 1/2, 1/4, 1/8, 1/16

	   v_sync : out  STD_LOGIC;
      h_sync : out  STD_LOGIC;

      v_sync_ext : out  STD_LOGIC;
      h_sync_ext : out  STD_LOGIC;

		h_zero : out std_logic;
		v_zero : out std_logic;
		
    	h_enable : out std_logic;
    	v_enable : out std_logic;

	   x_addr: out std_logic_vector(9 downto 0);	-- x coordinate in pixels
      y_addr: out std_logic_vector(9 downto 0);	-- y coordinate in rasterlines

		x_default_offset: out std_logic_vector(6 downto 0);
		y_default_offset: out natural;
		
	   reset : in std_logic
	   );
	 attribute maxskew: string;
	 attribute maxskew of x_addr : signal is "4 ns";
	 attribute maxdelay: string;
	 attribute maxdelay of x_addr : signal is "4 ns";

end Canvas;

architecture Behavioral of Canvas is


	-- 768x576@60 Hz

	-- all values in pixels
	-- note: cummulative, starting with back porch
	constant h_back_porch: std_logic_vector(9 downto 0) 	:= std_logic_vector(to_unsigned((104  						-8)/8	-1, 10));
	constant h_width: std_logic_vector(9 downto 0)			:= std_logic_vector(to_unsigned((104 + 768				-8)/8	-1, 10));
	constant h_front_porch: std_logic_vector(9 downto 0)	:= std_logic_vector(to_unsigned((104 + 768 + 24			)/8		-1, 10));
	constant h_sync_width: std_logic_vector(9 downto 0)	:= std_logic_vector(to_unsigned((104 + 768 + 24 + 80 	)/8		-1, 10));
	-- zero for pixel coordinates is 120 pixels = 15 chars left of default borders
	-- note: during hsync. may be relevant for raster match
	--constant h_zero_pos: std_logic_vector(9 downto 0)		:= std_logic_vector(to_unsigned((104 + 768 + 24 + 80 - (120-104))-2, 10));
	constant h_zero_pos: std_logic_vector(9 downto 0)		:= std_logic_vector(to_unsigned((104 + 768 + 24 + 80 - (120-104))-2, 10));

	-- all values in rasterlines
	constant v_back_porch: std_logic_vector(9 downto 0)	:=std_logic_vector(to_unsigned(17							-1, 10));
	constant v_width: std_logic_vector(9 downto 0)			:=std_logic_vector(to_unsigned(17 + 576					-1, 10));
	constant v_front_porch: std_logic_vector(9 downto 0)	:=std_logic_vector(to_unsigned(17 + 576 + 1				-1, 10));
	constant v_sync_width: std_logic_vector(9 downto 0)	:=std_logic_vector(to_unsigned(17 + 576 + 1 + 3			-1, 10));
	-- zero for pixel coordinates is 21 rasterlines up of default borders
	-- this is one sprite height and the max we have with 768x576, as all the off-screen is 21 rasterlines only!
	--constant v_zero_pos: std_logic_vector(9 downto 0)		:=std_logic_vector(to_unsigned(17 + 576 + 1 + 3 - (42 - 17), 10));
	constant v_zero_pos: std_logic_vector(9 downto 0)		:=std_logic_vector(to_unsigned(17 + 576 + 1 + 3 - (21 - 17), 10));

	-- runtime counters

	-- states: 00 = back p, 01 = data, 02 = front p, 03 = sync
	signal h_state: std_logic_vector(1 downto 0);	
	signal v_state: std_logic_vector(1 downto 0);

	-- limit reached
	signal h_limit: std_logic;
	signal v_limit: std_logic;

	-- adresses counters
	signal h_cnt: std_logic_vector(9 downto 0);
	signal v_cnt: std_logic_vector(9 downto 0);

	signal h_enable_int: std_logic;
	signal h_zero_int: std_logic;

	signal v_zero_int: std_logic;
	signal v_sync_int: std_logic;
	signal h_sync_int: std_logic;
	
	signal x_addr_int: std_logic_vector(9 downto 0);
	signal y_addr_int: std_logic_vector(9 downto 0);
	
begin

	-- passed through to the actual output; some modes inverted, others not
	-- 640x480 has h negative v negative
	-- 768x576 has h negative v positive
	h_sync_ext <= not( h_sync_int );
	v_sync_ext <= v_sync_int;

	-- in characters
	x_default_offset <= std_logic_vector(to_unsigned(21,7));
	-- in rasterlines
	y_default_offset <= 110;


	-----------------------------------------------------------------------------
	-- horizontal geometry calculation

	h_cnt(2 downto 0) <= dotclk(2 downto 0);
	
	pxl: process(qclk, dotclk, h_cnt, h_limit, reset)
	begin 
		if (reset = '1') then
			h_cnt(9 downto 4) <= (others => '0');
			h_state <= "00";
			h_sync_int <= '0';
			h_enable_int <= '0';
		elsif (falling_edge(qclk) and dotclk(3 downto 0) = "1111") then

			if (h_limit = '1' and h_state = "11") then
				-- sync with slotcnt / memclk by setting to zero on dotclk="1110"
				h_cnt(9 downto 3) <= (others => '0');
			else
				h_cnt(9 downto 3) <= h_cnt(9 downto 3) + 1;
			end if;

			if (h_limit = '1') then
				h_state <= h_state + 1;
			end if;

			h_enable_int <= '0';
			if (h_state = "01") then
				h_enable_int <= '1';
			end if;
			
			h_sync_int <= '0';
			if (h_state = "11") then
				h_sync_int <= '1';
			end if;
		end if;
	end process;

	h_sync <= h_sync_int;
	
	h_limit_p: process(qclk, dotclk, h_cnt, reset)
	begin 
		if (reset = '1') then
			h_limit <= '0';
		elsif (falling_edge(qclk) and dotclk(3 downto 0) = "0111") then

			h_limit <= '0';

			case h_state is
				when "00" =>	-- back porch
					if (h_cnt(9 downto 3) = h_back_porch) then
						h_limit <= '1';
					end if;
				when "01" =>	-- data
					if (h_cnt(9 downto 3) = h_width) then
						h_limit <= '1';
					end if;
				when "10" =>	-- front porch
					if (h_cnt(9 downto 3) = h_front_porch) then
						h_limit <= '1';
					end if;
				when "11" =>	-- sync
					if (h_cnt(9 downto 3) = h_sync_width) then
						h_limit <= '1';
					end if;
				when others =>
			end case;
		end if;
	end process;

	hz: process(qclk, dotclk, h_cnt, reset)
	begin 
		if (reset = '1') then
			h_zero_int <= '0';
		elsif (falling_edge(qclk) and dotclk(2 downto 0) = "110") then
			if (h_cnt = h_zero_pos) then
				h_zero_int <= '1';
			else 
				h_zero_int <= '0';
			end if;
		end if;
		
	end process;

	h_enable <= h_enable_int;
	h_zero <= h_zero_int;
	
	xa: process(qclk, dotclk, h_zero_int, x_addr_int)
	begin
		if (falling_edge(qclk) and dotclk(0) = '1') then
			if (h_zero_int = '1') then
				x_addr_int <= (others => '0');
			else
				x_addr_int <= x_addr_int + 1;
			end if;
		end if;
	end process;
	
	x_addr <= x_addr_int;

	-----------------------------------------------------------------------------
	-- vertical geometry calculation

	rline: process(h_enable_int, dotclk, v_cnt, v_limit, reset)
	begin 
		if (reset = '1') then
			v_cnt <= (others => '0');
			v_state <= "00";
			v_sync_int <= '0';
			v_enable <= '0';
		elsif (falling_edge(h_enable_int)) then

			if (v_limit = '1' and v_state = "11") then
				v_cnt <= (others => '0');
			else
				v_cnt <= v_cnt + 1;
			end if;

			if (v_limit = '1') then
				v_state <= v_state + 1;
			end if;

			v_enable <= '0';
			if (v_state = "01") then
				v_enable <= '1';
			end if;

			v_sync_int <= '0';
			if (v_state = "11") then
				v_sync_int <= '1';
			end if;

			if (v_limit = '1') then
				v_state <= v_state + 1;
			end if;
		end if;
	end process;

	v_sync <= v_sync_int;


	v_limit_p: process(h_enable_int, v_cnt, reset)
	begin 
		if (reset = '1') then
			v_limit <= '0';
		elsif (rising_edge(h_enable_int)) then

			v_limit <= '0';

			case v_state is
				when "00" =>	-- back porch
					if (v_cnt = v_back_porch) then
						v_limit <= '1';
					end if;
				when "01" =>	-- data
					if (v_cnt = v_width) then
						v_limit <= '1';
					end if;
				when "10" =>	-- front porch
					if (v_cnt = v_front_porch) then
						v_limit <= '1';
					end if;
				when "11" =>	-- sync
					if (v_cnt = v_sync_width) then
						v_limit <= '1';
					end if;
				when others =>
			end case;
			
			if (v_cnt = v_zero_pos) then
				v_zero_int <= '1';
			else 
				v_zero_int <= '0';
			end if;
			
		end if;
	end process;

	v_zero <= v_zero_int;
	
	ya: process(qclk, dotclk, v_zero_int, y_addr_int, h_sync_int)
	begin
		if (rising_edge(h_sync_int)) then
			if (v_zero_int = '1') then
				y_addr_int <= (others => '0');
			else
				y_addr_int <= y_addr_int + 1;
			end if;
		end if;
	end process;
	
	y_addr <= y_addr_int;
	
end Behavioral;

