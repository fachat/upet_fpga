----------------------------------------------------------------------------------
-- HDMI output transform from VGA-style pixel/sync signaling.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library UNISIM;
use UNISIM.VComponents.all;

entity HdmiOut is
    Port (
        qclk        : in  std_logic;                      -- 2x pixel clock
        pix_clk     : in  std_logic;                      -- pixel clock (qclk / 2)
        reset       : in  std_logic;
        pix_in      : in  std_logic_vector(7 downto 0);   -- RRRGGGBB
        hsync_in    : in  std_logic;
        vsync_in    : in  std_logic;
        tmds_clk_p  : out std_logic;
        tmds_clk_n  : out std_logic;
        tmds_d0_p   : out std_logic;
        tmds_d0_n   : out std_logic;
        tmds_d1_p   : out std_logic;
        tmds_d1_n   : out std_logic;
        tmds_d2_p   : out std_logic;
        tmds_d2_n   : out std_logic
    );
end HdmiOut;

architecture Behavioral of HdmiOut is

    signal pll_clk_5x : std_logic;
    signal pll_fb     : std_logic;
    signal pll_lock   : std_logic;

    signal pix_hs_d1  : std_logic;
    signal pix_hs_d2  : std_logic;
    signal load_sym   : std_logic;

    signal sr_clk     : std_logic_vector(9 downto 0);
    signal sr_d0      : std_logic_vector(9 downto 0);
    signal sr_d1      : std_logic_vector(9 downto 0);
    signal sr_d2      : std_logic_vector(9 downto 0);

    signal rd_d0      : integer range -32 to 32;
    signal rd_d1      : integer range -32 to 32;
    signal rd_d2      : integer range -32 to 32;

    function count_ones(d: std_logic_vector(7 downto 0)) return integer is
        variable cnt: integer := 0;
    begin
        for i in 0 to 7 loop
            if d(i) = '1' then
                cnt := cnt + 1;
            end if;
        end loop;
        return cnt;
    end function;

    function control_code(c1: std_logic; c0: std_logic) return std_logic_vector is
    begin
        if c1 = '0' and c0 = '0' then
            return "1101010100";
        elsif c1 = '0' and c0 = '1' then
            return "0010101011";
        elsif c1 = '1' and c0 = '0' then
            return "0101010100";
        else
            return "1010101011";
        end if;
    end function;

    function tmds_encode_data(d: std_logic_vector(7 downto 0); rd_in: integer) return std_logic_vector is
        variable qm     : std_logic_vector(8 downto 0);
        variable out10  : std_logic_vector(9 downto 0);
        variable ones_d : integer;
        variable ones_q : integer;
        variable bal_q  : integer;
    begin
        ones_d := count_ones(d);
        qm(0) := d(0);
        if (ones_d > 4) or (ones_d = 4 and d(0) = '0') then
            for i in 1 to 7 loop
                qm(i) := qm(i-1) xnor d(i);
            end loop;
            qm(8) := '0';
        else
            for i in 1 to 7 loop
                qm(i) := qm(i-1) xor d(i);
            end loop;
            qm(8) := '1';
        end if;

        ones_q := 0;
        for i in 0 to 7 loop
            if qm(i) = '1' then
                ones_q := ones_q + 1;
            end if;
        end loop;
        bal_q := ones_q - (8 - ones_q);

        if (rd_in = 0) or (ones_q = 4) then
            out10(9) := not qm(8);
            out10(8) := qm(8);
            if qm(8) = '1' then
                out10(7 downto 0) := qm(7 downto 0);
            else
                out10(7 downto 0) := not qm(7 downto 0);
            end if;
        elsif (rd_in > 0 and bal_q > 0) or (rd_in < 0 and bal_q < 0) then
            out10(9) := '1';
            out10(8) := qm(8);
            out10(7 downto 0) := not qm(7 downto 0);
        else
            out10(9) := '0';
            out10(8) := qm(8);
            out10(7 downto 0) := qm(7 downto 0);
        end if;
        return out10;
    end function;

    function tmds_next_rd(rd_in: integer; code: std_logic_vector(9 downto 0); de: std_logic) return integer is
        variable rd_v     : integer := rd_in;
        variable ones_out : integer := 0;
    begin
        if de = '0' then
            return 0;
        end if;

        for i in 0 to 9 loop
            if code(i) = '1' then
                ones_out := ones_out + 1;
            end if;
        end loop;
        rd_v := rd_in + (ones_out - (10 - ones_out));
        if rd_v > 32 then
            rd_v := 32;
        elsif rd_v < -32 then
            rd_v := -32;
        end if;
        return rd_v;
    end function;

