# travelstop.fish

## Commands

| Command                     | Abbr | Description                                                          |
| ---                         | ---  | ---                                                                  |
| `changes`                   | `c`  | Print list of changed stacks/modules in current branch              |
| `push`                      | `p`  | Deploy a CloudFormation stack / lambda function                     |
| `push_changes`              | `pc` | Deploy all changed stacks/modules in current branch                 |
| `logs`                      | `l`  | Watch lambda function logs                                           |
| `invoke`                    | `i`  | Invoke a lambda function                                            |
| `build_libs`                | `b`  | Rebuild the `libs` module                                           |
| `rename_modules`            | `r`  | Add/remove a suffix on module names                                 |
| `bump_version`              | `v`  | Bump service version (infers ticket from branch name)               |
| `sls`                       |      | Wrap `sls` to supply stage/profile/region implicitly                |
| `pack`                      |      | Package a serverless service                                        |
| `daily_report`              |      | Open daily report for a lambda in a Firefox container               |
| `download_ddb_table`        |      | Scan a DynamoDB table to `<table>.json`                             |
| `download_ses_suppression`  |      | Download the SES suppression list as JSON                           |
| `prune_functions_versions`  |      | Delete old lambda function versions (keep last N, default 10)       |
| `prune_layer_versions`      |      | Delete old lambda layer versions (keep last N)                      |
| `aws_check`                 |      | Check the AWS session for a profile (default `$AWS_PROFILE`); log in if expired |

## Installation

Install `jq`:
- macOS: `brew install jq`
- Debian/Ubuntu: `sudo apt install jq`
- Arch: `sudo pacman -S jq`
- Other: see https://jqlang.github.io/jq/download/

Then:

```sh
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

For dynamic values, define a `ts_env` function (one `KEY=value` pair per line).
If it exists it is used instead of the variable, so you can compute pairs with
custom logic, e.g. a proxy that depends on the current AWS profile:

```fish
function ts_env
    switch "$AWS_PROFILE"
        case 'acme@prod'
            echo HTTPS_PROXY=http://localhost:9999
        case '*'
            echo HTTPS_PROXY=http://localhost:8888
    end
