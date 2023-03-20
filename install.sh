#!/bin/bash

# Define color codes
YELLOW='\033[1;33m'
GREEN='\033[1;32m'

# Check if script requires sudo permissions
if [ "$EUID" -eq 0 ]; then
  echo "Please don't run this script with sudo or as root."
  exit 1
fi

# Ask the user for the OpenAI API Key
echo "Please enter your OpenAI API Key:"
read OPENAI_API_KEY

# Insert the API key into the second line of commitai.sh
sed -i '' "2s/.*/OPENAI_API_KEY=$OPENAI_API_KEY/" commitai.sh

# Copy the file to the appropriate location based on OS
if [[ "$OSTYPE" == "darwin"* ]]; then
  mkdir -p /usr/local/bin
  if [ -w /usr/local/bin ]; then
    cp commitai.sh /usr/local/bin/commitai
    chmod +x /usr/local/bin/commitai
    echo -e "${GREEN} Successfully installed commitai!"
  else
    echo -e "${YELLOW} Please execute the following commands:"
    echo -e "${GREEN} sudo cp commitai.sh /usr/local/bin/commitai"
    echo -e "${GREEN} sudo chmod +x /usr/local/bin/commitai"
  fi
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  mkdir -p ~/.local/bin
  cp commitai.sh ~/.local/bin/commitai
  chmod +x ~/.local/bin/commitai

  echo "Please add the following line to your .bashrc or .zshrc file:"
  echo "export PATH=\$PATH:~/.local/bin"
else
  echo "This script is not compatible with your operating system."
  exit 1
fi
