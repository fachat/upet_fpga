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
	   qclk: in std_logic;		-- Q clock (54MHz)
	   dotclk: in std_logic_vector(1 downto 0); 	-- 27Mhz

		mode_60hz: in std_logic;
		mode_tv: in std_logic;
 	   mode_out: in std_logic;
		
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
	
	-- in characters
	constant x_default_offset_50: std_logic_vector(6 downto 0):= std_logic_vector(to_unsigned(9,7));
	-- in rasterlines
	constant y_default_offset_50: natural := 80; -- 130
	-- zero for pixel coordinates is 88 rasterlines up of default borders
	constant vv_zero_50: std_logic_vector(9 downto 0)			:=std_logic_vector(to_unsigned(606, 10));
	
	-- visible horizontal window is shifted 8 cycles in front to account for pre-fetch; so we shift sync 8 cycles back

	---- VGA 50Hz 720x576p timing
	-- all values in pixels
	constant hh_display_50: std_logic_vector(10 downto 0)		:= std_logic_vector(to_unsigned(720				-1, 11));
	constant hh_sync_pos_50: std_logic_vector(10 downto 0)	:= std_logic_vector(to_unsigned(732				-1, 11)); --+7, 11));
	constant hh_sync_end_50: std_logic_vector(10 downto 0)	:= std_logic_vector(to_unsigned(796 			-1, 11)); --+7, 11));
	constant hh_total_50: std_logic_vector(10 downto 0)		:= std_logic_vector(to_unsigned(864				-1, 11));
	constant hh_zero_50: std_logic_vector(10 downto 0)			:= std_logic_vector(to_unsigned(820				-1, 11)); --+7, 11));
	-- all values in rasterlines
	constant vv_display_50: std_logic_vector(9 downto 0)		:=std_logic_vector(to_unsigned(576		-1, 10));
	constant vv_sync_pos_50: std_logic_vector(9 downto 0)		:=std_logic_vector(to_unsigned(581		-1, 10));
	constant vv_sync_end_50: std_logic_vector(9 downto 0)		:=std_logic_vector(to_unsigned(586		-1, 10));
	constant vv_total_50: std_logic_vector(9 downto 0)			:=std_logic_vector(to_unsigned(625		-1, 10));	
	
	---- TV PAL timing
	-- values in pixel
	constant hh_display_50_tv: std_logic_vector(10 downto 0)		:= std_logic_vector(to_unsigned(720 *2				-1, 11));
	constant hh_sync_pos_50_tv: std_logic_vector(10 downto 0)	:= std_logic_vector(to_unsigned(732 *2				-1, 11));
	constant hh_sync_end_50_tv: std_logic_vector(10 downto 0)	:= std_logic_vector(to_unsigned(795 *2	 			-1, 11));
	constant hh_total_50_tv: std_logic_vector(10 downto 0)		:= std_logic_vector(to_unsigned(864 *2				-1, 11));
	constant hh_zero_50_tv: std_logic_vector(10 downto 0)			:= std_logic_vector(to_unsigned(820 *2				-1, 11));
	-- all values in rasterlines
	constant vv_display_50_tv: std_logic_vector(9 downto 0)		:=std_logic_vector(to_unsigned(576		-1, 10));
	constant vv_sync_pos_50_tv: std_logic_vector(9 downto 0)		:=std_logic_vector(to_unsigned(580		-1, 10));
	constant vv_sync_end_50_tv: std_logic_vector(9 downto 0)		:=std_logic_vector(to_unsigned(586		-1, 10));
	constant vv_total_50_tv: std_logic_vector(9 downto 0)			:=std_logic_vector(to_unsigned(624		-1, 10));	

	---- PET monitor timing
	-- values in pixel
	constant hh_display_50_mon: std_logic_vector(10 downto 0)	:= std_logic_vector(to_unsigned(720 *2				-1, 11));
	constant hh_sync_pos_50_mon: std_logic_vector(10 downto 0)	:= std_logic_vector(to_unsigned(728 *2				-1, 11));
	constant hh_sync_end_50_mon: std_logic_vector(10 downto 0)	:= std_logic_vector(to_unsigned(856 *2	 			-1, 11));
	constant hh_total_50_mon: std_logic_vector(10 downto 0)		:= std_logic_vector(to_unsigned(864 *2				-1, 11));
	constant hh_zero_50_mon: std_logic_vector(10 downto 0)		:= std_logic_vector(to_unsigned(820 *2				-1, 11));
	-- all values in rasterlines
	constant vv_display_50_mon: std_logic_vector(9 downto 0)		:=std_logic_vector(to_unsigned(576		-1, 10));
	constant vv_sync_pos_50_mon: std_logic_vector(9 downto 0)	:=std_logic_vector(to_unsigned(590		-1, 10));
	constant vv_sync_end_50_mon: std_logic_vector(9 downto 0)	:=std_logic_vector(to_unsigned(620		-1, 10));
	constant vv_total_50_mon: std_logic_vector(9 downto 0)		:=std_logic_vector(to_unsigned(625		-1, 10));	


	----------------------------------------------------------------------------------------------------------------
	-- 720x480p60
	--
	-- 720x480@60 Hz
	-- 15.7343 kHz 	ModeLine "720x480" 13.50 720 739 801 858 480 488 494 524 -HSync -VSync Interlace 
	-- 31.4685 kHz 	ModeLine "720x480" 27.00 720 736 798 858 480 489 495 525 -HSync -VSync 
	--
	
	-- in characters
	constant x_default_offset_60: std_logic_vector(6 downto 0):= std_logic_vector(to_unsigned(9,7));
	-- in rasterlines
	constant y_default_offset_60: natural:= 80;
	-- zero for pixel coordinates is 85 rasterlines up of default borders
	constant vv_zero_60: std_logic_vector(9 downto 0)				:=std_logic_vector(to_unsigned(480, 10));
	
	---- VGA 60Hz 720x480p timing
	-- all values in pixels
	constant hh_display_60: std_logic_vector(10 downto 0)			:= std_logic_vector(to_unsigned(720				-1, 11));
	constant hh_sync_pos_60: std_logic_vector(10 downto 0)		:= std_logic_vector(to_unsigned(736				-1, 11));
	constant hh_sync_end_60: std_logic_vector(10 downto 0)		:= std_logic_vector(to_unsigned(798 			-1, 11));
	constant hh_total_60: std_logic_vector(10 downto 0)			:= std_logic_vector(to_unsigned(858				-1, 11));
	constant hh_zero_60: std_logic_vector(10 downto 0)				:= std_logic_vector(to_unsigned(824				-1, 11));
	-- in rasterlines
	constant vv_display_60: std_logic_vector(9 downto 0)			:=std_logic_vector(to_unsigned(480		-1, 10));
	constant vv_sync_pos_60: std_logic_vector(9 downto 0)			:=std_logic_vector(to_unsigned(489		-1, 10));
	constant vv_sync_end_60: std_logic_vector(9 downto 0)			:=std_logic_vector(to_unsigned(495		-1, 10));
	constant vv_total_60: std_logic_vector(9 downto 0)				:=std_logic_vector(to_unsigned(525		-1, 10));

	---- 60Hz NTSC timing
	--	horizonatl timing
	constant hh_display_60_tv: std_logic_vector(10 downto 0)		:= std_logic_vector(to_unsigned(720	*2			-1, 11));
	constant hh_sync_pos_60_tv: std_logic_vector(10 downto 0)	:= std_logic_vector(to_unsigned(739	*2			-1, 11));
	constant hh_sync_end_60_tv: std_logic_vector(10 downto 0)	:= std_logic_vector(to_unsigned(801 *2			-1, 11));
	constant hh_total_60_tv: std_logic_vector(10 downto 0)		:= std_logic_vector(to_unsigned(858	*2			-1, 11));
	constant hh_zero_60_tv: std_logic_vector(10 downto 0)			:= std_logic_vector(to_unsigned(824	*2			-1, 11));	
	-- in rasterlines
	constant vv_display_60_tv: std_logic_vector(9 downto 0)		:=std_logic_vector(to_unsigned(480		-1, 10));
	constant vv_sync_pos_60_tv: std_logic_vector(9 downto 0)		:=std_logic_vector(to_unsigned(488		-1, 10));
	constant vv_sync_end_60_tv: std_logic_vector(9 downto 0)		:=std_logic_vector(to_unsigned(494		-1, 10));
	constant vv_total_60_tv: std_logic_vector(9 downto 0)			:=std_logic_vector(to_unsigned(525		-1, 10));

	---- 60Hz PET monitor timing
	--	horizonatl timing
	constant hh_display_60_mon: std_logic_vector(10 downto 0)	:= std_logic_vector(to_unsigned(720	*2			-1, 11));
	constant hh_sync_pos_60_mon: std_logic_vector(10 downto 0)	:= std_logic_vector(to_unsigned(730	*2			-1, 11));
	constant hh_sync_end_60_mon: std_logic_vector(10 downto 0)	:= std_logic_vector(to_unsigned(850 *2			-1, 11));
	constant hh_total_60_mon: std_logic_vector(10 downto 0)		:= std_logic_vector(to_unsigned(858	*2			-1, 11));
	constant hh_zero_60_mon: std_logic_vector(10 downto 0)		:= std_logic_vector(to_unsigned(824	*2			-1, 11));	
	-- in rasterlines
	constant vv_display_60_mon: std_logic_vector(9 downto 0)		:=std_logic_vector(to_unsigned(480		-1, 10));
	constant vv_sync_pos_60_mon: std_logic_vector(9 downto 0)	:=std_logic_vector(to_unsigned(485		-1, 10));
	constant vv_sync_end_60_mon: std_logic_vector(9 downto 0)	:=std_logic_vector(to_unsigned(520		-1, 10));
	constant vv_total_60_mon: std_logic_vector(9 downto 0)		:=std_logic_vector(to_unsigned(524		-1, 10));



	----------------------------------------------------------------------------------------------------------------
	-- all values in pixels
	-- note: cummulative, starting with display
	signal hh_display: std_logic_vector(10 downto 0);
	signal hh_sync_pos: std_logic_vector(10 downto 0);
	signal hh_sync_end: std_logic_vector(10 downto 0);
	signal hh_total: std_logic_vector(10 downto 0);
	signal hh_zero: std_logic_vector(10 downto 0);

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

	signal x_addr_int: std_logic_vector(10 downto 0);
	signal y_addr_int: std_logic_vector(9 downto 0);
	
    ---------------------------------------------------------------------------
    -- 720x480p60 timing constants
    --   These must be consistent with the H_TOTAL / V_TOTAL used inside
    --   HdmiTestTop to ensure the video signals align with the TMDS stream.
    --
    --  Horizontal (858 total):
    --    [  0 .. 719] display
    --    [720 .. 735] front porch  (16)
    --    [736 .. 797] sync pulse   (62, negative)
    --    [798 .. 857] back porch   (60)
    --
    --  Vertical (525 total):
    --    [  0 .. 479] display
    --    [480 .. 488] front porch  ( 9)
    --    [489 .. 494] sync pulse   ( 6, negative)
    --    [495 .. 524] back porch   (30)
    ---------------------------------------------------------------------------
    constant H_DISPLAY_60 : integer := 720;
    constant H_FP_60      : integer := 16;
    constant H_SYNC_W_60  : integer := 62;
    constant H_TOTAL_60   : integer := 858;
	 constant H_ZERO_P_60  : integer := 824;
	 
    constant V_DISPLAY_60 : integer := 480;
    constant V_FP_60      : integer := 9;
    constant V_SYNC_W_60  : integer := 6;
    constant V_TOTAL_60   : integer := 525;
	 constant V_ZERO_P_60  : integer := 478; --480;

    ---------------------------------------------------------------------------
    -- 720x576p50 timing constants
    constant H_DISPLAY_50 : integer := 720;
    constant H_FP_50      : integer := 12;
    constant H_SYNC_W_50  : integer := 64;
    constant H_TOTAL_50   : integer := 864;
	 constant H_ZERO_P_50  : integer := 820;
	 
    constant V_DISPLAY_50 : integer := 576;
    constant V_FP_50      : integer := 5;
    constant V_SYNC_W_50  : integer := 5;
    constant V_TOTAL_50   : integer := 625;
	 constant V_ZERO_P_50  : integer := 525;

    ---------------------------------------------------------------------------
	 
	 signal h_display 	 : integer range 0 to 1023;
	 signal h_sync_b   	 : integer range 0 to 1023;
	 signal h_sync_e	 	 : integer range 0 to 1023;
	 signal h_total	  	 : integer range 0 to 1023;
	 signal h_zero_p		 : integer range 0 to 1023;
	 
	 signal v_display 	 : integer range 0 to 1023;
	 signal v_sync_b	  	 : integer range 0 to 1023;
	 signal v_sync_e	 	 : integer range 0 to 1023;
	 signal v_total	  	 : integer range 0 to 1023;
	 signal v_zero_p		 : integer range 0 to 1023;
	 
	 
	 signal frame_h_cnt   : integer range 0 to 1023;
    signal frame_v_cnt   : integer range 0 to 1023;
	 signal de_s		: std_logic;
	 signal hde_s		: std_logic;
	 signal vde_s		: std_logic;
	 signal hsync_s	: std_logic;
	 signal vsync_s	: std_logic;
	 signal hzero_s   : std_logic;
	 signal vzero_s   : std_logic;
	 
	 signal hzero_d1	: std_logic;
	 signal hzero_d2	: std_logic;
	 signal hzero_d3	: std_logic;
	 signal hzero_d4	: std_logic;
	 
