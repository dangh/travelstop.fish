function add_account -d "add new AWS account from clipboard"
  pbpaste | read -l -z creds
  if string match -q -r '^\[[[:alnum:]_]+\](\naws_[[:alpha:]_]+=.*)+$' "$creds"
    printf $creds | read -l -L profile aws_access_key_id aws_secret_access_key aws_session_token
    string match -r '^\[([[:digit:]]+)_([[:alpha:]]+)\]' $profile | read -l -L _0 account_id role
    set -l account_exist 0
    for stage_config in $ts_aws_creds
      echo $stage_config | read -l -d , _account_id stage region
      if test "$account_id" = "$_account_id"
        set account_exist 1
        break
      end
    end
    if test $account_exist -eq 0
      set -l stage
      set -l region
      set -l supported_stages dev dev-in test stage prod
      set -l supported_regions sg in
      while not contains "$stage" $supported_stages
        read -P (_ts_log "Account STAGE: ( "(string join " | " $supported_stages)" ) ") stage
      end
      while not contains "$region" $supported_regions
        read -P (_ts_log "Account REGION: ( "(string join " | " $supported_regions)" ) ") region
      end
      set stage (string upper -- $stage 2>/dev/null)
      switch $region
      case sg
        set region ap-southeast-1
      case in
        set region ap-south-1
      end
      if test -n "$account_id" -a -n "$stage" -a -n "$region"
        set -U -a ts_aws_creds "$account_id,$stage,$region"
        _ts_aws_creds $creds
      end
    end
  end
end
