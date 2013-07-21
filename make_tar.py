#!python

import os
import re

# ----------------------------------
# Definitions:
# ----------------------------------

# Script name
script_name = "CluelessPlus"
script_pack_name = script_name.replace(" ", "-")

# ----------------------------------


# Script:
version = -1
for line in open("version.nut"):

	r = re.search('SELF_VERSION\s+<-\s+([0-9]+)', line)
	if(r != None):
		version = r.group(1)

if(version == -1):
	print("Couldn't find " + script_name + " version in info.nut!")
	exit(-1)

dir_name = script_pack_name + "-v" + version
tar_name = dir_name + ".tar"
os.system("mkdir " + dir_name);
os.system("cp -Ra *.nut readme.txt changelog.txt license.txt " + dir_name);
os.system("tar -cf " + tar_name + " " + dir_name);
os.system("rm -r " + dir_name);
