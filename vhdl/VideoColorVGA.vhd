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

entity Video is
    Port ( A : out  STD_LOGIC_VECTOR (15 downto 0);
	   CPU_D: in std_logic_vector(7 downto 0);
		VRAM_D: in std_logic_vector(7 downto 0);
		vd_out: out std_logic_vector(7 downto 0);
	   phi2: in std_logic;
	   
	   --dena   : out std_logic;	-- display enable
	   v_sync : out  STD_LOGIC;
      h_sync : out  STD_LOGIC;
	   pet_vsync: out std_logic;	-- for the PET screen interrupt

	   is_enable: in std_logic;
		is_80_in: in std_logic;
	   is_graph : in std_logic;	-- graphic mode (from PET I/O)
	   
	   crtc_sel : in std_logic;
	   crtc_rs : in std_logic_vector(6 downto 0);
	   crtc_rwb : in std_logic;
	   mode_regmap: out std_logic;
		
	   qclk: in std_logic;		-- Q clock (50MHz)
		dotclk: in std_logic_vector(3 downto 0);	-- 25Mhz, 1/2, 1/4, 1/8, 1/16
	   
	   vid_fetch : out std_logic; -- true during video access phase (all, character, chrom, and hires pixel data)
		vreq_video : out std_logic;	-- true if *next* memory access should be video
		
	   vid_out: out std_logic_vector(5 downto 0);
		
		irq_out: out std_logic;
		
	   dbg_out : out std_logic;
	   
	   reset : in std_logic
	   );
		attribute maxskew: string;
		attribute maxskew of vid_out : signal is "4 ns";
		attribute maxdelay: string;
		attribute maxdelay of vid_out : signal is "5 ns";
end Video;

