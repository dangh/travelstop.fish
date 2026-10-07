function logs -d "watch lambda function logs"
    if test -f serverless.yml
        logs_sls $argv
    else
        logs_awscli $argv
    end
end
