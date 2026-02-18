library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cache is
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
----------------------------------------------------------
	m_addr : out integer range 0 to ram_size-1;

	m_read : out std_logic;
	m_readdata : in std_logic_vector (7 downto 0);

	m_write : out std_logic;
	m_writedata : out std_logic_vector (7 downto 0);

	m_waitrequest : in std_logic
);
end cache;

architecture arch of cache is
--------- CONSTANTS AND TYPES ------------------------------------------------------------------------------
	-- cache configs:
	-- 32 bit words
	-- 128 bits/block = 16 bytes/blobk = 4 words/block
	-- 32 blocks
	-- 32 bit addresses

	--		example instruction:
	-- [ tag(23 bits)  |  index (5 bits)  | offset (4 bits) ]
	-- last 2 LSBs are the byte offset (are ignored, assuming that we are only referncing multiples of 4)

	-- TAG_SIZE, however, is not the full 23 bits, since the size of main memory is only 2^15 bytes
	-- therefore, the tag bits are actually 14 -> 9 = 6 bits long

	--CONSTANT BLOCK_SIZE : integer := 4;
	CONSTANT NUM_BLOCKS : integer := 32;
	CONSTANT TAG_SIZE : integer := 6;

	TYPE WORD_ARR IS ARRAY(3 downto 0) OF STD_LOGIC_VECTOR(31 DOWNTO 0);
	TYPE DATA_ARRAY IS ARRAY(NUM_BLOCKS-1 downto 0) OF WORD_ARR;
	TYPE TAG_ARRAY IS ARRAY(NUM_BLOCKS-1 downto 0) OF std_logic_vector(TAG_SIZE-1 downto 0);
	TYPE FLAG_ARRAY IS ARRAY(NUM_BLOCKS-1 downto 0) OF std_logic;

	--FSM states
	TYPE FSM_STATE is (IDLE, CONTROL_CMP, WRITEBACK, REPLACE_BLOCK, REPLACE_FINISH, DONE);
--------- INTERNAL SIGNALS ---------------------------------------------------------------------------------
	-- cache arrays
	signal cache_valid : FLAG_ARRAY;	-- array of 32 valid bits
	signal cache_dirty : FLAG_ARRAY;	-- array of 32 dirty bits
	signal cache_tags : TAG_ARRAY;		-- array of 32 tags, each of length 6 bits
	signal cache_data : DATA_ARRAY;		-- 32 blocks, each have 4 words

	-- address parsing
	signal addr_tag : std_logic_vector(TAG_SIZE-1 downto 0);
	signal addr_index : integer range NUM_BLOCKS-1 downto 0;
	signal addr_offset : integer range 3 downto 0;			-- only extract bits 3-2, as we are assuming multiples of 4 
									-- i.e. addr_offset is a value = [0, 3], where index 0 is the first 
									-- word in that block and index 3 is the 4th word in that block

	--cache hit/miss
	signal cache_hit :std_logic;
	
	--initialize FSM to IDLE
	signal state : FSM_STATE := IDLE;

	-- count # bytes sent to MM
	signal byte_count : integer range 15 downto 0 := 0;
	signal old_tag : std_logic_vector(TAG_SIZE-1 downto 0);
	signal mem_addr_vec : std_logic_vector(14 downto 0);

	

begin

--------- PARSE ADDRESS ------------------------------------------------------------------------------------
	-- extract tag
	addr_tag <= s_addr(14 downto 9);
	--extract index
	addr_index <= to_integer(unsigned(s_addr(8 downto 4)));
	--extract word offset
	addr_offset <= to_integer(unsigned(s_addr(3 downto 2)));	-- again, ignore bits 1-0 since we are only accessing multiples of 4

--------- CACHE HIT/MISS DETECTION -------------------------------------------------------------------------
	-- cannot use "if" statement in combinatorial logic, have to use conditional statement
	cache_hit <= '1' when (cache_valid(addr_index) = '1' AND cache_tags(addr_index) = addr_tag) else '0';

