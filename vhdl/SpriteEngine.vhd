----------------------------------------------------------------------------------
-- Company: n/a
-- Engineer: Andre Fachat
--
-- Create Date:    2026
-- Design Name:
-- Module Name:    SpriteEngine - Behavioral
-- Project Name:
-- Target Devices:
-- Tool versions:
-- Description:
--   Sprite engine: manages all 8 sprites, the fetch state machine, the priority
--   multiplexer and the sprite-specific register file. This component is
--   instantiated once from VideoColorVGA.vhd and replaces the eight individual
--   Sprite instantiations together with the surrounding sprite-fetch logic that
--   used to live in that file.
--
--   Interface groups
--   ----------------
--   Clocks        : phi2, qclk, dotclk
--   Register I/O  : crtc_sel / crtc_is_data / regsel / crtc_rwb / CPU_D / dout
--                   Handles registers R42 (sprite_base), R46-R47 (mcol),
--                   R48-R79 (per-sprite), R80-R87 (per-sprite fg colour).
--   Video memory  : vmem_req / vmem_fetch / vmem_addr / vmem_data
--                   vmem_req  - request: next memory access should be for sprites
--                   vmem_fetch - a sprite fetch is active right now (contribution
--                                to vid_fetch)
--                   vmem_addr  - address to read during the current sprite fetch
--                   vmem_data  - data returned by the video memory bus
--   Display geo   : h_enable / h_zero / v_zero / x_addr / y_addr
--   Display mode  : col_bg0 / is_double / is_80 / is_tv /
--                   is_shift40 / is_shift80 / vsync_pos0
--   Pixel output  : sprite_on / sprite_outcol / sprite_onborder /
--                   sprite_onraster / sprite_no / sprite_ison
--
-- Dependencies: Sprite.vhd
--
-- Revision:
-- Revision 0.01 - File Created
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_unsigned.ALL;
use ieee.numeric_std.all;

entity SpriteEngine is
	Port (
		-- clocks
		phi2:         in  std_logic;
		qclk:         in  std_logic;
		dotclk:       in  std_logic_vector(3 downto 0);

		-- CPU register interface
		crtc_sel:     in  std_logic;
		crtc_is_data: in  std_logic;
		regsel:       in  std_logic_vector(7 downto 0);
		crtc_rwb:     in  std_logic;
		CPU_D:        in  std_logic_vector(7 downto 0);
		dout:         out std_logic_vector(7 downto 0);

		-- video memory fetch interface
		is_enable:    in  std_logic;
		rline_cnt0:   in  std_logic;
		is_interlace: in  std_logic;
		h_enable:     in  std_logic;
		vmem_req:     out std_logic;    -- next memory access should be a sprite fetch
		vmem_fetch:   out std_logic;    -- sprite fetch is active (drives vid_fetch)
		vmem_addr:    out std_logic_vector(15 downto 0); -- address to present to video RAM
		vmem_data:    in  std_logic_vector(7 downto 0);  -- data returned from video RAM

		-- display geometry
		h_zero:       in  std_logic;
		v_zero:       in  std_logic;
		x_addr:       in  std_logic_vector(10 downto 0);
		y_addr:       in  std_logic_vector(9 downto 0);

		-- display mode
		col_bg0:      in  std_logic_vector(3 downto 0);
		is_double:    in  std_logic;
		is_80:        in  std_logic;
		is_tv:        in  std_logic;
		is_shift40:   in  std_logic;
		is_shift80:   in  std_logic;
		vsync_pos0:   in  std_logic;

		-- pixel output and active-sprite flags
		sprite_on:       out std_logic;
		sprite_outcol:   out std_logic_vector(4 downto 0);
		sprite_onborder: out std_logic;
		sprite_onraster: out std_logic;
		sprite_no:       out integer range 0 to 7;
		sprite_ison:     out std_logic_vector(7 downto 0); -- per-sprite active-pixel flag

		reset:        in  std_logic
	);
end SpriteEngine;

