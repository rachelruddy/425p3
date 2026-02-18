library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cache_tb is
end cache_tb;

architecture behavior of cache_tb is

component cache is
generic(
    ram_size : INTEGER := 32768
);
port(
    clock : in std_logic;
    reset : in std_logic;

    -- Avalon interface --
    s_addr : in std_logic_vector (31 downto 0);
    s_read : in std_logic;
    s_readdata : out std_logic_vector (31 downto 0);
    s_write : in std_logic;
    s_writedata : in std_logic_vector (31 downto 0);
    s_waitrequest : out std_logic; 

    m_addr : out integer range 0 to ram_size-1;
    m_read : out std_logic;
    m_readdata : in std_logic_vector (7 downto 0);
    m_write : out std_logic;
    m_writedata : out std_logic_vector (7 downto 0);
    m_waitrequest : in std_logic
);
end component;

component memory is 
GENERIC(
    ram_size : INTEGER := 32768;
    mem_delay : time := 10 ns;
    clock_period : time := 1 ns
);
PORT (
    clock: IN STD_LOGIC;
    writedata: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
    address: IN INTEGER RANGE 0 TO ram_size-1;
    memwrite: IN STD_LOGIC;
    memread: IN STD_LOGIC;
    readdata: OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
    waitrequest: OUT STD_LOGIC
);
end component;
	
-- test signals 
signal reset : std_logic := '0';
signal clk : std_logic := '0';
constant clk_period : time := 1 ns;

signal s_addr : std_logic_vector (31 downto 0);
signal s_read : std_logic;
signal s_readdata : std_logic_vector (31 downto 0);
signal s_write : std_logic;
signal s_writedata : std_logic_vector (31 downto 0);
signal s_waitrequest : std_logic;

signal m_addr : integer range 0 to 2147483647;
signal m_read : std_logic;
signal m_readdata : std_logic_vector (7 downto 0);
signal m_write : std_logic;
signal m_writedata : std_logic_vector (7 downto 0);
signal m_waitrequest : std_logic; 

begin

-- Connect the components which we instantiated above to their
-- respective signals.
dut: cache 
port map(
    clock => clk,
    reset => reset,

    s_addr => s_addr,
    s_read => s_read,
    s_readdata => s_readdata,
    s_write => s_write,
    s_writedata => s_writedata,
    s_waitrequest => s_waitrequest,

    m_addr => m_addr,
    m_read => m_read,
    m_readdata => m_readdata,
    m_write => m_write,
    m_writedata => m_writedata,
    m_waitrequest => m_waitrequest
);

MEM : memory
port map (
    clock => clk,
    writedata => m_writedata,
    address => m_addr,
    memwrite => m_write,
    memread => m_read,
    readdata => m_readdata,
    waitrequest => m_waitrequest
);
				

clk_process : process
begin
  clk <= '0';
  wait for clk_period/2;
  clk <= '1';
  wait for clk_period/2;
end process;

test_process : process

--This procedure reads the data at the given address for testing purposes
procedure read_test( addr : in std_logic_vector(31 downto 0)) is
begin
	s_addr <= addr;  --setting up the signals needed
	wait until rising_edge(clk);
	s_read <= '1';
	s_write <= '0';

	wait until rising_edge(clk); --waiting until the cache is ready
	while s_waitrequest = '1' loop
		wait until rising_edge(clk);
	end loop;

	s_read <= '0';   --resetting siganls for next time
	wait until rising_edge(clk);
end procedure;

--This procedure wites the data given to it at the address spercified
procedure write_test(
		addr : in std_logic_vector(31 downto 0);
		data : in std_logic_vector(31 downto 0)) is
begin
	s_addr <= addr;  --setting up the signals needed
	wait until rising_edge(clk);
	s_writedata <= data;
	s_read <= '0';
	s_write <= '1';

	wait until rising_edge(clk); --waiting until the cache is ready
	while s_waitrequest = '1' loop
		wait until rising_edge(clk);
	end loop;

	s_write <= '0';   --resetting siganls for next time
	wait until rising_edge(clk);
end procedure;

begin
-- put your tests here