begin

    -- qclk is 2x pixel clock; HDMI serial clock needs 10x pixel clock = 5x qclk.
    pll_hdmi: PLL_BASE
    generic map (
        BANDWIDTH          => "OPTIMIZED",
        CLKFBOUT_MULT      => 10,
        CLKFBOUT_PHASE     => 0.0,
        CLKIN_PERIOD       => 18.518,    -- 54 MHz nominal; VCO = 540 MHz, output = 270 MHz (5x qclk)
        CLKOUT0_DIVIDE     => 2,
        CLKOUT0_DUTY_CYCLE => 0.5,
        CLKOUT0_PHASE      => 0.0,
        DIVCLK_DIVIDE      => 1,
        REF_JITTER         => 0.010
    )
    port map (
        CLKFBIN   => pll_fb,
        CLKIN     => qclk,
        RST       => reset,
        CLKFBOUT  => pll_fb,
        CLKOUT0   => pll_clk_5x,
        CLKOUT1   => open,
        CLKOUT2   => open,
        CLKOUT3   => open,
        CLKOUT4   => open,
        CLKOUT5   => open,
        LOCKED    => pll_lock
    );

    serializer_p: process(pll_clk_5x)
        variable de_v      : std_logic;
        variable load_sym_v: std_logic;
        variable data_r    : std_logic_vector(7 downto 0);
        variable data_g    : std_logic_vector(7 downto 0);
        variable data_b    : std_logic_vector(7 downto 0);
        variable code_d0   : std_logic_vector(9 downto 0);
        variable code_d1   : std_logic_vector(9 downto 0);
        variable code_d2   : std_logic_vector(9 downto 0);
    begin
        if rising_edge(pll_clk_5x) then
            if reset = '1' or pll_lock = '0' then
                pix_hs_d1 <= '0';
                pix_hs_d2 <= '0';
                load_sym <= '0';
                sr_clk <= "1111100000";
                sr_d0 <= control_code('0', '0');
                sr_d1 <= control_code('0', '0');
                sr_d2 <= control_code('0', '0');
                rd_d0 <= 0;
                rd_d1 <= 0;
                rd_d2 <= 0;
            else
                pix_hs_d1 <= pix_clk;
                pix_hs_d2 <= pix_hs_d1;
                load_sym <= '0';
                load_sym_v := '0';

                if pix_hs_d1 = '1' and pix_hs_d2 = '0' then
                    load_sym <= '1';
                    load_sym_v := '1';
                end if;

                if load_sym_v = '1' then
                    data_r := pix_in(7 downto 5) & pix_in(7 downto 5) & pix_in(7 downto 6);
                    data_g := pix_in(4 downto 2) & pix_in(4 downto 2) & pix_in(4 downto 3);
                    data_b := pix_in(1 downto 0) & pix_in(1 downto 0) & pix_in(1 downto 0) & pix_in(1 downto 0);

                    if hsync_in = '0' or vsync_in = '0' then
                        de_v := '0';
                    else
                        de_v := '1';
                    end if;

                    if de_v = '0' then
                        code_d0 := control_code(vsync_in, hsync_in);
                        code_d1 := control_code('0', '0');
                        code_d2 := control_code('0', '0');
                    else
                        code_d0 := tmds_encode_data(data_b, rd_d0);
                        code_d1 := tmds_encode_data(data_g, rd_d1);
                        code_d2 := tmds_encode_data(data_r, rd_d2);
                    end if;

                    sr_clk <= "1111100000";
                    sr_d0 <= code_d0;
                    sr_d1 <= code_d1;
                    sr_d2 <= code_d2;

                    rd_d0 <= tmds_next_rd(rd_d0, code_d0, de_v);
                    rd_d1 <= tmds_next_rd(rd_d1, code_d1, de_v);
                    rd_d2 <= tmds_next_rd(rd_d2, code_d2, de_v);
                else
                    sr_clk <= '0' & sr_clk(9 downto 1);
                    sr_d0 <= '0' & sr_d0(9 downto 1);
                    sr_d1 <= '0' & sr_d1(9 downto 1);
                    sr_d2 <= '0' & sr_d2(9 downto 1);
                end if;
            end if;
        end if;
    end process;

    -- Re-use existing 8 single-ended VGA outputs as 4 differential HDMI pairs.
    tmds_clk_p <= sr_clk(0);
    tmds_clk_n <= not sr_clk(0);
    tmds_d0_p <= sr_d0(0);
    tmds_d0_n <= not sr_d0(0);
    tmds_d1_p <= sr_d1(0);
    tmds_d1_n <= not sr_d1(0);
    tmds_d2_p <= sr_d2(0);
    tmds_d2_n <= not sr_d2(0);

end Behavioral;
