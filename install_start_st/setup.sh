#!/bin/bash
# Check if Python 3 is installed
if ! command -v python3 &> /dev/null
then
    echo "Python 3 is not installed. Please install Python 3 using Homebrew: brew install python"
    exit 1
fi

# Check if Python 3 is in PATH
if ! command -v python3 &> /dev/null
then
    echo "Python 3 is not in PATH. Adding Python 3 to PATH."
    echo 'export PATH="/usr/local/opt/python/libexec/bin:$PATH"' >> ~/.bash_profile
    source ~/.bash_profile
    echo "Please restart your terminal for the changes to take effect."
    exit 1
else
    echo "Python 3 is already in PATH."
fi

# Create virtual environment
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Create a start script
echo "#!/bin/bash" > start_app.sh
echo "source venv/bin/activate" >> start_app.sh
echo "streamlit run app.py" >> start_app.sh
chmod +x start_app.sh

echo "Setup complete. Run ./start_app.sh to start the Streamlit app."