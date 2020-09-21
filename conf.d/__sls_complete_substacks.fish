function __sls_complete_substacks
  find ./*/ -name serverless.yml | awk '{ gsub("/serverless.yml", ""); gsub("^./", ""); print }'
end
