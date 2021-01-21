# serverless.fish

### Install

```sh
fisher install dangh/withd.fish
fisher install dangh/travelstop.fish
```

To update AWS config automatically when copied to clipboard:

```sh
fisher install dangh/pbmonitor.fish
set -U tsp_aws_config account_id,stage,region account_id_2,stage_2,region_2
```

To apply default arguments to commands:

```sh
set -U ts_default_argv_push --conceal --verbose
set -U ts_default_argv_logs --tail --startTime=2m
set -U ts_default_argv_invoke --type=Event
```
