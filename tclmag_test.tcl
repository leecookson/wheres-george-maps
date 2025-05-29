#!/bin/tclsh 

# Load the tclMagick module
#

set dir /usr/bin

package ifneeded TclMagick 0.41 [list load [file join $dir TclMagick[info sharedlibextension]]]

# Create wand & draw objects
#
set wand [magick::wand create]
set draw [magick::draw create]

# Load & enlarge a PNG
#
$wand ReadImage CC_HIT_MAP.png
$wand ResizeImage 500 500 cubic
# Draw a red "Tcl/Tk" rotated by 45°
#
$draw push graph
     $draw SetStrokeWidth 1
     $draw SetStrokeColorString "red"
     $draw SetFillColorString "red"
     $draw SetFontSize 18
     $draw Annotation -97 170 "Tcl/Tk"
$draw pop graph
$draw Rotate -45

$wand DrawImage $draw

# Write the image in different file formats
#
$wand WriteImage sample.jpg
$wand WriteImage sample.gif
$wand WriteImage sample.pdf

# Delete wand & draw objects
#
magick::draw delete $draw
magick::wand delete $wand 