begin

	-- passed through to the actual output; some modes inverted, others not
	-- 640x480 has h negative v negative
	-- 768x576 has h negative v negative
	h_sync_ext <= not( hsync_s );
	v_sync_ext <= not( vsync_s );
	
	-- in characters
	x_default_offset <= x_default_offset_val;
	-- in rasterlines
	y_default_offset <= y_default_offset_val;

	-- geometry

	geo_p: process(mode_60hz, mode_tv, mode_out) 
	begin
	
		if (mode_60hz = '0') then
--		if (mode_60hz = '1') then
--			if (mode_tv = '1') then
--				if (mode_out = '1') then
--					hh_display 			<= hh_display_60_mon;
--					hh_sync_pos 		<= hh_sync_pos_60_mon;
--					hh_sync_end 		<= hh_sync_end_60_mon;
--					hh_total 			<= hh_total_60_mon;
--					hh_zero	 			<= hh_zero_60_mon;
--					vv_display			<= vv_display_60_mon;
--					vv_sync_pos			<= vv_sync_pos_60_mon;
--					vv_sync_end			<= vv_sync_end_60_mon;
--					vv_total				<= vv_total_60_mon;
--				else
--					hh_display 			<= hh_display_60_tv;
--					hh_sync_pos 		<= hh_sync_pos_60_tv;
--					hh_sync_end 		<= hh_sync_end_60_tv;
--					hh_total 			<= hh_total_60_tv;
--					hh_zero	 			<= hh_zero_60_tv;
--					vv_display			<= vv_display_60_tv;
--					vv_sync_pos			<= vv_sync_pos_60_tv;
--					vv_sync_end			<= vv_sync_end_60_tv;
--					vv_total				<= vv_total_60_tv;
--				end if;
--			else
--				hh_display 			<= hh_display_60;
--				hh_sync_pos 		<= hh_sync_pos_60;
--				hh_sync_end 		<= hh_sync_end_60;
--				hh_total 			<= hh_total_60;
--				hh_zero	 			<= hh_zero_60;
--				vv_display			<= vv_display_60;
--				vv_sync_pos			<= vv_sync_pos_60;
--				vv_sync_end			<= vv_sync_end_60;
--				vv_total				<= vv_total_60;				
--			end if;
--			vv_zero					<= vv_zero_60;

			x_default_offset_val	<= x_default_offset_60;
			y_default_offset_val	<= y_default_offset_60;

			h_display			<= H_DISPLAY_60;
			h_sync_b				<= H_DISPLAY_60 + H_FP_60;
			h_sync_e				<= H_DISPLAY_60 + H_FP_60 + H_SYNC_W_60;
			h_total				<= H_TOTAL_60 - 1;
			h_zero_p				<= H_ZERO_P_60;
			
			v_display			<= V_DISPLAY_60;
			v_sync_b				<= V_DISPLAY_60 + V_FP_60;
			v_sync_e				<= V_DISPLAY_60 + V_FP_60 + V_SYNC_W_60;
			v_total				<= V_TOTAL_60 - 1;
			v_zero_p				<= V_ZERO_P_60;
		else
