library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_flash_model is
    port (
        cs_n : in std_logic;
        sclk : in std_logic;
        mosi : in std_logic;
        miso : out std_logic
    );
end entity;

architecture behavioral of spi_flash_model is
    type t_state is (S_CMD, S_ADDR, S_DATA);
    signal state : t_state := S_CMD;

    type t_flash is array (0 to 65535) of std_logic_vector(7 downto 0);

    function init_flash return t_flash is
        variable mem : t_flash := (others => x"EA");
    begin
        -- Reset vector in the first 256-byte page loaded by IPL.
        mem(16#00FC#) := x"00";
        mem(16#00FD#) := x"FF";
        return mem;
    end function;

    signal flash : t_flash := init_flash;

    signal bit_cnt : integer range 0 to 31 := 0;
    signal data_bit : integer range 0 to 7 := 0;
    signal cmd_shift : std_logic_vector(7 downto 0) := (others => '0');
    signal addr_shift : std_logic_vector(23 downto 0) := (others => '0');
    signal cur_addr : unsigned(23 downto 0) := (others => '0');
    signal cur_byte : std_logic_vector(7 downto 0) := (others => '0');
begin
    process(cs_n, sclk)
        variable next_addr : unsigned(23 downto 0);
    begin
        if cs_n = '1' then
            state <= S_CMD;
            bit_cnt <= 0;
            data_bit <= 0;
            cmd_shift <= (others => '0');
            addr_shift <= (others => '0');
            cur_addr <= (others => '0');
            cur_byte <= (others => '0');
            miso <= '0';
        elsif rising_edge(sclk) then
            case state is
                when S_CMD =>
                    cmd_shift <= cmd_shift(6 downto 0) & mosi;
                    if bit_cnt = 7 then
                        bit_cnt <= 0;
                        if (cmd_shift(6 downto 0) & mosi) = x"03" then
                            state <= S_ADDR;
                        end if;
                    else
                        bit_cnt <= bit_cnt + 1;
                    end if;

                when S_ADDR =>
                    addr_shift <= addr_shift(22 downto 0) & mosi;
                    if bit_cnt = 23 then
                        cur_addr <= unsigned(addr_shift(22 downto 0) & mosi);
                        cur_byte <= flash(to_integer(unsigned((addr_shift(14 downto 0) & mosi))));
                        state <= S_DATA;
                        data_bit <= 0;
                        bit_cnt <= 0;
                    else
                        bit_cnt <= bit_cnt + 1;
                    end if;

                when S_DATA =>
                    null;
            end case;
        elsif falling_edge(sclk) then
            if state = S_DATA then
                miso <= cur_byte(7 - data_bit);
                if data_bit = 7 then
                    data_bit <= 0;
                    next_addr := cur_addr + 1;
                    cur_addr <= next_addr;
                    cur_byte <= flash(to_integer(next_addr(15 downto 0)));
                else
                    data_bit <= data_bit + 1;
                end if;
            else
                miso <= '0';
            end if;
        end if;
    end process;
end architecture;