architecture Behavioral of SpriteEngine is

	type AOA4 is array(natural range<>) of std_logic_vector(3 downto 0);
	type AOA5 is array(natural range<>) of std_logic_vector(4 downto 0);
	type AOA6 is array(natural range<>) of std_logic_vector(5 downto 0);
	type AOA8 is array(natural range<>) of std_logic_vector(7 downto 0);

	-- individual Sprite sub-component (Sprite.vhd)
	component Sprite is
	Port (
		phi2:         in  std_logic;
		sel:          in  std_logic;
		rwb:          in  std_logic;
		regsel:       in  std_logic_vector(1 downto 0);
		din:          in  std_logic_vector(7 downto 0);
		dout:         out std_logic_vector(7 downto 0);

		fgcol:        in  std_logic_vector(3 downto 0);
		bgcol:        in  std_logic_vector(3 downto 0);
		mcol1:        in  std_logic_vector(3 downto 0);
		mcol2:        in  std_logic_vector(3 downto 0);

		fetch_offset: out std_logic_vector(5 downto 0);
		fetch_ce:     in  std_logic;

		qclk:         in  std_logic;
		dotclk0:      in  std_logic;
		phase:        in  std_logic_vector(1 downto 0);
		vdin:         in  std_logic_vector(7 downto 0);
		h_enable:     in  std_logic;
		h_zero:       in  std_logic;
		v_zero:       in  std_logic;
		x_addr:       in  std_logic_vector(10 downto 0);
		y_addr:       in  std_logic_vector(9 downto 0);
		is_double:    in  std_logic;
		is_interlace: in  std_logic;
		is80:         in  std_logic;
		is_tv:        in  std_logic;
		is_shift40:   in  std_logic;
		is_shift80:   in  std_logic;
		vsync_pos0:   in  std_logic;

		enabled:      out std_logic;
		ison:         out std_logic;
		overraster:   out std_logic;
		overborder:   out std_logic;
		outbits:      out std_logic_vector(4 downto 0);

		reset:        in  std_logic
	);
	end component;

	-- per-sprite signals
	signal sprite_sel:          std_logic_vector(7 downto 0);
	signal sprite_dout_int:     AOA8(0 to 7);
	signal sprite_fetch_offset: AOA6(0 to 7);
	signal sprite_enabled:      std_logic_vector(7 downto 0);
	signal sprite_ison_int:     std_logic_vector(7 downto 0);
	signal sprite_overraster:   std_logic_vector(7 downto 0);
	signal sprite_overborder:   std_logic_vector(7 downto 0);
	signal sprite_outbits:      AOA5(0 to 7);

	-- global sprite registers
	signal sprite_fgcol:  AOA4(0 to 7);
	signal sprite_mcol1:  std_logic_vector(3 downto 0);
	signal sprite_mcol2:  std_logic_vector(3 downto 0);
	signal sprite_base:   std_logic_vector(7 downto 0);

	-- fetch state machine
	signal sprite_phase:        std_logic_vector(1 downto 0);
	signal sprite_req_state:    integer range 0 to 63;
	signal sprite_req_idx:      integer range 0 to 7;
	signal sprite_req_win:      std_logic;
	signal sprite_fetch_state:  integer range 0 to 63;
	signal sprite_fetch_idx:    integer range 0 to 7;
	signal sprite_fetch_idx_v:  std_logic_vector(2 downto 0);
	signal sprite_fetch_win:    std_logic;
	signal sprite_fetch_done:   std_logic;
	signal sprite_req_active:   std_logic;
	signal sprite_fetch_active: std_logic;
	signal sprite_data_ptr:     std_logic_vector(7 downto 0);
	signal sprite_fetch_ce:     std_logic_vector(7 downto 0);

	signal fetch_sprite_en:     std_logic;
	signal req_sprite_en:       std_logic;
	signal sprite_data_fetch:   std_logic;

	-- fetch_ce derived from dotclk inside the engine
	signal fetch_ce_int:        std_logic;