-- reset to init
	reset <= '1';
	wait until rising_edge(clk);
	reset <= '0';
	wait until rising_edge(clk);

-- Case 1: Writting to a not valid, clean block with no tag match
	write_test(x"00000000", x"beefcafe");

--Case 2 : Reading a valid, dirty block with tag match
	read_test(x"00000000");
	Assert (s_readdata = x"beefcafe")
	Report "Error with either case 1 or 2. Either we didn't write correctly or we didn't read correctly unfortunatly no way to know."
	Severity ERROR;

--Case 3 : Writing to a valid, dirty block with tag match
	write_test(x"00000000", x"deadbeef");
	read_test(x"00000000");
	Assert (s_readdata = x"deadbeef")
	Report "Error with case 3: overwriting a dirty valid block"
	Severity ERROR;

--Case 4 : Reading a valid, dirty block without tag match
	-- read_test(x"00008000");
	-- -- !!!!!!!!!!!!!! we cant really assert m_write here since it is being toggled within the CPU logic....
	-- -- instead we could probably just read it from memory ourselves directly and assert that value
	-- Assert (m_write = '1')
	-- Report "Error with case 4: we did not write the dirty block back into memory"
	-- Severity ERROR;

--Case 5 : Writing to a valid, clean block without tag match
	write_test(x"00000000", x"beefcafe");
	read_test(x"00000000");
	Assert (s_readdata = x"beefcafe")
	Report "Error with case 5. Writing to a valid, clean block without tag match."
	Severity ERROR;

--Case 6 : Writing to a valid, dirty block without tag match
	write_test(x"00000200", x"10101010");
    read_test(x"00000200");
    Assert (s_readdata = x"10101010")
    Report "Error with case 6. Writing to a valid, dirty block without tag match."
    Severity ERROR;

--Case 7 : Reading a none valid, clean block without a tag match
	-- read_test(x"00000100");
	-- -- !!!!!!!!!! I think this is the same as case 4, I don't think we can assert m_write in the tests.
	-- -- this test should be changed as well
	-- Assert (m_write = '1')
	-- Report "Error with case 7: we aren't checking memory for a block we haven't accessed yet"
	-- Severity ERROR;

--Case 8 : Reading a valid, clean without a tag match
	read_test(x"00000300");
    read_test(x"00000200");
    Assert (s_readdata = x"10101010")
    Report "Error with case 8. Reading a valid, clean without a tag match."
    Severity ERROR;

--Case 9 : Reading a valid clean block with a tag match
	read_test(x"00000200");
    Assert (s_readdata = x"10101010")
    Report "Error with case 9. Reading a valid clean block with a tag match."
    Severity ERROR;

--Case 10 : Writing to a a valid clean block with a tag match
	write_test(x"00000200", x"abbacafe");
    read_test(x"00000200");
    Assert (s_readdata = x"abbacafe")
    Report "Error with case 10. Writing to a a valid clean block with a tag match."
    Severity ERROR;

--Case 11 : Reading a none valid, clean block with a tag match
--!!!!!!!!!!! not sure why this is failing, should be looked at
	write_test(x"00000100", x"beefcab5");

    read_test(x"00000300");

    wait until rising_edge(clk);
--The only way I could figure out how have it not valid but still have a tag match was to reset the cache so thats what im doing but if reset also resets the values in memeory i dont know what im doing
	reset <= '1';
	-- !! maybe we should wait until rising edge here
	wait until rising_edge(clk);
	reset <= '0';
    wait until rising_edge(clk);

	read_test(x"00000100");
	Assert (s_readdata = x"beefcab5")
	Report "Error with case 11. Reading a none valid, clean block with a tag match. (also possible something went wrong with the reset)"
	Severity ERROR;

--Case 12 : Writing a none valid block with a tag match
	write_test(x"00000200", x"12345678");
    read_test(x"00000200");
    Assert (s_readdata = x"12345678")
    Report "Error with case 12. Writing a none valid block with a tag match."
    Severity ERROR;


	Report "Yay !!! All the test cases are done. If no errors poped up it means we got this (or my testbench is messed up)";



end process;
	
end;
