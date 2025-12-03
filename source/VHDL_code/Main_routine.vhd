library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity final is
    port (
        clk         : in std_logic;      -- 50 MHz system clock
        pwd         : out std_logic;     -- PWM output for the servo (pulse width modulated)
        RESET_N     : in std_logic;      -- Active-low asynchronous reset
        MQ135_DOUT  : in std_logic;      -- Raw digital output from MQ135 gas sensor
        LED_R       : out std_logic;     -- Red LED output
        LED_V       : out std_logic;     -- Green LED output
        BUZZER      : out std_logic;     -- Buzzer output
        RX          : in  std_logic;     -- UART RX input
        data_byte   : out std_logic_vector(7 downto 0); -- Last received byte
        data_valid  : out std_logic;     -- Pulse: 1 clock when byte received
        TX          : out std_logic;     -- UART TX output
        send        : in  std_logic;     -- Trigger to send tx_byte
        tx_byte     : in  std_logic_vector(7 downto 0); -- Byte to transmit
        busy        : out std_logic      -- TX busy (1 while transmitting)
    );
end final;

architecture Behavioural of final is

    -----------------------------------------------------------------------
    -- PWM / Servo constants
    -----------------------------------------------------------------------
    constant PERIOD     : integer := 1000000;  -- 1,000,000 cycles ≈ 20 ms @ 50 MHz
    constant NONE       : integer := 50000;    -- 50,000 cycles ≈ 1 ms
    constant ALLOWED    : integer := 75000;    -- 75,000 cycles ≈ 1.5 ms

    -----------------------------------------------------------------------
    -- MQ135 Debounce / Synchronizer signals
    -----------------------------------------------------------------------
    signal mq135_sync1  : std_logic := '0';
    signal mq135_sync2  : std_logic := '0';
    signal counter      : unsigned(23 downto 0) := (others => '0'); -- 24-bit counter
    signal mq135_state  : std_logic := '0';

    -----------------------------------------------------------------------
    -- PWM / Servo control signals
    -----------------------------------------------------------------------
    signal pwm_counter  : integer := 0;
    signal pulse_width  : integer := ALLOWED;
    signal servo        : std_logic := '0';

    -----------------------------------------------------------------------
    -- UART constants and signals (115200 @ 50 MHz)
    -----------------------------------------------------------------------
    constant BAUD_DIV : integer := 434;  -- 50MHz / 115200 ≈ 434

    -- RX signals
    signal rx_sync1      : std_logic := '1';
    signal rx_sync2      : std_logic := '1';
    signal receiving     : std_logic := '0';
    signal baud_count_rx : integer range 0 to BAUD_DIV-1 := 0;
    signal bit_index_rx  : integer range 0 to 9 := 0;
    signal shift_rx      : std_logic_vector(7 downto 0) := (others => '0');
    signal dv            : std_logic := '0';

    -- TX signals
    signal tx_reg        : std_logic := '1';
    signal sending       : std_logic := '0';
    signal shift_tx      : std_logic_vector(7 downto 0) := (others => '0');
    signal baud_count_tx : integer range 0 to BAUD_DIV-1 := 0;
    signal bit_index_tx  : integer range 0 to 9 := 0;

    -----------------------------------------------------------------------
    -- MESSAGE FLAGS decoded from received bytes
    -----------------------------------------------------------------------
    signal spo2_msg : std_logic := '0';
    signal hr_msg   : std_logic := '0';

