function vpn-native
  set --local pidfile {$TMPDIR}travelstop-vpn.pid
  sudo pkill -9 -F $pidfile >/dev/null 2>&1
  if not test -f ~/.config/vpn/config
    echo Please put your VPN config in $HOME/.config/vpn/config
    return 1
  end
  function vpn-up --on-event openvpn-up --argument-names payload
    pkill -9 -U (id -u) tinyproxy >/dev/null 2>&1
    echo $payload | read --delimiter ' ' --local tun_mtu link_mtu ifconfig_local ifconfig_netmask script_context
    tinyproxy --port 8888 --bind $ifconfig_local --disable-via-header --log-level Connect --syslog On
    functions --erase (status function)
    set --local notif_title 'VPN connected!'
    set --local notif_message 'Proxy: localhost:8888'
    functions --query fontface &&
      set notif_title (fontface math_monospace "$notif_title") &&
      set notif_message (fontface math_monospace "$notif_message")
    _ts_notify "$notif_title" "$notif_message"
  end
  openvpn --config ~/.config/vpn/config --askpass ~/.config/vpn/passwd --auth-nocache --daemon travelstop-vpn --fast-io --writepid $pidfile
end

function vpn-docker
  set --local image huynhminhdang/openvpn-tinyproxy:latest
  set --local container travelstop-vpn
  if string match --quiet '*colima is not running*' (colima status 2>&1)
    colima start --runtime docker --cpu 1 --memory 1 --disk 1 --verbose
  end
  if test -z (docker images --quiet $image)
    docker pull $image
  end
  docker kill (docker ps --quiet --filter "name=$container") 2>/dev/null
  docker run \
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

function vpn
  vpn-docker
end
