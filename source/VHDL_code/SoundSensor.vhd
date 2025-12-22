library IEEE;
use IEEE.std_logic_1164.all;

ENTITY SoundSensor IS
    PORT(
        sound_sensor : IN  std_logic;
        sound_light    : OUT std_logic
    );
END SoundSensor;

ARCHITECTURE Behaviour OF SoundSensor IS
BEGIN
	PROCESS(sound_sensor)
BEGIN
    sound_light <= sound_sensor;
	 END PROCESS;
END Behaviour;