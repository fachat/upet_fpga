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

entity HBorder is
		Port (
			qclk: in std_logic;
			dotclk: in std_logic_vector(3 downto 0);
			
			-- one on last pxl before pxl addr should be zeroed
			h_zero: in std_logic;
			
			hsync_pos: in std_logic_vector(6 downto 0);
			slots_per_line: in std_logic_vector(6 downto 0);
			mode_tv: in std_logic;
			h_extborder: in std_logic;
			is_80: in std_logic;

			h_phase0: out std_logic;
			h_phase1: out std_logic;
			h_phase2: out std_logic;
			h_phase3: out std_logic;
			h_phase4: out std_logic;
			
			is_preload: out std_logic;		-- one slot before end of border
			is_border: out std_logic;			
			is_last_vis: out std_logic;
			
			is_shift40: out std_logic;
			is_shift80: out std_logic;
			
			reset : in std_logic
		);

end HBorder;

architecture Behavioral of HBorder is

	-- state
	signal slot_state: std_logic_vector(1 downto 0);
	signal slot_cnt: std_logic_vector(8 downto 0);
	
	-- five phases for fetching a slot, i.e.:
	signal phase0: std_logic;	-- last memclk before first fetch, to request memory fetch
	signal phase1: std_logic;	-- first memclk char
	signal phase2: std_logic;	-- second memclk attrib
	signal phase3: std_logic;	-- third memclk pxl
	signal phase4: std_logic;	-- fourth (depends)
	
	-- how many mem-cycle are in a char on screen (-1)
	-- VGA 80: 4 cycles
	-- VGA 40: 8 cycles
	-- TV  80: 8 cycles
	-- TV  40: 16cycles
	signal slot_len: std_logic_vector(3 downto 0);
	-- count mem-cycles
	signal slot_len_cnt: std_logic_vector(3 downto 0);
	
	signal is_hsync: std_logic;
	signal is_slots: std_logic;
	signal is_slot_len: std_logic;
	
	-- two shifted border signals
	signal is_border_1: std_logic;
	signal is_border_2: std_logic;
	signal is_border_3: std_logic;
	

