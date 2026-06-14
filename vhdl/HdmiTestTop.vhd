----------------------------------------------------------------------------------
-- Module:      HdmiTestTop
-- Description: 720x480p60 HDMI TMDS encoder / serialiser.
--              Requires only a 54 MHz input clock; accepts pixel video signals
--              (de, hsync, vsync, r, g, b) from the caller and outputs the TMDS
--              serial stream.  Pixel position (h_out, v_out) is exported so
--              the caller can generate the correct video signals for each pixel.
--
-- Video format: 720x480p 59.94/60 Hz (CEA-861 format 2/3)
--   ModeLine: 27.00 720 736 798 858 480 489 495 525 -HSync -VSync
--   Pixel clock : 27 MHz
--   TMDS serial : 270 MHz  (10x pixel clock, generated internally by PLL)
--
-- TMDS channel assignment (HDMI):
--   D0 = Blue  — carries VSYNC/HSYNC control codes during blanking
--   D1 = Green — carries 0/0 control codes during blanking
--   D2 = Red   — carries 0/0 control codes during blanking
--
-- Target: Xilinx Spartan-6 (uses PLL_BASE and BUFG from UNISIM)
--         Differential outputs are driven by simple inversion; constrain
--         the pins to TMDS_33 I/O standard in the UCF file.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library UNISIM;
use UNISIM.VComponents.all;

entity HdmiTestTop is
    Port (
        clk54      : in  std_logic;   -- 54 MHz board clock
        reset_n    : in  std_logic;   -- active-low reset
        -- Video inputs (driven combinatorially by caller based on h_out/v_out)
        de         : in  std_logic;                      -- data enable
        hsync      : in  std_logic;                      -- horizontal sync
        vsync      : in  std_logic;                      -- vertical sync
        r          : in  std_logic_vector(7 downto 0);   -- red channel
        g          : in  std_logic_vector(7 downto 0);   -- green channel
        b          : in  std_logic_vector(7 downto 0);   -- blue channel
		  
        -- Pixel position outputs (for caller to generate video signals)
        h_out      : out std_logic_vector(9 downto 0);   -- horizontal pixel index
        v_out      : out std_logic_vector(9 downto 0);   -- vertical line index
        -- TMDS differential outputs
        tmds_clk_p : out std_logic;
        tmds_d0_p  : out std_logic;
        tmds_d1_p  : out std_logic;
        tmds_d2_p  : out std_logic
    );
end HdmiTestTop;

