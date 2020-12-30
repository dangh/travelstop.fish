function __sls_complete_substacks
  find . -name serverless.yml -maxdepth 2 -mindepth 2 | string replace --regex '^\./(.*)/serverless\.yml$' '$1'
end
