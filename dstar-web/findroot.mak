##-*- Mode: GNUmakefile -*-
##
## File: config/common/findroot.mak
## Author: Bryan Jurish <jurish@bbaw.de>
## Usage:
##  + install this in a build directory using svn:externals and include it
## Description:
##  + dstar corpus administration tools: configuration: search for DSTAR_ROOT
##  + if DSTAR_ROOT is already set to a non-empty value, does nothing
##  + starts searching at the directory containing this file (DIR=$(abspath $(dir $(lastword $(MAKEFILE_LIST)))))
##  + if the current search directory $(DIR) contains the sentinel file .DSTAR_ROOT, sets the variable
##      DSTAR_ROOT := $(DIR)
##    and terminates
##  + otherwise, if $(DIR) contains a symlink DSTAR_ROOT, sets
##     DIR=$(shell readlink -f $(DIR)/DSTAR_ROOT)
##    and continues the search with the new DIR (symlink "hint")
##  + otherwise, if $(DIR) is not the filesystem root directory ("/"),
##    continues the search with DIR=`$(DIR)/..` ("relax" to parent directory)
##  + on completion, the variable DSTAR_ROOT should either an absolute path
##  + aborts with an error message if DSTAR_ROOT is unset and could not be found
##  + note that symlinks in DIR paths may not be handled as expected by the "relax" step;
##    - see https://stackoverflow.com/questions/8390502/how-to-make-gnu-make-stop-de-referencing-symbolic-links-to-directories

#$(info DEBUG: evaluating $(lastword $(MAKEFILE_LIST)))

ifeq ($(origin DSTAR_ROOT),undefined)

## $(call dstar_find_root_info,MESSAGE)
##   + tweak this definition to debug the dstar_find_root
define dstar_find_root_info
 $(if x,,$(info DEBUG: dstar_find_root: $(1)))
endef

DSTAR_ROOT_checked ?=

define dstar_find_root
 $(call dstar_find_root_info,checking $(1))
 DSTAR_ROOT_checked +=$(1:/=)/
 $(if $(wildcard $(1:/=)/.DSTAR_ROOT),\
      $(call dstar_find_root_info,-> found sentinel $(1:/=)/.DSTAR_ROOT)\
      DSTAR_ROOT := $(1:/=),\
      $(if $(wildcard $(1:/=)/DSTAR_ROOT),\
           $(call dstar_find_root_info, -> found symlink $(1:/=)/DSTAR_ROOT)\
	   $(call dstar_find_root,$(shell readlink -f $(1:/=)/DSTAR_ROOT)),\
           $(if $(1:/=),\
                $(call dstar_find_root_info,-> relaxing)\
                $(call dstar_find_root,$(dir $(1:/=))),\
		)))
endef

##-- auto-search
#$(eval $(call dstar_find_root,$(shell pwd)))
#$(eval $(call dstar_find_root,$(CURDIR)))
$(eval $(call dstar_find_root,$(abspath $(dir $(lastword $(MAKEFILE_LIST))))))

##-- sanity check(s)
ifeq ($(origin DSTAR_ROOT),undefined)
  $(warning WARNING: no .DSTAR_ROOT sentinel or DSTAR_ROOT symlink found!)
  $(foreach d,$(DSTAR_ROOT_checked),$(warning WARNING: checked directory: $(d)))
  $(error ERROR: could not determine DSTAR_ROOT)
endif

##-- cleanup
undefine DSTAR_ROOT_checked
undefine dstar_find_root_info
undefine dstar_find_root

endif

##-- always export DSTAR_ROOT
export DSTAR_ROOT
