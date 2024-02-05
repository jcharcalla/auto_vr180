#!/bin/bash

#
# A script for creating vr180 stereoscopic video.
#
# Requires.
#  - ffmpeg
#  - imagemagick
#  - hugin
#
# NOTE: This script uses the flat frame method found in the 
#       "An Introduction to FFmpeg, ..." book
#       by Michael Koch which can be found here
#       http://www.astro-electronic.de/FFmpeg_Book.pdf
#
# Copyright 2024 - Jason Charcalla
#
# Date: 1/31/2024
# Version: 0.01.1
# 
# Changelog
# 1/31/2024: Initial version
#
#
# To Do:
# - video syncronization
# - fine tune left/right ypr
# - more arguments (resolution)
# - hardware acceleration
# - debug mode
# - cleanup
# - audio support
# - platform tagging
# - containerization
# - color correction / grading
#
PROG_NAME=$(basename "$0")

# How too
print_usage() {
	cat <<EOF
#
# Requires a Left and Right video and output to be specified
#
#  -L # Left Video
#  -R # Right Video
#  -l # Left flat video
#  -r # Right flat video
#  -f # Input field of view
#  -F # Desired output fps
#  -o # Output filename prefix, will have left/right.png appended
#  -O # Set the output file path and name.
#  -m # Re-use flat, mask, and alpha chanels from a previous invocation
#     # you must use the same '-o' (Output filename prefix) option.
#  -H # Provide a Hugin PTO file instead of calculating a new one.
#  -c # Use a concatinated ffmpeg video list. NOTE: you must use 
#     # '-m' and '-H' with this flag. Specify the lists instead of l/r video
#     # Note: this seems to oomkill with a large number of files even with 16gb ram
#
# ./${PROG_NAME} -h
#
# EX: 
./auto_vr180.sh \
     -l /tmp/flats/4000x3000_left-flat-20240130215831.mjpeg \
     -r /tmp/flats/4000x3000_right-flat-20240130214800.mjpeg \
     -L /tmp/outdoor_1/4000x3000_left-01-20240128140001.mjpeg \
     -R /tmp/outdoor_1/4000x3000_right-01-20240128140001.mjpeg \
     -o 6000x3000/outdoor_1 \
     -O /tmp/6000x3000-final-20240128140001.mp4

# Or to re-use alpha chanels, masks and the Hugin file from a previous ussage.

./auto_vr180.sh \
     -l /tmp/flats/4000x3000_left-flat-20240130215831.mjpeg \
     -r /tmp/flats/4000x3000_right-flat-20240130214800.mjpeg \
     -L /tmp/outdoor_1/4000x3000_left-01-20240128140001.mjpeg \
     -R /tmp/outdoor_1/4000x3000_right-01-20240128140001.mjpeg \
     -o 6000x3000-outdoor_1 \
     -m 1 \
     -H /tmp/outdoor_1/6000x3000-outdoor_1-hugin-with_cp-cleaned-lines-optomized.pto \
     -O /tmp/outdoor_1/6000x3000-final-20240128140001-copy.mp4

#
#
EOF
exit 1
}
## Default options
FRAME_LIMIT=128
ALPHA_CONTRAST_STRETCH="3%x77%"
ALPHA_COLORS=8

YAW="0"
PITCH="0"
ROLL="0"

SCALE_H_RES=3000 # 3000
SCALE_V_RES=2250 # 2250

H_RES=3000
V_RES=3000

#IN_FOV=202 # Input field of view
IN_FOV=202 # Input field of view
PTS="0.5" # need to keep it below .2 because input is only 12fps
OUTPUT_FPS=60
OUT_H_FOV=180 # Output horizontal FOV (typically 180 but could be 360)
OUT_V_FOV=180 # Out put verticle FOV (Ussually always 180, and not > 180)

PTO_FILE=none
HUGIN_FILE=0
CONCAT=0

REUSE_MASK=0

YPR_MODIFY=0

if [ "$#" -le 3 ]; then
	    print_usage
fi

