library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity tb_shellultra_sim is
end entity;

architecture sim of tb_shellultra_sim is
    constant C_QCLK_PERIOD : time := 18.518 ns; -- 54MHz
    constant C_FRAME_W : integer := 720;
    constant C_FRAME_H : integer := 576;
    constant C_LINE_TOTAL : integer := 864;
    constant C_FRAME_TOTAL : integer := 625;

    signal q50m : std_logic := '0';
    signal nres : std_logic := '0';
    signal nirq : std_logic;

    signal c8phi2 : std_logic;
    signal c2phi2 : std_logic;
    signal cphi2 : std_logic;

    signal graphic : std_logic := '0';

    signal A : std_logic_vector(15 downto 0);
    signal D : std_logic_vector(7 downto 0);
    signal vda : std_logic;
    signal vpa : std_logic;
    signal rwb : std_logic;
    signal rdy : std_logic := '1';
    signal phi2 : std_logic;
    signal vpb : std_logic;
    signal e : std_logic;
    signal mlb : std_logic;
    signal cpu_nbe : std_logic;

    signal nbe_dout : std_logic;

    signal sync : std_logic;
    signal be_in : std_logic := '0';
    signal nmemsel : std_logic;
    signal niosel : std_logic;
    signal extio : std_logic := '0';
    signal ioinh : std_logic := '0';
    signal nbe_out : std_logic;

    signal VA : std_logic_vector(18 downto 0);
    signal FA : std_logic_vector(19 downto 15);
    signal VD : std_logic_vector(7 downto 0);

    signal nvramsel : std_logic;
    signal nframsel : std_logic;
    signal ramrwb : std_logic;

    signal vsync : std_logic;
    signal hsync : std_logic;
    signal pet_vsync : std_logic;
    signal pxl_out : std_logic_vector(5 downto 0);

    signal spi_out : std_logic;
    signal spi_clk : std_logic;
    signal spi_in1 : std_logic;
    signal spi_in3 : std_logic;
    signal spi_sela : std_logic;
    signal spi_selb : std_logic;
    signal spi_selc : std_logic;

    signal spi_naudio : std_logic;
    signal spi_aclk : std_logic;
    signal spi_amosi : std_logic;
    signal nldac : std_logic;

    signal flash_cs_n : std_logic;

    type t_ram is array (0 to 2**21 - 1) of std_logic_vector(7 downto 0);
    type t_vram is array (0 to 2**19 - 1) of std_logic_vector(7 downto 0);

    signal fram : t_ram := (others => (others => '0'));
    signal vram : t_vram := (others => (others => '0'));

    signal fram_addr : integer range 0 to 2**21 - 1;
    signal vram_addr : integer range 0 to 2**19 - 1;

    type t_frame is array (0 to C_FRAME_W * C_FRAME_H - 1) of std_logic_vector(5 downto 0);
    signal framebuf : t_frame := (others => (others => '0'));

    function comp2_to_u8(c : std_logic_vector(1 downto 0)) return integer is
    begin
        case c is
            when "00" => return 0;
            when "01" => return 85;
            when "10" => return 170;
            when others => return 255;
        end case;
    end function;

