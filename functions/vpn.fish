function vpn
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
