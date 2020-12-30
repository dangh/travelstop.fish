function __sls_complete_functions
  if test -e ./serverless.yml
    set --local inside_functions 0
    while read --local line
      if string match --quiet 'functions:' $line
        set inside_functions 1
      else if test $inside_functions -eq 1
        string match --quiet --regex '^#' $line && continue
        string match --quiet --regex '^\w' $line && break
        string match --quiet --regex '^  \w+' $line \
          && string match --regex '\w+' $line
      end
    end < ./serverless.yml
  end
end
