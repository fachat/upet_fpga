----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    21:40:17 10/21/2023 
-- Design Name: 
-- Module Name:    DAC - Behavioral 
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

entity DAC is
	Port (
		phi2: in std_logic;
		sel: in std_logic;
		rwb: in std_logic;
		regsel: in std_logic_vector(3 downto 0);
		din: in std_logic_vector(7 downto 0);
		dout: out std_logic_vector(7 downto 0);
		
		qclk: in std_logic;
		dotclk: in std_logic_vector(3 downto 0);
		vdin: in std_logic_vector(7 downto 0);

		dma_req: out std_logic;
		dma_ack: in std_logic;		-- on falling edge data is taken
		dma_addr: out std_logic_vector(15 downto 0);

		spi_naudio: out std_logic;
		spi_aclk: out std_logic;
		spi_amosi: out std_logic;
		nldac: out std_logic;

		reset: in std_logic
	);

end DAC;

architecture Behavioral of DAC is

	type AOA8 is array(natural range<>) of std_logic_vector(7 downto 0);

	signal dma_active: std_logic;
	signal dma_loop: std_logic;
	signal dma_stereo: std_logic;
	signal dma_channel: std_logic;	-- only if stereo == 0
	signal dma_start: std_logic_vector(15 downto 0);
	signal dma_len: std_logic_vector(15 downto 0);
	
	signal dma_ce: std_logic;
	signal dma_load: std_logic;
	signal dma_addr_int: std_logic_vector(15 downto 0);
	signal dma_count: std_logic_vector(15 downto 0);

	signal dac_buf: AOA8(0 to 15);
	signal dac_wp: natural range 0 to 15;
	signal dac_rp: natural range 0 to 15;
	signal dac_rate: std_logic_vector(11 downto 0);		--	approx 10Hz - 44100Hz
	signal dac_count: std_logic_vector(15 downto 0);	-- clock counter for rate; scale = 16x rate
	
	-- spi phases
	-- 00: inactive
	-- 01: sel down
	-- 02: shift out
	-- 03: sel out
	-- 04: ldac down
	-- 05: ldac up, end
	signal spi_phase: std_logic_vector(2 downto 0);
	signal spi_cnt: std_logic_vector(6 downto 0);
	signal spi_start: std_logic;
	signal spi_buf: std_logic_vector(7 downto 0);
	signal spi_msg: std_logic_vector(15 downto 0);
	signal spi_chan: std_logic;
	signal spi_direct: std_logic;
	
	signal rate_ce: std_logic;
	signal dac_ce: std_logic;
	signal spi_ce: std_logic;
	signal mosi_ce: std_logic;
	
