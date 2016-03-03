#!/bin/bash

## + requires perl-reversion from Perl::Version (debian package libperl-version-perl)
## + example call:
##    ./reversion.sh -bump -dryrun

pmfiles=(`find share lib *.perl -name '*.pm' -o -name '*.perl'`)

exec perl-reversion "$@" "${pmfiles[@]}"
