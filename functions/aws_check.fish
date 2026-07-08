function aws_check -d 'check the AWS session for a profile (default $AWS_PROFILE); log in if expired'
    _ts_ensure_session $argv[1]
end