architecture Behavioral of HdmiTestTop is

    ---------------------------------------------------------------------------
    -- 720x480p60 frame dimensions.
    -- Only the total counts are needed here; the caller supplies timing signals.
    --   H_TOTAL = H_DISPLAY(720) + H_FP(16) + H_SYNC_W(62) + H_BP(60) = 858
    --   V_TOTAL = V_DISPLAY(480) + V_FP(9)  + V_SYNC_W(6)  + V_BP(30) = 525
    ---------------------------------------------------------------------------
    constant H_TOTAL   : integer := 858;
    constant V_TOTAL   : integer := 525;

    ---------------------------------------------------------------------------
    -- PLL / clock signals
    --   PLL input  : 54 MHz
    --   VCO        : 54 * 10 = 540 MHz  (within Spartan-6 PLL VCO range 400-1000 MHz)
    --   CLKOUT0/2  : 540 / 2 = 270 MHz  (10x pixel clock, TMDS serial clock)
    ---------------------------------------------------------------------------
    signal pll_fb      : std_logic;
    signal pll_lock    : std_logic;
    signal clk_ser_raw : std_logic;
    signal clk_ser     : std_logic;   -- 270 MHz, global buffer

    signal reset       : std_logic;

    ---------------------------------------------------------------------------
    -- Video / serialiser state (all in the 270 MHz domain)
    --   One pixel = 10 serial clock cycles  (270 / 27 = 10)
    --   ser_cnt counts 0..9; at ser_cnt=9 the current pixel is encoded and
    --   the counters advance to the next pixel.
    ---------------------------------------------------------------------------
    signal h_cnt   : integer range 0 to H_TOTAL  - 1;
    signal v_cnt   : integer range 0 to V_TOTAL  - 1;
    signal ser_cnt : integer range 0 to 9;

    signal sr_clk  : std_logic_vector(9 downto 0);
    signal sr_d0   : std_logic_vector(9 downto 0);
    signal sr_d1   : std_logic_vector(9 downto 0);
    signal sr_d2   : std_logic_vector(9 downto 0);

    -- TMDS running-disparity accumulators
    signal rd_d0   : integer range -32 to 32;
    signal rd_d1   : integer range -32 to 32;
    signal rd_d2   : integer range -32 to 32;

    ---------------------------------------------------------------------------
    -- TMDS helper functions (DVI 1.0 / HDMI 1.4 spec, Section 3.3)
    ---------------------------------------------------------------------------

    -- Count set bits in a byte.
    function count_ones(d : std_logic_vector(7 downto 0)) return integer is
        variable n : integer := 0;
    begin
        for i in 0 to 7 loop
            if d(i) = '1' then n := n + 1; end if;
        end loop;
        return n;
    end function;

    -- Return one of the four TMDS control tokens.
    function control_code(c1 : std_logic; c0 : std_logic)
            return std_logic_vector is
    begin
        if    c1 = '0' and c0 = '0' then return "1101010100";
        elsif c1 = '0' and c0 = '1' then return "0010101011";
        elsif c1 = '1' and c0 = '0' then return "0101010100";
        else                              return "1010101011";
        end if;
    end function;

    -- TMDS-encode one 8-bit data byte given the current running disparity.
    function tmds_encode(d : std_logic_vector(7 downto 0); rd_in : integer)
            return std_logic_vector is
        variable qm      : std_logic_vector(8 downto 0);
        variable code    : std_logic_vector(9 downto 0);
        variable ones_d  : integer;
        variable ones_q  : integer;
        variable bal_q   : integer;
    begin
        -- Step 1: build the 9-bit transition-minimised intermediate value.
        ones_d := count_ones(d);
        qm(0)  := d(0);
        if (ones_d > 4) or (ones_d = 4 and d(0) = '0') then
            for i in 1 to 7 loop qm(i) := qm(i-1) xnor d(i); end loop;
            qm(8) := '0';   -- XNOR
        else
            for i in 1 to 7 loop qm(i) := qm(i-1) xor  d(i); end loop;
            qm(8) := '1';   -- XOR
        end if;
        -- Step 2: DC balance.
        ones_q := 0;
        for i in 0 to 7 loop
            if qm(i) = '1' then ones_q := ones_q + 1; end if;
        end loop;
        bal_q := ones_q - (8 - ones_q);
        if rd_in = 0 or ones_q = 4 then
            code(9) := not qm(8);
            code(8) := qm(8);
            if qm(8) = '1' then
                code(7 downto 0) := qm(7 downto 0);
            else
                code(7 downto 0) := not qm(7 downto 0);
            end if;
        elsif (rd_in > 0 and bal_q > 0) or (rd_in < 0 and bal_q < 0) then
            code(9) := '1';
            code(8) := qm(8);
            code(7 downto 0) := not qm(7 downto 0);
        else
            code(9) := '0';
            code(8) := qm(8);
            code(7 downto 0) := qm(7 downto 0);
        end if;
        return code;
    end function;

    -- Compute the next running-disparity value after emitting 'code'.
    -- During blanking (de='0') disparity is reset to 0.
    function next_rd(rd_in : integer; code : std_logic_vector(9 downto 0);
                     de : std_logic) return integer is
        variable n  : integer := 0;
        variable rd : integer;
    begin
        if de = '0' then return 0; end if;
        for i in 0 to 9 loop
            if code(i) = '1' then n := n + 1; end if;
        end loop;
        rd := rd_in + (n - (10 - n));
        if    rd >  32 then return  32;
        elsif rd < -32 then return -32;
        else                return rd;
        end if;
    end function;