--------- FSM ----------------------------------------------------------------------------------------------
	-- handles assigning the outputs
	cache_process: process(clock, reset)
	variable v_addr : std_logic_vector(14 downto 0);
	begin
		if reset = '1' then
			state <= IDLE;

			s_waitrequest <= '1';
			s_readdata <= (others => '0');

			m_read <= '0';
			m_write <= '0';
			m_addr <= 0;
			m_writedata <= (others => '0');

			byte_count <= 0;
			old_tag <= (others => '0');
			mem_addr_vec <= (others => '0');

			for i in 0 to NUM_BLOCKS-1 loop
                cache_valid(i) <= '0';
                cache_dirty(i) <= '0';
                cache_tags(i) <= (others => '0');

                for j in 0 to 3 loop
                    cache_data(i)(j) <= (others => '0');
                end loop;
            end loop;
		elsif rising_edge(clock) then
			case state is
				when IDLE => 
					-- wait for request from CPU
					s_waitrequest <= '1';		-- as per instructions, waitrequest is initially '1', is '0' for 1 clock cycle only when data is ready
					m_read <= '0';
					m_write <= '0';
					
					-- stay idle until get a read or write request
					if s_read = '1' OR s_write = '1' then
						state <= CONTROL_CMP;
					end if;
				when CONTROL_CMP => 
					if cache_hit = '1' then
						-- if read, read data from cache
						if s_read = '1' then
							s_readdata <= cache_data(addr_index)(addr_offset);
						-- if write, write data to cache, set dirty bit in array
						elsif s_write = '1' then
							cache_data(addr_index)(addr_offset) <= s_writedata;
							cache_dirty(addr_index) <= '1';
						end if;
						-- set waitrequest to 0 and state to idle
						s_waitrequest <= '0';
						state <= DONE;

					else -- miss
						-- only need to writeback when cache block is dirty	
						if cache_dirty(addr_index) = '1' then
							--latch onto tag of block being replaced
							old_tag <= cache_tags(addr_index);
							state <= WRITEBACK;
						else
							state <= REPLACE_BLOCK;
						end if;
					end if;
				when WRITEBACK => 
					-- set m signals so main memory handles writing
					m_write <= '1';
					m_read <= '0';
			
					--build memory address to send to MM
					v_addr := old_tag & std_logic_vector(to_unsigned(addr_index,5)) & std_logic_vector(to_unsigned(byte_count,4));
                    mem_addr_vec <= v_addr;
                    m_addr <= to_integer(unsigned(v_addr));

					-- for each word in that block, send each byte individually to write to MM
					case byte_count is
						when 0  => m_writedata <= cache_data(addr_index)(0)(7 downto 0); -- select lsb of word at index 0 in that block
						when 1  => m_writedata <= cache_data(addr_index)(0)(15 downto 8);
						when 2  => m_writedata <= cache_data(addr_index)(0)(23 downto 16);
						when 3  => m_writedata <= cache_data(addr_index)(0)(31 downto 24);

						when 4  => m_writedata <= cache_data(addr_index)(1)(7 downto 0);
						when 5  => m_writedata <= cache_data(addr_index)(1)(15 downto 8);
						when 6  => m_writedata <= cache_data(addr_index)(1)(23 downto 16);
						when 7  => m_writedata <= cache_data(addr_index)(1)(31 downto 24);

						when 8  => m_writedata <= cache_data(addr_index)(2)(7 downto 0);
						when 9  => m_writedata <= cache_data(addr_index)(2)(15 downto 8);
						when 10 => m_writedata <= cache_data(addr_index)(2)(23 downto 16);
						when 11 => m_writedata <= cache_data(addr_index)(2)(31 downto 24);

						when 12 => m_writedata <= cache_data(addr_index)(3)(7 downto 0);
						when 13 => m_writedata <= cache_data(addr_index)(3)(15 downto 8);
						when 14 => m_writedata <= cache_data(addr_index)(3)(23 downto 16);
						when 15 => m_writedata <= cache_data(addr_index)(3)(31 downto 24);

						when others => null;

    					end case;

    					-- advance when memory accepts write
    					if m_waitrequest = '0' then
							m_write <= '0';
        					if byte_count = 15 then
            					byte_count <= 0;			-- reset byte count
            					cache_dirty(addr_index) <= '0';		-- reset dirty bit
            					state <= REPLACE_BLOCK;
        					else
            					byte_count <= byte_count + 1;
        					end if;
    					end if;

				when REPLACE_BLOCK =>
					-- get block from memory
					m_write <= '0';
					m_read <= '1';

					v_addr := addr_tag & std_logic_vector(to_unsigned(addr_index,5)) & std_logic_vector(to_unsigned(byte_count,4));
                    mem_addr_vec <= v_addr;
                    m_addr <= to_integer(unsigned(v_addr));

					if m_waitrequest = '0' then
						m_read <= '0';
						-- replace block 
						case byte_count is
							when 0  => cache_data(addr_index)(0)(7 downto 0)   <= m_readdata;
							when 1  => cache_data(addr_index)(0)(15 downto 8)  <= m_readdata;
							when 2  => cache_data(addr_index)(0)(23 downto 16) <= m_readdata;
							when 3  => cache_data(addr_index)(0)(31 downto 24) <= m_readdata;

							when 4  => cache_data(addr_index)(1)(7 downto 0)   <= m_readdata;
							when 5  => cache_data(addr_index)(1)(15 downto 8)  <= m_readdata;
							when 6  => cache_data(addr_index)(1)(23 downto 16) <= m_readdata;
							when 7  => cache_data(addr_index)(1)(31 downto 24) <= m_readdata;

							when 8  => cache_data(addr_index)(2)(7 downto 0)   <= m_readdata;
							when 9  => cache_data(addr_index)(2)(15 downto 8)  <= m_readdata;
							when 10 => cache_data(addr_index)(2)(23 downto 16) <= m_readdata;
							when 11 => cache_data(addr_index)(2)(31 downto 24) <= m_readdata;

							when 12 => cache_data(addr_index)(3)(7 downto 0)   <= m_readdata;
							when 13 => cache_data(addr_index)(3)(15 downto 8)  <= m_readdata;
							when 14 => cache_data(addr_index)(3)(23 downto 16) <= m_readdata;
							when 15 => cache_data(addr_index)(3)(31 downto 24) <= m_readdata;

							when others => null;
						end case;
					
						if byte_count = 15 then
							byte_count <= 0;
							m_read <= '0';

							-- updating cache metadat
							cache_tags(addr_index) <= addr_tag;
							cache_valid(addr_index) <= '1';
							cache_dirty(addr_index) <= '0';

							-- Go to FINISH state to complete the CPU request
                            state <= REPLACE_FINISH;
						else
							byte_count <= byte_count + 1;
						end if;
					end if;
				when REPLACE_FINISH =>
					if s_read = '1' then
						s_readdata <= cache_data(addr_index)(addr_offset);
					elsif s_write = '1' then
						cache_data(addr_index)(addr_offset) <= s_writedata;
						cache_dirty(addr_index) <= '1';
					end if;
					s_waitrequest <= '0';
					state <= DONE;
				when DONE =>
					-- holding waitrequest low for a cycle according to avalon interface
					-- s_waitrequest will have been set to low in the previous cycle, will be set to high in the IDLE state
					state <= IDLE;
			end case;
		end if;
	end process;

end arch;