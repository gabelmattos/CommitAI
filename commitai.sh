#!/bin/bash

YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
NC='\033[0m'

# Spinner function
spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='|/-\'
  local dotcount=0
  local dots=""
  local msgs=("Dusting off the propellers" "Warming up the hamsters" "Unleashing the penguins" "Juggling the electrons")
  local msg_delay=2  # Delay between messages in seconds
  local msg_time=$((SECONDS + msg_delay))  # Time to display next message
  local msg_index=0  # Index of the current message
  local timeout=30  # Timeout in seconds
  local end_time=$((SECONDS + timeout))  # Time to end spinner
  # Hide the cursor
  printf "\e[?25l"
  while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
    local temp=${spinstr#?}
    # Check if it's time to display the next message
    if [ $SECONDS -ge $msg_time ]; then
      msg_index=$((msg_index + 1))
      if [ $msg_index -eq ${#msgs[@]} ]; then
        msg_index=0
      fi
      msg_time=$((SECONDS + msg_delay))
    fi
    dotcount=$((dotcount + 1))
    dots+="."
    if [ $dotcount -gt 3 ]; then
      dotcount=0
      dots=""
    fi
    # Print the loader animation
    printf " [%c]  %s%s  " "$spinstr" "${msgs[$msg_index]}" "$dots"
    local spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    # Move the cursor back to the start of the line
    printf "\r"
    # Print the loader animation again, followed by spaces to overwrite the previous message
    printf " [%c]  %s%s  %*s" "$spinstr" "${msgs[$msg_index]}" "$dots" "${#msgs[$msg_index]}"
    # Move the cursor back to the start of the line
    printf "\r"
    # Check if the spinner has exceeded the timeout
    if [ $SECONDS -ge $end_time ]; then
      printf " \b\b\b\b"
        # Clear the current line
      printf "\r\033[K"
      printf "${RED}error: OpenAI response timed out, check service status at https://status.openai.com/ \n"
      # Show the cursor
      printf "\e[?25h"
      # rm response.json
      exit 1
    fi
  done
  printf " \b\b\b\b"
  # Clear the current line
  printf "\r\033[K"
  # Show the cursor
  printf "\e[?25h"
}

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo "Options:"
  echo "  -h, --help            Show this help message and exit"
  echo "  -s, --semantic        Semantic commit message includes a type identifier at the beginning of each modification"
  echo "  -p, --prompt Use a custom prompt provided by the user"
}

# Parse command-line arguments
SEMANTIC=false
CUSTOM_PROMPT=false
USER_PROMPT=""
for arg in "$@"
do
  case $arg in
    -h|--help)
      usage
      exit 0
      ;;
    -s|--semantic)
      SEMANTIC=true
      shift
      ;;
    -cm|--custom-prompt)
      CUSTOM_PROMPT=true
      echo "Enter your custom prompt:"
      read -r USER_PROMPT
      shift
      ;;
    *)
      shift
      ;;
  esac
done

# Check if the current directory is a git directory
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo -e "${RED}\nThe current directory is not a git directory"
  exit 1
fi

# Properly escape the DIFF variable
DIFF=$(git diff --staged)

if [ -z "$DIFF" ] || [ "$DIFF" = $'\n' ]; then
  echo -e "${RED} \nThere are no changes staged, please add by using git add . or git add <file>."
  exit 1
fi

# Calculate token count
TOKEN_COUNT=$(($(echo -n "$DIFF" | wc -c) / 4))

# Check if the diff has at most 4,000 tokens
if [ $TOKEN_COUNT -gt 4000 ]; then
  echo "error, diff too long"
  exit 1
fi

SYSTEM_PROMPT="You are a senior dev, \
you generate commit messages for your team members, \
each commit message includes a type identifier at the beginning of each file modified in the diff, \
you will ALWAYS and exclusively outoput ONLY the following format pattern: \<type>(file): <subject> \
ONLY show ONE commit message PER file, \
Allowed <type> values: \
feat: new feature for the user \
fix: bug fix for the user \
perf: performance improvement \
docs: changes to documentation \
style: formatting, missing semicolons, etc. \
refactor: refactoring production code \
test: adding missing tests, refactoring tests \
build: updating build configuration, development tools, etc."

PROMPT="Generate commit message following format pattern for the following diff, \
 for comments, only mention that new commends are added, and indicate \
 the nature of each file change in a concise short commit message: \n\n$DIFF\n\n"


if [ "$SEMANTIC" = true ]; then
  MESSAGES=$(jq -n \
    --arg system_prompt "$SYSTEM_PROMPT" \
    --arg prompt "$PROMPT" \
    '[{role: "system", content: $system_prompt}, {role: "user", content: $prompt}]')
else
  MESSAGES=$(jq -n \
    --arg prompt "$PROMPT" \
    '[{role: "user", content: $prompt}]')
fi

# Construct JSON payload using jq
PAYLOAD=$(jq -n \
  --arg diff "$DIFF" \
  --argjson messages "$MESSAGES" \
  '{ model: "gpt-3.5-turbo", messages: $messages }')

# Submit the diff to OpenAI API and capture the output in COMMIT_MESSAGE variable
COMMIT_MESSAGE=""
while [ -z "$COMMIT_MESSAGE" ]; do
  (spinner $$) &
  spinner_pid=$!
  output=$(curl -s https://api.openai.com/v1/chat/completions \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    --data "$PAYLOAD")
  kill "$spinner_pid"
  if [ $? -ne 0 ]; then
    echo "Error: curl command failed"
    exit 1
  fi
  COMMIT_MESSAGE=$(echo "$output" | jq -r '.choices[0].message.content')
  if [ -z "$COMMIT_MESSAGE" ] || ! echo "$output" | grep -q "$COMMIT_MESSAGE"; then
    echo "Error: empty COMMIT_MESSAGE or not found in response body"
    echo "Response body: $output"
    sleep 1
  fi
done

# Escape any double quotes in the commit message
COMMIT_MESSAGE=$(echo "$COMMIT_MESSAGE" | sed -e 's/"/\\"/g')

# Show the commit message and ask for confirmation
while true; do
  echo -e "${YELLOW}\nHere is the commit message generated:\n ${GREEN} $COMMIT_MESSAGE ${YELLOW}\n"
  echo "Press ENTER to accept as is, 'e' to edit, or 'c' to cancel"
  read -r -n1 -s KEY
  case $KEY in
    e)
      echo -e "\nPlease enter your edited commit message:"
      read -r COMMIT_MESSAGE
      ;;
    c)
      echo -e "${RED}\nCommit canceled by user"
      exit
      ;;
    *)
      break
      ;;
  esac
done

# Commit and push the changes
echo "${NC}Committing and pushing the changes..."
git commit -m "$COMMIT_MESSAGE" 