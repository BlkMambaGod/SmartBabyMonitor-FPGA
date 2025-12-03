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
        BUZZER      : out std_logic      -- Buzzer output
    );
end final;

architecture Behavioural of final is

    -----------------------------------------------------------------------
    -- CONSTANTS
    -----------------------------------------------------------------------

    constant PERIOD     : integer := 1000000;
    -- PWM period (in clock cycles). At 50 MHz, 1,000,000 cycles ≈ 20 ms
    -- This matches standard servo update frequency (50 Hz).

    constant NONE       : integer := 50000;
    -- Pulse width when "safe" (servo in position A). 50,000 cycles ≈ 1 ms.

    constant ALLOWED    : integer := 75000;
    -- Pulse width when "alert" (servo in position B). 75,000 cycles ≈ 1.5 ms.

    -----------------------------------------------------------------------
    -- SIGNALS
    -----------------------------------------------------------------------

    signal mq135_sync1  : std_logic := '0';
    signal mq135_sync2  : std_logic := '0';
    -- Two-stage synchronizer for MQ135_DOUT to avoid metastability.

    signal counter      : unsigned(23 downto 0) := (others => '0');
    -- Debounce/filter counter. Used to confirm sensor changes.

    signal mq135_state  : std_logic := '0';
    -- Stable debounced value of the MQ135 signal.

    signal pwm_counter  : integer := 0;
    -- Counts up to PERIOD to generate PWM.

    signal pulse_width  : integer := ALLOWED;
    -- Current PWM pulse width (NONE or ALLOWED depending on air quality).

    signal servo        : std_logic := '0';
    -- Internal signal controlling pulse_width (inverted MQ135 state).

begin

    -----------------------------------------------------------------------
    -- INPUT SYNCHRONIZER
    -- This prevents metastability by passing the input through two flip-flops.
    -----------------------------------------------------------------------
    process(clk, RESET_N)
    begin
        if RESET_N = '0' then
            mq135_sync1 <= '0';
            mq135_sync2 <= '0';

        elsif rising_edge(clk) then
            mq135_sync1 <= MQ135_DOUT;   -- First stage
            mq135_sync2 <= mq135_sync1;  -- Second stage (stable version)
        end if;
    end process;

    -----------------------------------------------------------------------
    -- INPUT DEBOUNCE / NOISE FILTERING
    -- mq135_state is updated only if the input remains different
    -- from its current state for a long enough time (counter reaches threshold).
    -----------------------------------------------------------------------
    process(clk, RESET_N)
    begin
        if RESET_N = '0' then
            counter      <= (others => '0');
            mq135_state  <= '0';

        elsif rising_edge(clk) then

            -- If the synchronized input changed compared to the saved state
            if mq135_sync2 /= mq135_state then
                counter <= counter + 1;  -- Count how long the new value persists

                -- Once enough cycles pass (acts as a debounce filter)
                if counter = x"FFFF" then
                    mq135_state <= mq135_sync2;  -- Accept new stable state
                    counter     <= (others => '0');
                end if;

            else
                -- If input equals the stable state, reset counter
                counter <= (others => '0');
            end if;

        end if;
    end process;

    -----------------------------------------------------------------------
    -- OUTPUT LOGIC
    -- Red LED, buzzer, and servo activate when sensor state is HIGH.
    -----------------------------------------------------------------------
    LED_V   <= mq135_state;        -- Green LED indicates safe
    LED_R   <= not mq135_state;    -- Red LED indicates alert
    BUZZER  <= not mq135_state;    -- Buzzer activates on alert
    servo   <= not mq135_state;    -- Servo activates on alert

    -----------------------------------------------------------------------
    -- PWM GENERATION FOR SERVO CONTROL
    -- Produces a pulse (1 ms or 1.5 ms) inside a 20 ms period.
    -----------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then

            -------------------------------------------------------------------
            -- PWM COUNTER LOGIC (0 to PERIOD)
            -------------------------------------------------------------------
            pwm_counter <= pwm_counter + 1;

            -- Set PWM output high during the pulse width
            if pwm_counter < pulse_width then
                pwd <= '1';
            else
                pwd <= '0';
            end if;

            -- Reset counter after reaching full period
            if pwm_counter >= PERIOD then
                pwm_counter <= 0;
            end if;

            -------------------------------------------------------------------
            -- SERVO POSITION CONTROL
            -- Changes the pulse width depending on air quality state.
            -------------------------------------------------------------------
            if servo = '0' then
                pulse_width <= NONE;     -- Low pulse width (1 ms)
            else
                pulse_width <= ALLOWED;  -- High pulse width (1.5 ms)
            end if;

        end if;
    end process;

end Behavioural;
