function bump_version
    argparse v/version= r/release= t/ts= -- $argv || return 1

    set v "$_flag_version"
    set release "$_flag_release"
    set ts "$_flag_ts"
    set msg "$argv"

    if test -z "$ts"
        string match -qri 'ts-(?<ts>\d+)' -- (git branch --show-current)
    end
    if test -z "$ts"
        echo task number is required
        return 1
    end

    sed '/^\s*$/q' CHANGELOG.md | read -z LAST_CHANGE
    string match -qr '# (?<last_version>\d+\.\d+\.\d+) \(Release: \[(?<last_release>\d+\.\d+(\.\d+)?)\]' -- $LAST_CHANGE
    string match -qri -- "- \[TS-$ts\]\(https://notion.so/TS-$ts\): (?<last_message>.*)" $LAST_CHANGE

    if test -z "$msg"
        set msg "$last_message"
    end
    if test -z "$msg"
        echo message is required
        return 1
    end

    if test -z "$last_message"
        # task not found in changelog
        # default to the next release
        if test -z "$release"
            git tag | grep -E '^\d+\.\d+(\.\d+)?$' | sort -V | tail -1 | read current_release
            string match -qr '(?<r_major>\d+)\.(?<r_minor>\d+)(\.(?<r_patch>\d+))?$' -- $current_release
            set r_minor (math $r_minor + 1)
            set release "$r_major.$r_minor"
        end
        # bump minor version by default
        if test -z "$v"
            string match -qr '(?<v_major>\d+)\.(?<v_minor>\d+)\.(?<v_patch>\d+)' -- $last_version
            set v_minor (math $v_minor + 1)
            set v "$v_major.$v_minor.0"
        end
    end

    if test -n "$v"
        if test "$v" != "$last_version"
            for d in . nodejs
                if test -f $d/package.json
                    fish -P -c "
                        cd $d
                        npm version --allow-same-version $v
                        test -f package-lock.json && npm i --package-lock-only
                    "
                end
            end
        end
    else
        set v "$last_version"
    end

    if test "$release" != "$last_release"
        set changelog "# $v (Release: [$release](https://github.com/WhiteLabs/Travelstop/releases/tag/$release))\n- [TS-$ts](https://notion.so/TS-$ts): $msg\n\n"
        sed -i '' "1s;^;$changelog;" CHANGELOG.md
    else
        # TODO
    end
end
