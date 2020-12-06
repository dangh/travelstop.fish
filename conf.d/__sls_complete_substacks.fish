function __sls_complete_substacks
  find . -name serverless.yml -maxdepth 2 -mindepth 2 | awk '{ gsub("/serverless.yml", ""); gsub("^./", ""); print }'
end
