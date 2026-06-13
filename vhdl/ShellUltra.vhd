----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    01:38:52 06/21/2020 
-- Design Name: 
-- Module Name:    Top - Behavioral 
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

entity ShellUltra is
    Port ( 
	-- clock
	   q50m : in std_logic;
	   nres : in std_logic;
	   nirq : out std_logic;
	
	   -- CS/A out bus timing
	   c8phi2	: out std_logic;
	   c2phi2	: out std_logic;
	   cphi2	: out std_logic;

	-- config
	   graphic: in std_logic;	-- from I/O, select charset
	   
	-- CPU interface
	   A : in  STD_LOGIC_VECTOR (15 downto 0);
           D : inout  STD_LOGIC_VECTOR (7 downto 0);
           vda : in  STD_LOGIC;
           vpa : in  STD_LOGIC;
	   rwb : in std_logic;
	   rdy : in std_logic;
           phi2 : out  STD_LOGIC;	-- with pull-up to go to 5V
	   vpb : in std_logic;
	   e : in std_logic;
	   mlb: in std_logic;
	   --mx : in std_logic;
	   cpu_nbe: out std_logic;

	-- bus
	-- ROM, I/O (on CPU bus)	   
	   nbe_dout : out std_logic;

	-- Ulti-PET / Ultra-CPU specific
	   sync : out std_logic;
	   be_in: in std_logic;
	   nmemsel: out std_logic;
	   niosel: out std_logic;
	   extio: in std_logic;
	   ioinh: in std_logic;
	   nbe_out : out std_logic;
	  
	-- UPet specific
	-- nsel1: out std_logic;
	-- nsel2: out std_logic;
	-- nsel4: out std_logic;
		
	-- V/RAM interface
	   VA : out std_logic_vector (18 downto 0);	-- 512k
	   FA : out std_logic_vector (19 downto 15);	-- 512k, mappable in 32k blocks
	   VD : inout std_logic_vector (7 downto 0);
	   
	   nvramsel : out STD_LOGIC;
	   nframsel : out STD_LOGIC;
	   ramrwb : out std_logic;
	   
	   pet_vsync: out std_logic;

		hdmi_ck_n: out std_logic;
		hdmi_ck_p: out std_logic;
		hdmi_d0_n: out std_logic;
		hdmi_d0_p: out std_logic;
		hdmi_d1_n: out std_logic;
		hdmi_d1_p: out std_logic;
		hdmi_d2_n: out std_logic;
		hdmi_d2_p: out std_logic;
	   
	-- SPI
	   spi_out : out std_logic;
	   spi_clk : out std_logic;
	   -- MISO
	   spi_in1  : in std_logic;
	   spi_in3  : in std_logic;
	   -- selects
	   spi_sela : out std_logic;
	   spi_selb : out std_logic;
	   spi_selc : out std_logic;
			   
	-- Audio / DAC output
	   spi_naudio : out std_logic;
	   spi_aclk : out std_logic;
	   spi_amosi : out std_logic;
	   nldac : out std_logic
	 );
end ShellUltra;

