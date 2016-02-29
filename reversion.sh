#!/bin/bash

## + requires perl-reversion from Perl::Version (debian package libperl-version-perl)
## + example call:
##    ./reversion.sh -bump -dryrun

pmfiles=(`find . -name '*.pm' -o -name '*.perl'`)

exec perl-reversion "$@" "${pmfiles[@]}"
