#!/usr/bin/tclsh 

# ZIP Fill


# uses NJ_zip2towns.txt
# maps zips in incoming URL file to actual town names
# got zips from http://www.state.nj.us/nj/about/facts/njzips.html
# changed ambiguous ones.

	package require http 2.0
	set maps_dir $env(MAPSHOME)

 	cd $maps_dir

	# defines getPage and sets up proxy variable http_proxy
	source http_utils.tcl

	set magick_home $env(MAGICK_HOME)
	set imconvert ${magick_home}/bin/convert

	set font Arial-Regular
	set font_size 13
	
	puts "proxy_host=$proxy_host"

	proc get_scale_factor { values min_output max_output } {
		set max 0
		set min 99999999
		foreach value $values {
			if { $value > $max } {
				set max $value
			}
			if { $value < $min } {
				set min $value
			}
		}
	
		set range [expr $max - $min + 1]
		set output_range [expr $max_output - $min_output + 1]
		set scale [expr (0.0 + $output_range) / (0.0 + $range) ]
	
		return $scale	
	}
	
	proc save_stats { state pos counts } {
		array set pos_array $pos

		set stats_out {}
		foreach {k v} $counts {
			if { [info exists pos_array($k)] } {
			lappend stats_out "$k	$v
	"
			}
		}
		set stats_out [lsort $stats_out]
		set stats_fd [open ${state}_stats.txt w]
		puts $stats_fd $stats_out
		close $stats_fd
		

	}

	proc save_last { state } {

		puts "Checking $state"

		set stats_fd [open ${state}_stats.txt r]
		while { ! [eof $stats_fd] } {
			gets $stats_fd stat
			append stats $stat
		}
		close $stats_fd

		set stats_last_fd [open ${state}_stats_last.txt r]
		while { ! [eof $stats_last_fd] } {
			gets $stats_last_fd stat
			append stats_last $stat
		}
		close $stats_last_fd
		
		set log [open ${state}_stats.log w]
		puts $log "stats=     |$stats|"
		puts $log "stats_last=|$stats_last|"
		close $log

		if { $stats != $stats_last } {
			puts "Detected change in $state"
	
			file delete "${state}_HIT_MAP_Y.png"
			file copy "${state}_HIT_MAP_Z.png" "${state}_HIT_MAP_Y.png"
	
			file delete "${state}_stats_last.txt"
			file copy "${state}_stats.txt" "${state}_stats_last.txt"
		}		


	}

	proc morph { state } {
		set degree 3
		set total_frames [expr $degree + 2]
		set morph_stub HIT_MORPH

		# original

		#generate 6 frames, state_HIT_MORPH-[0-6		]
		exec $::imconvert ${state}_HIT_MAP_Y.png ${state}_HIT_MAP_Z.png -morph $degree tmp/${state}_${morph_stub}

		set cmd [list exec $::imconvert \-delay 100]
		for { set i 0 } { $i < $total_frames } { incr i } {
			if { $i == [expr $total_frames-1] } {
				lappend cmd \-delay 400
			}
			lappend cmd tmp/${state}_${morph_stub}-$i
		}

		lappend cmd ${state}_HIT_MAP_YZ.gif
		return [eval "$cmd"]

	}

	proc get_min_value { values } {
		set min 99999999
		foreach value $values {
			if { $value < $min } {
				set min $value
			}
		}
		return $min
	}
	
	proc get_max_value { values } {
		set max -1
		foreach value $values {
			if { $value > $max } {
				set max $value
			}
		}
		return $max
	}
	
	proc scale_color { value scale_factor min_input min_output } {
		set hex_factor [expr 256.0 / 100.0]
		return [format "%2x" [expr int(((($value - $min_input) * $scale_factor ) + $min_output) * $hex_factor)]]
	}
	
	proc find_bracket { hits rangemn_array rangemx_array} {
		array set rangemn $rangemn_array
		array set rangemx $rangemx_array
	
		for { set i 1 } { $i <= 6 } { incr i } {
			if { $hits >= $rangemn($i) && $hits <= $rangemx($i) } {
				return $i
			}
		}
		
		return 0
	}

	proc compare_counties { c1 c2 } {
		set hits1 [lindex $c1 1]
		set hits2 [lindex $c2 1]
		if { ![string is integer $hits1] } {return -1}
		if { ![string is integer $hits2] } {return 1}
		if { $hits1 > $hits2 } { return 1 }
		if { $hits1 < $hits2 } { return -1 }
		if { $hits1 == $hits2 } { 
			if { [lindex $c1 0] < [lindex $c2 0] } {
				return 1
			} else {
				return -1
			}
		}
	}

	proc create_gradients { colors_in } {
		set gradcmdroot {}
		lappend gradcmdroot exec -- $::imconvert -size 100x100
		
		array set colors $colors_in
		#fill range spot to color in array
		foreach {index r_color} [array get colors] {
			set r_color "$r_color"
			set grad_file_name "fills/xgradient_range${r_color}.png"
			set solid_file_name "fills/xsolid_range${r_color}.png"

			if { [file exists $grad_file_name] && [file exists $solid_file_name] } {
				return
			}
			set gradcmd $gradcmdroot
			set solidcmd $gradcmdroot

#			lappend gradcmd plasma:gray80-gray90 -blur 0x2  -fill $r_color -colorize 50
			set next_index [expr $index + 1]
			set stroke_color #000

			if { $index < 6 } { set stroke_color $colors($next_index) }

			lappend gradcmd pattern:right45 -fill $stroke_color -opaque black -fill $r_color -opaque white -fill white  -tint 90
			if { ! [file exists $grad_file_name] } {
				lappend gradcmd "$grad_file_name"
				eval "$gradcmd"
			}
			if { ! [file exists $solid_file_name] } {
				lappend solidcmd "xc:$r_color" "$solid_file_name"
				eval "$solidcmd"
			}
			
		}
		

	}	

	proc load_zip_mappings { filename } {
		set fd [open $filename "r"]
		
		while { ![eof $fd] } {
			set line ""
			gets $fd line
			set tokens [split $line]
			if { [llength $tokens] > 1 } {
				set zip [lindex $line 0]
				set town [lrange $line 1 end]
				set ::zip_to_city($zip) $town
			}
		}
		close $fd
	}

	proc get_city { zip } {
		set return_val "${zip} Not Found"
		set try [ catch {
			set return_val $::zip_to_city($zip)
		} errMsg]
		return $return_val
	}

	# start of main program, determine state/county symbol
	if { $argc > 0 } {
		set state [lindex $argv 0]
	} else {
		set state NJ
	}
	
	set draw_names 0
	
	set colors(0) "#fff"
	set colors(1) "#FFB"
	set colors(2) "#FBF"
	set colors(3) "#aaf"
	set colors(4) "#0f0"
	set colors(5) "#ef0"
	set colors(6) "#f11"
	

	set ofile [open ${state}_data.txt w]
	
	set rangeName "${state}_range.txt"
	source ${rangeName}

	load_zip_mappings $zip_file

	create_gradients [array get colors]

	set pos_file_name "${state}_pos.txt"
	set posf [open $pos_file_name r]
	while { ! [eof $posf] } {
		set line ""
		gets $posf line
		set cp [split $line =]
		set city [lindex $cp 0]
		set cpos [lindex $cp 1]
		set "pos($city)" $cpos
	}
	close $posf
	
	file delete "${state}_HIT_MAP_FF.PNG"
	#set http_proxy=http://proxy.dowjones.net:80

	set cookies {mid=19745215; pagewidth=814; userkey=1ba8966ffd95bc9573d6534b039a44a8}
	