architecture Behavioral of ShellUltra is

	signal nsel1: std_logic;
	signal nsel2: std_logic;
	signal nsel4: std_logic;
	
	signal vga_hsync_int: std_logic;
	signal vga_vsync_int: std_logic;
	signal v_out: std_logic_vector(5 downto 0);
	signal dotclk0: std_logic;
	
	signal tmds_ck: std_logic;
	signal tmds_d0: std_logic;
	signal tmds_d1: std_logic;
	signal tmds_d2: std_logic;
	
	component Top is
    	Port ( 
	-- clock
	   q50m : in std_logic;
	   nres : in std_logic;
	   nirq : out std_logic;
	
	   -- CS/A out bus timing
	   c8phi2	: out std_logic;
	   c2phi2	: out std_logic;
	   cphi2	: out std_logic;

	-- config
	   graphic: in std_logic;	-- from I/O, select charset
	   
	-- CPU interface
	   A : in  STD_LOGIC_VECTOR (15 downto 0);
      D : inout  STD_LOGIC_VECTOR (7 downto 0);
      vda : in  STD_LOGIC;
      vpa : in  STD_LOGIC;
	   rwb : in std_logic;
	   rdy : in std_logic;
           phi2 : out  STD_LOGIC;	-- with pull-up to go to 5V
	   vpb : in std_logic;
	   e : in std_logic;
	   mlb: in std_logic;
	   --mx : in std_logic;
	   cpu_nbe: out std_logic;

	-- bus
	-- ROM, I/O (on CPU bus)	   
	   nbe_dout : out std_logic;

	-- Ulti-PET / Ultra-CPU specific
	   sync : out std_logic;
	   be_in: in std_logic;
	   nmemsel: out std_logic;
	   niosel: out std_logic;
	   extio: in std_logic;
	   ioinh: in std_logic;
	   nbe_out : out std_logic;
	  
	-- UPet specific
	   nsel1: out std_logic;
	   nsel2: out std_logic;
	   nsel4: out std_logic;
		
	-- V/RAM interface
	   VA : out std_logic_vector (18 downto 0);	-- 512k
	   FA : out std_logic_vector (19 downto 15);	-- 512k, mappable in 32k blocks
	   VD : inout std_logic_vector (7 downto 0);
	   
	   nvramsel : out STD_LOGIC;
	   nframsel : out STD_LOGIC;
	   ramrwb : out std_logic;
	   
		dotclk0 : out std_logic;
		pixel0: out std_logic;
	   vsync : out  STD_LOGIC;
 	   hsync : out  STD_LOGIC;
	   pet_vsync: out std_logic;

	   pxl_out: out std_logic_vector(5 downto 0);
	   
	-- SPI
	   spi_out : out std_logic;
	   spi_clk : out std_logic;
	   -- MISO
	   spi_in1  : in std_logic;
	   spi_in3  : in std_logic;
	   -- selects
	   spi_sela : out std_logic;
	   spi_selb : out std_logic;
	   spi_selc : out std_logic;
			   
	-- Audio / DAC output
	   spi_naudio : out std_logic;
	   spi_aclk : out std_logic;
	   spi_amosi : out std_logic;
	   nldac : out std_logic
				
	 );
	end component;
	   
	component HdmiOut is
		Port (
			qclk       : in  std_logic;
			pix_clk    : in  std_logic;
			reset      : in  std_logic;
			pix_in     : in  std_logic_vector(7 downto 0);
			hsync_in   : in  std_logic;
			vsync_in   : in  std_logic;
			tmds_clk_p : out std_logic;
			tmds_d0_p  : out std_logic;
			tmds_d1_p  : out std_logic;
			tmds_d2_p  : out std_logic
		);
	end component;

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
				pixel0	  : in  std_logic;
            h_out      : out std_logic_vector(9 downto 0);
            v_out      : out std_logic_vector(9 downto 0);
            tmds_clk_p : out std_logic;
            tmds_d0_p  : out std_logic;
            tmds_d1_p  : out std_logic;
            tmds_d2_p  : out std_logic
        );
    end component;

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

    -- Pixel position exported by HdmiTestTop (combinatorial, 270 MHz domain).
    signal h_cnt     : std_logic_vector(9 downto 0);
    signal v_cnt     : std_logic_vector(9 downto 0);

    -- Generated video signals (combinatorial, based on h_cnt / v_cnt).
    signal de_s    : std_logic;
    signal hsync_s : std_logic;
    signal vsync_s : std_logic;
    signal r_s     : std_logic_vector(7 downto 0);
    signal g_s     : std_logic_vector(7 downto 0);
    signal b_s     : std_logic_vector(7 downto 0);

	 signal pixel0	 : std_logic;
	 
begin

    top_c: Top
	port map (
	-- clock
	q50m,
	nres,
	nirq,
	
	-- CS/A out bus timing
	c8phi2,
	c2phi2,
	cphi2,

	-- config
	graphic,
	   
	-- CPU interface
	A,
        D,
        vda,
        vpa,
	rwb,
	rdy,
        phi2,
	vpb,
	e,
	mlb,
	--mx ,
	cpu_nbe,

	-- bus
	-- ROM, I/O (on CPU bus)	   
	nbe_dout,

	-- Ulti-PET / Ultra-CPU specific
	sync,
	be_in,
	nmemsel,
	niosel,
	extio,
	ioinh,
	nbe_out,
	  
	-- UPet specific
	nsel1,
	nsel2,
	nsel4,
		
	-- V/RAM interface
	VA,
	FA,
	VD,
	   
	nvramsel,
	nframsel,
	ramrwb,
	   
	dotclk0,
	pixel0,
	vga_vsync_int,
	vga_hsync_int,
	pet_vsync,

	v_out,
	   
	-- SPI
	spi_out,
	spi_clk,
	-- MISO
	spi_in1,
	spi_in3,
	-- selects
	spi_sela,
	spi_selb,
	spi_selc,
			   
	-- Audio / DAC output
	spi_naudio,
	spi_aclk,
	spi_amosi,
	nldac
	);

    test_hdmi : HdmiTestTop
    port map (
        clk54      => q50m,
        reset_n    => nres,
        de         => de_s,
        hsync      => hsync_s,	--not(vga_hsync_int),
        vsync      => vsync_s,	--not(vga_vsync_int),
        r          => r_s,
        g          => g_s,
        b          => b_s,
		  pixel0		 => pixel0,
        h_out      => h_cnt,
        v_out      => v_cnt,
        tmds_clk_p => tmds_ck,
        tmds_d0_p  => tmds_d0,
        tmds_d1_p  => tmds_d1,
        tmds_d2_p  => tmds_d2
    );

    video_gen_p : process(h_cnt, v_cnt, v_out, dotclk0)
        variable h : integer;
        variable v : integer;
    begin
        h := to_integer(unsigned(h_cnt));
        v := to_integer(unsigned(v_cnt));

        -- Data enable: high inside active display window.
        if h < H_DISPLAY and v < V_DISPLAY then
            de_s <= '1';
        else
            de_s <= '0';
        end if;

        -- Horizontal sync (negative polarity - low during pulse).
        if h >= H_DISPLAY + H_FP and h < H_DISPLAY + H_FP + H_SYNC_W then
            hsync_s <= '0';
        else
            hsync_s <= '1';
        end if;

        -- Vertical sync (negative polarity - low during pulse).
        if v >= V_DISPLAY + V_FP and v < V_DISPLAY + V_FP + V_SYNC_W then
            vsync_s <= '0';
        else
            vsync_s <= '1';
        end if;
		  
        -- Pixel colour: 8 SMPTE colour bars, 90 pixels wide each.
		  if (rising_edge(dotclk0)) then
          if h < H_DISPLAY and v < V_DISPLAY then
