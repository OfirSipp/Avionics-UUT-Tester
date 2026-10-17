@echo off
rem Runs both self-checking testbenches. Double-click it or run sim\run_sim.bat.
rem Simulator: Vivado xsim if Vivado is on PATH, in XILINX_VIVADO or in a usual
rem install folder (X:\Xilinx, X:\AMDDesignTools, X:\Vivado), otherwise GHDL.
setlocal
cd /d "%~dp0"
set SRC=Tone_Config.vhd ADC_LTC.vhd DAC8043FP2.vhd Tone_Recognition.vhd Tone_Generator.vhd tb_ADC_DAC.vhd tb_Tone_Recognition.vhd

rem Vivado's own .bat files abort on a folder path with parentheses, such as
rem "Avionics-UUT-Tester-main (1)", so the simulation runs in a scratch folder
rem with copies of the sources.
set "W=%TEMP%\uut_tester_sim"
if not exist "%W%" mkdir "%W%"
for %%F in (..\rtl\Tone_Config.vhd ..\rtl\ADC_LTC.vhd ..\rtl\DAC8043FP2.vhd ..\rtl\Tone_Recognition.vhd
            Tone_Generator.vhd tb_ADC_DAC.vhd tb_Tone_Recognition.vhd) do (
  copy /y "%%F" "%W%" >nul || goto fail
)

rem --- find a simulator ---------------------------------------------------------
where xvhdl >nul 2>&1 && goto xsim
set VBIN=
if defined XILINX_VIVADO if exist "%XILINX_VIVADO%\bin\xvhdl.bat" set "VBIN=%XILINX_VIVADO%\bin"
if defined VBIN goto addvivado
for %%D in (C D E F G) do (
  for /d %%V in ("%%D:\Xilinx\Vivado\*") do if exist "%%~V\bin\xvhdl.bat" set "VBIN=%%~V\bin"
  for /d %%V in ("%%D:\Xilinx\*" "%%D:\AMDDesignTools\*" "%%D:\Vivado\*") do if exist "%%~V\Vivado\bin\xvhdl.bat" set "VBIN=%%~V\Vivado\bin"
)
if not defined VBIN goto noxsim
:addvivado
set "PATH=%VBIN%;%PATH%"
goto xsim

:noxsim
where ghdl >nul 2>&1 && goto ghdl
echo No VHDL simulator found.
echo Install Vivado, or GHDL:  winget install ghdl.ghdl.ucrt64.mcode
echo or put Vivado's bin folder on PATH / set XILINX_VIVADO.
goto fail

rem --- Vivado xsim -----------------------------------------------------------------
:xsim
echo Simulator: Vivado xsim
echo Work folder: %W%
cd /d "%W%"
call xvhdl -2008 %SRC% || goto fail
call :xsim_tb tb_ADC_DAC || goto fail
echo tb_Tone_Recognition simulates about 7 s of signals - this takes a minute or two...
call :xsim_tb tb_Tone_Recognition || goto fail
goto pass

:xsim_tb
call xelab -debug off %1 -s %1 || exit /b 1
call xsim %1 -R -log %1.log || exit /b 1
findstr /C:"ALL TESTS PASSED" %1.log >nul || exit /b 1
exit /b 0

rem --- GHDL -------------------------------------------------------------------------
:ghdl
echo Simulator: GHDL
echo Work folder: %W%
cd /d "%W%"
ghdl -a --std=08 %SRC% || goto fail
call :ghdl_tb tb_ADC_DAC || goto fail
echo tb_Tone_Recognition simulates about 7 s of signals - this takes a few seconds...
call :ghdl_tb tb_Tone_Recognition || goto fail
goto pass

:ghdl_tb
ghdl --elab-run --std=08 %1 > %1.log 2>&1
type %1.log
findstr /C:"ALL TESTS PASSED" %1.log >nul || exit /b 1
exit /b 0

rem --- result -----------------------------------------------------------------------
:pass
echo.
echo *** All testbenches passed
set RC=0
goto done

:fail
echo.
echo *** FAILED - see the messages above
set RC=1

:done
rem keep the window open when started by double-click
echo %cmdcmdline% | find /i "%~nx0" >nul && pause
exit /b %RC%
