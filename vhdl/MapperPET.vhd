----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    13:06:36 06/20/2020 
-- Design Name: 
-- Module Name:    Mapper - Behavioral 
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

entity Mapper is
    Port ( A : in  STD_LOGIC_VECTOR (15 downto 8);
           D : in  STD_LOGIC_VECTOR (7 downto 0);
	   reset : in std_logic;
	   phi2: in std_logic;
	   vpa: in std_logic;
	   vda: in std_logic;
	   vpb: in std_logic;
	   rwb : in std_logic;
	   
	   qclk: in std_logic;
	   
      cfgld : in  STD_LOGIC;	-- set when loading the cfg
	   
	   -- mapped address lines
      RA : out std_logic_vector (19 downto 8);	-- mapped FRAM address
		
	   ffsel: out std_logic;
	   iosel: out std_logic;
		iowin: out std_logic;
	   memsel: out std_logic;	-- bus memory
		
	   vramsel: out std_logic;
	   framsel: out std_logic;
	   
	   boot: in std_logic;
	   lowbank: in std_logic_vector(3 downto 0);
	   hibank: in std_logic_vector(3 downto 0);
	   vidblock: in std_logic_vector(2 downto 0);
	   vsize: in std_logic_vector(1 downto 0);	-- 0=1k, 1=2k, 2=4k, 3=8k
		
   	wp_rom9: in std_logic;
   	wp_romA: in std_logic;
	   wp_romB: in std_logic;
	   wp_romPET: in std_logic;

	   -- bus
	   bus_window_9: in std_logic;
	   bus_window_c: in std_logic;
	   bus_win_9_is_io: in std_logic;
	   bus_win_c_is_io: in std_logic;
		-- page 9/a maps
		page9_map: in std_logic_vector(7 downto 0);
		--pageA_map: in std_logic_vector(7 downto 0);
		
	   -- force bank0 (used in emulation mode)
	   forceb0: in std_logic;
	   -- is screen in bank0?
	   screenb0: in std_logic;
		-- are we in 8296 mode?
		is8296: in std_logic;
		-- don't map colour video at $8800-$8fff (mostly for 8296)
	   isnocolmap: in std_logic;
		
	   dbgout: out std_logic
	);
end Mapper;

architecture Behavioral of Mapper is

	signal cfg_mp: std_logic_vector(7 downto 0) := (others => '0');
	signal bankl: std_logic_vector(7 downto 0);
	
	-- convenience
	signal low64k: std_logic;
	--signal low32k: std_logic;
	signal c8296ram: std_logic;
	signal isblockCtoF: std_logic;
	signal isblock8: std_logic;
	signal isblock9: std_logic;
	signal isblockA: std_logic;
	signal isblockB: std_logic;
	signal isblockC: std_logic;
	signal petio: std_logic;
	signal wprot: std_logic;
	signal screen: std_logic;
	signal iopeek: std_logic;
	signal scrpeek: std_logic;
	signal boota19: std_logic;
	signal avalid: std_logic;
	signal screenwin: std_logic;
	signal buswin: std_logic;
	signal iowin_int: std_logic;
	signal vram9: std_logic;		-- write only to vram under ROM at $9xxx
	
	signal vidblock0: std_logic_vector(2 downto 0);
	signal vidblock1: std_logic_vector(2 downto 0);
	signal vidblock2: std_logic_vector(2 downto 0);
	signal vidblock3: std_logic_vector(2 downto 0);
	
	signal vramsel_int: std_logic;
	signal framsel_int: std_logic;
	signal ffsel_int: std_logic;
	signal memsel_int: std_logic;
	signal iosel_int: std_logic;
	signal iowin_int2: std_logic;
   signal RA_int : std_logic_vector (19 downto 8);
	
	signal page_map: std_logic_vector(7 downto 0);
	signal do_page_map: std_logic;
	
	signal bank: std_logic_vector(7 downto 0);
	
	function To_Std_Logic(L: BOOLEAN) return std_ulogic is
	begin
		if L then
			return('1');
		else
			return('0');
		end if;
	end function To_Std_Logic;
	