architecture Behavioral of Video is

	type AOA2 is array(natural range<>) of std_logic_vector(1 downto 0);
	type AOA4 is array(natural range<>) of std_logic_vector(3 downto 0);
	type AOA5 is array(natural range<>) of std_logic_vector(4 downto 0);
	type AOA6 is array(natural range<>) of std_logic_vector(5 downto 0);
	type AOA8 is array(natural range<>) of std_logic_vector(7 downto 0);
	
	--- modes
	signal mode_attrib: std_logic;			-- r25.6, enable attribute use
	signal mode_extended: std_logic;		-- r33.2, enables full and multicolor modes
	signal mode_bitmap: std_logic;
	signal mode_pet: std_logic;			-- when Micro-PET compat, r1 and others behave differently
	signal mode_rev: std_logic;			-- r24.6, reverse the screen
	signal dispen: std_logic;
	signal mode_double: std_logic;
	signal mode_interlace: std_logic;
	signal mode_80col: std_logic;
	
	signal mode_altreg: std_logic;		-- enable access to alternate vid_base and attr_base
	signal mode_bitmap_alt: std_logic;	
	signal mode_extended_alt: std_logic;	
	signal mode_attrib_alt: std_logic;	
	signal mode_bitmap_reg: std_logic;	
	signal mode_extended_reg: std_logic;	
	signal mode_attrib_reg: std_logic;	
	signal mode_regmap_int: std_logic;
	signal mode_tv: std_logic;				-- used to enable "i" instead of "p" video modes, allowing for PAL/NTSC compatible timing
	signal mode_60hz: std_logic;			-- used to set 720x480p60 instead of the default 720x576p50
	signal mode_out: std_logic;			-- if mode_tv is set, use PET monitor timing
	signal alt_match_modes : std_logic;
	signal alt_match_hsync : std_logic;
	signal alt_match_palette : std_logic;
	signal alt_match_vaddr : std_logic;
	signal alt_match_attr : std_logic;
	signal alt_rc_cnt: std_logic_vector(3 downto 0);
	signal alt_set_rc: std_logic;
	signal alt_do_set_rc: std_logic;
	signal mode_set_flag: std_logic;
	signal mode_set_hsync: std_logic;
	
	--- colours
	signal col_fg: std_logic_vector(3 downto 0);
	signal col_bg0: std_logic_vector(3 downto 0);
	signal col_bg1: std_logic_vector(3 downto 0);
	signal col_bg2: std_logic_vector(3 downto 0);
	signal col_border: std_logic_vector(3 downto 0);
	signal vid_out_idx: std_logic_vector(4 downto 0);
	signal vid_out_blank: std_logic;
	
	--- blink
	signal blink_cnt: std_logic_vector(5 downto 0);
	signal blink_16: std_logic;			-- blink with 1/16 frame rate
	signal blink_32: std_logic;			-- blink with 1/32 frame rate
	
	--- cursor
	signal crsr_start_scan: std_logic_vector(4 downto 0);
	signal crsr_end_scan: std_logic_vector(4 downto 0);
	signal crsr_address: std_logic_vector(15 downto 0);
	signal crsr_mode: std_logic_vector(1 downto 0);
	signal crsr_active: std_logic;			-- set when cursor is active in scanline
	signal crsr_addr_match: std_logic;		-- set when cursor is in current display cell

	--- underline
	signal uline_scan : std_logic_vector(4 downto 0);
	signal uline_active: std_logic;			-- set when underline is active in scanline (but still needs attribute to be set)

	--- new geo
	signal x_border: std_logic;
	signal x_start: std_logic;
	signal y_border: std_logic;
	signal rline_cnt0: std_logic;

	---
	signal cblink_mode: std_logic;			-- character blink mode, R24.5
	signal cblink_active: std_logic;		-- when set, character blinking is active
	signal sr_reverse_p : std_logic;
	signal sr_underline_p: std_logic;
	signal is_outbit: std_logic_vector(1 downto 0);
	signal raster_out: AOA4(0 to 7);
	signal raster_bg: std_logic_vector(7 downto 0);
	signal raster_outbit: std_logic_vector(3 downto 0);
	signal sr_buf: std_logic_vector(7 downto 0);
	signal raster_isbg: std_logic;
	signal do_shift: std_logic;
	
	-- mode
	signal is_80: std_logic;
	
	-- crtc register emulation
	signal crtc_reg: std_logic_vector(7 downto 0);
	signal crtc_is_data: std_logic;
	signal regsel: std_logic_vector(7 downto 0);
	signal crtc_rs_int : std_logic_vector(7 downto 0);
	signal crtc_mapped: std_logic;

	signal rows_per_char: std_logic_vector(3 downto 0);
	signal bits_per_char: std_logic_vector(3 downto 0);
	signal vis_rows_per_char: std_logic_vector(3 downto 0);
	signal slots_per_line: std_logic_vector(6 downto 0);
	signal clines_per_screen: std_logic_vector(7 downto 0);
	signal hsync_pos: std_logic_vector(6 downto 0);
	signal vsync_pos: std_logic_vector(7 downto 0);
	
	signal vid_base : std_logic_vector(15 downto 0);
	signal attr_base : std_logic_vector(15 downto 0);
	signal crom_base : std_logic_vector(7 downto 0);
	
	signal vid_base_alt : std_logic_vector(15 downto 0);
	signal attr_base_alt : std_logic_vector(15 downto 0);

	signal h_shift_reg: std_logic_vector(2 downto 0);
	signal h_shift_alt: std_logic_vector(2 downto 0);

	-- count "slots", i.e. 8pixels
	-- 
	-- one slot may need none (out of screen), one (hires), or two (character display) 
	-- memory accesses. At 16MHz pixel, a slot has four potential memory accesses at 8MHz
	-- up to 127 slots/line
	--
	-- now see ClockBorder.vhd
	
	-- count raster lines per character lines
	signal rcline_cnt : std_logic_vector (3 downto 0) := (others => '0');

	-- vdc r27
	signal va_offset: std_logic_vector(7 downto 0);
	
	-- computed video memory address
	signal vid_addr : std_logic_vector (15 downto 0) := (others => '0');
	-- computed video memory address at start of line (to re-load chars each raster line)
	signal vid_addr_hold : std_logic_vector(15 downto 0) := (others => '0');

	-- computed attribute memory address
	signal attr_addr : std_logic_vector (15 downto 0) := (others => '0');
	-- computed attribute memory address at start of line (to re-load chars each raster line)
	signal attr_addr_hold : std_logic_vector(15 downto 0) := (others => '0');
	
	-- replacement for csa_ultracpu IC7 when holding character data for the crom fetch
	signal char_index_buf : std_logic_vector(7 downto 0);
	signal attr_buf : std_logic_vector(7 downto 0);
	signal pxl_buf : std_logic_vector(7 downto 0);
	-- replacements for shift register
	signal sr : std_logic_vector(6 downto 0);
	signal nsrload : std_logic;
	signal dena_int : std_logic;
	signal sr_attr: std_logic_vector(7 downto 0); -- the attributes for the bitmap in sr
	signal sr_crsr: std_logic;
	signal sr_blink: std_logic;
	signal sr_odd: std_logic;

	-- geo signals
	--
   signal x_addr: std_logic_vector(10 downto 0);    -- x coordinate in pixels
   signal y_addr: std_logic_vector(9 downto 0);    -- y coordinate in rasterlines
	signal y_addr_d: std_logic_vector(9 downto 0);	-- y coord delayed at end of h visible, to get early sprite enable
	signal y_addr_latch: std_logic_vector(9 downto 8); 	-- latch upper two bits when reading lower bits from r38
	
	-- border
	signal h_shift: std_logic_vector(2 downto 0);
	signal h_extborder: std_logic;
	signal h_extborder_alt: std_logic;
	signal h_extborder_reg: std_logic;
	signal v_extborder: std_logic;
	signal v_shift: std_logic_vector(3 downto 0);
	
	-- pulse for last visible character/slot; falling slotclk
	signal last_vis_slot_of_line : std_logic := '0';
	-- pulse at end of character line; falling slotclk
	signal last_line_of_char : std_logic := '0';
	-- pulse at end of screen
	signal last_line_of_screen : std_logic := '0';
	-- when char rows are actually visible
	signal vis_line_of_char: std_logic;
	
	-- enable
	signal h_enable : std_logic := '0';	
	signal v_enable : std_logic := '0';
	signal enable : std_logic;
	
	-- sync
	signal h_sync_int : std_logic := '0';	
	signal v_sync_int : std_logic := '0';
	signal h_sync_ext : std_logic := '0';	
	signal v_sync_ext : std_logic := '0';
	
	-- raster interrupt
	signal raster_match: std_logic_vector(9 downto 0);
	signal is_raster_match: std_logic;
	signal is_raster_match_d: std_logic;
	
	-- interrupts
	signal irq_raster_ack: std_logic;
	signal irq_raster: std_logic;
	signal irq_raster_en: std_logic;
	signal irq_out_int: std_logic;

	signal irq_sprite_raster_trigger: std_logic;
	signal irq_sprite_raster: std_logic;
	signal irq_sprite_raster_en: std_logic;
	signal irq_sprite_sprite_trigger: std_logic;
	signal irq_sprite_sprite: std_logic;
	signal irq_sprite_sprite_en: std_logic;
	signal irq_sprite_border_trigger: std_logic;
	signal irq_sprite_border: std_logic;
	signal irq_sprite_border_en: std_logic;

	-- intermediate
	signal h_zero: std_logic;
	signal v_zero: std_logic;
	signal a_out : std_logic_vector (15 downto 0);
	signal chr_window : std_logic;
	signal pxl_window : std_logic;
	signal attr_window : std_logic;
	signal sr_window : std_logic;
	signal sprite_ptr_window: std_logic;
	signal sprite_data_window: std_logic;

	signal h_phase0: std_logic;		-- when next memclk should be phase1 video fetch
	signal h_phase1: std_logic;		-- phase1 video fetch
	signal h_phase2: std_logic;		-- phase2 video fetch
	signal h_phase3: std_logic;		-- phase3 video fetch
	signal h_phase4: std_logic;		-- phase4 
	
	signal x_default_offset: std_logic_vector(6 downto 0);
	signal y_default_offset: natural;
	
	-- clock phases (16 half-pixels in one slot)
	signal pxl_ce_00: std_logic;
	signal pxl_ce_01: std_logic;
	signal pxl_ce_10: std_logic;
	signal fetch_ce: std_logic;

	signal new_line_attr: std_logic;
	signal new_line_vaddr: std_logic;
	--signal new_line_attr_d: std_logic;
	signal new_line_vaddr_d: std_logic;
	
	signal fetch_int: std_logic;
	signal fetch_sprite_en: std_logic;
	
	signal chr_fetch_int : std_logic;
	signal crom_fetch_int: std_logic;
	signal pxl_fetch_int : std_logic;
	signal attr_fetch_int : std_logic;
	signal sr_fetch_int : std_logic;
	
	signal sprite_ptr_fetch: std_logic;
	signal sprite_data_fetch: std_logic;
	
	-- true when shift should be done
	signal is_shift: std_logic;
	signal is_shift40: std_logic;
	signal is_shift80: std_logic;
	
	-- temporary
	signal is_double_int: std_logic;
	signal interlace_int: std_logic;

	-- sprite
	signal sprite_sel: std_logic_vector(7 downto 0);
	signal sprite_dout: AOA8(0 to 7);
	signal sprite_d: std_logic_vector(7 downto 0);
	signal sprite_fetch_offset: AOA6(0 to 7);
	signal sprite_enabled: std_logic_vector(7 downto 0);
	--signal sprite_active: std_logic_vector(7 downto 0);
	signal sprite_ison: std_logic_vector(7 downto 0);
	signal sprite_overraster: std_logic_vector(7 downto 0);
	signal sprite_overborder: std_logic_vector(7 downto 0);
	signal sprite_outbits: AOA5(0 to 7);
	signal sprite_fgcol: AOA4(0 to 7);
	signal sprite_mcol1: std_logic_vector(3 downto 0);
	signal sprite_mcol2: std_logic_vector(3 downto 0);
	signal sprite_base: std_logic_vector(7 downto 0);
	
	-- goes high after h_enable goes low to enable sprite fetch
	signal spr_fetch_en: std_logic;
	-- when a sprite fetch is active
	signal spr_fetch_active: std_logic_vector(7 downto 0);
	-- fetch enable from one sprite to the next, chaining the sprite fetches together
	signal spr_fetch_next: std_logic_vector(7 downto 0);
	-- active when sprite ptr is done on next fetch_ce
	signal spr_fetch_ptr: std_logic_vector(7 downto 0);
	
	
	-- palette
	--signal palette: AOA8(0 to 31);
	signal pal_sel: std_logic;		-- which half is visible in the register file
	signal pal_alt: std_logic;		-- use alternate palette
	
	-- output to mixer
	signal sprite_on: std_logic;
	signal sprite_outcol: std_logic_vector(4 downto 0);
	signal sprite_onborder: std_logic;
	signal sprite_onraster: std_logic;
	signal sprite_no: integer range 0 to 7;
	
	signal sprite_fetch_idx: integer range 0 to 7;
	signal sprite_fetch_idx_v: std_logic_vector(2 downto 0);
	signal sprite_fetch_win: std_logic;	-- sprites can fetch
	signal sprite_fetch_done: std_logic;	-- sprites can fetch
	signal sprite_fetch_active: std_logic;		-- sprite is active for fetch
	signal sprite_data_ptr: std_logic_vector(7 downto 0);
	signal sprite_fetch_ce: std_logic_vector(7 downto 0);
	signal sprite_fetch_ptr: std_logic_vector(15 downto 0);
	
	-- collision
	signal collision_sprite_sprite_none: std_logic;
	signal collision_sprite_raster_none: std_logic;
	signal collision_sprite_border_none: std_logic;
	
	signal collision_trigger_sprite_border: std_logic_vector(7 downto 0);
	signal collision_accum_sprite_border: std_logic_vector(7 downto 0);
	signal collision_trigger_sprite_raster: std_logic_vector(7 downto 0);
	signal collision_accum_sprite_raster: std_logic_vector(7 downto 0);
	signal collision_trigger_sprite_sprite: std_logic_vector(7 downto 0);
	signal collision_accum_sprite_sprite: std_logic_vector(7 downto 0);
	
	-- palette as block ram
	signal pbr_clkA :  std_logic;
	signal pbr_enA :  std_logic;
	signal pbr_weA :  std_logic;
	signal pbr_addrA :  std_logic_vector(4 downto 0);
	signal pbr_diA :  std_logic_vector(7 downto 0);
	signal pbr_doA :  std_logic_vector(7 downto 0);
		
	signal pbr_clkB :  std_logic;
	signal pbr_enB :  std_logic;
	signal pbr_weB :  std_logic;
	signal pbr_addrB :  std_logic_vector(4 downto 0);
	signal pbr_diB :  std_logic_vector(7 downto 0);
	signal pbr_doB :  std_logic_vector(7 downto 0);

	-- helpers
	
	function To_Std_Logic(L: BOOLEAN) return std_ulogic is
	begin
		if L then
			return('1');
		else
			return('0');
		end if;
	end function To_Std_Logic;

	-- VGA canvas (fixed timing, ?_addr start with 0/0 on upper left edge, outside visible area)
	component Canvas is
    	Port (
           qclk: in std_logic;          -- Q clock (50MHz)
           dotclk: in std_logic_vector(3 downto 0);     -- 25Mhz, 1/2, 1/4, 1/8, 1/16

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

           x_addr: out std_logic_vector(10 downto 0);    -- x coordinate in pixels
           y_addr: out std_logic_vector(9 downto 0);    -- y coordinate in rasterlines

			  x_default_offset: out std_logic_vector(6 downto 0);
			  y_default_offset: out natural;
			  
           reset : in std_logic
        );
	end component;

	component HBorder is
		Port (
			qclk: in std_logic;
			dotclk: in std_logic_vector(3 downto 0);			
			
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
	end component;

	component VBorder is
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
	end component;
	
	component Sprite is
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
	end component;
	
	component palette_bram is 

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

	end component;
	
	

begin
	
	windows_p: process(dotclk, h_phase1, h_phase2, h_phase3, h_phase4)
	begin
			chr_window <= h_phase1;		--'0';
			attr_window <= h_phase2;	--'0';
			pxl_window <= h_phase3;		--'0';
			sr_window <= h_phase4;		--'0';
			sprite_ptr_window <= '0';
			sprite_data_window <= '0';
			
			-- access windows for pixel data, character data, or chr ROM
			-- TODO: make case()
			if (dotclk(3 downto 2) = "00") then
				--chr_window <= '1';
				sprite_ptr_window <= '1';
			end if;
			
			-- note: attributes must be loaded before character set, as attributes contain alternate character bit
			if (dotclk(3 downto 2) = "01") then
				--attr_window <= '1';
				sprite_data_window <= '1';
			end if;

			if (dotclk(3 downto 2) = "10") then
				--pxl_window <= '1';
				sprite_data_window <= '1';
			end if;			
			
			if (dotclk(3 downto 2) = "11") then
				--sr_window <= '1';
				sprite_data_window <= '1';
			end if;
			
	end process;

	ce_p: process(dotclk)
	begin
			pxl_ce_00 <= '0';
			pxl_ce_01 <= '0';
			pxl_ce_10 <= '0';
			fetch_ce <= '0';

			if (dotclk(1 downto 0) = "00") then
				pxl_ce_00 <= '1';
			end if;

			if (dotclk(1 downto 0) = "01") then
				pxl_ce_01 <= '1';
			end if;
			if (dotclk(1 downto 0) = "10") then
				pxl_ce_10 <= '1';
			end if;

			if (dotclk(1 downto 0) = "11") then
				fetch_ce <= '1';
			end if;
	end process;
	

	--fetch_int <= is_enable and (not(in_slot) or is_80) and (interlace_int or not(rline_cnt0));
	fetch_int <= is_enable and (interlace_int or not(rline_cnt0));
	
	
	-- do we fetch character index?
	-- not hires, and first cycle in streak
	chr_fetch_int <= chr_window and fetch_int and not(mode_bitmap);

	-- col fetch
	attr_fetch_int <= attr_window and fetch_int and (mode_attrib or mode_extended);
	
	-- hires fetch
	pxl_fetch_int <= pxl_window and fetch_int;	-- both, hires and crom and mode_bitmap;
	
	-- character rom fetch
	crom_fetch_int <= pxl_window and fetch_int and not(mode_bitmap);

	-- sr load
	sr_fetch_int <= sr_window and fetch_int;

	fetch_p: process(chr_fetch_int, pxl_fetch_int, attr_fetch_int, crom_fetch_int, qclk,
						sprite_ptr_fetch, sprite_data_fetch, dotclk)
	begin
		-- video access?
--		if (falling_edge(qclk) and dotclk(1 downto 0) = "11") then
			vid_fetch <= chr_fetch_int 
						or pxl_fetch_int 
						or attr_fetch_int 
						or sprite_ptr_fetch
						or sprite_data_fetch
						;
					
			-- provisional approach for initial testing of new approach
			if (dotclk(3 downto 2) = "10") then
				--vreq_video <= '0';
				vreq_video <= sprite_data_fetch;
			else 
				vreq_video <= '1';
			end if;
--		end if;
	end process;
	
	-----------------------------------------------------------------------------
	-- geometry calculation

	-------------------------------------------
	-- VGA canvas, incl. fixed enable output
	vgacanvas: Canvas
	port map (
		qclk,
		dotclk,
		mode_60hz,
		mode_tv,
		mode_out,
		v_sync_int,
		h_sync_int,
		v_sync_ext,
		h_sync_ext,
		h_zero,
		v_zero,
		h_enable,
		v_enable,
		x_addr,
		y_addr,
		x_default_offset,
		y_default_offset,
		reset
	);

	y_addr_d_p: process(y_addr, h_enable)
	begin
		if (falling_edge(h_enable)) then
			y_addr_d <= y_addr;
		end if;
	end process;
	
	-------------------------------------------
	-- border calculations and display state

	h_border: HBorder
	port map (
			qclk,
			dotclk,
			h_zero,
			hsync_pos,
			slots_per_line,
			mode_tv,
			h_extborder,			
			is_80,
			h_phase0,
			h_phase1,
			h_phase2,
			h_phase3,
			h_phase4,
			x_start,
			x_border,
			last_vis_slot_of_line,
			is_shift40,
			is_shift80,
			reset
	);
	
	v_border: VBorder
	port map (
			h_zero,
			v_zero,
			y_addr,
			vsync_pos,
			rows_per_char,
			vis_rows_per_char,
			clines_per_screen,
			v_extborder,
			is_double_int,
			mode_tv,
			v_shift,
			alt_rc_cnt,
			alt_do_set_rc,
			y_border,
			last_line_of_char,
			last_line_of_screen,
			vis_line_of_char,
			rcline_cnt,
			rline_cnt0,
			reset
	);
	
	alt_do_set_rc <= is_raster_match and alt_set_rc;
	
	h_sync <= h_sync_ext;
	
	is_80 <= mode_80col or is_80_in;
	
	v_sync <= v_sync_ext;
	
	-- PET vsync is always positive pulse
	pet_vsync <= v_sync_int;
	
	-----------------------------------------------------------------------------
	-- raster address calculations
	
	newline_p:process(last_line_of_char, mode_bitmap, rline_cnt0, is_double_int)
	begin
		new_line_vaddr <= '0';
		new_line_attr <= '0';
		
		if (rline_cnt0 = '1' or is_double_int = '1') then
			if (last_line_of_char = '1') then
				new_line_attr <='1';
			end if;
			if (last_line_of_char = '1' or mode_bitmap = '1') then
				new_line_vaddr <= '1';
			end if;
		end if;
	end process;
	
	AddrHold: process(qclk, last_line_of_screen, vid_addr, reset, dotclk) 
	begin
		if (reset ='1') then
			vid_addr_hold <= (others => '0');
		elsif (rising_edge(qclk) and dotclk(1 downto 0) = "11") then 
			if (last_vis_slot_of_line = '1') then
				if (last_line_of_screen = '1') then
					vid_addr_hold <= vid_base;
					attr_addr_hold <= attr_base;
				else
					if (new_line_attr = '1') then
						-- so tired of this...
						if (is_80 = '1' and interlace_int = '1' and mode_tv = '0') then
							attr_addr_hold <= attr_addr + va_offset + 1;
						else
							attr_addr_hold <= attr_addr + va_offset;
						end if;
					end if;
					if (new_line_vaddr = '1') then
						if (is_80 = '1' and interlace_int = '1' and mode_tv = '0') then
							vid_addr_hold <= vid_addr + va_offset + 1;
						else
							vid_addr_hold <= vid_addr + va_offset;
						end if;
					end if;
					-- alternate values on raster match
					if (is_raster_match = '1' and alt_match_vaddr = '1') then
						vid_addr_hold <= vid_base_alt;
					end if;
					if (is_raster_match = '1' and alt_match_attr = '1') then
						attr_addr_hold <= attr_base_alt;
					end if;
				end if;
				--new_line_attr_d <= new_line_attr;
				new_line_vaddr_d <= new_line_vaddr;
			end if;
		end if;
	end process;
	
	AddrCnt: process(x_start, vid_addr, vid_addr_hold, is_80, qclk, reset, dotclk)
	begin
		if (reset = '1') then
			vid_addr <= (others => '0');
			attr_addr <= (others => '0');
		elsif (rising_edge(qclk) and dotclk(1 downto 0) = "11") then --dotclk(1 downto 0) = "11") then
				if (x_start = '1') then