begin

	dma_ce <= '1' when dotclk(0) = '1' and dotclk(1) = '1' else '0';
	dac_ce <= '1' when dotclk(0) = '1' and dotclk(1) = '1' else '0';
	rate_ce <= '1' when dotclk(0) = '1' and dotclk(1) = '0' else '0';
	-- spi_ce must enable same falling clock as phi2 falling, to get direct writes
	spi_ce <= '1' when dotclk(0) = '1' and dotclk(1) = '1' else '0';
	-- mosi_ce should be between two spi_ce
	mosi_ce <= '1' when dotclk(0) = '0' and dotclk(1) = '1' else '0';

	dma_p: process(qclk, dma_ce, reset)
	begin
		if (reset = '1') then
			dma_req <= '0';
			dac_wp <= 0;
		elsif (falling_edge(qclk) and dma_ce = '1') then
			if (dma_load = '1' or dma_count = x"0000") then
				dma_addr_int <= dma_start;
				dma_count <= dma_len;
			elsif (dma_ack = '1') then
				dma_addr_int <= dma_addr_int + 1;
				dma_count <= dma_count - 1;
			end if;

			if (dma_active = '0') then
				dac_wp <= 0;
			else
				if (dac_wp = 15) then
					dac_wp <= 0;
				else
					dac_wp <= dac_wp + 1;
				end if;
			end if;
			
			dma_req <= '0';
			if(not(dac_rp = dac_wp)) then
				if (dma_active = '1') then
					dma_req <= '1';
				end if;
			end if;
		end if;
	end process;
	
	dma_addr <= dma_addr_int;

	rate_p: process(qclk, reset,rate_ce, dac_ce, spi_ce, mosi_ce)
	begin
		if (reset = '1') then
			spi_start <= '0';
		elsif (falling_edge(qclk)) then	
			if (rate_ce = '1') then
				-- reset counter
				if (dma_active = '0') then
					spi_start <= '0';
					dac_count(15 downto 4) <= dac_rate;
				elsif (dac_rate = dac_count(15 downto 4)) then
					dac_count <= (others => '0');
					spi_start <= '1';
				else
					dac_count <= dac_count + 1;
					spi_start <= '0';
				end if;
			end if;
		end if;
	end process;
	
	spi_p: process(qclk, reset, spi_ce, spi_start, spi_phase, spi_cnt)
	begin
		if (reset = '1') then
			spi_naudio <= '1';
			nldac <= '1';
			dac_rp <= 0;
		elsif (falling_edge(qclk) and spi_ce = '1') then
						
				if (spi_start = '1') then
					-- start work
					spi_phase <= "001";
					spi_cnt <= (others => '0');
					spi_buf <= dac_buf(dac_rp);
					spi_chan <= '0'; 	-- TODO
					dac_rp <= dac_rp + 1;
				elsif (spi_direct = '1') then
					spi_phase <= "001";
					spi_cnt <= (others => '0');
					spi_buf <= din;
					spi_chan <= regsel(0);
				elsif (spi_phase = "001" and spi_cnt = "000010") then
					-- after waiting spi_cnt=2 cycles to keep chip setup time, select chip
					spi_naudio <= '0';
					spi_cnt <= spi_cnt + 1;
				elsif (spi_phase = "001" and spi_cnt = "000100") then
					-- after waiting another 2 cycles, start shifting phase, reset counter
					-- note: each bit is 4 cycles; 2 c. per SPI clock phase
					spi_phase <= "010";
					spi_cnt <= (others => '0');
				elsif (spi_phase = "010" and spi_cnt = "011111") then
					-- after 16x2 cycles, end shifting phase, deselect chip
					spi_phase <= "011";
					spi_cnt <= (others => '0');
				elsif (spi_phase = "011" and spi_cnt = "00001") then
					spi_naudio <= '1';
					nldac <= '0';
					spi_cnt <= spi_cnt + 1;
				elsif (spi_phase = "011" and spi_cnt = "00100") then
					spi_phase <= "000";
					nldac <= '1';
					spi_cnt <= spi_cnt + 1;
				else
					spi_cnt <= spi_cnt + 1;
				end if;
		end if;
	end process;
	
	-- shift out 16 bits (msb first) per channel
	-- 15: A/B:  0 = DAC A, 1 = DAC B
	-- 14: --
	-- 13: /GA: gain selection: 1 = 1x Vref, 0 = 2x Vref
	-- 12: /SHDN: shutdown. 1 = active, 0 = output disabled
	-- 11: D7
	-- ...
	--  4: D0
	--  3: --
	--  2: --
	--  1: --
	--  0: --
	spi_msg(15) <= spi_chan;
	spi_msg(14) <= '0';	-- n/a bit
	spi_msg(13) <= '0';	-- gain TODO
	spi_msg(12) <= '1';	-- active
	spi_msg(11 downto 4) <= spi_buf;
	spi_msg(3 downto 0) <= (others => '0');
	
	mosi_p: process(qclk, reset, dac_ce, spi_ce, mosi_ce, spi_start)
	begin
		if (reset = '1') then
			spi_amosi <= '0';
		elsif (falling_edge(qclk) and mosi_ce = '1') then
			spi_aclk <= '0';		-- mode 0
			if (spi_phase = "010") then
				-- shifting phase, starts with cnt="000000"
				spi_aclk <= spi_cnt(0);
				if (spi_cnt(0) = '0') then
					-- on end of clk hi, set new value
					-- index is derived from cnt
					spi_amosi <= spi_msg(15 - to_integer(unsigned(spi_cnt(4 downto 1))));
				end if;
			end if;
		end if;
	end process;
	
	spi_direct <= '1' when
				sel = '1'
				and rwb = '0'
				and regsel(3 downto 1) = "110"
			else '0';
	
	regw_p: process(reset, phi2, sel, regsel,rwb)
	begin
		if (reset = '1') then
			dma_active <= '0';
			dma_stereo <= '0';
			dma_channel <= '0';
			dma_loop <= '0';
		elsif (falling_edge(phi2)
			and sel = '1' and rwb = '0'
			) then

			case (regsel) is
			when "0000" =>	-- R0
				dma_start(7 downto 0) <= din;
			when "0001" => 	-- R1
				dma_start(15 downto 8) <= din;
			when "0010" =>	-- R2
				dma_len(7 downto 0) <= din;
			when "0011" =>	-- R3
				dma_len(15 downto 8) <= din;
			when "0100" =>	-- R3
				dac_rate(7 downto 0) <= din;
			when "0101" =>	-- R3
				dac_rate(11 downto 8) <= din(3 downto 0);
			when "1100" =>	-- R12
				-- dummy, see spi_direct
			when "1101" =>	-- R13
				-- dummy, see spi_direct
			when "1111" =>	-- R15
				dma_active <= din(7);
				dma_channel <= din(2);
				dma_stereo <= din(1);
				dma_loop <= din(0);
			when others =>
				null;
			end case;
		end if;
	end process;
	
	reqr_p: process(phi2, sel, rwb, regsel, dma_start, dma_len, dac_rate, dma_active, dma_channel, dma_stereo, dma_loop)
	begin
		dout <= (others => '0');
		
		if (sel = '1' and rwb = '1') then
		
			case regsel is
			when "0000" =>	-- R0
				dout <= dma_start(7 downto 0);
			when "0001" =>	-- R1
				dout <= dma_start(15 downto 8);
			when "0010" =>
				dout <= dma_len(7 downto 0);
			when "0011" =>
				dout <= dma_len(15 downto 8);
			when "0100" =>
				dout <= dac_rate(7 downto 0);
			when "0101" =>
				dout(3 downto 0) <= dac_rate(11 downto 8);
			when "1111" =>
				dout(7) <= dma_active;
				dout(2) <= dma_channel;
				dout(1) <= dma_stereo;
				dout(0) <= dma_loop;
			when others =>
				null;
			end case;
		end if;
	end process;
	
	
end Behavioral;
