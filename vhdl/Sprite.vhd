---------f-------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    21:40:17 10/21/2023 
-- Design Name: 
-- Module Name:    Sprite - Behavioral 
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
use IEEE.STD_LOGIC_unsigned.ALL;
use ieee.numeric_std.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity Sprite is
	Port (
		phi2: in std_logic;
		sel: in std_logic;
		rwb: in std_logic;
		regsel: in std_logic_vector(1 downto 0);
		din: in std_logic_vector(7 downto 0);
		dout: out std_logic_vector(7 downto 0);
		
		fgcol: in std_logic_vector(3 downto 0);
		bgcol: in std_logic_vector(3 downto 0);
		mcol1: in std_logic_vector(3 downto 0);
		mcol2: in std_logic_vector(3 downto 0);

		fetch_offset: out std_logic_vector(5 downto 0);	-- 21x3 bytes = 63
		fetch_ce: in std_logic;
		
		qclk: in std_logic;
		dotclk: in std_logic_vector(3 downto 0);
		vdin: in std_logic_vector(7 downto 0);
		h_enable: in std_logic;
		h_zero: in std_logic;
		v_zero: in std_logic;
		x_addr: in std_logic_vector(10 downto 0);
		y_addr: in std_logic_vector(9 downto 0);
		is_double: in std_logic;
		is_interlace: in std_logic;
		is80: in std_logic;
		is_tv: in std_logic;
		is_shift40: in std_logic;
		is_shift80: in std_logic;
		vsync_pos0: in std_logic;
		
		enabled: out std_logic;		-- if sprite data should be read in rasterline
		--active: out std_logic;		-- if sprite pixel out is active (in x/y area)
		ison: out std_logic;			-- if sprite pixel is not background (for collision / prio)
		overraster: out std_logic;		-- if sprite should appear over the raster
		overborder: out std_logic;		-- if sprite should appear over the border
		outbits: out std_logic_vector(4 downto 0); 	-- double bit output, plus alt palette bit
		
		reset: in std_logic
	);

end Sprite;