begin

	-- length of slot (=8 pixel) in memory accesses -1
	slot_len_p: process(mode_tv, is_80)
	begin
		if (mode_tv = '0') then
			if (is_80 = '1') then
				-- 80 cols VGA mode is fastest
				slot_len <= "0011";
			else
				-- 40 col VGA mode
				slot_len <= "0111";
			end if;
		else
			if (is_80 = '1') then
				-- 80 col TV mode
				slot_len <= "0111";
			else
				-- 40 col TV mode
				slot_len <= "1111";
			end if;
		end if;
	end process;
	
	slot_p: process(qclk, dotclk, slot_len, slot_cnt, reset)
	begin
		if (reset = '1') then
			slot_state <= "00";
			slot_cnt <= (others => '0');
			is_last_vis <= '0';
		else
			-- every memclk
			-- output (is_border) is evaluated at falling qclk and dotclk(0)=1
			-- should this be phase shifted?
			if (falling_edge(qclk) and dotclk(1 downto 0) = "11") then
				phase0 <= '0';
				is_preload <= '0';
				is_last_vis <= '0';
				if (h_zero = '1') then
					if (mode_tv = '1') then
						slot_cnt <= "000000000";
					else
						slot_cnt <= "000000100";
					end if;
					slot_state <= "00";
					is_border_1 <= '1';
					is_border_2 <= '1';
					is_border_3 <= '1';
				else
				
					if (is_slot_len = '1') then
						slot_len_cnt <= "0000";
						-- counts number of chars / slots
						slot_cnt <= slot_cnt + 1;
						-- shifted border
						is_border_2 <= is_border_1;
					else
						-- counts memclks per char / slot
						slot_len_cnt <= slot_len_cnt + 1;
					end if;
				
					case (slot_state) is
					when "00" =>
						-- counts number of chars / slots
						-- until horizontal start of raster position is reached
						slot_len_cnt <= "0000";
						slot_cnt <= slot_cnt + 1;
						if (is_hsync = '1') then
							slot_state <= "01";
						end if;
					when "01" =>
						-- sync start of raster with shift / slot phase, so
						-- that first fetch starts immediately
						slot_len_cnt <= "0000";
						if (dotclk(2 downto 0) = "011") then
							phase0 <= '1';
							is_preload <= '1';
							slot_state <= "10";
							slot_cnt <= "000000001";
						end if;
					when "10" =>
						
						if (phase4 = '1') then
							if (is_slots = '1') then
								-- end display after slots to display are reached
								slot_state <= "11";
								-- last char starts shifting out
								if (is_80 = '0' or mode_tv = '1') then
									-- if VGA80, then is_slots is set already on the phase4 of the prev char/slot
									is_border_1 <= '1';
								end if;
								-- reset slot len cnt
								slot_len_cnt <= "0000";
								is_last_vis <= '1';
							else
								-- start display after first full phase set
								is_border_3 <= is_border_1;
								is_border_1 <= '0';
							end if;
						end if;

						if (is_slot_len = '1') then
							if (not(phase4 = '1' and is_slots = '1')) then
								phase0 <= '1';
							end if;
						end if;

					when "11" =>
						if (is_slot_len = '1') then
							is_border_1 <= '1';
						end if;	

					when others =>
						null;
					end case;
				end if;
				
				phase4 <= phase3;
				phase3 <= phase2;
				phase2 <= phase1;
				phase1 <= phase0;
				
			end if;
		end if;
		
	end process;
	
	is_border <= is_border_1 and is_border_2 when h_extborder = '0'
					else is_border_1 or is_border_2 or is_border_3;
	
	h_phase0 <= phase0;
	h_phase1 <= phase1;
	h_phase2 <= phase2;
	h_phase3 <= phase3;
	h_phase4 <= phase4;
	
	slot_px: process(qclk, dotclk, slot_len, slot_cnt, reset)
	begin
		if (reset = '1') then
			is_hsync <= '0';
			is_slots <= '0';
			is_slot_len <= '0';
		else
			if (falling_edge(qclk) and dotclk(1 downto 0) = "01") then
			
				-- count characters
				-- slots_per_line, however, is always in 80col char cells, even in 40 col mode
				is_slots <= '0';
				if (is_80 = '0') then
					if (slot_cnt(5 downto 0) = slots_per_line(6 downto 1)) then
						is_slots <= '1';
					end if;
				else
					if (slot_cnt(6 downto 0) = slots_per_line) then
						is_slots <= '1';
					end if;
				end if;
				
				is_hsync <= '0';
				if (mode_tv = '0') then
						-- VGA40/80
						if ((slot_cnt(8 downto 2) = hsync_pos(6 downto 0))
							and slot_cnt(1 downto 0) = "00")
							then is_hsync <= '1';
						end if;
				else
						-- TV40/80
						if ((slot_cnt(8 downto 3) = hsync_pos(5 downto 0))
							and slot_cnt(2 downto 0) = "000")
							then is_hsync <= '1';
						end if;
				end if;

				is_slot_len <= '0';
				if (slot_len_cnt = slot_len) then
					is_slot_len <= '1';
				end if;
				
			end if;
		end if;
		
	end process;

	---------------------------------------------------------------------------

	is_shift_p: process(is_80, mode_tv, dotclk)
	begin
		--dotclk(0) = '0' and (is_80 = '1' or dotclk(1) = '1')
		if (mode_tv = '0') then
				-- VGA 40 col
				is_shift40 <= dotclk(1);
				-- VGA 80 col
				is_shift80 <= '1';
		else
				-- TV 40 col
				is_shift40 <= dotclk(1) and dotclk(2);
				-- TV 80 col
				is_shift80 <= dotclk(1);
		end if;
	end process;

end Behavioral;

