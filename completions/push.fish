function __sls_complete_functions
	if test -e serverless.yml
		cat serverless.yml \
			| sed -e '/#.*/d' -e '/^\s*$/d' \
			| awk '/^functions/{p=1;print;next} p&&/^(resources|package|provider|plugins|service|custom)/{p=0};p' \
			| grep -e '^  \w' \
			| sed -e 's/://' -e 's/  //'
	end
end

complete --no-files --command push --arguments "libs templates"
complete --no-files --command push --arguments "(__sls_complete_functions)"
