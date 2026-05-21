@echo off
setlocal
set PYTHON_EXE=%LOCALAPPDATA%\Python\pythoncore-3.14-64\python.exe
if not exist "%PYTHON_EXE%" set PYTHON_EXE=python
"%PYTHON_EXE%" "%~dp0tools\hss_rpa_bot.py" --calibrate
endlocal

