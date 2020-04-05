function build_libs -a force -d "rebuild libs module"
  set -l project_dir (git rev-parse --show-toplevel)
  set -l nodejs_dir "$project_dir/modules/libs/nodejs"

  # repackaging libs
  echo (set_color -b green)(set_color black)repackaging libs(set_color normal)
  npm run --prefix "$nodejs_dir" --silent build

  # invalidate libs and package-lock
  set -l libs (awk '/\"build-/ {print $1}' package.json | awk -F 'build-' '{print $2}' | awk -F '"' '{print $1}')
  rm -r "$nodejs_dir/package-lock.json" 2>/dev/null
  for lib in $libs
    echo (set_color red)invalidate $lib(set_color normal)
    rm -r "$nodejs_dir/node_modules/$lib" 2>/dev/null
  end
  echo (set_color red)invalidate package-lock.json(set_color normal)

  # rebuild package-lock and reinstall libs
  echo (set_color -b green)(set_color black)reinstall packages(set_color normal)
  npm i --prefix "$nodejs_dir"
end
