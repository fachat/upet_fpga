----------------------------------------------------------------------------------
-- Module:      HdmiTestShell
-- Description: Top-level test shell for 720x480p60 colour-bar video output.
--              Generates the SMPTE/EBU 8-bar test image (hsync, vsync, and pixel
--              colour values) and feeds it to HdmiTestTop for TMDS serialisation.
--              Also drives the board's parallel video outputs (HSYNC, VSYNC,
--              PXL_OUT) directly.
--
-- Board:       ultipet 1.3a  (Spartan-6 XC6SLX9, Q50M = 50 MHz input clock)
-- UCF:         pinoutUPet13aHdmitest.ucf
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity HdmiTestShell is
    Port (
        q50m      : in  std_logic;   -- 50 MHz board clock
        nres      : in  std_logic;   -- active-low reset
        vsync     : out std_logic;
        hsync     : out std_logic;
        pxl_out   : out std_logic_vector(5 downto 0)
    );
end HdmiTestShell;

architecture Behavioral of HdmiTestShell is

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
    constant H_DISPLAY : integer := 720;
    constant H_FP      : integer := 16;
    constant H_SYNC_W  : integer := 62;

    constant V_DISPLAY : integer := 480;
    constant V_FP      : integer := 9;
    constant V_SYNC_W  : integer := 6;

    component HdmiTestTop is
        Port (
            clk54      : in  std_logic;
            reset_n    : in  std_logic;
            de         : in  std_logic;
            hsync      : in  std_logic;
            vsync      : in  std_logic;
            r          : in  std_logic_vector(7 downto 0);
            g          : in  std_logic_vector(7 downto 0);
            b          : in  std_logic_vector(7 downto 0);
            h_out      : out std_logic_vector(9 downto 0);
            v_out      : out std_logic_vector(9 downto 0);
            tmds_clk_p : out std_logic;
--            tmds_clk_n : out std_logic;
            tmds_d0_p  : out std_logic;
--            tmds_d0_n  : out std_logic;
            tmds_d1_p  : out std_logic;
--            tmds_d1_n  : out std_logic;
            tmds_d2_p  : out std_logic
--            tmds_d2_n  : out std_logic
        );
    end component;

    -- Pixel position exported by HdmiTestTop (combinatorial, 270 MHz domain).
    signal h_s     : std_logic_vector(9 downto 0);
    signal v_s     : std_logic_vector(9 downto 0);

    -- Generated video signals (combinatorial, based on h_s / v_s).
    signal de_s    : std_logic;
    signal hsync_s : std_logic;
    signal vsync_s : std_logic;
    signal r_s     : std_logic_vector(7 downto 0);
    signal g_s     : std_logic_vector(7 downto 0);
    signal b_s     : std_logic_vector(7 downto 0);

	 -- HDMI output signals
	 signal tmds_clk_p : std_logic;
--    signal tmds_clk_n : std_logic;
    signal tmds_d0_p  : std_logic;
--    signal tmds_d0_n  : std_logic;
    signal tmds_d1_p  : std_logic;
--    signal tmds_d1_n  : std_logic;
    signal tmds_d2_p  : std_logic;
--    signal tmds_d2_n  : std_logic;

begin

    ---------------------------------------------------------------------------
    -- Instantiate HdmiTestTop (TMDS encoder / serialiser).
    -- TMDS differential outputs are not used by this board variant.
    ---------------------------------------------------------------------------
    test_c : HdmiTestTop
    port map (
        clk54      => q50m,
        reset_n    => nres,
        de         => de_s,
        hsync      => hsync_s,
        vsync      => vsync_s,
        r          => r_s,
        g          => g_s,
        b          => b_s,
        h_out      => h_s,
        v_out      => v_s,
        tmds_clk_p => tmds_clk_p,
--        tmds_clk_n => tmds_clk_n,
        tmds_d0_p  => tmds_d0_p,
--        tmds_d0_n  => tmds_d0_n,
        tmds_d1_p  => tmds_d1_p,
--        tmds_d1_n  => tmds_d1_n,
        tmds_d2_p  => tmds_d2_p
--        tmds_d2_n  => tmds_d2_n
    );

    ---------------------------------------------------------------------------
    -- Test video image generator: 720x480p60 SMPTE/EBU 8-colour bars
    --   White | Yellow | Cyan | Green | Magenta | Red | Blue | Black
    --   (90 pixels wide each)
    --
    -- Runs combinatorially on h_s/v_s so that the generated signals are valid
    -- at the 270 MHz load cycle when HdmiTestTop samples them.
    ---------------------------------------------------------------------------
    video_gen_p : process(h_s, v_s)
        variable h : integer;
        variable v : integer;
    begin
        h := to_integer(unsigned(h_s));
        v := to_integer(unsigned(v_s));

        -- Data enable: high inside active display window.
        if h < H_DISPLAY and v < V_DISPLAY then
            de_s <= '1';
        else
            de_s <= '0';
        end if;

        -- Horizontal sync (negative polarity — low during pulse).
        if h >= H_DISPLAY + H_FP and h < H_DISPLAY + H_FP + H_SYNC_W then
            hsync_s <= '0';
        else
            hsync_s <= '1';
        end if;

        -- Vertical sync (negative polarity — low during pulse).
        if v >= V_DISPLAY + V_FP and v < V_DISPLAY + V_FP + V_SYNC_W then
            vsync_s <= '0';
        else
            vsync_s <= '1';
        end if;

        -- Pixel colour: 8 SMPTE colour bars, 90 pixels wide each.
        if h < H_DISPLAY and v < V_DISPLAY then
            if    h <  90 then r_s <= x"FF"; g_s <= x"F7"; b_s <= x"FF"; -- White
            elsif h < 180 then r_s <= x"F7"; g_s <= x"FF"; b_s <= x"00"; -- Yellow
            elsif h < 270 then r_s <= x"00"; g_s <= x"FF"; b_s <= x"FF"; -- Cyan
            elsif h < 360 then r_s <= x"00"; g_s <= x"F7"; b_s <= x"00"; -- Green
            elsif h < 450 then r_s <= x"7F"; g_s <= x"00"; b_s <= x"FF"; -- Magenta
            elsif h < 540 then r_s <= x"FF"; g_s <= x"00"; b_s <= x"00"; -- Red
            elsif h < 630 then r_s <= x"00"; g_s <= x"00"; b_s <= x"FF"; -- Blue
            else                r_s <= x"00"; g_s <= x"00"; b_s <= x"00"; -- Black
            end if;
        else
            r_s <= x"00"; g_s <= x"00"; b_s <= x"00";
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Board-level HDMI video output mapping
    ---------------------------------------------------------------------------
    vsync   <= tmds_clk_p;
    hsync   <= not(tmds_clk_p);
    pxl_out(5) <= tmds_d2_p;
	 pxl_out(4) <= not(tmds_d2_p);
	 pxl_out(3) <= tmds_d1_p;
	 pxl_out(2) <= not(tmds_d1_p);
	 pxl_out(1)	<= tmds_d0_p;
	 pxl_out(0) <= not(tmds_d0_p);

end Behavioral;

