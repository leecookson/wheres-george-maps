#!/usr/bin/tclsh 

	package require http 2.0
	set maps_dir $env(MAPSHOME)

 	cd $maps_dir

	# defines getPage and sets up proxy variable http_proxy
	source http_utils.tcl

	set magick_home $env(MAGICK_HOME)
	set imconvert ${magick_home}/bin/convert

	set font Arial-Regular
	
	puts "proxy_host=$proxy_host"

	set url http://www.wheresgeorge.com/ybs.php

	set cookies {mid=19745215; pagewidth=814; userkey=1ba8966ffd95bc9573d6534b039a44a8}

	lappend headers "Cookie" $cookies
	
	##################################
	# Get page so we can start parsing
	set input [getPage $url $headers]

	set origInput $input
	## Parse out the data from this format:
	##		You have entered 11,038 Bills worth $17,563</div></td>
	##	</tr>
	##	<tr class="topnav" bgcolor="#007000">	<td ><div align=center>Bills with hits: 1,303 &nbsp;&nbsp;&nbsp;Total hits: 1,507</div></td>
	##	</tr>
	##	<tr class="topnav" bgcolor="#007000">	<td ><div align=center>Hit rate: 11.80%&nbsp;&nbsp;&nbsp;Slugging Percentage: 13.65% (total hits/total bills)</div></td>
	##	</tr>
	##	<tr class="topnav" bgcolor="#007000">	<td ><div align=center>George Score: 1,036.96</div><!-- actual 1036.96211836605 --></td>
	##	</tr>
	##	<tr class="topnav" bgcolor="#007000">	<td ><div align=center>Your rank (based on George Score) is #1,203<br>(out of&nbsp;51,901 current users with a George Score. [97.7 Percentile])</div></td>
	##	</tr>
	##	<tr class="topnav" bgcolor="#007000">	<td ><div align=center>Your State Rank in New Jersey is: 35 out of 3,158 [98.9]	

	set start [string first "You Have Entered" $origInput]
	set end [expr [string first "in New Jersey" $origInput] + 50]
	set data [string range $input $start $end]
	set orig_data $data

	set bills 0
	set bills_hit 0
	set bill_hits 0
	set rank 0
	set state_rank 0
	set vars {date bills bills_hit bill_hits rank state_rank}
	set starts {{as of: } {You have entered } {Bills with hits: } {Total hits: } {Your rank (based on George Score) is #} {Your State Rank in New Jersey is: }}
	set ends {{<br>} { } { } {</div>} {<br>} { }}

	set output_vars ""
	foreach v $vars s $starts e $ends {
		set st_len [string length $s]
		set start [expr [string first $s $data] + $st_len]
		set data [string range $data $start end]
		set end [expr [string first $e $data] -1]
		
		set $v [string range $data 0 $end]
		lappend output_vars $v $end [string range $data 0 $end]

		set data [string range $data $end end]
	}

	set ofile [open "$maps_dir/ybs_data_feed.txt" a]

	puts $ofile "Run time: [clock format [clock seconds] -format "%b-%d-%Y %H:%M"]"
	puts $ofile "Report time: $date"

	puts $ofile "$bills   $rank   $state_rank   $bills_hit   $bill_hits"
	puts $ofile ""

	close $ofile

	set filename "$maps_dir/ybs_data_[clock format [clock seconds] -format "%a"].htm"
	# assume file may not exist, and append if it does
	set modes a
	
	if { [file exists $filename] } {
		# if file exists, check whether it was last modified today
		set lastMod [file mtime $filename]
		set lastModTimeDay [clock format $lastMod -format %d]
		set currentTimeDay [clock format [clock seconds] -format %d]
		if { $lastModTimeDay != $currentTimeDay  } {
			# first report for this day, overwrite file
			set modes w
		}
	}
	
	set ofile [open $filename $modes]
	
	puts $ofile "open mode=$modes\n"
	puts $ofile "===================\ninput=$input\n==================\n"


	set start [string last "Federal Reserve Bank" $input]
	set input [string range $input $start end]

	puts $ofile "start=$start\n"

	set end [string first "</table" $input]

	puts $ofile "end=$end\n"

	set input [string range $input 0 $end]

	puts $ofile "===================\ninput=$input\n==================\n"

	set tr [string first "<tr" $input]
	set input [string range $input $tr $end]
	# skip first row, column titles
	set tr [string first "<tr" $input]

	set cmd {}

	set cmd {}

	lappend cmd exec -- $imconvert "frb_table.png"

	lappend cmd	-fill black
	lappend cmd	-font "$font" -pointsize 11
	lappend cmd	-linewidth 3
	
	set index 0
	set vpos 69
	while { $tr > -1 } {
		set td [string first "<td align=center>" $input]
		set td [expr $td + 17]
		set endtd [expr [string first "</td>" $input] -1]
		set frb($index) [string range $input $td $endtd] 

		lappend cmd	-draw "translate -222,-160 gravity Center text 96,$vpos '$frb($index)'"

		set input [string range $input [expr $endtd + 5] end]

		set td [string first "<td align=center>" $input]
		set td [expr $td + 17]
		set endtd [expr [string first "</td>" $input] -1]
		set entered($index) [string range $input $td $endtd]

		lappend cmd	-draw "translate -222,-160 gravity Center text 213,$vpos  ' $entered($index) '"

		set input [string range $input [expr $endtd + 5] end]

		set td [string first "<td align=center>" $input]
		set td [expr $td + 17]
		set endtd [expr [string first "</td>" $input] -1]
		set percent($index) [string range $input $td $endtd]

		lappend cmd	-draw "translate -222,-160 gravity Center text 277,$vpos  ' $percent($index) '"

		set input [string range $input [expr $endtd + 5] end]

		set td [string first "<td align=center>" $input]
		set td [expr $td + 17]
		set endtd [expr [string first "</td>" $input] -1]
		set hits($index) [string range $input $td $endtd]

		lappend cmd	-draw "translate -222,-160 gravity Center text 347,$vpos  ' $hits($index) '"

		set input [string range $input [expr $endtd + 5] end]

		set td [string first "<td align=center>" $input]
		set td [expr $td + 17]
		set endtd  [expr [string first "</td>" $input] -1]
		set hitrate($index) [string range $input $td $endtd]

		lappend cmd	-draw "translate -222,-160 gravity Center text 411,$vpos  ' $hitrate($index) '"

		set input [string range $input [expr $endtd + 5] end]

		puts $ofile "frb=$frb($index),percent=$percent($index),entered=$entered($index),hits=$hits($index),hitrate=$hitrate($index)\n"


		incr index
		incr vpos 19
		set tr [string first "<tr" $input]
	}

	lappend cmd	-font "$font" -pointsize 13
	lappend cmd	-draw "text 4,310  ' Updated: [clock format [clock seconds] -format %c] '"

	lappend cmd	"frb_table_Z.png"

	set out [eval "$cmd"]
