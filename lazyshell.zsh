#!/usr/bin/env zsh

__lzsh_get_distribution_name() {
  if [[ "$(uname)" == "Darwin" ]]; then
    echo "$(sw_vers -productName) $(sw_vers -productVersion)" 2>/dev/null
  else
    echo "$(cat /etc/*-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)"
  fi
}

__lzsh_get_os_prompt_injection() {
  local os=$(__lzsh_get_distribution_name)
  if [[ -n "$os" ]]; then
    echo " for $os"
  else
    echo ""
  fi
}

__lzsh_preflight_check() {
  if [ -z "$OPENAI_API_KEY" ]; then
    echo ""
    echo "Error: OPENAI_API_KEY is not set"
    echo "Get your API key from https://beta.openai.com/account/api-keys and then run:"
    echo "export OPENAI_API_KEY=<your API key>"
    zle reset-prompt
    return 1
  fi

  if ! command -v jq &> /dev/null; then
    echo ""
    echo "Error: jq is not installed"
    zle reset-prompt
    return 1
  fi

  if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
    echo ""
    echo "Error: curl or wget is not installed"
    zle reset-prompt
    return 1
  fi
}

choose_model() {
  local choices=("davinci" "curie" "babbage" "ada")
  local selected=$(echo $choices | tr ' ' '\n' | fzf)
  echo $selected
}

__lzsh_llm_api_call() {
  # calls the llm API, shows a nice spinner while it's running 
  # called without a subshell to stay in the widget context, returns the answer in $generated_text variable
  local intro="$1"
  local prompt="$2"
  local progress_text="$3"
  local model="$4"

  local response_file=$(mktemp)

  local escaped_prompt=$(echo "$prompt" | jq -R -s '.')
  local escaped_intro=$(echo "$intro" | jq -R -s '.')
  local data='{"model": "'"$model"'","prompt": '"$escaped_prompt"',"temperature": 0.7, "max_tokens": 256}'

  # Read the response from file
  # Todo: avoid using temp files
  set +m
  if command -v curl &> /dev/null; then
    { curl -s -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $OPENAI_API_KEY" -d "$data" https://api.openai.com/v1/completions > "$response_file" } &>/dev/null &
  else
    { wget -qO- --header="Content-Type: application/json" --header="Authorization: Bearer $OPENAI_API_KEY" --post-data="$data" https://api.openai.com/v1/completions > "$response_file" } &>/dev/null &
  fi
  local pid=$!

  # Display a spinner while the API request is running in the background
  local spinner=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "
