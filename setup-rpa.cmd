@echo off
setlocal
set PYTHON_EXE=%LOCALAPPDATA%\Python\pythoncore-3.14-64\python.exe
if not exist "%PYTHON_EXE%" set PYTHON_EXE=python
"%PYTHON_EXE%" -m pip install --user -r "%~dp0requirements.txt"
echo.
echo RPA setup complete. If there were no errors, run:
echo "%~dp0run-rpa.cmd"
endlocal

