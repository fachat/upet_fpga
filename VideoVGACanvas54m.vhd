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

		mode_60hz: in std_logic;
		mode_tv: in std_logic;
		
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

	-- https://www.mythtv.org/wiki/Modeline_Database

	-- 720x576@50 Hz
	-- 15.625 kHz 	ModeLine "720x576" 13.50 720 732 795 864 576 580 586 624 -HSync -VSync Interlace 
	-- 31.25 kHz 	ModeLine "720x576" 27.00 720 732 796 864 576 581 586 625 -HSync -VSync 
	
	-- 720x480@60 Hz
	-- 15.7343 kHz 	ModeLine "720x480" 13.50 720 739 801 858 480 488 494 524 -HSync -VSync Interlace 
	-- 31.4685 kHz 	ModeLine "720x480" 27.00 720 736 798 858 480 489 495 525 -HSync -VSync 
	
	----------------------------------------------------------------------------------------------------------------
	-- 720x576p50
	--
	-- 720x576@50 Hz
	-- 15.625 kHz 	ModeLine "720x576" 13.50 720 732 795 864 576 580 586 624 -HSync -VSync Interlace 
	-- 31.25 kHz 	ModeLine "720x576" 27.00 720 732 796 864 576 581 586 625 -HSync -VSync 
	--
	-- all values in pixels
	-- note: cummulative, starting with back porch
	constant h_back_porch_50: std_logic_vector(10 downto 0) 	:= std_logic_vector(to_unsigned(68				-1, 11));
	constant h_width_50: std_logic_vector(10 downto 0)			:= std_logic_vector(to_unsigned(68 + 720		-9, 11));
	constant h_front_porch_50: std_logic_vector(10 downto 0)	:= std_logic_vector(to_unsigned(68 + 732		-9, 11));
	constant h_sync_width_50: std_logic_vector(10 downto 0)	:= std_logic_vector(to_unsigned(68 + 796 		-1, 11));
	-- zero for pixel coordinates is 120 pixels = 15 chars left of default borders
	-- note: during hsync. may be relevant for raster match - must be divisble by 8
	constant h_zero_pos_50: std_logic_vector(10 downto 0)		:= std_logic_vector(to_unsigned(24		-1, 11));
	-- in characters
	constant x_default_offset_50: std_logic_vector(6 downto 0):= std_logic_vector(to_unsigned(8,7));
	
	-- all values in rasterlines
	constant v_back_porch_50: std_logic_vector(9 downto 0)	:=std_logic_vector(to_unsigned(39				-1, 10));
	constant v_width_50: std_logic_vector(9 downto 0)			:=std_logic_vector(to_unsigned(39 + 576		-1, 10));
	constant v_front_porch_50: std_logic_vector(9 downto 0)	:=std_logic_vector(to_unsigned(39 + 581		-1, 10));
	constant v_sync_width_50: std_logic_vector(9 downto 0)	:=std_logic_vector(to_unsigned(39 + 586		-1, 10));
	-- zero for pixel coordinates is 2x21 rasterlines up of default borders (1 sprite, either double height or interlace)
	constant v_zero_pos_50: std_logic_vector(9 downto 0)		:=std_logic_vector(to_unsigned(625 - (42 - 39) -1, 10));
	-- in rasterlines
	constant y_default_offset_50: natural := 42 + (576-400)/2; -- 130

	----------------------------------------------------------------------------------------------------------------
	-- 720x480p60
	--
	-- 720x480@60 Hz
	-- 15.7343 kHz 	ModeLine "720x480" 13.50 720 739 801 858 480 488 494 524 -HSync -VSync Interlace 
	-- 31.4685 kHz 	ModeLine "720x480" 27.00 720 736 798 858 480 489 495 525 -HSync -VSync 
	--
	-- all values in pixels
	-- note: cummulative, starting with back porch
	constant h_back_porch_60: std_logic_vector(10 downto 0) 	:= std_logic_vector(to_unsigned(60			-1, 11));
	constant h_width_60: std_logic_vector(10 downto 0)			:= std_logic_vector(to_unsigned(60 + 720	-9, 11));
	constant h_front_porch_60: std_logic_vector(10 downto 0)	:= std_logic_vector(to_unsigned(60 + 736	-9, 11));
	constant h_sync_width_60: std_logic_vector(10 downto 0)	:= std_logic_vector(to_unsigned(60 + 798	-1, 11));
	-- zero for pixel coordinates is 2x24 pixels left of default borders must be divisible by 8
	constant h_zero_pos_60: std_logic_vector(10 downto 0)		:= std_logic_vector(to_unsigned(16	-1, 11));
	-- in characters
	constant x_default_offset_60: std_logic_vector(6 downto 0):= std_logic_vector(to_unsigned(8,7));
	--
	-- all values in rasterlines
	constant v_back_porch_60: std_logic_vector(9 downto 0)	:=std_logic_vector(to_unsigned(30			-1, 10));
	constant v_width_60: std_logic_vector(9 downto 0)			:=std_logic_vector(to_unsigned(30 + 480	-1, 10));
	constant v_front_porch_60: std_logic_vector(9 downto 0)	:=std_logic_vector(to_unsigned(30 + 489	-1, 10));
	constant v_sync_width_60: std_logic_vector(9 downto 0)	:=std_logic_vector(to_unsigned(30 + 495	-1, 10));
	-- zero for pixel coordinates is 2x21 rasterlines up of default borders (1 sprite, either double height or interlace)
	constant v_zero_pos_60: std_logic_vector(9 downto 0)		:=std_logic_vector(to_unsigned(525 - (42 - 30) -1, 10));
	-- in rasterlines
	constant y_default_offset_60: natural:= 42 + (480-400)/2;

	----------------------------------------------------------------------------------------------------------------
	-- all values in pixels
	-- note: cummulative, starting with back porch
	signal h_back_porch: std_logic_vector(10 downto 0);
	signal h_width: std_logic_vector(10 downto 0);
	signal h_front_porch: std_logic_vector(10 downto 0);
	signal h_sync_width: std_logic_vector(10 downto 0);
	signal h_zero_pos: std_logic_vector(10 downto 0);

	signal v_back_porch: std_logic_vector(9 downto 0);
	signal v_width: std_logic_vector(9 downto 0);
	signal v_front_porch: std_logic_vector(9 downto 0);
	signal v_sync_width: std_logic_vector(9 downto 0);
	signal v_zero_pos: std_logic_vector(9 downto 0);

	signal x_default_offset_val: std_logic_vector(6 downto 0);
	signal y_default_offset_val: natural;

	-- runtime counters

	-- states: 00 = back p, 01 = data, 02 = front p, 03 = sync
	signal h_state: std_logic_vector(1 downto 0);	
	signal v_state: std_logic_vector(1 downto 0);

	-- limit reached
	signal h_limit: std_logic;
	signal v_limit: std_logic;

	-- adresses counters
	signal h_cnt: std_logic_vector(10 downto 0);
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
	v_sync_ext <= not( v_sync_int );

	-- in characters
	x_default_offset <= x_default_offset_val;
	-- in rasterlines
	y_default_offset <= y_default_offset_val;

	-- geometry

	geo_p: process(mode_60hz) 
	begin
	
		if (mode_60hz = '1') then
			if (mode_tv = '1') then
				h_back_porch(10 downto 1) 		<= h_back_porch_60(9 downto 0);
				h_back_porch(0) <= '0';
				h_width(10 downto 1)				<= h_width_60(9 downto 0);
				h_width(0) <= '0';
				h_front_porch(10 downto 1)		<= h_front_porch_60(9 downto 0);
				h_front_porch(0) <= '0';
				h_sync_width(10 downto 1)		<= h_sync_width_60(9 downto 0);
				h_sync_width(0) <= '0';
				h_zero_pos(6 downto 1)			<= h_zero_pos_60(5 downto 0);
			else
				h_back_porch 		<= h_back_porch_60;
				h_width				<= h_width_60;
				h_front_porch		<= h_front_porch_60;
				h_sync_width		<= h_sync_width_60;
				h_zero_pos			<= h_zero_pos_60;
			end if;
			v_back_porch 		<= v_back_porch_60;
			v_width				<= v_width_60;
			v_front_porch		<= v_front_porch_60;
			v_sync_width		<= v_sync_width_60;
			v_zero_pos			<= v_zero_pos_60;
			x_default_offset_val<= x_default_offset_60;
			y_default_offset_val<= y_default_offset_60;
		else
			if (mode_tv = '1') then
				h_back_porch(10 downto 1) 		<= h_back_porch_50(9 downto 0);
				h_back_porch(0) <= '0';
				h_width(10 downto 1)				<= h_width_50(9 downto 0);
				h_width(0) <= '0';
				h_front_porch(10 downto 1)		<= h_front_porch_50(9 downto 0);
				h_front_porch(0) <= '0';
				h_sync_width(10 downto 1)		<= h_sync_width_50(9 downto 0);
				h_sync_width(0) <= '0';
				h_zero_pos(6 downto 1)			<= h_zero_pos_50(5 downto 0);
				h_zero_pos(0) <= '0';
			else
				h_back_porch 		<= h_back_porch_50;
				h_width				<= h_width_50;
				h_front_porch		<= h_front_porch_50;
				h_sync_width		<= h_sync_width_50;
				h_zero_pos			<= h_zero_pos_50;
			end if;
			v_back_porch 		<= v_back_porch_50;
			v_width				<= v_width_50;
			v_front_porch		<= v_front_porch_50;
			v_sync_width		<= v_sync_width_50;
			v_zero_pos			<= v_zero_pos_50;
			x_default_offset_val<= x_default_offset_50;
			y_default_offset_val<= y_default_offset_50;
		end if;
	end process;

	-----------------------------------------------------------------------------
	-- horizontal geometry calculation

	--h_cnt(2 downto 0) <= dotclk(2 downto 0);
	
	pxl: process(qclk, dotclk, h_cnt, h_limit, reset)
	begin 
		if (reset = '1') then
			h_cnt(9 downto 4) <= (others => '0');
			h_state <= "00";
			h_sync_int <= '0';
			h_enable_int <= '0';
		elsif (falling_edge(qclk) and dotclk(0) = '1') then

			if (h_limit = '1') then
				if (h_state = "11") then
					if (dotclk(3 downto 0) = "1111") then
						-- sync with slotcnt / memclk by setting to zero on dotclk="1110"
						h_cnt <= (others => '0');
						h_state <= "00";
					end if;
				else
					h_state <= h_state + 1;
					h_cnt <= h_cnt + 1;
				end if; 
			else
				h_cnt <= h_cnt + 1;
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

	h_sync <= not(h_sync_int);
	
	h_limit_p: process(qclk, dotclk, h_cnt, reset)
	begin 
		if (reset = '1') then
			h_limit <= '0';
		elsif (rising_edge(qclk)) then -- and dotclk(3 downto 0) = "0111") then

			h_limit <= '0';

			case h_state is
				when "00" =>	-- back porch
					if (h_cnt = h_back_porch) then
						h_limit <= '1';
					end if;
				when "01" =>	-- data
					if (h_cnt = h_width) then
						h_limit <= '1';
					end if;
				when "10" =>	-- front porch
					if (h_cnt = h_front_porch) then
						h_limit <= '1';
					end if;
				when "11" =>	-- sync
					if (h_cnt = h_sync_width) then
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
				if (mode_tv = '1') then
					v_cnt <= v_cnt + 2;
				else
					v_cnt <= v_cnt + 1;
				end if;
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

	v_sync <= not(v_sync_int);


	v_limit_p: process(h_enable_int, v_cnt, reset)
	begin 
		if (reset = '1') then
			v_limit <= '0';
		elsif (rising_edge(h_enable_int)) then

			v_limit <= '0';

			case v_state is
				when "00" =>	-- back porch
					if ((v_cnt(9 downto 1) = v_back_porch(9 downto 1))
						and (mode_tv = '1' or v_cnt(0) = v_back_porch(0))) then
						v_limit <= '1';
					end if;
				when "01" =>	-- data
					if ((v_cnt(9 downto 1) = v_width(9 downto 1)) 
						and (mode_tv = '1' or v_cnt(0) = v_width(0))) then
						v_limit <= '1';
					end if;
				when "10" =>	-- front porch
					if ((v_cnt(9 downto 1) = v_front_porch(9 downto 1)) 
						and (mode_tv = '1' or v_cnt(0) = v_front_porch(0))) then
						v_limit <= '1';
					end if;
				when "11" =>	-- sync
					if ((v_cnt(9 downto 1) = v_sync_width(9 downto 1)) 
						and (mode_tv = '1' or v_cnt(0) = v_sync_width(0))) then
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