begin

    reset <= not reset_n;

    -- Export pixel position so the caller can compute video signals.
    h_out <= std_logic_vector(to_unsigned(h_cnt, 10));
    v_out <= std_logic_vector(to_unsigned(v_cnt, 10));

    ---------------------------------------------------------------------------
    -- PLL: 54 MHz → 270 MHz serial clock
    --   CLKFBOUT_MULT=10, DIVCLK_DIVIDE=1 → VCO = 540 MHz
    --   CLKOUT0_DIVIDE=2                  → 270 MHz
    ---------------------------------------------------------------------------
    pll_inst : PLL_BASE
    generic map (
        BANDWIDTH          => "OPTIMIZED",
        CLKFBOUT_MULT      => 10,
        CLKFBOUT_PHASE     => 0.0,
        CLKIN_PERIOD       => 18.519,   -- 54 MHz
        CLKOUT0_DIVIDE     => 2,        -- 270 MHz
        CLKOUT0_DUTY_CYCLE => 0.5,
        CLKOUT0_PHASE      => 0.0,
        DIVCLK_DIVIDE      => 1,
        REF_JITTER         => 0.010
    )
    port map (
        CLKFBIN  => pll_fb,
        CLKIN    => clk54,
        RST      => reset,
        CLKFBOUT => pll_fb,
        CLKOUT0  => clk_ser_raw,
        CLKOUT1  => open,
        CLKOUT2  => open,
        CLKOUT3  => open,
        CLKOUT4  => open,
        CLKOUT5  => open,
        LOCKED   => pll_lock
    );

    -- Route the high-speed clock through a global buffer.
    bufg_ser : BUFG
    port map (I => clk_ser_raw, O => clk_ser);

    ---------------------------------------------------------------------------
    -- Main process — runs entirely at 270 MHz
    --
    -- Pixel boundary:  every 10 serial clock cycles (ser_cnt 0..9)
    -- At ser_cnt = 9 : encode the pixel at (h_cnt, v_cnt), load the shift
    --                  registers, then advance h_cnt / v_cnt.
    -- At ser_cnt = 0..8 : shift the registers right, serialising bits 1..9.
    --                  Bit 0 of each 10-bit code is output on the load cycle
    --                  (ser_cnt=9) via the bottom of the freshly loaded register.
    --
    -- Initialising ser_cnt=9 in reset ensures the very first active clock
    -- immediately triggers a load, preventing stale data from being shifted out.
    ---------------------------------------------------------------------------
    main_p : process(clk_ser)
        -- Pixel-domain variables (evaluated once per pixel at the load cycle)
        variable code_d0  : std_logic_vector(9 downto 0);
        variable code_d1  : std_logic_vector(9 downto 0);
        variable code_d2  : std_logic_vector(9 downto 0);
    begin
        if rising_edge(clk_ser) then
            if reset = '1' or pll_lock = '0' then
                -- Hold everything in reset; start with ser_cnt=9 so the first
                -- active cycle immediately executes the load path.
                ser_cnt <= 9;
                h_cnt   <= 0;
                v_cnt   <= 0;
                sr_clk  <= "1111100000";
                sr_d0   <= control_code('0', '0');
                sr_d1   <= control_code('0', '0');
                sr_d2   <= control_code('0', '0');
                rd_d0   <= 0;
                rd_d1   <= 0;
                rd_d2   <= 0;

            elsif ser_cnt = 9 then
                ---------------------------------------------------------------
                -- Load cycle: encode the pixel at the current position.
                -- de/hsync/vsync/r/g/b are driven combinatorially by the
                -- caller based on h_out/v_out and are stable by this edge.
                ---------------------------------------------------------------
                ser_cnt <= 0;

                -- TMDS encoding.
                if de = '1' then
                    -- Active pixels: encode RGB data.
                    -- D0 = Blue, D1 = Green, D2 = Red  (HDMI channel mapping).
                    code_d0 := tmds_encode(b, rd_d0);
                    code_d1 := tmds_encode(g, rd_d1);
                    code_d2 := tmds_encode(r, rd_d2);
                else
                    -- Blanking: carry sync polarity in D0 control codes.
                    code_d0 := control_code(vsync, hsync);
                    code_d1 := control_code('0', '0');
                    code_d2 := control_code('0', '0');
                end if;

                -- Load the TMDS clock channel (always "1111100000" = pixel clock).
                sr_clk <= "1111100000";
                sr_d0  <= code_d0;
                sr_d1  <= code_d1;
                sr_d2  <= code_d2;

                -- Update running disparity.
                rd_d0 <= next_rd(rd_d0, code_d0, de);
                rd_d1 <= next_rd(rd_d1, code_d1, de);
                rd_d2 <= next_rd(rd_d2, code_d2, de);

                -- Advance pixel / line counters.
                if (h_cnt = H_TOTAL - 1) then
                    h_cnt <= 0;
                    if (v_cnt = V_TOTAL - 1) then
                        v_cnt <= 0;
                    else
                        v_cnt <= v_cnt + 1;
                    end if;
                else
                    h_cnt <= h_cnt + 1;
                end if;

            else
                ---------------------------------------------------------------
                -- Shift cycles: serialise bits 1..9.
                ---------------------------------------------------------------
                ser_cnt <= ser_cnt + 1;
                sr_clk  <= '0' & sr_clk(9 downto 1);
                sr_d0   <= '0' & sr_d0(9 downto 1);
                sr_d1   <= '0' & sr_d1(9 downto 1);
                sr_d2   <= '0' & sr_d2(9 downto 1);
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- TMDS differential outputs.
    -- Bit 0 of each shift register is the current serial output bit.
    -- The inverted signal drives the complementary pin of each LVDS pair.
    -- Constrain both members of each pair to TMDS_33 in the UCF file.
    ---------------------------------------------------------------------------
    tmds_clk_p <= sr_clk(0);
--    tmds_clk_n <= not sr_clk(0);
    tmds_d0_p  <= sr_d0(0);
--    tmds_d0_n  <= not sr_d0(0);
    tmds_d1_p  <= sr_d1(0);
--    tmds_d1_n  <= not sr_d1(0);
    tmds_d2_p  <= sr_d2(0);
--    tmds_d2_n  <= not sr_d2(0);

end Behavioral;