begin

	dbgout <= '0';
	
	avalid <= vda or vpa;
	
	vidblock0 <= vidblock;
	vidblock1 <= vidblock + 1;
	vidblock2 <= vidblock + 2;
	vidblock3 <= vidblock + 3;
		
	-----------------------------------------------------------------------
	-- CPU address space analysis
	--

	-- note: simply latching D at rising phi2 does not work,
	-- as in the logical part after the latch, the changing D already
	-- bleeds through, before the result is switched back when bankl is in effect.
	-- Therefore we sample D at half-qclk before the transition of phi2.
	-- This may lead to speed limits in faster designs, but works here.
	BankLatch: process(reset, D, phi2, qclk, forceb0)
	begin
		if (reset ='1') then
			bankl <= (others => '0');
--		elsif (falling_edge(qclk) and phi2='0') then
		elsif (phi2 = '0') then 
			if (forceb0 = '1') then
				bankl <= (others => '0');
			else 
				bankl <= D;
			end if;
		end if;
	end process;
	
	bank <= bankl;
	
	low64k <= '1' when bank = "00000000" else '0';
	--low32k <= '1' when low64k = '1' and A(15) = '0' else '0';
	
	petio <= '1' when A(15 downto 8) = x"E8"
		else '0';
	
	-- the following are used to determine write protect
	-- of ROM area in the upper half of bank 0 and if page9/A maps are to be used
	-- Is evaluated in bank 0 only, so low64k can be ignored here
	isblockCtoF <= '1' when A(15) = '1' and			-- upper half
			A(14) = '1' -- upper 16k
			else '0';
			
	isblock9 <= '1' when A(15 downto 12) = x"9"
			else '0';

	isblockA <= '1' when A(15 downto 12) = x"A"
			else '0';

	isblockB <= '1' when A(15 downto 12) = x"B"
			else '0';
			
	isblockC <= '1' when A(15 downto 12) = x"C"
			else '0';

	screen <= '1' when A(15 downto 13) = "100" and (
					(vsize = "00" and A(12 downto 10) = "000")
					or (vsize = "01" and A(12 downto 11) = "00")
					or (vsize = "10" and A(12) = '0')
					or (vsize = "11" and (A(12) = '0' or rwb = '0'))
					)
			else '0';

	-- 8296 specifics. *peek allow using the IO and screen memory windows despite mapping RAM
	
	iopeek <= '1' when petio = '1' and cfg_mp(6)='1' else '0';
			 
	scrpeek <= '1' when screen = '1' and cfg_mp(5)='1' else '0';

	-- when c8296 is set, upper 16k of bank0 are mapped to RAM (with holes on *peek)
	-- evaluated in bank0 only, so low64k ignored here
	c8296ram <= '1' when cfg_mp(7) = '1'
				and iopeek = '0' 
				and scrpeek = '0'
				else '0';

	-- write should not happen (only evaluated in upper half of bank 0)
	wprot <= '0' when rwb = '1' else			-- read access are ok
			'0' when cfg_mp(7) = '1' and		-- ignore I/O window
				petio = '1' and iopeek = '1' 
				else
			'1' when cfg_mp(7) = '1' and		-- 8296 enabled
				((A(14)='1' and cfg_mp(1)='1')	-- upper 16k write protected
				or (A(14)='0' and cfg_mp(0)='1')) -- lower 16k write protected
				else 
			'0' when cfg_mp(7) = '1' 		-- 8296 RAM but no wp
				else
			'1' when isblockCtoF = '1' and wp_romPET = '1'
				else
			'1' when isblock9 = '1' and wp_rom9 = '1'
				else
			'1' when isblockA = '1' and wp_romA = '1'
				else
			'1' when isblockB = '1' and wp_romB = '1'
				else
			'0';
			 
	-- page 9/A mapping
	do_page_map <= '1' when low64k = '1' 
								and ((isblock9 = '1' and page9_map(7) = '1') )--or (isblockA = '1' and pageA_map(7) = '1'))
								and c8296ram = '0'
				else '0';
				
	page_map <= page9_map; --when isblock9 = '1'
					--else '0'; --pageA_map;
					
	-----------------------------------------------------------------------
	-- physical address space generation
	--
	
	ra_p: process(page_map, do_page_map, A, screenwin, isnocolmap, vidblock0, vidblock1, vidblock2, vidblock3, vram9, rwb, is8296)
	begin
	
		-- map upper address bits (18-15)
		RA_int(19 downto 16) <=	bank(3 downto 0);
		RA_int(15) <= A(15);
		if (low64k = '1') then
			if (A(15) = '0') then
				-- lower 32k in bank 0
				RA_int(18 downto 15) <= lowbank(3 downto 0);
			else
				-- upper 32k in bank 0
				if (c8296ram = '0') then
					if (screenwin = '1') then
						-- video bank
						RA_int(18 downto 15) <= "0001";
					else
						-- mapped fram bank
						RA_int(18 downto 15) <= hibank(3 downto 0);
						-- overwrite for page_map ($9xxx)
						if (do_page_map = '1') then 
							RA_int(18 downto 15) <= page_map(6 downto 3);
						end if;
					end if;
				else
					if (A(14) = '0') then
						-- 8296 map block $8000-$bfff -> $18000-1bfff / 10000-13fff
						RA_int(15) <= cfg_mp(2);
					else
						-- 8296 map block $c000-$ffff -> $1c000-1ffff / 14000-17fff
						RA_int(15) <= cfg_mp(3);
					end if;
					RA_int(18 downto 16) <= "001";
				end if;
			end if;
		end if;
		
	-- banks 2-15