begin

    ----------------------------------------------------------------------------
    -- Top-level assignments
    ----------------------------------------------------------------------------
    TX         <= tx_reg;
    busy       <= sending;
    data_valid <= dv;
    data_byte  <= shift_rx;

    ----------------------------------------------------------------------------
    -- MQ135 input synchronizer (2-stage) to avoid metastability
    ----------------------------------------------------------------------------
    process(clk, RESET_N)
    begin
        if RESET_N = '0' then
            mq135_sync1 <= '0';
            mq135_sync2 <= '0';
        elsif rising_edge(clk) then
            mq135_sync1 <= MQ135_DOUT;   -- first stage
            mq135_sync2 <= mq135_sync1;  -- second stage
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- MQ135 debounce / filter process
    -- Accept a change only after it remains stable for the debounce count.
    ----------------------------------------------------------------------------
    process(clk, RESET_N)
    begin
        if RESET_N = '0' then
            counter     <= (others => '0');
            mq135_state <= '0';
        elsif rising_edge(clk) then
            if mq135_sync2 /= mq135_state then
                counter <= counter + 1;

                -- <<< FIX: counter is 24 bits, compare to 24-bit constant >>>
                if counter = x"FFFFFF" then
                    mq135_state <= mq135_sync2;
                    counter     <= (others => '0');
                end if;
            else
                counter <= (others => '0');
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- Outputs driven by MQ135 state
    ----------------------------------------------------------------------------
    LED_V  <= mq135_state;        -- green when safe (state='1')
    LED_R  <= not mq135_state;    -- red when alert
    BUZZER <= not mq135_state;    -- buzzer active on alert
    servo  <= not mq135_state;    -- servo active on alert (inverted mapping preserved)

    ----------------------------------------------------------------------------
    -- PWM generation (servo)
    -- Produces a pulse of pulse_width inside PERIOD. Added reset behavior.
    ----------------------------------------------------------------------------
    process(clk, RESET_N)
    begin
        if RESET_N = '0' then
            pwm_counter <= 0;
            pulse_width <= ALLOWED; -- default
            pwd <= '0';
        elsif rising_edge(clk) then
            -- increment PWM counter
            pwm_counter <= pwm_counter + 1;

            -- set PWM output based on pulse_width
            if pwm_counter < pulse_width then
                pwd <= '1';
            else
                pwd <= '0';
            end if;

            -- wrap PWM counter
            if pwm_counter >= PERIOD then
                pwm_counter <= 0;
            end if;

            -- update pulse_width from servo flag
            if servo = '0' then
                pulse_width <= NONE;
            else
                pulse_width <= ALLOWED;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- UART RX process
    --  - 2-stage synchronizer already handled in local rx_sync1/rx_sync2
    --  - Detect start bit, sample mid-bit, collect 8 data bits LSB-first,
    --    check stop bit, assert dv and run decoder when frame completes.
    ----------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then

            -- synchronize RX pin into clock domain
            rx_sync1 <= RX;
            rx_sync2 <= rx_sync1;

            -- default: data valid low (pulses to '1' when byte completes)
            dv <= '0';

            -- if not currently receiving, watch for start bit
            if receiving = '0' then
                if rx_sync2 = '0' then    -- start bit detected (line went low)
                    receiving     <= '1';
                    bit_index_rx  <= 0;
                    baud_count_rx <= BAUD_DIV / 2;  -- sample in the middle of first data bit
                end if;

            else  -- receiving = '1', process ongoing frame

                -- baud timing counter
                if baud_count_rx = BAUD_DIV-1 then
                    baud_count_rx <= 0;
                    bit_index_rx  <= bit_index_rx + 1;
                else
                    baud_count_rx <= baud_count_rx + 1;
                end if;

                -- sample at the end of each bit-time
                if baud_count_rx = BAUD_DIV-1 then
                    case bit_index_rx is
                        when 0 =>
                            -- verify start bit still low
                            if rx_sync2 = '1' then
                                receiving <= '0'; -- false start, abort
                            end if;

                        when 1 to 8 =>
                            -- collect data bits LSB first
                            shift_rx(bit_index_rx - 1) <= rx_sync2;

                        when 9 =>
                            -- stop bit: frame finished
                            receiving <= '0';
                            if rx_sync2 = '1' then
                                dv <= '1'; -- byte is valid this cycle

                                ----------------------------------------------------------------
                                -- BYTE DECODER: update message flags immediately on valid byte
                                -- <<< RESTORED ORIGINAL MAPPINGS (F0, 0F, FF) >>>
                                ----------------------------------------------------------------
                                case shift_rx is
                                    when x"00" =>
                                        spo2_msg <= '0';
                                        hr_msg   <= '0';

                                    when x"F0" =>
                                        spo2_msg <= '0';
                                        hr_msg   <= '1';

                                    when x"0F" =>
                                        spo2_msg <= '1';
                                        hr_msg   <= '0';

                                    when x"FF" =>
                                        spo2_msg <= '1';
                                        hr_msg   <= '1';

                                    when others =>
                                        null;
                                end case;
                            end if;

                        when others =>
                            null;
                    end case;
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- UART TX process
    --  - When `send` is pulsed high (one cycle), load tx_byte and start sending.
    --  - Send 1 start bit, 8 data bits (LSB-first), 1 stop bit.
    --  - On completion, sending <= '0' and tx_reg returns to '1' (idle).
    ----------------------------------------------------------------------------
    process(clk, RESET_N)
    begin
        if RESET_N = '0' then
            -- safe initial state after reset
            sending       <= '0';
            shift_tx      <= (others => '0');
            baud_count_tx <= 0;
            bit_index_tx  <= 0;
            tx_reg        <= '1'; -- idle
        elsif rising_edge(clk) then

            if sending = '0' then
                -- idle, check send strobe
                if send = '1' then
                    sending       <= '1';
                    shift_tx      <= tx_byte;
                    bit_index_tx  <= 0;
                    baud_count_tx <= 0;
                    tx_reg        <= '0'; -- send start bit immediately
                end if;

            else
                -- transmission in progress: advance baud counter
                if baud_count_tx = BAUD_DIV-1 then
                    baud_count_tx <= 0;
                    bit_index_tx  <= bit_index_tx + 1;
                else
                    baud_count_tx <= baud_count_tx + 1;
                end if;

                -- change tx output at bit boundaries
                if baud_count_tx = BAUD_DIV-1 then
                    case bit_index_tx is
                        when 1 to 8 =>
                            tx_reg <= shift_tx(bit_index_tx - 1); -- data bits LSB-first

                        when 9 =>
                            tx_reg   <= '1';   -- stop bit (line idle)
                            sending  <= '0';   -- done

                        when others =>
                            null;
                    end case;
                end if;
            end if;
        end if;
    end process;

end Behavioural;
