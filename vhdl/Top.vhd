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

entity Top is
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
				
	-- debug
		--dbg: in std_logic
	 );
	 attribute system_jitter: string;
	 attribute system_jitter of q50m: signal is "10 ps";
	 attribute maxskew: string;
	 attribute maxskew of q50m : signal is "3 ns";
	 attribute maxdelay: string;
	 attribute maxdelay of q50m : signal is "3 ns";
end Top;

architecture Behavioral of Top is

	type T_VADDR_SRC is (VRA_NONE, VRA_IPL, VRA_CPU, VRA_VIDEO, VRA_DAC);
	type T_FADDR_SRC is (FRA_NONE, FRA_CPU);
	type T_BUS_STATE is (BUS_NONE, BUS_CPU, BUS_SETUP, BUS_WAIT);
	type T_IPL_STATE is (IPL_SETTLE, IPL_CMD, IPL_LOAD, IPL_DONE);
	
	attribute NOREDUCE : string;
	
	-- control
	signal s0_d: std_logic_vector(7 downto 0);
	
	-- Initial program load
	signal ipl: std_logic;		-- Initial program load from SPI flash
	signal ipl_d: std_logic;		-- Initial program load from SPI flash
	constant ipl_addr: std_logic_vector(18 downto 8) := "00011111111";	-- top most RAM page in bank 0
	signal ipl_state: T_IPL_STATE;
	signal ipl_state_d: T_IPL_STATE;
	signal ipl_is_load: std_logic;
	signal ipl_is_flash: std_logic;
	signal ipl_cnt: std_logic_vector(11 downto 0); -- 11-4: block address count, 3-0: SPI state count
	signal ipl_out: std_logic;	-- SPI output from IPL to flash
	signal ipl_next: std_logic;	-- start next phase
	
	signal spi_slowclk: std_logic;
	
	-- clock
	signal dotclk: std_logic_vector(3 downto 0);
	signal vid_fetch: std_logic;
	signal VA_select: T_VADDR_SRC;
	signal VA_select_d: T_VADDR_SRC;
	signal va_is_cpu_d: std_logic;
	signal FA_select: T_FADDR_SRC;
	
	signal memclk: std_logic;
	signal cp00: std_logic;		-- clk enable on qclk falling when memclk is in the middle of low
	signal cp01: std_logic;		-- clk enable on qclk falling when memclk is going low to high
	signal cp10: std_logic;		-- clk enable on qclk falling when memclk is going high to low
	signal cp11: std_logic;		-- clk enable on qclk falling when memclk is in the middle of high
	
	signal clk1m: std_logic;
	signal clk2m: std_logic;
	signal clk4m: std_logic;
	signal cphi2_int: std_logic;
	
	signal phi2_int: std_logic;
	signal phi2_out: std_logic;
	signal is_cpu: std_logic;
	signal is_cpu_trigger: std_logic;
		
	-- CPU memory mapper
	signal cfgld_in: std_logic;
	signal ma_out: std_logic_vector(19 downto 8);
	--signal ma_vout: std_logic_vector(13 downto 12);
	signal m_framsel_out: std_logic;
	signal m_vramsel_out: std_logic;
	signal m_ffsel_out: std_logic;
	signal nvramsel_int: std_logic;
	signal nframsel_int: std_logic;
	signal m_iosel: std_logic;
	signal m_iowin: std_logic;
	signal m_memsel: std_logic;

	signal sel0 : std_logic;
	signal vid_sel : std_logic;
	
	signal mode : std_logic_vector(1 downto 0);
	signal boot : std_logic;
	signal wp_rom9 : std_logic;
	signal wp_romA : std_logic;
	signal wp_romB : std_logic;
	signal wp_romPET : std_logic;
	signal is8296 : std_logic;
	signal lowbank : std_logic_vector(3 downto 0);
	signal vidblock : std_logic_vector(2 downto 0);
	signal lockb0 : std_logic;
	signal forceb0 : std_logic;
	signal m_dbg_out: std_logic;
	
	-- video
	signal va_out: std_logic_vector(15 downto 0);
	signal vd_in: std_logic_vector(7 downto 0);
	signal vd_out: std_logic_vector(7 downto 0);
	signal vis_enable: std_logic;
	signal vis_80_in: std_logic;
	signal vgraphic: std_logic;
	signal screenb0: std_logic;
	signal isnocolmap: std_logic;
	signal v_out: std_logic_vector(5 downto 0);
	signal vis_regmap: std_logic;		-- when set, Viccy occupies not 4, but 96 addresses due to register-to-memory mapping
	signal v_dbg_out: std_logic;
	
	-- cpu
	signal ca_in: std_logic_vector(15 downto 0);
	signal cd_in: std_logic_vector(7 downto 0);
	signal reset: std_logic;
	signal irq_out: std_logic;
	signal wait_ram: std_logic;
	signal wait_bus: std_logic;	-- when CPU waits for end of CS/A bus cycle
	signal wait_setup: std_logic;	-- when CPU needs to wait for setup time
	signal is_bus: std_logic;
	signal is_bus_a: std_logic;	-- bus access where memclk is on wrong phase with phi2 going down
	signal wait_int: std_logic;
	signal ramrwb_int: std_logic;
	signal do_cpu : std_logic;

	-- video RAMarbiter
	signal vreq_video: std_logic;
	signal vreq_dac: std_logic;
	signal vreq_cpu: std_logic;
	signal vreq_ipl: std_logic;
	
	-- SPI
	signal spi_dout : std_logic_vector(7 downto 0);
	signal spi_cs : std_logic;
	signal spi_in : std_logic;
	signal spi_sel : std_logic_vector(2 downto 0);
	signal spi_outx : std_logic;
	signal spi_clkx : std_logic;
	
	-- bus
	signal niosel_int: std_logic;
	signal nmemsel_int: std_logic;
	signal chold: std_logic;
	signal csetup: std_logic;
	signal be_out_int: std_logic;
	
	signal bus_window_c: std_logic;	-- map $00Cxxx to MEMSEL too
	signal bus_window_9: std_logic; -- map $009xxx to MEMSEL
	signal bus_win_9_is_io: std_logic;
	signal bus_win_c_is_io: std_logic;
	signal page9_map: std_logic_vector(7 downto 0);
	signal pageA_map: std_logic_vector(7 downto 0);
	
	signal bus_state: T_BUS_STATE;
	signal bus_state_d: T_BUS_STATE;
	
	-- DAC
	signal dac_sel: std_logic;
	signal dac_dma_req: std_logic;
	signal dac_dma_ack: std_logic;
	signal dac_dma_addr: std_logic_vector(19 downto 0);
	signal dac_dout: std_logic_vector(7 downto 0);
	signal dac_irq: std_logic;
	signal nldac_int: std_logic;
	
	-- components
	
	component Clock is
	  Port (
	   qclk 	: in std_logic;		-- input clock
	   reset	: in std_logic;
	   
	   memclk 	: out std_logic;	-- memory access clock signal
		cp00: out std_logic;		-- clk enable on qclk falling when memclk is in the middle of low
		cp01: out std_logic;		-- clk enable on qclk falling when memclk is going low to high
		cp10: out std_logic;		-- clk enable on qclk falling when memclk is going high to low
		cp11: out std_logic;		-- clk enable on qclk falling when memclk is in the middle of high
	   
	   clk1m 	: out std_logic;	-- trigger CPU access @ 1MHz
	   clk2m	: out std_logic;	-- trigger CPU access @ 2MHz
	   clk4m	: out std_logic;	-- trigger CPU access @ 4MHz
	   
	   -- CS/A out bus timing
	   c8phi2	: out std_logic;
	   c2phi2	: out std_logic;
	   cphi2	: out std_logic;
	   chold	: out std_logic;
	   csetup	: out std_logic;
	   
	   dotclk	: out std_logic_vector(3 downto 0)	-- pixel clock for video
	 );
	end component;
	   
	component Mapper is
	  Port ( 
	   A : in  STD_LOGIC_VECTOR (15 downto 8);
           D : in  STD_LOGIC_VECTOR (7 downto 0);
	   reset : in std_logic;
	   phi2: in std_logic;
	   vpa: in std_logic;
	   vda: in std_logic;
	   vpb: in std_logic;
	   rwb : in std_logic;
	   
	   qclk : in std_logic;
	   
      cfgld : in  STD_LOGIC;	-- set when loading the cfg
	   
      RA : out std_logic_vector (19 downto 8);	-- mapped CPU address (FRAM)

	   ffsel: out std_logic;
	   iosel: out std_logic;
		iowin: out std_logic;
	   memsel: out std_logic;
	   vramsel: out std_logic;
	   framsel: out std_logic;

	   boot: in std_logic;
	   lowbank: in std_logic_vector(3 downto 0);
	   vidblock: in std_logic_vector(2 downto 0);
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
		pageA_map: in std_logic_vector(7 downto 0);

	   forceb0: in std_logic;
	   screenb0: in std_logic;
	   is8296: in std_logic;
		isnocolmap: in std_logic;
	   dbgout: out std_logic
	  );
	end component;
	
	component Video is
	  Port ( 
	   A : out  STD_LOGIC_VECTOR (15 downto 0);
	   CPU_D : in std_logic_vector (7 downto 0);
		VRAM_D: in std_logic_vector (7 downto 0);
		vd_out: out std_logic_vector(7 downto 0);

	   phi2 : in std_logic;
	   
	   --dena   : out std_logic;	-- display enable
      v_sync : out  STD_LOGIC;
      h_sync : out  STD_LOGIC;
	   pet_vsync: out std_logic;	-- for the PET screen interrupt

	   is_enable: in std_logic;	-- is display enabled
		is_80_in: in std_logic;
	   is_graph : in std_logic;	-- from PET I/O
	   
	   crtc_sel : in std_logic;	-- select line for CRTC
	   crtc_rs  : in std_logic_vector(6 downto 0);	-- register select
	   crtc_rwb : in std_logic;	-- r/-w
	   mode_regmap: out std_logic;
	   
	   qclk: in std_logic;		-- Q clock
		dotclk: in std_logic_vector(3 downto 0);	-- pixel clock
	   
	   vid_fetch : out std_logic; 	-- true during video memory fetch by Viccy
	   vreq_video: out std_logic;		-- true when *next* vram access should be video
		
	   --sr_load : in std_logic;
	   vid_out : out std_logic_vector(5 downto 0);
	
		irq_out : out std_logic;
		
		dbg_out : out std_logic;
	   reset : in std_logic
	 );
	end component;

   component DAC is
	Port (
		phi2: in std_logic;
		sel: in std_logic;
		rwb: in std_logic;
		regsel: in std_logic_vector(3 downto 0);
		din: in std_logic_vector(7 downto 0);
		dout: out std_logic_vector(7 downto 0);
		irq: out std_logic;
		
		qclk: in std_logic;
		dotclk: in std_logic_vector(1 downto 0);
		vdin: in std_logic_vector(7 downto 0);

		dma_req: out std_logic;
		dma_ack: in std_logic;		-- on falling edge data is taken
		dma_addr: out std_logic_vector(19 downto 0);

		spi_naudio: out std_logic;
		spi_aclk: out std_logic;
		spi_amosi: out std_logic;
		nldac: out std_logic;

		reset: in std_logic
	);
   end component;

	component SPI is
	  Port ( 
	   phi2: in std_logic;
	   DIN : in  STD_LOGIC_VECTOR (7 downto 0);
	   DOUT : out  STD_LOGIC_VECTOR (7 downto 0);
	   RS: in std_logic_vector(1 downto 0);
	   RWB: in std_logic;
	   CS: in std_logic;	-- includes clock
	   
	   serin: in std_logic;
	   serout: out std_logic;
	   serclk: out std_logic;
	   sersel: out std_logic_vector(2 downto 0);	   
	   spiclk : in std_logic;
	   spislowclk: in std_logic;
	   
	   ipl: in std_logic;
	   reset : in std_logic
	 );
	end component;

	function To_Std_Logic(L: BOOLEAN) return std_ulogic is
	begin
		if L then
			return('1');
		else
			return('0');
		end if;
	end function To_Std_Logic;