--					if (last_line_of_char = '0' 
--							or (rline_cnt0 = '1' and interlace_int = '1' and is_double_int = '0')) then
					if (new_line_attr = '0'
							or (interlace_int = '1')
							) then
						attr_addr <= attr_addr_hold;
					end if;
--					if ((mode_bitmap = '0' and last_line_of_char = '0') 
--							or (rline_cnt0 = '1' and interlace_int = '1' and is_double_int = '0')) then
					if (new_line_vaddr = '0'
							or (interlace_int = '1')
							) then
						vid_addr <= vid_addr_hold;
					end if;
				else
					if (sr_fetch_int = '1' ) then
						vid_addr <= vid_addr + 1;
						attr_addr <= attr_addr + 1;
					end if;
				end if;
		end if;
	end process;

	cam_p: process(crsr_address,vid_addr)
	begin
			if (vid_addr = crsr_address) then
				crsr_addr_match <= '1'; 
			else
				crsr_addr_match <= '0';
			end if;
	end process;

	-----------------------------------------------------------------------------
	-- sprite handling

	-- enables sprite fetch on the first 8 slots (8x4 accesses), when the correct sprite is enabled (sprite_active)
	-- sprite_fetch_active is set whenever sprite_fetch_idx matches a sprite active in the given rasterline
	fetch_sprite_en <= '1' when is_enable = '1' 
								-- and first_row = '1'
								and (interlace_int = '1' or rline_cnt0 = '0')
								and sprite_fetch_active = '1'
								and sprite_fetch_win = '1'
							else '0';

	-- these two are derived from the window functions in the general fetch timing
	-- sprite_ptr_window and sprite_data_window are alternate to char/attr/pixel fetch in off-screen areas
	sprite_ptr_fetch <= sprite_ptr_window and fetch_sprite_en;
	sprite_data_fetch <= sprite_data_window and fetch_sprite_en;	
	
	sprite_outcol_p: process(qclk, dotclk)
	begin
		
		if (falling_edge(qclk)) then -- and dotclk(0) = '0') then
			if (sprite_ison(0) = '1') then
				sprite_on <= '1';
				sprite_outcol <= sprite_outbits(0);
				sprite_onborder <= sprite_overborder(0);
				sprite_onraster <= sprite_overraster(0);
				sprite_no <= 0;
			elsif (sprite_ison(1) = '1') then
				sprite_on <= '1';
				sprite_outcol <= sprite_outbits(1);
				sprite_onborder <= sprite_overborder(1);
				sprite_onraster <= sprite_overraster(1);
				sprite_no <= 1;
			elsif (sprite_ison(2) = '1') then
				sprite_on <= '1';
				sprite_outcol <= sprite_outbits(2);
				sprite_onborder <= sprite_overborder(2);
				sprite_onraster <= sprite_overraster(2);
				sprite_no <= 2;
			elsif (sprite_ison(3) = '1') then
				sprite_on <= '1';
				sprite_outcol <= sprite_outbits(3);
				sprite_onborder <= sprite_overborder(3);
				sprite_onraster <= sprite_overraster(3);
				sprite_no <= 3;
			elsif (sprite_ison(4) = '1') then
				sprite_on <= '1';
				sprite_outcol <= sprite_outbits(4);
				sprite_onborder <= sprite_overborder(4);
				sprite_onraster <= sprite_overraster(4);
				sprite_no <= 4;
			elsif (sprite_ison(5) = '1') then
				sprite_on <= '1';
				sprite_outcol <= sprite_outbits(5);
				sprite_onborder <= sprite_overborder(5);
				sprite_onraster <= sprite_overraster(5);
				sprite_no <= 5;
			elsif (sprite_ison(6) = '1') then
				sprite_on <= '1';
				sprite_outcol <= sprite_outbits(6);
				sprite_onborder <= sprite_overborder(6);
				sprite_onraster <= sprite_overraster(6);
				sprite_no <= 6;
			elsif (sprite_ison(7) = '1') then
				sprite_on <= '1';
				sprite_outcol <= sprite_outbits(7);
				sprite_onborder <= sprite_overborder(7);
				sprite_onraster <= sprite_overraster(7);
				sprite_no <= 7;
			else
				sprite_on <= '0';
				sprite_outcol <= "00000";
				sprite_onborder <= '0';
				sprite_onraster <= '0';
				sprite_no <= 0;
			end if;
		end if;
	end process;


	spritesprite_p: process(qclk, collision_trigger_sprite_sprite, collision_accum_sprite_sprite)
	begin

		collision_sprite_sprite_none <= '0';
		if (collision_accum_sprite_sprite = "00000000") then
			collision_sprite_sprite_none <= '1';
		end if;
		
		if (falling_edge(qclk)) then -- and dotclk(0) = '0') then

			irq_sprite_sprite_trigger <= '0';
			
			outer_l: for i in 0 to 7 loop
			
				collision_trigger_sprite_sprite(i) <= '0';
				
				inner_l: for j in 0 to 7 loop
				
					if (i /= j) then
					
						if (sprite_ison(i) = '1' and sprite_ison(j) = '1') then
						
							collision_trigger_sprite_sprite(i) <= '1';
							
							if (collision_sprite_sprite_none = '1') then 
								irq_sprite_sprite_trigger <= '1';
							end if;
						end if;
					end if;
				end loop;
			end loop;
		end if;
	end process;
	
	sdo_p: process(regsel, crtc_sel, crtc_is_data, sprite_dout)
	begin
	
		sprite_sel <= (others => '0');
		sprite_d <= (others => '0');
		
		if (crtc_sel = '1' and crtc_is_data = '1') then
			case regsel(6 downto 2) is
			when "01100" =>	-- sprite 0
				sprite_sel(0) <= '1';
				sprite_d <= sprite_dout(0);
			when "01101" =>	-- sprite 1
				sprite_sel(1) <= '1';
				sprite_d <= sprite_dout(1);
			when "01110" =>	-- sprite 2
				sprite_sel(2) <= '1';
				sprite_d <= sprite_dout(2);
			when "01111" =>	-- sprite 3
				sprite_sel(3) <= '1';
				sprite_d <= sprite_dout(3);
			when "10000" =>	-- sprite 4
				sprite_sel(4) <= '1';
				sprite_d <= sprite_dout(4);
			when "10001" =>	-- sprite 5
				sprite_sel(5) <= '1';
				sprite_d <= sprite_dout(5);
			when "10010" =>	-- sprite 6
				sprite_sel(6) <= '1';
				sprite_d <= sprite_dout(6);
			when "10011" =>	-- sprite 7
				sprite_sel(7) <= '1';
				sprite_d <= sprite_dout(7);
			when others =>
			end case;
		end if;
	end process;

	fetch_idx_p: process(qclk, dotclk, h_zero, sprite_fetch_idx, h_enable)
	begin
	-- start fetching sprite immediately after end of visible area
		if (h_enable = '1') then
		--if (h_enable = '0') then
			sprite_fetch_idx <= 0;
			sprite_fetch_win <= '0';
			sprite_fetch_done <= '0';
		elsif (falling_edge(qclk) and dotclk = "1111") then
			if (sprite_fetch_done = '0') then
				if (sprite_fetch_win = '0') then
					sprite_fetch_win <= '1';
				elsif(sprite_fetch_idx = 7) then
					sprite_fetch_win <= '0';
					sprite_fetch_done <= '1';
				else
					sprite_fetch_idx <= sprite_fetch_idx + 1;
				end if;
			end if;
		end if;
		
		sprite_fetch_idx_v <= std_logic_vector(to_unsigned(sprite_fetch_idx, sprite_fetch_idx_v'length));
	end process;
	
	fetchactive_p: process(qclk, x_addr, sprite_fetch_idx, sprite_ptr_fetch, sprite_data_fetch, fetch_ce, sprite_data_ptr, sprite_base,
			sprite_enabled, sprite_fetch_offset)
	begin
		sprite_fetch_active <= sprite_enabled(sprite_fetch_idx);

		sprite_fetch_ptr(5 downto 0) <= sprite_fetch_offset(sprite_fetch_idx);			
		sprite_fetch_ptr(13 downto 6) <= sprite_data_ptr;
		sprite_fetch_ptr(15 downto 14) <= sprite_base(7 downto 6);
				
		if (falling_edge(qclk)) then
			if (fetch_ce = '1' and sprite_ptr_fetch = '1') then
				sprite_data_ptr <= VRAM_D;
			end if;
		end if;

		sprite_fetch_ce <= "00000000";
		case (sprite_fetch_idx) is
		when 0 =>       sprite_fetch_ce(0) <= sprite_data_fetch and fetch_ce;
		when 1 =>       sprite_fetch_ce(1) <= sprite_data_fetch and fetch_ce;
		when 2 =>       sprite_fetch_ce(2) <= sprite_data_fetch and fetch_ce;
		when 3 =>       sprite_fetch_ce(3) <= sprite_data_fetch and fetch_ce;
		when 4 =>       sprite_fetch_ce(4) <= sprite_data_fetch and fetch_ce;
		when 5 =>       sprite_fetch_ce(5) <= sprite_data_fetch and fetch_ce;
		when 6 =>       sprite_fetch_ce(6) <= sprite_data_fetch and fetch_ce;
		when 7 =>       sprite_fetch_ce(7) <= sprite_data_fetch and fetch_ce;
		end case;

	end process;

	sprite0: Sprite
	port map (
		phi2,
		sprite_sel(0),
		crtc_rwb,
		regsel(1 downto 0),
		CPU_D,
		sprite_dout(0),
		sprite_fgcol(0),
		col_bg0,
		sprite_mcol1,
		sprite_mcol2,
		sprite_fetch_offset(0),
		sprite_fetch_ce(0),
		qclk,
		dotclk,
		VRAM_D,
		h_enable,
		h_zero,
		v_zero,
		x_addr,
		y_addr_d,
		is_double_int,
		interlace_int,
		is_80,
		mode_tv,
		is_shift40,
		is_shift80,
		vsync_pos(0),
		sprite_enabled(0),
		sprite_ison(0),
		sprite_overraster(0),
		sprite_overborder(0),
		sprite_outbits(0),
		reset
	);

	sprite1: Sprite
	port map (
		phi2,
		sprite_sel(1),
		crtc_rwb,
		regsel(1 downto 0),
		CPU_D,
		sprite_dout(1),
		sprite_fgcol(1),
		col_bg0,
		sprite_mcol1,
		sprite_mcol2,
		sprite_fetch_offset(1),
		sprite_fetch_ce(1),
		qclk,
		dotclk,
		VRAM_D,
		h_enable,
		h_zero,
		v_zero,
		x_addr,
		y_addr_d,
		is_double_int,
		interlace_int,
		is_80,
		mode_tv,
		is_shift40,
		is_shift80,
		vsync_pos(0),
		sprite_enabled(1),
		sprite_ison(1),
		sprite_overraster(1),
		sprite_overborder(1),
		sprite_outbits(1),
		reset
	);

	sprite2: Sprite
	port map (
		phi2,
		sprite_sel(2),
		crtc_rwb,
		regsel(1 downto 0),
		CPU_D,
		sprite_dout(2),
		sprite_fgcol(2),
		col_bg0,
		sprite_mcol1,
		sprite_mcol2,
		sprite_fetch_offset(2),
		sprite_fetch_ce(2),
		qclk,
		dotclk,
		VRAM_D,
		h_enable,
		h_zero,
		v_zero,
		x_addr,
		y_addr_d,
		is_double_int,
		interlace_int,
		is_80,
		mode_tv,
		is_shift40,
		is_shift80,
		vsync_pos(0),
		sprite_enabled(2),
		sprite_ison(2),
		sprite_overraster(2),
		sprite_overborder(2),
		sprite_outbits(2),
		reset
	);

	sprite3: Sprite
	port map (
		phi2,
		sprite_sel(3),
		crtc_rwb,
		regsel(1 downto 0),
		CPU_D,
		sprite_dout(3),
		sprite_fgcol(3),
		col_bg0,
		sprite_mcol1,
		sprite_mcol2,
		sprite_fetch_offset(3),
		sprite_fetch_ce(3),
		qclk,
		dotclk,
		VRAM_D,
		h_enable,
		h_zero,
		v_zero,
		x_addr,
		y_addr_d,
		is_double_int,
		interlace_int,
		is_80,
		mode_tv,
		is_shift40,
		is_shift80,
		vsync_pos(0),
		sprite_enabled(3),
		sprite_ison(3),
		sprite_overraster(3),
		sprite_overborder(3),
		sprite_outbits(3),
		reset
	);

	sprite4: Sprite
	port map (
		phi2,
		sprite_sel(4),
		crtc_rwb,
		regsel(1 downto 0),
		CPU_D,
		sprite_dout(4),
		sprite_fgcol(4),
		col_bg0,
		sprite_mcol1,
		sprite_mcol2,
		sprite_fetch_offset(4),
		sprite_fetch_ce(4),
		qclk,
		dotclk,
		VRAM_D,
		h_enable,
		h_zero,
		v_zero,
		x_addr,
		y_addr_d,
		is_double_int,
		interlace_int,
		is_80,
		mode_tv,
		is_shift40,
		is_shift80,
		vsync_pos(0),
		sprite_enabled(4),
		sprite_ison(4),
		sprite_overraster(4),
		sprite_overborder(4),
		sprite_outbits(4),
		reset
	);

	sprite5: Sprite
	port map (
		phi2,
		sprite_sel(5),
		crtc_rwb,
		regsel(1 downto 0),
		CPU_D,
		sprite_dout(5),
		sprite_fgcol(5),
		col_bg0,
		sprite_mcol1,
		sprite_mcol2,
		sprite_fetch_offset(5),
		sprite_fetch_ce(5),
		qclk,
		dotclk,
		VRAM_D,
		h_enable,
		h_zero,
		v_zero,
		x_addr,
		y_addr_d,
		is_double_int,
		interlace_int,
		is_80,
		mode_tv,
		is_shift40,
		is_shift80,
		vsync_pos(0),
		sprite_enabled(5),
		sprite_ison(5),
		sprite_overraster(5),
		sprite_overborder(5),
		sprite_outbits(5),
		reset
	);

	sprite6: Sprite
	port map (
		phi2,
		sprite_sel(6),
		crtc_rwb,
		regsel(1 downto 0),
		CPU_D,
		sprite_dout(6),
		sprite_fgcol(6),
		col_bg0,
		sprite_mcol1,
		sprite_mcol2,
		sprite_fetch_offset(6),
		sprite_fetch_ce(6),
		qclk,
		dotclk,
		VRAM_D,
		h_enable,
		h_zero,
		v_zero,
		x_addr,
		y_addr_d,
		is_double_int,
		interlace_int,
		is_80,
		mode_tv,
		is_shift40,
		is_shift80,
		vsync_pos(0),
		sprite_enabled(6),
		sprite_ison(6),
		sprite_overraster(6),
		sprite_overborder(6),
		sprite_outbits(6),
		reset
	);

	sprite7: Sprite
	port map (
		phi2,
		sprite_sel(7),
		crtc_rwb,
		regsel(1 downto 0),
		CPU_D,
		sprite_dout(7),
		sprite_fgcol(7),
		col_bg0,
		sprite_mcol1,
		sprite_mcol2,
		sprite_fetch_offset(7),
		sprite_fetch_ce(7),
		qclk,
		dotclk,
		VRAM_D,
		h_enable,
		h_zero,
		v_zero,
		x_addr,
		y_addr_d,
		is_double_int,
		interlace_int,
		is_80,
		mode_tv,
		is_shift40,
		is_shift80,
		vsync_pos(0),
		sprite_enabled(7),
		sprite_ison(7),
		sprite_overraster(7),
		sprite_overborder(7),
		sprite_outbits(7),
		reset
	);
	
	-----------------------------------------------------------------------------
	-- replace discrete color circuitry of ultracpu 1.2b

	is_shift_p: process(is_80, mode_tv, dotclk, is_shift40, is_shift80)
	begin
		if (is_80 = '0') then
			is_shift <= not(dotclk(0)) and is_shift40;
		else
			is_shift <= not(dotclk(0)) and is_shift80;
		end if;
	end process;
	
	char_buf_p: process(qclk, chr_fetch_int, attr_fetch_int, pxl_fetch_int, VRAM_D, qclk, 
		mode_rev, sr_crsr, sr_blink, mode_attrib, mode_extended, attr_buf, cblink_active, uline_active)
	begin

		if (falling_edge(qclk)) then
			if (fetch_ce = '1' and chr_fetch_int = '1') then
				char_index_buf <= VRAM_D;
				sr_crsr <= crsr_addr_match and crsr_active;
			end if;			
		end if;
		
		if (falling_edge(qclk)) then
			if (fetch_ce = '1' and attr_fetch_int = '1') then
				attr_buf <= VRAM_D;
			end if;
		end if;

		if (falling_edge(qclk)) then
			if (fetch_ce = '1' and pxl_fetch_int = '1') then
				if (mode_bitmap = '1' or vis_line_of_char = '1') then
					pxl_buf <= VRAM_D;
				else
					pxl_buf <= (others => '0');
				end if;
			end if;
		end if;

		if (falling_edge(qclk)) then
			if (pxl_ce_00 = '1' and sr_fetch_int = '1') then
			
				sr_underline_p <= '0';
				sr_blink <= '0';
				if (mode_attrib = '0') then
				elsif (mode_extended = '0') then
					if (attr_buf(6) = '1' 			-- reverse attribute
						xor (attr_buf(4) = '1' and			-- blink
							cblink_active = '1')) then
						sr_blink <= '1';
					end if;
					if (attr_buf(5) = '1' and uline_active = '1') then
						sr_underline_p <= '1';
					end if;
				else -- extended == 1			
					if (attr_buf(5) = '0' and ((attr_buf(6) = '1') 			-- reverse attribute
						xor (attr_buf(4) = '1' and			-- blink
							cblink_active = '1'))) then
						sr_blink <= '1';
					end if;
				end if;
				
			end if;
		end if;
		
		sr_reverse_p <= mode_rev 
								xor sr_crsr
								xor sr_blink;

		if (falling_edge(qclk)) then
			if (pxl_ce_01 = '1' and sr_fetch_int = '1') then
				--attr_buf2 <= attr_buf;
				if (sr_underline_p = '1') then
					sr_buf <= "11111111";
				elsif (sr_reverse_p = '1') then
					sr_buf <= not(pxl_buf);
				else
					sr_buf <= pxl_buf;
				end if;
			end if;
		end if;
		
		if (falling_edge(qclk)) then
			if (pxl_ce_10 = '1' and (sr_fetch_int = '1')) then
				sr_attr <= attr_buf;
				sr(6 downto 0) <= sr_buf (6 downto 0);
				sr_odd <= '0';
				
				if (mode_attrib = '1' and mode_extended = '1') then
					-- multicolour (2-bit colour mode)
					is_outbit(1) <= sr_buf(7);
					is_outbit(0) <= sr_buf(6);
				else
					-- normal 1-bit colour modes
					is_outbit(1) <= '0';
					is_outbit(0) <= sr_buf(7);
				end if;
				
				case (bits_per_char) is
				when "0000" =>
					sr <= (others => '0');
					is_outbit(0) <= '0';
					is_outbit(1) <= '0';
				when "0001" =>
					sr <= (others => '0');
				when "0010" =>
					sr(5 downto 0) <= (others => '0');
				when "0011" =>
					sr(4 downto 0) <= (others => '0');
				when "0100" =>
					sr(3 downto 0) <= (others => '0');
				when "0101" =>
					sr(2 downto 0) <= (others => '0');
				when "0110" =>
					sr(1 downto 0) <= (others => '0');
				when "0111" =>
					sr(0 downto 0) <= (others => '0');
				when others =>
				end case;
				
			--elsif (dotclk(0) = '0' and (is_80 = '1' or dotclk(1) = '1')) then
			elsif (is_shift = '1') then
				sr(6 downto 1) <= sr(5 downto 0);
				sr(0) <= '1';
				sr_odd <= not(sr_odd);
				
				if (mode_attrib = '1' and mode_extended = '1') then
					if (sr_odd = '1') then
						-- multicolour (2-bit colour mode)
						is_outbit(1) <= sr(6);
						is_outbit(0) <= sr(5);
					end if;
				else
					is_outbit(1) <= '0';
					is_outbit(0) <= sr(6);
				end if;
			end if;
						
		end if;
	end process;
					
	rasterout_p: process(qclk, dotclk, sr, x_border, y_border, dispen, mode_extended, mode_attrib, sr_attr, col_border, is_outbit, 
		col_bg0, col_fg, col_bg1, col_bg2)
	begin
		if (falling_edge(qclk) and dotclk(0) = '0') then -- and (is_80 = '1' or dotclk(1) = '1')) then
			raster_isbg <= '0';
			if (mode_extended = '0' and mode_attrib = '0') then
				-- 2 COL MODE
				if is_outbit(0) = '0' then
					raster_outbit <= col_bg0;
					raster_isbg <= '1';
				else
					raster_outbit <= col_fg;
				end if;
			elsif (mode_extended = '0' and mode_attrib = '1') then
				-- ATTRIBUTE MODE (VDC)
				if (is_outbit(0) = '0') then
					raster_outbit <= col_bg0;
					raster_isbg <= '1';
				else
					raster_outbit <= sr_attr(3 downto 0);
				end if;
			elsif (mode_extended = '1' and mode_attrib = '0') then
				-- EXTENDED MODE (COLOUR PET)
				if is_outbit(0) = '0' then
					raster_outbit <= sr_attr(7 downto 4);
					raster_isbg <= '1';
				else
					raster_outbit <= sr_attr(3 downto 0);
				end if;
			else
				-- MULTICOLOUR MODE
				case (is_outbit) is
				when "00" =>
					raster_outbit <= sr_attr(7 downto 4);
					raster_isbg <= '1';
				when "01" =>
					raster_outbit <= col_bg1;
				when "10" =>
					raster_outbit <= col_bg2;
				when "11" =>
					raster_outbit <= sr_attr(3 downto 0);
				when others =>
					raster_outbit <= col_border;
				end case;
			end if;
		end if;
		
		if (rising_edge(qclk)) then
			raster_out(7) <= raster_outbit;
			raster_bg(7) <= raster_isbg;
			
			inner_l: for i in 0 to 6 loop

				if (h_shift = i) then
					raster_out(i) <= raster_outbit;
					raster_bg(i) <= raster_isbg;
				elsif (is_shift = '1') then
					raster_out(i) <= raster_out(i+1);
					raster_bg(i) <= raster_bg(i+1);
				end if;
			end loop;
				
		end if;
	end process;
					
	collision_p: process(qclk, phi2, collision_trigger_sprite_border, collision_trigger_sprite_raster, 
			collision_accum_sprite_raster, collision_accum_sprite_border, collision_trigger_sprite_sprite,
			collision_sprite_border_none, collision_sprite_raster_none)
	begin
	
		if (falling_edge(qclk)) then
			collision_sprite_raster_none <= '0';
			if (collision_accum_sprite_raster = "00000000") then
				collision_sprite_raster_none <= '1';
			end if;
			collision_sprite_border_none <= '0';
			if (collision_accum_sprite_border = "00000000") then
				collision_sprite_border_none <= '1';
			end if;
		end if;
		
		irq_sprite_raster_trigger <= '0';
		irq_sprite_border_trigger <= '0';

		coll_l: for i in 0 to 7 loop
			if (collision_sprite_border_none = '1' and collision_trigger_sprite_border(i) = '1') then
				irq_sprite_border_trigger <= '1';
			end if;
		
			if (collision_trigger_sprite_border(i) = '1') then
				collision_accum_sprite_border(i) <= '1';				
			elsif (falling_edge(phi2)) then
			
				if (crtc_sel = '1' and crtc_rwb = '1' and crtc_is_data = '1') then
					if (regsel = x"2b") then
						-- reading the sprite-border collision register
						collision_accum_sprite_border(i) <= '0';
					end if;
				end if;
			end if;
			
			if (collision_sprite_raster_none = '1' and collision_trigger_sprite_raster(i) = '1') then
				irq_sprite_raster_trigger <= '1';
			end if;
			
			if (collision_trigger_sprite_sprite(i) = '1') then
				collision_accum_sprite_sprite(i) <= '1';
			elsif (falling_edge(phi2)) then
				if (crtc_sel = '1' and crtc_rwb = '1' and crtc_is_data = '1') then
					if (regsel = x"2c") then
						-- reading the sprite-sprite collision register
						collision_accum_sprite_sprite(i) <= '0';
					end if;
				end if;
			end if;
			
			if (collision_trigger_sprite_raster(i) = '1') then
				collision_accum_sprite_raster(i) <= '1';
			elsif (falling_edge(phi2)) then
				if (crtc_sel = '1' and crtc_rwb = '1' and crtc_is_data = '1') then
					if (regsel = x"2d") then
						-- reading the sprite-raste collision register
						collision_accum_sprite_raster(i) <= '0';
					end if;
				end if;
			end if;
			
		end loop;
	end process;
	
	vid_mixer_p: process (qclk, dotclk, dena_int, pal_alt, reset)
	begin
		if (dena_int = '0' or reset = '1') then
			vid_out_idx <= (others => '0');
			vid_out_blank <= '1';
			
		elsif (falling_edge(qclk) and dotclk(0) = '1') then -- and (is_80 = '1' or dotclk(1) = '1')) then

			collision_trigger_sprite_border <= (others => '0');
			collision_trigger_sprite_raster <= (others => '0');
			
			vid_out_blank <= '0';
			
			if (x_border = '1' or y_border = '1' or dispen = '0') then
				if (sprite_on = '1' and sprite_onborder = '1') then
					-- sprite on top of border
					vid_out_idx <= sprite_outcol;
					collision_trigger_sprite_border(sprite_no) <= '1';
				else
					-- BORDER
					vid_out_idx(3 downto 0) <= col_border;
					vid_out_idx(4) <= pal_alt;
				end if;
			elsif (sprite_on = '1' and (raster_bg(0) = '1' or sprite_onraster = '1')) then
				-- sprite on top of raster
				vid_out_idx <= sprite_outcol;
				if (raster_bg(0) = '0') then
					collision_trigger_sprite_raster(sprite_no) <= '1';
				end if;
				
			elsif (is_80 = '1' or dotclk(0) = '1') then
				-- raster
				vid_out_idx(3 downto 0) <= raster_out(0);
				vid_out_idx(4) <= pal_alt;
			end if;			
		end if;
	end process;
	
	-----------------------------------------------------------------------------
	-- address mixer
	-- mem_addr = hires fetch or chr fetch (i.e. NOT charrom pxl fetch)
	
	--when sprite_ptr_fetch = '1' else
	--when sprite_data_fetch = '1' else
	
	a_out(2 downto 0) <= 
							sprite_fetch_idx_v(2 downto 0)	when sprite_ptr_fetch = '1' else
							sprite_fetch_ptr(2 downto 0)		when sprite_data_fetch = '1' else
							attr_addr(2 downto 0) 				when attr_fetch_int = '1' else
							rcline_cnt(2 downto 0) 				when crom_fetch_int = '1' else
							vid_addr(2 downto 0);

	a_out(3) <= 
							'1'										when sprite_ptr_fetch = '1' else
							sprite_fetch_ptr(3)					when sprite_data_fetch = '1' else
							attr_addr(3)			 				when attr_fetch_int = '1' else
							rcline_cnt(3) 			 				when crom_fetch_int = '1' else
							vid_addr(3);

	a_out(7 downto 4) <= 
							"1111"									when sprite_ptr_fetch = '1' else
							sprite_fetch_ptr(7 downto 4)		when sprite_data_fetch = '1' else
							attr_addr(7 downto 4)				when attr_fetch_int = '1' else
							char_index_buf(3 downto 0) 		when crom_fetch_int = '1' else
							vid_addr(7 downto 4);

	a_out(11 downto 8) <= 
							sprite_base(3 downto 0)				when sprite_ptr_fetch = '1' else
							sprite_fetch_ptr(11 downto 8)		when sprite_data_fetch = '1' else
							attr_addr(11 downto 8)				when attr_fetch_int = '1' else
							char_index_buf(7 downto 4) 		when crom_fetch_int = '1' else
							vid_addr(11 downto 8);

	a_out(12) 		<= 
							sprite_base(4)							when sprite_ptr_fetch = '1' else
							sprite_fetch_ptr(12)					when sprite_data_fetch = '1' else
							attr_addr(12)							when attr_fetch_int = '1' else
							is_graph									when crom_fetch_int = '1' else
							vid_addr(12);

	a_out(15 downto 13) <= 
							sprite_base(7 downto 5)				when sprite_ptr_fetch = '1' else
							sprite_fetch_ptr(15 downto 13)	when sprite_data_fetch = '1' else
							attr_addr(15 downto 13)				when attr_fetch_int = '1' else
							crom_base(7 downto 5) 				when crom_fetch_int = '1' else
							vid_addr(15 downto 13);
							
	A <= a_out;
	
	-----------------------------------------------------------------------------
	-- output sr control

	en_p: process(nsrload, qclk, enable, h_enable, v_enable, interlace_int, rline_cnt0)
	begin
		enable <= h_enable and v_enable
				and (interlace_int or not(rline_cnt0)); -- comment to DEBUG interlace timing
		dena_int <= enable;
	end process;

	--------------------------------------------
	-- raster interrupt handling
	
	RasterMatch: process(h_zero, raster_match, y_addr)
	begin
		
		if (rising_edge(h_zero)) then
			is_raster_match <= '0';
			
			if (mode_tv = '0') then
				if (interlace_int = '1') then
					if (raster_match = y_addr) then
						is_raster_match <= '1';
					end if;
				else
					if (raster_match(9 downto 1) = y_addr(9 downto 1)
							and y_addr(0) = '1') then
						is_raster_match <= '1';
					end if;
				end if;
			else
				if (raster_match(9 downto 1) = y_addr(8 downto 0)) then
					is_raster_match <= '1';
				end if;
			end if;
			
			is_raster_match_d <= is_raster_match;
		end if;
		
	end process;
	
	RasterIrq: process(phi2, crtc_reg, crtc_sel, crtc_rs, reset)
	begin
		if (falling_edge(phi2)) then
			
			if (is_raster_match = '0') then
				irq_raster_ack <= '0';
			end if;

			if (crtc_sel = '1' and crtc_is_data = '1' and regsel = x"24"
					and crtc_rwb = '0'
					) then
				if (CPU_D(0) = '1') then
					irq_raster_ack <= '1';
				end if;
			end if;
			
		end if;

		-- FIXME: if you ack the interrupt while it is still active, this might immediately trigger again 
		if (reset = '1') then
			irq_raster <= '0';
		elsif (falling_edge(phi2)) then
			if (irq_raster_ack = '1') then
				irq_raster <= '0';
			elsif (is_raster_match = '1') then
				irq_raster <= '1';
			end if;
		end if;
		
	end process;
	
	sprite_irq_p: process(phi2, irq_sprite_sprite_trigger, irq_sprite_border_trigger, irq_sprite_raster_trigger)
	begin
	
		if (irq_sprite_raster_trigger = '1') then
			irq_sprite_raster <= '1';
		elsif (falling_edge(phi2)) then
			if (crtc_sel = '1' and crtc_is_data = '1' and regsel = x"24" and crtc_rwb = '0') then
				if (CPU_D(1) = '1') then
					irq_sprite_raster <= '0';
				end if;
			end if;
		end if;

		if (irq_sprite_sprite_trigger = '1') then
			irq_sprite_sprite <= '1';
		elsif (falling_edge(phi2)) then
			if (crtc_sel = '1' and crtc_is_data = '1' and regsel = x"24" and crtc_rwb = '0') then
				if (CPU_D(2) = '1') then
					irq_sprite_sprite <= '0';
				end if;
			end if;
		end if;
		
		if (irq_sprite_border_trigger = '1') then
			irq_sprite_border <= '1';
		elsif (falling_edge(phi2)) then
			if (crtc_sel = '1' and crtc_is_data = '1' and regsel = x"24" and crtc_rwb = '0') then
				if (CPU_D(3) = '1') then
					irq_sprite_border <= '0';
				end if;
			end if;
		end if;

	end process;
	
	irq_out_int <= (irq_raster and irq_raster_en)
				 or (irq_sprite_sprite and irq_sprite_sprite_en) 
				 or (irq_sprite_raster and irq_sprite_raster_en) 
				 or (irq_sprite_border and irq_sprite_border_en);
	
	irq_out <= irq_out_int;
	
	--------------------------------------------
	-- alt modes
	altmodes_p: process(qclk)
	begin
	
		if (falling_edge(qclk)) then
			
			if (v_zero = '1' or mode_set_flag = '1') then
				mode_attrib <= mode_attrib_reg;
				mode_extended <= mode_extended_reg;
				mode_bitmap <= mode_bitmap_reg;
			elsif (is_raster_match_d = '1') then
				if (alt_match_modes = '1') then
					mode_attrib <= mode_attrib_alt;
					mode_extended <= mode_extended_alt;
					mode_bitmap <= mode_bitmap_alt;
				end if;
			end if;
			if (v_zero = '1' or mode_set_hsync = '1') then
				h_shift <= h_shift_reg;
				h_extborder <= h_extborder_reg;
			elsif (is_raster_match_d = '1') then
				if (alt_match_hsync = '1') then
					h_shift <= h_shift_alt;
					h_extborder <= h_extborder_alt;
				end if;
			end if;
			if (v_zero = '1') then
				pal_alt <= '0';
			elsif (is_raster_match = '1') then
				if (alt_match_palette = '1') then
					pal_alt <= '1';
				end if;
			end if;
		end if;
	end process;

	Writemode_p: process(phi2, h_zero, regsel, crtc_sel, crtc_is_data, reset)
	begin
		if (h_zero = '1') then
			mode_set_flag <= '0';
			mode_set_hsync <= '0';
		elsif (falling_edge(phi2)) then
			if (crtc_sel = '1' and crtc_is_data = '1' and (regsel = x"20")
					and crtc_rwb = '0'	
					) then
				mode_set_flag <= '1';
			end if;
			if (crtc_sel = '1' and crtc_is_data = '1' and (regsel = x"19")
					and crtc_rwb = '0'	-- note this seems to break display...???
					) then
				mode_set_hsync <= '1';
			end if;
		end if;
	end process;

	--------------------------------------------
	-- palette handling as block RAM

	palette_p: palette_bram
	port map (
		pbr_clkA,
		pbr_enA,
		pbr_weA,
		pbr_addrA,
		pbr_diA,
		pbr_doA,
		
		pbr_clkB,
		pbr_enB,
		pbr_weB,
		pbr_addrB,
		pbr_diB,
		pbr_doB
	);
	
	pbr_diB <= "00000000";
	
	-- block ram uses rising edge on clk signal
	pbr_clkA <= not(dotclk(1));
	
	pbr_enA <= '1' when crtc_sel = '1' 
							and crtc_is_data = '1' 
							and regsel(7 downto 3) = "01011"
					else '0';
					
	pbr_weA <= not(crtc_rwb);
	
	pbr_addrA(2 downto 0) <= regsel(2 downto 0);
	pbr_addrA(3) <= pal_sel;
	pbr_addrA(4) <= mode_altreg;
	
	pbr_diA <= CPU_D;
	
	pbr_clkB <= qclk;
	pbr_enB <= '1';
	pbr_weB <= '0';
	pbr_addrB <= vid_out_idx;
	
	
	vid_out(1 downto 0) <= "00" when vid_out_blank = '1' else pbr_doB(1 downto 0);	-- BLUE
	vid_out(3 downto 2) <= "00" when vid_out_blank = '1' else pbr_doB(4 downto 3);  -- GREEN
	vid_out(5 downto 4) <= "00" when vid_out_blank = '1' else pbr_doB(7 downto 6); 	-- RED

	-- potential DEBUG