while getopts h?l:r:L:R:o:O:s:F:c:m:f:p:x:y:H: arg ; do
	case $arg in
		l) LEFT_FLAT=$OPTARG;;
		r) RIGHT_FLAT=$OPTARG;;
		L) LEFT_VIDEO=$OPTARG;;
		R) RIGHT_VIDEO=$OPTARG;;
		o) OUTPUT_PREFIX=$OPTARG;;
		O) OUTPUT_FILE=$OPTARG;;
		s) PTS=$OPTARG;;
		F) OUTPUT_FPS=$OPTARG;;
		c) CONCAT=1;;
		m) REUSE_MASK=1;;
		f) IN_FOV=$OPTARG;;
		H) PTO_FILE=$OPTARG
		   HUGIN_FILE=1;;
		y) YAW=$OPTARG
	           YPR_MODIFY=1;;
		p) PITCH=$OPTARG
                   YPR_MODIFY=1;;
		x) ROLL=$OPTARG
                   YPR_MODIFY=1;;
		h|\?) print_usage; exit ;;
	esac
done

## More defaults based on args
OUTPUT_DIR=$(dirname ${LEFT_VIDEO})
FLAT_DIR=$(dirname ${LEFT_VIDEO})


cat <<EOF
###
###
#
# Inputs were... 
# LEFT_FLAT: ${LEFT_FLAT}
# RIGHT_FLAT: ${RIGHT_FLAT}
# LEFT_VIDEO: ${LEFT_VIDEO}
# RIGHT_VIDEO: ${RIGHT_VIDEO}
# OUTPUT_PREFIX: ${OUTPUT_PREFIX}
#
###
###
EOF

