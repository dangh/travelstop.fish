# travelstop.fish

## Installation

```sh
brew install jq
fisher install \
  dangh/ansi-escape.fish \
  dangh/travelstop.fish
```

## Usage

### To use environment variables:

```sh
set -U ts_env
# set proxy
set -a ts_env HTTPS_PROXY=http://localhost:8888
# disable serverless deprecation warnings
set -a ts_env SLS_DEPRECATION_DISABLE='*'
```

### To apply default arguments to commands:

```sh
set -U ts_default_argv_push --conceal --verbose
set -U ts_default_argv_logs --tail --startTime=2m
set -U ts_default_argv_invoke --type=Event
```

### To push notification after deploy with [Pushover](https://pushover.net)

```
set -U PUSHOVER_APP_TOKEN <app_token>
set -U PUSHOVER_USER_KEY <user_key>
```

### Logs formatting

To change default style, use environment variables prefixed with `ts_` and set the value follow [tmux styles](http://man.openbsd.org/OpenBSD-current/man1/tmux.1#STYLES). For example, to make JSON keys bold and green:

```sh
set -Ux ts_json_key_style bold,fg=green
```

To show some indicator text before each request:

```sh
# show 20 blank lines
set -Ux ts_blank_page_height 20

# show random fortune cookie in pride
set -Ux ts_blank_page_cmd 'echo; fortune -s | cowsay -f $(cowsay -l | tail -n +2 | tr  " "  "\n" | sort -R | head -n 1) | lolcat; echo;'
```

List of supported variables:

| Key                         | Default value     | Description                                                                         |
| ---                         | ---               | ---                                                                                 |
| `ts_enable_abbr`            | true              | Enable default abbreviations                                                        |
| `ts_npm_install_options`    |                   | Additional options for `npm install` command                                        |
| `ts_meta_stage_style`       | `fg=blue`         |                                                                                     |
| `ts_meta_timestamp_style`   | `fg=blue`         |                                                                                     |
| `ts_meta_source_file_style` | `fg=magenta`      |                                                                                     |
| `ts_meta_source_line_style` | `fg=magenta,bold` |                                                                                     |
| `ts_meta_method_style`      | `fg=cyan`         |                                                                                     |
| `ts_meta_log_level_style`   | `fg=blue`         |                                                                                     |
| `ts_meta_style`             | `fg=blue,dim`     |                                                                                     |
| `ts_json_key_style`         | `fg=magenta`      |                                                                                     |
| `ts_json_string_style`      |                   |                                                                                     |
| `ts_json_boolean_style`     | `fg=green`        |                                                                                     |
| `ts_json_number_style`      | `fg=green`        |                                                                                     |
| `ts_json_null_style`        | `bold`            |                                                                                     |
| `ts_json_undefined_style`   | `dim`             |                                                                                     |
| `ts_json_date_style`        |                   |                                                                                     |
| `ts_json_uuid_style`        | `fg=yellow`       |                                                                                     |
| `ts_json_colon_style`       | `dim,bold`        |                                                                                     |
| `ts_json_quote_style`       | `dim`             |                                                                                     |
| `ts_json_bracket_style`     | `dim`             |                                                                                     |
| `ts_json_comma_style`       | `dim`             |                                                                                     |
| `ts_uuid_style`             | `yellow`          |                                                                                     |
| `ts_indent_guide_style`     | `reverse`         |                                                                                     |
| `ts_indent_size`            | 4                 | Size of indent in JSON                                                              |
| `ts_inline_simple_object`   | 1                 | Simple JSON object will be print in single line                                     |
| `ts_blank_page_cmd`         |                   | Command to print text before each request                                           |
| `ts_blank_page`             |                   | Text to show before each request if `ts_blank_page_cmd` is not defined              |
| `ts_blank_page_height`      |                   | Number of blank lines to show before each request if `ts_blank_page` is not defined |
| `ts_blank_page_style`       |                   | Style of blank lines to show before each request if `ts_blank_page` is not defined  |

### Default abbreviations:

```sh
abbr -a -- c changes
abbr -a -- p push
abbr -a -- l logs
abbr -a -- i invoke
abbr -a -- b build_libs
abbr -a -- r rename_modules
abbr -a -- v bump_version
abbr -a -- l0 'logs --startTime=(date -u +%Y%m%dT%H%M%S)'
abbr -a -- l5 'logs --startTime=5m'
abbr -a -- l10 'logs --startTime=10m'
abbr -a -- l15 'logs --startTime=15m'
abbr -a -- l30 'logs --startTime=30m'
```
### Random rainbow cowsay fortune before each request log:

```sh
brew install cowsay fortune lolcat
set -Ux ts_blank_page_cmd fortune \| cowsay -f \$\( ls /opt/homebrew/share/cows/*.cow \| sort -R \| head -1 \) \| lolcat -F 0.01
```

### To open daily report function in Firefox container:

```sh
# we need ast-grep to grep error message from js file
brew install ast-grep

# this is the root dir of the project
set -U ts_master_dir <path_to_project_dir>
```
