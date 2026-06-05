----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    22:37:05 06/04/2026 
-- Design Name: 
-- Module Name:    HdmiTestShell - Behavioral 
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

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity HdmiTestShell is
	    Port (
        q50m      : in  std_logic;   -- 27 MHz board clock
        nres      : in  std_logic;   -- active-low reset
        vsync     : out std_logic;
        hsync     : out std_logic;
        pxl_out   : out std_logic_vector(5 downto 0)
    );

end HdmiTestShell;

architecture Behavioral of HdmiTestShell is

	component HdmiTestTop is
    Port (
        clk54      : in  std_logic;   -- 27 MHz board clock
        reset_n    : in  std_logic;   -- active-low reset
        tmds_clk_p : out std_logic;
        tmds_clk_n : out std_logic;
        tmds_d0_p  : out std_logic;
        tmds_d0_n  : out std_logic;
        tmds_d1_p  : out std_logic;
        tmds_d1_n  : out std_logic;
        tmds_d2_p  : out std_logic;
        tmds_d2_n  : out std_logic
    );
	end component;

begin
	
	test_c: HdmiTestTop
	port map (
		q50m,
		nres,
		vsync,
		hsync,
		pxl_out(1),
		pxl_out(0),
		pxl_out(3),
		pxl_out(2),
		pxl_out(5),
		pxl_out(4)		
	);
	

end Behavioral;