begin

	-- -------------------------------------------------------------------------
	-- fetch_ce: high on dotclk phase "11"
	fetch_ce_int <= '1' when dotclk(1 downto 0) = "11" else '0';

	-- -------------------------------------------------------------------------
	-- Sprite register select / read-data output (combinatorial)
	--
	-- Handles:
	--   R42  (x"2a") sprite_base
	--   R46  (x"2e") sprite_mcol1
	--   R47  (x"2f") sprite_mcol2
	--   R48-R79 (x"30"-x"4f") per-sprite registers via individual Sprite sub-components
	--   R80-R87 (x"50"-x"57") per-sprite foreground colours
	sdo_p: process(regsel, crtc_sel, crtc_is_data, sprite_dout_int,
	               sprite_base, sprite_mcol1, sprite_mcol2, sprite_fgcol)
	begin
		sprite_sel <= (others => '0');
		dout       <= (others => '0');

		if (crtc_sel = '1' and crtc_is_data = '1') then
			-- global sprite register reads
			case regsel is
			when x"2a" =>
				dout <= sprite_base;
			when x"2e" =>
				dout(3 downto 0) <= sprite_mcol1;
			when x"2f" =>
				dout(3 downto 0) <= sprite_mcol2;
			when x"50" =>
				dout(3 downto 0) <= sprite_fgcol(0);
			when x"51" =>
				dout(3 downto 0) <= sprite_fgcol(1);
			when x"52" =>
				dout(3 downto 0) <= sprite_fgcol(2);
			when x"53" =>
				dout(3 downto 0) <= sprite_fgcol(3);
			when x"54" =>
				dout(3 downto 0) <= sprite_fgcol(4);
			when x"55" =>
				dout(3 downto 0) <= sprite_fgcol(5);
			when x"56" =>
				dout(3 downto 0) <= sprite_fgcol(6);
			when x"57" =>
				dout(3 downto 0) <= sprite_fgcol(7);
			when others =>
				-- per-sprite register reads (R48-R79, decoded via bits 6:2)
				case regsel(6 downto 2) is
				when "01100" =>   -- sprite 0  R48-R51
					sprite_sel(0) <= '1';
					dout <= sprite_dout_int(0);
				when "01101" =>   -- sprite 1  R52-R55
					sprite_sel(1) <= '1';
					dout <= sprite_dout_int(1);
				when "01110" =>   -- sprite 2
					sprite_sel(2) <= '1';
					dout <= sprite_dout_int(2);
				when "01111" =>   -- sprite 3
					sprite_sel(3) <= '1';
					dout <= sprite_dout_int(3);
				when "10000" =>   -- sprite 4
					sprite_sel(4) <= '1';
					dout <= sprite_dout_int(4);
				when "10001" =>   -- sprite 5
					sprite_sel(5) <= '1';
					dout <= sprite_dout_int(5);
				when "10010" =>   -- sprite 6
					sprite_sel(6) <= '1';
					dout <= sprite_dout_int(6);
				when "10011" =>   -- sprite 7
					sprite_sel(7) <= '1';
					dout <= sprite_dout_int(7);
				when others =>
					null;
				end case;
			end case;
		end if;
	end process;

	-- -------------------------------------------------------------------------
	-- Global sprite register file (write path)
	regfile_p: process(phi2, reset)
	begin
		if (falling_edge(phi2)) then
		 if (reset = '1') then
			sprite_base  <= "10010111";
			sprite_mcol1 <= "0000";
			sprite_mcol2 <= "0000";
			for i in 0 to 7 loop
				sprite_fgcol(i) <= "0000";
			end loop;
		 elsif (crtc_sel = '1' and crtc_is_data = '1' and crtc_rwb = '0') then
			case regsel is
			when x"2a" =>  -- R42: sprite base address
				sprite_base <= CPU_D;
			when x"2e" =>  -- R46: sprite multi-colour 1
				sprite_mcol1 <= CPU_D(3 downto 0);
			when x"2f" =>  -- R47: sprite multi-colour 2
				sprite_mcol2 <= CPU_D(3 downto 0);
			when x"50" =>  -- R80: sprite 0 foreground colour
				sprite_fgcol(0) <= CPU_D(3 downto 0);
			when x"51" =>  -- R81
				sprite_fgcol(1) <= CPU_D(3 downto 0);
			when x"52" =>  -- R82
				sprite_fgcol(2) <= CPU_D(3 downto 0);
			when x"53" =>  -- R83
				sprite_fgcol(3) <= CPU_D(3 downto 0);
			when x"54" =>  -- R84
				sprite_fgcol(4) <= CPU_D(3 downto 0);
			when x"55" =>  -- R85
				sprite_fgcol(5) <= CPU_D(3 downto 0);
			when x"56" =>  -- R86
				sprite_fgcol(6) <= CPU_D(3 downto 0);
			when x"57" =>  -- R87
				sprite_fgcol(7) <= CPU_D(3 downto 0);
			when others =>
				null;
			end case;
		 end if;
		end if;
	end process;

	-- -------------------------------------------------------------------------
	-- Priority multiplexer: pick the lowest-numbered active sprite
	sprite_outcol_p: process(qclk)
	begin
		if (falling_edge(qclk)) then
			if (sprite_ison_int(0) = '1') then
				sprite_on       <= '1';
				sprite_outcol   <= sprite_outbits(0);
				sprite_onborder <= sprite_overborder(0);
				sprite_onraster <= sprite_overraster(0);
				sprite_no       <= 0;
			elsif (sprite_ison_int(1) = '1') then
				sprite_on       <= '1';
				sprite_outcol   <= sprite_outbits(1);
				sprite_onborder <= sprite_overborder(1);
				sprite_onraster <= sprite_overraster(1);
				sprite_no       <= 1;
			elsif (sprite_ison_int(2) = '1') then
				sprite_on       <= '1';
				sprite_outcol   <= sprite_outbits(2);
				sprite_onborder <= sprite_overborder(2);
				sprite_onraster <= sprite_overraster(2);
				sprite_no       <= 2;
			elsif (sprite_ison_int(3) = '1') then
				sprite_on       <= '1';
				sprite_outcol   <= sprite_outbits(3);
				sprite_onborder <= sprite_overborder(3);
				sprite_onraster <= sprite_overraster(3);
				sprite_no       <= 3;
			elsif (sprite_ison_int(4) = '1') then
				sprite_on       <= '1';
				sprite_outcol   <= sprite_outbits(4);
				sprite_onborder <= sprite_overborder(4);
				sprite_onraster <= sprite_overraster(4);
				sprite_no       <= 4;
			elsif (sprite_ison_int(5) = '1') then
				sprite_on       <= '1';
				sprite_outcol   <= sprite_outbits(5);
				sprite_onborder <= sprite_overborder(5);
				sprite_onraster <= sprite_overraster(5);
				sprite_no       <= 5;
			elsif (sprite_ison_int(6) = '1') then
				sprite_on       <= '1';
				sprite_outcol   <= sprite_outbits(6);
				sprite_onborder <= sprite_overborder(6);
				sprite_onraster <= sprite_overraster(6);
				sprite_no       <= 6;
			elsif (sprite_ison_int(7) = '1') then
				sprite_on       <= '1';
				sprite_outcol   <= sprite_outbits(7);
				sprite_onborder <= sprite_overborder(7);
				sprite_onraster <= sprite_overraster(7);
				sprite_no       <= 7;
			else
				sprite_on       <= '0';
				sprite_outcol   <= "00000";
				sprite_onborder <= '0';
				sprite_onraster <= '0';
				sprite_no       <= 0;
			end if;
		end if;
	end process;

	sprite_ison <= sprite_ison_int;

	-- -------------------------------------------------------------------------
	-- Fetch state machine
	-- Counts through 8 sprites x 4 memory accesses = 32 states after h_enable
	-- goes low.  The first access of each sprite is the sprite-pointer fetch
	-- (sprite_ptr_window); the remaining three are sprite-data fetches.
	fetch_idx_p: process(qclk, dotclk, h_enable, sprite_req_state, sprite_fetch_state, sprite_fetch_idx)
	begin
		-- reset counters while visible area is active
		if (h_enable = '1') then
			sprite_fetch_state <= 0;
			sprite_req_state   <= 0;
			sprite_fetch_win   <= '0';
			sprite_req_win     <= '0';
			sprite_fetch_done  <= '0';
		elsif (falling_edge(qclk) and dotclk(1 downto 0) = "11") then
		
			if (sprite_fetch_done = '0') then
				if (sprite_req_win = '0') then
					sprite_req_win <= '1';
				elsif (sprite_req_state = 31) then
					sprite_req_win    <= '0';
					sprite_fetch_done <= '1';
				else
					sprite_req_state <= sprite_req_state + 1;
				end if;
			end if;

			-- fetch window is one memory access behind the request window
			sprite_fetch_win   <= sprite_req_win;
			sprite_fetch_state <= sprite_req_state;
			
		end if;

		-- combinatorial derivations (always re-evaluated)
		sprite_req_idx     <= sprite_req_state / 4;
		sprite_fetch_idx   <= sprite_fetch_state / 4;
		sprite_fetch_idx_v <= std_logic_vector(to_unsigned(sprite_fetch_idx, sprite_fetch_idx_v'length));

		sprite_phase <= std_logic_vector(to_unsigned(sprite_fetch_state, 2));

	end process;

	-- -------------------------------------------------------------------------
	-- Fetch-enable signals
	fetch_sprite_en <= '1' when is_enable = '1'
	                        and (is_interlace = '1' or rline_cnt0 = '0')
	                        and sprite_fetch_active = '1'
	                        and sprite_fetch_win = '1'
	                   else '0';

	req_sprite_en   <= '1' when is_enable = '1'
	                        and (is_interlace = '1' or rline_cnt0 = '0')
	                        and sprite_req_active = '1'
	                        and sprite_req_win = '1'
	                   else '0';

	sprite_data_fetch <= (sprite_phase(0) or sprite_phase(1)) and fetch_sprite_en;

	-- expose to parent
	vmem_fetch <= fetch_sprite_en;
	vmem_req   <= req_sprite_en;

	-- -------------------------------------------------------------------------
	-- Video-memory address
	--   During a sprite-pointer fetch: {sprite_base[7:0], 5'b11111, sprite_idx[2:0]}
	--   During a sprite-data fetch:    {sprite_base[7:6], sprite_data_ptr[7:0], sprite_fetch_offset[5:0]}
	vmem_addr <= sprite_base & "11111" & sprite_fetch_idx_v
	                  when sprite_phase = "00"
	             else sprite_base(7 downto 6) & sprite_data_ptr & sprite_fetch_offset(sprite_fetch_idx);

	-- -------------------------------------------------------------------------
	-- Fetch-active control and per-sprite fetch_ce signals
	fetchactive_p: process(qclk, sprite_fetch_idx, 
	                        sprite_data_fetch, fetch_ce_int,
	                        sprite_enabled, sprite_fetch_offset, sprite_req_idx)
	begin
		sprite_req_active   <= sprite_enabled(sprite_req_idx);
		sprite_fetch_active <= sprite_enabled(sprite_fetch_idx);

		-- capture sprite data pointer from video memory on pointer fetch
		if (falling_edge(qclk) and fetch_ce_int = '1') then
			if (sprite_phase = "00") then
				sprite_data_ptr <= vmem_data;
			end if;
		end if;

		-- route fetch_ce to the currently-fetching sprite
		sprite_fetch_ce <= "00000000";
		case (sprite_fetch_idx) is
		when 0 =>  sprite_fetch_ce(0) <= sprite_data_fetch and fetch_ce_int;
		when 1 =>  sprite_fetch_ce(1) <= sprite_data_fetch and fetch_ce_int;
		when 2 =>  sprite_fetch_ce(2) <= sprite_data_fetch and fetch_ce_int;
		when 3 =>  sprite_fetch_ce(3) <= sprite_data_fetch and fetch_ce_int;
		when 4 =>  sprite_fetch_ce(4) <= sprite_data_fetch and fetch_ce_int;
		when 5 =>  sprite_fetch_ce(5) <= sprite_data_fetch and fetch_ce_int;
		when 6 =>  sprite_fetch_ce(6) <= sprite_data_fetch and fetch_ce_int;
		when 7 =>  sprite_fetch_ce(7) <= sprite_data_fetch and fetch_ce_int;
		end case;
	end process;

	-- -------------------------------------------------------------------------
	-- 8 individual Sprite sub-components

	sprite0: Sprite
	port map (
		phi2,
		sprite_sel(0),
		crtc_rwb,
		regsel(1 downto 0),
		CPU_D,
		sprite_dout_int(0),
		sprite_fgcol(0),
		col_bg0,
		sprite_mcol1,
		sprite_mcol2,
		sprite_fetch_offset(0),
		sprite_fetch_ce(0),
		qclk,
		dotclk(0),
		sprite_phase,
		vmem_data,
		h_enable,
		h_zero,
		v_zero,
		x_addr,
		y_addr,
		is_double,
		is_interlace,
		is_80,
		is_tv,
		is_shift40,
		is_shift80,
		vsync_pos0,
		sprite_enabled(0),
		sprite_ison_int(0),
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
		sprite_dout_int(1),
		sprite_fgcol(1),
		col_bg0,
		sprite_mcol1,
		sprite_mcol2,
		sprite_fetch_offset(1),
		sprite_fetch_ce(1),
		qclk,
		dotclk(0),
		sprite_phase,
		vmem_data,
		h_enable,
		h_zero,
		v_zero,
		x_addr,
		y_addr,
		is_double,
		is_interlace,
		is_80,
		is_tv,
		is_shift40,
		is_shift80,
		vsync_pos0,
		sprite_enabled(1),
		sprite_ison_int(1),
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
		sprite_dout_int(2),
		sprite_fgcol(2),
		col_bg0,
		sprite_mcol1,
		sprite_mcol2,
		sprite_fetch_offset(2),
		sprite_fetch_ce(2),
		qclk,
		dotclk(0),
		sprite_phase,
		vmem_data,
		h_enable,
		h_zero,
		v_zero,
		x_addr,
		y_addr,
		is_double,
		is_interlace,
		is_80,
		is_tv,
		is_shift40,
		is_shift80,
		vsync_pos0,
		sprite_enabled(2),
		sprite_ison_int(2),
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
		sprite_dout_int(3),
		sprite_fgcol(3),
		col_bg0,
		sprite_mcol1,
		sprite_mcol2,
		sprite_fetch_offset(3),
		sprite_fetch_ce(3),
		qclk,
		dotclk(0),
		sprite_phase,
		vmem_data,
		h_enable,
		h_zero,
		v_zero,
		x_addr,
		y_addr,
		is_double,
		is_interlace,
		is_80,
		is_tv,
		is_shift40,
		is_shift80,
		vsync_pos0,
		sprite_enabled(3),
		sprite_ison_int(3),
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
		sprite_dout_int(4),
		sprite_fgcol(4),
		col_bg0,
		sprite_mcol1,
		sprite_mcol2,
		sprite_fetch_offset(4),
		sprite_fetch_ce(4),
		qclk,
		dotclk(0),
		sprite_phase,
		vmem_data,
		h_enable,
		h_zero,
		v_zero,
		x_addr,
		y_addr,
		is_double,
		is_interlace,
		is_80,
		is_tv,
		is_shift40,
		is_shift80,
		vsync_pos0,
		sprite_enabled(4),
		sprite_ison_int(4),
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
		sprite_dout_int(5),
		sprite_fgcol(5),
		col_bg0,
		sprite_mcol1,
		sprite_mcol2,
		sprite_fetch_offset(5),
		sprite_fetch_ce(5),
		qclk,
		dotclk(0),
		sprite_phase,
		vmem_data,
		h_enable,
		h_zero,
		v_zero,
		x_addr,
		y_addr,
		is_double,
		is_interlace,
		is_80,
		is_tv,
		is_shift40,
		is_shift80,
		vsync_pos0,
		sprite_enabled(5),
		sprite_ison_int(5),
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
		sprite_dout_int(6),
		sprite_fgcol(6),
		col_bg0,
		sprite_mcol1,
		sprite_mcol2,
		sprite_fetch_offset(6),
		sprite_fetch_ce(6),
		qclk,
		dotclk(0),
		sprite_phase,
		vmem_data,
		h_enable,
		h_zero,
		v_zero,
		x_addr,
		y_addr,
		is_double,
		is_interlace,
		is_80,
		is_tv,
		is_shift40,
		is_shift80,
		vsync_pos0,
		sprite_enabled(6),
		sprite_ison_int(6),
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
		sprite_dout_int(7),
		sprite_fgcol(7),
		col_bg0,
		sprite_mcol1,
		sprite_mcol2,
		sprite_fetch_offset(7),
		sprite_fetch_ce(7),
		qclk,
		dotclk(0),
		sprite_phase,
		vmem_data,
		h_enable,
		h_zero,
		v_zero,
		x_addr,
		y_addr,
		is_double,
		is_interlace,
		is_80,
		is_tv,
		is_shift40,
		is_shift80,
		vsync_pos0,
		sprite_enabled(7),
		sprite_ison_int(7),
		sprite_overraster(7),
		sprite_overborder(7),
		sprite_outbits(7),
		reset
	);

end Behavioral;
