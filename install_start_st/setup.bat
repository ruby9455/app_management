@echo off
REM Check if Python is installed
python --version
IF %ERRORLEVEL% NEQ 0 (
    echo Python is not installed. Please install Python from https://www.python.org/downloads/ and select add to PATH during installation.
    exit /b 1
)

REM Check if Python is in PATH
python --version
IF %ERRORLEVEL% NEQ 0 (
    echo Python is not in PATH. Adding Python to PATH.
    setx PATH "%PATH%;C:\Python39;C:\Python39\Scripts"
    echo Please restart your command prompt or computer for the changes to take effect.
    pause
    exit /b 1
) ELSE (
    echo Python is already in PATH.
)

REM Create virtual environment
python -m venv venv

REM Activate virtual environment
call venv\Scripts\activate

REM Install dependencies
pip install -r requirements.txt

REM Create a start script
echo @echo off > start_app.bat
echo call venv\Scripts\activate >> start_app.bat
echo streamlit run app.py >> start_app.bat

echo Setup complete. Run start_app.bat to start the Streamlit app.
pause