--			if (mode_tv = '1') then
--				if (mode_out = '1') then
--					hh_display 			<= hh_display_50_mon;
--					hh_sync_pos 		<= hh_sync_pos_50_mon;
--					hh_sync_end 		<= hh_sync_end_50_mon;
--					hh_total 			<= hh_total_50_mon;
--					hh_zero	 			<= hh_zero_50_mon;
--					vv_display			<= vv_display_50_mon;
--					vv_sync_pos			<= vv_sync_pos_50_mon;
--					vv_sync_end			<= vv_sync_end_50_mon;
--					vv_total				<= vv_total_50_mon;
--				else
--					hh_display 			<= hh_display_50_tv;
--					hh_sync_pos 		<= hh_sync_pos_50_tv;
--					hh_sync_end 		<= hh_sync_end_50_tv;
--					hh_total 			<= hh_total_50_tv;
--					hh_zero	 			<= hh_zero_50_tv;
--					vv_display			<= vv_display_50_tv;
--					vv_sync_pos			<= vv_sync_pos_50_tv;
--					vv_sync_end			<= vv_sync_end_50_tv;
--					vv_total				<= vv_total_50_tv;
--				end if;
--			else
--				hh_display 			<= hh_display_50;
--				hh_sync_pos 		<= hh_sync_pos_50;
--				hh_sync_end 		<= hh_sync_end_50;
--				hh_total 			<= hh_total_50;
--				hh_zero	 			<= hh_zero_50;
--				vv_display			<= vv_display_50;
--				vv_sync_pos			<= vv_sync_pos_50;
--				vv_sync_end			<= vv_sync_end_50;
--				vv_total				<= vv_total_50;
--			end if;
--			vv_zero					<= vv_zero_50;

			x_default_offset_val	<= x_default_offset_50;
			y_default_offset_val	<= y_default_offset_50;

			h_display			<= H_DISPLAY_50;
			h_sync_b				<= H_DISPLAY_50 + H_FP_50;
			h_sync_e				<= H_DISPLAY_50 + H_FP_50 + H_SYNC_W_50;
			h_total				<= H_TOTAL_50 - 1;
			h_zero_p				<= H_ZERO_P_50;
			
			v_display			<= V_DISPLAY_50;
			v_sync_b				<= V_DISPLAY_50 + V_FP_50;
			v_sync_e				<= V_DISPLAY_50 + V_FP_50 + V_SYNC_W_50;
			v_total				<= V_TOTAL_50 - 1;
			v_zero_p				<= V_ZERO_P_50;
		end if;
	end process;

	-----------------------------------------------------------------------------
	-- frame generation

    hframe_p : process(qclk, dotclk, frame_h_cnt, h_total, frame_v_cnt, v_total, reset)
    begin
        if (rising_edge(qclk) and dotclk(0) = '0') then
            if reset = '1' then
                -- Hold everything in reset; start with ser_cnt=9 so the first
                -- active cycle immediately executes the load path.
                frame_h_cnt   <= 0;
                frame_v_cnt   <= 0;
            else
                -- Advance pixel / line counters.
                if (frame_h_cnt = h_total) then
                    frame_h_cnt <= 0;
                    if (frame_v_cnt = v_total) then
                        frame_v_cnt <= 0;
                    else
                        frame_v_cnt <= frame_v_cnt + 1;
                    end if;
                else
                    frame_h_cnt <= frame_h_cnt + 1;
                end if;
				end if;
				
				hzero_d1 <= hzero_s;
				hzero_d3 <= hzero_d2;
        end if;
    end process;

    video_gen_p : process(qclk, dotclk, frame_h_cnt, frame_v_cnt, h_display, v_display, h_sync_b, v_sync_b, v_zero_p, h_zero_p, h_sync_e, v_sync_e)
    begin
		-- hzero and hsync must not have glitches, so they need to be clocked
      if (rising_edge(qclk) and dotclk(0) = '1') then

        -- Data enable: high inside active display window.
        if frame_h_cnt < h_display and frame_v_cnt < v_display then
            de_s <= '1';
        else
            de_s <= '0';
        end if;
		  if (frame_h_cnt < h_display) then
				hde_s <= '1';
		  else
				hde_s <= '0';
		  end if;
		  if (frame_v_cnt < v_display) then
				vde_s <= '1';
		  else
				vde_s <= '0';
		  end if;

        -- Horizontal sync (positive polarity - note: ext is negative = low during pulse).
        if frame_h_cnt >= h_sync_b and frame_h_cnt < h_sync_e then
            hsync_s <= '1';
        else
            hsync_s <= '0';
        end if;

        -- Vertical sync (positive polarity - note: ext is negative = low during pulse).
        if frame_v_cnt >= v_sync_b and frame_v_cnt < v_sync_e then
            vsync_s <= '1';
        else
            vsync_s <= '0';
        end if;

		  -- vertical origin of coordinate system
		  if frame_v_cnt = v_zero_p then
				vzero_s <= '1';
		  else
				vzero_s <= '0';
		  end if;
		  
		  -- vertical origin of coordinate system
		  if frame_h_cnt = h_zero_p then
				hzero_s <= '1';
		  else
				hzero_s <= '0';
		  end if;

		end if;
		
		hzero_d2 <= hzero_d1;
		hzero_d4 <= hzero_d3;
	end process;

	-----------------------------------------------------------------------------
	-- horizontal geometry calculation
	
	xa: process(qclk, dotclk, hzero_s, x_addr_int, reset)
	begin
		if (falling_edge(qclk) and dotclk(0) = '1') then
			if (reset = '1' or hzero_s = '1') then
				x_addr_int <= (others => '0');
			else
				x_addr_int <= x_addr_int + 1;
			end if;
		end if;		
	end process;
	
	h_enable <= hde_s;
	h_sync <= hsync_s;

	hz: process(qclk, dotclk, hzero_s, hzero_d1, hzero_d2)
	begin
		if (falling_edge(qclk) and dotclk(1 downto 0) = "10") then
			-- shape ext. hzero; delays make sure a dotclk "10" falling q is always included
			h_zero <= hzero_s or hzero_d1 or hzero_d2 or hzero_d3 or hzero_d4;
		end if;
	end process;
			
	x_addr <= x_addr_int;
	
	-----------------------------------------------------------------------------
	-- vertical geometry calculation
	
	v_sync <= vsync_s;
	
	ya: process(qclk, vzero_s, y_addr_int, hsync_s, reset)
	begin
		if (rising_edge(hsync_s)) then
			if (reset = '1' or vzero_s = '1') then
				y_addr_int <= (others => '0');
			else
				y_addr_int <= y_addr_int + 1;
			end if;
		end if;
	end process;

	v_enable <= vde_s;

	vzero_p: process(hde_s, vzero_s)
	begin
		if (rising_edge(hde_s)) then
			v_zero <= vzero_s;
		end if;
	end process;
	
	y_addr <= y_addr_int;
	
--	dispen <= de_s;
	
end Behavioral;

