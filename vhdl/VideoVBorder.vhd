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
-- Horizontal border timing.
-- creates "is_border" so that border is displayed
-- creates "is_preload" to start char/attrib fetch one char slot before border starts
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

entity VBorder is
		Port (
			h_zero: in std_logic;
			
			v_zero: in std_logic;
			y_addr: in std_logic_vector(9 downto 0);
			vsync_pos: in std_logic_vector(7 downto 0);
			rows_per_char: in std_logic_vector(3 downto 0);
			vis_rows_per_char: in std_logic_vector(3 downto 0);
			clines_per_screen: in std_logic_vector(7 downto 0);
			v_extborder: in std_logic;			
			is_double: in std_logic;
			mode_tv: in std_logic;
			v_shift: in std_logic_vector(3 downto 0);
			alt_rc_cnt: in std_logic_vector(3 downto 0);
			alt_set_rc: in std_logic;
			
			is_border: out std_logic;			
			is_last_row_of_char: out std_logic;
			is_last_row_of_screen: out std_logic;
			is_visible: out std_logic;
			rcline_cnt: out std_logic_vector(3 downto 0);
			rline_cnt0: out std_logic;
			
			reset : in std_logic
		);

end VBorder;

architecture Behavioral of VBorder is

	-- signal defs
	signal v_state: std_logic;
	signal v_next: std_logic;
	
	signal is_border_int: std_logic;
	signal is_last_row_of_char_ext: std_logic;
	
	signal vh_cnt : std_logic_vector (7 downto 0) := (others => '0');
	signal rcline_cnt_ext: std_logic_vector(3 downto 0);
	signal rline_cnt0_int: std_logic;

	signal next_row: std_logic;

	signal is_matchon: std_logic;
	signal is_matchoff: std_logic;
	signal is_nextcr: std_logic;
	
	signal is_vis_start: std_logic;
	signal is_vis_end: std_logic;
begin

	--next_row <= not(rline_cnt0_int) or is_double;
	next_row <= rline_cnt0_int or is_double;
	
	RowCnt: process(h_zero, vh_cnt, reset)
	begin
		if (reset = '1') then
			v_state <= '0';
			vh_cnt <= (others => '0');
		elsif (rising_edge(h_zero)) then
		
			if (v_zero = '1') then
				vh_cnt <= (others => '0');
				v_state <= '0';
			else 
			
				rline_cnt0_int <= not(rline_cnt0_int);
				
				if (v_state = '0') then
				
					if (v_next = '0') then

						vh_cnt <= vh_cnt + 1;
		
					else -- v_next = '1'

						vh_cnt <= (others => '0'); --std_logic_vector(to_unsigned(1,10));

						rcline_cnt_ext <= v_shift;
						
						rline_cnt0_int <= '0';
						v_state <= '1';							
					end if;
					
				else -- v_state = '1'

					if (alt_set_rc = '1') then
						rcline_cnt_ext <= alt_rc_cnt;
					elsif (is_last_row_of_char_ext = '1') then
						rcline_cnt_ext <= (others => '0');
					elsif (next_row = '1') then
						rcline_cnt_ext <= rcline_cnt_ext + 1;
					end if;

					if (is_last_row_of_char_ext = '1') then
						vh_cnt <= vh_cnt + 1;
					end if;
				end if;
			end if;			
		end if;
	end process;

	State: process (vh_cnt, v_state, vsync_pos, h_zero, rcline_cnt_ext, rows_per_char, next_row, v_shift, rline_cnt0_int, is_double, vis_rows_per_char)
	begin		

		if (rcline_cnt_ext = vis_rows_per_char and (rline_cnt0_int = '0' or is_double = '1')) then -- rows_per_char
			is_vis_end <= '1';
		else
			is_vis_end <= '0';
		end if;
		if (rcline_cnt_ext = 0) then -- rows_per_char
			is_vis_start <= '1';
		else
			is_vis_start <= '0';
		end if;
	
		-- end of character (last pixel row)
		if (rcline_cnt_ext = rows_per_char and next_row = '1') then -- rows_per_char
			is_nextcr <= '1';
		else
			is_nextcr <= '0';
		end if;
		-- start border
		if (rcline_cnt_ext = v_shift and (rline_cnt0_int = '0' or is_double = '1')) then -- rows_per_char
			is_matchon <= '1';
		else
			is_matchon <= '0';
		end if;
		-- disable border
		if (rcline_cnt_ext = v_shift) then -- rows_per_char
		--if (rcline_cnt_ext = v_shift and rline_cnt0_int = '0') then -- rows_per_char
			is_matchoff <= '1';
		else
			is_matchoff <= '0';
		end if;
	end process;
	
	State2: process (vh_cnt, v_state, vsync_pos, h_zero)
	begin		
		
		if (falling_edge(h_zero)) then
			v_next <= '0';

			is_last_row_of_char_ext <= '0';

			if (v_zero = '1') then
				is_border_int <= '1';
			end if;
			
			if (v_state = '0' and 
					y_addr(9 downto 8) = "00" and (
					(mode_tv = '1' and y_addr(7) = '0' and y_addr(6 downto 0) = vsync_pos(7 downto 1))
					or (mode_tv = '0' and y_addr(7 downto 0) = vsync_pos))
					) then
				v_next <= '1';				
			end if;
			
			if (v_state = '1') then

				if (is_nextcr = '1') then
					is_last_row_of_char_ext <= '1';
				end if;
				
				if (is_vis_end = '1') then
					is_visible <= '0';
				end if;
				if (is_vis_start = '1') then
					is_visible <= '1';
				end if;
				
				if (v_extborder = '0') then
					if (is_matchoff = '1' and vh_cnt = 0) then
						is_border_int <= '0';
					end if;
					if (is_matchon = '1' and vh_cnt = clines_per_screen) then
						is_border_int <= '1';
					end if;
				else -- v_extborder='1'
					if (is_matchoff = '1' and vh_cnt = 1) then
						is_border_int <= '0';
					end if;
					if (is_matchon = '1' and vh_cnt = clines_per_screen - 1) then
						is_border_int <= '1';	
					end if;							
				end if;
							
			end if;
					
		end if;
	end process;

	rcline_cnt <= rcline_cnt_ext;
	rline_cnt0 <= rline_cnt0_int;
	
	is_last_row_of_char <= is_last_row_of_char_ext; --_2;
	is_last_row_of_screen <= v_next; --is_first_row_of_screen_ext;
	
	is_border <= is_border_int;
	

end Behavioral;

