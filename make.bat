@ECHO OFF
del mmx_msu1.sfc
del mmx_msu1_emulator.sfc

copy mmx_original.sfc mmx_msu1.sfc

set BASS_ARG=
if "%~1" == "emu" set BASS_ARG=-d EMULATOR_VOLUME

bass %BASS_ARG% -o mmx_msu1.sfc mmx_msu1_music.asm

copy mmx_original.sfc mmx_msu1_emulator.sfc
bass -d EMULATOR_VOLUME -o mmx_msu1_emulator.sfc mmx_msu1_music.asm