function __sls_complete_functions
  if test -e ./serverless.yml
    set --local inside_functions 0
    while read --local line
      if string match 'functions:' $line >/dev/null
        set inside_functions 1
      else if [ "$inside_functions" = "1" ]
        string match --regex '^#' $line >/dev/null; and continue
        string match --regex '^\w' $line >/dev/null; and break
        if string match --regex '^  \w+' $line >/dev/null
          string match --regex '\w+' $line
        end
      end
    end < ./serverless.yml
  end
end
