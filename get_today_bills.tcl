#!/usr/bin/tclsh 

	package require http 2.0
#	load /opt/local/lib/mysqltcl-3.05/libmysqltcl3.02.dylib
	package require mysqltcl

	source set_proxy.tcl
	set maps_dir $env(MAPSHOME)
	cd $maps_dir


        set proxy_info [set_proxy]

	puts "proxy= $http_proxy"
	proc log { handle message } {
		#puts $handle $message
	}

	proc escape_sql_string { input } {
		set output $input
		set try [catch {
			regsub -all "\n" $input "\\n" output1
			regsub -all "'" $output1 "''" output
		} errMsg]
		return $output
	}

	proc expand_city_state_zip_county { input } {
		# hits: <script>document.write("<A  HREF=\"javascript:popup_win('flags/pa.jpg',230,310,'no');\"><IMG border=0 width=30 height=19 SRC=\"flags/pa.jpg\">&nbsp;</a>");</script><noscript><A HREF=flags/pa.jpg target=_blank><IMG border=0 width=30 height=19 SRC="flags/pa.jpg">
		#			&nbsp;</a></noscript>Philadelphia, PA&nbsp;</b>&nbsp;(19119/Philadelphia)&nbsp;&nbsp;<span class=small><a target=_blank href=http://www.mapquest.com/maps/map.adp?zoom=3&formtype=address&searchtype=address&country=US&zipcode=19119>map</a></span>
		# nohits: Burlington, NJ&nbsp;</b>&nbsp;(08016/Burlington)&nbsp;&nbsp;<span class=small><a target=_blank href=http://www.mapquest.com/maps/map.adp?zoom=3&formtype=address&searchtype=address&country=US&zipcode=08016>map</a></span>
		# foreign: Playa del Carmen,&nbsp;Mexico&nbsp;</b>&nbsp;(17674Z)&nbsp;[mx]
		# Canada: <IMG border=0 width=30 height=19 SRC=images/canflag.gif>&nbsp;Ottawa, ON&nbsp;</b>&nbsp;(K1R5M6)&nbsp;&nbsp;<span class=small><a target=_blank href=http://www.mapquest.com/maps/map.adp?zoom=3&formtype=address&searchtype=address&country=CA&zipcode=K1R5M6>map</a></span>
		set city ""
		set state ""
		set zip ""
		set county ""

		set script_pos [string first script $input]
		if { $script_pos >= 0 } {
			# hits mode
			set end [string first </noscript> $input]
			set input [string range $input [expr $end + 11] end]
		}

		set canada_pos [string first canflag $input]
		if { $canada_pos >= 0 } {
			# canada mode
			set img_pos [string first <IMG $input]
			set end [string first "&nbsp;" $input]
			set input [string range $input [expr $end + 6] end]
			set canada_mode 1
		} else {
			set canada_mode 0
		}
		# check for foreign hit
		set bracket_pos [string first \[ $input]
		if { $bracket_pos >=0 } {
			set city_skip 7
			set zip_end ")"
			set zip_skip 8
			set county_end \]
		} else {
			set city_skip 2
			if { $canada_mode } {
				set zip_end ")"
			} else {
				set zip_end "/"
			}
			set zip_skip 1
			set county_end )
		}

		set end [string first , $input]
		set city [string range $input 0 [expr $end -1]]
		set input [string range $input [expr $end + $city_skip] end]

		set end [string first "&nbsp;" $input]
		set state [string range $input 0 [expr $end -1]]
		set input [string range $input [expr $end + 17] end]

		set end [string first $zip_end $input]
		set zip [string range $input 0 [expr $end -1]]
		set input [string range $input [expr $end + $zip_skip] end]
		if { $canada_mode } {
			set county "n/a"
		} else {
			set end [string first $county_end $input]
			set county [string range $input 0 [expr $end -1]]
		}

		return [list $city $state $zip $county]
	}


	#######################
	# input: bill_data, list of { $denom $series $serial $key $entries $hits $date
	# will insert new bill entry, or update existing bill entry with all fields
	#
	proc insert_or_update_bill { bill_data input_wild db_handle log_handle } {
		set change 0

		set input_denom [lindex $bill_data 0]
		set input_series [lindex $bill_data 1]
		set input_serial [lindex $bill_data 2]
		set input_key [lindex $bill_data 3]
		set input_entries [lindex $bill_data 4]
		set input_hits [lindex $bill_data 5]
		set input_date [lindex $bill_data 6]

		set result [::mysql::sel $db_handle "select id, total_hits, wild from bills where id='$input_key'" -list]
		log $log_handle "checking before insert $input_key=\{$result\}"

		if { [llength $result] == 0 } {
			# insert new row
			log $log_handle "inserting $bill_data"
			if { $input_wild } {
				set input_wild "1"
			} else {
				set input_wild "0"
			}
			::mysql::query $db_handle "insert into bills values('$input_key','$input_denom','$input_series','$input_serial',$input_hits,'$input_date','$input_date',$input_wild)"
			set change 1

		} else {
			# Bill $key exists, updating entries if needed
			foreach row $result {
				set key [lindex $row 0]
				set hits [lindex $row 1]
				set wild [lindex $row 2]

				set num_entries [get_number_of_entries $input_key $db_handle]
				log $log_handle "checking before update $input_key, hits=$hits, input_hits=$input_hits, entries=$num_entries, input_entries=$input_entries "

				set wild_clause ''

				if { $input_wild } {
					set wild_clause ", wild=1"
				}

				if { $hits != $input_hits || $num_entries != $input_entries || $input_wild != $wild } {
					# update
					::mysql::query $db_handle "update bills set total_hits=$input_hits, denom='$input_denom', series='$input_series', serial='$input_serial' ${wild_clause} where id='$key'"
					set change 1
				}
			}
		}

		return $change
	}


	#########
	#
	# Get number of entries in hits table for bill_id
	#
	proc get_number_of_entries { bill_id db_handle } {
		set result [::mysql::sel $db_handle "select * from hits where bill_id='$bill_id'" -list]

		return [llength	 $result]
	}

	#########
	#
	# Remove all entries for a bill
	#
	proc remove_entries { bill_id db_handle } {
		::mysql::query $db_handle "delete from hits where bill_id='$bill_id'"

	}

	#########
	#
	#	updates bill with new last_hit_date
	#	last_hit_date needs to be in ####-##-## ##:##:## format
	proc update_last_hit_date { key input_date db_handle } {
		#	using triggers to update these fields now
		#::mysql::query $db_handle "update bills set  last_hit_date='$input_date' where id='$key' and ('$input_date' > last_hit_date || last_hit_date = '0000-00-00 00:00:00')"
	}

	#########
	#
	#	updates bill with new entry_date
	#	entry_date needs to be in ####-##-## ##:##:## format
	proc update_entry_date { key input_date db_handle } {
		#	using triggers to update these fields now
		#::mysql::query $db_handle "update bills set  entry_date='$input_date' where id='$key' and ('$input_date' < entry_date || entry_date = '0000-00-00 00:00:00')"
	}


	########
	#
	#	formats WG date/time format to MySQL datetime format
	proc wg_datetime_to_mysql_datetime { date_time } {

		if { $date_time == "" } {
			return "0000-00-00 00:00:00"
		}

		set result [regexp "(..)-(...)-(..) (..):(..) (..)" $date_time v dy mo yr hr mn ampm]

		set new_date_time "$mo $dy, $yr $hr:$mn $ampm"
		# required: monthname dd ?, yy?
		set dt [clock scan $new_date_time]
		return [clock format $dt -format "%Y-%m-%d %H:%M:00"]
	
	}

	proc getPage { url {headers ""}} {
		if { $::proxy_host != "" } {
		   ::http::config -proxyhost $::proxy_host -proxyport $::proxy_port
		}
	       set token [::http::geturl $url -headers $headers ]
	       set data [::http::data $token]
	       set ::code [::http::code $token]
	       ::http::cleanup $token
	       return $data
	}


	# checking schema
	#set result [::mysql::col $handle bills name]
	#puts $result


	if { $argc > 0 } {
		set command [lindex $argv 0]
		set page 1
		if { $argc > 1 } {
			set page [lindex $argv 1]
		}
	} else {
		set command recently_entered
		set page 1
	}

	puts "Fetching $command, page=$page"
	puts "--------"
	
	set useragent {Tcl http client package 2.4.2}
	set acceptval {text/xml,application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,*/*;q=0.5}
	set posturl {http://www.wheresgeorge.net/upload.php}

	# open DB connection
	set handle [::mysql::connect -host 127.0.0.1 -user root -password mysqldmx7 -db bills]

#	set to 1 to load all hits, 0 for only updated/new bills
	set fetch_all_hits 0
	set wild 0


	switch $command {
		hits_today {
			#	Today's Hits
			set url http://www.wheresgeorge.com/ybd.php?args=bb0796fc455b7a8ff37366bbcdc255090c187d280bcecaac84a49ea4663013859e38000bb1bf512361e9db198da7f5cc18c3d18eb856bad498298d36edfa3182ddd22d979d1ac83a435dcba41e70b42661717822c53185c0136ea54c2ef25eb7
		}
		hits_10_days {
			#	Last 10 days Hits
			set url http://www.wheresgeorge.com/ybd.php?args=5b7e6521216416f42265bdc8837bdb4cd0753ff329dfd3a934c8cf5c87711377c26bba4c89897ba0831893f750106cbd9a8d5ea727269cbcb279120a0f896b1490837d75589f357425ecbc6902c512657af11a107d33874bc78861fcd28c871b
		}
		recently_entered {
			#	Recently Entered
			set url http://www.wheresgeorge.com/ybd.php?PF%5Bpage_num%5D=${page}&PF%5Bitemsperpage%5D=250&PF%5Bsortby%5D=last_update&PF%5Bsortorder%5D=desc&cnt_tot_rows=250&args=e6cb7653d7a1944940709a3054b2b662febde97d096b98607f6e3e2ede1399f68c399852f3a1696f20abd621b4f80966a279840b1dadfbdea1ba6a9b379d7130eaae097a7bfc39ac035e54d902ca424bec7a2894137d36089c56fdb42a1e1100args=4e881bd6c73b6c26203e6d46b904bb650d447712671bbd3cd56565666ba60a35366d88647cc5d5b0eaceaef8af9a1328a279840b1dadfbdea1ba6a9b379d7130eaae097a7bfc39ac3c4f917f4442660422e41264b97c23adcafd894b78367bb9
		}
		all_entered {
			#	All Entered, 250 per page, page= $page
			set url http://www.wheresgeorge.com/ybd.php?PF%5Bpage_num%5D=${page}&PF%5Bitemsperpage%5D=250&PF%5Bsortby%5D=entry_time&PF%5Bsortorder%5D=desc&cnt_tot_rows=13000&args=bdddcff70ef7e573b2138767ed2ce0bf1da8ca0b3367e677414c3a6aef36b842e0bf47fe1ae7ff85aa3fdac5a382c5451f01ca7b998580f59e3bcbe8a65425715b4a4d0c91cb415d86c9901f404dfe4f10fa656bb677841879ac4dbefb88ad6a
		}
		all_entered_by_entries {
			#	all entered, sorted desc by # entries, 250 per page, page=$page
			set url http://www.wheresgeorge.com/ybd.php?PF%5Bpage_num%5D=${page}&PF%5Bitemsperpage%5D=250&PF%5Bsortby%5D=entcnt&PF%5Bsortorder%5D=desc&cnt_tot_rows=13000&args=44dc04324e0221810996653b9e2c2a3e76ae5d7b39d2d383d006fa8a39c47519a0917f82313b4a8876b89c969d249e1f1f01ca7b998580f59e3bcbe8a65425715b4a4d0c91cb415dbf9addd6c02e85b1962fef428cde2a2ef2e1d0ad4d830c5a
		}
		all_entered_by_series {
			#	all entered, sorted desc by series, 250 per page, page=$page
			set url http://www.wheresgeorge.com/ybd.php?PF%5Bpage_num%5D=${page}&PF%5Bitemsperpage%5D=250&PF%5Bsortby%5D=series&PF%5Bsortorder%5D=desc&cnt_tot_rows=13000&args=44dc04324e0221810996653b9e2c2a3e76ae5d7b39d2d383d006fa8a39c47519a0917f82313b4a8876b89c969d249e1f1f01ca7b998580f59e3bcbe8a65425715b4a4d0c91cb415dbf9addd6c02e85b1962fef428cde2a2ef2e1d0ad4d830c5a
		}
		wilds {
			# all wilds I have hit
			set url http://www.wheresgeorge.com/ybd.php?PF%5Bpage_num%5D=1&PF%5Bitemsperpage%5D=250&PF%5Bsortby%5D=entry_time&PF%5Bsortorder%5D=desc&cnt_tot_rows=250&args=9462fa6e5a6801c0f7e68152faf0949725abbfb205b5057736f31974c45354bbf8eb1c8977bccd825b272f08859afb1c8ca70ed650bda6717ce3cc215018b95795650223ddd068430bc64cc2f9136cfe36eddcc116a3827fb854658fa0230ec3
			set wild 1
		}
		all_hits {
			#	all hits, 250 per page, page=$page
			set url http://www.wheresgeorge.com/ybd.php?PF%5Bpage_num%5D=${page}&PF%5Bitemsperpage%5D=250&PF%5Bsortby%5D=last_update&PF%5Bsortorder%5D=desc&cnt_tot_rows=1371&args=e63aaf262516c5f0fc08b70ab4a70f3212d8733aa3c809821f8897ad1b3dacef533bccde646313902d16d03c1381fda56e5037e8478763fe479c9bfd9986ae328d1ebaaf6c15471ff259f0efe3e8be6edcd40d8445f3dbfd48bdc51c70a3b6c3
		}
		5_hits {
			#	all bills with 5 hits
			set url http://www.wheresgeorge.com/ybd.php?args=8867ed92866152e36c9e82ac283bba37ec8ad261d177044eb886ae26f1d89af8cd924fa579081efdeff12cbf1de68e1b30d46b357a38015e04123de8862f60c4222ee7fd04fa6742ed041f3ff7346855a986f44b0079fffb917de24d1880200b
		}
		4_hits {
			#	bills with 4 hits
			set url http://www.wheresgeorge.com/ybd.php?args=f549d1b055bc0e588305af86242cc8c0e8539ed7ed97ac0f59a22bab6f61a36a5d0e6e31c203754d018bda2907827c5330d46b357a38015e04123de8862f60c4222ee7fd04fa6742b0eb59b093c25512772bad9be81202bdcebdea30d8f6cf82
		}
		3_hits {
			#	bills with 3 hits
			set url http://www.wheresgeorge.com/ybd.php?args=392aea1c62c25af85a68bed945273b494b94adb7cc1ad082567431192fa284cf7f31fdb4ef59714458f16b1b8c5e9f4730d46b357a38015e04123de8862f60c4222ee7fd04fa67420015fdabd657abb433690be15012826e50dc328892e0955b
		}
		2_hits {
			# bills with 2 hits, 250 per page. page=$page
			set url http://www.wheresgeorge.com/ybd.php?PF%5Bpage_num%5D=${page}&PF%5Bitemsperpage%5D=250&PF%5Bsortby%5D=last_update&PF%5Bsortorder%5D=desc&cnt_tot_rows=1371&args=bce75fd5239788bc973812b2189d28bdd4b059b630b3769cac55dc640a105412e39f5ca8b7f5ab7efb1d8fff7cb3d50730d46b357a38015e04123de8862f60c4222ee7fd04fa6742256a9921c3e5772b70f2aa7226fdf41716f8711649252724
		}
		default {
			puts "command $command not recognized"
			exit
		}
	}

	puts "Fetching URL $url"
	puts "--------"

	set bill_report_delay 1450

	# set bill details URL
	set bill_details_prefix http://www.wheresgeorge.com/report.php?key=
	set bill_details_suffix &pf
	set cookies {mid=19745215; pagewidth=814; userkey=1ba8966ffd95bc9573d6534b039a44a8}

	lappend headers "Cookie" $cookies

	# init list of bills to check/fetch
	set bills_to_check {}
	set fetch_bills {}

	set database_busy 1

	while { $database_busy == 1} {
		set input [getPage $url $headers]

		set seconds 0
		set database_busy [regexp "The update should be complete in about (\[0-9\]+) Seconds" $input msg seconds]

		if { $database_busy } {
			set wait_seconds [expr $seconds + 30]
			puts "Database Updating, $msg, Waiting $wait_seconds"

			set wait [expr $wait_seconds * 1000]

			after $wait
		}
	}

	set origInput $input
	## code to pull bill info out of today's hit report
	
		##<TABLE width="100%" cellpadding="2" cellspacing="0" bordercolor="#999999" border=1 class="body">
		##<tr class="body" bgcolor="#dddddd">	<td colspan=9>Bills 1 thru 2 out of 2 total bills</td>
		##</tr>
		##<tr class="body" bgcolor="#dddddd">	<td align=center>Rank</td>
		##	<td align=center>Denom</td>
		##	<td align=center>Series</td>
		##	<td align=center>Serial Number<br>Click for Report</td>
		##	<td align=center>Total<br>Entries</td>
		##	<td align=center>Total<br>Hits</td>
		##	<td align=center>Last Update</td>
		##	<td align=center>Bill<br>Note<br>Editor</td>
		##	<td align=center>Zip Code<br>Editor</td>
		##</tr>
		##<tr class="ybbody" bgcolor="white">	<td align=center>1.</td>
		##                              @@OR@@  <td align=center bgcolor=#eeeeee >1.</td>
		##	<td align=center>Ten</td>
		##	<td align=center>1999</td>
		##	<td align=center><a href='report.php?key=2f2c9695ee2609c34a0bbf9c80b8370b7a9a9b86adadca27&entcnt=1'>BF887---93A</a></td>
		##	<td align=center>2</td>
		##	<td align=center>1</td>
		##	<td align=center>Sep-06-2007</td>
		##	<td align=center><a href=edit_note.php?args=976afde95f9c67bd463637b0ef635d98f39909520b46488099d7a062229985f8c7639aee47e9e5269789fbb0370864c5f1b435e748cb6cb94348a8c9fdf9919494620f69ef918e0b67605924149ec93b85754c1a55c525dc693b31c5a363141e8b030995f3d4d86cba09567a74983c8a4eadae798480bb1053f879d30b3c76e9c63341d5cb9b995d0d3f916745366830>Edit</a>
		##	<a href='javascript:alert("got from Salem Rd Beneficial Bank, Burlington, NJ
		##
		##Bill #11,144 entered
		##
		##Please enter a note to make this bills trek more interesting!");'><IMG border=0 ALT='got from Salem Rd Beneficial Bank, Burlington, NJ
		##
		##Bill #11,144 entered
		##
		##Please enter a note to make this bills trek more interesting!' SRC=images/notes.gif></a></td>
		##	<td align=center><a href=edit_zip.php?args=976afde95f9c67bd463637b0ef635d98f39909520b46488099d7a062229985f8c7639aee47e9e5269789fbb0370864c5f1b435e748cb6cb94348a8c9fdf9919494620f69ef918e0b67605924149ec93b85754c1a55c525dc693b31c5a363141e8b030995f3d4d86cba09567a74983c8a4eadae798480bb1053f879d30b3c76e9c63341d5cb9b995d0d3f916745366830>08016</a></td>
		##</tr>
		##<tr class="ybbody" bgcolor="white">	<td align=center>2.</td>
		##	<td align=center>One</td>
		##	<td align=center>2001</td>
		##	<td align=center><a href='report.php?key=92fb618c30102791558e39efa4d0abee891d2bd8c0f79ebd&entcnt=1'>B4097---4C</a></td>
		##	<td align=center>2</td>
		##	<td align=center>1</td>
		##	<td align=center>Sep-06-2007</td>
		##	<td align=center><a href=edit_note.php?args=0872972d3a64bff8294c4e7614df09adb322ef6e5ae003f65e3beccdf2007b634e57373e06780daa896933f9750bffae3492b992e014897c800ffb2a1baabd58d60f79a10c6982afa201a05edf14f44eec8cdafb8fcf34379048fb7c5a66cb1f0144a07ab5ed96fd9aea58a83ccdc1642048d62acbe3e82753f879d30b3c76e9c63341d5cb9b995d0d3f916745366830>Edit</a><a href='javascript:alert("got from FMS Bank, Burlington, NJ
		##
		##Bill #10,442 entered
		##
		##Please enter a note to make this bills trek more interesting!");'><IMG border=0 ALT='got from FMS Bank, Burlington, NJ
		##
		##Bill #10,442 entered
		##
		##Please enter a note to make this bills trek more interesting!' SRC=images/notes.gif></a></td>
		##	<td align=center><a href=edit_zip.php?args=0872972d3a64bff8294c4e7614df09adb322ef6e5ae003f65e3beccdf2007b634e57373e06780daa896933f9750bffae3492b992e014897c800ffb2a1baabd58d60f79a10c6982afa201a05edf14f44eec8cdafb8fcf34379048fb7c5a66cb1f0144a07ab5ed96fd9aea58a83ccdc1642048d62acbe3e82753f879d30b3c76e9c63341d5cb9b995d0d3f916745366830>08016</a></td>
		##</tr>
		#</table>

	set bill_count 1

	set start [string first "ybbody" $origInput]
	set end [string first "Back to Top" $origInput]
	set data [string range $input $start $end]
	
	# remove highlighted rows...these are "favorites', but make parsing dificult
	set new_data $data
	regsub -all " bgcolor=#eeeeee " $data "" new_data
	set data $new_data
	
	set orig_data $data

	set rank 0
	set series 0
	set serial ""
	set bill_entries 0
	set bill_hits 0
	set date 0
	set note_edit ""
	set note ""
	set zip_edit ""
	set vars {rank denom series key serial bill_entries bill_hits date note zip}
	set starts {{<td align=center>}
			{<td align=center>}
			{<td align=center>}
			{key=}
			{'>}
			{<td align=center>}
			{<td align=center>}
			{<td align=center>}
			{javascript:alert("}
			{<td align=center>}}
	set ends {{</td>}
			{</td>}
			{</td>}
			{&entcnt=}
			{</a>}
			{</td>}
			{</td>}
			{</td>}
			{");}
			{</td>}}

	set ofile [open "$maps_dir/ybd_today_data_feed.txt" a]

	log $ofile [clock format [clock seconds] -format %Y_%m_%d]

	set output_vars ""
	while { [string length $data] > 150} {
		foreach v $vars s $starts e $ends {
			set st_len [string length $s]
			set start [expr [string first $s $data] + $st_len]
			set data [string range $data $start end]
			set end [expr [string first $e $data] -1]
			set data_value [string range $data 0 $end]
			set $v [escape_sql_string $data_value]
			lappend output_vars $v $end $data_value
			if { $v == "zip" } {
				set st [expr [string first > $data_value] + 1]
				set en [expr [string last < $data_value] - 1]
				set zip [string range $data_value $st $en]
			}

			set data [string range $data [expr $end + 3] end]
		}

		lappend bills_to_check $key
		set bill_info($key) [list $denom $series $serial $key $bill_entries $bill_hits $date]

		set next_row [string first "ybbody" $data]
		if { $next_row < 0 } {
			set data ""
		} else {
			set data [string range $data $next_row end]
		}

		incr bill_count
	}

	set bills_parsed [incr bill_count -1]

	set bill_count 1	
	set bills_updated 0

	foreach bill_key $bills_to_check {
		set change [insert_or_update_bill $bill_info($bill_key) $wild $handle $ofile]

		if { $change || $fetch_all_hits} {
			incr bills_updated
			lappend fetch_bills $bill_key
		}

		puts "$bill_count CHANGE= $change, $bill_key"
		#puts "           $denom, $series, $serial"
		log $ofile "CHANGE= $change"
		log $ofile "DATA:"
		log $ofile "rank:$rank"
		log $ofile "denom: $denom"
		log $ofile "series $series"
		log $ofile "key: $bill_key"
		log $ofile "serial: $serial"
		log $ofile "entries: $bill_entries"
		log $ofile "hits: $bill_hits"
		log $ofile "date: $date"
		log $ofile "note: $note"
		log $ofile "zip: $zip"
		log $ofile "========================"

		incr bill_count
	}

	close $ofile
 
	set filename "$maps_dir/ybd_today_data_[clock format [clock seconds] -format "%a"].htm"
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
	puts $ofile "===================\ninput=$orig_data\n==================\n"

	close $ofile
	## code to pull info out of bill detail report.

	set origInput $input
	## Parse out the data from this format:
		##<TABLE width="100%" cellpadding="2" cellspacing="0" bordercolor="#999999" border=1 class="body">
		##<tr class="tabletitle" bgcolor="#669933">	<td colspan=7><font color=white size=2>Ten Dollar Bill, Serial# <b>BF887---93A</b> Series: <b> 1999 </b><!-- alevel=10788602--></td>
		##</tr>
		##<tr class="tabletitle" bgcolor="#669933">	<td colspan=7><font color=white size=2>This bill has travelled 18 Miles in 11 Days, 19 Hrs, 32 Mins at an average of 1.5 Miles per day.&nbsp;&nbsp;&nbsp;<br>It is now 18 miles from its starting location.</td>
		##</tr>
		##<tr class="tabletitle" bgcolor="#669933">	<td colspan=7><font color=white size=2>This list is in reverse-chronological order</td>
		##</tr>
		##<tr class="tabletitle" bgcolor="#669933">	<td >Entry Time<br>(Local Time of Zip)</td>
		##	<td >Location, State/Province<br>(Green=USA, Blue=Canada, Purple=International)</td>
		##	<td >Travel Time<BR>(from previous entry)</td>
		##	<td >Distance<BR>(Miles)<SUP>*</SUP></td>
		##	<td >Average<BR>Speed<br>(Miles<br>Per Day)</td>
		##	<td >Send<br>Anon<br>email</td>
		##	<td >View<br>User<br>Profile</td>
		##</tr>
		##<tr class="printer_friendly" bgcolor="white">	<td >Sep-06-07 12:07&nbsp;PM<NOBR>(-5)</NOBR></td>
		##	<td ><script>document.write("<A  HREF=\"javascript:popup_win('flags/nj.jpg',209,310,'no');\"><IMG border=0 width=30 height=19 SRC=\"flags/nj.jpg\">&nbsp;</a>");</script><noscript><A HREF=flags/nj.jpg target=_blank><IMG border=0 width=30 height=19 SRC="flags/nj.jpg">
		##	&nbsp;</a></noscript>Pennington, NJ&nbsp;</b>&nbsp;(08534/Mercer)&nbsp;&nbsp;<span class=small><a target=_blank href=http://www.mapquest.com/maps/map.adp?zoom=3&formtype=address&searchtype=address&country=US&zipcode=08534>map</a></span></td>
		##	<td >11 Days, 19 Hrs, 32 Mins</td>
		##	<td align=center>18</td>
		##	<td align=center>1.5</td>
		##	<td align=center>&nbsp;</td>
		##	<td align=center>&nbsp;</td>
		##</tr>
		##<tr class="note" bgcolor="#777777">	<td >User's Note</td>
		##	<td colspan=6>company cafateria</td>
		##</tr>
		##<tr class="printer_friendly" bgcolor="white">	<td >Aug-25-07 04:35&nbsp;PM<NOBR>(-5)</NOBR></td>
		##	<td ><script>document.write("<A  HREF=\"javascript:popup_win('flags/nj.jpg',209,310,'no');\"><IMG border=0 width=30 height=19 SRC=\"flags/nj.jpg\">&nbsp;</a>");</script><noscript><A HREF=flags/nj.jpg target=_blank><IMG border=0 width=30 height=19 SRC="flags/nj.jpg">&nbsp;</a></noscript>Burlington, NJ&nbsp;</b>&nbsp;(08016/Burlington)&nbsp;&nbsp;<span class=small><a target=_blank href=http://www.mapquest.com/maps/map.adp?zoom=3&formtype=address&searchtype=address&country=US&zipcode=08016>map</a></span></td>
		##	<td >Initial Entry</td>
		##	<td align=center>n/a</td>
		##	<td align=center>n/a</td>
		##	<td align=center><a href=anon_email.php?args=c2ada231f228c06b77191b784395cfdb6c46c1b9e526311a4e0f50b76c73da5e724a34432854267708ea478ec2daf8f6ff6c2d510987895ef35f1424578e5a1a6df1952d9a9da53a1136ca1590ee0b8314f464eaee609b9632042561845fa7d2b7b5d26ad44a8c21947ca157ee12d570ae90d38fa8bb7fd0e47a12c789f5b9b7df6a1c395a2814634903afec4c099dd8a6cd7814686780f9ef30c5f338283ca124751cfc2d033cc0><IMG  border=0 SRC=images/email1.gif></a></td>
		##	<td align=center><script>document.write("<A  HREF=\"javascript:popup_win('user_profile_popup.php?ukey=1c48871d2481b356e00789340b46fc0f',600,800,'yes');\"><IMG border=0 SRC=images/profile1.gif></a>");</script><noscript><A HREF=user_profile_popup.php?ukey=1c48871d2481b356e00789340b46fc0f target=_blank><IMG border=0 SRC=images/profile1.gif></a></noscript></td>
		##</tr>
		##<tr class="note" bgcolor="#777777">	<td >User's Note <a href=edit_note.php?args=976afde95f9c67bd463637b0ef635d98f39909520b46488099d7a062229985f8c7639aee47e9e5269789fbb0370864c5f1b435e748cb6cb94348a8c9fdf9919494620f69ef918e0b67605924149ec93b85754c1a55c525dc693b31c5a363141e8b030995f3d4d86cba09567a74983c8a4eadae798480bb1053f879d30b3c76e9c63341d5cb9b995d0d3f916745366830>[Edit]</a></td>
		##	<td colspan=6>got from Salem Rd Beneficial Bank, Burlington, NJ<br />
		##<br />
		##Bill #11,144 entered<br />
		##<hr /><br />
		##<b style="padding:3px;background-color:#ffd;color:#900;">Please enter a note to make this bill's trek more interesting!</b><hr><b>Please become a member of WheresGeorge.com, it's free, and you can track this bill's journey.</b><hr /><img src="http://bankoffrank.com/cgi-bin/bill_paths.png?size=375" /><br />Bill path maps from<a href="http://bankoffrank.com/">Bank of Frank</a></td>
		##</tr>
		##</table>

# test bill		
#append fetch_bills {
#2d1dcca5bbdfc944ccde00131133803c237e38bd5d2a94a2
#}

#set fetch_bills {
#2d1dcca5bbdfc944ccde00131133803c237e38bd5d2a94a2
#}

	set ofile [open "$maps_dir/ybd_today_data_feed.txt" a]

	log $ofile [clock format [clock seconds] -format %Y-%m-%d]

	set bill_count 1

	foreach bill_id $fetch_bills {

		puts "-----==----==----==----==-----"
		puts "$bill_count Getting Details for $bill_id"
		log $ofile "-----==----==----==----==-----"
		log $ofile "$bill_id"

		set bill_url "${bill_details_prefix}+${bill_id}+${bill_details_suffix}"
	
		set input [getPage $bill_url $headers]
		set origInput $input
	
		set start [string first "printer_friendly" $origInput]
		set end [string first "Back to Top" $origInput]
		set data [string range $input $start $end]
		set orig_data $data

#puts $ofile "=====================================+++++++++++++++++++"
#puts $ofile $data
#puts $ofile "=====================================+++++++++++++++++++"

		remove_entries $bill_id $handle

		# use this to parse line 1
		set vars {entry_time city_state_zip_county distance miles_per_day}
		set starts {{<td >} {<td >}  {<td align=center>} {<td align=center>}}
		set ends {{<NOBR>} </td> {</td>} {</td>}}

		# use this to parse line 2, if it exists..will check for "User note" test
		set vars2 {note}
		set starts2 {{<td colspan=6>}}
		set ends2 {{</td>}}

		set output_vars ""
		while { [string length $data] > 100} {

			set entry_time "0000-00-00"
			set city_state_zip_county ""
			set city ""
			set county ""
			set state ""
			set zip ""
			set distance 0
			set miles_per_day 0
			set note ""

			foreach v $vars s $starts e $ends {
				set st_len [string length $s]
				set start [expr [string first $s $data] + $st_len]

				set data [string range $data $start end]
				set end [expr [string first $e $data] -1]
				set data_value [string range $data 0 $end]

				set $v [escape_sql_string $data_value]
				lappend output_vars $v $end [string range $data 0 $end]

				set data [string range $data [expr $end -1] end]
			}

			set next_entry [string first "<tr class=\"printer_friendly" $data]
			set next_note [string first "<tr class=\"note" $data]
			if { $next_entry > $next_note || $next_entry < 0 } {
				foreach v $vars2 s $starts2 e $ends2 {
					set st_len [string length $s]
					set start [expr [string first $s $data] + $st_len]
					set data [string range $data $start end]
					set end [expr [string first $e $data] -1]
					set data_value [string range $data 0 $end]

					set $v [escape_sql_string $data_value]
					lappend output_vars $v $end [string range $data 0 $end]
	
					set data [string range $data [expr $end -1] end]
				}
			}

			#puts $ofile $city_state_zip_county
			# fix up city/state/zip/county, if there is a flag icon
			set data_list [expand_city_state_zip_county $city_state_zip_county]
			
			set city [lindex $data_list 0]
			set state [lindex $data_list 1]
			set zip [lindex $data_list 2]
			set county [lindex $data_list 3]
			
			# fix up date
			regsub "&nbsp;" $entry_time " " new_entry_time
			set entry_time $new_entry_time

			set entry_time [wg_datetime_to_mysql_datetime $entry_time]

			log $ofile ""
			log $ofile "DATA:"
			log $ofile "entry_time:$entry_time"
			log $ofile "city: $city"
			log $ofile "state: $state"
			log $ofile "zip: $zip"
			log $ofile "county: $county"
			log $ofile "note: $note"
			log $ofile "========================"
			
			if { ![string is double $distance] } {
				set distance 0
			}
			if { ![string is double $miles_per_day] } {
				set miles_per_day 0
			}

			set result [::mysql::sel $handle "select * from bills where id='$bill_id'" -list]
			#puts "checking before insert hit $bill_id=\{$result\}"
			puts "hit=$entry_time, found hit entry [lindex [lindex $result 0] 5], last hit [lindex [lindex $result 0] 6]" 
			
			if { [llength $result] != 0 } {
				set query "select * from hits where bill_id='$bill_id' and date='$entry_time'"

				set result [::mysql::sel $handle $query -list]
				if { [llength $result] == 0 } {

					set query "insert into hits set date='$entry_time',city='$city',county='$county',state='$state',zip='$zip',distance=$distance,miles_per_day=$miles_per_day,note='$note',bill_id='$bill_id'"


					::mysql::query $handle "$query"

				} else {
					puts "Hit for $bill_id ALREADY in DB"
				}
				
				update_last_hit_date $bill_id $entry_time $handle

				update_entry_date $bill_id $entry_time $handle

			} else {
				puts "Bill $bill_id **NOT** in DB"
			}

			set next_row [string first "<tr class=\"printer_friendly" $data]
			if { $next_row < 0 } {
				set data ""
			} else {
				set data [string range $data $next_row end]
			}
		}
		after $bill_report_delay
		incr bill_count
	}	

	set bill_hits_checked [incr bill_count -1]

	log $ofile "------------"

	puts "Summary:"
	puts "  Bills Parsed: $bills_parsed"
	puts "  Bills Updated: $bills_updated"
	puts "  Bill Hits Updated: $bill_hits_checked"

	close $ofile

	set filename "$maps_dir/ybd_today_data_[clock format [clock seconds] -format "%a"].htm"
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

	close $ofile

	# close DB connection
	::mysql::close $handle