begin

	cpu_nbe <= '0';
	
	clocky: Clock
	port map (
	   q50m,
	   reset,
	   memclk,
		cp00,
		cp01,
		cp10,
		cp11,
	   clk1m,
	   clk2m,
	   clk4m,
	   c8phi2,
	   c2phi2,
	   cphi2_int,
	   chold,
	   csetup,
	   dotclk
	);

	-- shorten bus phi2 a tad bit on write cycles, to keep bus hold time
	-- for slightly slower devices.
	cphi2 <= cphi2_int and (chold or rwb or not(is_bus));
	
	reset <= not(nres);
	
	nirq <= '0' when irq_out = '1' or dac_irq = '1' else 'Z';
	
	-- define CPU slots.
	-- mode(1 downto 0): 00=1MHz, 01=2MHz, 10=4MHz, 11=Max speed

	is_cpu_trigger <= '1'	when mode = "11" else
			clk4m	when mode = "10" else
			clk2m	when mode = "01" else
			clk1m;
	
	-- depending on mode, goes high when we have a CPU access pending,
	-- and else low when a CPU access is done
	is_cpu_p: process(reset, q50m, dotclk, is_cpu_trigger, is_cpu, do_cpu, mode, cp10)
	begin
		if (reset = '1') then
			is_cpu <= '0';
		elsif (rising_edge(q50m) and dotclk(1 downto 0) = "11") then
		--elsif (falling_edge(q50m) and cp10 = '1') then
			if (mode = "11") then
				is_cpu <= '1';
 			elsif (is_cpu_trigger = '1') then
				is_cpu <= '1';
			elsif (do_cpu = '1') then
				is_cpu <= '0';
			end if;
		end if;
	end process;

	-- vreq_cpu is sampled at falling edge of phi2 (phi2to1)
	-- so using is_cpu directly is a race condition, as it falls with falling phi2.
	vreq_cpu <= is_cpu_trigger or is_cpu;
	
	
	-- stretch clock such that we approx. one cycle per is_cpu_trigger (1, 2, 4MHz)
	-- wait_int rises with falling edge of memclk (see trigger above), or is 
	-- constant low (full speed)
	wait_int <= not(is_cpu);
		
	-- do_cpu is set when the coming falling edge of memclk should be active for the CPU
	release2_p: process(q50m, reset, cp11) 
	begin
		if (reset = '1') then
			do_cpu <= '0';
		--elsif (rising_edge(q50m) and dotclk(1 downto 0) = "11") then
		elsif (falling_edge(q50m) and cp11 = '1') then
			if (	(is_bus = '0' 
					and wait_int = '0' and wait_ram = '0')
				or (is_bus = '1' 
					and wait_setup = '0' and wait_bus = '0')
				) then
				do_cpu <= '1';
			else
				do_cpu <= '0';
			end if;
		end if;
	end process;
	
	------------------------------------------------------
	-- bus timing

	bus_stat_p: process(reset, q50m, is_bus, chold, csetup, dotclk, cp11, cp00)
	begin
		if (reset = '1') then
			bus_state <= BUS_NONE;
		elsif (rising_edge(q50m) and dotclk(1 downto 0) = "10") then
			if (is_bus = '0') then
				bus_state <= BUS_NONE;
			elsif (csetup = '1') then
				if (is_bus_a = '0') then
					bus_state <= BUS_SETUP;
				else
					bus_state <= BUS_NONE;
				end if;
			elsif (bus_state_d = BUS_SETUP) then
				if (chold = '0') then
					-- get away from BUS_SETUP, so CPU clock goes low for actual access at hi/lo transition
					bus_state <= BUS_CPU;
				end if;
			else
				bus_state <= BUS_WAIT;
			end if;
		end if;
			
		if (reset = '1') then
			is_bus_a <= '0';
		elsif (falling_edge(q50m) and cp00 = '1') then
			if (bus_state_d = BUS_SETUP
					and chold = '0') then
				is_bus_a <= '1';
			else
				is_bus_a <= '0';
			end if;
		end if;
		
		if (falling_edge(q50m) and cp11 = '1') then
			bus_state_d <= bus_state;
		end if;
		
	end process;

	wait_setup <= '1' when bus_state = BUS_SETUP else '0';
	wait_bus <= '1' when bus_state = BUS_WAIT else '0';
	

	-- Note if we use phi2 without setting it high on waits (and would use RDY instead), 
	-- the I/O timers will always count on 8MHz - which is not what we want (at 1MHz at least)
	phi2_int <= (memclk or not(do_cpu)) and not(ipl) when is_bus_a = '0'
					else not(csetup);
	
	phi2_out <= phi2_int; -- or wait_bus or wait_setup;
	
	phi2 <= phi2_out;
		
	------------------------------------------------------
	-- CPU memory mapper
	
	cd_in <= D;
	ca_in <= A;
	vd_in <= VD;

	mappy: Mapper
	port map (
	   ca_in(15 downto 8),
      cd_in,
	   reset,
	   phi2_int,
	   vpa,
	   vda,
	   vpb,
	   rwb,
	   q50m,
           cfgld_in,
	   ma_out,
	   --ma_vout,
	   m_ffsel_out,
	   m_iosel,
		m_iowin,
	   m_memsel,
	   m_vramsel_out,
	   m_framsel_out,
	   boot,
	   lowbank,
	   vidblock,
	   wp_rom9,
	   wp_romA,
	   wp_romB,
	   wp_romPET,
	   bus_window_9,
	   bus_window_c,
		bus_win_9_is_io,
		bus_win_c_is_io,
		page9_map,
		pageA_map,
	   forceb0,
	   screenb0,
		is8296,
		isnocolmap,
		m_dbg_out
	);

	forceb0 <= '1' when lockb0 = '1' and e = '1' else
		'0';
		
	cfgld_in <= '1' when is8296 = '1' and m_ffsel_out ='1' and ca_in(7 downto 0) = x"F0" else '0';

	-- internal selects
	-- $e800-$e80b. Note that $e80c-$e80f is now the I2C controller
	sel0 		<= '1' when m_iosel = '1' and ca_in(7 downto 4) = x"0" and (ca_in(3) = '0' or ca_in(2) = '0') else '0';
	dac_sel 	<= '1' when m_iosel = '1' and ca_in(7 downto 4) = x"3" else '0';
	vid_sel	<= '1' when m_iosel = '1' and 
							((vis_regmap = '0' and ca_in(7 downto 4) = x"8")
							or (vis_regmap = '1' and ca_in(7) = '1' and not(ca_in(6 downto 5) = "11")))
						else '0';

	nbussel_p: process(reset, memclk)
	begin
		if (reset = '1') then
			niosel <= '1';
			nmemsel <= '1';
		elsif (falling_edge(memclk)) then
			niosel <= niosel_int
					or wait_bus; 
			nmemsel <= nmemsel_int
					or wait_bus;