--	vid_out(0) <= '0' when vid_out_blank = '1' else last_line_of_char;
--	vid_out(1) <= '0' when vid_out_blank = '1' else rline_cnt0;
--	vid_out(4) <= '0' when vid_out_blank = '1' else new_line_vaddr;
--	vid_out(5) <= '0' when vid_out_blank = '1' else last_vis_slot_of_line;
	
	
	
	--------------------------------------------
	-- crtc register emulation
	-- only 8/9 rows per char are emulated right now

	dbg_out <= h_zero; --'0';

	is_double_int <= mode_double or mode_tv;
	interlace_int <= mode_interlace or mode_tv;

	crtc_rs_int(1 downto 0) <= crtc_rs(1 downto 0);
	crtc_rs_int(6 downto 2) <= crtc_rs(6 downto 2) when mode_regmap_int = '1' 
										else "00000";
	crtc_rs_int(7) <= '0';
	
	crtc_mapped <= '0' when mode_regmap_int = '0' or crtc_rs(6 downto 2) = "00000"		-- lowest 4 addresses not mapped
					else '1';												-- anythings else is mapped

	regsel <= crtc_reg when crtc_mapped = '0'
				else crtc_rs_int;

	crtc_is_data <= '1' when crtc_rs_int(1 downto 0) = "01" 
								or crtc_rs_int(1 downto 0) = "11"
								or crtc_mapped = '1'
				else '0';
	
	mode_regmap <= mode_regmap_int;
	
	regfile: process(phi2, CPU_D, crtc_sel, crtc_rs, crtc_rwb, reset) 
	begin
		if (reset = '1') then
			crtc_reg <= (others => '0');
		elsif (falling_edge(phi2) and crtc_sel = '1') then
		
			if (crtc_rs_int = x"03") then
				-- if accessing address 3, auto-increment the register number
				crtc_reg(6 downto 0) <= crtc_reg(6 downto 0) + 1;
				
			elsif ((crtc_rs_int = x"00" or crtc_rs_int = x"02") and crtc_rwb = '0' ) then
				-- writing to either address 0 or 2 sets the register number
				crtc_reg(6 downto 0) <= CPU_D(6 downto 0);
			end if;
		end if;
	end process;
	
	
	reg9: process(phi2, CPU_D, crtc_sel, crtc_rs, crtc_rwb, crtc_is_data, regsel, reset) 
	begin
		if (falling_edge(phi2)) then
 		 if (reset = '1') then
			mode_tv <= '0';
			mode_60hz <= '0';
			mode_out <= '0';
			mode_rev <= '0';
			cblink_mode <= '0';
			mode_attrib_reg <= '0';
			mode_extended_reg <= '0';
			mode_bitmap_reg <= '0';
			mode_attrib_alt <= '0';
			mode_extended_alt <= '0';
			mode_bitmap_alt <= '0';
			mode_pet <= '1';
			mode_double <= '0';
			mode_interlace <= '0';
			mode_80col <= '0';
			mode_altreg <= '0';
			mode_regmap_int <= '0';
			alt_match_modes <= '0';
			alt_match_hsync <= '0';
			alt_match_vaddr <= '0';
			alt_match_attr <= '0';
			alt_match_palette <= '0';
			alt_rc_cnt <= "0000";
			alt_set_rc <= '0';
			dispen <= '1';
			crsr_mode <= (others => '0');
			crsr_address <= (others => '0');
			rows_per_char <= "0111"; -- 7
			bits_per_char <= "1000"; -- 8
			vis_rows_per_char <= "1111"; -- 15
			slots_per_line <= "1010000";	-- 80
			hsync_pos <= x_default_offset; -- "0001101";	-- 13
			vsync_pos <= std_logic_vector(to_unsigned(y_default_offset,8));
			clines_per_screen <= "00011001";	-- 25
			attr_base <= x"d000";
			attr_base_alt <= x"d000";
			vid_base <= x"9000";
			vid_base_alt <= x"9000";
			crom_base <= x"00";
			col_fg <= "1111";
			col_bg0 <= "0000";
			col_bg1 <= "0000";
			col_bg2 <= "0000";
			col_border <= "0000";
			uline_scan <= (others => '0');
			h_extborder_alt <= '0';
			h_extborder_reg <= '0';
			v_extborder <= '0';
			h_shift_reg <= (others => '0');
			h_shift_alt <= (others => '0');
			v_shift <= (others => '0');
			va_offset <= (others => '0');
			raster_match <= (others => '0');
			irq_raster_en <= '0';
			irq_sprite_sprite_en <= '0';
			irq_sprite_border_en <= '0';
			irq_sprite_raster_en <= '0';
			sprite_mcol1 <= "0000";
			sprite_mcol1 <= "0000";
			sprite_base <= "10010111";
			pal_sel <= '0';
		elsif(
				crtc_sel = '1'
				and crtc_is_data = '1' 
				and crtc_rwb = '0'
				) then
			case (regsel) is
			when x"01" =>
				-- note: if pet compat, value written is doubled (as in the PET for 80 columns)
				if (mode_pet = '1' or is_80 = '0') then
					slots_per_line(6 downto 1) <= CPU_D(5 downto 0);
					slots_per_line(0) <= '0';
				else
					slots_per_line(6 downto 0) <= CPU_D(6 downto 0);
				end if;
			when x"05" => 
				-- mirror of R1 when regmap is set
				if (mode_regmap_int = '1') then
					-- note: if pet compat, value written is doubled (as in the PET for 80 columns)
					if (mode_pet = '1' or is_80 = '0') then
						slots_per_line(6 downto 1) <= CPU_D(5 downto 0);
						slots_per_line(0) <= '0';
					else
						slots_per_line(6 downto 0) <= CPU_D(6 downto 0);
					end if;
				end if;
			when x"06" => 
				clines_per_screen <= CPU_D;
			when x"08" =>
				-- b1: interlace, b0: double (if b1=1)
				mode_interlace <= CPU_D(1);
				mode_double <= CPU_D(0);
				if (mode_pet = '0') then
					mode_out <= CPU_D(4);
					mode_tv <= CPU_D(5);
					mode_60hz <= CPU_D(6);
					mode_80col <= CPU_D(7);
				end if;
