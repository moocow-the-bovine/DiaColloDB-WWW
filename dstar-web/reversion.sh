#!/bin/bash

## + requires perl-reversion from Perl::Version (debian package libperl-version-perl)
## + example call:
##    ./reversion.sh -bump -dryrun

pmfiles=(dstar.perl common.ttk)

exec perl-reversion "$@" "${pmfiles[@]}"