--	nmemsel <= v_dbg_out; FIXME
	
			if (niosel_int = '0'
				and ca_in(7 downto 4) = "0001") then
				nsel1 <= '0';
			else
				nsel1 <= '1';
			end if;

			if (niosel_int = '0'
				and ca_in(7 downto 4) = "0010") then
				nsel2 <= '0';
			else
				nsel2 <= '1';
			end if;
			
			if (niosel_int = '0'
				and ca_in(7 downto 4) = "0100") then
				nsel4 <= '0';
			else
				nsel4 <= '1';
			end if;
			
		end if;
	end process;
	
	-- external selects are inverted
	niosel_int <= --'0' when extio = '1'			-- external I/O
			--else '1' when ioinh = '1'	-- I/O inhibit
			--else 
			'0' when (m_iosel = '1'  
					and sel0 = '0' and vid_sel = '0' and dac_sel = '0')
				or (m_iowin = '1')
			else '1';

	nmemsel_int <= not (m_memsel); -- not for now

	is_bus <= not(niosel_int and nmemsel_int);
	
	-------------
	-- CS/A bus
	
	sync <= vda and vpa;

	be_p: process(reset, memclk)
	begin
		if(reset = '1') then
			be_out_int <= '0';
		elsif (rising_edge(memclk)) then
			be_out_int <= not(
				(niosel_int and nmemsel_int) 
				or wait_bus
				or be_in
				);
		end if;
	end process;
	nbe_out <= not( be_out_int );
	nbe_dout <=  not( be_out_int ) or not(phi2_int);
	
	------------------------------------------------------
	-- video
	--
	viccy: Video
	port map (
		va_out,
		cd_in, 
		vd_in,
		vd_out,
		phi2_int,
		vsync,
		hsync,
		pet_vsync,
		vis_enable,
		vis_80_in,
		vgraphic,
		vid_sel,
		ca_in(6 downto 0),
		rwb,
		vis_regmap,
		q50m,		-- Q clock (50MHz)
		dotclk,	-- pixel clock, 25MHz
		vid_fetch,
		vreq_video,
		v_out,
		irq_out,
		v_dbg_out,
		reset
	);

	vgraphic <= not(graphic);
	
	pxl_out <= v_out;

	------------------------------------------------------
	-- DAC interface

	dac_comp: DAC
	port map (
		phi2_int,
		dac_sel,
		rwb,
		ca_in(3 downto 0),
		cd_in,
		dac_dout,
		dac_irq, 
		
		q50m,
		dotclk(1 downto 0),
		vd_in,

		dac_dma_req,
		dac_dma_ack,
		dac_dma_addr,

		spi_naudio,
		spi_aclk,
		spi_amosi,
		nldac_int,

		reset
	);
	
	nldac <= nldac_int;
	
	------------------------------------------------------
	-- SPI interface
	
	spi_comp: SPI
	port map (
	   phi2_int,
	   cd_in,
	   spi_dout,
	   ca_in(1 downto 0),
	   rwb,
	   spi_cs,
	   spi_in,
	   spi_outx,
	   spi_clkx,
	   spi_sel,
	   memclk,		-- dotclk(1)
		spi_slowclk,	-- slow clock
		
	   ipl_is_load,
	   reset
	);

	--spi_slowclk <= dotclk(2);
	spi_slowclk <= clk1m;
	
	-- CPU access to SPI registers
	spi_cs <= To_Std_Logic(sel0 = '1' and ca_in(3) = '1' and ca_in(2) = '0');
	
	-- SPI serial data in - shared except IN3 for SD card
	spi_in <= spi_in3 when spi_sel = "011" else
			spi_in1;
	
	-- SPI serial data out
	spi_out <= ipl_out	when ipl_is_flash = '1' 	else
		spi_outx;
		
	-- SPI serial clock
	spi_clk <= ipl_cnt(0)	when ipl_is_flash = '1' else
		spi_clkx;
	
	spi_sela <= '1' 	when reset = '1' else
				'1' 	when ipl_is_flash = '1' else
				spi_sel(0);
				
	spi_selb <= '1'	when reset = '1' else
				'0'	when ipl_is_flash = '1' else
				spi_sel(1);
				
	spi_selc <= '1' 	when reset = '1' else
				'0' 	when ipl_is_flash = '1' else
				spi_sel(2);
	
	
	------------------------------------------------------
	-- control registers
	
	Ctrl_P: process(sel0, phi2_int, rwb, reset, ca_in, D)
	begin
		if (reset = '1') then
			vis_80_in <= '0';
			vis_enable <= '1';
			mode <= "00";
			screenb0 <= '1';
			isnocolmap <= '0';
			wp_rom9 <= '0';
			wp_romA <= '0';
			wp_romPET <= '0';
			is8296 <= '0';
			lowbank <= (others => '0');
			vidblock <= "010";
			boot <= '1';
			lockb0 <= '0';
			bus_window_c <= '0';
			bus_window_9 <= '0';
			bus_win_c_is_io <= '0';
			bus_win_9_is_io <= '0';
			page9_map <= "00001001";
			pageA_map <= "00001010";
		elsif (falling_edge(phi2_int) and sel0='1' and rwb='0' and ca_in(3) = '0') then
			-- Write to $E80x
			case (ca_in(2 downto 0)) is
			when "000" =>
				-- video controls
				vis_80_in <= D(1);
				screenb0 <= not(D(2));
				isnocolmap <= D(3);
				vis_enable <= not(D(7));
			when "001" =>
				-- memory map controls
				lockb0 <= D(0);
				boot <= D(1);
				is8296 <= D(3);
				wp_rom9 <= D(4);
				wp_romA <= D(5);
				wp_romB <= D(6);
				wp_romPET <= D(7);
			when "010" =>
				-- bank controls
				lowbank <= D(3 downto 0);
			when "011" =>
				-- speed controls
				mode(1 downto 0) <= D(1 downto 0); -- speed bits
			when "100" =>
				-- bus controls
				bus_window_9 <= D(0);
				bus_window_c <= D(1);
				bus_win_9_is_io <= D(2);
				bus_win_c_is_io <= D(3);
			when "101" =>
				-- video bank controls
				vidblock <= D(2 downto 0);
			when "110" =>
				-- page 9 map
				page9_map <= D;
			when "111" =>
				-- page A map
				pageA_map <= D;
			when others =>
				null;
			end case;
		end if;
	end process;

	Ctrl_Rd: process(sel0, phi2_int, rwb, reset, ca_in, D,
		vis_80_in, screenb0, isnocolmap, vis_enable, lockb0, boot, is8296, 
		wp_rom9, wp_roma, wp_romb, wp_rompet, lowbank, mode,
		bus_window_9, bus_window_c, bus_win_9_is_io, bus_win_c_is_io,
		vidblock, page9_map, pageA_map
	)
	begin
	
		s0_d <= (others => '0');

		if (sel0='1' and rwb='1' and ca_in(3) = '0') then
			-- Read from to $E80x			
			case (ca_in(2 downto 0)) is
			when "000" =>
				-- video controls
				s0_d(1) <= vis_80_in;
				s0_d(2) <= not(screenb0);
				s0_d(3) <= isnocolmap;
				s0_d(7) <= not(vis_enable);
			when "001" =>
				-- memory map controls
				s0_d(0) <= lockb0;
				s0_d(1) <= boot;
				s0_d(3) <= is8296;
				s0_d(4) <= wp_rom9;
				s0_d(5) <= wp_romA;
				s0_d(6) <= wp_romB;
				s0_d(7) <= wp_romPET;
			when "010" =>
				-- bank controls
				s0_d(3 downto 0) <= lowbank;
			when "011" =>
				-- speed controls
				s0_d(1 downto 0) <= mode(1 downto 0); -- speed bits
			when "100" =>
				-- bus controls
				s0_d(0) <= bus_window_9;
				s0_d(1) <= bus_window_c;
				s0_d(2) <= bus_win_9_is_io;
				s0_d(3) <= bus_win_c_is_io;
			when "101" =>
				-- video bank controls
				s0_d(2 downto 0) <= vidblock;
			when "110" =>
				-- page 9 map
				s0_d <= page9_map;
			when "111" =>
				-- page A map
				s0_d <= pageA_map;
			when others =>
				s0_d <= (others => '0');
			end case;
		end if;
	end process;



	v_out_p: process(q50m, memclk, nvramsel_int, nframsel_int, ipl, reset,
			vid_fetch, rwb, m_vramsel_out, dac_dma_req, is_cpu, is_cpu_trigger)
	begin
		if (reset = '1') then
			--ramrwb_int	<= '1';
			--nframsel <= '1';
			--nvramsel <= '1';
		elsif (rising_edge(q50m)) then