if [ ${REUSE_MASK} -eq 0 ]
then	
	## create average frame png

	echo "Averaging left flat frame image to png file."
	# I've remove the desaturate "saturation=0" becase my images have a fisheye color cast issue.
	#ffmpeg -i ${LEFT} -vf "tmix=128,format=rgb48,eq=saturation=0" -frames 1 -y ${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_tmp.png
	ffmpeg -i ${LEFT_FLAT} -vf "tmix=${FRAME_LIMIT},format=rgb48" -frames 1 -y ${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_tmp.png

	echo "Averaging right flat frame image to png file."
	ffmpeg -i ${RIGHT_FLAT} -vf "tmix=${FRAME_LIMIT},format=rgb48" -frames 1 -y ${OUTPUT_DIR}/${OUTPUT_PREFIX}-right_tmp.png

	## Normalize
	# This could also be done with imagemagick, I should add an example comment.
	# https://legacy.imagemagick.org/Usage/color_mods/#normalize

	echo "Normalizing left flat image."
	ffmpeg -i ${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_tmp.png -vf drawbox=w=1:h=1:color=black,normalize -frames 1 -y ${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_normalized.png

	echo "Normalizing right flat image."
	ffmpeg -i ${OUTPUT_DIR}/${OUTPUT_PREFIX}-right_tmp.png -vf drawbox=w=1:h=1:color=black,normalize -frames 1 -y ${OUTPUT_DIR}/${OUTPUT_PREFIX}-right_normalized.png


	## Create alpha channels

	echo "Creating left alpha channel for fisheye masks"

	convert ${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_normalized.png -contrast-stretch ${ALPHA_CONTRAST_STRETCH} -colorspace gray +dither -posterize ${ALPHA_COLORS} -alpha copy ${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_alpha.png


	convert ${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_normalized.png ${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_alpha.png -compose DstOut -composite PNG32:${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_border_alpha.png


	convert ${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_normalized.png -contrast-stretch ${ALPHA_CONTRAST_STRETCH} -colorspace gray +dither -posterize ${ALPHA_COLORS} -negate -alpha copy ${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_inverse_alpha.png

	convert ${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_normalized.png ${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_inverse_alpha.png -compose DstOut -composite PNG32:${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_normalized_alpha.png

	echo "Creating right alpha channel for fisheye masks"

	convert ${OUTPUT_DIR}/${OUTPUT_PREFIX}-right_normalized.png -contrast-stretch ${ALPHA_CONTRAST_STRETCH} -colorspace gray +dither -posterize ${ALPHA_COLORS} -alpha copy ${OUTPUT_DIR}/${OUTPUT_PREFIX}-right_alpha.png


	convert ${OUTPUT_DIR}/${OUTPUT_PREFIX}-right_normalized.png ${OUTPUT_DIR}/${OUTPUT_PREFIX}-right_alpha.png -compose DstOut -composite PNG32:${OUTPUT_DIR}/${OUTPUT_PREFIX}-right_border_alpha.png


	convert ${OUTPUT_DIR}/${OUTPUT_PREFIX}-right_normalized.png -contrast-stretch ${ALPHA_CONTRAST_STRETCH} -colorspace gray +dither -posterize ${ALPHA_COLORS} -negate -alpha copy ${OUTPUT_DIR}/${OUTPUT_PREFIX}-right_inverse_alpha.png

	convert ${OUTPUT_DIR}/${OUTPUT_PREFIX}-right_normalized.png ${OUTPUT_DIR}/${OUTPUT_PREFIX}-right_inverse_alpha.png -compose DstOut -composite PNG32:${OUTPUT_DIR}/${OUTPUT_PREFIX}-right_normalized_alpha.png
else
	echo "Set to re-use mask and alpha channel files from a previous invocation."
fi



if [ ${HUGIN_FILE} -eq 0 ]
then
	
	## Create HUGIN PTO file
	# sudo add-apt-repository ppa:ubuntuhandbook1/apps
	# sudo apt install hugin

	# extract single frame for hugin
	echo "Extracting Hugin frames for camera calibration."

	ffmpeg -y -accurate_seek -ss 1 -i ${LEFT_VIDEO} -vf scale=2000x1500 \
	-compression_algo raw -pix_fmt rgb24 -vframes 1 ${OUTPUT_DIR}/${OUTPUT_PREFIX}-left-calibration.tiff

	ffmpeg -y -accurate_seek -ss 1 -i ${RIGHT_VIDEO} -vf scale=2000x1500 \
	-compression_algo raw -pix_fmt rgb24 -vframes 1 ${OUTPUT_DIR}/${OUTPUT_PREFIX}-right-calibration.tiff

	echo "Creating HUGIN pto file."
	pto_gen -p 2 -f 202 -o ${OUTPUT_DIR}/${OUTPUT_PREFIX}-hugin.pto \
		${OUTPUT_DIR}/${OUTPUT_PREFIX}-left-calibration.tiff \
		${OUTPUT_DIR}/${OUTPUT_PREFIX}-right-calibration.tiff

	echo "Detecting contol points with HUGIN."
	cpfind --fullscale --celeste --multirow -n 2 \
		-o ${OUTPUT_DIR}/${OUTPUT_PREFIX}-hugin-with_cp.pto \
		${OUTPUT_DIR}/${OUTPUT_PREFIX}-hugin.pto

	echo "Cleaning contol points with HUGIN."
	cpclean -o ${OUTPUT_DIR}/${OUTPUT_PREFIX}-hugin-with_cp-cleaned.pto \
		${OUTPUT_DIR}/${OUTPUT_PREFIX}-hugin-with_cp.pto

	echo "Finding lines in images with HUGIN (for alignment)."
	linefind -o ${OUTPUT_DIR}/${OUTPUT_PREFIX}-hugin-with_cp-cleaned-lines.pto \
		${OUTPUT_DIR}/${OUTPUT_PREFIX}-hugin-with_cp-cleaned.pto

	echo "Optimize image with HUGIN."
	autooptimiser -a -p -s \
		-o ${OUTPUT_DIR}/${OUTPUT_PREFIX}-hugin-with_cp-cleaned-lines-optomized.pto \
        	${OUTPUT_DIR}/${OUTPUT_PREFIX}-hugin-with_cp-cleaned-lines.pto

	# This seems to produce random results so it cant be used with manual adjustments.
	#echo "Straighten with HUGIN (this may cause more trouble than good)"
	#pano_modify -c -s --canvas=${H_RES}x${V_RES} \
	#	-o ${OUTPUT_DIR}/${OUTPUT_PREFIX}-hugin-with_cp-cleaned-lines-optomized-modified.pto \
	#	${OUTPUT_DIR}/${OUTPUT_PREFIX}-hugin-with_cp-cleaned-lines-optomized.pto

	
	# remove link if its already there
	rm ${OUTPUT_DIR}/${OUTPUT_PREFIX}-hugin-calibrated.pto

	# Link the PTO we want to use to the final calibration PTO

	ln -s ${OUTPUT_DIR}/${OUTPUT_PREFIX}-hugin-with_cp-cleaned-lines-optomized.pto ${OUTPUT_DIR}/${OUTPUT_PREFIX}-hugin-calibrated.pto

	#ln -s ${OUTPUT_DIR}/${OUTPUT_PREFIX}-hugin-with_cp-cleaned-lines-optomized-modified.pto ${OUTPUT_DIR}/${OUTPUT_PREFIX}-hugin-calibrated.pto
else
	echo "using existing pto file ${PTO_FILE}"
	# remove link if its already there
	rm ${OUTPUT_DIR}/${OUTPUT_PREFIX}-hugin-calibrated.pto


	# Link the provided PTO we want to use to the final calibration PTO
	ln -s ${PTO_FILE} ${OUTPUT_DIR}/${OUTPUT_PREFIX}-hugin-calibrated.pto
fi

echo "non adjusted yaw, pitch, roll for l/r"
cat ${OUTPUT_DIR}/${OUTPUT_PREFIX}-hugin-calibrated.pto | grep right | cut -f 14,15,16 -d " "
cat ${OUTPUT_DIR}/${OUTPUT_PREFIX}-hugin-calibrated.pto | grep left | cut -f 14,15,16 -d " "

# adjust the yaw pitch or roll
if [ ${YPR_MODIFY} -eq 1 ]
then
        pano_modify --rotate=${YAW},${PITCH},${ROLL} -o ${OUTPUT_DIR}/${OUTPUT_PREFIX}-hugin-calibrated.pto ${OUTPUT_DIR}/${OUTPUT_PREFIX}-hugin-calibrated.pto
fi

echo "Extracting Yaw, Pitch, Roll from Hugin PTO file."
# Note: these are reveresed on purpose, not sure why but this is the way it works.
L_YPR=$(cat ${OUTPUT_DIR}/${OUTPUT_PREFIX}-hugin-calibrated.pto | grep right | cut -f 14,15,16 -d " ")
R_YPR=$(cat ${OUTPUT_DIR}/${OUTPUT_PREFIX}-hugin-calibrated.pto | grep left | cut -f 14,15,16 -d " ")

L_ROLL=$(echo "${L_YPR}" | cut -f 1 -d " " | tr -d 'r' | cut -c1-12)
L_PITCH=$(echo "${L_YPR}" | cut -f 2 -d " " | tr -d 'p' | cut -c1-12)
L_YAW=$(echo "${L_YPR}" | cut -f 3 -d " " | tr -d 'y' | cut -c1-12)

R_ROLL=$(echo "${R_YPR}" | cut -f 1 -d " " | tr -d 'r' | cut -c1-12)
R_PITCH=$(echo "${R_YPR}" | cut -f 2 -d " " | tr -d 'p' | cut -c1-12)
R_YAW=$(echo "${R_YPR}" | cut -f 3 -d " " | tr -d 'y' | cut -c1-12)

echo "Left - Yaw=${L_YAW}, Pitch=${L_PITCH}, Roll=${L_ROLL}"
echo "Right - Yaw=${R_YAW}, Pitch=${R_PITCH}, Roll=${R_ROLL}"


# Create VIDEO
# NOTE:  capture commands that have time code
#echo "sleep 0.1; /usr/bin/ffmpeg -y -f v4l2 -framerate 15 -video_size 4000x3000 -input_format mjpeg -ts mono2abs -i /dev/video0 -c:v copy -copyts -f segment -segment_atclocktime 1 -segment_time 10 -segment_format mp4 -fflags +genpts -reset_timestamps 0 -strftime 1 -avoid_negative_ts 1 "/charky_pool/tmp/dump/vid_test2/outdoor_1/4000x3000_left-01-%Y%m%d%H%M%S.mjpeg" > /home/jason/left.txt" | at 01:04pm -M
#echo "/usr/bin/ffmpeg -y -f v4l2 -framerate 15 -video_size 4000x3000 -input_format mjpeg -ts mono2abs -i /dev/video2 -c:v copy -copyts -f segment -segment_atclocktime 1 -segment_time 10 -segment_format mp4 -fflags +genpts -reset_timestamps 0 -strftime 1 -avoid_negative_ts 1 "/charky_pool/tmp/dump/vid_test2/outdoor_1/4000x3000_right-01-%Y%m%d%H%M%S.mjpeg" > /home/jason/right.txt" | at 01:04pm -M

cat <<EOF
###
### Running the following ffmpeg command.
###

ffmpeg -y -v info \
-i ${LEFT_VIDEO} \
-loop 0 -i ${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_normalized_alpha.png \
-loop 0 -i ${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_border_alpha.png \
-i ${RIGHT_VIDEO} \
-loop 0 -i ${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_normalized_alpha.png \
-loop 0 -i ${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_border_alpha.png \
-filter_complex \
"[0:v]setpts=${PTS}*PTS,fps=${OUTPUT_FPS},scale=${SCALE_H_RES}x${SCALE_V_RES},format=gbrp[l_scaled]; \
[1:v]scale=${SCALE_H_RES}x${SCALE_V_RES}[l_na_scaled]; \
[l_scaled][l_na_scaled]blend=all_mode=divide,format=yuv420p[l_blended]; \
[2:v]scale=${SCALE_H_RES}x${SCALE_V_RES}[l_ba_scaled]; \
[l_blended][l_ba_scaled]overlay[l_over]; \
[l_over]scale=${SCALE_H_RES}x${SCALE_V_RES},pad=${H_RES}:${V_RES}:(ow-iw)/2:(oh-ih)/2,v360=input=fisheye:ih_fov=${IN_FOV}:iv_fov=${IN_FOV}:h_fov=${OUT_H_FOV}:v_fov=${OUT_V_FOV}:yaw=${L_YAW}:pitch=${L_PITCH}:roll=${L_ROLL}:output=hequirect[left]; \
[3:v]setpts=${PTS}*PTS,fps=${OUTPUT_FPS},scale=${SCALE_H_RES}x${SCALE_V_RES},format=gbrp[r_scaled]; \
[4:v]scale=${SCALE_H_RES}x${SCALE_V_RES}[r_na_scaled]; \
[r_scaled][r_na_scaled]blend=all_mode=divide,format=yuv420p[r_blended]; \
[5:v]scale=${SCALE_H_RES}x${SCALE_V_RES}[r_ba_scaled]; \
[r_blended][r_ba_scaled]overlay[r_over]; \
[r_over]scale=${SCALE_H_RES}x${SCALE_V_RES},pad=${H_RES}:${V_RES}:(ow-iw)/2:(oh-ih)/2,v360=input=fisheye:ih_fov=${IN_FOV}:iv_fov=${IN_FOV}:h_fov=${OUT_H_FOV}:v_fov=${OUT_V_FOV}:yaw=${R_YAW}:pitch=${R_PITCH}:roll=${R_ROLL}:output=hequirect[right]; \
[left][right]hstack=inputs=2[output]" \
-map "[output]" -an -vcodec libx264 -preset superfast -x264opts "frame-packing=3" \
-profile:v baseline -pix_fmt yuv420p ${OUTPUT_DIR}/${OUTPUT_PREFIX}-output.mp4

###
###
EOF

if [ ${CONCAT} -eq 0 ]
then

ffmpeg -y -v info \
-i ${LEFT_VIDEO} \
-loop 0 -i ${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_normalized_alpha.png \
-loop 0 -i ${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_border_alpha.png \
-i ${RIGHT_VIDEO} \
-loop 0 -i ${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_normalized_alpha.png \
-loop 0 -i ${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_border_alpha.png \
-filter_complex \
"[0:v]setpts=${PTS}*PTS,fps=${OUTPUT_FPS}[l_fps]; \
[l_fps]scale=${SCALE_H_RES}x${SCALE_V_RES},format=gbrp[l_scaled]; \
[1:v]scale=${SCALE_H_RES}x${SCALE_V_RES}[l_na_scaled]; \
[l_scaled][l_na_scaled]blend=all_mode=divide,format=yuv420p[l_blended]; \
[2:v]scale=${SCALE_H_RES}x${SCALE_V_RES}[l_ba_scaled]; \
[l_blended][l_ba_scaled]overlay[l_over]; \
[l_over]scale=${SCALE_H_RES}x${SCALE_V_RES},pad=${H_RES}:${V_RES}:(ow-iw)/2:(oh-ih)/2,v360=input=fisheye:ih_fov=${IN_FOV}:iv_fov=${IN_FOV}:h_fov=${OUT_H_FOV}:v_fov=${OUT_V_FOV}:yaw=${L_YAW}:pitch=${L_PITCH}:roll=${L_ROLL}:output=hequirect[left]; \
[3:v]setpts=${PTS}*PTS,fps=${OUTPUT_FPS}[r_fps]; \
[r_fps]scale=${SCALE_H_RES}x${SCALE_V_RES},format=gbrp[r_scaled]; \
[4:v]scale=${SCALE_H_RES}x${SCALE_V_RES}[r_na_scaled]; \
[r_scaled][r_na_scaled]blend=all_mode=divide,format=yuv420p[r_blended]; \
[5:v]scale=${SCALE_H_RES}x${SCALE_V_RES}[r_ba_scaled]; \
[r_blended][r_ba_scaled]overlay[r_over]; \
[r_over]scale=${SCALE_H_RES}x${SCALE_V_RES},pad=${H_RES}:${V_RES}:(ow-iw)/2:(oh-ih)/2,v360=input=fisheye:ih_fov=${IN_FOV}:iv_fov=${IN_FOV}:h_fov=${OUT_H_FOV}:v_fov=${OUT_V_FOV}:yaw=${R_YAW}:pitch=${R_PITCH}:roll=${R_ROLL}:output=hequirect[right]; \
[left][right]hstack=inputs=2[output]" \
-map "[output]" -an -vcodec libx264 -preset superfast -x264opts "frame-packing=3" \
-profile:v baseline -pix_fmt yuv420p ${OUTPUT_FILE}

else

ffmpeg -y -v info \
-f concat -safe 0 -i ${LEFT_VIDEO} \
-loop 0 -i ${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_normalized_alpha.png \
-loop 0 -i ${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_border_alpha.png \
-f concat -safe 0 -i ${RIGHT_VIDEO} \
-loop 0 -i ${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_normalized_alpha.png \
-loop 0 -i ${OUTPUT_DIR}/${OUTPUT_PREFIX}-left_border_alpha.png \
-filter_complex \
"[0:v]setpts=${PTS}*PTS,fps=${OUTPUT_FPS},scale=${SCALE_H_RES}x${SCALE_V_RES},format=gbrp[l_scaled]; \
[1:v]scale=${SCALE_H_RES}x${SCALE_V_RES}[l_na_scaled]; \
[l_scaled][l_na_scaled]blend=all_mode=divide,format=yuv420p[l_blended]; \
[2:v]scale=${SCALE_H_RES}x${SCALE_V_RES}[l_ba_scaled]; \
[l_blended][l_ba_scaled]overlay[l_over]; \
[l_over]scale=${SCALE_H_RES}x${SCALE_V_RES},pad=${H_RES}:${V_RES}:(ow-iw)/2:(oh-ih)/2,v360=input=fisheye:ih_fov=${IN_FOV}:iv_fov=${IN_FOV}:h_fov=${OUT_H_FOV}:v_fov=${OUT_V_FOV}:yaw=${L_YAW}:pitch=${L_PITCH}:roll=${L_ROLL}:output=hequirect[left]; \
[3:v]setpts=${PTS}*PTS,fps=${OUTPUT_FPS},scale=${SCALE_H_RES}x${SCALE_V_RES},format=gbrp[r_scaled]; \
[4:v]scale=${SCALE_H_RES}x${SCALE_V_RES}[r_na_scaled]; \
[r_scaled][r_na_scaled]blend=all_mode=divide,format=yuv420p[r_blended]; \
[5:v]scale=${SCALE_H_RES}x${SCALE_V_RES}[r_ba_scaled]; \
[r_blended][r_ba_scaled]overlay[r_over]; \
[r_over]scale=${SCALE_H_RES}x${SCALE_V_RES},pad=${H_RES}:${V_RES}:(ow-iw)/2:(oh-ih)/2,v360=input=fisheye:ih_fov=${IN_FOV}:iv_fov=${IN_FOV}:h_fov=${OUT_H_FOV}:v_fov=${OUT_V_FOV}:yaw=${R_YAW}:pitch=${R_PITCH}:roll=${R_ROLL}:output=hequirect[right]; \
[left][right]hstack=inputs=2[output]" \
-map "[output]" -an -vcodec libx264 -preset superfast -x264opts "frame-packing=3" \
-profile:v baseline -pix_fmt yuv420p ${OUTPUT_FILE}

fi


exit 0
