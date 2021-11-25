function add_account --description "add new AWS account from clipboard"
  pbpaste | read --null --local creds
  if string match --quiet --regex '^\[[[:alnum:]_]+\](\naws_[[:alpha:]_]+=.*)+$' "$creds"
    printf $creds | read --local --line profile aws_access_key_id aws_secret_access_key aws_session_token
    string match --regex '^\[([[:digit:]]+)_([[:alpha:]]+)\]' $profile | read --local --line _ account_id role
    set --local account_exist 0
    for stage_config in $ts_aws_creds
      echo $stage_config | read --delimiter=, --local _account_id stage region
      if test "$account_id" = "$_account_id"
        set account_exist 1
        break
      end
    end
    if test $account_exist -eq 0
      set --local stage
      set --local region
      set --local supported_stages dev dev-in test stage prod
      set --local supported_regions sg in
      while not contains "$stage" $supported_stages
        read --prompt-str (_ts_log "Account STAGE: ( "(string join " | " $supported_stages)" ) ") stage
      end
      while not contains "$region" $supported_regions
        read --prompt-str (_ts_log "Account REGION: ( "(string join " | " $supported_regions)" ) ") region
      end
      set stage (string upper -- $stage 2>/dev/null)
      switch $region
      case sg
        set region ap-southeast-1
      case in
        set region ap-south-1
      end
      if test -n "$account_id" -a -n "$stage" -a -n "$region"
        set --universal --append ts_aws_creds "$account_id,$stage,$region"
        _ts_aws_creds $creds
      end
    end
  end
end