--            if    h <  90 then r_s <= x"FF"; g_s <= x"FF"; b_s <= x"FF"; -- White
--            elsif h < 180 then r_s <= x"F7"; g_s <= x"FF"; b_s <= x"00"; -- Yellow
--            elsif h < 270 then r_s <= x"00"; g_s <= x"FF"; b_s <= x"FF"; -- Cyan
--            elsif h < 360 then r_s <= x"00"; g_s <= x"F7"; b_s <= x"00"; -- Green
--            elsif h < 450 then r_s <= x"7F"; g_s <= x"00"; b_s <= x"FF"; -- Magenta
--            elsif h < 540 then r_s <= x"FF"; g_s <= x"00"; b_s <= x"00"; -- Red
--            elsif h < 630 then r_s <= x"00"; g_s <= x"00"; b_s <= x"FF"; -- Blue
--            else      			 r_s <= x"00"; g_s <= x"00"; b_s <= x"00"; -- Black
--            end if;
--            if    h <  90 then r_s <= x"FF"; b_s <= x"FF"; -- White
--            elsif h < 180 then r_s <= x"F7"; b_s <= x"00"; -- Yellow
--            elsif h < 270 then r_s <= x"00"; b_s <= x"FF"; -- Cyan
--            elsif h < 360 then r_s <= x"00"; b_s <= x"00"; -- Green
--            elsif h < 450 then r_s <= x"7F"; b_s <= x"FF"; -- Magenta
--            elsif h < 540 then r_s <= x"FF"; b_s <= x"00"; -- Red
--            elsif h < 630 then r_s <= x"00"; b_s <= x"FF"; -- Blue
--            else      			 r_s <= x"00"; b_s <= x"00"; -- Black
--            end if;
				r_s <= v_out(5) & v_out(4) & v_out(5) & v_out(4) & v_out(5) & v_out(4) & v_out(5) & v_out(4);
				g_s <= v_out(3) & v_out(2) & v_out(3) & v_out(2) & v_out(3) & v_out(2) & v_out(3) & v_out(2);
				b_s <= v_out(1) & v_out(0) & v_out(1) & v_out(0) & v_out(1) & v_out(0) & v_out(1) & v_out(0);
          else
            r_s <= x"00"; g_s <= x"00"; b_s <= x"00";
			 end if;
        end if;
	end process;
	
--	hdmi_out: HdmiOut
--	port map (
--		q50m,
--		dotclk0,
--		not(nres),
--		v_out(5 downto 4) & '0' & v_out(3 downto 2) & '0' & v_out(1 downto 0),
--		not(vga_hsync_int),
--		not(vga_vsync_int),
--		tmds_ck,
--		tmds_d0,
--		tmds_d1,
--		tmds_d2
--	);

	hdmi_ck_p <= tmds_ck;
	hdmi_ck_n <= not(tmds_ck);

	hdmi_d0_p <= tmds_d0;
	hdmi_d0_n <= not(tmds_d0);
	hdmi_d1_p <= tmds_d1;
	hdmi_d1_n <= not(tmds_d1);
	hdmi_d2_p <= tmds_d2;
	hdmi_d2_n <= not(tmds_d2);

end Behavioral;