--		elsif (falling_edge(q50m)) then
				
			--if (dotclk(0) ='0') then
			--end if;
		end if;
		
				nvramsel <= nvramsel_int;
				nframsel <= nframsel_int;
		
		vreq_ipl <= ipl;
		vreq_dac <= dac_dma_req;
		
		if (reset = '1') then
			VA_select <= VRA_NONE;
			FA_select <= FRA_NONE;
		elsif (falling_edge(q50m)) then 
			if (cp10 = '1') then
				-- at end of previous cycle we determine whichh type we have
				if (vreq_ipl = '1') then
					VA_select <= VRA_IPL;
				elsif (vreq_video = '1') then
					VA_select <= VRA_VIDEO;
				elsif (vreq_dac = '1') then
					VA_select <= VRA_DAC;
				elsif (vreq_cpu = '1') then
					-- potential CPU access (depending on vramsel)
					VA_select <= VRA_CPU;
				else
					--VA_select <= VRA_CPU;
					VA_select <= VRA_NONE; 
				end if;
				
				if (vreq_cpu = '1') then
					FA_select <= FRA_CPU;
				else
					FA_select <= FRA_NONE;
				end if;
				
				-- vram select goes inactive here
				nvramsel_int <= '1';
				nframsel_int <= '1';
				ramrwb_int <= '1';
				
			elsif (cp01 = '1') then
				-- at the middle of the cycle we enable vram access if needed
				case (VA_select) is
				when VRA_IPL =>
					nvramsel_int <= '0';
					wait_ram <= m_vramsel_out;
					ramrwb_int <= '0';
				when VRA_NONE =>
					nvramsel_int <= '1';
					wait_ram <= m_vramsel_out;
					ramrwb_int <= '1';
				when VRA_CPU =>
					nvramsel_int <= not(m_vramsel_out);
					wait_ram <= '0';
					ramrwb_int <= rwb or not( m_vramsel_out );
				when others =>
					nvramsel_int <= '0';
					wait_ram <= m_vramsel_out;
					ramrwb_int <= '1';
				end case;
				
				case (FA_select) is
				when FRA_CPU =>
					nframsel_int <= not(m_framsel_out);
				when others =>
					nframsel_int <= '1';
				end case;
				
			end if;

		end if;
				
		if (rising_edge(q50m)) then
