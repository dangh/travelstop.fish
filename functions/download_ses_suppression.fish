function download_ses_suppression
    set files
    set page 0
    set token
    while true
        set page (math $page + 1)
        set file (mktemp)
        set -a files $file
        set -l args
        test -n "$token" && set -a args --next-token $token
        aws sesv2 list-suppressed-destinations $args >$file
        set token (jq -r '.NextToken' $file)
        if test "$token" = null
            break
        end
    end
    jq -s '{ SuppressedDestinationSummaries: .[].SuppressedDestinationSummaries | sort_by(.LastUpdateTime) | reverse }' $files
    rm -f $files
end
