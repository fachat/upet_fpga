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
--   Sprite engine: manages 8 or 16 sprites, the fetch state machine, the priority
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
--                   R48-R79 / internal R128-R159 (per-sprite),
--                   R80-R87 / internal R160-R167 (per-sprite fg colour).
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
	Generic (
		NUM_SPRITES: integer := 8
	);
	Port (
		-- clocks
		phi2:         in  std_logic;
		qclk:         in  std_logic;
		dotclk:       in  std_logic_vector(3 downto 0);

		-- CPU register interface
		crtc_sel:     in  std_logic;
		crtc_is_data: in  std_logic;
		regsel:       in  std_logic_vector(7 downto 0);
		reg_window:   in  std_logic_vector(7 downto 0);
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
		sprite_no:       out integer range 0 to 15;
		sprite_ison:     out std_logic_vector(15 downto 0); -- per-sprite active-pixel flag

		reset:        in  std_logic
	);
end SpriteEngine;

architecture Behavioral of SpriteEngine is

	type AOA4 is array(natural range<>) of std_logic_vector(3 downto 0);
	type AOA5 is array(natural range<>) of std_logic_vector(4 downto 0);
	type AOA6 is array(natural range<>) of std_logic_vector(5 downto 0);
	type AOA8 is array(natural range<>) of std_logic_vector(7 downto 0);

	function normalized_sprite_count(sprite_count: integer) return integer is
	begin
		if (sprite_count = 16) then
			return 16;
		else
			return 8;
		end if;
	end function;

	constant SPRITE_COUNT: integer := normalized_sprite_count(NUM_SPRITES);
	constant FETCH_STATE_LAST: integer := SPRITE_COUNT * 4 - 1;

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
	signal sprite_sel:          std_logic_vector(15 downto 0);
	signal sprite_dout_int:     AOA8(0 to 15);
	signal sprite_fetch_offset: AOA6(0 to 15);
	signal sprite_enabled:      std_logic_vector(15 downto 0);
	signal sprite_ison_int:     std_logic_vector(15 downto 0);
	signal sprite_overraster:   std_logic_vector(15 downto 0);
	signal sprite_overborder:   std_logic_vector(15 downto 0);
	signal sprite_outbits:      AOA5(0 to 15);

	-- global sprite registers
	signal sprite_fgcol:  AOA4(0 to 15);
	signal sprite_mcol1:  std_logic_vector(3 downto 0);
	signal sprite_mcol2:  std_logic_vector(3 downto 0);
	signal sprite_base:   std_logic_vector(7 downto 0);

	-- fetch state machine
	signal sprite_phase:        std_logic_vector(1 downto 0);
	signal sprite_req_state:    integer range 0 to 63;
	signal sprite_req_idx:      integer range 0 to 15;
	signal sprite_req_win:      std_logic;
	signal sprite_fetch_state:  integer range 0 to 63;
	signal sprite_fetch_idx:    integer range 0 to 15;
	signal sprite_fetch_idx_v:  std_logic_vector(3 downto 0);
	signal sprite_fetch_win:    std_logic;
	signal sprite_fetch_done:   std_logic;
	signal sprite_req_active:   std_logic;
	signal sprite_fetch_active: std_logic;
	signal sprite_data_ptr:     std_logic_vector(7 downto 0);
	signal sprite_fetch_ce:     std_logic_vector(15 downto 0);
	signal sprite_ptr_addr_low: std_logic_vector(7 downto 0);

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
	--   R42  (x"2a") sprite_base                         - direct access
	--   R46  (x"2e") sprite_mcol1                        - direct access
	--   R47  (x"2f") sprite_mcol2                        - direct access
	--   Window 4, R64-R95 (x"40"-x"5f")  per-sprite registers, sprites 0-7
	--   Window 5, R64-R95 (x"40"-x"5f")  per-sprite registers, sprites 8-15
	--   Window 6, R64-R79 (x"40"-x"4f")  per-sprite foreground colours
	--     regsel(4 downto 0) = 5-bit index within the register window
	sdo_p: process(regsel, reg_window, crtc_sel, crtc_is_data, sprite_dout_int,
	               sprite_base, sprite_mcol1, sprite_mcol2, sprite_fgcol)
		variable sprite_idx: integer range 0 to 15;
	begin
		sprite_sel <= (others => '0');
		dout       <= (others => '0');
		sprite_idx := 0;

		if (crtc_sel = '1' and crtc_is_data = '1') then
			-- direct sprite register reads (R42, R46, R47)
			case regsel is
			when x"2a" =>
				dout <= sprite_base;
			when x"2e" =>
				dout(3 downto 0) <= sprite_mcol1;
			when x"2f" =>
				dout(3 downto 0) <= sprite_mcol2;
			when others =>
				null;
			end case;

			-- window-based register access (R64-R95 = x"40"-x"5f")
			if (regsel >= x"40" and regsel <= x"5f") then
				case reg_window is
				when x"04" =>
					-- per-sprite registers for sprites 0-7
					-- bits 4:2 of regsel index the sprite, bits 1:0 the register within
					sprite_idx := to_integer(unsigned(regsel(4 downto 2)));
					sprite_sel(sprite_idx) <= '1';
					dout <= sprite_dout_int(sprite_idx);
				when x"05" =>
					-- per-sprite registers for sprites 8-15 (16-sprite mode only)
					if (SPRITE_COUNT = 16) then
						sprite_idx := 8 + to_integer(unsigned(regsel(4 downto 2)));
						sprite_sel(sprite_idx) <= '1';
						dout <= sprite_dout_int(sprite_idx);
					end if;
				when x"06" =>
					-- sprite foreground colours
					-- regsel x"40"-x"4f" only (regsel(4)='0'); x"50"-x"5f" invalid here
					if (regsel(4) = '0') then
						sprite_idx := to_integer(unsigned(regsel(3 downto 0)));
						if (sprite_idx < 8 or SPRITE_COUNT = 16) then
							dout(3 downto 0) <= sprite_fgcol(sprite_idx);
						end if;
					end if;
				when others =>
					null;
				end case;
			end if;
		end if;
	end process;

	-- -------------------------------------------------------------------------
	-- Global sprite register file (write path)
	regfile_p: process(phi2, reset)
		variable sprite_idx: integer range 0 to 15;
	begin
		sprite_idx := 0;
		if (falling_edge(phi2)) then
		 if (reset = '1') then
			sprite_base  <= "10010111";
			sprite_mcol1 <= "0000";
			sprite_mcol2 <= "0000";
			for i in 0 to 15 loop
				sprite_fgcol(i) <= "0000";
			end loop;
		 elsif (crtc_sel = '1' and crtc_is_data = '1' and crtc_rwb = '0') then
			-- direct sprite register writes (R42, R46, R47)
			case regsel is
			when x"2a" =>  -- R42: sprite base address
				sprite_base <= CPU_D;
			when x"2e" =>  -- R46: sprite multi-colour 1
				sprite_mcol1 <= CPU_D(3 downto 0);
			when x"2f" =>  -- R47: sprite multi-colour 2
				sprite_mcol2 <= CPU_D(3 downto 0);
			when others =>
				null;
			end case;
			-- window 6: sprite foreground colour writes
			-- regsel x"40"-x"4f" only (regsel(4)='0' within x"40"-x"5f")
			if (regsel >= x"40" and regsel <= x"5f" and reg_window = x"06") then
				if (regsel(4) = '0') then
					sprite_idx := to_integer(unsigned(regsel(3 downto 0)));
					if (sprite_idx < 8 or SPRITE_COUNT = 16) then
						sprite_fgcol(sprite_idx) <= CPU_D(3 downto 0);
					end if;
				end if;
			end if;
		 end if;
		end if;
	end process;

	-- -------------------------------------------------------------------------
	-- Priority multiplexer: pick the lowest-numbered active sprite
	sprite_outcol_p: process(qclk)
		variable active_found: boolean;
		variable active_index: integer range 0 to 15;
	begin
		if (falling_edge(qclk)) then
			active_found := false;
			active_index := 0;
			for i in 0 to SPRITE_COUNT - 1 loop
				if (active_found = false and sprite_ison_int(i) = '1') then
					active_found := true;
					active_index := i;
				end if;
			end loop;
			if (active_found = true) then
				sprite_on       <= '1';
				sprite_outcol   <= sprite_outbits(active_index);
				sprite_onborder <= sprite_overborder(active_index);
				sprite_onraster <= sprite_overraster(active_index);
				sprite_no       <= active_index;
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
	-- Counts through SPRITE_COUNT sprites x 4 memory accesses after h_enable
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
				elsif (sprite_req_state = FETCH_STATE_LAST) then
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

		sprite_phase <= std_logic_vector(to_unsigned(sprite_fetch_state mod 4, sprite_phase'length));

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
	--   During a sprite-pointer fetch: pointer table in top 8 or 16 bytes of page
	--   During a sprite-data fetch:    {sprite_base[7:6], sprite_data_ptr[7:0], sprite_fetch_offset[5:0]}
	sprite_ptr_addr_low <= "1111" & sprite_fetch_idx_v
		when SPRITE_COUNT = 16
		else "11111" & sprite_fetch_idx_v(2 downto 0);

	vmem_addr <= sprite_base & sprite_ptr_addr_low
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
		sprite_fetch_ce <= (others => '0');
		if (sprite_fetch_idx < SPRITE_COUNT) then
			sprite_fetch_ce(sprite_fetch_idx) <= sprite_data_fetch and fetch_ce_int;
		end if;
	end process;

	-- -------------------------------------------------------------------------
	-- individual Sprite sub-components
	sprite_gen: for i in 0 to 15 generate
	begin
		sprite_i: Sprite
		port map (
			phi2,
			sprite_sel(i),
			crtc_rwb,
			regsel(1 downto 0),
			CPU_D,
			sprite_dout_int(i),
			sprite_fgcol(i),
			col_bg0,
			sprite_mcol1,
			sprite_mcol2,
			sprite_fetch_offset(i),
			sprite_fetch_ce(i),
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
			sprite_enabled(i),
			sprite_ison_int(i),
			sprite_overraster(i),
			sprite_overborder(i),
			sprite_outbits(i),
			reset
		);
	end generate;

end Behavioral;
