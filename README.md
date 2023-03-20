# CommitAI

CommitAI is a tool designed to generate concise and engaging commit messages for your staged git changes using OpenAI's GPT-3.5 Turbo. It also provides options for semantic commit messages and custom prompts.

## Features

- ⚡️ Written in pure bash, which means it's fast and lightweight
- 🚗 Generate commit messages based on staged git changes
- 🎤 Supports semantic commit messages
- 🧩 Custom prompt support
- 🤼‍♂️ Interactive commit message confirmation and editing

## Installation

To install CommitAI, simply run the following command:

```bash
curl https://raw.githubusercontent.com/gabedemattos/CommitAI/main/commitai.sh -o commitai.sh && bash <(curl -s https://raw.githubusercontent.com/gabedemattos/CommitAI/main/install.sh)
```

## Usage

```bash
commitai [options]
```

### Options

| Option | Description |
| ------ | ----------- |
| `-h or --help` | Show help |
| `-s or --semantic` | Generate a semantic commit message |
| `-cm or --custom-message` | Use a custom prompt |

## Examples

### Generate a commit message based on staged git changes

```bash
commitai
```

### Generate a semantic commit message

```bash
commitai -s
```

### Generate a commit message using a custom prompt

```bash
commitai -cm "Generate a commit message with a funny message"
```

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## Requirements

- [OpenAI API Key](https://platform.openai.com/account/api-keys)
- [OpenAI GPT-3.5 Turbo](https://beta.openai.com/pricing)
- [Git](https://git-scm.com/downloads)
- [Bash](https://www.gnu.org/software/bash/)
- [Curl](https://curl.se/download.html)
- [jq](https://stedolan.github.io/jq/download/)

## License

[MIT](https://choosealicense.com/licenses/mit/)