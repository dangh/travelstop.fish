function vpn-native
  set -l pidfile {$TMPDIR}travelstop-vpn.pid
  sudo pkill -9 -F $pidfile >/dev/null 2>&1
  if not test -f ~/.config/vpn/config
    echo Please put your VPN config in $HOME/.config/vpn/config
    return 1
  end
  function vpn-up -e openvpn-up -a payload
    pkill -9 -U (id -u) tinyproxy >/dev/null 2>&1
    echo $payload | read -l -d ' ' tun_mtu link_mtu ifconfig_local ifconfig_netmask script_context
    tinyproxy --port 8888 --bind $ifconfig_local --disable-via-header --log-level Connect --syslog On
    functions -e (status function)
    set -l notif_title 'VPN connected!'
    set -l notif_message 'Proxy: localhost:8888'
    functions -q fontface &&
      set notif_title (fontface math_monospace "$notif_title") &&
      set notif_message (fontface math_monospace "$notif_message")
    _ts_notify "$notif_title" "$notif_message"
  end
  openvpn --config ~/.config/vpn/config --askpass ~/.config/vpn/passwd --auth-nocache --daemon travelstop-vpn --fast-io --writepid $pidfile
end

function vpn-docker -a action
  set -l runtime docker
  set -l image huynhminhdang/openvpn-tinyproxy:latest
  set -l container travelstop-vpn
  set -l colima colima --profile $container-$runtime
  set -l ctl docker
  switch "$action"
    case stop
      command $colima stop
    case update
      command $colima status 2>&1 | string collect | string match -q '*is running*' ||
        command $colima start --runtime $runtime --cpu 1 --memory 1 --disk 1 --verbose
      command $ctl pull $image
    case \*
      command $colima status 2>&1 | string collect | string match -q '*is running*' ||
        command $colima start --runtime $runtime --cpu 1 --memory 1 --disk 1 --verbose
      command $ctl images --quiet $image | test -n - ||
        command $ctl pull $image
      command $ctl kill (command $ctl ps --quiet --filter "name=$container") 2>/dev/null
      command $ctl run \
        --name $container \
        --volume ~/.config/vpn:/etc/openvpn/profile \
        --volume ~/.config/vpn:/etc/openvpn/hosts \
        --publish 8888:8888 \
        --device /dev/net/tun \
        --cap-add NET_ADMIN \
        --rm \
        --tty \
        --detach \
        $image
  end
end

function vpn-containerd -a action
  set -l runtime containerd
  set -l image huynhminhdang/openvpn-tinyproxy:latest
  set -l container travelstop-vpn
  set -l colima colima --profile $container-$runtime
  set -l ctl $colima nerdctl --
  switch "$action"
    case stop
      command $colima stop
    case update
      command $colima status 2>&1 | string collect | string match -q '*is running*' ||
        command $colima start --runtime $runtime --cpu 1 --memory 1 --disk 1 --verbose
      command $ctl pull $image
    case \*
      command $colima status 2>&1 | string collect | string match -q '*is running*' ||
        command $colima start --runtime $runtime --cpu 1 --memory 1 --disk 1 --verbose
      command $ctl images --quiet $image | test -n - ||
        command $ctl pull $image
      command $ctl ps --all | grep $image | read container_id _ 2>/dev/null
      test -n "$container_id" &&
        command $ctl rm --force $container_id
      command $ctl run \
        --name $container \
        --volume ~/.config/vpn:/etc/openvpn/profile \
        --volume ~/.config/vpn:/etc/openvpn/hosts \
        --publish 8888:8888 \
        --device /dev/net/tun \
        --cap-add NET_ADMIN \
        --detach \
        $image
  end
end

function vpn
  switch "$ts_vpn"
    case native
      vpn-native $argv
    case docker
      vpn-docker $argv
    case \*
      vpn-containerd $argv
  end
end