begin
    q50m <= not q50m after C_QCLK_PERIOD / 2;

    process
    begin
        nres <= '0';
        wait for 2 us;
        nres <= '1';
        wait;
    end process;

    fram_addr <= to_integer(unsigned(FA)) * 65536 + to_integer(unsigned(A));
    vram_addr <= to_integer(unsigned(VA));

    -- FRAM model on CPU bus
    D <= fram(fram_addr) when (nframsel = '0' and ramrwb = '1') else (others => 'Z');

    process(phi2)
    begin
        if falling_edge(phi2) then
            if nframsel = '0' and ramrwb = '0' then
                fram(fram_addr) <= D;
            end if;
        end if;
    end process;

    -- VRAM model shared with video and IPL
    VD <= vram(vram_addr) when (nvramsel = '0' and ramrwb = '1') else (others => 'Z');

    process(q50m)
    begin
        if rising_edge(q50m) then
            if nvramsel = '0' and ramrwb = '0' then
                vram(vram_addr) <= VD;
            end if;
        end if;
    end process;

    flash_cs_n <= '0' when (spi_selb = '0' and spi_selc = '0') else '1';

    flash0 : entity work.spi_flash_model
        port map (
            cs_n => flash_cs_n,
            sclk => spi_clk,
            mosi => spi_out,
            miso => spi_in1
        );

    spi_in3 <= spi_in1;

    cpu0 : entity work.cpu65816_core
        port map (
            nres => nres,
            phi2 => phi2,
            rdy  => rdy,
            A    => A,
            D    => D,
            vda  => vda,
            vpa  => vpa,
            rwb  => rwb,
            vpb  => vpb,
            e    => e,
            mlb  => mlb
        );

    dut : entity work.ShellUltra
        port map (
            q50m => q50m,
            nres => nres,
            nirq => nirq,
            c8phi2 => c8phi2,
            c2phi2 => c2phi2,
            cphi2 => cphi2,
            graphic => graphic,
            A => A,
            D => D,
            vda => vda,
            vpa => vpa,
            rwb => rwb,
            rdy => rdy,
            phi2 => phi2,
            vpb => vpb,
            e => e,
            mlb => mlb,
            cpu_nbe => cpu_nbe,
            nbe_dout => nbe_dout,
            sync => sync,
            be_in => be_in,
            nmemsel => nmemsel,
            niosel => niosel,
            extio => extio,
            ioinh => ioinh,
            nbe_out => nbe_out,
            VA => VA,
            FA => FA,
            VD => VD,
            nvramsel => nvramsel,
            nframsel => nframsel,
            ramrwb => ramrwb,
            vsync => vsync,
            hsync => hsync,
            pet_vsync => pet_vsync,
            pxl_out => pxl_out,
            spi_out => spi_out,
            spi_clk => spi_clk,
            spi_in1 => spi_in1,
            spi_in3 => spi_in3,
            spi_sela => spi_sela,
            spi_selb => spi_selb,
            spi_selc => spi_selc,
            spi_naudio => spi_naudio,
            spi_aclk => spi_aclk,
            spi_amosi => spi_amosi,
            nldac => nldac
        );

    process
        variable pix_phase : std_logic := '0';
        variable x : integer := 0;
        variable y : integer := 0;
        variable idx : integer;

        file ppm : text;
        variable linebuf : line;
        variable p : std_logic_vector(5 downto 0);
        variable r, g, b : integer;
    begin
        wait until nres = '1';
        wait for 1 ms;

        while true loop
            wait until rising_edge(q50m);
            pix_phase := not pix_phase;
            if pix_phase = '1' then
                if x < C_FRAME_W and y < C_FRAME_H then
                    idx := y * C_FRAME_W + x;
                    framebuf(idx) <= pxl_out;
                end if;

                if x = C_LINE_TOTAL - 1 then
                    x := 0;
                    if y = C_FRAME_TOTAL - 1 then
                        file_open(ppm, "out/frame.ppm", write_mode);
                        write(linebuf, string'("P3"));
                        writeline(ppm, linebuf);
                        write(linebuf, C_FRAME_W);
                        write(linebuf, string'(" "));
                        write(linebuf, C_FRAME_H);
                        writeline(ppm, linebuf);
                        write(linebuf, string'("255"));
                        writeline(ppm, linebuf);

                        for yy in 0 to C_FRAME_H - 1 loop
                            linebuf := null;
                            for xx in 0 to C_FRAME_W - 1 loop
                                p := framebuf(yy * C_FRAME_W + xx);
                                r := comp2_to_u8(p(5 downto 4));
                                g := comp2_to_u8(p(3 downto 2));
                                b := comp2_to_u8(p(1 downto 0));
                                write(linebuf, r);
                                write(linebuf, string'(" "));
                                write(linebuf, g);
                                write(linebuf, string'(" "));
                                write(linebuf, b);
                                write(linebuf, string'(" "));
                            end loop;
                            writeline(ppm, linebuf);
                        end loop;
                        file_close(ppm);
                        report "Simulation complete; frame written to out/frame.ppm" severity note;
                        stop;
                    else
                        y := y + 1;
                    end if;
                else
                    x := x + 1;
                end if;
            end if;
        end loop;
    end process;
end architecture;
