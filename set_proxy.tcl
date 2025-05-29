proc set_proxy {  } {
	set proxy_host ""
	set proxy_port ""

	set ::http_proxy ""
	catch {
		set ::http_proxy $::env(http_proxy)
	}

	if { $::http_proxy != "" } {
		regexp {http://(.*):(.*)/} $::http_proxy all proxy_host proxy_port
	}
	set ::proxy_host $proxy_host
	set ::proxy_port $proxy_port

	return [list $proxy_host $proxy_port]
}