#	set fileName "${state}.htm"
#	set accept "Accept: $acceptval"
#	set acceptlangval {en-us,en;q=0.5}
#	set acceptlang "Accept-Language: $acceptlangval"
#	set acceptcharsetval {ISO-8859-1,utf-8;q=0.7,*;q=0.7}
#	set acceptcharset "Accept-Charset: $acceptcharsetval"
	
#	set wgetcmd {}
#	lappend wgetcmd exec wget -O $fileName --user-agent=$useragent --header=Cookie:$cookies  $url
	
#	set try [#catch {
#	set out ""
#	set out [#eval "$wgetcmd"]
#	} errmsg]
	#userkey=1ba8966ffd95bc9573d6534b039a44a8
	
#	set fileId [ open $fileName r ]      
#	while { ! [eof $fileId] } {
#		set line ""
#		gets $fileId line
#	    append input $line
#	}      
#	close $fileId
	
	lappend headers "Cookie" $cookies
	set input [getPage $zip_url $headers]
	
	puts $ofile "argv=$argv"
#	puts $ofile "$wgetcmd"
	
	puts $ofile "===================\ninput=$input\n==================\n"
	
	set USmode 0
	
	set start [string first "ybbody" $input]
	if { $start == -1 } {
		set start [string first {class="body"} $input]
		set USmode 1
	}
	puts $ofile "start1=$start\n"
	set start [string last "<tr" [string range $input 0 $start]]
	puts $ofile "start2=$start\n"
	set end [string last "ybbody" $input]
	if { $end == -1 } {
		set end [string last {class="body"} $input]
		set USmode 1
	}
	puts $ofile "end1=$end\n"
	set end [expr [string first "</tr>" [string range $input $end end]] + $end + 5]
	puts $ofile "end2=$end\n"
	set data [string range $input $start $end]
	
	set hit_list {}
	set index 1
	# remove all linefeeds/tabs
	regsub -all "\n\t" $data "" tmpdata
	puts $ofile $tmpdata
	
	for { set index 1 } { $index <= $num_counties } { incr index } {
		#use regexp
		set row ""
		set rank 0
		set city N
		set hits 0
		set rankval "${index}"
		set startrow [string first ">${rankval}.<" $tmpdata]
		set rest [string range $tmpdata $startrow end]
		set endrow [string first "</tr>" $rest]
		set endrow [expr $endrow + 12]
		set row [string range $rest 0 $endrow]
	
		regexp {>([0-9-]+).<} $row x rank
		regexp {>([0-9][0-9][0-9][0-9][0-9]+)[</a]} $row x2 zip
		set cut_index [string first /a $row]
		set row [string range $row $cut_index end]
		set cut_index [expr [string first /td $row] +1]
		set row [string range $row $cut_index end]

		regexp {<td align=center>([^<]+)</td>} $row x3 city
		set cut_index [expr [string first /td $row] +1]
		set row [string range $row $cut_index end]

		regexp {<td align=center>([^<]+)</td>} $row x3 county
		set cut_index [expr [string first /td $row] +1]
		set row [string range $row $cut_index end]

		regexp {<td align=center>([0-9-]+)</td>} $row x3 hits
		set county [string trim $county]
		set city [string trim $city]
		set zip [string trim $zip]
		set hits [string trim $hits]
		puts $ofile "row=$row, rank=$rank,zip=$zip,city=$city,county=$county,hits=$hits\n"
		set zip_array($zip) $hits
	}

	puts $ofile "Hits per zip zip_array="
	puts $ofile [array get zip_array]
	puts $ofile ""

	# accumulate ZIP hits into Cities
	set zip_array_data [array get zip_array]
	foreach { z h } $zip_array_data  {
		# get city from zip2city mapping table
		set city [get_city $z]
		set h_tmp 0
		catch {
			set h_tmp "$d($city)"
		}
		incr h_tmp $h
		set "d($city)" $h_tmp
	}

	puts $ofile "Hits per city d="
	puts $ofile [array get d]
	puts $ofile ""

	set city_array_data [array get d]
	foreach {c h} $city_array_data {
		set range [find_bracket $h [array get rangemn] [array get rangemx]]
		if { $range > 0 && $h == $rangemx($range)  && $h != $rangemn($range) } {
			set "limit($c)" 1
		} else {
			set "limit($c)" 0
		}
		set "color($c)" $colors($range)
		if { [string is integer $h] } {
			lappend hit_list $h
		}
	}

	puts $ofile "hit_list=$hit_list"

	####### INACTIVE, SCALES COLORS BASED ON # of hits	
	set hits_scale [get_scale_factor $hit_list 50 95]
	set hits_min [get_min_value $hit_list]
	set hits_max [get_max_value $hit_list]
	set hit_array_data [array get d]
	set hit_list_by_city ""
	foreach {c h} $hit_array_data {
		if { [string is integer $h] } {
			set scaled_color_r [scale_color $h $hits_scale $hits_min 50]
			set scaled_color_gb [scale_color [expr $hits_max - $h ] $hits_scale $hits_min 50]
	#		set "color($c)" "#${scaled_color_r}${scaled_color_gb}${scaled_color_gb}"
			lappend hit_list_by_city [list $c $h]
		}
	}
	#######

	
	# use lappend to build the arg list dynamically
	set city_colors [array get color]
	set cmd {}

	puts $ofile "city_colors=$city_colors"

	# save count stats, stored in array called "d"
	save_stats $state [array get pos] [array get d]

	lappend cmd exec -- $imconvert "${state}_HIT_MAP.png"

	set legend_pos_x [expr $legend_x + 14]
	set legend_pos_y [expr $legend_y + 5]

	set spacing_y 17

	# write range text, hard-coded, no loop
	lappend cmd	-fill black
	lappend cmd	-font "$font" -pointsize $font_size
	lappend cmd	-linewidth 3
	set loop_max 6
	for { set i $loop_max } { $i > 0 } { incr i -1 } {
		if { $loop_max == $i } {
			lappend cmd	-draw "text $legend_pos_x,$legend_pos_y  ' $rangemn($i) +'"
		} else {
			lappend cmd	-draw "text $legend_pos_x,$legend_pos_y  ' $rangemn($i) - $rangemx($i) '"
		}
		incr legend_pos_y $spacing_y
	}

	set legend_pos_x $legend_x

	# draw spots for legend
	foreach {index r_color} [array get colors] {
		if { $index > 0 } {
			set legend_pos_y [expr $legend_y + ((6-$index) * $spacing_y)]
	
			set legend_pos_x_outer [expr $legend_pos_x - 6]
			lappend cmd -fill "$r_color" -draw "circle ${legend_pos_x},${legend_pos_y} ${legend_pos_x_outer},${legend_pos_y}"
		}
		incr legend_pos_y $spacing_y
	}
	
	lappend cmd	-fill black

	set day [clock format [clock seconds] -format %d]
	set day [expr [string trimleft $day 0] ]
	lappend cmd	-draw "text 4,14  ' Updated: [clock format [clock seconds] -format "%a %b $day, %Y %H:%M:%S %Z"] '"


	# print top 5 on map if top_5_x is set
	if { [info exists top_5_x] && [info exists top_5_y] } {
		if { [info exists top_count] && [string is integer $top_count] } {
			set count $top_count
		} else {
			set count 5
		}
		lappend cmd	-fill black -pointsize $font_size
		lappend cmd	-draw "text ${top_5_x},${top_5_y}  'Top $count'"
		incr top_5_y 16
		set hit_list_by_city [lsort -decreasing -command compare_counties $hit_list_by_city]
		foreach {c_h} $hit_list_by_city {
			set c [lindex $c_h 0]
			set h [lindex $c_h 1]
			if { ! [info exists "pos($c)"] } { continue }
			lappend cmd	-draw "text ${top_5_x},${top_5_y}  '$h'"
			lappend cmd	-draw "text [expr ${top_5_x} + 28],${top_5_y}  '$c'"
			incr top_5_y $font_size
			incr count -1
			if { $count <= 0 } break
		}
	}

	set cities_in_county {}

	foreach {city c_color} $city_colors {
		if { ! [info exists "pos($city)"] } {
			set c_pos "0,0"
			continue
		} else {
			set c_pos $pos($city)
			lappend cities_in_county [list $city $c_pos $c_color]
		}
		set c_pos_list [split $c_pos "|"]
		foreach cp $c_pos_list {
			set c_pos_value [split $cp ","]
			set c_pos_x [lindex $c_pos_value 0]
			set c_pos_y [lindex $c_pos_value 1]
			set c_pos_x_outer [expr $c_pos_x - 1]
			set c_pos_y_outer [expr $c_pos_y - 1]
			if { $limit($city) == 1 } {
				lappend cmd -tile fills/xgradient_range${c_color}.png
				lappend cmd -draw "color $cp floodfill"
			} else {
				lappend cmd -tile fills/xsolid_range${c_color}.png
				lappend cmd -draw "color $cp floodfill"
			}
			# this would draw a blue dot a fill point			
		#		lappend cmd -linewidth 1 -stroke "#00d" -fill "#ff0" -draw "circle ${c_pos_x},${c_pos_y} ${c_pos_x_outer},${c_pos_y_outer}"
		}
	}

	lappend cmd -bordercolor #999 -border 1x1

	lappend cmd	"${state}_HIT_MAP_Z.png"
	
	puts $ofile cities_in_county=$cities_in_county
	
	save_last ${state}

	puts $ofile $cmd
	
	set out [eval "$cmd"]

	morph $state
	
	close $ofile