architecture Behavioral of Sprite is

	signal s_enabled: std_logic;
	signal s_multi: std_logic;
	signal s_overborder: std_logic;
	signal s_overraster: std_logic;
	signal x_expand: std_logic;
	signal y_expand: std_logic;
	signal s_fine: std_logic;
	signal s_palette: std_logic;

	signal x_pos: std_logic_vector(9 downto 0);
	signal y_pos: std_logic_vector(9 downto 0);
	
	signal x_cnt: std_logic_vector(5 downto 0);
	signal y_cnt: std_logic_vector(4 downto 0);
	signal y_sub: std_logic_vector(1 downto 0);
	signal y_sub_end: std_logic_vector(1 downto 0);
	
	signal shiftreg: std_logic_vector(23 downto 0) := "111100101000001010101111";
	signal cur: std_logic_vector(1 downto 0);
	signal is_shift2: std_logic;
	
	signal enabled_int: std_logic;
	signal active_int: std_logic;
	signal ison_int: std_logic;
	
	signal is_y_end: std_logic;
	signal is_y_next: std_logic;
	
	signal pxl_idx: integer range 0 to 23;
	
	signal fetch_offset_int: std_logic_vector(5 downto 0);

	-- https://stackoverflow.com/questions/13584307/reverse-bit-order-on-vhdl	
	function reverse_any_vector (a: in std_logic_vector)
	return std_logic_vector is
	  variable result: std_logic_vector(a'RANGE);
	  alias aa: std_logic_vector(a'REVERSE_RANGE) is a;
	begin
	  for i in aa'RANGE loop
	    result(i) := aa(i);
	  end loop;
	  return result;
	end; -- function reverse_any_vector

begin

	is_shift2 <= is_shift80 when s_fine = '1' else
				is_shift40;

	xcnt_p: process(qclk, h_zero, dotclk, is80, is_shift2)
	begin
		if (h_zero = '1') then
			x_cnt <= (others => '0');
		elsif (falling_edge(qclk) and dotclk(0) = '1' 
				--and (is80 = '1' or dotclk(1) = '1')
				and is_shift2 = '1'
				) then
			if (active_int = '1') then
				x_cnt <= x_cnt + 1;
			end if;
		end if;
	end process;

	-- note: is_tv, not is_double; 
	y_sub_end <= "00" when is_tv = '1' and y_expand = '0' else
					 "01" when y_expand = '0' or is_tv = '1' else
					 "11";	-- y_expand = '1' and is_tv='0'
					 
	enable_p: process (h_enable)
	begin
		if (falling_edge(h_enable)) then
			if (s_enabled = '1' and (
					(is_tv = '0' and y_addr(9 downto 1) = y_pos(9 downto 1) and y_addr(0) = vsync_pos0)
					or (is_tv = '1' and y_addr(9) = '0' and y_addr(8 downto 0) = y_pos(9 downto 1))
					)) then
				enabled_int <= '1';
				y_cnt <= (others => '0');
				y_sub <= "00";
			elsif (enabled_int = '1') then
				if (is_y_next = '1') then
					if (is_y_end = '1') then
						enabled_int <= '0';
					else
						y_cnt <= y_cnt + 1;
						y_sub <= "00";
					end if;
				else
					y_sub <= y_sub + 1;
				end if;
			end if;

			if (v_zero = '1') then -- or fetch_offset_int = "111111") then
				enabled_int <= '0';
			end if;
		end if;
		
		if (rising_edge(h_enable)) then
			is_y_end <= '0';
			if (y_cnt = "10100") then
				is_y_end <= '1';
			end if;
			
			is_y_next <= '0';
			if (y_sub = y_sub_end) then
				is_y_next <= '1';
			end if;
		end if;
	end process;
	
	active_p: process (qclk)
	begin
		if (falling_edge(qclk)) then
			if (enabled_int = '1' and (
				(is_tv = '0' and x_addr(9 downto 0) = x_pos) 
				or (is_tv = '1' and x_addr(10 downto 1) = x_pos and x_addr(0) = '0')
				)) then
				active_int <= '1';
			elsif (x_expand = '0' and x_cnt = "011000") then	-- 24
				active_int <= '0';
			elsif (x_expand = '1' and x_cnt = "110000") then	-- 48
				active_int <= '0';
			end if;
		end if;
	end process;
		
	fetch_offset <= fetch_offset_int;
	
	-- TODO
	fetch_p: process(qclk, fetch_ce, x_expand, shiftreg, v_zero, x_cnt, pxl_idx, enabled_int)
	begin
			
		-- fetch sprite data
		if (enabled_int = '0') then
			fetch_offset_int <= (others => '0');
		elsif (falling_edge(qclk)) then
			if (fetch_ce = '1') then
			
				if (
						y_sub = "00" 
						or (is_interlace = '0' and y_sub = "01")
					) then
				
					fetch_offset_int <= fetch_offset_int + 1;
				
					case (dotclk(3 downto 2)) is
					when "11" =>
						shiftreg(23 downto 16) <= reverse_any_vector(vdin);
					when "10" => 
						shiftreg(15 downto 8) <= reverse_any_vector(vdin);
					when "01" =>
						shiftreg(7 downto 0) <= reverse_any_vector(vdin);
					when others =>
						-- fetch_ce only active during the three values above
					end case;
				end if;
			end if;
		end if;
	end process;
	
	out_p: process(qclk, fetch_ce, x_expand, shiftreg, v_zero, x_cnt, pxl_idx)
	begin
	
		if (x_expand = '0') then
			pxl_idx <= to_integer(unsigned(x_cnt));
		else
			pxl_idx <= to_integer(unsigned(x_cnt(5 downto 1)));
		end if;
		cur(0) <= shiftreg(pxl_idx);
		cur(1) <= shiftreg(pxl_idx + 1);
		
		-- shift out bits
		if (falling_edge(qclk)) then
			if (dotclk(0) = '1' and is_shift2 = '1') then
			
				if (active_int = '1') then
					outbits(4) <= s_palette;
					
					if (s_multi = '0') then
						if (cur(0) = '1') then
							ison_int <= '1';
							outbits(3 downto 0) <= fgcol;
						else
							ison_int <= '0';
							outbits(3 downto 0) <= bgcol;
						end if;
					elsif (x_cnt(0) = '0' and (x_expand = '0' or x_cnt(1) = '0')) then -- multicolour
						case (cur) is
						when "00" =>
							outbits(3 downto 0) <= bgcol;
							ison_int <= '0';
						when "01" => 
							outbits(3 downto 0) <= mcol1;
							ison_int <= '1';
						when "10" => 
							outbits(3 downto 0) <= mcol2;
							ison_int <= '1';
						when "11" => 
							outbits(3 downto 0) <= fgcol;
							ison_int <= '1';
						when others =>
							ison_int <= '0';
						end case;
						
					end if;
				else
					ison_int <= '0';
				end if;
			end if;
		end if;
	end process;
	
	regw_p: process(reset, phi2, sel, regsel,rwb)
	begin
		if (falling_edge(phi2)) then
		 if (reset = '1') then
			x_expand <= '0';
			y_expand <= '0';
			s_enabled <= '0';
			s_overraster <= '0';
			s_overborder <= '0';
			s_multi <= '0';
			s_fine <= '0';
			s_palette <= '0';
			x_pos <= "0000000000";	-- (others => '0');
			y_pos <= "0000000000";	-- (others => '0');
		 elsif(
			sel = '1' and rwb = '0'
			) then
		
			case (regsel) is
			when "00" =>	-- R0
				if (is80 = '1' or s_fine = '1') then
					x_pos(7 downto 0) <= din;
				else
					x_pos(8 downto 1) <= din;
					x_pos(0) <= '0';
				end if;
			when "01" => 	-- R1
				if ((is_interlace = '1' and is_double = '1') or s_fine = '1') then
					y_pos(7 downto 0) <= din;
				else
					y_pos(8 downto 1) <= din;
					y_pos(0) <= '0';
				end if;
			when "10" =>	-- R2
				if (is80 = '1' or s_fine = '1') then
					x_pos(9 downto 8) <= din(1 downto 0);
				else
					x_pos(9) <= din(0);
				end if;
				if ((is_interlace = '1' and is_double = '1') or s_fine = '1') then
					y_pos(9 downto 8) <= din(5 downto 4);
				else
					y_pos(9) <= din(4);
				end if;
			when "11" =>	-- R3
				s_enabled <= din(0);
				x_expand <= din(1);
				y_expand <= din(2);
				s_multi <= din(3);
				s_overraster <= not(din(4));
				s_overborder <= din(5);
				s_fine <= din(6);
				s_palette <= din(7);
			when others =>
				null;
			end case;
 		 end if;
		end if;
	end process;
	
	reqr_p: process(phi2, sel, rwb, regsel, x_pos, y_pos, s_enabled, x_expand, y_expand, s_multi, s_overraster, s_overborder,
			is80, s_fine, is_interlace, is_double, s_palette)
	begin
		dout <= (others => '0');
		
		if (sel = '1' and rwb = '1') then
		
			case regsel is
			when "00" =>	-- R0
				if (is80 = '1' or s_fine = '1') then
					dout <= x_pos(7 downto 0);
				else
					dout <= x_pos(8 downto 1);
				end if;
			when "01" =>	-- R1
				if ((is_interlace = '1' and is_double = '1') or s_fine = '1') then
					dout <= y_pos(7 downto 0);
				else
					dout <= y_pos(8 downto 1);
				end if;
			when "10" =>
				if (is80 = '1' or s_fine = '1') then
					dout(1 downto 0) <= x_pos(9 downto 8);
				else
					dout(0) <= x_pos(9);
				end if;
				if ((is_interlace = '1' and is_double = '1') or s_fine = '1') then
					dout(5 downto 4) <= y_pos(9 downto 8);
				else
					dout(4) <= y_pos(9);
				end if;
			when "11" =>
				dout(0) <= s_enabled;
				dout(1) <= x_expand;
				dout(2) <= y_expand;
				dout(3) <= s_multi;
				dout(4) <= not(s_overraster);
				dout(5) <= s_overborder;
				dout(6) <= s_fine;
				dout(7) <= s_palette;
			when others =>
				null;
			end case;
		end if;
	end process;
	
	overborder <= s_overborder;
	overraster <= s_overraster;
	enabled <= enabled_int;
	--active <= active_int;
	ison <= ison_int;
	
end Behavioral;