end
```

### To apply default arguments to commands:

```sh
set -U ts_default_argv_push --conceal --verbose
set -U ts_default_argv_logs --tail --startTime=2m
set -U ts_default_argv_invoke --type=Event
```

### Deploying a whole tree

`push -a/--all` expands each target (the current directory when you pass none)
to every service below it, so it works from a plain parent directory that holds
services but is not a service itself:

```sh
cd services/booking   # no serverless.yml here, only in its subdirectories
push -a               # deploys every service under services/booking
push -a hotels ops    # same, for two given directories/stacks
```

Only when the directory holds no service at all does `push -a` walk up to the
nearest enclosing service (and then deploys that service plus its subservices).

### Parallel deploys

`push` deploys independent targets at the same time, 4 at once by default
(`-j/--jobs N`). Targets are grouped into dependency tiers that run one after
the other: modules (layers) → `*-resources` stacks → `*authorizer*` stacks →
other services, a parent stack before its subservices → `*monitoring*` stacks →
functions (functions of one service stay sequential, they share its
`.serverless/` dir). `-j 1` gives the old strictly sequential run in list order
(`push -a` lists authorizers before other services too; this also honors the
order you set in the `-i` editor):

```sh
push -j 1 -a hotels        # one at a time
set -U ts_default_argv_push -j 8
```

Each target's output goes to its own log file under
`$XDG_RUNTIME_DIR/ts_push/<run>/` (`/tmp/ts_push/` when the runtime dir is not
set); `ts_push/latest` points at the current run. A single-target tier still
prints live to the terminal. When a target in a parallel tier fails, `push`
shows the tail of its log and asks `[r]etry / [s]kip / [a]bort` once the tier
is done; retried targets run as the next tier.

Parallel targets run in child `fish` processes that load your normal config, so
`ts_npm_install_options`, `ts_env` and friends must be universal variables or
defined in `config.fish`/`conf.d` to reach them.

### To push notification after deploy with [Pushover](https://pushover.net)

```
set -U PUSHOVER_APP_TOKEN <app_token>
set -U PUSHOVER_USER_KEY <user_key>
```

### Reading logs

`logs` automatically selects its backend based on the current directory:
- If `./serverless.yml` exists, it calls `logs_sls` (the original Serverless implementation).
- Otherwise, it calls `logs_awscli` (AWS CLI v2, `aws logs tail`).

Call `logs_sls` or `logs_awscli` directly to choose a backend explicitly.
Arguments are forwarded unchanged; both use `ts_default_argv_logs` and retain
`-s` / `--stage` overrides. Only the current directory is checked, not ancestors.

For the AWS CLI backend, install and configure
[AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
with CloudWatch Logs read permissions.

From a service directory:

```fish
logs myFunction                         # last 2 minutes
logs myFunction --tail --startTime 30m  # follow new events
logs myFunction -s prod --filter ERROR
logs --log-group /aws/lambda/custom-name --tail
```

With `logs_awscli`, short function names resolve to `/aws/lambda/<service>-<stage>-<function>`
from the current directory, with no Serverless files or helpers required.
The directory named `services` is the boundary, wherever it appears below the
Git root. Only path components after `services` are joined with hyphens; parent components are
singularized (`ies` → `y`, trailing `s` removed except `ss`), while the final
component is unchanged. This is a simple naming convention, not a general
English inflector.

For example, from `<git-root>/services/users/groups`, `logs create` with stage
`dev` reads `/aws/lambda/user-groups-dev-create`. From
`<git-root>/backend/services/users`, it reads `/aws/lambda/users-dev-create`.

Stage defaults to the lowercased part of the selected AWS profile after `@`;
`--stage` overrides it. Profile and region default to `AWS_PROFILE` and
`AWS_REGION`, with `--aws-profile` and `--region` overrides.
Use `--log-group` for custom names or outside a service directory/Git repository.

`--startTime` accepts AWS CLI relative times (`5m`, `1h`) or ISO 8601 timestamps;
compact UTC timestamps from `l0` and `invoke` are converted automatically.
`ts_env`, `ts_default_argv_logs`, `parse_logs`, and log styling remain supported.
In `logs_awscli`, `ts_env` applies to the session check, AWS CLI, optional
`parse_logs`, and AWK formatter. A `ts_env` function takes precedence over the
variable; these environment overrides stay local to the command.
AWS output uses `--format short --color off`; its timestamp prefix is stripped
before parsing and styling, leaving the original log messages.
In `logs_awscli`, `--interval` is unsupported (AWS CLI manages polling). Legacy `--app`,
`--org`, and `--config` are accepted for compatibility with `invoke` but have no effect.
Deployment and invocation still use Serverless.

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
| `ts_push_rename_modules`    | true              | Rename modules (branch suffix) during `push`. Set `0`/`false`/`no`/`off` to disable  |
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
abbr -a -- pc push_changes
abbr -a -- l logs
abbr -a -- i invoke
abbr -a -- b build_libs
abbr -a -- r rename_modules
abbr -a -- v bump_version
```

Plus a regex abbreviation: any `l<N>` expands to `logs` over the last `<N>` minutes
(`l5` → `logs --startTime=5m`, `l30` → `logs --startTime=30m`). `l0` starts from now
(`logs --startTime=(date -u +%Y%m%dT%H%M%S)`).

### AWS profile aliases (when [`assume`](https://docs.commonfate.io/granted) is installed):

```sh
alias d  'assume DEV'
alias di 'assume DEV-IN'
alias t  'assume TEST'
alias s  'assume STAGE'
# `a [profile]` assumes profile (default: current) with `-s cloudwatch`
```

AWS-touching commands (`push`, `push_changes`, `invoke`, `logs`, `pack`, `sls`,
`download_ddb_table`, `download_ses_suppression`, `prune_layer_versions`,
`prune_functions_versions`) run a session pre-flight (`_ts_ensure_session`)
before hitting AWS. An expired SSO session surfaces the login URL up-front at a
clean prompt (not buried mid-command); complete it and the command continues. If
login is skipped it prompts to retry, so you can re-auth inline instead of
re-running the whole command. Run `aws_check` any time to check / refresh the
session manually.
### Random rainbow cowsay fortune before each request log (macOS — Homebrew paths):

```sh
brew install cowsay fortune lolcat
set -Ux ts_blank_page_cmd fortune \| cowsay -f \$\( ls /opt/homebrew/share/cows/*.cow \| sort -R \| head -1 \) \| lolcat -F 0.01
```

On Linux, the cow files live elsewhere depending on your distro (e.g. `/usr/share/cowsay/cows` on Debian/Ubuntu, `/usr/share/cows` on Arch). Adjust the path in `ls ...` accordingly.

### To open daily report function in Firefox container:

```sh
# we need ast-grep to grep error message from js file
brew install ast-grep

# this is the root dir of the project
set -U ts_master_dir <path_to_project_dir>
```
