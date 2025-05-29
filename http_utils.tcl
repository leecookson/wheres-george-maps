# tcl shared getpage function
#	handles proxy detection from http_proxy environment variable

	set ::proxy_host ""
	catch {
		set  ::proxy_host $env(http_proxy)
	}
	 
	proc getPage { url {headers ""}} {
		if { $::proxy_host != "" } {
		   ::http::config -proxyhost proxy.dowjones.net -proxyport 80
		}
	       set token [::http::geturl $url -headers $headers ]
	       set data [::http::data $token]
	       set ::code [::http::code $token]
	       ::http::cleanup $token
	       return $data
	}