--	RA_int(19) <=	
--			bank(3);
--	
--	RA_int(18 downto 17) <= 
--			lowbank(3 downto 2) when low64k = '1' and A(15) = '0' else
--			page_map(6 downto 5) when do_page_map = '1' else
--			bank(2 downto 1);			-- just map
--	
--	-- bank 0/1
--	RA_int(16) <= 
--			bank(0) when low64k = '0' else  	-- CPU is not in low 64k
--			lowbank(1) when A(15) = '0' else
--			page_map(4) when do_page_map = '1' else
--			'1' 	when c8296ram = '1' 		-- 8296 enabled,
--					and A(15) = '1' 	-- upper half of bank0
--					else  			 
--			'0';
--			
--	-- within bank0
--	RA_int(15) <= 
--			A(15) when low64k = '0' else		-- some upper bank
--			lowbank(0) when A(15) = '0' else-- lower half of bank0
--			page_map(3) when do_page_map = '1' else
--			'1' when c8296ram = '0' else	-- upper half of bank0, no 8296 mapping
--			cfg_mp(3) when A(14) = '1' else	-- 8296 map block $c000-$ffff -> $1c000-1ffff / 14000-17fff
--			cfg_mp(2);			-- 8296 map block $8000-$bfff -> $18000-1bfff / 10000-13fff

	
	-- map screen memory
	--
	-- note that this is only relevant for VRAM, as FRAM has A0-14 connected to the CPU
	-- directly, without mapping.
	--
	-- lower half of 4k screenwin is mapped to char memory $8xxx-Bxxx
	-- upper half of 4k screenwin is mapped into color memory $Cxxx-$Fxxx
	-- Note: vidblock maps in 2k steps; 8 positions are possible, so we
	-- get 16k char RAM at $8000-$BFFF and 16k color RAM at $C000-FFFF
	-- BUT: in 8296 mode, we directly map to video RAM, as the 8296 CRTC
	-- has 8k video RAM, using isnocolmap
	
		-- outside bank 0 -> don't map
		RA_int(14 downto 11) <= A(14 downto 11);
		if (low64k = '1') then
			if (screenb0 = '1') then
				case(A(15 downto 11)) is
				when "10000" =>
					-- $8000-$87ff video map
					-- either 8296 off, or screen peek through
					if (cfg_mp(7) = '0' or cfg_mp(5) = '1') then
						RA_int(14) <= '0';	-- vid ram
						RA_int(13 downto 11) <= vidblock0;
					end if;
				when "10001" =>
					-- $8800-$8fff video map
					-- either 8296 off, or screen peek through
					if (cfg_mp(7) = '0' or cfg_mp(5) = '1') then
						if (isnocolmap = '1') then
							RA_int(14) <= '0';	-- vid ram 
							RA_int(13 downto 11) <= vidblock1;
						else
							RA_int(14) <= '1';	-- col ram
							RA_int(13 downto 11) <= vidblock0;
						end if;
					end if;
				when "10010" =>
					-- $9000-$97ff video map
					if (rwb = '0' and is8296 = '1') then
						RA_int(14) <= '0';	-- vid ram
						RA_int(13 downto 11) <= vidblock2;
					end if;
					if (do_page_map = '1') then
						RA_int(14 downto 12) <= page_map(2 downto 0);
						RA_int(11) <= '0';
					end if;
				when "10011" =>
					-- $9800-$9fff video map
					if (rwb = '0' and is8296 = '1') then
						RA_int(14) <= '0';	-- vid ram
						RA_int(13 downto 11) <= vidblock3;
					end if;
					if (do_page_map = '1') then
						RA_int(14 downto 12) <= page_map(2 downto 0);
						RA_int(11) <= '1';
					end if;
				when others =>
				end case;
			end if;
		end if;
	end process;
	
			
	-- map 1:1, in 2k blocks
	RA_int(10 downto 8) <= 
			A(10 downto 8);
				
	--boota19 <= '1'; --bank(3) xor boot;
	boota19 <= bank(3) xor boot;
	
	
	-- VRAM is second 512k of CPU, plus 4k read/write-window on $008000 ($088000 in VRAM) if screenb0 is set
	screenwin <= '1' when low64k = '1'
				and screen = '1'
				and screenb0 = '1'
				-- either 8296 off, or screen peek through
				and (cfg_mp(7) = '0' or cfg_mp(5) = '1')
			else '0';
	
	vram9 <= '1' when is8296 = '1'		-- 8296 mode
				and low64k = '1'					-- low 64k
				and isblock9 = '1'					-- addresses $9xxx