--			if (VA_select = VRA_CPU) then
--				va_is_cpu_d <= '1';
--			else
--				va_is_cpu_d <= '0';
--			end if;
			
			VA_select_d <= VA_select;
		end if;
		
	end process;

	
	v_out_p2: process(q50m, memclk, VA_select, reset,
			rwb, ipl_cnt, ca_in, ma_out, dac_dma_addr, va_out, VA_select_d)
	begin

		-- keep VA, ramrwb etc stable one half qclk cycle after
		-- de-select.
		if (reset = '1') then
			dac_dma_ack <= '0';
		elsif (falling_edge(q50m)) then
		
			-- RAM R/W (only for video RAM, FRAM gets /WE from CPU's RWB)
			
			dac_dma_ack <= '0';
			
			if (VA_select = VRA_DAC) then
				dac_dma_ack <= '1';
			end if;
		end if;

		-- delay A, R/-W a bit to implement hold times
			case (VA_select_d) is
			when VRA_IPL =>
				VA(7 downto 0) <= ipl_cnt(11 downto 4);
				VA(18 downto 8) <= ipl_addr(18 downto 8);
			when VRA_CPU =>
				VA(7 downto 0) <= ca_in (7 downto 0);
				VA(18 downto 8) <= ma_out (18 downto 8);
			when VRA_DAC =>
				VA <= dac_dma_addr(18 downto 0);
			when VRA_VIDEO =>  
				VA(15 downto 0) <= va_out(15 downto 0);
				VA(18 downto 16) <= (others => '0');
			when others =>
				VA 	<= (others => '0');
			end case;
						
	end process;

	ramrwb <= ramrwb_int; 


	
	FA(19 downto 16) <= 	ma_out(19 downto 16);
	FA(15) <=		ma_out(15);
			
--	-- data transfer between CPU data bus and video/memory data bus
--	VD <= 	spi_dout	when ipl = '1' 		else	-- IPL
--		D 		when va_is_cpu_d = '1' and ramrwb_int = '0' else	-- CPU write
--		(others => 'Z');
	vd_out_p: process(spi_dout, D, VA_select_d, ramrwb_int)
	begin
		case (VA_select_d) is
		when VRA_IPL =>	
			VD <= spi_dout;
		when VRA_CPU =>
			if (ramrwb_int = '0') then
				VD <= D;
			else
				VD <= (others => 'Z');
			end if;
		when others =>
				VD <= (others => 'Z');
		end case;
	end process;
	
	D <= 	
		(others => 'Z') when
			rwb = '0' 
			or phi2_int = '0'
		else
			VD when VA_select_d = VRA_CPU
				and m_vramsel_out ='1' 
		else
			spi_dout when spi_cs = '1'
		else
			vd_out when vid_sel = '1'
		else
			dac_dout when dac_sel = '1'
		else
			s0_d when sel0 = '1'
		else
			(others => 'Z');
		
	
	------------------------------------------------------
	-- IPL logic
	
	ipl_is_load <= '1' when ipl_state = IPL_LOAD else '0';
	ipl_is_flash <= '1' when ipl_state = IPL_CMD or ipl_state = IPL_LOAD else '0';

	ipl_p: process(q50m, dotclk, reset, ipl, ipl_d)
	begin
		if (reset = '1') then 
			ipl_state <= IPL_SETTLE;
			ipl_cnt <= (others => '0');
			ipl <= '1';
		--elsif (falling_edge(memclk) and ipl_d = '1') then
		elsif (falling_edge(q50m) and dotclk(1 downto 0) = "11" and ipl_d = '1') then
		
			--ipl <= '0';	-- block IPL to test
			case (ipl_state_d) is
			when IPL_SETTLE =>
				-- settle to allow for spi_clk pin to transfer to IO
				if (ipl_next = '1') then
					ipl_state <= IPL_CMD;
					ipl_cnt <= (others => '0');
				else
					ipl_cnt <= ipl_cnt + 1;
				end if;
			when IPL_CMD =>
				-- initial count and SPI Flash read command				
				if (ipl_next = '1') then
					ipl_state <= IPL_LOAD;
					ipl_cnt <= (others => '0');
				else
					ipl_cnt <= ipl_cnt + 1;
				end if;
			when IPL_LOAD =>
				-- read block
				if (ipl_next = '1') then
					ipl <= '0';
					ipl_state <= IPL_DONE;
				else
					ipl_cnt <= ipl_cnt + 1;
				end if;
			when others =>
			end case;
		end if;
	end process;
	
	ipl_state_p: process(reset, q50m, dotclk, ipl_state)
	begin
		if (reset = '1') then
			ipl_next <= '0';
			ipl_out <= '0';
			ipl_d <= '1';
		--elsif (rising_edge(memclk)) then
		elsif (falling_edge(q50m) and dotclk(1 downto 0) = "01") then
			ipl_state_d <= ipl_state;
			ipl_d <= ipl;
			
			ipl_next <= '0';
			case (ipl_state) is
			when IPL_SETTLE =>
				if (ipl_cnt = "000001000000") then
					ipl_next <= '1';
				end if;
			when IPL_CMD =>
				if (ipl_cnt = "000001000000") then
					ipl_next <= '1';
				end if;
				
				if (ipl_cnt >= "000000001011"
					and ipl_cnt <= "000000001110"
					) then
					ipl_out <= '1';
				else
					ipl_out <= '0';
				end if;
			when IPL_LOAD =>
				if (ipl_cnt = "111111111111") then
					ipl_next <= '1';
				end if;
				 
				ipl_out <= '0';
			when others =>
			end case;
		end if;
	end process;


end Behavioral;
