function build_libs --description "rebuild libs module"
  set --local  project_dir (git rev-parse --show-toplevel)
  set --local  nodejs_dir "$project_dir/modules/libs/nodejs"

  # repack libs
  echo (set_color --background green)(set_color black)repack libs(set_color normal)
  npm run --prefix "$nodejs_dir" --silent build

  # invalidate package-lock
  rm -r "$nodejs_dir/package-lock.json" 2>/dev/null

  # invalidate libs
  set --local libs (awk '/\"build-/ {print $1}' package.json | awk -F 'build-' '{print $2}' | awk -F '"' '{print $1}')
  for lib in $libs
    echo (set_color red)invalidate $lib(set_color normal)
    rm -r "$nodejs_dir/node_modules/$lib" 2>/dev/null
  end
  echo (set_color red)invalidate package-lock.json(set_color normal)

  # rebuild package-lock and reinstall libs
  echo (set_color --background green)(set_color black)reinstall packages(set_color normal)
  npm install --prefix "$nodejs_dir" --production --no-shrinkwrap
  npm install --prefix "$nodejs_dir" --production --no-shrinkwrap --package-lock-only
end