--				and isblockA = '1'					-- addresses $Axxx - for testing only, as $9xxx has boot code
				and cfg_mp(7) = '0'				-- extended RAM off
				and rwb = '0'						-- writes
			else '0';
			
	buswin <= '0' when low64k = '0'
			else '1' when
				(isblockC = '1'
				and bus_window_c = '1'
				and bus_win_c_is_io = '0')
			or
				(A(15 downto 12) = "1001"
				and bus_window_9 = '1'
				and bus_win_9_is_io = '0')
			else '0';

	iowin_int <= '0' when low64k = '0'
			else '1' when
--				(A(15 downto 12) = "1100"	-- addresses $cxxx
--				and bus_window_c = '1'
--				and bus_win_c_is_io = '1')
--			or
				(A(15 downto 12) = "1001"	-- addresses $9xxx
				and bus_window_9 = '1'
				and bus_win_9_is_io = '1')
			else '0';
			
	vramsel_int <= '0' when avalid = '0' else
			'1' when screenwin = '1' or vram9 = '1' else
--			'1' when screenwin = '1' else
			'1' when do_page_map = '1' else
			boota19;			-- second 512k (or 1st 512k on boot)

	framsel_int <= '0' when avalid='0' 
					or boota19 = '1' else	-- not in upper half of 1M address space is ROM (4-7 are ignored, only 1M addr space)
			'1' when low64k = '0' or A(15) = '0' else	-- lowest 32k or 64k-512k is RAM, i.e. all above 64k besides ROM
			'0' when screenwin = '1' or iowin_int = '1' or buswin = '1' or wprot = '1' 
					or do_page_map ='1' else	-- not in screen window
			'1' when c8296ram = '1' else	-- upper half mapped (except peek through)
			'0' when petio = '1' else	-- not in I/O space
			'1';
			
	ram_p: process(phi2, avalid, boota19, low64k, A, screenwin, iowin_int2, buswin, wprot, c8296ram, petio) 
	begin
		if (rising_edge(phi2)) then
		end if;
	end process;
			ffsel <= ffsel_int;
			iowin <= iowin_int2;
			iosel <= iosel_int;
			memsel <= memsel_int;
			RA <= RA_int;
			framsel <= framsel_int;
			vramsel <= vramsel_int;
	
	iosel_int <= '0' when avalid='0' 
					or low64k = '0' 			-- not in lowest 64k
					or c8296ram = '1' else 	-- or if in 8296 ram instead of normal address map and no peekthrough
			'1' when petio ='1' else 
			'0';
			
	iowin_int2 <= '0' when avalid = '0' 
			else iowin_int;
	
	memsel_int <= '1' when
		bank(7 downto 4) = "0001" else
			buswin;
			
	ffsel_int <= '0' when avalid='0' else
			'1' when low64k ='1' 
				and A(15 downto 8) = x"FF" else 
			'0';

	-----------------------------------
	-- cfg
	
	CfgMP: process(reset, phi2, rwb, cfgld, D)
	begin
		if (reset ='1') then
			cfg_mp <= (others => '0');
		elsif (falling_edge(phi2)) then
			if (cfgld = '1' and rwb = '0') then
				cfg_mp <= D;
			end if;
		end if;
	end process;
	
	
end Behavioral;

