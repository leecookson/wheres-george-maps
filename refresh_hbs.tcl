#!/usr/bin/tclsh 

# refresh_hbs, only cron at 11:30pm, else it will use up refreshes too early.

	package require http 2.0

	set maps_dir $env(MAPSHOME)

 	cd $maps_dir

	set wg_domain "http://www.wheresgeorge.com"

	set useragent {Tcl http client package 2.4.2}
	set acceptval {text/xml,application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,*/*;q=0.5}
	set posturl {http://www.wheresgeorge.net/upload.php}
	
	proc getPage { url {headers ""}} {
	       set token [::http::geturl $url -headers $headers ]
	       set data [::http::data $token]
	       set ::code [::http::code $token]
	       ::http::cleanup $token
	       return $data
	}


	set url http://www.wheresgeorge.com/ybs.php?hbs=5644

	set cookies {mid=19745215; pagewidth=814; userkey=1ba8966ffd95bc9573d6534b039a44a8}

	lappend headers "Cookie" $cookies

	set ofile [open hbs_data_refresh.txt w]

	puts $ofile "===================\nGETing=$url\n==================\n"

	set input [getPage $url $headers]
	
	puts $ofile "===================\ninput=$input\n==================\n"

	set start [string last "href=runner.php" $input]
	if { $start < 0 } { exit 0 }

	incr start 5
	set input [string range $input $start end]

	puts $ofile "start=$start\n"

	set end [expr [string first ">" $input] -1]

	puts $ofile "end=$end\n"

	set refresh_path [string range $input 0 $end]

	puts $ofile "===================\nrefresh_path=$refresh_path\n==================\n"
	
	set refresh_url "${wg_domain}/${refresh_path}"

	set now [lindex $argv 0]

	set time_now [clock seconds]
	set hour [clock format $time_now -format "%H"]
	set minute [clock format $time_now -format "%M"]

	if { ($hour >= 23 || $hour < 1 || $now == "now") && $refresh_path != ""} {
		set input [getPage $refresh_url $headers]
		puts $ofile "executed $refresh_url at ($hour:$minute)"
	} else {
		puts $ofile "would have done http_get $refresh_url"
		puts $ofile "but it's not after 23:00 or before 01:00 ($hour:$minute)"
	}

	close $ofile
