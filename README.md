# serverless.fish

### Install

```sh
fisher install dangh/withd.fish
fisher install dangh/travelstop.fish
```

To show blank line between prompts

```sh
set -U ts_newline
```

To use environment variables:

```sh
set -U ts_env
# set proxy
set -a ts_env HTTPS_PROXY=http://localhost:8888
# disable serverless deprecation warnings
set -a ts_env SLS_DEPRECATION_DISABLE='*'
# change indentation to 4 spaces
set -a ts_env TAB_CHAR='    '
# or use a dot as indent guide
set -a ts_ENV TAB_CHAR='﹒  '
```

To update AWS config automatically when copied to clipboard:

```sh
fisher install dangh/pbmonitor.fish
set -U ts_aws_creds account_id,stage,region account_id_2,stage_2,region_2
```

To apply default arguments to commands:

```sh
set -U ts_default_argv_push --conceal --verbose
set -U ts_default_argv_logs --tail --startTime=2m
set -U ts_default_argv_invoke --type=Event
```

Useful abbreviations:

```sh
abbr -aU p push
abbr -aU l logs
abbr -aU i invoke
abbr -aU b build_libs
abbr -aU r rename_libs
```
