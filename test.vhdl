LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY cache_tb IS
END cache_tb;

ARCHITECTURE behavior OF cache_tb IS

    COMPONENT cache IS
        GENERIC (
            ram_size : INTEGER := 32768
        );
        PORT (
            clock : IN STD_LOGIC;
            reset : IN STD_LOGIC;
            s_addr : IN STD_LOGIC_VECTOR (31 DOWNTO 0);
            s_read : IN STD_LOGIC;
            s_readdata : OUT STD_LOGIC_VECTOR (31 DOWNTO 0);
            s_write : IN STD_LOGIC;
            s_writedata : IN STD_LOGIC_VECTOR (31 DOWNTO 0);
            s_waitrequest : OUT STD_LOGIC;
            m_addr : OUT INTEGER RANGE 0 TO ram_size - 1;
            m_read : OUT STD_LOGIC;
            m_readdata : IN STD_LOGIC_VECTOR (7 DOWNTO 0);
            m_write : OUT STD_LOGIC;
            m_writedata : OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
            m_waitrequest : IN STD_LOGIC
        );
    END COMPONENT;

    COMPONENT memory IS
        GENERIC (
            ram_size : INTEGER := 32768;
            mem_delay : TIME := 10 ns;
            clock_period : TIME := 1 ns
        );
        PORT (
            clock : IN STD_LOGIC;
            writedata : IN STD_LOGIC_VECTOR (7 DOWNTO 0);
            address : IN INTEGER RANGE 0 TO ram_size - 1;
            memwrite : IN STD_LOGIC;
            memread : IN STD_LOGIC;
            readdata : OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
            waitrequest : OUT STD_LOGIC
        );
    END COMPONENT;

    SIGNAL reset : STD_LOGIC := '0';
    SIGNAL clk : STD_LOGIC := '0';
    CONSTANT clk_period : TIME := 1 ns;

    SIGNAL s_addr : STD_LOGIC_VECTOR (31 DOWNTO 0);
    SIGNAL s_read : STD_LOGIC;
    SIGNAL s_readdata : STD_LOGIC_VECTOR (31 DOWNTO 0);
    SIGNAL s_write : STD_LOGIC;
    SIGNAL s_writedata : STD_LOGIC_VECTOR (31 DOWNTO 0);
    SIGNAL s_waitrequest : STD_LOGIC;

    SIGNAL m_addr : INTEGER RANGE 0 TO 2147483647;
    SIGNAL m_read : STD_LOGIC;
    SIGNAL m_readdata : STD_LOGIC_VECTOR (7 DOWNTO 0);
    SIGNAL m_write : STD_LOGIC;
    SIGNAL m_writedata : STD_LOGIC_VECTOR (7 DOWNTO 0);
    SIGNAL m_waitrequest : STD_LOGIC;

    -- -------------------------------------------------------
    -- Address map (cache uses bits 14:0 only):
    --   tag   = bits 14:9  (6 bits)
    --   index = bits  8:4  (5 bits)
    --   offset= bits  3:2  (2 bits, word select)
    --
    -- To get DIFFERENT tags at the SAME index, add 0x200 (bit 9).
    --   0x00000000 -> tag=0, index=0
    --   0x00000200 -> tag=1, index=0   (evicts tag=0 at index=0)
    --   0x00000100 -> tag=0, index=16
    --   0x00000300 -> tag=1, index=16  (evicts tag=0 at index=16)
    --
    -- *** WRONG (bit 15 is ignored by cache): ***
    --   0x00008000 -> tag=0, index=0   (SAME as 0x00000000! No eviction!)
    -- -------------------------------------------------------

    FUNCTION slv_to_hex(slv : STD_LOGIC_VECTOR) RETURN STRING IS
        CONSTANT hex_chars : STRING(1 TO 16) := "0123456789abcdef";
        VARIABLE padded : STD_LOGIC_VECTOR(((slv'length + 3) / 4) * 4 - 1 DOWNTO 0) := (OTHERS => '0');
        VARIABLE result : STRING(1 TO (slv'length + 3) / 4);
        VARIABLE nibble : STD_LOGIC_VECTOR(3 DOWNTO 0);
        VARIABLE idx : INTEGER;
    BEGIN
        padded(slv'length - 1 DOWNTO 0) := slv;
        FOR i IN result'RANGE LOOP
            nibble := padded(padded'length - (i - 1) * 4 - 1 DOWNTO padded'length - i * 4);
            IF nibble = "0000" THEN
                idx := 1;
            ELSIF nibble = "0001" THEN
                idx := 2;
            ELSIF nibble = "0010" THEN
                idx := 3;
            ELSIF nibble = "0011" THEN
                idx := 4;
            ELSIF nibble = "0100" THEN
                idx := 5;
            ELSIF nibble = "0101" THEN
                idx := 6;
            ELSIF nibble = "0110" THEN
                idx := 7;
            ELSIF nibble = "0111" THEN
                idx := 8;
            ELSIF nibble = "1000" THEN
                idx := 9;
            ELSIF nibble = "1001" THEN
                idx := 10;
            ELSIF nibble = "1010" THEN
                idx := 11;
            ELSIF nibble = "1011" THEN
                idx := 12;
            ELSIF nibble = "1100" THEN
                idx := 13;
            ELSIF nibble = "1101" THEN
                idx := 14;
            ELSIF nibble = "1110" THEN
                idx := 15;
            ELSIF nibble = "1111" THEN
                idx := 16;
            ELSE
                idx := 1;
            END IF;
            result(i) := hex_chars(idx);
        END LOOP;
        RETURN result;
    END FUNCTION;

BEGIN

    dut : cache
    PORT MAP(
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
    PORT MAP(
        clock => clk,
        writedata => m_writedata,
        address => m_addr,
        memwrite => m_write,
        memread => m_read,
        readdata => m_readdata,
        waitrequest => m_waitrequest
    );

    clk_process : PROCESS
    BEGIN
        clk <= '0';
        WAIT FOR clk_period/2;
        clk <= '1';
        WAIT FOR clk_period/2;
    END PROCESS;

    test_process : PROCESS

        PROCEDURE read_test(addr : IN STD_LOGIC_VECTOR(31 DOWNTO 0)) IS
        BEGIN
            REPORT "READ_TEST: Initiating read at addr=0x" & slv_to_hex(addr) SEVERITY note;
            s_addr <= addr;
            s_read <= '1';
            s_write <= '0';

            WAIT UNTIL rising_edge(clk);
            WHILE s_waitrequest = '1' LOOP
                WAIT UNTIL rising_edge(clk);
            END LOOP;

            s_read <= '0';
            WAIT UNTIL rising_edge(clk);
            REPORT "READ_TEST: Complete. addr=0x" & slv_to_hex(addr)
                & " | s_readdata=0x" & slv_to_hex(s_readdata)
                & " | m_write=" & STD_LOGIC'image(m_write)
                & " | m_read=" & STD_LOGIC'image(m_read)
                & " | m_addr=" & INTEGER'image(m_addr)
                SEVERITY note;
        END PROCEDURE;

        PROCEDURE write_test(
            addr : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
            data : IN STD_LOGIC_VECTOR(31 DOWNTO 0)) IS
        BEGIN
            REPORT "WRITE_TEST: Initiating write at addr=0x" & slv_to_hex(addr)
                & " data=0x" & slv_to_hex(data) SEVERITY note;
            s_addr <= addr;
            s_writedata <= data;
            s_read <= '0';
            s_write <= '1';

            WAIT UNTIL rising_edge(clk);
            WHILE s_waitrequest = '1' LOOP
                WAIT UNTIL rising_edge(clk);
            END LOOP;

            s_write <= '0';
            WAIT UNTIL rising_edge(clk);
            REPORT "WRITE_TEST: Complete. addr=0x" & slv_to_hex(addr)
                & " | m_write=" & STD_LOGIC'image(m_write)
                & " | m_read=" & STD_LOGIC'image(m_read)
                & " | m_addr=" & INTEGER'image(m_addr)
                & " | m_writedata=0x" & slv_to_hex(m_writedata)
                SEVERITY note;
        END PROCEDURE;

    BEGIN

        s_addr <= (OTHERS => '0');
        s_read <= '0';
        s_write <= '0';
        s_writedata <= (OTHERS => '0');

        REPORT "DIAG: Asserting reset to initialize cache..." SEVERITY note;
        reset <= '1';
        WAIT FOR 20 ns;
        reset <= '0';
        REPORT "DIAG: Reset done. s_waitrequest=" & STD_LOGIC'image(s_waitrequest)
            & " | m_addr=" & INTEGER'image(m_addr)
            SEVERITY note;

        WAIT UNTIL rising_edge(clk);

        -- ===================================================================
        -- CASE 1: Write to INVALID, CLEAN block, NO tag match
        --   Cache index 0 is invalid after reset. Writing 0x00000000 causes
        --   a miss -> REPLACE_BLOCK (load from memory) -> REPLACE_FINISH
        --   (write data, set dirty=1, valid=1, tag=0).
        -- ===================================================================
        REPORT "=== CASE 1: Write | invalid | clean | no tag match ===" SEVERITY note;
        write_test(x"00000000", x"beefcafe");

        -- ===================================================================
        -- CASE 2: Read from VALID, DIRTY block, WITH tag match (cache hit)
        --   Index 0 now has tag=0, dirty=1, valid=1 from Case 1.
        --   Reading 0x00000000 (tag=0, index=0) is a hit -> return cached data.
        -- ===================================================================
        REPORT "=== CASE 2: Read | valid | dirty | tag match ===" SEVERITY note;
        read_test(x"00000000");
        REPORT "CASE 2 CHECK: got=0x" & slv_to_hex(s_readdata) & " expected=0xbeefcafe" SEVERITY note;
        ASSERT (s_readdata = x"beefcafe")
        REPORT "FAIL Case 2: read after write returned wrong data"
            SEVERITY ERROR;

        -- ===================================================================
        -- CASE 3: Write to VALID, DIRTY block, WITH tag match (cache hit)
        --   Index 0: valid=1, dirty=1, tag=0. Writing 0x00000000 again is a
        --   hit -> overwrite cached word, dirty stays 1.
        -- ===================================================================
        REPORT "=== CASE 3: Write | valid | dirty | tag match ===" SEVERITY note;
        write_test(x"00000000", x"deadbeef");
        read_test(x"00000000");
        REPORT "CASE 3 CHECK: got=0x" & slv_to_hex(s_readdata) & " expected=0xdeadbeef" SEVERITY note;
        ASSERT (s_readdata = x"deadbeef")
        REPORT "FAIL Case 3: overwrite of dirty valid block failed"
            SEVERITY ERROR;

        -- ===================================================================
        -- CASE 4: Read from VALID, DIRTY block, NO tag match (dirty eviction)
        --   Index 0: valid=1, dirty=1, tag=0 (holds 0xdeadbeef).
        --   Reading 0x00000200 (tag=1, index=0) -> miss, dirty -> WRITEBACK
        --   (write 0xdeadbeef to memory at tag=0/index=0), then REPLACE_BLOCK
        --   (load tag=1/index=0 from memory) -> REPLACE_FINISH.
        --   Verify by re-reading 0x00000000: must come from memory = 0xdeadbeef.
        -- ===================================================================
        REPORT "=== CASE 4: Read | valid | dirty | no tag match (dirty eviction) ===" SEVERITY note;
        REPORT "CASE 4: Reading 0x00000200 to evict dirty tag=0 block at index=0..." SEVERITY note;
        read_test(x"00000200");
        REPORT "CASE 4: Re-reading 0x00000000 to confirm writeback to memory..." SEVERITY note;
        read_test(x"00000000");
        REPORT "CASE 4 CHECK: got=0x" & slv_to_hex(s_readdata) & " expected=0xdeadbeef" SEVERITY note;
        ASSERT (s_readdata = x"deadbeef")
        REPORT "FAIL Case 4: dirty eviction did not write back to memory correctly"
            SEVERITY ERROR;

        -- ===================================================================
        -- CASE 5: Write to VALID, CLEAN block, NO tag match
        --   Index 0: valid=1, dirty=0, tag=0 (loaded from memory in Case 4).
        --   Writing 0x00000200 first makes index=0 hold tag=1, clean (from
        --   memory). Then writing 0x00000000 (tag=0) -> miss, clean -> no
        --   writeback, REPLACE_BLOCK (load tag=0 from memory) -> REPLACE_FINISH
        --   (write data, set dirty=1).
        -- ===================================================================
        REPORT "=== CASE 5: Write | valid | clean | no tag match ===" SEVERITY note;
        read_test(x"00000200"); -- ensure index=0 holds tag=1 (clean)
        write_test(x"00000000", x"beefcafe");
        read_test(x"00000000");
        REPORT "CASE 5 CHECK: got=0x" & slv_to_hex(s_readdata) & " expected=0xbeefcafe" SEVERITY note;
        ASSERT (s_readdata = x"beefcafe")
        REPORT "FAIL Case 5: write to valid clean block with tag mismatch failed"
            SEVERITY ERROR;

        -- ===================================================================
        -- CASE 6: Write to VALID, DIRTY block, NO tag match
        --   Index 0: valid=1, dirty=1, tag=0 (holds 0xbeefcafe from Case 5).
        --   Writing 0x00000200 (tag=1) -> miss, dirty -> WRITEBACK (write
        --   0xbeefcafe to memory for tag=0), REPLACE_BLOCK, REPLACE_FINISH
        --   (write 0x10101010 for tag=1, set dirty=1).
        -- ===================================================================
        REPORT "=== CASE 6: Write | valid | dirty | no tag match ===" SEVERITY note;
        write_test(x"00000200", x"10101010");
        read_test(x"00000200");
        REPORT "CASE 6 CHECK: got=0x" & slv_to_hex(s_readdata) & " expected=0x10101010" SEVERITY note;
        ASSERT (s_readdata = x"10101010")
        REPORT "FAIL Case 6: write to valid dirty block with tag mismatch failed"
            SEVERITY ERROR;

        -- ===================================================================
        -- CASE 7: Read from INVALID, CLEAN block, NO tag match
        --   Index 8 has never been touched (invalid after reset).
        --   Reading 0x00000080 (tag=0, index=8, offset=0) -> miss, invalid,
        --   clean -> REPLACE_BLOCK (fetch from memory, no writeback).
        --   Memory was initialized as ram(i) = i mod 256, so word 0 of the
        --   block at memory address 8*16=128=0x80 is {0x83,0x82,0x81,0x80} =
        --   0x83828180. We verify s_readdata is that value (NOT all zeros,
        --   which would indicate cache wasn't populated from memory).
        --   NOTE: m_write is never asserted for a read miss; m_read is used.
        -- ===================================================================
        REPORT "=== CASE 7: Read | invalid | clean | no tag match ===" SEVERITY note;
        read_test(x"00000080");
        REPORT "CASE 7 CHECK: s_readdata=0x" & slv_to_hex(s_readdata)
            & " (expected 0x83828180 = memory init values at block index=8)"
            SEVERITY note;
        ASSERT (s_readdata = x"83828180")
        REPORT "FAIL Case 7: read of invalid block did not fetch correctly from memory"
            SEVERITY ERROR;

        -- ===================================================================
        -- CASE 8: Read from VALID, CLEAN block, NO tag match
        --   After Case 7, index=8 has tag=0, valid=1, dirty=0.
        --   Reading 0x00000280 (tag=1, index=8) -> miss, clean -> no writeback,
        --   REPLACE_BLOCK (load tag=1/index=8 from memory).
        --   Then re-reading 0x00000080 (tag=0, index=8) verifies that the
        --   previously evicted clean block was NOT written to memory (it was
        --   clean, so memory still has the right data -> re-read gets it back).
        -- ===================================================================
        REPORT "=== CASE 8: Read | valid | clean | no tag match ===" SEVERITY note;
        read_test(x"00000280"); -- evict clean tag=0 from index=8, load tag=1
        read_test(x"00000080"); -- evict clean tag=1, reload tag=0 from memory
        REPORT "CASE 8 CHECK: got=0x" & slv_to_hex(s_readdata) & " expected=0x83828180" SEVERITY note;
        ASSERT (s_readdata = x"83828180")
        REPORT "FAIL Case 8: read of valid clean block with tag mismatch failed"
            SEVERITY ERROR;

        -- ===================================================================
        -- CASE 9: Read from VALID, CLEAN block, WITH tag match (cache hit)
        --   Index=8 now has tag=0, valid=1, dirty=0 from Case 8.
        --   Reading 0x00000080 again is a hit -> return cached data immediately.
        -- ===================================================================
        REPORT "=== CASE 9: Read | valid | clean | tag match ===" SEVERITY note;
        read_test(x"00000080");
        REPORT "CASE 9 CHECK: got=0x" & slv_to_hex(s_readdata) & " expected=0x83828180" SEVERITY note;
        ASSERT (s_readdata = x"83828180")
        REPORT "FAIL Case 9: read hit on valid clean block returned wrong data"
            SEVERITY ERROR;

        -- ===================================================================
        -- CASE 10: Write to VALID, CLEAN block, WITH tag match (cache hit)
        --   Index=8: valid=1, dirty=0, tag=0. Writing 0x00000080 -> hit,
        --   overwrite word, set dirty=1.
        -- ===================================================================
        REPORT "=== CASE 10: Write | valid | clean | tag match ===" SEVERITY note;
        write_test(x"00000080", x"abbacafe");
        read_test(x"00000080");
        REPORT "CASE 10 CHECK: got=0x" & slv_to_hex(s_readdata) & " expected=0xabbacafe" SEVERITY note;
        ASSERT (s_readdata = x"abbacafe")
        REPORT "FAIL Case 10: write hit on valid clean block failed"
            SEVERITY ERROR;

        -- ===================================================================
        -- CASE 11: Read from INVALID, CLEAN block, WITH tag match (after reset)
        --   Write 0xbeefcab5 to 0x00000100 (tag=0, index=16), making it dirty.
        --   Evict by reading 0x00000300 (tag=1, index=16) -> WRITEBACK sends
        --   0xbeefcab5 to memory at tag=0/index=16 = address 0x100.
        --   Reset cache (all blocks invalid, dirty=0, tags cleared).
        --   Read 0x00000100 again -> INVALID, so tag match is irrelevant;
        --   must fetch from memory and return 0xbeefcab5.
        -- ===================================================================
        REPORT "=== CASE 11: Read | invalid | clean | tag match (after reset) ===" SEVERITY note;
        REPORT "CASE 11: Writing 0xbeefcab5 to addr 0x00000100 (tag=0, index=16)..." SEVERITY note;
        write_test(x"00000100", x"beefcab5");
        REPORT "CASE 11: Evicting dirty block by reading 0x00000300 (tag=1, index=16)..." SEVERITY note;
        read_test(x"00000300");
        REPORT "CASE 11: Re-reading 0x00000100 to confirm writeback worked..." SEVERITY note;
        read_test(x"00000100");
        REPORT "CASE 11: Value at 0x00000100 before reset=0x" & slv_to_hex(s_readdata) SEVERITY note;

        REPORT "CASE 11: Resetting cache (invalidates all blocks)..." SEVERITY note;
        reset <= '1';
        WAIT FOR 20 ns;
        reset <= '0';
        WAIT UNTIL rising_edge(clk);

        REPORT "CASE 11: Reading 0x00000100 after reset - must come from memory..." SEVERITY note;
        read_test(x"00000100");
        REPORT "CASE 11 CHECK: got=0x" & slv_to_hex(s_readdata) & " expected=0xbeefcab5" SEVERITY note;
        ASSERT (s_readdata = x"beefcab5")
        REPORT "FAIL Case 11: post-reset read did not fetch written-back data from memory"
            SEVERITY ERROR;

        -- ===================================================================
        -- CASE 12: Write to INVALID block (tag irrelevant since invalid)
        --   After reset, index=0 is invalid. Writing 0x00000200 (tag=1, index=0)
        --   -> INVALID -> REPLACE_BLOCK (load from memory), REPLACE_FINISH
        --   (write data, valid=1, dirty=1, tag=1).
        --   Read back to verify.
        -- ===================================================================
        REPORT "=== CASE 12: Write | invalid | clean | (tag match irrelevant) ===" SEVERITY note;
        write_test(x"00000200", x"12345678");
        read_test(x"00000200");
        REPORT "CASE 12 CHECK: got=0x" & slv_to_hex(s_readdata) & " expected=0x12345678" SEVERITY note;
        ASSERT (s_readdata = x"12345678")
        REPORT "FAIL Case 12: write to invalid block failed"
            SEVERITY ERROR;

        -- ===================================================================
        -- FINAL: Confirm memory persistence across reset
        --   Write 0x12345678 to 0x00000200, evict, reset, re-read from memory.
        -- ===================================================================
        REPORT "=== FINAL: Verify memory persistence after reset ===" SEVERITY note;
        -- 0x00000200 is dirty (tag=1, index=0) from Case 12.
        -- Evict by reading 0x00000000 (tag=0, index=0) -> writeback 0x12345678 to memory.
        REPORT "FINAL: Evicting dirty 0x00000200 block by reading 0x00000000..." SEVERITY note;
        read_test(x"00000000");
        REPORT "FINAL: Resetting cache..." SEVERITY note;
        reset <= '1';
        WAIT FOR 20 ns;
        reset <= '0';
        WAIT UNTIL rising_edge(clk);
        REPORT "FINAL: Reading 0x00000200 after reset - expected 0x12345678 from memory..." SEVERITY note;
        read_test(x"00000200");
        REPORT "FINAL CHECK: got=0x" & slv_to_hex(s_readdata) & " expected=0x12345678" SEVERITY note;
        ASSERT (s_readdata = x"12345678")
        REPORT "FAIL Final: memory did not persist data across cache reset"
            SEVERITY ERROR;

        REPORT "All test cases done. No errors = all cases passed." SEVERITY note;
        WAIT;
    END PROCESS;

END;