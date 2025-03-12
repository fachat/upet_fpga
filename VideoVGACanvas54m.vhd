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

	   x_addr: out std_logic_vector(10 downto 0);	-- x coordinate in pixels
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
	-- in characters
	constant x_default_offset_50: std_logic_vector(6 downto 0):= std_logic_vector(to_unsigned(9,7));

	-- all values in pixels
	-- visible window is shifted 8 cycles in front to account for pre-fetch; so we shift sync 8 cycles back
	constant hh_display_50: std_logic_vector(10 downto 0)		:= std_logic_vector(to_unsigned(720				-1, 11));
	constant hh_sync_pos_50: std_logic_vector(10 downto 0)	:= std_logic_vector(to_unsigned(732				+7, 11));
	constant hh_sync_end_50: std_logic_vector(10 downto 0)	:= std_logic_vector(to_unsigned(796 			+7, 11));
	constant hh_total_50: std_logic_vector(10 downto 0)		:= std_logic_vector(to_unsigned(864				-1, 11));
	constant hh_zero_50: std_logic_vector(10 downto 0)			:= std_logic_vector(to_unsigned(820				+7, 11));
	
	-- all values in rasterlines
	constant vv_display_50: std_logic_vector(9 downto 0)		:=std_logic_vector(to_unsigned(576		-1, 10));
	constant vv_sync_pos_50: std_logic_vector(9 downto 0)		:=std_logic_vector(to_unsigned(581		-1, 10));
	constant vv_sync_end_50: std_logic_vector(9 downto 0)		:=std_logic_vector(to_unsigned(586		-1, 10));
	constant vv_total_50: std_logic_vector(9 downto 0)			:=std_logic_vector(to_unsigned(625		-1, 10));
	
	-- zero for pixel coordinates is 88 rasterlines up of default borders
	constant vv_zero_50: std_logic_vector(9 downto 0)			:=std_logic_vector(to_unsigned(608, 10));

	-- in rasterlines
	constant y_default_offset_50: natural := 80; -- 130

	----------------------------------------------------------------------------------------------------------------
	-- 720x480p60
	--
	-- 720x480@60 Hz
	-- 15.7343 kHz 	ModeLine "720x480" 13.50 720 739 801 858 480 488 494 524 -HSync -VSync Interlace 
	-- 31.4685 kHz 	ModeLine "720x480" 27.00 720 736 798 858 480 489 495 525 -HSync -VSync 
	--
	-- all values in pixels
	constant hh_display_60: std_logic_vector(10 downto 0)		:= std_logic_vector(to_unsigned(720				-1, 11));
	constant hh_sync_pos_60: std_logic_vector(10 downto 0)	:= std_logic_vector(to_unsigned(739				+7, 11));
	constant hh_sync_end_60: std_logic_vector(10 downto 0)	:= std_logic_vector(to_unsigned(801 			+7, 11));
	constant hh_total_60: std_logic_vector(10 downto 0)		:= std_logic_vector(to_unsigned(858				-1, 11));
	constant hh_zero_60: std_logic_vector(10 downto 0)			:= std_logic_vector(to_unsigned(824				+7, 11));

	-- in characters
	constant x_default_offset_60: std_logic_vector(6 downto 0):= std_logic_vector(to_unsigned(9,7));

	--	horizonatl timing
	constant hh_display_60_tv: std_logic_vector(10 downto 0)	:= std_logic_vector(to_unsigned(720	*2			-1, 11));
	constant hh_sync_pos_60_tv: std_logic_vector(10 downto 0):= std_logic_vector(to_unsigned(725	*2			+7, 11));
	constant hh_sync_end_60_tv: std_logic_vector(10 downto 0):= std_logic_vector(to_unsigned(850 *2			+7, 11));
	constant hh_total_60_tv: std_logic_vector(10 downto 0)	:= std_logic_vector(to_unsigned(858	*2			-1, 11));
	constant hh_zero_60_tv: std_logic_vector(10 downto 0)		:= std_logic_vector(to_unsigned(824	*2			+7, 11));
	
	-- in rasterlines
	constant vv_display_60: std_logic_vector(9 downto 0)		:=std_logic_vector(to_unsigned(480		-1, 10));
	constant vv_sync_pos_60: std_logic_vector(9 downto 0)		:=std_logic_vector(to_unsigned(489		-1, 10));
	constant vv_sync_end_60: std_logic_vector(9 downto 0)		:=std_logic_vector(to_unsigned(495		-1, 10));
	constant vv_total_60: std_logic_vector(9 downto 0)			:=std_logic_vector(to_unsigned(525		-1, 10));

	-- zero for pixel coordinates is 85 rasterlines up of default borders
	constant vv_zero_60: std_logic_vector(9 downto 0)			:=std_logic_vector(to_unsigned(490, 10));

	-- in rasterlines
	constant y_default_offset_60: natural:= 80;

	----------------------------------------------------------------------------------------------------------------
	-- all values in pixels
	-- note: cummulative, starting with display
	signal hh_display: std_logic_vector(10 downto 0);
	signal hh_sync_pos: std_logic_vector(10 downto 0);
	signal hh_sync_end: std_logic_vector(10 downto 0);
	signal hh_total: std_logic_vector(10 downto 0);
	signal hh_zero: std_logic_vector(10 downto 0);

	signal v_back_porch: std_logic_vector(9 downto 0);
	signal v_width: std_logic_vector(9 downto 0);
	signal v_front_porch: std_logic_vector(9 downto 0);
	signal v_sync_width: std_logic_vector(9 downto 0);
	signal v_zero_pos: std_logic_vector(9 downto 0);

	signal vv_display: std_logic_vector(9 downto 0);
	signal vv_sync_pos: std_logic_vector(9 downto 0);
	signal vv_sync_end: std_logic_vector(9 downto 0);
	signal vv_total: std_logic_vector(9 downto 0);
	signal vv_zero: std_logic_vector(9 downto 0);
	
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
	
	signal x_addr_int: std_logic_vector(10 downto 0);
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

	geo_p: process(mode_60hz, mode_tv) 
	begin
	
		if (mode_60hz = '1') then
			if (mode_tv = '1') then		
				hh_display 			<= hh_display_60_tv;
				hh_sync_pos 		<= hh_sync_pos_60_tv;
				hh_sync_end 		<= hh_sync_end_60_tv;
				hh_total 			<= hh_total_60_tv;
				hh_zero	 			<= hh_zero_60_tv;
			else
				hh_display 			<= hh_display_60;
				hh_sync_pos 		<= hh_sync_pos_60;
				hh_sync_end 		<= hh_sync_end_60;
				hh_total 			<= hh_total_60;
				hh_zero	 			<= hh_zero_60;
			end if;
			vv_display			<= vv_display_60;
			vv_sync_pos			<= vv_sync_pos_60;
			vv_sync_end			<= vv_sync_end_60;
			vv_total				<= vv_total_60;
			vv_zero				<= vv_zero_60;
			x_default_offset_val<= x_default_offset_60;
			y_default_offset_val<= y_default_offset_60;
		else
			if (mode_tv = '1') then
				hh_display 			<= hh_display_60_tv;
				hh_sync_pos 		<= hh_sync_pos_60_tv;
				hh_sync_end 		<= hh_sync_end_60_tv;
				hh_total 			<= hh_total_60_tv;
				hh_zero	 			<= hh_zero_60_tv;
			else
				hh_display 			<= hh_display_50;
				hh_sync_pos 		<= hh_sync_pos_50;
				hh_sync_end 		<= hh_sync_end_50;
				hh_total 			<= hh_total_50;
				hh_zero	 			<= hh_zero_50;
			end if;
			vv_display			<= vv_display_50;
			vv_sync_pos			<= vv_sync_pos_50;
			vv_sync_end			<= vv_sync_end_50;
			vv_total				<= vv_total_50;
			vv_zero				<= vv_zero_50;
			x_default_offset_val<= x_default_offset_50;
			y_default_offset_val<= y_default_offset_50;
		end if;
	end process;

	-----------------------------------------------------------------------------
	-- horizontal geometry calculation

	--h_cnt(2 downto 0) <= dotclk(2 downto 0);
	
	pxl: process(qclk, dotclk, h_cnt, h_limit, h_state, reset)
	begin 
		if (reset = '1') then
			h_cnt <= (others => '0');
			h_state <= "00";
			h_sync_int <= '0';
			h_enable_int <= '0';
		elsif (falling_edge(qclk) and dotclk(0) = '1') then
		
			if (h_zero_int = '0' or dotclk(3 downto 1) = "111") then
					h_cnt <= h_cnt + 1;
			end if;
			
			if (h_limit = '1') then
				if (h_state = "11") then
					h_state <= "00";
					h_cnt <= (others => '0');
				else
					h_state <= h_state + 1;
				end if;
			end if;

		end if;
		
			h_enable_int <= '0';
			if (h_state = "00") then
				h_enable_int <= '1';
			end if;
			
			h_sync_int <= '0';
			if (h_state = "10") then
				h_sync_int <= '1';
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
				when "00" =>	-- visible
					if (h_cnt = hh_display) then
						h_limit <= '1';
					end if;
				when "01" =>	-- front porch
					if (h_cnt = hh_sync_pos) then
						h_limit <= '1';
					end if;
				when "10" =>	-- sync
					if (h_cnt = hh_sync_end) then
						h_limit <= '1';
					end if;
				when "11" =>	-- back porch
					if (h_cnt = hh_total) then
						h_limit <= '1';
					end if;
				when others =>
					null;
			end case;
		end if;
	end process;

	hz: process(qclk, dotclk, h_cnt, reset)
	begin 
		if (reset = '1') then
			h_zero_int <= '0';
		elsif (falling_edge(qclk) and dotclk(0) = '0') then
			if (h_cnt = hh_zero) then
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
			if (v_state = "00") then
				v_enable <= '1';
			end if;

			v_sync_int <= '0';
			if (v_state = "10") then
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
				when "00" =>	-- diaplay
					if ((v_cnt(9 downto 1) = vv_display(9 downto 1))
						and (mode_tv = '1' or v_cnt(0) = vv_display(0))) then
						v_limit <= '1';
					end if;
				when "01" =>	-- back porch
					if ((v_cnt(9 downto 1) = vv_sync_pos(9 downto 1)) 
						and (mode_tv = '1' or v_cnt(0) = vv_sync_pos(0))) then
						v_limit <= '1';
					end if;
				when "10" =>	-- sync
					if ((v_cnt(9 downto 1) = vv_sync_end(9 downto 1)) 
						and (mode_tv = '1' or v_cnt(0) = vv_sync_end(0))) then
						v_limit <= '1';
					end if;
				when "11" =>	-- total
					if ((v_cnt(9 downto 1) = vv_total(9 downto 1)) 
						and (mode_tv = '1' or v_cnt(0) = vv_total(0))) then
						v_limit <= '1';
					end if;
				when others =>
					null;
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

