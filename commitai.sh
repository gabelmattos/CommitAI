#!/bin/bash

set -e

# Color codes
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Check if OPENAI_API_KEY is set
check_openai_api_key() {
  if [ -z "$OPENAI_API_KEY" ]; then
    echo -e "${RED} \nError: OPENAI_API_KEY is not set"
    exit 1
  fi
}

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
  tput civis

  while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
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
    spinner_display $spinstr
    spinstr="${spinstr:1}${spinstr:0:1}"  # Rotate spinstr
    # Check if the spinner has exceeded the timeout
    if [ $SECONDS -ge $end_time ]; then
      spinner_cleanup
      printf "${RED} \nError: OpenAI response timed out, check service status at https://status.openai.com/ \n"
      exit 1
    fi
  done
  spinner_cleanup
}

spinner_display() {
  local spinstr=$1
  printf " [%c]  %s%s  " "$spinstr" "${msgs[$msg_index]}" "$dots"
  sleep $delay
  printf "\r"
}

spinner_cleanup() {
  # Clear the current line
  printf "\r\033[K"
  # Show the cursor
  tput cnorm
}

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo "Options:"
  echo "  -h, --help            Show this help message and exit"
  echo "  -s, --semantic        Semantic commit message includes a type identifier at the beginning of each modification"
  echo "  -p, --prompt          Use a custom prompt provided by the user"
}

# Parse command-line arguments
parse_arguments() {
  if [ "$#" -gt 2 ]; then
    echo -e "${RED}\nError, you can only enter one argument at a time"
    exit 1
  fi

  while [ "$#" -gt 0 ]; do
    case $1 in
      -h|--help)
        if [ "$#" -eq 1 ]; then
          usage
          exit 0
        else
          echo -e "${RED}\nError, you can only enter one argument at a time"
          exit 1
        fi
        ;;
      -s|--semantic)
        if [ "$#" -eq 1 ]; then
          SEMANTIC=true
          shift
        else
          echo -e "${RED}\nError, you can only enter one argument at a time"
          exit 1
        fi
        ;;
      -p|--prompt)
        if [ "$#" -eq 2 ]; then
          CUSTOM_PROMPT=true
          shift  # Shift to the next argument, which is the prompt message
          USER_PROMPT="$1"  # Assign the prompt message to the USER_PROMPT variable
          shift
        else
          echo -e "${RED}\nError, you can only enter one argument at a time"
          exit 1
        fi
        ;;
      *)
        shift
        ;;
    esac
  done
}

# Check if the current directory is a git directory
check_git_directory() {
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${RED}\nThe current directory is not a git directory"
    exit 1
  fi
}

# Check if there are staged changes
check_staged_changes() {
  if [ -z "$DIFF" ] || [ "$DIFF" = $'\n' ]; then
    echo -e "${RED}\nError: There are no changes staged, please add by using git add . or git add <file>."
    exit 1
  fi
}

# Check if the diff has at most 4,000 tokens
check_token_count() {
  if [ "$SEMANTIC" = true ]; then
    MAX_TOKEN_COUNT=3200
  elif [ "$CUSTOM_PROMPT" = true ]; then
    MAX_TOKEN_COUNT=3500
  else
    MAX_TOKEN_COUNT=4000
  fi

  if [ $TOKEN_COUNT -gt $MAX_TOKEN_COUNT ]; then
    echo -e "${RED}\nError: diff too long to generate a commit message, please split the diff into smaller chunks."
    exit 1
  fi
}

# Generate commit messages
generate_commit_message() {
  # Define the Prompts
  SYSTEM_PROMPT="As a senior developer on your team, your responsibility includes \
  generating commit messages for your team members. For each file modified in the diff, \
  you need to add a type identifier at the beginning of the commit message, and the format \
  pattern should always be <type>(scope): <subject>. Please note that only one commit message \
  per file is allowed. \
  The following are the allowed <type> values and their corresponding meanings: \
  feat: a new feature for the user \
  fix: a bug fix for the user \
  perf: a performance improvement \
  docs: changes to documentation \
  style: formatting, missing semicolons, etc. \
  refactor: refactoring production code \
  test: adding missing tests, refactoring tests \
  build: updating build configuration, development tools, etc. \
  Make sure to follow this format pattern for all commit messages to ensure consistency and readability of the codebase."

  PROMPT="Generate commit message for the following diff, \
  for comments, only mention that new commends are added, and indicate \
  the nature of each file change in a concise short commit message: \n\n$DIFF\n\n"

  if [ "$SEMANTIC" = true ]; then
    MESSAGES=$(jq -n \
    --arg system_prompt "$SYSTEM_PROMPT" \
    --arg prompt "$PROMPT" \
    '[{role: "system", content: $system_prompt}, {role: "user", content: $prompt}]')
  elif [ "$CUSTOM_PROMPT" = true ]; then
    USER_PROMPT="$USER_PROMPT \n\n$DIFF\n\n"
    MESSAGES=$(jq -n \
    --arg prompt "$USER_PROMPT" \
    '[{role: "user", content: $prompt}]')
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
      echo -e "${RED} \nError: curl command failed"
      exit 1
    fi
    COMMIT_MESSAGE=$(echo "$output" | jq -r '.choices[0].message.content')
    # Check if commit message is null as well
    if [ -z "$COMMIT_MESSAGE" -o "$COMMIT_MESSAGE" = null ]; then
      echo -e "${RED} \nError: empty COMMIT_MESSAGE not found in response body"
      echo -e "${RED} \nResponse body: $output"
      sleep 1
      exit 1
    fi
  done
}

# Escape any double quotes in the commit message
escape_commit_message() {
  COMMIT_MESSAGE=$(echo "$COMMIT_MESSAGE" | sed -e 's/"/\"/g')
}

# Confirm and edit commit message
confirm_edit_commit_message() {
  while true; do
    echo -e "${YELLOW}\nHere is the commit message generated:\n${GREEN}  $COMMIT_MESSAGE${YELLOW}\n"
    echo "Press ENTER to accept as is, 'e' to edit, or 'c' to cancel"
    read -r -n1 -s KEY
    case $KEY in
      e)
        echo -e "\nPlease enter your commit message instead:"
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
}

# Commit and push the changes
commit_and_push() {
  echo -e "${NC} \nAdding the commit message...\n"
  git commit -m "$COMMIT_MESSAGE"
}

main() {
  parse_arguments "$@"
  check_openai_api_key
  check_git_directory
  DIFF=$(git diff --staged)
  check_staged_changes
  TOKEN_COUNT=$(($(echo -n "$DIFF" | wc -c) / 4))
  check_token_count
  generate_commit_message
  escape_commit_message
  confirm_edit_commit_message
  commit_and_push
}

main "$@"