--				if (mode_pet = '1') then
--					if (CPU_D(6) = '0') then
--						-- setup 
--						vsync_pos <= std_logic_vector(to_unsigned(y_default_offset,8));
--					else
--						vsync_pos <= std_logic_vector(to_unsigned(33,8));
--					end if;
--				end if;
			when x"09" =>
				rows_per_char <= CPU_D(3 downto 0);
				if (mode_pet = '1') then
					if (CPU_D(3) = '1') then
						vsync_pos <= std_logic_vector(to_unsigned(y_default_offset - 20,8));
						rows_per_char <= "1000";	-- limit to 8
					else
						vsync_pos <= std_logic_vector(to_unsigned(y_default_offset,8));
					end if;
				end if;
			when x"0a" =>
				crsr_start_scan <= CPU_D(4 downto 0);
				crsr_mode <= CPU_D(6 downto 5);
			when x"0b" => 
				crsr_end_scan <= CPU_D(4 downto 0);
			when x"0c" =>
				if (mode_altreg = '1') then
					vid_base_alt(14 downto 8) <= CPU_D(6 downto 0);
					if (mode_pet = '1') then
						vid_base_alt(15) <= not(CPU_D(7));
					else
						vid_base_alt(15) <= CPU_D(7);
					end if;
				else
					vid_base(14 downto 8) <= CPU_D(6 downto 0);
					if (mode_pet = '1') then
						vid_base(15) <= not(CPU_D(7));
					else
						vid_base(15) <= CPU_D(7);
					end if;
				end if;
			when x"0d" =>
				if (mode_altreg = '1') then
					vid_base_alt(7 downto 0) <= CPU_D;
				else
					vid_base(7 downto 0) <= CPU_D;
				end if;
			when x"0e" =>
				crsr_address(14 downto 8) <= CPU_D(6 downto 0);
				if (mode_pet = '1') then
					crsr_address(15) <= not(CPU_D(7));
				else
					crsr_address(15) <= CPU_D(7);
				end if;
			when x"0f" =>	-- R15
				crsr_address(7 downto 0) <= CPU_D;
			when x"14" =>	-- R20
				if (mode_altreg = '1') then
					attr_base_alt(15 downto 8) <= CPU_D;
				else
					attr_base(15 downto 8) <= CPU_D;
				end if;
			when x"15" =>	-- R21
				if (mode_altreg = '1') then
					attr_base_alt(7 downto 0) <= CPU_D;
				else
					attr_base(7 downto 0) <= CPU_D;
				end if;
			when x"16" => 	-- R22
				bits_per_char <= CPU_D(3 downto 0);
			when x"17" => 	-- R23
				vis_rows_per_char <= CPU_D(3 downto 0);
			when x"18" =>	-- R24
				v_shift <= CPU_D(3 downto 0);
				v_extborder <= CPU_D(4);
				cblink_mode <= CPU_D(5);
				mode_rev <= CPU_D(6);
			when x"19" =>	-- R25
				if (mode_altreg = '1') then
					h_shift_alt <= CPU_D(2 downto 0);
					h_extborder_alt <= CPU_D(4);
				else
					h_shift_reg <= CPU_D(2 downto 0);
					h_extborder_reg <= CPU_D(4);
				end if;
			when x"1a" => 	-- R26
				col_fg <= CPU_D(7 downto 4);
				col_bg0 <= CPU_D(3 downto 0);
			when x"1b" => -- R27
				va_offset <= CPU_D;
			when x"1c" => 	-- R28
				crom_base <= CPU_D;
			when x"1d" => 	-- R29
				uline_scan <= CPU_D(4 downto 0);
			when x"1e" =>	-- R30
				raster_match(7 downto 0) <= CPU_D;
			when x"1f" =>	-- R31
				raster_match(9 downto 8) <= CPU_D(1 downto 0);
			when x"20" =>	-- R32 (was: R39)
				mode_attrib_reg <= CPU_D(0);
				mode_bitmap_reg <= CPU_D(1);
				mode_extended_reg <= CPU_D(2);
				dispen <= CPU_D(4);
				pal_sel <= CPU_D(5);
				mode_regmap_int <= CPU_D(6);
				mode_pet <= CPU_D(7);
			when x"21" => 	-- R33 (was: R40)
				col_bg1 <= CPU_D(3 downto 0);
				col_bg2 <= CPU_D(7 downto 4);
			when x"22" =>	-- R34 (was: R41)
				col_border <= CPU_D(3 downto 0);
			when x"23" =>	-- R35 (was: R42)
				irq_raster_en <= CPU_D(0);
				irq_sprite_raster_en <= CPU_D(1);
				irq_sprite_sprite_en <= CPU_D(2);
				irq_sprite_border_en <= CPU_D(3);
			when x"24" =>	-- R36 (was: R43 / 2b)
				-- IRQ status
			when x"25" => 	-- R37
				-- read sync status
			when x"26" =>	-- R38 (was R44)
				-- horizontal sync
				hsync_pos <= CPU_D(6 downto 0);
			when x"27" =>	-- R39 (was R45)
				vsync_pos <= CPU_D;
			when x"28" =>	-- R40 (was R46) (alternate control I)
				mode_altreg <= CPU_D(0);
				mode_bitmap_alt <= CPU_D(1);
				mode_attrib_alt <= CPU_D(2);
				mode_extended_alt <= CPU_D(3);
				alt_match_palette <= CPU_D(4);
				alt_match_modes <= CPU_D(5);
				alt_match_attr <= CPU_D(6);
				alt_match_vaddr <= CPU_D(7);				
			when x"29" =>	-- R41 (was R47) (alternate control II)
				alt_rc_cnt <= CPU_D(3 downto 0);
				alt_match_hsync <= CPU_D(6);
				alt_set_rc <= CPU_D(7);
			when x"2a" =>	-- R42 (was R88)
				sprite_base <= CPU_D;
			when x"2b" =>	-- R43 (was R89 / 59)
				-- sprite border collisions
			when x"2c" =>	-- R44 (was R90 / 5a)
				-- sprite sprite collisions
			when x"2d" =>	-- R45 (was R91 / 5b)
				-- sprite raster collisions
			when x"2e" =>	-- R46 (was R92 / 5c)
				sprite_mcol1 <= CPU_D(3 downto 0);
			when x"2f" =>	-- R47 (was R93)
				sprite_mcol2 <= CPU_D(3 downto 0);
			--
			-- R48-R79 (x"30" - x"4f") are decoded separately in the sprites section
			--
			when x"50" =>	-- R80
				sprite_fgcol(0) <= CPU_D(3 downto 0);
			when x"51" =>	-- R81
				sprite_fgcol(1) <= CPU_D(3 downto 0);
			when x"52" =>	-- R82
				sprite_fgcol(2) <= CPU_D(3 downto 0);
			when x"53" =>	-- R83
				sprite_fgcol(3) <= CPU_D(3 downto 0);
			when x"54" =>	-- R84
				sprite_fgcol(4) <= CPU_D(3 downto 0);
			when x"55" =>	-- R85
				sprite_fgcol(5) <= CPU_D(3 downto 0);
			when x"56" =>	-- R86
				sprite_fgcol(6) <= CPU_D(3 downto 0);
			when x"57" =>	-- R87
				sprite_fgcol(7) <= CPU_D(3 downto 0);
			--
			-- R88 - R95 are reserved for palette access, see palette_bram and related signals
			--	
			when others =>
				null;
			end case;
		 end if;
		end if;
	end process;

	readreg: process(crtc_rwb, crtc_sel, crtc_rs_int, crtc_is_data, crtc_reg, regsel, reset) 
	begin
		if (reset = '1') then
			vd_out <= (others => '0');
			y_addr_latch <= (others => '0');
		else 
			vd_out <= (others => '0');
			
			if	(crtc_sel = '1'
				and crtc_rwb = '1'
				) then
				
				if (crtc_rs_int = x"02") then
					vd_out <= crtc_reg;
				elsif (crtc_rs_int = x"00") then
					-- TODO: status register at address 0
				elsif (crtc_is_data = '1') then
					
					case (regsel) is
					when x"01" =>
						-- note: if upet compat, value written is doubled (as in the PET for 80 columns)
						if (mode_pet = '1' or is_80 = '0') then
							vd_out(5 downto 0) <= slots_per_line(6 downto 1);
						else
							vd_out(6 downto 0) <= slots_per_line(6 downto 0);
						end if;
					when x"05" =>
						-- mirrors R1 for memory-mapped mode
						if (mode_regmap_int = '1') then
							-- note: if upet compat, value written is doubled (as in the PET for 80 columns)
							if (mode_pet = '1' or is_80 = '0') then
								vd_out(5 downto 0) <= slots_per_line(6 downto 1);
							else
								vd_out(6 downto 0) <= slots_per_line(6 downto 0);
							end if;
						end if;
					when x"06" =>
						vd_out <= clines_per_screen;
					when x"08" =>
						vd_out(0) <= mode_double;
						vd_out(1) <= mode_interlace;
						vd_out(4) <= mode_out;
						vd_out(5) <= mode_tv;
						vd_out(6) <= mode_60hz;
						vd_out(7) <= mode_80col;
					when x"09" =>
						vd_out(3 downto 0) <= rows_per_char;
					when x"0a" =>
						vd_out(4 downto 0) <= crsr_start_scan;
						vd_out(6 downto 5) <= crsr_mode;
					when x"0b" =>
						vd_out(4 downto 0) <= crsr_end_scan;
					when x"0c" =>
						if (mode_altreg = '1') then
							vd_out(6 downto 0) <= vid_base_alt(14 downto 8);
							if (mode_pet = '1') then
								vd_out(7) <= not(vid_base_alt(15));
							else
								vd_out(7) <= vid_base_alt(15);
							end if;
						else
							vd_out(6 downto 0) <= vid_base(14 downto 8);
							if (mode_pet = '1') then
								vd_out(7) <= not(vid_base(15));
							else
								vd_out(7) <= vid_base(15);
							end if;
						end if;
					when x"0d" =>
						if (mode_altreg = '1') then
							vd_out <= vid_base_alt(7 downto 0);
						else
							vd_out <= vid_base(7 downto 0);
						end if;
					when x"0e" =>
						vd_out(6 downto 0) <= crsr_address(14 downto 8);
						if (mode_pet = '1') then
							vd_out(7) <= not(crsr_address(15));
						else
							vd_out(7) <= crsr_address(15);
						end if;
					when x"0f" =>	-- R15
						vd_out <= crsr_address(7 downto 0);
					when x"14" =>	-- R20
						if (mode_altreg = '1') then
							vd_out <= attr_base_alt(15 downto 8);
						else 
							vd_out <= attr_base(15 downto 8);
						end if;
					when x"15" =>	-- R21
						if (mode_altreg = '1') then
							vd_out <= attr_base_alt(7 downto 0);
						else
							vd_out <= attr_base(7 downto 0);
						end if;
					when x"16" => 	-- R22
						vd_out(3 downto 0) <= bits_per_char;
					when x"17" => 	-- R23
						vd_out(3 downto 0) <= vis_rows_per_char;
					when x"18" =>	-- R24
						vd_out(3 downto 0) <= v_shift;
						vd_out(4) <= v_extborder;
						vd_out(5) <= cblink_mode;
						vd_out(6) <= mode_rev;
					when x"19" =>	-- R25
						if (mode_altreg = '1') then
							vd_out(2 downto 0) <= h_shift_alt;
							vd_out(4) <= h_extborder_alt;
						else
							vd_out(2 downto 0) <= h_shift_reg;
							vd_out(4) <= h_extborder_reg;
						end if;
					when x"1a" => 	-- R26
						vd_out(7 downto 4) <= col_fg;
						vd_out(3 downto 0) <= col_bg0;
					when x"1b" => 	-- R27
						vd_out <= va_offset;
					when x"1c" => 	-- R28
						vd_out <= crom_base;
					when x"1d" => 	-- R29
						vd_out(4 downto 0) <= uline_scan;
					when x"1e" => 	-- R30
						vd_out <= y_addr(7 downto 0);
						y_addr_latch(9 downto 8) <= y_addr(9 downto 8);
					when x"1f" =>	-- R31
						vd_out(1 downto 0) <= y_addr_latch(9 downto 8);
					when x"20" =>	-- R32 (was R39)
						vd_out(0) <= mode_attrib;
						vd_out(1) <= mode_bitmap;
						vd_out(2) <= mode_extended;
						vd_out(4) <= dispen;
						vd_out(5) <= pal_sel;
						vd_out(6) <= mode_regmap_int;
						vd_out(7) <= mode_pet;
					when x"21" => 	-- R33 (was R40)
						vd_out(3 downto 0) <= col_bg1;
						vd_out(7 downto 4) <= col_bg2;
					when x"22" =>	-- R34 (was R41)
						vd_out(3 downto 0) <= col_border;
					when x"23" =>	-- R35 (was R42)
						vd_out(0) <= irq_raster_en;
						vd_out(1) <= irq_sprite_raster_en;
						vd_out(2) <= irq_sprite_sprite_en;
						vd_out(3) <= irq_sprite_border_en;
					when x"24" =>	-- R36 (was R43)
						vd_out(0) <= irq_raster;
						vd_out(1) <= irq_sprite_raster;
						vd_out(2) <= irq_sprite_sprite;
						vd_out(3) <= irq_sprite_border;
						vd_out(7) <= irq_out_int;
					when x"25" => 	-- R37
						vd_out(6) <= not(h_sync_int);
						vd_out(5) <= v_sync_int;
					when x"26" =>	-- R38 (was R44)
						vd_out(6 downto 0) <= hsync_pos;
					when x"27" =>	-- R39 (was R45)
						vd_out(7 downto 0) <= vsync_pos;
					when x"28" =>	-- R40 (was R46) (alternate control I)
						vd_out(0) <= mode_altreg;
						vd_out(1) <= mode_bitmap_alt;
						vd_out(2) <= mode_attrib_alt;
						vd_out(3) <= mode_extended_alt;
						vd_out(5) <= alt_match_palette;
						vd_out(5) <= alt_match_modes;
						vd_out(6) <= alt_match_attr;
						vd_out(7) <= alt_match_vaddr;
					when x"29" =>	-- R41 (was R47) (alternate control II)
						vd_out(3 downto 0) <= alt_rc_cnt;
						vd_out(6) <= alt_match_hsync;
						vd_out(7) <= alt_set_rc;
					when x"2a" =>	-- R42 (was R88)
						vd_out <= sprite_base;
					when x"2b" =>	-- R43 (was R89)
						vd_out <= collision_accum_sprite_border;
					when x"2c" =>	-- R44 (was R90)
						vd_out <= collision_accum_sprite_sprite;
					when x"2d" =>	-- R45 (was R91)
						vd_out <= collision_accum_sprite_raster;
					when x"2e" =>	-- R46 (was R92)
						vd_out(3 downto 0) <= sprite_mcol1;
					when x"2f" =>	-- R47 (was R93)
						vd_out(3 downto 0) <= sprite_mcol2;
					-- registers 0x30-0x4f are for sprites
					-- registers 0x50-0x57 are sprite foreground colours
					when x"50" =>	-- R80
						vd_out(3 downto 0) <= sprite_fgcol(0);
					when x"51" =>	-- R81
						vd_out(3 downto 0) <= sprite_fgcol(1);
					when x"52" =>	-- R82
						vd_out(3 downto 0) <= sprite_fgcol(2);
					when x"53" =>	-- R83
						vd_out(3 downto 0) <= sprite_fgcol(3);
					when x"54" =>	-- R84
						vd_out(3 downto 0) <= sprite_fgcol(4);
					when x"55" =>	-- R85
						vd_out(3 downto 0) <= sprite_fgcol(5);
					when x"56" =>	-- R86
						vd_out(3 downto 0) <= sprite_fgcol(6);
					when x"57" =>	-- R87
						vd_out(3 downto 0) <= sprite_fgcol(7);
					-- registers 0x58-0x5f are palette access
					when x"58" =>   -- R88
						vd_out <= pbr_doA;
					when x"59" =>   -- R89
						vd_out <= pbr_doA;
					when x"5a" =>   -- R90
						vd_out <= pbr_doA;
					when x"5b" =>   -- R91
						vd_out <= pbr_doA;
					when x"5c" =>   -- R92
						vd_out <= pbr_doA;
					when x"5d" =>   -- R93
						vd_out <= pbr_doA;
					when x"5e" =>   -- R94
						vd_out <= pbr_doA;
					when x"5f" =>   -- R95
						vd_out <= pbr_doA;
					when others =>
						vd_out <= sprite_d;
					end case;
				end if;
			end if;
		end if;
	end process;

	--- blinker

	blink_p: process(v_sync_int, reset, blink_cnt)
	begin
		if (reset = '1') then
			blink_cnt <= (others => '0');
		elsif (falling_edge(v_zero)) then
			blink_cnt <= blink_cnt + 1;
		end if;
		
		blink_16 <= blink_cnt(4);
		blink_32 <= blink_cnt(5);
	end process;
	
	--- cursor
	crsr_p: process(h_zero)
	begin
		if (falling_edge(h_zero)) then
			if rcline_cnt = crsr_start_scan then
				case crsr_mode is
				when "00" =>
					crsr_active <= '1';
				when "01" =>
					crsr_active <= '0';
				when "10" =>
					crsr_active <= blink_16;
				when "11" => 
					crsr_active <= blink_32;
				when others =>
					null;
				end case;
			elsif rcline_cnt = crsr_end_scan then
				crsr_active <= '0';
			end if;
		end if;
	end process;

	--- underline
	uline_p: process(h_zero)
	begin
		if (falling_edge(h_zero)) then
			if rcline_cnt = uline_scan then
				uline_active <= '1';
			else
				uline_active <= '0';
			end if;
		end if;
	end process;
	
	cblink_p: process(h_zero) 
	begin
		if (falling_edge(h_zero)) then
			if ((cblink_mode = '0' and blink_16='1') or (cblink_mode = '1' and blink_32 = '1')) then
				cblink_active <= '1';
			else 
				cblink_active <= '0';
			end if;
		end if;
	end process;
	
end Behavioral;

